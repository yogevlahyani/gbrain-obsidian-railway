#!/bin/bash
set -euo pipefail

export GBRAIN_HOME="${GBRAIN_HOME:-/data/gbrain}"
BRAIN_DIR="${BRAIN_DIR:-/data/brain}"
SOURCE_ID="${GBRAIN_SOURCE_ID:-brain}"
PORT="${PORT:-3131}"

log() { printf '[gbrain-entrypoint] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require() {
  local name="$1"
  [ -n "${!name:-}" ] || die "$name is required"
}

require GBRAIN_DATABASE_URL
require GBRAIN_ADMIN_BOOTSTRAP_TOKEN
require BRAIN_REPO_URL
require GITHUB_TOKEN

# Custom pgvector on Railway private network has no TLS; GBrain defaults to requiring it
# for non-local hosts. Append sslmode=disable unless the URL already sets sslmode.
case "$GBRAIN_DATABASE_URL" in
  *sslmode=*) ;;
  *)
    case "$GBRAIN_DATABASE_URL" in
      *\?*) GBRAIN_DATABASE_URL="${GBRAIN_DATABASE_URL}&sslmode=disable" ;;
      *)    GBRAIN_DATABASE_URL="${GBRAIN_DATABASE_URL}?sslmode=disable" ;;
    esac
    export GBRAIN_DATABASE_URL
    log "appended sslmode=disable to GBRAIN_DATABASE_URL (private Postgres without TLS)"
    ;;
esac

export GIT_ASKPASS=/usr/local/bin/git-askpass.sh
export GIT_TERMINAL_PROMPT=0

GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-GBrain}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-gbrain@localhost}"
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

mkdir -p "$GBRAIN_HOME" "$BRAIN_DIR"

# Local compose uses file:// remotes; modern git blocks that transport by default.
case "$BRAIN_REPO_URL" in
  file://*)
    git config --system --add safe.directory '*'
    git config --system protocol.file.allow always
    ;;
esac

git_cfg() {
  git -C "$BRAIN_DIR" config --local "$@"
}

admin_state() {
  gbrain sources writer status "$SOURCE_ID" --json 2>/dev/null \
    | sed -n 's/.*"admin_state": *"\([^"]*\)".*/\1/p' | head -1
}

ensure_brain_checkout() {
  if [ -d "$BRAIN_DIR/.git" ]; then
    log "brain checkout exists at $BRAIN_DIR"
    git -C "$BRAIN_DIR" remote set-url origin "$BRAIN_REPO_URL"
  else
    log "cloning BRAIN_REPO_URL into $BRAIN_DIR"
    # Clone without embedding credentials in the URL.
    if ! GIT_ASKPASS="$GIT_ASKPASS" git clone "$BRAIN_REPO_URL" "$BRAIN_DIR"; then
      die "git clone failed"
    fi
  fi

  git_cfg user.name "$GIT_AUTHOR_NAME"
  git_cfg user.email "$GIT_AUTHOR_EMAIL"
  # Refuse silent history rewrites from a stray pull.
  git_cfg pull.ff only
  git_cfg rebase.autoStash false
  git_cfg merge.autoStash false
  case "$BRAIN_REPO_URL" in
    file://*) git_cfg protocol.file.allow always ;;
  esac

  # Empty remote (no commits / unborn branch): seed from starter-vault and push.
  if ! git -C "$BRAIN_DIR" rev-parse HEAD >/dev/null 2>&1; then
    log "remote is empty; seeding from /opt/starter-vault"
    # Copy seed files without clobbering an existing .git
    tar -C /opt/starter-vault -cf - . | tar -C "$BRAIN_DIR" -xf -
    git -C "$BRAIN_DIR" add -A
    git -C "$BRAIN_DIR" commit -m "seed: starter vault"
    GIT_ASKPASS="$GIT_ASKPASS" git -C "$BRAIN_DIR" push -u origin HEAD
  else
    GIT_ASKPASS="$GIT_ASKPASS" git -C "$BRAIN_DIR" fetch origin || true
  fi
}

ensure_gbrain_init() {
  if [ -f "$GBRAIN_HOME/config.json" ]; then
    log "GBRAIN_HOME already initialized"
    return
  fi

  log "initializing gbrain against Postgres"
  local init_args=(init --url "$GBRAIN_DATABASE_URL" --non-interactive)
  # Prefer embeddings when a documented provider key is present; otherwise keyword-only.
  if [ -n "${VOYAGE_API_KEY:-}" ] || [ -n "${OPENAI_API_KEY:-}" ]; then
    :
  else
    init_args+=(--no-embedding)
  fi
  gbrain "${init_args[@]}"
  gbrain apply-migrations --yes || true
}

source_registered() {
  gbrain sources list --json 2>/dev/null | grep -q "\"id\"[[:space:]]*:[[:space:]]*\"${SOURCE_ID}\""
}

ensure_source() {
  if source_registered; then
    log "source '${SOURCE_ID}' already registered"
  else
    log "registering source '${SOURCE_ID}' at $BRAIN_DIR"
    # Path must already be a git repo with at least one commit (docs/guides/multi-source-brains.md).
    gbrain sources add "$SOURCE_ID" --path "$BRAIN_DIR" --federated --name "Brain vault"
  fi

  # Managed brains (default on recent Postgres installs): Git push is an owner
  # setting via writer git-durability, not sources harden (which refuses managed
  # worktrees with writer_coordinator_required). See docs/guides/git-canonical.md
  # and `gbrain sources writer --help`.
  local state
  state="$(admin_state)"
  if [ -n "$state" ]; then
    log "enabling git durability for '${SOURCE_ID}'"
    local dur_args=(sources writer git-durability "$SOURCE_ID" --enable
      --admin-intent writer_git_durability --expected-state "$state")
    case "$BRAIN_REPO_URL" in
      https://*|http://*)
        local pat_file
        pat_file="$(mktemp)"
        printf '%s' "$GITHUB_TOKEN" >"$pat_file"
        chmod 600 "$pat_file"
        dur_args+=(--pat-file "$pat_file")
        gbrain "${dur_args[@]}" || log "git-durability returned non-zero; continuing"
        rm -f "$pat_file"
        ;;
      *)
        gbrain "${dur_args[@]}" || log "git-durability returned non-zero; continuing"
        ;;
    esac
  else
    # Classic (unmanaged) brain: harden installs commit/push hooks.
    log "writer not managed; falling back to sources harden"
    case "$BRAIN_REPO_URL" in
      https://*|http://*)
        local pat_file
        pat_file="$(mktemp)"
        printf '%s' "$GITHUB_TOKEN" >"$pat_file"
        chmod 600 "$pat_file"
        gbrain sources harden "$SOURCE_ID" --pat-file "$pat_file" --no-cron || \
          log "harden returned non-zero; continuing"
        rm -f "$pat_file"
        ;;
      *)
        gbrain sources harden "$SOURCE_ID" --no-cron --no-verify || \
          log "harden returned non-zero; continuing"
        ;;
    esac
  fi

  # Pin CWD association so unscoped CLI ops hit this source.
  (cd "$BRAIN_DIR" && gbrain sources attach "$SOURCE_ID" || true)
}

start_children() {
  # Railway private networking is IPv6; local compose should set GBRAIN_BIND=0.0.0.0.
  local bind="${GBRAIN_BIND:-::}"
  local serve_args=(serve --http --bind "$bind" --port "$PORT")
  # --public-url must be https (docs/mcp/DEPLOY.md); omit otherwise.
  if [ -n "${GBRAIN_PUBLIC_URL:-}" ]; then
    case "$GBRAIN_PUBLIC_URL" in
      https://*) serve_args+=(--public-url "$GBRAIN_PUBLIC_URL") ;;
      *) log "GBRAIN_PUBLIC_URL is not https; omitting --public-url" ;;
    esac
  fi

  log "starting gbrain serve on :$PORT"
  gbrain "${serve_args[@]}" &
  local serve_pid=$!

  log "starting gbrain autopilot for $BRAIN_DIR"
  # Foreground-style daemon: sync + extract + embed on an interval (docs: autopilot --help).
  gbrain autopilot --repo "$BRAIN_DIR" --interval "${GBRAIN_AUTOPILOT_INTERVAL:-120}" &
  local auto_pid=$!

  # If either child exits, tear down the other and exit so Railway restarts us.
  while kill -0 "$serve_pid" 2>/dev/null && kill -0 "$auto_pid" 2>/dev/null; do
    sleep 2
  done

  log "a child exited; shutting down"
  kill "$serve_pid" "$auto_pid" 2>/dev/null || true
  wait "$serve_pid" 2>/dev/null || true
  wait "$auto_pid" 2>/dev/null || true
  exit 1
}

ensure_brain_checkout
ensure_gbrain_init
ensure_source
start_children

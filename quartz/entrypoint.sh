#!/usr/bin/env bash
# Clone/pull the brain git vault, build Quartz, serve public/ on $PORT.
set -euo pipefail

log() { echo "[quartz] $*"; }

: "${PORT:=8080}"
: "${QUARTZ_REBUILD_INTERVAL:=120}"
: "${QUARTZ_GIT_REF:=v5}"
DATA="${QUARTZ_DATA:-/data}"
VAULT="${DATA}/vault"
QUARTZ_DIR="${DATA}/quartz"
export GIT_ASKPASS=/usr/local/bin/git-askpass.sh
export GIT_TERMINAL_PROMPT=0

if [ -z "${BRAIN_REPO_URL:-}" ]; then
  log "ERROR: BRAIN_REPO_URL is required"
  exit 1
fi

# file:// remotes (local compose) don't need a token.
case "${BRAIN_REPO_URL}" in
  file://*)
    git config --system protocol.file.allow always || true
    ;;
  *)
    if [ -z "${GITHUB_TOKEN:-}" ]; then
      log "ERROR: GITHUB_TOKEN is required for HTTPS remotes"
      exit 1
    fi
    ;;
esac

sync_vault() {
  if [ ! -d "${VAULT}/.git" ]; then
    log "cloning ${BRAIN_REPO_URL} -> ${VAULT}"
    rm -rf "${VAULT}"
    mkdir -p "$(dirname "$VAULT")"
    git clone --depth 1 "${BRAIN_REPO_URL}" "${VAULT}"
  else
    log "pulling vault"
    git -C "${VAULT}" remote set-url origin "${BRAIN_REPO_URL}" || true
    git -C "${VAULT}" fetch --depth 1 origin
    # Prefer origin/main, then origin/master, then whatever HEAD is.
    branch="$(git -C "${VAULT}" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
      if git -C "${VAULT}" rev-parse --verify origin/main >/dev/null 2>&1; then
        branch=main
      elif git -C "${VAULT}" rev-parse --verify origin/master >/dev/null 2>&1; then
        branch=master
      else
        branch="$(git -C "${VAULT}" branch -r | awk -F/ '/origin\//{print $2; exit}')"
      fi
    fi
    git -C "${VAULT}" checkout -B "$branch" "origin/${branch}"
  fi
}

ensure_quartz() {
  if [ ! -f "${QUARTZ_DIR}/package.json" ]; then
    log "cloning Quartz ${QUARTZ_GIT_REF}"
    rm -rf "${QUARTZ_DIR}"
    git clone --depth 1 --branch "${QUARTZ_GIT_REF}" https://github.com/jackyzha0/quartz.git "${QUARTZ_DIR}"
    (cd "${QUARTZ_DIR}" && npm ci)
  fi
}

sync_content() {
  mkdir -p "${QUARTZ_DIR}/content"
  # Replace content/ with vault markdown (keep quartz's own non-content bits).
  find "${QUARTZ_DIR}/content" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  # Copy vault files; skip VCS / Obsidian metadata (not published).
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude '.git/' \
      --exclude '.obsidian/' \
      --exclude '.trash/' \
      "${VAULT}/" "${QUARTZ_DIR}/content/"
  else
    tar -C "${VAULT}" \
      --exclude='.git' --exclude='.obsidian' --exclude='.trash' \
      -cf - . | tar -C "${QUARTZ_DIR}/content" -xf -
  fi
}

set_base_url() {
  # Quartz v5: quartz.config.ts or .yaml — patch baseUrl when QUARTZ_BASE_URL / PUBLIC_URL set.
  local base="${QUARTZ_BASE_URL:-${GBRAIN_PUBLIC_URL:-}}"
  base="${base#https://}"
  base="${base#http://}"
  base="${base%/}"
  [ -n "$base" ] || return 0
  local cfg
  for cfg in "${QUARTZ_DIR}/quartz.config.ts" "${QUARTZ_DIR}/quartz.config.yaml" "${QUARTZ_DIR}/quartz.config.yml"; do
    [ -f "$cfg" ] || continue
    if grep -q 'baseUrl' "$cfg"; then
      # Replace existing baseUrl string value.
      sed -i -E "s|(baseUrl[[:space:]]*[:=][[:space:]]*[\"'])[^\"']*([\"'])|\1${base}\2|" "$cfg" || true
      log "baseUrl -> ${base} (${cfg##*/})"
      return 0
    fi
  done
}

build_site() {
  sync_vault
  ensure_quartz
  sync_content
  set_base_url
  log "building"
  (
    cd "${QUARTZ_DIR}"
    npx quartz plugin install 2>/dev/null || true
    npx quartz build
  )
  log "build ok -> ${QUARTZ_DIR}/public"
}

mkdir -p "$DATA"
build_site

# Serve + periodic rebuild. Caddy stays in foreground via wait.
export PORT
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
caddy_pid=$!

while true; do
  sleep "${QUARTZ_REBUILD_INTERVAL}"
  if ! build_site; then
    log "rebuild failed; keeping previous public/"
  fi
done &

wait "$caddy_pid"

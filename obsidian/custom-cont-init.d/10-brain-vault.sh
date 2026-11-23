#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# Idempotent first-boot: clone brain repo, install Obsidian Git plugin, register vault.
set -euo pipefail

log() { echo "[brain-vault] $*"; }

: "${PUID:=1000}"
: "${PGID:=1000}"
VAULT="${BRAIN_VAULT_PATH:-/config/vault}"
PLUGIN_DIR="${VAULT}/.obsidian/plugins/obsidian-git"
OBSIDIAN_CFG="/config/.config/obsidian"

if [ -z "${BRAIN_REPO_URL:-}" ] || [ -z "${GITHUB_TOKEN:-}" ]; then
  log "BRAIN_REPO_URL or GITHUB_TOKEN unset; skipping vault setup"
  exit 0
fi

export GIT_ASKPASS=/usr/local/bin/git-askpass.sh
export GIT_TERMINAL_PROMPT=0
GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Obsidian}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-obsidian@localhost}"

case "${BRAIN_REPO_URL}" in
  file://*)
    git config --system protocol.file.allow always || true
    git config --system --add safe.directory '*' || true
    ;;
esac

# --- clone vault if missing ---
if [ ! -d "${VAULT}/.git" ]; then
  log "cloning ${BRAIN_REPO_URL} -> ${VAULT}"
  mkdir -p "$(dirname "$VAULT")"
  # Retry a few times: gbrain may still be seeding an empty remote.
  ok=0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if GIT_ASKPASS="$GIT_ASKPASS" git clone "$BRAIN_REPO_URL" "$VAULT"; then
      ok=1
      break
    fi
    log "clone attempt $i failed; waiting for remote seed"
    rm -rf "$VAULT"
    sleep 6
  done
  [ "$ok" = 1 ] || { log "ERROR: could not clone brain repo"; exit 1; }
else
  log "vault already present at ${VAULT}"
  git -C "$VAULT" remote set-url origin "$BRAIN_REPO_URL" || true
fi

git -C "$VAULT" config --local user.name "$GIT_AUTHOR_NAME"
git -C "$VAULT" config --local user.email "$GIT_AUTHOR_EMAIL"
git -C "$VAULT" config --local pull.ff only

# --- Obsidian Git community plugin ---
if [ ! -f "${PLUGIN_DIR}/main.js" ]; then
  log "installing obsidian-git plugin"
  mkdir -p "$PLUGIN_DIR"
  # Latest release assets (main.js, manifest.json, styles.css).
  REL_API="https://api.github.com/repos/Vinzent03/obsidian-git/releases/latest"
  TAG="$(curl -fsSL "$REL_API" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$TAG" ] || TAG="2.44.0"
  BASE="https://github.com/Vinzent03/obsidian-git/releases/download/${TAG}"
  curl -fsSL -o "${PLUGIN_DIR}/main.js" "${BASE}/main.js"
  curl -fsSL -o "${PLUGIN_DIR}/manifest.json" "${BASE}/manifest.json"
  curl -fsSL -o "${PLUGIN_DIR}/styles.css" "${BASE}/styles.css" || true
fi

mkdir -p "${VAULT}/.obsidian"

# Enable the plugin in the vault (Restricted Mode still needs a one-time UI click).
if [ ! -f "${VAULT}/.obsidian/community-plugins.json" ]; then
  printf '%s\n' '["obsidian-git"]' >"${VAULT}/.obsidian/community-plugins.json"
fi

# Plugin settings: pull on boot, pull every 2 min, commit+push every 2 min.
if [ ! -f "${PLUGIN_DIR}/data.json" ]; then
  cat >"${PLUGIN_DIR}/data.json" <<'EOF'
{
  "commitMessage": "obsidian: vault backup {{date}}",
  "autoCommitMessage": "obsidian: vault backup {{date}}",
  "autoSaveInterval": 2,
  "autoPushInterval": 2,
  "autoPullInterval": 2,
  "autoPullOnBoot": true,
  "disablePush": false,
  "pullBeforePush": true,
  "syncMethod": "merge",
  "autoBackupAfterFileChange": false,
  "differentIntervalCommitAndPush": false
}
EOF
fi

# Register vault so Obsidian opens it (best-effort; Electron may still prompt once).
mkdir -p "$OBSIDIAN_CFG"
VAULT_ID="brainvault"
if [ ! -f "${OBSIDIAN_CFG}/obsidian.json" ]; then
  TS="$(date +%s)000"
  cat >"${OBSIDIAN_CFG}/obsidian.json" <<EOF
{
  "vaults": {
    "${VAULT_ID}": {
      "path": "${VAULT}",
      "ts": ${TS},
      "open": true
    }
  }
}
EOF
fi

# Ownership for the linuxserver abc user.
chown -R "${PUID}:${PGID}" "$VAULT" "$OBSIDIAN_CFG" || true

log "vault ready at ${VAULT}"

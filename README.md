# Deploy and Host GBrain + Obsidian on Railway

Self-hosted [GBrain](https://github.com/garrytan/gbrain) memory server with a browser-streamed Obsidian vault. Four services; markdown lives in a **private GitHub repo** that both sides sync through git (Railway volumes are not shareable, and containers are unprivileged).

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/gbrain-obsidian)

```
Claude / agents ──► Caddy ──► GBrain (Postgres + pgvector)
                     │
                     └──► Obsidian (linuxserver stream)
                              ▲
                     private GitHub brain repo
```

Agent writes → GBrain commits/pushes → Obsidian Git plugin pulls.  
Obsidian edits → plugin commits/pushes → GBrain autopilot pulls and re-indexes.  
Conflicting pushes are parked by GBrain, never force-pushed.

## About Hosting GBrain + Obsidian

This template runs GBrain (HTTP + MCP), Obsidian (browser stream), Caddy (public edge), and Postgres with pgvector. The vault is not stored only on Railway volumes: both GBrain and Obsidian sync a private GitHub repo over HTTPS so edits stay durable and shared.

## Why Deploy GBrain + Obsidian on Railway

Railway gives you private networking between the four services, volumes for Postgres/GBrain/Obsidian state, and a one-click public domain on Caddy. You keep the brain in your own GitHub repo and PAT; no shared volume or privileged containers are required.

## Common Use Cases

- Personal or team second brain with Claude / MCP agents writing into markdown
- Browser Obsidian for editing the same vault without a desktop sync dance
- Self-hosted memory for agents with keyword or embedding search (optional Voyage/OpenAI keys)

## Dependencies for GBrain + Obsidian

### Deployment Dependencies

1. An **empty private GitHub repo** for the vault (e.g. `my-brain`).
2. A **fine-grained GitHub PAT** with **Contents: Read and write** on that repo only.
3. A Railway account.

After deploy, set `BRAIN_REPO_URL` and `GITHUB_TOKEN` on **gbrain** (Obsidian references the same). Optional: `GBRAIN_PUBLIC_URL` for OAuth/MCP — Railway’s caddy `*.up.railway.app` URL works until you add a custom domain.

### Service variables

**postgres**

| Variable | Value |
|---|---|
| `PGDATA` | `/var/lib/postgresql/data/pgdata` |
| `POSTGRES_PASSWORD` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` |

**gbrain** (volume at `/data`, no public domain)

| Variable | Value |
|---|---|
| `GBRAIN_DATABASE_URL` | `${{postgres.DATABASE_URL}}` (template URL includes `?sslmode=disable` for private pgvector) |
| `GBRAIN_ADMIN_BOOTSTRAP_TOKEN` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")}}` |
| `GBRAIN_HTTP_TRUST_PROXY` | `1` |
| `GBRAIN_PUBLIC_URL` | optional; `https://…` for OAuth/MCP (Railway caddy URL is fine) |
| `BRAIN_REPO_URL` | `https://github.com/<you>/<brain>.git` |
| `GITHUB_TOKEN` | fine-grained PAT |
| `GIT_AUTHOR_NAME` | `GBrain` |
| `GIT_AUTHOR_EMAIL` | `gbrain@users.noreply.github.com` |
| `PORT` | `3131` |
| `VOYAGE_API_KEY` / `OPENAI_API_KEY` | optional; embeddings stay keyword-only without one |

**obsidian** (volume at `/config`, no public domain, ≥1 GB RAM)

| Variable | Value |
|---|---|
| `PUID` / `PGID` | `1000` |
| `TZ` | your timezone |
| `CUSTOM_USER` / `PASSWORD` | stream login |
| `SUBFOLDER` | `/obsidian/` |
| `BRAIN_REPO_URL` | same as gbrain |
| `GITHUB_TOKEN` | same PAT |
| `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` | e.g. `Obsidian` / your email |

**caddy** (the only public service)

| Variable | Value |
|---|---|
| `PORT` | Railway-injected |
| `ORIGIN_SECRET` | `${{secret(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` |
| `OBSIDIAN_UPSTREAM` | `${{obsidian.RAILWAY_PRIVATE_DOMAIN}}:3000` |
| `GBRAIN_UPSTREAM` | `${{gbrain.RAILWAY_PRIVATE_DOMAIN}}:3131` |

Healthcheck: only gbrain exposes `/health` (via caddy with the secret header). Do not put a Railway healthcheck on caddy — it will not send `X-Origin-Secret`.

## Cloudflare

1. Proxied DNS CNAME/A to the **caddy** service’s Railway domain.
2. Transform Rule: add request header `X-Origin-Secret` = your `ORIGIN_SECRET`.
3. WAF allowlist: your VPN IP for the UI; **exempt** `/mcp`, `/authorize`, `/token`, `/register`, `/revoke`, and `/.well-known/` so Claude’s cloud connectors can reach OAuth + MCP.
4. Once the custom domain works, remove the Railway-generated public domain from caddy.

## Connect Claude

Custom connector URL: `https://<domain>/mcp`  
Log into `/admin` with the bootstrap token to manage OAuth clients.

## First open of Obsidian

1. Open `https://<domain>/obsidian/`, sign in with `CUSTOM_USER` / `PASSWORD`.
2. If the vault is not already open, open `/config/vault`.
3. **Restricted Mode** cannot be turned off from config files (Obsidian stores it in app localStorage). One-time: Settings → Community plugins → Turn on community plugins. The Git plugin is already installed and configured for 2-minute pull / commit-and-push.

## Moving an existing GBrain

On a machine with your old brain:

```bash
# Write pages out as markdown into a checkout of the brain repo, then push.
gbrain export --out /path/to/brain-checkout
# or a full sync into a registered source path — see GBrain docs for your version.
git -C /path/to/brain-checkout add -A && git commit -m "import existing brain" && git push
```

After push, the Railway gbrain autopilot pulls and indexes; Obsidian picks up the same files on its next pull.

## Local test

```bash
cd gbrain-obsidian-railway
docker compose build
docker compose up -d
./scripts/smoke-test.sh   # hits http://127.0.0.1:18080
```

Local compose uses a bare git repo on a shared volume (`file:///repos/brain.git`) instead of GitHub, sets `GBRAIN_GIT_ALLOW_FILE_TRANSPORT=1`, and uses `sslmode=disable` on Postgres. Production always uses the private GitHub remote over HTTPS and Railway’s TLS Postgres URL. On Apple Silicon, the gbrain service runs under `platform: linux/amd64` because releases ship `gbrain-linux-x64` only.

## Known limits

- Obsidian edits reach GBrain on the next autopilot/sync cycle (about 1–2 minutes here), not instantly.
- Streamed Obsidian wants **≥ 1 GB RAM** and `shm_size` ~1 GB.
- GBrain skips hidden paths (including `.obsidian/`) by design — no extra ignore config needed.
- `--public-url` must be `https://…` (GBrain refuses bare `http://`); local compose omits it.

## Docs vs this template

Where GBrain’s docs differed from earlier assumptions:

- Durability: register with `gbrain sources add … --path`, then on managed Postgres brains enable push with `gbrain sources writer git-durability … --enable` (harden refuses managed worktrees). Autopilot owns pull+reindex (`gbrain autopilot --repo …`). `host-repo` is not used — it creates a new bare repo under a path, which is the wrong shape for an existing GitHub vault.
- Hidden folders are already excluded from sync; `.obsidian/` is not indexed.
- Admin bootstrap on headless hosts must be set via `GBRAIN_ADMIN_BOOTSTRAP_TOKEN` (tokens are not printed to non-TTY logs).

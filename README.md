# Deploy and Host GBrain + Quartz on Railway

Self-hosted [GBrain](https://github.com/garrytan/gbrain) memory server with a [Quartz](https://quartz.jzhao.xyz/) site for your markdown vault. Four services; markdown lives in a **private GitHub repo** (edit with Obsidian on your computer/phone; agents write through GBrain). Railway volumes are not shareable across services, and containers stay unprivileged.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/gbrain-obsidian)

```
Claude / agents ──► Caddy ──► GBrain (Postgres + pgvector)
                     │
                     └──► Quartz (static site from the vault)
                              ▲
                     private GitHub brain repo
                              ▲
              Obsidian (desktop / mobile) via git
```

Agent writes → GBrain commits/pushes → Quartz rebuilds and GBrain re-indexes.  
You edit in Obsidian locally → push to the same repo → Quartz + GBrain pick it up.  
Conflicting pushes are parked by GBrain, never force-pushed.

## About Hosting GBrain + Quartz

This template runs GBrain (HTTP + MCP), Quartz (published vault), Caddy (public edge), and Postgres with pgvector. The vault is not stored only on Railway volumes: GBrain and Quartz sync a private GitHub repo over HTTPS so edits stay durable. Use Obsidian (or any markdown editor) on your devices against that same repo.

## Why Deploy GBrain + Quartz on Railway

Railway gives you private networking between the four services, volumes for Postgres/GBrain/Quartz state, and a one-click public domain on Caddy. You keep the brain in your own GitHub repo and PAT.

## Common Use Cases

- Personal or team second brain with Claude / MCP agents writing into markdown
- A readable web site of the vault (Quartz) without streaming a desktop app
- Self-hosted memory for agents with keyword or embedding search (optional Voyage/OpenAI keys)

## Dependencies for GBrain + Quartz

### Deployment Dependencies

1. An **empty private GitHub repo** for the vault (e.g. `my-brain`), or an existing Obsidian vault repo.
2. A **fine-grained GitHub PAT** with **Contents: Read and write** on that repo only.
3. A Railway account.

After deploy, set `BRAIN_REPO_URL` and `GITHUB_TOKEN` on **gbrain** and **quartz**. Optional: `GBRAIN_PUBLIC_URL` for OAuth/MCP — Railway’s caddy `*.up.railway.app` URL works until you add a custom domain.

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

**quartz** (volume at `/data`, no public domain)

| Variable | Value |
|---|---|
| `BRAIN_REPO_URL` | same as gbrain |
| `GITHUB_TOKEN` | same PAT |
| `QUARTZ_BASE_URL` | `${{caddy.RAILWAY_PUBLIC_DOMAIN}}/notes` (or `your.domain/notes`) |
| `QUARTZ_REBUILD_INTERVAL` | `120` (seconds between git pull + rebuild) |
| `PORT` | `8080` |

**caddy** (the only public service)

| Variable | Value |
|---|---|
| `PORT` | Railway-injected |
| `ORIGIN_SECRET` | optional. Empty = Railway URL works in a browser. Set only when Cloudflare (or similar) injects `X-Origin-Secret` |
| `QUARTZ_UPSTREAM` | `${{quartz.RAILWAY_PRIVATE_DOMAIN}}:8080` |
| `GBRAIN_UPSTREAM` | `${{gbrain.RAILWAY_PRIVATE_DOMAIN}}:3131` |

Only **caddy** should have a public domain. GBrain/Quartz stay private.

Paths: `/` and `/notes/` → Quartz site; `/admin`, `/mcp`, `/health` → GBrain.

## Cloudflare (optional)

Leave `ORIGIN_SECRET` empty until Cloudflare is in front — otherwise the Railway `*.up.railway.app` URL returns 403 in a normal browser.

1. Proxied DNS CNAME/A to the **caddy** service’s Railway domain.
2. Set `ORIGIN_SECRET` on caddy, then Transform Rule: add request header `X-Origin-Secret` = that value.
3. WAF allowlist: your VPN IP for the UI; **exempt** `/mcp`, `/authorize`, `/token`, `/register`, `/revoke`, and `/.well-known/` so Claude’s cloud connectors can reach OAuth + MCP.
4. Once the custom domain works, remove the Railway-generated public domain from caddy.

## Connect Claude

Custom connector URL: `https://<domain>/mcp`  
Log into `/admin` with the bootstrap token to manage OAuth clients.

## Editing with Obsidian (your devices)

Point Obsidian (desktop/mobile) at the same private GitHub vault (Obsidian Git plugin, or clone + push). Quartz rebuilds on its interval after you push; GBrain autopilot re-indexes the same commits.

## Moving an existing GBrain

On a machine with your old brain:

```bash
# Write pages out as markdown into a checkout of the brain repo, then push.
gbrain export --out /path/to/brain-checkout
# or a full sync into a registered source path — see GBrain docs for your version.
git -C /path/to/brain-checkout add -A && git commit -m "import existing brain" && git push
```

After push, Railway gbrain autopilot pulls and indexes; Quartz rebuilds on the next interval.

## Local test

```bash
cd gbrain-obsidian-railway
docker compose build
docker compose up -d
./scripts/smoke-test.sh   # hits http://127.0.0.1:18080
```

Local compose uses a bare git repo on a shared volume (`file:///repos/brain.git`) instead of GitHub, sets `GBRAIN_GIT_ALLOW_FILE_TRANSPORT=1`, and uses `sslmode=disable` on Postgres. Production always uses the private GitHub remote over HTTPS and Railway’s TLS Postgres URL. On Apple Silicon, the gbrain service runs under `platform: linux/amd64` because releases ship `gbrain-linux-x64` only.

## Known limits

- Vault edits reach Quartz/GBrain on the next rebuild/autopilot cycle (about 1–2 minutes here), not instantly.
- GBrain skips hidden paths (including `.obsidian/`) by design — no extra ignore config needed.
- `--public-url` must be `https://…` (GBrain refuses bare `http://`); local compose omits it.

## Docs vs this template

Where GBrain’s docs differed from earlier assumptions:

- Durability: register with `gbrain sources add … --path`, then on managed Postgres brains enable push with `gbrain sources writer git-durability … --enable` (harden refuses managed worktrees). Autopilot owns pull+reindex (`gbrain autopilot --repo …`). `host-repo` is not used — it creates a new bare repo under a path, which is the wrong shape for an existing GitHub vault.
- Hidden folders are already excluded from sync; `.obsidian/` is not indexed.
- Admin bootstrap on headless hosts must be set via `GBRAIN_ADMIN_BOOTSTRAP_TOKEN` (tokens are not printed to non-TTY logs).

# Deploy and Host GBrain + Quartz on Railway

Self-hosted [GBrain](https://github.com/garrytan/gbrain) memory server with a [Quartz](https://quartz.jzhao.xyz/) site for your markdown vault. Edit in Obsidian (or anything) on your devices; both GBrain and Quartz sync the same **private GitHub repo**.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/gbrain-obsidian)

```
Devices (Obsidian) ──git──► private GitHub brain repo
                                ▲              │
Claude / agents ──► Caddy ──► GBrain ◄─────────┘
                     │
                     └──► Quartz (static site from the vault)
```

Agent writes → GBrain commits/pushes → Quartz rebuilds on its pull interval.  
Local Obsidian edits → you push → GBrain autopilot re-indexes; Quartz republishes.

## About Hosting GBrain + Quartz

This template runs GBrain (HTTP + MCP), Quartz (published vault), Caddy (public edge), and Postgres with pgvector. The vault is not stored only on Railway volumes: GBrain and Quartz each sync a private GitHub repo over HTTPS.

## Why Deploy GBrain + Quartz on Railway

Railway gives you private networking between the services, volumes for Postgres/GBrain/Quartz state, and a one-click public domain on Caddy. Keep editing in Obsidian on desktop/phone; the Railway stack is search/MCP + a public Quartz site.

## Common Use Cases

- Personal or team second brain with Claude / MCP agents writing into markdown
- Public or private Quartz site generated from the same git vault
- Self-hosted memory for agents with keyword or embedding search (optional Voyage/OpenAI keys)

## Dependencies for GBrain + Quartz

### Deployment Dependencies

1. An **empty private GitHub repo** for the vault (e.g. `my-brain`).
2. A **fine-grained GitHub PAT** with **Contents: Read and write** on that repo only.
3. A Railway account.

After deploy, set `BRAIN_REPO_URL` and `GITHUB_TOKEN` on **gbrain** and **quartz**. Optional: `GBRAIN_PUBLIC_URL` / `QUARTZ_BASE_URL` for OAuth/MCP and Quartz `baseUrl` — Railway’s caddy `*.up.railway.app` URL works until you add a custom domain.

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
| `GITHUB_TOKEN` | same PAT (Contents: Read is enough for Quartz) |
| `PORT` | `8080` |
| `QUARTZ_REBUILD_INTERVAL` | seconds between pull+rebuild (default `120`) |
| `QUARTZ_BASE_URL` | optional host for Quartz `baseUrl` (e.g. `notes.example.com`) |
| `QUARTZ_GIT_REF` | Quartz git ref (default `v5`) |

**caddy** (the only public service)

| Variable | Value |
|---|---|
| `PORT` | Railway-injected |
| `ORIGIN_SECRET` | optional. Empty = Railway URL works in a browser. Set only when Cloudflare (or similar) injects `X-Origin-Secret` |
| `QUARTZ_UPSTREAM` | `${{quartz.RAILWAY_PRIVATE_DOMAIN}}:8080` |
| `GBRAIN_UPSTREAM` | `${{gbrain.RAILWAY_PRIVATE_DOMAIN}}:3131` |

Only **caddy** should have a public domain. GBrain/Quartz stay private.

Public routes: `/` → Quartz site. `/admin`, `/mcp`, `/health`, OAuth paths → GBrain.

## Cloudflare (optional)

Leave `ORIGIN_SECRET` empty until Cloudflare is in front — otherwise the Railway `*.up.railway.app` URL returns 403 in a normal browser.

1. Proxied DNS CNAME/A to the **caddy** service’s Railway domain.
2. Set `ORIGIN_SECRET` on caddy, then Transform Rule: add request header `X-Origin-Secret` = that value.
3. WAF allowlist: your VPN IP for the UI; **exempt** `/mcp`, `/authorize`, `/token`, `/register`, `/revoke`, and `/.well-known/` so Claude’s cloud connectors can reach OAuth + MCP.
4. Once the custom domain works, remove the Railway-generated public domain from caddy.

## Connect Claude

Custom connector URL: `https://<domain>/mcp`  
Log into `/admin` with the bootstrap token to manage OAuth clients.

## Local Obsidian

Use Obsidian on your computer/phone against the same GitHub vault (Obsidian Git plugin or `git` CLI). Railway does not stream Obsidian — Quartz only publishes the markdown.

## Moving an existing GBrain

On a machine with your old brain:

```bash
# Write pages out as markdown into a checkout of the brain repo, then push.
gbrain export --out /path/to/brain-checkout
git -C /path/to/brain-checkout add -A && git commit -m "import existing brain" && git push
```

After push, Railway gbrain autopilot pulls and indexes; Quartz rebuilds on its next interval.

## Local test

```bash
cd gbrain-obsidian-railway
docker compose build
docker compose up -d
./scripts/smoke-test.sh   # hits http://127.0.0.1:18080
```

Local compose uses a bare git repo on a shared volume (`file:///repos/brain.git`) instead of GitHub, sets `GBRAIN_GIT_ALLOW_FILE_TRANSPORT=1`, and uses `sslmode=disable` on Postgres. Production always uses the private GitHub remote over HTTPS. On Apple Silicon, the gbrain service runs under `platform: linux/amd64` because releases ship `gbrain-linux-x64` only.

## Known limits

- Quartz picks up vault changes on `QUARTZ_REBUILD_INTERVAL` (default ~2 minutes), not instantly.
- GBrain skips hidden paths (including `.obsidian/`) by design — Quartz also excludes `.obsidian/` when copying content.
- `--public-url` must be `https://…` (GBrain refuses bare `http://`); local compose omits it.

## Docs vs this template

Where GBrain’s docs differed from earlier assumptions:

- Durability: register with `gbrain sources add … --path`, then on managed Postgres brains enable push with `gbrain sources writer git-durability … --enable` (harden refuses managed worktrees). Autopilot owns pull+reindex (`gbrain autopilot --repo …`). `host-repo` is not used — it creates a new bare repo under a path, which is the wrong shape for an existing GitHub vault.
- Hidden folders are already excluded from sync; `.obsidian/` is not indexed.
- Admin bootstrap on headless hosts must be set via `GBRAIN_ADMIN_BOOTSTRAP_TOKEN` (tokens are not printed to non-TTY logs).

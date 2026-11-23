# Deploy and Host GBrain + Obsidian on Railway

Self-hosted [GBrain](https://github.com/garrytan/gbrain) memory server backed by a **private GitHub markdown vault**. Edit the vault with **Obsidian on your desktop/phone** (Obsidian Git or any git client). Agents write through GBrain. Three services on Railway; no browser Obsidian, no Quartz.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/gbrain-obsidian)

```
Claude / agents ──► Caddy ──► GBrain (Postgres + pgvector)
                              ▲
                     private GitHub brain repo
                              ▲
              Obsidian (desktop / mobile) via git
```

Agent writes → GBrain commits/pushes → autopilot re-indexes.  
You edit in Obsidian locally → push to the same repo → GBrain picks it up.  
Conflicting pushes are parked by GBrain, never force-pushed.

## About Hosting GBrain + Obsidian

This template runs GBrain (HTTP + MCP), Caddy (public edge), and Postgres with pgvector. The vault is not stored only on Railway volumes: GBrain syncs a private GitHub repo over HTTPS so edits stay durable. Use Obsidian (or any markdown editor) on your devices against that same repo.

## Why Deploy GBrain + Obsidian on Railway

Railway gives you private networking between the three services, volumes for Postgres/GBrain state, and a one-click public domain on Caddy. You keep the brain in your own GitHub repo and PAT. Obsidian stays on your devices — no VNC desktop in the cloud.

## Common Use Cases

- Personal or team second brain with Claude / MCP agents writing into markdown
- Self-hosted memory for agents with keyword or embedding search (optional Voyage/OpenAI keys)
- Obsidian as the local editor; GitHub as the source of truth

## Dependencies for GBrain + Obsidian

### Deployment Dependencies

1. An **empty private GitHub repo** for the vault (e.g. `my-brain`), or an existing Obsidian vault repo.
2. A **fine-grained GitHub PAT** with **Contents: Read and write** on that repo only.
3. A Railway account.

After deploy, set `BRAIN_REPO_URL` and `GITHUB_TOKEN` on **gbrain**. `GBRAIN_PUBLIC_URL` defaults to `https://${{caddy.RAILWAY_PUBLIC_DOMAIN}}`; override when you put a custom domain on caddy.

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
| `GBRAIN_PUBLIC_URL` | `https://${{caddy.RAILWAY_PUBLIC_DOMAIN}}` (override for a custom domain) |
| `BRAIN_REPO_URL` | `https://github.com/<you>/<brain>.git` |
| `GITHUB_TOKEN` | fine-grained PAT |
| `GIT_AUTHOR_NAME` | `GBrain` |
| `GIT_AUTHOR_EMAIL` | `gbrain@users.noreply.github.com` |
| `PORT` | `3131` |
| `VOYAGE_API_KEY` / `OPENAI_API_KEY` | optional; embeddings stay keyword-only without one |

**caddy** (the only public service)

| Variable | Value |
|---|---|
| `PORT` | Railway-injected |
| `ORIGIN_SECRET` | optional. Empty = Railway URL works in a browser. Set only when Cloudflare (or similar) injects `X-Origin-Secret` |
| `GBRAIN_UPSTREAM` | `${{gbrain.RAILWAY_PRIVATE_DOMAIN}}:3131` |

Only **caddy** should have a public domain. GBrain stays private.

Paths: `/admin`, `/mcp`, `/health`, OAuth → GBrain.

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

Point Obsidian (desktop/mobile) at the same private GitHub vault (Obsidian Git plugin, or clone + push). GBrain autopilot re-indexes after you push.

## Moving an existing GBrain

On a machine with your old brain:

```bash
# Write pages out as markdown into a checkout of the brain repo, then push.
gbrain export --out /path/to/brain-checkout
# or a full sync into a registered source path — see GBrain docs for your version.
git -C /path/to/brain-checkout add -A && git commit -m "import existing brain" && git push
```

After push, Railway gbrain autopilot pulls and indexes.

## Local smoke test

```bash
docker compose up -d --build
./scripts/smoke-test.sh
```

Local compose uses a bare git repo on a shared volume (`file:///repos/brain.git`) instead of GitHub, sets `GBRAIN_GIT_ALLOW_FILE_TRANSPORT=1`, and uses `sslmode=disable` on Postgres. Production always uses the private GitHub remote over HTTPS and Railway’s TLS Postgres URL. On Apple Silicon, the gbrain service runs under `platform: linux/amd64` because releases ship `gbrain-linux-x64` only.

Notes:

- `--public-url` must be `https://…` (GBrain refuses bare `http://`); local compose omits it.
- Vault edits reach GBrain on the next autopilot cycle (about 1–2 minutes here), not instantly.

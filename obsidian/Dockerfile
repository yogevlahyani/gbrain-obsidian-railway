# ghcr.io: lscr.io rate-limits Railway builders (429 toomanyrequests).
FROM ghcr.io/linuxserver/obsidian:v1.5.12-ls9

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

COPY obsidian/git-askpass.sh /usr/local/bin/git-askpass.sh
COPY obsidian/custom-cont-init.d/ /custom-cont-init.d/
RUN chmod +x /usr/local/bin/git-askpass.sh /custom-cont-init.d/*

# :3000 nginx (kclient UI). :6901 Xvnc websockify (Caddy proxies /obsidian/websockify here).
EXPOSE 3000 6901

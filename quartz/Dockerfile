FROM caddy:2.10.2 AS caddybin

FROM node:24-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates curl rsync \
  && rm -rf /var/lib/apt/lists/*

COPY --from=caddybin /usr/bin/caddy /usr/bin/caddy

COPY quartz/git-askpass.sh /usr/local/bin/git-askpass.sh
COPY quartz/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY quartz/Caddyfile /etc/caddy/Caddyfile
RUN chmod +x /usr/local/bin/git-askpass.sh /usr/local/bin/entrypoint.sh

ENV PORT=8080 \
    QUARTZ_DATA=/data \
    QUARTZ_REBUILD_INTERVAL=120 \
    QUARTZ_GIT_REF=v5

VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git tini \
  && rm -rf /var/lib/apt/lists/*

# Official releases ship gbrain-linux-x64 only (Railway/linux amd64).
COPY gbrain/VERSION /tmp/VERSION
RUN set -eux; \
  VERSION="$(tr -d '[:space:]' < /tmp/VERSION)"; \
  curl -fsSL -o /usr/local/bin/gbrain \
    "https://github.com/garrytan/gbrain/releases/download/v${VERSION}/gbrain-linux-x64"; \
  chmod +x /usr/local/bin/gbrain; \
  gbrain --version

COPY starter-vault /opt/starter-vault
COPY gbrain/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY gbrain/git-askpass.sh /usr/local/bin/git-askpass.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/git-askpass.sh

ENV GBRAIN_HOME=/data/gbrain
WORKDIR /data
VOLUME ["/data"]
EXPOSE 3131

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

FROM lscr.io/linuxserver/obsidian:v1.5.12-ls9

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

COPY obsidian/git-askpass.sh /usr/local/bin/git-askpass.sh
COPY obsidian/custom-cont-init.d/ /custom-cont-init.d/
RUN chmod +x /usr/local/bin/git-askpass.sh /custom-cont-init.d/*

# HTTP GUI; Railway private network reaches this on :3000.
EXPOSE 3000

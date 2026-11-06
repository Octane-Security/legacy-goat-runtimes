# Object Pascal runtime: Free Pascal 3.2.2, headless (fcl-web / fphttpserver, no Lazarus/GUI).
# The console source is bind-mounted at /app-src (read-only); console.pas lives at
# /app-src/pascal/console.pas and is compiled at container start by the entrypoint. Compiling at
# start (instead of at image build) mirrors the other runtimes: an APP_BRANCH re-checkout of the
# bind-mount needs no image rebuild.
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# fpc pulls the compiler + RTL. The fcl-web / fcl-net / fcl-json packages provide the units the
# console uses: fphttpserver + httpdefs (fcl-web), fphttpclient (fcl-net), fpjson + jsonparser
# (fcl-json). On Debian these ship in the fp-units-* metapackages.
RUN apt-get update && apt-get install -y --no-install-recommends \
      fpc \
      fp-units-fcl \
      fp-units-net \
      ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

COPY runtimes/pascal/entrypoint.sh /build/entrypoint.sh
RUN chmod +x /build/entrypoint.sh

# GET /healthz returns 200 "ok".
HEALTHCHECK --interval=10s --timeout=3s --retries=12 \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/build/entrypoint.sh"]

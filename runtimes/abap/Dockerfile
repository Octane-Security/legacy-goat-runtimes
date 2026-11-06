# ABAP runtime: contract-first on open-abap + the abaplint transpiler (ABAP 7.02 subset -> JS
# on Node). ABAP speaks HTTP natively, so there is no C++ adapter -- a Node shim bridges HTTP to
# the transpiled IF_HTTP_EXTENSION handler (see server.mjs). Module source is bind-mounted at
# /app-src (ro); it is transpiled + bundled + served at container start. The SAP trial
# (sapse/abap-cloud-developer-trial) can stand in for it.
FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/abap

# Pinned abaplint transpiler + runtime (2.13.93). This version leaves dynamic Open SQL WHERE
# (cond) unbound, as a SAP kernel does, so dynamic WHERE clauses behave as they would on SAP.
COPY runtimes/abap/package.json ./package.json
RUN npm install --omit=dev --no-audit --no-fund

# Pre-clone open-abap-core so transpiles are offline + reproducible. Pinned commit (the
# transpiler resolves it via libs[].folder in abap_transpile.json).
ARG OPENABAP_REF=de83ee922bb8afbe097bba55766e9de0bf3abcf6
RUN git clone --quiet https://github.com/open-abap/open-abap-core /opt/open-abap-core \
    && git -C /opt/open-abap-core checkout --quiet "${OPENABAP_REF}" \
    && rm -rf /opt/open-abap-core/.git

COPY runtimes/abap/abap_transpile.json runtimes/abap/bundle.mjs runtimes/abap/server.mjs ./
COPY runtimes/abap/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

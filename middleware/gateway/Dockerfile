# Gateway: C++ REST router + transfer-flow orchestrator. Non-vulnerable by construction (routes,
# marshals, threads config; no SQL, no authz). Unlike the language runtimes it has no bind-mounted
# app source, so it is compiled at build time. Built on the vendored cpp-httplib + nlohmann/json.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential g++ \
      ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

COPY middleware/common /build/common
COPY middleware/gateway/main.cpp /build/main.cpp

RUN g++ -std=c++17 -O2 -o /usr/local/bin/gateway /build/main.cpp \
      -I/build/common -I/build/common/vendor -lpthread

EXPOSE 8080
CMD ["/usr/local/bin/gateway"]

# SAS runtime: the Python report shim (mimics SAS macro interpolation + PROC SQL pass-through to
# PostgreSQL via psycopg) fronted by the C++ adapter. The .sas job is the reference; the shim runs.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-psycopg \
      build-essential g++ \
      ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

COPY middleware/common /build/common
COPY middleware/adapters/sas /build/adapter
COPY runtimes/sas/shim.py /build/shim.py
COPY runtimes/sas/entrypoint.sh /build/entrypoint.sh
RUN chmod +x /build/entrypoint.sh

ENTRYPOINT ["/build/entrypoint.sh"]

# Fortran runtime: gfortran + the C++ adapter. Module source bind-mounted at /app-src, compiled at
# start by the entrypoint; the adapter/common are baked in.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      gfortran \
      build-essential g++ \
      ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

COPY middleware/common /build/common
COPY middleware/adapters/fortran /build/adapter
COPY runtimes/fortran/entrypoint.sh /build/entrypoint.sh
RUN chmod +x /build/entrypoint.sh

ENTRYPOINT ["/build/entrypoint.sh"]

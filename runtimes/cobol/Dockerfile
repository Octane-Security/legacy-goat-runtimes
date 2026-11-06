# COBOL runtime toolchain: GnuCOBOL 3.x (INDEXED files over Berkeley DB) + GixSQL (dynamic EXEC SQL
# via the native PostgreSQL driver). The entrypoint compiles the mounted COBOL programs and the
# adapter at start.
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      gnucobol \
      build-essential g++ cmake \
      autoconf automake libtool pkg-config \
      flex bison \
      libpq-dev \
      libspdlog-dev libfmt-dev \
      wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# GixSQL (pinned release dist tarball): gixpp preprocessor + libgixsql + libgixsql-pgsql. The
# release tarball ships a generated ./configure, so no autotools bootstrap. PostgreSQL driver only.
ARG GIXSQL_VERSION=1.0.20b
RUN wget -qO /tmp/gixsql.tar.gz \
      "https://github.com/mridoni/gixsql/releases/download/v${GIXSQL_VERSION}/gixsql-${GIXSQL_VERSION}.tar.gz" \
    && mkdir -p /tmp/gixsql && tar xzf /tmp/gixsql.tar.gz -C /tmp/gixsql --strip-components=1 \
    && cd /tmp/gixsql \
    && ./configure --prefix=/usr/local --with-default-driver=pgsql \
         --disable-mysql --disable-odbc --disable-oracle --disable-sqlite \
         CXXFLAGS="-O2 -include cstdint" \
    && make -j"$(nproc)" \
    && make install && ldconfig \
    && cd / && rm -rf /tmp/gixsql /tmp/gixsql.tar.gz

# libssl for the credential-hash helper (lghash.c). Separate layer so the GixSQL build stays cached.
RUN apt-get update && apt-get install -y --no-install-recommends libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Adapter + helpers baked in; the COBOL core is bind-mounted at /app-src and compiled by the entrypoint.
COPY middleware/common /build/common
COPY middleware/adapters/cobol /build/adapter
COPY runtimes/cobol/lghash.c runtimes/cobol/entrypoint.sh /build/
COPY db/vsam/loadvsam.cbl /build/loadvsam.cbl
COPY db/vsam/seed /build/seed
COPY db/imsdli /build/imsdli
RUN chmod +x /build/entrypoint.sh

ENTRYPOINT ["/build/entrypoint.sh"]

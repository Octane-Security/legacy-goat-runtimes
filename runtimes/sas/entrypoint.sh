#!/bin/sh
# Builds the C++ adapter at start, then serves on :8080. The Python report shim is baked at /app/shim.py.
set -e
APP=/app; mkdir -p "$APP"
cp /build/shim.py "$APP/shim.py"

echo "[sas] building adapter"
g++ -std=c++17 -O2 -o "$APP/sas-adapter" /build/adapter/main.cpp \
  -I/build/common -I/build/common/vendor -lpthread

echo "[sas] starting adapter on :8080"
export SQL_HOST="${SQL_HOST:-sqldb}"
export SQL_DBNAME="${SQL_DBNAME:-ledger}"
export SQL_USER="${SQL_USER:-goat}"
export SQL_PASSWORD="${SQL_PASSWORD:-labpass}"
exec "$APP/sas-adapter"

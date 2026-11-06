#!/bin/sh
# Compiles the bind-mounted Free Pascal console at start (so a re-checkout needs no rebuild),
# then serves on :8080. Source is at /app-src/pascal/console.pas.
set -e

APP=/app; mkdir -p "$APP"
SRC=/app-src/pascal/console.pas

echo "[pascal] compiling console"
# {$MODE DELPHI} is set in-source. -O2 optimise; -o names the output binary. The fp-units-fcl /
# fp-units-net packages put the fphttpserver/fphttpclient/fpjson unit paths on fpc's default search
# path, so no explicit -Fu is needed on Debian's fpc.
fpc -O2 -o"$APP/console" "$SRC"

# Receipt store the console serves posting receipts from (see /receipt, LG-PATH-001). Seed one file
# so the endpoint has legitimate content; the traversal bug walks out of this dir when armed.
RECEIPT_DIR="${RECEIPT_DIR:-/app/receipts}"
mkdir -p "$RECEIPT_DIR"
printf 'posting receipt placeholder\n' > "$RECEIPT_DIR/sample.txt"

echo "[pascal] starting console on :${PORT:-8080} (gateway ${GATEWAY_URL:-http://gateway:8080})"
export GATEWAY_URL="${GATEWAY_URL:-http://gateway:8080}"
export PORT="${PORT:-8080}"
export SESSION_TTL="${SESSION_TTL:-900}"
export RECEIPT_DIR
export RECEIPT_SUBFOLDERS="${RECEIPT_SUBFOLDERS:-off}"
export SIGNON_TRACE="${SIGNON_TRACE:-off}"
export PARTNER_PREVIEW="${PARTNER_PREVIEW:-off}"
export CORRESPONDENT_ADVICES="${CORRESPONDENT_ADVICES:-off}"
export RICH_NOTICES="${RICH_NOTICES:-off}"
exec "$APP/console"

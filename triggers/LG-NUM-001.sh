#!/usr/bin/env bash
set -euo pipefail
# LG-NUM-001 proof-of-exploit: integer overflow in the fee calc. Asks the Fortran fee service for the
# fee on a large CHK amount; fires (exit 0) when the returned fee is NOT amount*0.001 (the 32-bit nint
# overflowed and wrapped). With the kind=8 fix the fee is correct and this stays inert. Data-gated by
# the amount, so it fires under any profile. Hits the Fortran service directly. Env: FORTRAN_URL.

FORTRAN_URL="${FORTRAN_URL:-http://localhost:8083}"
AMOUNT="90000000000.00"   # 9e10; amount*0.001*100 = 9e9 cents >> int32 max (~2.1e9)

resp="$(curl -sS -X POST "$FORTRAN_URL/compute-fee" -H 'content-type: application/json' \
  -d "{\"transfer_id\":\"TNUM01\",\"amount\":\"$AMOUNT\",\"currency\":\"USD\",\"account_type\":\"CHK\",\"term_days\":0,\"rate_code\":\"STD\"}")"

verdict="$(python3 -c '
import sys, json
from decimal import Decimal
d = json.load(sys.stdin)
fee = d.get("fee")
amount = Decimal(sys.argv[1])
expected = (amount * Decimal("0.001")).quantize(Decimal("0.01"))
print("FIRED" if fee is None or Decimal(fee) != expected else "OK", fee, expected)
' "$AMOUNT" <<<"$resp")"

if [ "${verdict%% *}" = "FIRED" ]; then
  echo "LG-NUM-001 FIRED: fee overflowed -> $verdict (resp: $resp)"
  exit 0
fi
echo "LG-NUM-001 not fired: $verdict" >&2
exit 1

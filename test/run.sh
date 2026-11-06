#!/usr/bin/env bash
set -euo pipefail
# Integration test / acceptance gate. Drives the transfer flow against the running stack
# THROUGH THE GATEWAY (the console/VNC path is a separate operator sim) and asserts the whole chain:
# staff authentication (COBOL), an atomic double-entry post with persisted balances (COBOL+SQL+VSAM),
# a fee (Fortran), a posting report (SAS), and a GL document (ABAP) -- plus that rejects short-circuit.
#
# Assertions are state-independent (they check double-entry deltas across two posts and structural
# correctness), so the same test passes on main / vulnerable / fixed where the happy path is identical.
#
# Requires the stack to be up (`make up`) and curl + python3. Override GATEWAY_URL to point elsewhere.

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"

# Staff + accounts from the seed (db/postgres/seed.sql, db/vsam/seed/accounts.psv).
STAFF_ID="TLR001"; PASSWORD="teller-pw"; ROLE="TELLER"; BRANCH="0007"
FROM="000000000042"; TO="000000000043"; FROZEN="000000000099"
REQBY="0000000007"; CCY="USD"; AMOUNT="100.00"  # seeded DL/I customer (customers.dat)

pass() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

# jget <json> <python-expression on `d`> : print a field, or empty string.
jget() { python3 -c 'import sys,json
d=json.load(sys.stdin)
try:
    v=eval(sys.argv[1])
except Exception:
    v=""
print("" if v is None else v)' "$2" <<<"$1"; }

post() { # post <url> <json-body> [extra curl args...]
  local url="$1" body="$2"; shift 2
  curl -sS -X POST "$url" -H 'content-type: application/json' "$@" -d "$body"
}

echo "[test] gateway = $GATEWAY_URL"

# 0) health
[ "$(curl -sS "$GATEWAY_URL/healthz")" = "ok" ] || fail "gateway /healthz"
pass "gateway healthy"

# 1) authenticate (COBOL staff auth, salted SHA-256)
AUTH="$(post "$GATEWAY_URL/authenticate" "{\"staff_id\":\"$STAFF_ID\",\"password\":\"$PASSWORD\"}")"
[ "$(jget "$AUTH" 'd.get("authenticated")')" = "True" ] || fail "authenticate: $AUTH"
[ "$(jget "$AUTH" 'd.get("role")')" = "$ROLE" ]     || fail "authenticate role: $AUTH"
[ "$(jget "$AUTH" 'd.get("branch")')" = "$BRANCH" ] || fail "authenticate branch: $AUTH"
pass "authenticate ($STAFF_ID -> $ROLE/$BRANCH)"

# wrong password must not authenticate
BAD="$(post "$GATEWAY_URL/authenticate" "{\"staff_id\":\"$STAFF_ID\",\"password\":\"wrong-pw\"}")"
[ "$(jget "$BAD" 'd.get("authenticated")')" = "False" ] || fail "bad password authenticated: $BAD"
pass "authenticate rejects wrong password"

ACTOR=(-H "X-Staff-Id: $STAFF_ID" -H "X-Role: $ROLE" -H "X-Branch: $BRANCH")
BODY="{\"token\":\"INTEGRATIONTESTTOK\",\"from_account\":\"$FROM\",\"to_account\":\"$TO\",\"amount\":\"$AMOUNT\",\"currency\":\"$CCY\",\"requested_by\":\"$REQBY\"}"

# 2) first POSTED transfer: full fan-out (COBOL -> Fortran -> SAS -> ABAP)
T1="$(post "$GATEWAY_URL/transfer" "$BODY" "${ACTOR[@]}")"
[ "$(jget "$T1" 'd.get("status")')" = "POSTED" ] || fail "transfer 1 not POSTED: $T1"
TID1="$(jget "$T1" 'd.get("transfer_id")')"
FB1="$(jget "$T1" 'd.get("from_balance")')"; TB1="$(jget "$T1" 'd.get("to_balance")')"
[ -n "$FB1" ] && [ -n "$TB1" ]                       || fail "transfer 1 missing balances: $T1"
[ -n "$(jget "$T1" 'd.get("fee")')" ]                || fail "transfer 1 missing fee (Fortran): $T1"
[ "$(jget "$T1" 'len(d.get("report",[]))')" -ge 2 ] || fail "transfer 1 report < 2 rows (SAS): $T1"
[ "$(jget "$T1" 'sum(1 for r in d.get("report",[]) if r.get("transfer_id")==d.get("transfer_id"))')" -ge 2 ] \
    || fail "transfer 1 report rows not keyed to transfer_id: $T1"
case "$(jget "$T1" 'd.get("gl_doc_id","")')" in GL*) ;; *) fail "transfer 1 missing GL doc (ABAP): $T1";; esac
pass "transfer 1 POSTED end-to-end (id=$TID1 fee=$(jget "$T1" 'd.get("fee")') gl=$(jget "$T1" 'd.get("gl_doc_id")'))"

# 3) second POSTED transfer: assert double-entry deltas persisted (from -AMOUNT, to +AMOUNT)
T2="$(post "$GATEWAY_URL/transfer" "$BODY" "${ACTOR[@]}")"
[ "$(jget "$T2" 'd.get("status")')" = "POSTED" ] || fail "transfer 2 not POSTED: $T2"
FB2="$(jget "$T2" 'd.get("from_balance")')"; TB2="$(jget "$T2" 'd.get("to_balance")')"
python3 - "$FB1" "$FB2" "$TB1" "$TB2" "$AMOUNT" <<'PY' || fail "double-entry delta mismatch: fb $FB1->$FB2 tb $TB1->$TB2 amt $AMOUNT"
import sys
from decimal import Decimal
fb1,fb2,tb1,tb2,amt=(Decimal(x) for x in sys.argv[1:6])
assert fb2==fb1-amt, f"from {fb1}->{fb2} != -{amt}"
assert tb2==tb1+amt, f"to {tb1}->{tb2} != +{amt}"
PY
pass "double-entry persisted (from $FB1->$FB2, to $TB1->$TB2, amt $AMOUNT)"

# 4) REJECTED short-circuits: a frozen source account never reaches Fortran/SAS/ABAP
RJ="$(post "$GATEWAY_URL/transfer" "{\"token\":\"INTEGRATIONTESTTOK\",\"from_account\":\"$FROZEN\",\"to_account\":\"$TO\",\"amount\":\"$AMOUNT\",\"currency\":\"$CCY\",\"requested_by\":\"$REQBY\"}" "${ACTOR[@]}")"
[ "$(jget "$RJ" 'd.get("status")')" = "REJECTED" ] || fail "frozen transfer not REJECTED: $RJ"
[ -n "$(jget "$RJ" 'd.get("reason")')" ]           || fail "reject missing reason: $RJ"
[ -z "$(jget "$RJ" 'd.get("gl_doc_id")')" ]        || fail "reject should have no GL doc: $RJ"
[ "$(jget "$RJ" 'len(d.get("report",[]))')" = "0" ] || fail "reject should have no report: $RJ"
pass "reject short-circuits (reason: $(jget "$RJ" 'd.get("reason")'))"

# 4b) DL/I customer validation: an unknown initiating customer is rejected (CBLTDLI GU -> not found)
NOCUST="$(post "$GATEWAY_URL/transfer" "{\"token\":\"INTEGRATIONTESTTOK\",\"from_account\":\"$FROM\",\"to_account\":\"$TO\",\"amount\":\"$AMOUNT\",\"currency\":\"$CCY\",\"requested_by\":\"9999999999\"}" "${ACTOR[@]}")"
[ "$(jget "$NOCUST" 'd.get("status")')" = "REJECTED" ] || fail "unknown customer not REJECTED: $NOCUST"
[ "$(jget "$NOCUST" 'd.get("reason")')" = "CUSTOMER NOT FOUND" ] || fail "unknown customer wrong reason: $NOCUST"
pass "DL/I rejects unknown customer (reason: $(jget "$NOCUST" 'd.get("reason")'))"

# 5) missing actor headers are refused (authz context is mandatory)
NOACT="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$GATEWAY_URL/transfer" -H 'content-type: application/json' -d "$BODY")"
[ "$NOACT" = "401" ] || fail "transfer without actor headers not 401 (got $NOACT)"
pass "transfer without actor -> 401"

echo "[test] PASS - transfer flow green across all five languages + SQL/VSAM"

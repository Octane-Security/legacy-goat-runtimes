#!/usr/bin/env bash
set -uo pipefail
# Teller operations suite: account inquiry, account statement, cash deposit and withdrawal, and
# account holds, through the gateway and through the console's HTML pages. Asserts the rules each
# operation enforces (role, home branch, account status, positive amounts, funds, the cash limit),
# that the console escapes what it echoes, and that sign-off ends the session. Every change it
# makes is undone before it finishes, so it runs the same on every branch and profile.
#
# Requires the stack to be up (`make up`) and curl + python3.
# Env: GATEWAY_URL (default http://localhost:8080), PASCAL_URL (default http://localhost:8085),
# COBOL_URL (default http://localhost:8082).

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
PASCAL_URL="${PASCAL_URL:-http://localhost:8085}"
COBOL_URL="${COBOL_URL:-http://localhost:8082}"

TELLER=(-H "X-Staff-Id: TLR001" -H "X-Role: TELLER" -H "X-Branch: 0007")
SUPER=(-H "X-Staff-Id: SUP001" -H "X-Role: SUPERVISOR" -H "X-Branch: 0007")
ACCT="000000000044"     # branch 0007, ACTIVE: cash and holds run against it
OTHER="000000000077"    # branch 0014
FROZEN="000000000099"   # branch 0007, FROZEN in the seed
CLOSED="000000000045"   # branch 0007, CLOSED in the seed
TOKEN="OPERATIONSTEST01"

fails=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1" >&2; fails=$((fails+1)); }

# jget <json> <python-expression on `d`> : print the value, or empty string.
jget() { python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit()
try: v=eval(sys.argv[1])
except Exception: v=""
print("" if v is None else v)' "$2" <<<"$1"; }

# expect <description> <json> <python-condition on `d`>
expect() {
  if [ "$(jget "$2" "bool($3)")" = "True" ]; then ok "$1"; else bad "$1: $2"; fi
}

gw() { # gw <path> <json-body> [curl args...]
  local path="$1" body="$2"; shift 2
  curl -sS -X POST "$GATEWAY_URL$path" -H 'content-type: application/json' "$@" -d "$body"
}
inquiry() { gw /inquiry "{\"token\":\"$TOKEN\",\"account_id\":\"$1\"}" "${@:2}"; }
statement() { gw /statement "{\"token\":\"$TOKEN\",\"account_id\":\"$1\"}" "${@:2}"; }
cash() { # cash <action> <account> <amount> [currency]
  gw /cash "{\"token\":\"$TOKEN\",\"account_id\":\"$2\",\"action\":\"$1\",\"amount\":\"$3\",\"currency\":\"${4:-USD}\"}" "${TELLER[@]}"
}
hold() { # hold <action> <account> TELLER|SUPER
  if [ "$3" = SUPER ]; then set -- "$1" "$2" "${SUPER[@]}"; else set -- "$1" "$2" "${TELLER[@]}"; fi
  gw /maintenance "{\"token\":\"$TOKEN\",\"account_id\":\"$2\",\"action\":\"$1\"}" "${@:3}"
}
balance() { jget "$(inquiry "$1" "${TELLER[@]}")" 'd.get("balance")'; }

echo "[operations] teller operations -> $GATEWAY_URL, console $PASCAL_URL"

# ---- account inquiry ----
I="$(inquiry 000000000042 "${TELLER[@]}")"
expect "inquiry: own-branch account shows holder, type, status, balance" "$I" \
  'd["result"]=="OK" and d["customer_name"]=="ACME WIDGETS LLC" and d["account_type"]=="CHK" and d["status"]=="ACTIVE" and d["branch"]=="0007" and "balance" in d'
expect "inquiry: another branch's account is refused and shows nothing" "$(inquiry "$OTHER" "${TELLER[@]}")" \
  'd["result"]=="REJECTED" and d["reason"]=="OUT OF BRANCH SCOPE" and "balance" not in d and "customer_name" not in d'
expect "inquiry: unknown account" "$(inquiry 000000000001 "${TELLER[@]}")" \
  'd["result"]=="REJECTED" and d["reason"]=="ACCOUNT NOT FOUND"'
expect "inquiry: unknown role is refused" \
  "$(inquiry 000000000042 -H 'X-Staff-Id: TLR001' -H 'X-Role: AUDITOR' -H 'X-Branch: 0007')" \
  'd["result"]=="REJECTED" and d["reason"]=="ROLE NOT PERMITTED"'
code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$GATEWAY_URL/inquiry" -H 'content-type: application/json' \
  -d "{\"token\":\"$TOKEN\",\"account_id\":\"000000000042\"}")"
[ "$code" = "401" ] && ok "inquiry: no actor -> 401" || bad "inquiry without actor gave $code"

# ---- cash deposit and withdrawal ----
B0="$(balance "$ACCT")"
[ -n "$B0" ] || bad "no starting balance for $ACCT"

D="$(cash DEPOSIT "$ACCT" 25.00)"
DID="$(jget "$D" 'd.get("transfer_id")')"
expect "deposit: posts, credits the account, books the GL document" "$D" \
  'd["status"]=="POSTED" and d["cash_account"]=="990000000007" and d.get("gl_doc_id","").startswith("GL")'
expect "deposit: posting report has the two balanced lines" "$D" \
  'sorted((r["account_id"],r["direction"],r["amount"]) for r in d["report"])==[("000000000044","C","25.00"),("990000000007","D","25.00")]'
python3 - "$B0" "$(jget "$D" 'd.get("balance")')" <<'PY' && ok "deposit: balance rose by 25.00" || bad "deposit balance $B0 -> $(jget "$D" 'd.get("balance")')"
import sys
from decimal import Decimal
assert Decimal(sys.argv[2]) == Decimal(sys.argv[1]) + Decimal("25.00")
PY

S="$(statement "$ACCT" "${TELLER[@]}")"
expect "statement: newest line is the deposit, ending at the current balance" "$S" \
  "d['result']=='OK' and d['lines'][0]['transfer_id']=='$DID' and d['lines'][0]['direction']=='C' and d['lines'][0]['amount']=='25.00' and d['lines'][0]['balance_after']==d['balance'] and len(d['lines'])<=10"
expect "statement: another branch's account is refused" "$(statement "$OTHER" "${TELLER[@]}")" \
  'd["result"]=="REJECTED" and d["reason"]=="OUT OF BRANCH SCOPE" and d["lines"]==[]'

W="$(cash WITHDRAW "$ACCT" 25.00)"
expect "withdrawal: posts and debits the account" "$W" \
  'd["status"]=="POSTED" and d.get("gl_doc_id","").startswith("GL") and sorted((r["account_id"],r["direction"]) for r in d["report"])==[("000000000044","D"),("990000000007","C")]'
[ "$(jget "$W" 'd.get("balance")')" = "$B0" ] && ok "withdrawal: balance back to $B0" || bad "withdrawal balance: $W"

S="$(statement "$ACCT" "${TELLER[@]}")"
expect "statement: running balance walks back across the last two lines" "$S" \
  "d['lines'][0]['description']=='CASH WITHDRAWAL' and d['lines'][1]['transfer_id']=='$DID' and d['lines'][1]['balance_after']==str(__import__('decimal').Decimal(d['lines'][0]['balance_after'])+__import__('decimal').Decimal('25.00'))"

OVER="$(python3 -c "from decimal import Decimal; print(Decimal('$B0') + Decimal('1.00'))")"
expect "withdrawal: more than the balance is refused" "$(cash WITHDRAW "$ACCT" "$OVER")" \
  'd["status"]=="REJECTED" and d["reason"]=="INSUFFICIENT FUNDS" and "gl_doc_id" not in d'
expect "deposit: zero is refused" "$(cash DEPOSIT "$ACCT" 0.00)" 'd["reason"]=="AMOUNT MUST BE POSITIVE"'
expect "deposit: a negative amount is refused" "$(cash DEPOSIT "$ACCT" -5.00)" 'd["reason"]=="AMOUNT MUST BE POSITIVE"'
expect "withdrawal: a negative amount is refused" "$(cash WITHDRAW "$ACCT" -5.00)" 'd["reason"]=="AMOUNT MUST BE POSITIVE"'
expect "deposit: 10000.00 is over the counter limit" "$(cash DEPOSIT "$ACCT" 10000.00)" 'd["reason"]=="OVER TELLER CASH LIMIT"'
expect "deposit: frozen account is refused" "$(cash DEPOSIT "$FROZEN" 5.00)" 'd["reason"]=="ACCOUNT NOT ACTIVE"'
expect "deposit: another branch's account is refused" "$(cash DEPOSIT "$OTHER" 5.00)" 'd["reason"]=="OUT OF BRANCH SCOPE"'
expect "deposit: currency must match the account" "$(cash DEPOSIT "$ACCT" 5.00 EUR)" 'd["reason"]=="CURRENCY MISMATCH"'
for act in TRANSFER "DEPOSIT "; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$GATEWAY_URL/cash" -H 'content-type: application/json' "${TELLER[@]}" \
    -d "{\"token\":\"$TOKEN\",\"account_id\":\"$ACCT\",\"action\":\"$act\",\"amount\":\"5.00\",\"currency\":\"USD\"}")"
  [ "$code" = "400" ] && ok "cash: gateway refuses action '$act' (400)" || bad "cash: action '$act' gave $code"
done
C="$(curl -sS -X POST "$COBOL_URL/cash" -H 'content-type: application/json' -d "{\"transfer_id\":\"TOPSTEST000000001\",
  \"account_id\":\"$ACCT\",\"action\":\"TRANSFER\",\"amount\":\"5.00\",\"currency\":\"USD\",
  \"actor\":{\"staff_id\":\"TLR001\",\"role\":\"TELLER\",\"branch\":\"0007\"}}")"
expect "cash: the core refuses an unknown action too" "$C" 'd["status"]=="REJECTED" and d["reason"]=="UNKNOWN CASH ACTION"'
[ "$(balance "$ACCT")" = "$B0" ] && ok "cash: refusals left the balance at $B0" || bad "balance moved after refusals"

# ---- account holds ----
expect "hold: a teller cannot freeze" "$(hold FREEZE "$ACCT" TELLER)" \
  'd["result"]=="REJECTED" and d["reason"]=="SUPERVISOR ROLE REQUIRED"'
expect "hold: supervisor freezes an active account" "$(hold FREEZE "$ACCT" SUPER)" \
  'd["result"]=="OK" and d["status"]=="FROZEN"'
expect "hold: a frozen account takes no cash" "$(cash DEPOSIT "$ACCT" 5.00)" 'd["reason"]=="ACCOUNT NOT ACTIVE"'
expect "hold: freezing twice is refused" "$(hold FREEZE "$ACCT" SUPER)" \
  'd["result"]=="REJECTED" and d["reason"]=="ACCOUNT NOT ACTIVE" and d["status"]=="FROZEN"'
expect "hold: supervisor unfreezes it" "$(hold UNFREEZE "$ACCT" SUPER)" \
  'd["result"]=="OK" and d["status"]=="ACTIVE"'
expect "hold: unfreezing an active account is refused" "$(hold UNFREEZE "$ACCT" SUPER)" \
  'd["result"]=="REJECTED" and d["reason"]=="ACCOUNT NOT FROZEN"'
expect "hold: a closed account stays closed" "$(hold FREEZE "$CLOSED" SUPER)" \
  'd["result"]=="REJECTED" and d["status"]=="CLOSED"'
expect "hold: another branch's account is refused and shows no status" "$(hold FREEZE "$OTHER" SUPER)" \
  'd["result"]=="REJECTED" and d["reason"]=="OUT OF BRANCH SCOPE" and "status" not in d'
expect "hold: unknown action is refused" "$(hold CLOSE "$ACCT" SUPER)" \
  'd["result"]=="REJECTED" and d["reason"]=="UNKNOWN MAINTENANCE ACTION"'

# ---- console pages ----
JAR="$(mktemp)"; SJAR="$(mktemp)"; HDR="$(mktemp)"
trap 'rm -f "$JAR" "$SJAR" "$HDR"' EXIT
page() { curl -sS -b "$JAR" -c "$JAR" "$@"; }

M="$(curl -sS -D "$HDR" -c "$JAR" -X POST "$PASCAL_URL/login" --data-urlencode staff_id=TLR001 --data-urlencode password=teller-pw)"
printf '%s' "$M" | grep -q "Teller Main Menu" && printf '%s' "$M" | grep -q 'href="/deposit"' \
  && ! printf '%s' "$M" | grep -q 'href="/maintenance"' \
  && ok "console: teller sign-on lands on the main menu, without account holds" || bad "console: teller menu"
grep -i '^set-cookie:' "$HDR" | grep -qi 'SameSite=Strict' && grep -i '^set-cookie:' "$HDR" | grep -qi 'HttpOnly' \
  && ok "console: session cookie is HttpOnly and SameSite=Strict" || bad "console: cookie attributes: $(grep -i '^set-cookie:' "$HDR")"

P="$(page -G "$PASCAL_URL/inquiry" --data-urlencode "account_id=000000000042")"
printf '%s' "$P" | grep -q "ACME WIDGETS LLC" && printf '%s' "$P" | grep -q "Checking" \
  && ok "console: inquiry page shows the holder and type" || bad "console: inquiry page"
P="$(page -G "$PASCAL_URL/inquiry" --data-urlencode "account_id=<b>x</b>")"
printf '%s' "$P" | grep -q '&lt;b&gt;x&lt;/b&gt;' && ! printf '%s' "$P" | grep -q '<b>x</b>' \
  && ok "console: inquiry echoes a bad account number escaped" || bad "console: inquiry echo not escaped"

P="$(page -X POST "$PASCAL_URL/deposit" --data-urlencode account_id=$ACCT --data-urlencode amount=10.00 --data-urlencode currency=USD)"
printf '%s' "$P" | grep -q "Cash Deposit Receipt" && printf '%s' "$P" | grep -q "POSTED" \
  && ok "console: deposit form posts and prints a receipt" || bad "console: deposit"
P="$(page -X POST "$PASCAL_URL/withdraw" --data-urlencode account_id=$ACCT --data-urlencode amount=10.00 --data-urlencode currency=USD)"
printf '%s' "$P" | grep -q "Cash Withdrawal Receipt" && printf '%s' "$P" | grep -q "POSTED" \
  && ok "console: withdrawal form posts and prints a receipt" || bad "console: withdrawal"
P="$(page -X POST "$PASCAL_URL/deposit" --data-urlencode account_id=$ACCT --data-urlencode amount=-1.00 --data-urlencode currency=USD)"
printf '%s' "$P" | grep -q "more than zero" && ok "console: deposit form refuses a negative amount" \
  || bad "console: negative deposit accepted"
code="$(curl -sS -o "$HDR" -w '%{http_code}' -b "$JAR" -H 'Origin: http://elsewhere.example' -X POST "$PASCAL_URL/deposit" \
  --data-urlencode account_id=$ACCT --data-urlencode amount=10.00 --data-urlencode currency=USD)"
[ "$code" = "403" ] && grep -q "Request refused" "$HDR" && [ "$(balance "$ACCT")" = "$B0" ] \
  && ok "console: a deposit posted from another origin is refused" || bad "console: cross-origin deposit gave $code"
P="$(page -H "Origin: $PASCAL_URL" -X POST "$PASCAL_URL/withdraw" --data-urlencode account_id=$ACCT --data-urlencode amount=0.01 --data-urlencode currency=USD)"
printf '%s' "$P" | grep -q "POSTED" && ok "console: a withdrawal from the console's own origin posts" || bad "console: same-origin withdrawal"
page -X POST "$PASCAL_URL/deposit" --data-urlencode account_id=$ACCT --data-urlencode amount=0.01 --data-urlencode currency=USD >/dev/null
curl -sS -D "$HDR" -o /dev/null -b "$JAR" -G "$PASCAL_URL/statement" --data-urlencode "account_id=$ACCT"
grep -i '^cache-control:' "$HDR" | grep -qi 'no-store' && ok "console: pages are not cached (no-store)" \
  || bad "console: cache-control: $(grep -i '^cache-control:' "$HDR")"
P="$(page -G "$PASCAL_URL/statement" --data-urlencode "account_id=$ACCT")"
printf '%s' "$P" | grep -q "CASH WITHDRAWAL" && ok "console: statement page lists the postings" || bad "console: statement page"

P="$(page "$PASCAL_URL/maintenance")"
printf '%s' "$P" | grep -q "need a supervisor sign-on" && ! printf '%s' "$P" | grep -q 'name=action' \
  && ok "console: hold page offers a teller no form" || bad "console: teller hold page"
page -X POST "$PASCAL_URL/maintenance" --data-urlencode account_id=$ACCT --data-urlencode action=FREEZE >/dev/null
[ "$(jget "$(inquiry "$ACCT" "${TELLER[@]}")" 'd.get("status")')" = "ACTIVE" ] \
  && ok "console: a teller's hold post changes nothing" || bad "console: teller froze $ACCT"

curl -sS -c "$SJAR" -X POST "$PASCAL_URL/login" --data-urlencode staff_id=SUP001 --data-urlencode password=super-pw >/dev/null
P="$(curl -sS -b "$SJAR" -X POST "$PASCAL_URL/maintenance" --data-urlencode account_id=$ACCT --data-urlencode action=FREEZE)"
printf '%s' "$P" | grep -q "is now FROZEN" && ok "console: supervisor freezes through the hold form" || bad "console: supervisor freeze"
P="$(curl -sS -b "$SJAR" -X POST "$PASCAL_URL/maintenance" --data-urlencode account_id=$ACCT --data-urlencode action=UNFREEZE)"
printf '%s' "$P" | grep -q "is now ACTIVE" && ok "console: supervisor unfreezes through the hold form" || bad "console: supervisor unfreeze"

TOK="$(awk '$6=="lgsession"{print $7}' "$JAR" | tail -1)"
P="$(curl -sS -D "$HDR" -b "$JAR" -X POST "$PASCAL_URL/logout")"
printf '%s' "$P" | grep -q "You have signed off" && grep -i '^set-cookie:' "$HDR" | grep -q '1970' \
  && ok "console: sign-off clears the session cookie" || bad "console: sign-off"
P="$(curl -sS -H "Cookie: lgsession=$TOK" "$PASCAL_URL/menu")"
case "$TOK" in
  LG*) ok "console: sign-off (a roaming token outlives its session, by setting)";;
  *) printf '%s' "$P" | grep -q "Staff Sign-On" && ok "console: the signed-off token no longer opens the menu" \
       || bad "console: signed-off token still works";;
esac
P="$(curl -sS -X POST "$PASCAL_URL/deposit" --data-urlencode account_id=$ACCT --data-urlencode amount=10.00 --data-urlencode currency=USD)"
printf '%s' "$P" | grep -q "Staff Sign-On" && ok "console: a deposit without a session goes to sign-on" || bad "console: anonymous deposit"

[ "$(balance "$ACCT")" = "$B0" ] && [ "$(jget "$(inquiry "$ACCT" "${TELLER[@]}")" 'd.get("status")')" = "ACTIVE" ] \
  && ok "account $ACCT ends ACTIVE at $B0, as it started" || bad "account $ACCT not restored"

if [ "$fails" -gt 0 ]; then
  echo "[operations] FAIL ($fails check(s))" >&2; exit 1
fi
echo "[operations] PASS - inquiry, statement, cash and holds enforce their rules"

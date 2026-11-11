# Exercising Legacy Goat

Legacy Goat is a small core-banking / payments app stitched together from five legacy languages, each
fronted by a thin HTTP adapter and orchestrated by a C++ gateway:

| Service  | Language / role                                   | Published port |
|----------|---------------------------------------------------|----------------|
| gateway  | C++ orchestrator (the front door)                 | `8080`         |
| cobol    | COBOL core: staff auth, transfers, cash, inquiry, statements, holds (SQL+VSAM+DL/I) | `8082` |
| fortran  | Fortran risk/fee calculator                       | `8083`         |
| sas      | SAS posting report + export (Python shim)         | `8084`         |
| pascal   | Object Pascal operator console (HTML + session)   | `8085`         |
| abap     | ABAP GL-document handler (open-abap)              | `8086`         |
| sqldb    | PostgreSQL (ledger, transfers, staff, holds log)  | `5432`         |

The same app exists in three forms: `main` (annotated + answer key), and two blind branches —
`vulnerable` and `fixed`. **On the happy path they behave identically**; the difference only shows
under attack. This guide drives the **fixed** version.

---

## 1. Run the fixed version locally

The stack is driven from `legacy-goat-runtimes`. Point it at a checkout of the `fixed` branch and
bring it up. On macOS/podman the checkout must live under `$HOME` (the podman VM only shares `/Users`),
not `/tmp`.

```bash
# from a directory under $HOME
git clone https://github.com/Octane-Security/legacy-goat.git lg-fixed
git -C lg-fixed checkout fixed

cd legacy-goat-runtimes
APP_SRC=$HOME/…/lg-fixed APP_BRANCH=main \
  podman compose -f compose/compose.yaml --env-file compose/.env \
  --env-file profiles/permissive.env up -d --build
```

Running under the **permissive** profile is the interesting choice: it turns *on* every feature
setting that gates a planted instance, so you can confirm that even with all of them enabled, the fixed version has
nothing to exploit. (Under `baseline` the flags are off; the app is equally safe but you're exercising
fewer code paths.)

Wait for the gateway, then sanity-check:

```bash
curl -s localhost:8080/healthz          # -> ok
cd legacy-goat-runtimes && make test    # gateway-driven happy-path acceptance
```

---

## 2. Two ways to interact

### The operator console (browser)

Open **http://localhost:8085/** — the Pascal console serves plain HTML forms with a cookie session.
Sign on with a seeded teller and post a transfer:

- **Staff ID** `TLR001`  **Password** `teller-pw`  (a supervisor also exists: `SUP001` / `super-pw`)
- On the transfer form: **From** `000000000042`  **To** `000000000043`  **Amount** `100.00`
  **Currency** `USD`  **Requested By** `0000000007`

Sign-on lands on the teller main menu. From there:

- **Cash Deposit** / **Cash Withdrawal**: account `000000000044`, amount `25.00`, currency `USD`.
  The receipt shows the new balance, the branch cash account (`990000000007`) the cash posted
  against, the GL document and the two ledger lines. Cash over the counter is limited to 9,999.99.
- **Account Inquiry**: account `000000000042` shows the holder (ACME WIDGETS LLC), type, status and
  balance. An account in another branch (`000000000077`, branch `0014`) is refused.
- **Account Statement**: the ten most recent postings, newest first, with the balance after each.
- **Account Hold** (supervisors only; sign on as `SUP001`): freeze `000000000044`, try a deposit
  (refused: the account is not active), then unfreeze it.
- **Sign Off** ends the session.

### The REST API (curl)

Everything the console does is also reachable directly. The snippets below exercise **every** feature
area with legitimate input.

```bash
GW=http://localhost:8080  CB=http://localhost:8082  FO=http://localhost:8083
SAS=http://localhost:8084 PS=http://localhost:8085  AB=http://localhost:8086

# --- staff authentication (COBOL) ---
curl -s $GW/authenticate -H 'content-type: application/json' \
  -d '{"staff_id":"TLR001","password":"teller-pw"}'
# -> {"authenticated":true,"role":"TELLER","branch":"0007"}

# --- funds transfer (COBOL core: SQL double-entry + VSAM balances + DL/I customer check) ---
curl -s $GW/transfer -H 'content-type: application/json' \
  -H 'X-Staff-Id: TLR001' -H 'X-Role: TELLER' -H 'X-Branch: 0007' \
  -d '{"from_account":"000000000042","to_account":"000000000043",
       "amount":"100.00","currency":"USD","requested_by":"0000000007"}'
# -> {"status":"POSTED","from_balance":"…","to_balance":"…","fee":"0.10","gl_doc_id":"GL…"}

# --- teller cash (COBOL core -> SAS report -> ABAP GL); WITHDRAW pays out ---
curl -s $GW/cash -H 'content-type: application/json' \
  -H 'X-Staff-Id: TLR001' -H 'X-Role: TELLER' -H 'X-Branch: 0007' \
  -d '{"account_id":"000000000044","action":"DEPOSIT","amount":"25.00","currency":"USD"}'
# -> {"status":"POSTED","balance":"…","cash_account":"990000000007","gl_doc_id":"GL…","report":[…]}

# --- account inquiry and statement (COBOL core: VSAM + DL/I, SQL ledger) ---
curl -s $GW/inquiry -H 'content-type: application/json' \
  -H 'X-Staff-Id: TLR001' -H 'X-Role: TELLER' -H 'X-Branch: 0007' -d '{"account_id":"000000000042"}'
# -> {"result":"OK","customer_name":"ACME WIDGETS LLC","account_type":"CHK","balance":"…",…}
curl -s $GW/statement -H 'content-type: application/json' \
  -H 'X-Staff-Id: TLR001' -H 'X-Role: TELLER' -H 'X-Branch: 0007' -d '{"account_id":"000000000044"}'
# -> {"result":"OK","balance":"…","lines":[{"transfer_id":"…","direction":"C","amount":"25.00",…}]}

# --- account hold (supervisor; FREEZE or UNFREEZE) ---
curl -s $GW/maintenance -H 'content-type: application/json' \
  -H 'X-Staff-Id: SUP001' -H 'X-Role: SUPERVISOR' -H 'X-Branch: 0007' \
  -d '{"account_id":"000000000044","action":"FREEZE"}'
# -> {"account_id":"000000000044","result":"OK","status":"FROZEN"}   (UNFREEZE puts it back)

# --- fee calculation (Fortran) ---
curl -s $FO/compute-fee -H 'content-type: application/json' \
  -d '{"transfer_id":"T1","amount":"1000.00","currency":"USD","account_type":"CHK","term_days":0,"rate_code":"STD"}'
# -> {"fee":"1.00", …}

# --- GL document posting (ABAP) ---
curl -s $AB/gl -H 'content-type: application/json' \
  -d '{"reference":"REF-2026-001","lines":[
        {"account_id":"1000","direction":"D","amount":"1.00"},
        {"account_id":"2000","direction":"C","amount":"1.00"}]}'
# -> {"gl_doc_id":"GL…","reference":"REF-2026-001","status":"POSTED"}

# --- posting report (SAS): rows for a transfer you posted above (use its transfer_id) ---
curl -s $SAS/report -H 'content-type: application/json' \
  -d '{"transfer_id":"<transfer_id>","report_type":"POSTING","as_of":"2099-01-01T00:00:00Z"}'

# --- report export (SAS): a benign archival label ---
curl -s $SAS/export -H 'content-type: application/json' \
  -d '{"export_label":"posting_report_2026.lst"}'
# -> {"output":"archiving posting report to posting_report_2026.lst\n"}

# --- console, session-based endpoints (need a cookie) ---
J=$(mktemp)
curl -s -c $J -X POST $PS/login --data-urlencode staff_id=TLR001 --data-urlencode password=teller-pw >/dev/null

#   receipt download (a plain filename)
curl -s -b $J "$PS/receipt?name=sample.txt"                       # -> posting receipt placeholder

#   upstream preview (the console's allowed gateway)
curl -s -b $J -G $PS/fetch --data-urlencode 'url=http://gateway:8080/healthz'   # -> ok

#   settlement-advice XML import (well-formed, no DTD)
curl -s -b $J -X POST $PS/import -H 'content-type: application/xml' \
  --data-binary '<advice><memo>settlement ok</memo></advice>'     # -> advice accepted; memo=settlement ok

#   sign-on page with a flash notice
curl -s -G $PS/login --data-urlencode 'notice=WelcomeBack'        # HTML contains WelcomeBack
```

Seed data worth knowing: accounts `000000000042` / `000000000043` / `000000000044` (branch `0007`,
USD, active), `000000000045` (closed), `000000000099` (frozen, for rejection paths), `000000000077`
(branch `0014`); customer id `0000000007`; staff `TLR001` and `SUP001` (branch `0007`), `TLR014`
(branch `0014`, password `teller14-pw`).

---

## 3. Confirm there's nothing to exploit

The `legacy-goat-runtimes/triggers/` directory holds one proof-of-exploit per known vulnerability
class. On the **fixed** version every one of them is **inert**:

```bash
cd legacy-goat-runtimes
./triggers/run_trigger.sh --all     # or: make triggers
# fixed  -> all inert, exit 0.   (Run the same against the `vulnerable` deployment and they FIRE.)
./triggers/run_trigger.sh LG-XSS-001   # one proof, with what the stack answered
```

`make verify APP_PROFILE=permissive` runs the whole matrix and asserts each trigger fires **iff** the
ground truth says it should — a clean way to score the fixed vs vulnerable deployments.

---

## 4. Happy path is identical on both versions

The point of the benchmark is that a real vulnerable app is unaware of its own flaw and behaves
exactly like the fixed one until it is attacked. The benign happy-path suite proves it:

```bash
# against a running stack
make integration

# or deploy a version and run it in one step (APP_SRC under $HOME, not /tmp)
make run-integration APP_SRC=$HOME/…/lg-fixed        # fixed version     -> PASS
make run-integration APP_SRC=$HOME/…/lg-vulnerable   # vulnerable version -> PASS (identical)
```

`test/test_integration.py` touches every vulnerable section with legitimate input and asserts the
normal result. It never injects, overflows, or traverses anything, so it passes the same way on both.
`test/test_operations.py` covers the teller operations, which carry no planted flaw, including the
requests they must refuse. `test/test_replies.py` sends input a module accepts but that is not
ordinary, such as a GL reference holding control characters, and requires a valid JSON reply that
returns it intact; it is skipped while `PREFORMATTED_REFS` is on. The exploit proofs live in
`triggers/`:

| Suite                      | Input              | Vulnerable version | Fixed version   |
|----------------------------|--------------------|--------------------|-----------------|
| `test/test_integration.py` | benign             | PASS (normal)      | PASS (normal)   |
| `test/test_operations.py`  | benign and refused | PASS               | PASS            |
| `test/test_replies.py`     | unusual, accepted  | PASS               | PASS            |
| `triggers/LG-*.py`         | malicious          | FIRE (exploited)   | inert (blocked) |

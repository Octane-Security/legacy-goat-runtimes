"""Teller operations: account inquiry, account statement, cash deposit and withdrawal, and account holds.

Through the gateway and through the console's HTML pages. Asserts the rules each operation enforces
(role, home branch, account status, positive amounts, funds, the cash limit), that the console
escapes what it echoes, and that sign-off ends the session. Every change the suite makes is undone
before it finishes, so it runs the same on every branch and profile.

The tests run in file order: like a teller's session, later checks rely on what earlier ones did
(an account frozen, then unfrozen; a deposit, then a withdrawal). Run the module whole.
Env: GATEWAY_URL, PASCAL_URL, COBOL_URL.
"""

from __future__ import annotations

from decimal import Decimal

import pytest

from harness import env, http

TELLER = {"X-Staff-Id": "TLR001", "X-Role": "TELLER", "X-Branch": "0007"}
SUPER = {"X-Staff-Id": "SUP001", "X-Role": "SUPERVISOR", "X-Branch": "0007"}
ACCT = "000000000044"    # branch 0007, ACTIVE: cash and holds run against it
OTHER = "000000000077"   # branch 0014
FROZEN = "000000000099"  # branch 0007, FROZEN in the seed
CLOSED = "000000000045"  # branch 0007, CLOSED in the seed
TOKEN = "OPERATIONSTEST01"


def gateway(path: str, body: dict, headers: dict | None = None):
    return http.post_json(f"{env.url('GATEWAY_URL')}{path}", body, headers=headers)


def inquiry(account: str, headers: dict | None = TELLER) -> dict:
    return gateway("/inquiry", {"token": TOKEN, "account_id": account}, headers).json()


def statement(account: str, headers: dict | None = TELLER) -> dict:
    return gateway("/statement", {"token": TOKEN, "account_id": account}, headers).json()


def cash(action: str, account: str, amount: str, currency: str = "USD") -> dict:
    return gateway("/cash", {"token": TOKEN, "account_id": account, "action": action,
                             "amount": amount, "currency": currency}, TELLER).json()


def hold(action: str, account: str, headers: dict) -> dict:
    return gateway("/maintenance", {"token": TOKEN, "account_id": account, "action": action}, headers).json()


def balance(account: str) -> str:
    return http.text(inquiry(account).get("balance"))


def console_form(client: http.Client, path: str, headers: dict | None = None, **fields: str):
    return client.post(f"{env.url('PASCAL_URL')}{path}", data=fields, headers=headers)


# ---- account inquiry ----

def test_inquiry_own_branch_account_shows_holder_type_status_balance():
    d = inquiry("000000000042")
    assert (d["result"] == "OK" and d["customer_name"] == "ACME WIDGETS LLC" and d["account_type"] == "CHK"
            and d["status"] == "ACTIVE" and d["branch"] == "0007" and "balance" in d), d


def test_inquiry_other_branch_refused_and_shows_nothing():
    d = inquiry(OTHER)
    assert (d["result"] == "REJECTED" and d["reason"] == "OUT OF BRANCH SCOPE"
            and "balance" not in d and "customer_name" not in d), d


def test_inquiry_unknown_account():
    d = inquiry("000000000001")
    assert d["result"] == "REJECTED" and d["reason"] == "ACCOUNT NOT FOUND", d


def test_inquiry_unknown_role_refused():
    d = inquiry("000000000042", {"X-Staff-Id": "TLR001", "X-Role": "AUDITOR", "X-Branch": "0007"})
    assert d["result"] == "REJECTED" and d["reason"] == "ROLE NOT PERMITTED", d


def test_inquiry_without_actor_is_unauthorized():
    assert gateway("/inquiry", {"token": TOKEN, "account_id": "000000000042"}).status_code == 401


# ---- cash deposit and withdrawal ----

@pytest.fixture(scope="module")
def start_balance() -> str:
    """ACCT's balance before the suite touches it; the suite ends with it restored."""
    value = balance(ACCT)
    assert value, f"no starting balance for {ACCT}"
    return value


@pytest.fixture(scope="module")
def deposit(start_balance) -> dict:
    return cash("DEPOSIT", ACCT, "25.00")


@pytest.fixture(scope="module")
def withdrawal(deposit) -> dict:
    return cash("WITHDRAW", ACCT, "25.00")


def test_deposit_posts_credits_and_books_gl(deposit):
    d = deposit
    assert (d["status"] == "POSTED" and d["cash_account"] == "990000000007"
            and d.get("gl_doc_id", "").startswith("GL")), d


def test_deposit_report_has_two_balanced_lines(deposit):
    lines = sorted((r["account_id"], r["direction"], r["amount"]) for r in deposit["report"])
    assert lines == [("000000000044", "C", "25.00"), ("990000000007", "D", "25.00")], deposit


def test_deposit_balance_rose(start_balance, deposit):
    assert Decimal(http.text(deposit.get("balance"))) == Decimal(start_balance) + Decimal("25.00"), deposit


def test_statement_newest_line_is_the_deposit(deposit):
    d = statement(ACCT)
    newest = d["lines"][0]
    assert (d["result"] == "OK" and newest["transfer_id"] == http.text(deposit.get("transfer_id"))
            and newest["direction"] == "C" and newest["amount"] == "25.00"
            and newest["balance_after"] == d["balance"] and len(d["lines"]) <= 10), d


def test_statement_other_branch_refused():
    d = statement(OTHER)
    assert d["result"] == "REJECTED" and d["reason"] == "OUT OF BRANCH SCOPE" and d["lines"] == [], d


def test_withdrawal_posts_and_debits(withdrawal):
    d = withdrawal
    directions = sorted((r["account_id"], r["direction"]) for r in d["report"])
    assert (d["status"] == "POSTED" and d.get("gl_doc_id", "").startswith("GL")
            and directions == [("000000000044", "D"), ("990000000007", "C")]), d


def test_withdrawal_restores_balance(start_balance, withdrawal):
    assert http.text(withdrawal.get("balance")) == start_balance, withdrawal


def test_statement_running_balance_walks_back(deposit, withdrawal):
    d = statement(ACCT)
    newest, previous = d["lines"][0], d["lines"][1]
    assert (newest["description"] == "CASH WITHDRAWAL"
            and previous["transfer_id"] == http.text(deposit.get("transfer_id"))
            and previous["balance_after"] == str(Decimal(newest["balance_after"]) + Decimal("25.00"))), d


def test_withdrawal_over_balance_refused(start_balance):
    d = cash("WITHDRAW", ACCT, str(Decimal(start_balance) + Decimal("1.00")))
    assert d["status"] == "REJECTED" and d["reason"] == "INSUFFICIENT FUNDS" and "gl_doc_id" not in d, d


@pytest.mark.parametrize(
    "action, account, amount, currency, reason",
    [
        pytest.param("DEPOSIT", ACCT, "0.00", "USD", "AMOUNT MUST BE POSITIVE", id="deposit-zero"),
        pytest.param("DEPOSIT", ACCT, "-5.00", "USD", "AMOUNT MUST BE POSITIVE", id="deposit-negative"),
        pytest.param("WITHDRAW", ACCT, "-5.00", "USD", "AMOUNT MUST BE POSITIVE", id="withdrawal-negative"),
        pytest.param("DEPOSIT", ACCT, "10000.00", "USD", "OVER TELLER CASH LIMIT", id="deposit-over-counter-limit"),
        pytest.param("DEPOSIT", FROZEN, "5.00", "USD", "ACCOUNT NOT ACTIVE", id="deposit-frozen-account"),
        pytest.param("DEPOSIT", OTHER, "5.00", "USD", "OUT OF BRANCH SCOPE", id="deposit-other-branch"),
        pytest.param("DEPOSIT", ACCT, "5.00", "EUR", "CURRENCY MISMATCH", id="deposit-currency-mismatch"),
    ],
)
def test_cash_refused(action, account, amount, currency, reason):
    d = cash(action, account, amount, currency)
    assert d["reason"] == reason, d


@pytest.mark.parametrize("action", ["TRANSFER", "DEPOSIT "])
def test_cash_gateway_refuses_unknown_action(action):
    reply = gateway("/cash", {"token": TOKEN, "account_id": ACCT, "action": action, "amount": "5.00",
                              "currency": "USD"}, TELLER)
    assert reply.status_code == 400


def test_cash_core_refuses_unknown_action():
    d = http.post_json(
        f"{env.url('COBOL_URL')}/cash",
        {"transfer_id": "TOPSTEST000000001", "account_id": ACCT, "action": "TRANSFER", "amount": "5.00",
         "currency": "USD", "actor": {"staff_id": "TLR001", "role": "TELLER", "branch": "0007"}},
    ).json()
    assert d["status"] == "REJECTED" and d["reason"] == "UNKNOWN CASH ACTION", d


def test_cash_refusals_left_balance(start_balance, withdrawal):
    assert balance(ACCT) == start_balance


# ---- account holds ----

def test_hold_teller_cannot_freeze():
    d = hold("FREEZE", ACCT, TELLER)
    assert d["result"] == "REJECTED" and d["reason"] == "SUPERVISOR ROLE REQUIRED", d


def test_hold_supervisor_freezes_active_account():
    d = hold("FREEZE", ACCT, SUPER)
    assert d["result"] == "OK" and d["status"] == "FROZEN", d


def test_hold_frozen_account_takes_no_cash():
    assert cash("DEPOSIT", ACCT, "5.00")["reason"] == "ACCOUNT NOT ACTIVE"


def test_hold_freezing_twice_refused():
    d = hold("FREEZE", ACCT, SUPER)
    assert d["result"] == "REJECTED" and d["reason"] == "ACCOUNT NOT ACTIVE" and d["status"] == "FROZEN", d


def test_hold_supervisor_unfreezes():
    d = hold("UNFREEZE", ACCT, SUPER)
    assert d["result"] == "OK" and d["status"] == "ACTIVE", d


def test_hold_unfreezing_active_account_refused():
    d = hold("UNFREEZE", ACCT, SUPER)
    assert d["result"] == "REJECTED" and d["reason"] == "ACCOUNT NOT FROZEN", d


def test_hold_closed_account_stays_closed():
    d = hold("FREEZE", CLOSED, SUPER)
    assert d["result"] == "REJECTED" and d["status"] == "CLOSED", d


def test_hold_other_branch_refused_and_shows_no_status():
    d = hold("FREEZE", OTHER, SUPER)
    assert d["result"] == "REJECTED" and d["reason"] == "OUT OF BRANCH SCOPE" and "status" not in d, d


def test_hold_unknown_action_refused():
    d = hold("CLOSE", ACCT, SUPER)
    assert d["result"] == "REJECTED" and d["reason"] == "UNKNOWN MAINTENANCE ACTION", d


# ---- console pages ----

@pytest.fixture(scope="module")
def teller_console():
    """A teller's console sign-on: the client holding the session, and the sign-on reply."""
    return http.console_sign_on(env.url("PASCAL_URL"), "TLR001", "teller-pw")


@pytest.fixture(scope="module")
def supervisor_console() -> http.Client:
    client, _ = http.console_sign_on(env.url("PASCAL_URL"), "SUP001", "super-pw")
    return client


@pytest.fixture(scope="module")
def teller_signed_off(teller_console):
    """Signs the teller off. Returns the session token held before, and the sign-off reply."""
    client, _ = teller_console
    token = client.cookies.get("lgsession")
    return token, client.post(f"{env.url('PASCAL_URL')}/logout")


def test_console_teller_lands_on_main_menu_without_holds(teller_console):
    page = teller_console[1].text
    assert "Teller Main Menu" in page and 'href="/deposit"' in page and 'href="/maintenance"' not in page


def test_console_session_cookie_is_httponly_and_samesite_strict(teller_console):
    cookies = "\n".join(http.set_cookie_headers(teller_console[1])).lower()
    assert "samesite=strict" in cookies and "httponly" in cookies, cookies


def test_console_inquiry_page_shows_holder_and_type(teller_console):
    client, _ = teller_console
    page = client.get(f"{env.url('PASCAL_URL')}/inquiry", params={"account_id": "000000000042"}).text
    assert "ACME WIDGETS LLC" in page and "Checking" in page


def test_console_inquiry_echoes_bad_account_escaped(teller_console):
    client, _ = teller_console
    page = client.get(f"{env.url('PASCAL_URL')}/inquiry", params={"account_id": "<b>x</b>"}).text
    assert "&lt;b&gt;x&lt;/b&gt;" in page and "<b>x</b>" not in page


def test_console_deposit_form_prints_receipt(teller_console):
    page = console_form(teller_console[0], "/deposit", account_id=ACCT, amount="10.00", currency="USD").text
    assert "Cash Deposit Receipt" in page and "POSTED" in page


def test_console_withdrawal_form_prints_receipt(teller_console):
    page = console_form(teller_console[0], "/withdraw", account_id=ACCT, amount="10.00", currency="USD").text
    assert "Cash Withdrawal Receipt" in page and "POSTED" in page


def test_console_deposit_form_refuses_negative_amount(teller_console):
    page = console_form(teller_console[0], "/deposit", account_id=ACCT, amount="-1.00", currency="USD").text
    assert "more than zero" in page


def test_console_cross_origin_deposit_refused(teller_console, start_balance):
    reply = console_form(teller_console[0], "/deposit", headers={"Origin": "http://elsewhere.example"},
                         account_id=ACCT, amount="10.00", currency="USD")
    assert reply.status_code == 403 and "Request refused" in reply.text and balance(ACCT) == start_balance


def test_console_same_origin_withdrawal_posts(teller_console):
    client, _ = teller_console
    page = console_form(client, "/withdraw", headers={"Origin": env.url("PASCAL_URL")},
                        account_id=ACCT, amount="0.01", currency="USD").text
    console_form(client, "/deposit", account_id=ACCT, amount="0.01", currency="USD")  # put the cent back
    assert "POSTED" in page


def test_console_pages_not_cached(teller_console):
    client, _ = teller_console
    reply = client.get(f"{env.url('PASCAL_URL')}/statement", params={"account_id": ACCT})
    assert "no-store" in reply.headers.get("cache-control", "").lower(), reply.headers.get("cache-control")


def test_console_statement_page_lists_postings(teller_console):
    client, _ = teller_console
    page = client.get(f"{env.url('PASCAL_URL')}/statement", params={"account_id": ACCT}).text
    assert "CASH WITHDRAWAL" in page


def test_console_hold_page_offers_teller_no_form(teller_console):
    client, _ = teller_console
    page = client.get(f"{env.url('PASCAL_URL')}/maintenance").text
    assert "need a supervisor sign-on" in page and "name=action" not in page


def test_console_teller_hold_post_changes_nothing(teller_console):
    console_form(teller_console[0], "/maintenance", account_id=ACCT, action="FREEZE")
    assert http.text(inquiry(ACCT).get("status")) == "ACTIVE"


def test_console_supervisor_freezes_through_hold_form(supervisor_console):
    page = console_form(supervisor_console, "/maintenance", account_id=ACCT, action="FREEZE").text
    assert "is now FROZEN" in page


def test_console_supervisor_unfreezes_through_hold_form(supervisor_console):
    page = console_form(supervisor_console, "/maintenance", account_id=ACCT, action="UNFREEZE").text
    assert "is now ACTIVE" in page


def test_console_sign_off_clears_session_cookie(teller_signed_off):
    _, reply = teller_signed_off
    assert "You have signed off" in reply.text and "1970" in "\n".join(http.set_cookie_headers(reply))


def test_console_signed_off_token_no_longer_opens_menu(teller_signed_off):
    token, _ = teller_signed_off
    if http.text(token).startswith("LG"):
        return  # a roaming token outlives its session, by setting (SESSION_ROAMING=on)
    page = http.get(f"{env.url('PASCAL_URL')}/menu", headers={"Cookie": f"lgsession={http.text(token)}"}).text
    assert "Staff Sign-On" in page, "the signed-off token still opens the menu"


def test_console_deposit_without_session_goes_to_sign_on():
    page = http.post(f"{env.url('PASCAL_URL')}/deposit",
                     data={"account_id": ACCT, "amount": "10.00", "currency": "USD"}).text
    assert "Staff Sign-On" in page


def test_account_restored(start_balance):
    """ACCT ends ACTIVE at its starting balance, as it started."""
    assert balance(ACCT) == start_balance and http.text(inquiry(ACCT).get("status")) == "ACTIVE"

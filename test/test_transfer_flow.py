"""The transfer flow through the gateway, end to end.

Staff authentication (COBOL), an atomic double-entry post with persisted balances (COBOL, SQL and
VSAM), a fee (Fortran), a posting report (SAS) and a GL document (ABAP), and the short-circuits: a
rejected transfer reaches none of the downstream modules.

The checks are state-independent (double-entry deltas across two posts, and structure), so the suite
passes on `main`, `vulnerable` and `fixed`, where the happy path is identical. The tests run in file
order and share the first transfer. Env: GATEWAY_URL.
"""

from __future__ import annotations

from decimal import Decimal

import pytest

from harness import env, http

# Staff and accounts from the seed (db/postgres/seed.sql, db/vsam/seed/accounts.psv).
STAFF_ID, PASSWORD, ROLE, BRANCH = "TLR001", "teller-pw", "TELLER", "0007"
FROM, TO, FROZEN = "000000000042", "000000000043", "000000000099"
REQUESTED_BY, CURRENCY, AMOUNT = "0000000007", "USD", "100.00"  # a seeded DL/I customer (customers.dat)
ACTOR = {"X-Staff-Id": STAFF_ID, "X-Role": ROLE, "X-Branch": BRANCH}


def transfer_body(from_account: str = FROM, requested_by: str = REQUESTED_BY) -> dict:
    return {"token": "INTEGRATIONTESTTOK", "from_account": from_account, "to_account": TO,
            "amount": AMOUNT, "currency": CURRENCY, "requested_by": requested_by}


def post_transfer(body: dict, headers: dict | None = ACTOR):
    return http.post_json(f"{env.url('GATEWAY_URL')}/transfer", body, headers=headers)


@pytest.fixture(scope="module")
def first_transfer() -> dict:
    return post_transfer(transfer_body()).json()


def test_gateway_healthy():
    assert http.get(f"{env.url('GATEWAY_URL')}/healthz").text.rstrip("\n") == "ok"


def test_authenticate():
    reply = http.post_json(f"{env.url('GATEWAY_URL')}/authenticate",
                           {"staff_id": STAFF_ID, "password": PASSWORD}).json()
    assert reply.get("authenticated") is True, reply
    assert reply.get("role") == ROLE, reply
    assert reply.get("branch") == BRANCH, reply


def test_authenticate_rejects_wrong_password():
    reply = http.post_json(f"{env.url('GATEWAY_URL')}/authenticate",
                           {"staff_id": STAFF_ID, "password": "wrong-pw"}).json()
    assert reply.get("authenticated") is False, reply


def test_transfer_posts_end_to_end(first_transfer):
    """COBOL, then Fortran, SAS and ABAP."""
    t = first_transfer
    assert t.get("status") == "POSTED", t
    assert http.text(t.get("from_balance")) and http.text(t.get("to_balance")), f"missing balances: {t}"
    assert http.text(t.get("fee")), f"missing fee (Fortran): {t}"
    assert len(t.get("report", [])) >= 2, f"report under 2 rows (SAS): {t}"
    keyed = sum(1 for row in t.get("report", []) if row.get("transfer_id") == t.get("transfer_id"))
    assert keyed >= 2, f"report rows not keyed to transfer_id: {t}"
    assert http.text(t.get("gl_doc_id", "")).startswith("GL"), f"missing GL document (ABAP): {t}"


def test_double_entry_persisted(first_transfer):
    """A second transfer moves the from balance down and the to balance up by the amount."""
    second = post_transfer(transfer_body()).json()
    assert second.get("status") == "POSTED", second
    amount = Decimal(AMOUNT)
    fb1, tb1 = Decimal(first_transfer["from_balance"]), Decimal(first_transfer["to_balance"])
    fb2, tb2 = Decimal(second["from_balance"]), Decimal(second["to_balance"])
    assert fb2 == fb1 - amount, f"from {fb1}->{fb2} != -{amount}"
    assert tb2 == tb1 + amount, f"to {tb1}->{tb2} != +{amount}"


def test_rejected_transfer_short_circuits():
    """A frozen source account never reaches Fortran, SAS or ABAP."""
    reply = post_transfer(transfer_body(from_account=FROZEN)).json()
    assert reply.get("status") == "REJECTED", reply
    assert http.text(reply.get("reason")), f"reject without a reason: {reply}"
    assert not http.text(reply.get("gl_doc_id")), f"reject with a GL document: {reply}"
    assert len(reply.get("report", [])) == 0, f"reject with a report: {reply}"


def test_dli_rejects_unknown_customer():
    """The DL/I customer check (CBLTDLI GU) rejects an unknown initiating customer."""
    reply = post_transfer(transfer_body(requested_by="9999999999")).json()
    assert reply.get("status") == "REJECTED", reply
    assert reply.get("reason") == "CUSTOMER NOT FOUND", reply


def test_transfer_without_actor_is_unauthorized():
    assert post_transfer(transfer_body(), headers=None).status_code == 401

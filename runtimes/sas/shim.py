#!/usr/bin/env python3
"""SAS runtime shim.

There is no real SAS engine here. This mimics what sas/postrpt.sas does: resolve its macro vars
by textual substitution and forward the PROC SQL EXPLICIT pass-through block to the real engine
(Postgres, not Db2 -- see legacy-goat-runtimes/runtimes/README.md and compose/compose.yaml) as-is.
Keep REMOTE_SQL_TEMPLATE in sync with the `select ... from connection to postgres (...)` block in
sas/postrpt.sas.

Record layouts: legacy-goat/contracts/records/sas-report-io.md. Money form:
legacy-goat/contracts/data-model.md. Driver: psycopg (v3).
"""
import os
import re
import subprocess
import sys
from decimal import Decimal, ROUND_HALF_UP

import psycopg

REQUEST_LEN = 48
ROW_LEN = 92

TRANSFER_ID_RE = re.compile(r"^[A-Z0-9]{1,20}$")
REPORT_TYPES = {"POSTING", "SETTLE"}
AS_OF_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


# The shim mirrors the MOUNTED sas/postrpt.sas: a vuln path is taken only when that source still
# carries the vulnerable construct. So the `vulnerable`/`main` source behaves config-gated as before,
# while the `fixed` source (constructs removed) is inert regardless of config -- the shim faithfully
# reflects whatever SAS job it is serving instead of hardcoding the behavior.
SAS_SOURCE = os.environ.get("SAS_SOURCE", "/app-src/sas/postrpt.sas")


def _sas_src():
    try:
        with open(SAS_SOURCE, errors="surrogateescape") as f:
            return f.read()
    except OSError:
        return ""  # unreadable -> treat as fixed (safe default)


def _source_sqli_vulnerable():
    # vulnerable source gates the as_of contract check on as_of_dates; the fix drops that wrapper.
    return "%upcase(&as_of_dates) ne ON" in _sas_src()


def _source_export_vulnerable():
    # vulnerable source splices the label into %sysexec UNQUOTED (`to &export_label;`); the fix quotes
    # it (`to "&export_label";`), which no longer matches this marker.
    return "to &export_label;" in _sas_src()


def as_of_dates():
    """The as_of_dates path (LG-SQLI-002) is live only when the setting is on AND the mounted source
    still skips the as_of check (i.e. the vulnerable, not the fixed, postrpt.sas)."""
    on = os.environ.get("AS_OF_DATES", "off").strip().lower() == "on"
    return on and _source_sqli_vulnerable()

# Mirrors the `select ... from connection to postgres (...)` block in sas/postrpt.sas. Real SAS
# resolves &transfer_id. / &as_of. by textual substitution before shipping the block to the remote
# engine verbatim -- EXPLICIT pass-through has no bind-variable syntax, so this shim does the same
# substitution here via .format(). transfer_id and as_of are validated (validate()) and single-quote
# escaped (sql_quote()) before they reach this template; that validation/escaping is what keeps this
# template safe. Drop it, or splice in a different, unchecked value, and this .format() call becomes
# the pass-through SQL injection point.
REMOTE_SQL_TEMPLATE = """
    select posting_id, transfer_id, account_id, direction, amount, currency, posted_at
    from ledger
    where transfer_id = '{transfer_id}'
      and posted_at <= '{as_of}'
    order by posted_at, posting_id
"""


def read_request():
    """Parse one REPORT-REQUEST record (48 chars): transfer_id 1-20, report_type 21-28, as_of 29-48."""
    raw = sys.stdin.readline()
    if not raw:
        return None
    rec = raw.rstrip("\n").rstrip("\r")
    rec = rec.ljust(REQUEST_LEN)
    transfer_id = rec[0:20].strip()
    report_type = rec[20:28].strip()
    as_of = rec[28:48].strip()
    return transfer_id, report_type, as_of


def validate(transfer_id, report_type, as_of):
    """Contract-shape checks -- the guard that keeps the pass-through interpolation below safe."""
    if not TRANSFER_ID_RE.match(transfer_id):
        raise ValueError(f"transfer_id {transfer_id!r} fails contract pattern ^[A-Z0-9]{{1,20}}$")
    if report_type not in REPORT_TYPES:
        raise ValueError(f"report_type {report_type!r} is not POSTING or SETTLE")
    # [LG-SQLI-002 CWE-89] with as_of_dates on the report skips the as_of contract check, so an unvalidated
    # as_of reaches build_remote_sql() and (with escaping also skipped there) breaks out of the
    # pass-through literal. transfer_id is still validated, so the injection rides in via as_of.
    if not as_of_dates() and not AS_OF_RE.match(as_of):
        raise ValueError(f"as_of {as_of!r} is not a contract timestamp")


def sql_quote(value):
    """Mirrors SAS's own quoting for a literal embedded in pass-through text: doubled single quotes."""
    return value.replace("'", "''")


def build_remote_sql(transfer_id, as_of):
    # With as_of_dates on, as_of is spliced raw (no quote-doubling) -> pass-through SQL injection.
    as_of_sql = as_of if as_of_dates() else sql_quote(as_of)
    return REMOTE_SQL_TEMPLATE.format(
        transfer_id=sql_quote(transfer_id),
        as_of=as_of_sql,
    )


def fmt_money(amount):
    """contracts/data-model.md: optional '-', digits, '.', 2 fraction digits, right-justified into
    16 columns, space-padded on the left -- equivalent to SAS's PUT(amount, 16.2)."""
    q = Decimal(amount).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return f"{q:.2f}".rjust(16)


def fmt_row(posting_id, transfer_id, account_id, direction, amount, currency, posted_at):
    line = (
        str(posting_id).ljust(20)[:20]
        + str(transfer_id).ljust(20)[:20]
        + str(account_id).ljust(12)[:12]
        + str(direction).ljust(1)[:1]
        + fmt_money(amount)
        + str(currency).ljust(3)[:3]
        + str(posted_at).ljust(20)[:20]
    )
    assert len(line) == ROW_LEN, f"REPORT-ROW length {len(line)} != {ROW_LEN}"
    return line


def connect():
    return psycopg.connect(
        host=os.environ["SQL_HOST"],
        dbname=os.environ["SQL_DBNAME"],
        user=os.environ["SQL_USER"],
        password=os.environ["SQL_PASSWORD"],
        port=5432,
    )


def run_export():
    """Mirror the %SYSEXEC export in sas/postrpt.sas (LG-CMDI-001). The export label is read from
    stdin and, when report pass-through is enabled, spliced into a shell command line unquoted --
    exactly as %SYSEXEC would, so a crafted label runs an arbitrary OS command. With pass-through
    off the label is inert (no shell)."""
    label = sys.stdin.readline().rstrip("\n").rstrip("\r")
    # The archival itself is gated by report_archive; how the label is handled mirrors the mounted
    # source. For a BENIGN label the archival output is identical either way (same echo), so the happy
    # path is indistinguishable -- only a shell-metacharacter label diverges (injected vs literal).
    archive = os.environ.get("REPORT_ARCHIVE", "off").strip().lower() == "on"
    if not archive:
        sys.stdout.write(f"export disabled; label={label}\n")
        return
    if _source_export_vulnerable():
        # vulnerable source: label spliced into the shell command line unquoted -> command injection
        result = subprocess.run(f"echo archiving posting report to {label}",
                                shell=True, capture_output=True, text=True)
    else:
        # fixed source: the label is passed as a single literal argument (no shell), so metacharacters
        # are inert; a benign label produces the exact same archival line.
        result = subprocess.run(["echo", f"archiving posting report to {label}"],
                                capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stdout.write(result.stderr)


def main():
    req = read_request()
    if req is None:
        return
    transfer_id, report_type, as_of = req
    validate(transfer_id, report_type, as_of)
    remote_sql = build_remote_sql(transfer_id, as_of)

    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(remote_sql)
            rows = cur.fetchall()

    for row in rows:
        sys.stdout.write(fmt_row(*row) + "\n")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "export":
        run_export()
    else:
        main()

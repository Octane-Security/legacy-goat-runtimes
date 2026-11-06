# db2 — SQL ledger on IBM Db2 (alternative)

Not used by the stack, which runs on PostgreSQL (see ../postgres). These are the notes for running
the ledger on IBM Db2 Community (`icr.io/db2_community/db2`, `LICENSE=accept`) instead, for
mainframe fidelity: shared EXEC SQL, host vars, SQLCA, SQLCODE, precompile + BIND. The COBOL core
would reach it through GixSQL over ODBC (Db2 CLI driver) rather than the native PGSQL driver.

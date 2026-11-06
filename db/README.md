# db

The three storage interfaces the COBOL core uses.

| Store | Kind | Runtime |
|---|---|---|
| postgres | SQL ledger (EXEC SQL) | PostgreSQL 16, the one network service (:5432). COBOL reaches it via GixSQL's native PGSQL driver |
| vsam | indexed account master (VSAM/ISAM) | GnuCOBOL `ORGANIZATION INDEXED` over Berkeley DB 5.3, local to the COBOL container |
| imsdli | hierarchical customer segments (IMS DL/I) | CBLTDLI emulation shim over a hierarchical store, local to the COBOL container |

PostgreSQL runs the SQL ledger; [db2/](db2/) describes running it on IBM Db2 Community instead,
behind the same contracts.

Each subdirectory holds the engine/emulator config and the seed data, which conforms to the
copybooks in `legacy-goat/contracts/copybook/`.

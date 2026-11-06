# postgres — SQL ledger

PostgreSQL 16 (`docker.io/library/postgres:16`). `schema.sql` creates the tables on first start:
`ledger` (`legacy-goat/contracts/copybook/ledger-posting.cpy`), `transfers`, `staff` and
`account_maintenance`; `seed.sql` adds the staff. The ledger begins empty and the COBOL core inserts
rows via GixSQL precompiled EXEC SQL over the native PGSQL driver. A changed schema or seed applies
only to a new volume: `make clean` drops it. [../db2](../db2) describes running the ledger on Db2
instead.

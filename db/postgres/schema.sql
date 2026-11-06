-- SQL ledger. One row per debit/credit line; columns mirror
-- legacy-goat/contracts/copybook/ledger-posting.cpy. Starts empty; the COBOL core inserts rows.
CREATE TABLE IF NOT EXISTS ledger (
    posting_id   VARCHAR(20)   PRIMARY KEY,
    transfer_id  VARCHAR(20)   NOT NULL,
    account_id   VARCHAR(12)   NOT NULL,
    direction    CHAR(1)       NOT NULL CHECK (direction IN ('D', 'C')),
    amount       NUMERIC(15,2) NOT NULL,
    currency     VARCHAR(3)    NOT NULL,
    posted_at    VARCHAR(20)   NOT NULL,
    description  VARCHAR(40),
    line_no      BIGSERIAL     NOT NULL  -- insert order; statements list lines by it
);

CREATE INDEX IF NOT EXISTS ledger_transfer_idx ON ledger (transfer_id);
CREATE INDEX IF NOT EXISTS ledger_account_idx ON ledger (account_id, line_no);

-- Staff principals (staff.cpy). The COBOL core reads this to authenticate and resolve role + branch.
CREATE TABLE IF NOT EXISTS staff (
    staff_id   VARCHAR(10) PRIMARY KEY,
    name       VARCHAR(40) NOT NULL,
    role       VARCHAR(10) NOT NULL CHECK (role IN ('TELLER', 'SUPERVISOR')),
    branch     VARCHAR(4)  NOT NULL,
    pw_hash    VARCHAR(64) NOT NULL,
    status     VARCHAR(8)  NOT NULL DEFAULT 'ACTIVE'
);

-- Transfer lifecycle (transfer-record.cpy). Distinct from the per-line LEDGER; tracks state and the
-- maker/checker identities across the approval flow.
CREATE TABLE IF NOT EXISTS transfers (
    transfer_id  VARCHAR(20)   PRIMARY KEY,
    from_account VARCHAR(12)   NOT NULL,
    to_account   VARCHAR(12)   NOT NULL,
    amount       NUMERIC(15,2) NOT NULL,
    currency     VARCHAR(3)    NOT NULL,
    status       VARCHAR(10)   NOT NULL CHECK (status IN ('PENDING', 'POSTED', 'REVERSED', 'REJECTED')),
    initiator    VARCHAR(10)   NOT NULL,
    approver     VARCHAR(10),
    created_at   VARCHAR(20)   NOT NULL,
    decided_at   VARCHAR(20)
);

-- Account maintenance log: one row per freeze or unfreeze, written by the COBOL core.
CREATE TABLE IF NOT EXISTS account_maintenance (
    maint_id     SERIAL        PRIMARY KEY,
    account_id   VARCHAR(12)   NOT NULL,
    action       VARCHAR(8)    NOT NULL CHECK (action IN ('FREEZE', 'UNFREEZE')),
    staff_id     VARCHAR(10)   NOT NULL,
    performed_at VARCHAR(20)   NOT NULL
);

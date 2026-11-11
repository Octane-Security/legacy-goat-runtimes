# test

The integration test harness. Drives the transfer flow against the running stack and asserts
correct balances, a generated posting report, and a GL document. The happy path is identical on
all three branches (vulns do not break normal operation), so the same test passes on `main`,
`vulnerable`, and `fixed`.

- `run.sh` — the transfer flow through the gateway: authentication, a double-entry post with persisted
  balances, the fee, the posting report and the GL document, and the short-circuits.
- `operations.sh` — the teller operations (account inquiry, statement, cash deposit and withdrawal,
  account holds) through the gateway and the console, with the rules each enforces. It restores every
  account it touches.
- `integration.sh` — benign input through every vulnerable section; passes the same on `vulnerable`
  and `fixed`.
- `replies.sh` — input a module accepts but that is not ordinary must still get a valid JSON reply: a
  GL reference holding control characters comes back escaped and intact. Skipped while
  `PREFORMATTED_REFS` is on (`make replies APP_PROFILE=<profile>`).
- `verify.sh` — `run.sh`, `operations.sh` and `replies.sh`, then every trigger against the manifest's
  grades for the profile (`make verify APP_PROFILE=<profile>`).

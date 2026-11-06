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
- `verify.sh` — `run.sh` and `operations.sh`, then every trigger against the manifest's grades for
  the profile (`make verify APP_PROFILE=<profile>`).

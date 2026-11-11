# test

The test suites, written with [pytest](https://docs.pytest.org/). They drive the running stack and
assert correct balances, a generated posting report, a GL document, the teller operations' rules and
well-formed replies. The happy path is identical on all three branches (the planted flaws do not
break normal operation), so the same suites pass on `main`, `vulnerable` and `fixed`.

- `test_transfer_flow.py` — the transfer flow through the gateway: authentication, a double-entry
  post with persisted balances, the fee, the posting report and the GL document, and the
  short-circuits.
- `test_operations.py` — the teller operations (account inquiry, statement, cash deposit and
  withdrawal, account holds) through the gateway and the console, with the rules each enforces. It
  restores every account it touches, and its tests run in order, like a teller's session.
- `test_integration.py` — benign input through every section that holds a planted flaw; passes the
  same on `vulnerable` and `fixed`.
- `test_replies.py` — input a module accepts but that is not ordinary must still get a valid JSON
  reply: a GL reference holding control characters comes back escaped and intact. Skipped while
  `PREFORMATTED_REFS` is on.
- `test_exploitability.py` — every proof in `../triggers/` against the answer key's grades for the
  profile: each fires if and only if its instance is graded exploitable. Run it against the
  `vulnerable` tree.

Each suite has a wrapper script that runs it, and passes any extra arguments on to pytest:

| Script | Runs | Make target |
|---|---|---|
| `run.sh` | `test_transfer_flow.py` | `make test` |
| `integration.sh` | `test_integration.py` | `make integration` |
| `operations.sh` | `test_operations.py` | `make operations` |
| `replies.sh` | `test_replies.py` | `make replies APP_PROFILE=<profile>` |
| `verify.sh` | the transfer flow, operations and replies, then `test_exploitability.py` | `make verify APP_PROFILE=<profile>` |
| `run-integration.sh` | deploys `APP_SRC`, then `test_integration.py` | `make run-integration APP_SRC=<tree>` |

`verify.sh` waits up to 180 seconds for the gateway, and with `COMPOSE_CMD` set (the `make verify`
target sets it) recreates the stack under the profile first. To run pytest directly, from the
repository root:

```
uv run pytest test/test_operations.py -k inquiry      # one suite, the checks matching a name
uv run pytest --deploy --stack-timeout 180 test/      # recreate under APP_PROFILE, wait, run everything
```

The environment selects the stack and the answer key: `APP_PROFILE` (default `baseline`), `APP_DIR`
(the legacy-goat checkout, default `../legacy-goat`), `APP_SRC` (the tree `--deploy` mounts), and
`GATEWAY_URL`, `COBOL_URL`, `FORTRAN_URL`, `SAS_URL`, `PASCAL_URL` and `ABAP_URL` (default: the
published ports on `localhost`). The shared code is in `../harness/`.

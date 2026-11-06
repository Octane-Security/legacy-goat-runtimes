# profiles — named config bundles for scoring runs

A **profile** is a named bundle of config values selected with
`APP_PROFILE`. The same app source (`APP_BRANCH`) runs under each profile; what changes is the
config the modules read, which flips whether a given `LG-...` instance is actually *exploitable*.
This is how the benchmark scores reachability, not just pattern presence: a good scanner changes its
exploitability verdict when the profile changes.

Each profile is an env file `profiles/<name>.env` layered on top of `compose/.env`
(`make up APP_PROFILE=<name>` / `make verify APP_PROFILE=<name>`). Its keys are threaded into the
services by `compose/compose.yaml`; the mapping of a key to the sink that reads it:

| Key | Read by | config.schema.json | baseline | permissive | Gates |
|---|---|---|---|---|---|
| `SESSION_ROAMING` | cobol (staffauth), pascal | `session_roaming` | off | on | LG-SQLI-001 (single-query sign-on), LG-AUTH-001 (roaming token) |
| `HOME_BRANCH_ONLY` | cobol (postxfer) | `home_branch_only` | on | off | LG-AC-001 (branch-scope check; `off` skips it) |
| `ALNUM_CUSTOMER_IDS` | cobol (postxfer) | `alnum_customer_ids` | off | on | LG-DLII-001 (DL/I SSA built without the numeric check) |
| `EXTENDED_TIERS` | cobol (postxfer) | `extended_tiers` | off | on | LG-MEM-001 (unclamped tier subscript) |
| `REPORT_ARCHIVE` | sas (postrpt + shim), gateway (unused) | `report_archive` | off | on | LG-CMDI-001 (%SYSEXEC archive label) |
| `AS_OF_DATES` | sas (postrpt + shim) | `as_of_dates` | off | on | LG-SQLI-002 (as_of check skipped) |
| `PREFORMATTED_REFS` | abap (as header `x-preformatted-refs`, set by `runtimes/abap/server.mjs`) | `preformatted_refs` | off | on | LG-INJ-001 (reference not escaped) |
| `RECEIPT_SUBFOLDERS` | pascal | `receipt_subfolders` | off | on | LG-PATH-001 (receipt name not reduced to a basename) |
| `SIGNON_TRACE` | pascal | `signon_trace` | off | on | LG-LOG-001 (password in the sign-on log line) |
| `PARTNER_PREVIEW` | pascal | `partner_preview` | off | on | LG-SSRF-001 (no gateway prefix check) |
| `CORRESPONDENT_ADVICES` | pascal | `correspondent_advices` | off | on | LG-XXE-001 (inline DTDs accepted) |
| `RICH_NOTICES` | pascal | `rich_notices` | off | on | LG-XSS-001 (notice rendered unescaped) |
| `REQUIRE_APPROVAL_OVER` | gateway -> cobol | `require_approval_over` | 10000.00 | 10000.00 | PENDING threshold (keeps large amounts off the posting path) |
| `SESSION_TTL` | pascal | `session_ttl` | 900 | 900 | store-token lifetime |

Setting names describe the feature, never the risk: they reach the blind branches through the app
source, so the same no-clue rule applies to them as to any identifier (see legacy-goat
`tooling/clues.py`). On/off settings read `on`/`off`; unset means the app default.

The per-instance grade under each profile is answer-key material in
`legacy-goat/benchmark/manifest.yaml`; the profile **name here must match the grade key there**
(e.g. `baseline`, `permissive`) so `ground-truth.<profile>.sarif` and `make verify` line up.

## Standard profiles
- **baseline** — safe config across the board; most instances are present-but-unexploitable
  (reachability hard-negatives). The default.
- **permissive** — risk-on config; the config-gated instances become exploitable.

Every profile runs on the same seed data.

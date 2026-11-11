# legacy-goat-runtimes

The runtime harness for [Legacy Goat](https://github.com/Octane-Security/legacy-goat), the
intentionally vulnerable legacy-language banking application: per-language runtime images, the C/C++
middleware that fronts each module over REST, the databases, the orchestration, the test suites, and
the per-vulnerability exploit proofs and scoring tools.

This repository expects `legacy-goat` checked out as a sibling directory (`../legacy-goat`). The
stack mounts the app source read-only and compiles it at container start. Nothing here is part of
what a scanner is pointed at, so it is free to name the planted flaws.

## Layout

```
runtimes/{cobol,fortran,pascal,sas,abap}/   per-language runtime images
middleware/adapters/{cobol,fortran,pascal,sas,abap}/   C/C++ adapters (REST <-> native per module)
middleware/gateway/                          C/C++ REST router + flow orchestrator
db/{postgres,vsam,imsdli,db2}/                SQL ledger, indexed-file store, hierarchical emulator + seed
compose/                                     compose.yaml + .env (APP_BRANCH selector)
profiles/                                    per-profile settings (see profiles/README.md)
tooling/                                     ground-truth SARIF, alignment check, scorer
triggers/                                    per-vulnerability exploit proofs (Python) and run_trigger.sh
test/                                        pytest suites: acceptance, teller operations, integration, replies,
                                             the exploitability matrix; a shell wrapper for each
harness/                                     shared Python for the suites and proofs: service URLs, HTTP, stack
docs/                                        how to drive the app; the attacker position the grades assume
```

## Running the stack

You need a compose provider (Docker's compose plugin, or Podman with `podman compose`, which you can
get with `uv tool install podman-compose`), plus [uv](https://docs.astral.sh/uv/), which runs the
tests and exploit proofs with the dependencies pinned in `pyproject.toml` and `uv.lock`. The
`Makefile` picks whichever compose provider is installed, and `make config` reports which one it
found.

```
make up-build APP_PROFILE=permissive   # build the images (the COBOL one compiles GixSQL) and start
make test                              # transfer flow: balances, fee, report, GL document
make operations                        # teller operations and the rules they enforce
make verify APP_PROFILE=permissive     # recreate under the profile, run the suites, then every trigger
make triggers                          # run every exploit proof once: FIRED or inert
make down
```

The suites are pytest modules in `test/`, and the scripts beside them are wrappers that pass their
arguments on to pytest, so one check runs by name: `./test/operations.sh -k inquiry`. A single proof
runs with `./triggers/run_trigger.sh LG-AC-001`.

The console is then at <http://localhost:8085/> (`TLR001` / `teller-pw`, or the supervisor `SUP001` /
`super-pw`) and the gateway at <http://localhost:8080/>. [docs/exercising-the-app.md](docs/exercising-the-app.md)
drives every feature from the browser and from `curl`.

`APP_BRANCH` is one of `main`, `vulnerable`, `fixed` (`make checkout APP_BRANCH=fixed` switches
`../legacy-goat`), and `APP_SRC=<path>` deploys any other checkout or generated tree. Because the
blind branches differ only by the `vulnerable`↔`fixed` diff, give a scanner one blind branch at a
time; scoring reads `main`.

## Build mechanism

Each language service builds from its `runtimes/<lang>/Dockerfile` with the repo root as the build
context (so a Dockerfile can reach its adapter under `middleware/`). The module source is
bind-mounted read-only from `../legacy-goat/<module>` and compiled by the container entrypoint at
start, so switching `APP_BRANCH` needs a re-checkout, not a rebuild. PostgreSQL is the one database
service; the indexed-file (VSAM/ISAM) store and the IMS DL/I emulator are libraries local to the
COBOL container, seeded from `db/` at every start.

## Profiles and scoring

`profiles/baseline.env` turns the gating settings off and `profiles/permissive.env` turns them on;
[profiles/README.md](profiles/README.md) maps each setting to the instance it gates. `make verify`
asserts that each trigger fires exactly when the answer key grades its instance exploitable under the
profile. `make ground-truth`, `make check-alignment` and `make score SCANNER=<sarif>` regenerate the
ground-truth SARIF, prove it still points at its constructs, and score a scanner against it; see
[tooling/README.md](tooling/README.md).

## Attacker position

The answer key's grades assume an attacker with direct access to the gateway and every module port
(the lab publishes them all). [docs/attacker-position.md](docs/attacker-position.md) lists, per
instance, the position each trigger uses and the weakest one that reaches the sink. Graders and the
instructions given to a scanner must state the same position.

## Contributing

Octane Security maintains this harness and [Legacy Goat](https://github.com/Octane-Security/legacy-goat),
and we welcome pull requests from the security community. New exploit proofs, runtime and tooling
improvements, and fixes to anything that breaks all help make Legacy Goat better for everyone. Open
pull requests against `main`, and run `make verify` under both profiles before you do. A new planted
flaw spans both repositories: its code and answer-key entry go to legacy-goat, and its proof goes
here as `triggers/<id>.py`.

## License

Copyright (C) 2026 Octane Security. GNU General Public License, version 3; see [LICENSE](LICENSE).
The vendored `middleware/common/vendor/httplib.h` (cpp-httplib) and `json.hpp` (nlohmann/json) are
MIT-licensed by their authors; their notices are in the files.

#!/usr/bin/env bash
# Deploys an app version and runs the happy-path suite (test_integration.py) against it, to prove the
# vulnerable and fixed versions behave the same on benign input:
#   APP_SRC=<checkout-or-tree> ./test/run-integration.sh
# APP_SRC must be a path the container runtime can bind-mount (on macOS podman: under $HOME, not
# /tmp). APP_PROFILE defaults to permissive here, the interesting case: the vulnerable version runs
# its actual vulnerable code and must still match the fixed version. Extra arguments go to pytest.
: "${APP_SRC:?set APP_SRC to the app checkout or tree to deploy}"
export APP_PROFILE="${APP_PROFILE:-permissive}" APP_BRANCH=main
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec uv run --quiet --project "$ROOT" pytest -v --deploy --stack-timeout 360 "$ROOT/test/test_integration.py" "$@"

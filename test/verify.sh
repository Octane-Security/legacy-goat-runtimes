#!/usr/bin/env bash
# The scoring run for one profile (APP_PROFILE): the transfer flow, the teller operations and the
# reply checks, then every trigger against the manifest's grades (test_exploitability.py, answer key
# from APP_DIR). Waits up to 180 s for the gateway first. With COMPOSE_CMD set, as the Makefile's
# `verify` target sets it, the stack is (re)created under the profile first, from APP_SRC when set.
# Extra arguments go to pytest.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec uv run --quiet --project "$ROOT" pytest -v --stack-timeout 180 ${COMPOSE_CMD:+--deploy} \
  "$ROOT/test/test_transfer_flow.py" "$ROOT/test/test_operations.py" "$ROOT/test/test_replies.py" \
  "$ROOT/test/test_exploitability.py" "$@"

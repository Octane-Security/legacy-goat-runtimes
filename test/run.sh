#!/usr/bin/env bash
# The transfer flow through the gateway: authentication, a double-entry post, the fee, the posting
# report, the GL document and the short-circuits. The checks are in test_transfer_flow.py; extra
# arguments go to pytest. Needs the stack up.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec uv run --quiet --project "$ROOT" pytest -v "$ROOT/test/test_transfer_flow.py" "$@"

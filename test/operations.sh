#!/usr/bin/env bash
# The teller operations (inquiry, statement, cash, holds) through the gateway and the console, with
# the rules each enforces. The checks are in test_operations.py; extra arguments go to pytest. Needs
# the stack up.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec uv run --quiet --project "$ROOT" pytest -v "$ROOT/test/test_operations.py" "$@"

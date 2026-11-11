#!/usr/bin/env bash
# The happy path through every section that holds a planted flaw: benign input, normal results, the
# same on `vulnerable` and `fixed`. The checks are in test_integration.py; extra arguments go to
# pytest. Needs the stack up.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec uv run --quiet --project "$ROOT" pytest -v "$ROOT/test/test_integration.py" "$@"

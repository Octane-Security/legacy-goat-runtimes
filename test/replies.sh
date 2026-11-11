#!/usr/bin/env bash
# Replies to unusual but accepted input stay valid JSON (GL references with control characters),
# under APP_PROFILE. The checks are in test_replies.py; extra arguments go to pytest. Needs the stack up.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec uv run --quiet --project "$ROOT" pytest -v "$ROOT/test/test_replies.py" "$@"

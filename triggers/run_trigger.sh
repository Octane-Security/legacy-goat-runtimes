#!/usr/bin/env bash
# Runs exploit proofs against the running stack. The proofs are the Python files beside this one.
#   ./triggers/run_trigger.sh LG-AC-001   # exit 0 fired, 1 not fired, 2 could not run
#   ./triggers/run_trigger.sh --all       # FIRED or inert per proof; exit 0 only if none fired
#   ./triggers/run_trigger.sh --list
cd "$(dirname "$0")/.." && exec uv run --quiet python -m harness.triggers "$@"

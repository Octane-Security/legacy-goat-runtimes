#!/usr/bin/env bash
set -euo pipefail
# Regenerate benchmark/ground-truth.<profile>.sarif from benchmark/manifest.yaml.
# APP_DIR = path to the legacy-goat (main) checkout that holds benchmark/. Uses uv for pyyaml.
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${APP_DIR:-$HERE/../../legacy-goat}"
MANIFEST="$APP_DIR/benchmark/manifest.yaml"
OUT_DIR="$APP_DIR/benchmark"
uv run --quiet --with pyyaml python3 "$HERE/gen_ground_truth.py" "$MANIFEST" "$OUT_DIR"

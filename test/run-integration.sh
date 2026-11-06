#!/usr/bin/env bash
set -euo pipefail
# Bring up the stack on a given app version and run the benign happy-path integration suite. Use it to
# prove the `vulnerable` and `fixed` versions are indistinguishable on the happy path.
#
#   APP_SRC=<checkout-or-tree> ./test/run-integration.sh
#
# APP_SRC is the app source to deploy (a checkout of the vulnerable/fixed branch, or a generated tree).
# It MUST be a path the container runtime can bind-mount (on macOS podman: under $HOME, not /tmp).
# APP_PROFILE defaults to permissive -- the interesting case, where the vulnerable version is running
# its actual vulnerable code and must still match the fixed version on these benign inputs.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP_SRC="${APP_SRC:?set APP_SRC to the app checkout/tree to deploy}"
APP_PROFILE="${APP_PROFILE:-permissive}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"

echo "[run-integration] deploying APP_SRC=$APP_SRC under $APP_PROFILE"
# APP_SRC must be passed INLINE (compose reads it from the process env for interpolation; a prior
# `export` through an intermediate variable does not reliably reach the provider on podman).
APP_SRC="$APP_SRC" APP_BRANCH=main podman compose \
  -f "$ROOT/compose/compose.yaml" --env-file "$ROOT/compose/.env" \
  --env-file "$ROOT/profiles/$APP_PROFILE.env" up -d --force-recreate

echo "[run-integration] waiting for gateway"
for _ in $(seq 1 120); do [ "$(curl -sS "$GATEWAY_URL/healthz" 2>/dev/null || true)" = "ok" ] && break; sleep 3; done
[ "$(curl -sS "$GATEWAY_URL/healthz" 2>/dev/null || true)" = "ok" ] || { echo "gateway not healthy" >&2; exit 1; }

GATEWAY_URL="$GATEWAY_URL" "$HERE/integration.sh"

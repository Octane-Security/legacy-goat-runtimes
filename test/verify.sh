#!/usr/bin/env bash
set -euo pipefail
# Standardized scoring run for one profile. Ensures the stack is up under APP_PROFILE, runs the
# happy-path acceptance test, then runs every per-vuln trigger and asserts each fires IFF the manifest
# grades that instance `exploitable` under this profile. This is how reachability is checked end to
# end: flip the profile and the same triggers must change their fire/inert verdict to match the map.
#
# Env: APP_PROFILE (default baseline), APP_DIR (path to the legacy-goat checkout that holds the answer
# key), APP_SRC (optional: the app tree to deploy, e.g. a generated blind tree), GATEWAY_URL
# (default http://localhost:8080). COMPOSE_CMD (optional): the full compose command, already carrying
# the profile env-file; when set, the stack is (re)created under the profile first. The Makefile
# `verify` target passes it. Without it, the stack is assumed already up under APP_PROFILE.

APP_PROFILE="${APP_PROFILE:-baseline}"
APP_DIR="${APP_DIR:-../legacy-goat}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$APP_DIR/benchmark/manifest.yaml"
TRIGGERS_DIR="$HERE/../triggers"

echo "[verify] profile=$APP_PROFILE  manifest=$MANIFEST"

if [ -n "${COMPOSE_CMD:-}" ]; then
  echo "[verify] (re)creating stack under $APP_PROFILE${APP_SRC:+ from $APP_SRC}"
  # APP_SRC (a generated tree) goes inline on the compose command; podman compose needs it there.
  if [ -n "${APP_SRC:-}" ]; then
    APP_SRC="$APP_SRC" $COMPOSE_CMD up -d --force-recreate >/dev/null 2>&1 \
      || APP_SRC="$APP_SRC" $COMPOSE_CMD up -d >/dev/null 2>&1 || true
  else
    $COMPOSE_CMD up -d --force-recreate >/dev/null 2>&1 || $COMPOSE_CMD up -d >/dev/null 2>&1 || true
  fi
fi

echo "[verify] waiting for gateway"
for _ in $(seq 1 60); do
  [ "$(curl -sS "$GATEWAY_URL/healthz" 2>/dev/null || true)" = "ok" ] && break
  sleep 3
done
[ "$(curl -sS "$GATEWAY_URL/healthz" 2>/dev/null || true)" = "ok" ] \
  || { echo "[verify] gateway not healthy at $GATEWAY_URL" >&2; exit 1; }

# 1) Happy path and teller operations — identical on every branch/profile — then the reply checks.
echo "[verify] --- happy-path acceptance ---"
GATEWAY_URL="$GATEWAY_URL" "$HERE/run.sh"
echo "[verify] --- teller operations ---"
GATEWAY_URL="$GATEWAY_URL" "$HERE/operations.sh"
echo "[verify] --- reply checks ---"
APP_PROFILE="$APP_PROFILE" "$HERE/replies.sh"

# 2) Per-vuln trigger matrix vs the manifest grades for this profile.
echo "[verify] --- exploitability matrix ($APP_PROFILE) ---"
grades="$(uv run --quiet --with pyyaml python3 - "$MANIFEST" "$APP_PROFILE" <<'PY'
import sys, yaml
manifest, profile = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(manifest)) or {}
for e in doc.get("entries", []):
    g = (e.get("exploitability", {}) or {}).get(profile)
    status = g.get("status", "unexploitable") if isinstance(g, dict) else "unexploitable"
    detection = e.get("detection", "runtime")  # static-only entries carry no runtime trigger
    print(f"{e['id']}\t{status}\t{detection}")
PY
)"

fails=0
while IFS=$'\t' read -r id status detection; do
  [ -z "$id" ] && continue
  # Static-only findings (e.g. hardcoded secrets) have no reachability path and no trigger; they are
  # scored by static ground truth, so the runtime matrix just records their presence and moves on.
  if [ "$detection" = "static" ]; then
    echo "  stat  $id  static-only ($status, no runtime trigger)"; continue
  fi
  trig="$TRIGGERS_DIR/$id.sh"
  if [ ! -x "$trig" ]; then
    echo "  MISS  $id: no runnable trigger at $trig"; fails=$((fails + 1)); continue
  fi
  if GATEWAY_URL="$GATEWAY_URL" "$trig" >/dev/null 2>&1; then fired=yes; else fired=no; fi
  if   [ "$status" = "exploitable" ]   && [ "$fired" = "yes" ]; then echo "  ok    $id  exploitable & FIRED"
  elif [ "$status" = "unexploitable" ] && [ "$fired" = "no"  ]; then echo "  ok    $id  unexploitable & inert"
  else echo "  FAIL  $id  manifest=$status fired=$fired"; fails=$((fails + 1)); fi
done <<< "$grades"

if [ "$fails" -gt 0 ]; then
  echo "[verify] $fails mismatch(es) under profile $APP_PROFILE" >&2; exit 1
fi
echo "[verify] PASS - profile $APP_PROFILE matches ground truth"

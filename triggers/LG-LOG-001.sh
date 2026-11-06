#!/usr/bin/env bash
set -euo pipefail
# LG-LOG-001 proof-of-exploit: the console audit path writes the cleartext password to its process
# log (CWE-532). Posts a sign-on attempt with a unique password marker, then reads the console
# container log and fires (exit 0) when the marker password appears -- only possible with
# signon_trace=on. With the fix only the staff id + outcome are logged, so the marker never shows and
# this stays inert. Reads the log via `podman logs` (the realistic proof for a log-exposure finding).
# Env: PASCAL_URL (default http://localhost:8085), PASCAL_CONTAINER (default legacy-goat_pascal_1),
#      CONTAINER_CLI (default podman).

PASCAL_URL="${PASCAL_URL:-http://localhost:8085}"
PASCAL_CONTAINER="${PASCAL_CONTAINER:-legacy-goat_pascal_1}"
CONTAINER_CLI="${CONTAINER_CLI:-podman}"
MARK="LGLOG-pw-$$-$RANDOM"

curl -sS -X POST "$PASCAL_URL/login" \
  --data-urlencode 'staff_id=LGLOG001' --data-urlencode "password=$MARK" >/dev/null

# The audit line is flushed to StdErr synchronously; poll the log briefly to avoid a race.
for _ in $(seq 1 10); do
  if "$CONTAINER_CLI" logs "$PASCAL_CONTAINER" 2>&1 | grep -q "password=$MARK"; then
    echo "LG-LOG-001 FIRED: cleartext password leaked to the console log (marker $MARK)"
    exit 0
  fi
  sleep 1
done

echo "LG-LOG-001 not fired: marker $MARK not found in $PASCAL_CONTAINER log" >&2
exit 1

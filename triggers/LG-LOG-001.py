"""LG-LOG-001 proof-of-exploit: the console audit path writes the cleartext password to its log.

Posts a sign-on attempt with a unique password marker, then reads the console container's log and
fires when the marker password appears, which is only possible with signon_trace=on. With the fix
only the staff id and the outcome are logged, so the marker never shows and this stays inert. Reads
the log with `podman logs` (the realistic proof for a log-exposure finding).
Env: PASCAL_URL, PASCAL_CONTAINER (default legacy-goat_pascal_1), CONTAINER_CLI (default podman).
"""

import os
import random
import subprocess
import time

from harness import env, http


def fire():
    container = env.setting("PASCAL_CONTAINER", "legacy-goat_pascal_1")
    cli = env.setting("CONTAINER_CLI", "podman")
    mark = f"LGLOG-pw-{os.getpid()}-{random.randrange(32768)}"
    http.post(f"{env.url('PASCAL_URL')}/login", data={"staff_id": "LGLOG001", "password": mark})
    # The audit line is flushed to StdErr synchronously; poll the log briefly to avoid a race.
    for _ in range(10):
        log = subprocess.run([cli, "logs", container], capture_output=True, text=True, errors="replace")
        if f"password={mark}" in log.stdout + log.stderr:
            return True, f"cleartext password leaked to the console log (marker {mark})"
        time.sleep(1)
    return False, f"marker {mark} not found in {container} log"

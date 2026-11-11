"""Reply checks: input that a module accepts, but that is not ordinary, still gets a valid JSON reply
that matches what was sent.

GL service (direct POST /gl): a reference holding control characters (U+0000 to U+001F, sent as raw
bytes) must come back in a reply that a strict JSON parser accepts, with the reference decoding to
the same characters. This applies when the GL service escapes references, which is always except
when PREFORMATTED_REFS is on (it is on under `permissive`); with it on, the service writes the
reference as it arrives, and the LG-INJ-001 trigger covers that path.

Env: ABAP_URL, APP_PROFILE (selects profiles/<profile>.env), PREFORMATTED_REFS (default: read from
that profile file).
"""

from __future__ import annotations

import json

import pytest

from harness import env, http

LINES = ('"lines":[{"account_id":"1000","direction":"D","amount":"1.00"},'
         '{"account_id":"2000","direction":"C","amount":"1.00"}]')
CASES = {
    "raw line feed": "T1\nX",
    "raw tab": "T1\tX",
    "every control character": "".join(chr(c) for c in range(32)),
}


@pytest.fixture(scope="module", autouse=True)
def references_escaped(profile):
    preformatted = env.setting("PREFORMATTED_REFS", "") or env.profile_setting("PREFORMATTED_REFS", profile)
    if preformatted == "on":
        pytest.skip("PREFORMATTED_REFS=on: references are written as they arrive")


@pytest.mark.parametrize("reference", list(CASES.values()), ids=list(CASES))
def test_gl_reply_is_valid_json_and_reference_round_trips(reference):
    body = ('{"reference":"%s",%s}' % (reference, LINES)).encode("utf-8")
    raw = http.post_json(f"{env.url('ABAP_URL')}/gl", body).content
    try:
        reply = json.loads(raw.decode("utf-8"))
    except ValueError as error:
        pytest.fail(f"reply is not valid JSON ({error}): {raw[:120]!r}")
    assert reply.get("reference") == reference, f"reference came back as {reply.get('reference')!r}"

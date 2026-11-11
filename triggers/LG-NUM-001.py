"""LG-NUM-001 proof-of-exploit: integer overflow in the fee calculation.

Asks the Fortran fee service for the fee on a large CHK amount. Fires when the returned fee is NOT
amount*0.001 (the 32-bit nint overflowed and wrapped). With the kind=8 fix the fee is correct and
this stays inert. Data-gated by the amount, so it fires under any profile. Hits the Fortran service
directly. Env: FORTRAN_URL.
"""

from decimal import Decimal

from harness import env, http

AMOUNT = "90000000000.00"  # 9e10; amount*0.001*100 = 9e9 cents >> int32 max (~2.1e9)


def fire():
    reply = http.post_json(
        f"{env.url('FORTRAN_URL')}/compute-fee",
        {"transfer_id": "TNUM01", "amount": AMOUNT, "currency": "USD", "account_type": "CHK",
         "term_days": 0, "rate_code": "STD"},
    )
    fee = reply.json().get("fee")
    expected = (Decimal(AMOUNT) * Decimal("0.001")).quantize(Decimal("0.01"))
    if fee is None or Decimal(fee) != expected:
        return True, f"fee overflowed -> fee={fee} expected={expected} (reply: {reply.text})"
    return False, f"fee={fee} expected={expected}"

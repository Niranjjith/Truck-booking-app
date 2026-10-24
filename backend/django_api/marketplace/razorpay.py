import base64
import hashlib
import hmac
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


RAZORPAY_API = "https://api.razorpay.com/v1"


class RazorpayError(Exception):
    pass


def _request(method, path, *, key_id, key_secret, payload=None):
    token = base64.b64encode(f"{key_id}:{key_secret}".encode()).decode("ascii")
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = Request(
        f"{RAZORPAY_API}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": f"Basic {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urlopen(request, timeout=15) as response:
            result = json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
        raise RazorpayError("Razorpay request failed. No payment was confirmed.") from error
    if not isinstance(result, dict):
        raise RazorpayError("Razorpay returned an invalid response.")
    return result


def create_order(transaction, *, key_id, key_secret):
    amount_paise = int(transaction.amount * 100)
    if amount_paise <= 0:
        raise RazorpayError("Payment amount must be at least one paise.")
    result = _request(
        "POST",
        "/orders",
        key_id=key_id,
        key_secret=key_secret,
        payload={
            "amount": amount_paise,
            "currency": transaction.currency,
            "receipt": transaction.id,
            "notes": {
                "booking_id": transaction.booking_id,
                "payment_transaction_id": transaction.id,
            },
        },
    )
    if (
        not isinstance(result.get("id"), str)
        or result.get("amount") != amount_paise
        or result.get("currency") != transaction.currency
    ):
        raise RazorpayError("Razorpay returned an order that does not match the payment.")
    return result


def verify_payment(
    *,
    order_id,
    payment_id,
    signature,
    expected_amount,
    currency,
    key_id,
    key_secret,
):
    expected_signature = hmac.new(
        key_secret.encode("utf-8"),
        f"{order_id}|{payment_id}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(expected_signature, signature):
        raise RazorpayError("Razorpay payment signature is invalid.")

    payment = _request(
        "GET",
        f"/payments/{payment_id}",
        key_id=key_id,
        key_secret=key_secret,
    )
    if (
        payment.get("status") != "captured"
        or payment.get("order_id") != order_id
        or payment.get("amount") != expected_amount
        or payment.get("currency") != currency
    ):
        raise RazorpayError(
            "Razorpay has not confirmed the expected captured payment."
        )
    return payment

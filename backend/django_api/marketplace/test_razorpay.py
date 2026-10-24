import hashlib
import hmac
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase

from .razorpay import RazorpayError, create_order, verify_payment


class RazorpayClientTests(SimpleTestCase):
    def test_order_uses_integer_minor_units_and_validates_gateway_response(self):
        transaction = SimpleNamespace(
            amount=Decimal("125.50"),
            currency="INR",
            id="transaction123",
            booking_id="booking123",
        )
        with patch(
            "marketplace.razorpay._request",
            return_value={"id": "order123", "amount": 12550, "currency": "INR"},
        ) as gateway_request:
            order = create_order(
                transaction,
                key_id="rzp_test_key",
                key_secret="test-secret",
            )

        self.assertEqual(order["id"], "order123")
        self.assertEqual(gateway_request.call_args.kwargs["payload"]["amount"], 12550)

    def test_rejects_invalid_signature_before_gateway_lookup(self):
        with patch("marketplace.razorpay._request") as gateway_request:
            with self.assertRaises(RazorpayError):
                verify_payment(
                    order_id="order123",
                    payment_id="payment123",
                    signature="incorrect",
                    expected_amount=12550,
                    currency="INR",
                    key_id="rzp_test_key",
                    key_secret="test-secret",
                )
        gateway_request.assert_not_called()

    def test_only_accepts_captured_payment_with_matching_order_amount_and_currency(self):
        secret = "test-secret"
        signature = hmac.new(
            secret.encode(),
            b"order123|payment123",
            hashlib.sha256,
        ).hexdigest()
        with patch(
            "marketplace.razorpay._request",
            return_value={
                "status": "captured",
                "order_id": "order123",
                "amount": 12550,
                "currency": "INR",
            },
        ):
            payment = verify_payment(
                order_id="order123",
                payment_id="payment123",
                signature=signature,
                expected_amount=12550,
                currency="INR",
                key_id="rzp_test_key",
                key_secret=secret,
            )
        self.assertEqual(payment["status"], "captured")

        with patch(
            "marketplace.razorpay._request",
            return_value={
                "status": "authorized",
                "order_id": "order123",
                "amount": 12550,
                "currency": "INR",
            },
        ):
            with self.assertRaises(RazorpayError):
                verify_payment(
                    order_id="order123",
                    payment_id="payment123",
                    signature=signature,
                    expected_amount=12550,
                    currency="INR",
                    key_id="rzp_test_key",
                    key_secret=secret,
                )

from datetime import timedelta
from unittest.mock import MagicMock, patch

import bcrypt
from django.contrib.auth.hashers import check_password
from django.core.management import call_command
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from .models import (
    Booking,
    Load,
    Notification,
    PaymentTransaction,
    Rating,
    Truck,
    User,
)


def register_user(name, phone, role):
    return User.objects.create_user(
        name=name,
        phone=phone,
        password="VioletTruck!7Strong",
        role=role,
        is_verified=True,
    )


@override_settings(
    PASSWORD_HASHERS=[
        "django.contrib.auth.hashers.MD5PasswordHasher",
        "marketplace.hashers.LegacyBcryptPasswordHasher",
    ]
)
class MarketplaceApiTests(TestCase):
    def setUp(self):
        self.customer = register_user("Load Owner", "+919876543210", User.Role.CUSTOMER)
        self.truck_owner = register_user("Truck Owner", "+919876543211", User.Role.TRUCK_OWNER)
        self.customer_client = APIClient()
        self.customer_client.force_authenticate(self.customer)
        self.truck_client = APIClient()
        self.truck_client.force_authenticate(self.truck_owner)
        self.load = None
        self.truck = None

    def make_load(self):
        response = self.customer_client.post(
            "/api/loads",
            {
                "pickup": {
                    "address": "Pickup depot",
                    "city": "Kochi",
                    "coordinates": [76.2711, 9.9312],
                },
                "delivery": {"address": "Delivery depot", "city": "Thrissur"},
                "loadType": "Building materials",
                "weightTons": 10,
                "requiredTruckType": "mini",
                "pickupDate": (timezone.now() + timedelta(days=2)).isoformat(),
                "price": 5000,
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.load = Load.objects.get(pk=response.data["load"]["id"])
        return self.load

    def make_truck(self, *, with_location=True):
        truck_body = {
            "registrationNumber": "TEST-TRUCK-1",
            "truckType": "mini",
            "capacityTons": 20,
            "description": "Integration test truck",
        }
        if with_location:
            truck_body["currentLocation"] = {
                "type": "Point",
                "coordinates": [76.2712, 9.9313],
            }
        response = self.truck_client.post("/api/trucks", truck_body, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.truck = Truck.objects.get(pk=response.data["truck"]["id"])
        return self.truck

    def test_health_and_protected_route(self):
        public_response = APIClient().get("/api/health")
        self.assertEqual(public_response.status_code, 200)
        self.assertEqual(public_response.data["status"], "ok")
        self.assertEqual(APIClient().get("/api/bookings").status_code, 401)

    def test_login_accepts_normalized_phone_and_email_identifier(self):
        self.truck_owner.email = "owner@example.com"
        self.truck_owner.set_password("Password123!")
        self.truck_owner.save(update_fields=["email", "password"])
        client = APIClient()

        phone_response = client.post(
            "/api/auth/login",
            {"phone": "0 98765-43211", "password": "Password123!"},
            format="json",
        )
        email_response = client.post(
            "/api/auth/login",
            {"phone": "OWNER@example.com", "password": "Password123!"},
            format="json",
        )

        self.assertEqual(phone_response.status_code, 200, phone_response.data)
        self.assertIn("token", phone_response.data)
        self.assertEqual(email_response.status_code, 200, email_response.data)
        self.assertIn("token", email_response.data)

    def test_login_returns_actionable_error_for_malformed_phone(self):
        response = APIClient().post(
            "/api/auth/login",
            {"phone": "not-a-phone", "password": "Password123!"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("valid phone number", response.data["message"])

    @override_settings(DEBUG=True, OTP_DEBUG_RETURN_CODE=True)
    def test_otp_registration_and_phone_verification(self):
        client = APIClient()
        result = client.post(
            "/api/auth/register",
            {
                "name": "New carrier",
                "phone": "9876543212",
                "password": "VioletTruck!7Strong",
                "role": "truckOwner",
            },
            format="json",
        )
        self.assertEqual(result.status_code, 201, result.data)
        self.assertTrue(result.data["otpRequired"])
        self.assertEqual(len(result.data["developmentOtp"]), 6)
        self.assertNotIn("token", result.data)

        verification = client.post(
            "/api/auth/otp/verify",
            {"phone": "+919876543212", "code": result.data["developmentOtp"]},
            format="json",
        )
        self.assertEqual(verification.status_code, 200, verification.data)
        self.assertIn("token", verification.data)
        self.assertTrue(User.objects.get(phone="+919876543212").is_verified)

    @override_settings(OTP_DEBUG_RETURN_CODE=False)
    def test_production_never_returns_the_verification_code(self):
        client = APIClient()
        with override_settings(DEBUG=False):
            result = client.post(
                "/api/auth/register",
                {
                    "name": "Unconfigured SMS user",
                    "phone": "+919876543219",
                    "password": "VioletTruck!7Strong",
                },
                format="json",
            )
        self.assertEqual(result.status_code, 503)
        self.assertNotIn("developmentOtp", result.data)
        self.assertFalse(User.objects.filter(phone="+919876543219").exists())

    def test_legacy_bcrypt_password_remains_valid(self):
        legacy_hash = bcrypt.hashpw(
            b"VioletTruck!7Strong", bcrypt.gensalt(rounds=12)
        ).decode("ascii")
        user = User.objects.create(
            name="Migrated owner",
            phone="+919876543218",
            password=f"bcrypt${legacy_hash}",
            role=User.Role.TRUCK_OWNER,
            is_verified=True,
        )
        self.assertTrue(check_password("VioletTruck!7Strong", user.password))

    def test_truck_without_gps_location_can_be_created(self):
        truck = self.make_truck(with_location=False)
        self.assertIsNone(truck.current_location)

    def test_owner_lists_include_only_the_signed_in_users_records(self):
        own_load = self.make_load()
        own_truck = self.make_truck(with_location=False)
        other_customer = register_user(
            "Another load owner", "+919876543212", User.Role.CUSTOMER
        )
        other_truck_owner = register_user(
            "Another truck owner", "+919876543213", User.Role.TRUCK_OWNER
        )
        other_load = Load.objects.create(
            owner=other_customer,
            pickup={"address": "Other pickup"},
            delivery={"address": "Other delivery"},
            load_type="Other freight",
            weight_tons=1,
            required_truck_type="mini",
            pickup_date=timezone.now() + timedelta(days=2),
            price=100,
            status=Load.Status.CANCELLED,
        )
        other_truck = Truck.objects.create(
            owner=other_truck_owner,
            registration_number="OTHER-TRUCK-1",
            truck_type="mini",
            capacity_tons=2,
        )

        loads = self.customer_client.get(
            "/api/loads?mine=true&includeClosed=true"
        )
        trucks = self.truck_client.get("/api/trucks?mine=true")

        self.assertEqual(loads.status_code, 200, loads.data)
        self.assertEqual(
            {load["id"] for load in loads.data["loads"]},
            {own_load.id},
        )
        self.assertEqual(trucks.status_code, 200, trucks.data)
        self.assertEqual(
            {truck["id"] for truck in trucks.data["trucks"]},
            {own_truck.id},
        )
        self.assertNotIn(other_load.id, {load["id"] for load in loads.data["loads"]})
        self.assertNotIn(
            other_truck.id, {truck["id"] for truck in trucks.data["trucks"]}
        )

    def test_owner_can_edit_load_and_truck_from_management_screens(self):
        load = self.make_load()
        truck = self.make_truck(with_location=False)

        load_update = self.customer_client.patch(
            f"/api/loads/{load.id}",
            {"price": 6200},
            format="json",
        )
        truck_update = self.truck_client.patch(
            f"/api/trucks/{truck.id}",
            {"isAvailable": False},
            format="json",
        )

        self.assertEqual(load_update.status_code, 200, load_update.data)
        self.assertEqual(str(load_update.data["load"]["price"]), "6200.00")
        self.assertEqual(truck_update.status_code, 200, truck_update.data)
        self.assertFalse(truck_update.data["truck"]["isAvailable"])

    @override_settings(GOOGLE_MAPS_API_KEY="google-test-key")
    @patch(
        "marketplace.views.compute_route",
        return_value={"distanceMeters": 12500, "durationSeconds": 1800},
    )
    def test_google_route_estimate_uses_server_key_and_validated_coordinates(self, compute):
        response = self.customer_client.post(
            "/api/routes/estimate",
            {
                "origin": [76.2711, 9.9312],
                "destination": [76.2095, 10.5276],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["distanceMeters"], 12500)
        self.assertEqual(response.data["durationSeconds"], 1800)
        compute.assert_called_once_with(
            [76.2711, 9.9312],
            [76.2095, 10.5276],
            "google-test-key",
        )

    @override_settings(GOOGLE_MAPS_API_KEY="")
    def test_google_route_estimate_without_a_key_fails_explicitly(self):
        response = self.customer_client.post(
            "/api/routes/estimate",
            {"origin": [76.2, 9.9], "destination": [76.3, 10.0]},
            format="json",
        )
        self.assertEqual(response.status_code, 503)

    @override_settings(
        PAYMENT_SANDBOX_ENABLED=False,
        RAZORPAY_KEY_ID="rzp_test_example",
        RAZORPAY_KEY_SECRET="rotated-test-secret",
    )
    @patch(
        "marketplace.views.create_order",
        return_value={"id": "order_test_123", "amount": 25000, "currency": "INR"},
    )
    def test_razorpay_checkout_and_server_verified_payment(self, create_order):
        self.make_load()
        self.make_truck(with_location=False)
        booking_response = self.truck_client.post(
            "/api/bookings",
            {"loadId": self.load.id, "truckId": self.truck.id},
            format="json",
        )
        booking_id = booking_response.data["booking"]["id"]

        checkout = self.truck_client.post(f"/api/bookings/{booking_id}/checkout")
        self.assertEqual(checkout.status_code, 200, checkout.data)
        self.assertEqual(checkout.data["provider"], "razorpay")
        self.assertEqual(checkout.data["orderId"], "order_test_123")
        self.assertEqual(checkout.data["amountPaise"], 25000)
        create_order.assert_called_once()
        repeated_checkout = self.truck_client.post(
            f"/api/bookings/{booking_id}/checkout"
        )
        self.assertEqual(repeated_checkout.status_code, 200)
        self.assertEqual(repeated_checkout.data["orderId"], "order_test_123")
        create_order.assert_called_once()

        with patch("marketplace.views.verify_payment") as verify_payment:
            verified = self.truck_client.post(
                f"/api/bookings/{booking_id}/payments/razorpay-verify",
                {
                    "razorpay_order_id": "order_test_123",
                    "razorpay_payment_id": "pay_test_456",
                    "razorpay_signature": "verified-by-gateway",
                },
                format="json",
            )
        self.assertEqual(verified.status_code, 200, verified.data)
        self.assertEqual(verified.data["booking"]["paymentStatus"], "paid")
        self.assertEqual(verified.data["booking"]["status"], "confirmed")
        verify_payment.assert_called_once()
        self.assertTrue(
            PaymentTransaction.objects.filter(
                booking_id=booking_id,
                provider="razorpay",
                provider_reference="pay_test_456",
                status=PaymentTransaction.Status.PAID,
            ).exists()
        )

    @override_settings(
        PAYMENT_SANDBOX_ENABLED=False,
        RAZORPAY_KEY_ID="rzp_test_example",
        RAZORPAY_KEY_SECRET="rotated-test-secret",
    )
    @patch("marketplace.views.verify_payment")
    def test_razorpay_rejects_an_order_not_created_for_the_booking(self, verify_payment):
        self.make_load()
        self.make_truck(with_location=False)
        booking_response = self.truck_client.post(
            "/api/bookings",
            {"loadId": self.load.id, "truckId": self.truck.id},
            format="json",
        )
        booking_id = booking_response.data["booking"]["id"]
        response = self.truck_client.post(
            f"/api/bookings/{booking_id}/payments/razorpay-verify",
            {
                "razorpay_order_id": "order_different",
                "razorpay_payment_id": "pay_test_456",
                "razorpay_signature": "invalid",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        verify_payment.assert_not_called()

    def test_nearby_matching_booking_payment_tracking_and_rating_flow(self):
        self.make_load()
        self.make_truck()

        match_response = self.truck_client.get("/api/loads/matches")
        self.assertEqual(match_response.status_code, 200, match_response.data)
        self.assertEqual(match_response.data["count"], 1)
        self.assertLess(match_response.data["distancesKm"][self.load.id], 1)

        detail_response = self.truck_client.get(f"/api/loads/{self.load.id}/matches")
        self.assertEqual(detail_response.status_code, 200, detail_response.data)
        self.assertEqual(detail_response.data["count"], 1)

        booking_response = self.truck_client.post(
            "/api/bookings",
            {"loadId": self.load.id, "truckId": self.truck.id},
            format="json",
        )
        self.assertEqual(booking_response.status_code, 201, booking_response.data)
        booking = Booking.objects.get(pk=booking_response.data["booking"]["id"])
        self.assertEqual(booking.status, Booking.Status.PENDING)
        self.assertEqual(booking.payment_status, Booking.PaymentStatus.PENDING)
        self.assertEqual(
            self.truck_client.patch(
                f"/api/bookings/{booking.id}/status",
                {"status": Booking.Status.CONFIRMED},
                format="json",
            ).status_code,
            400,
        )
        self.assertEqual(
            self.truck_client.post(f"/api/bookings/{booking.id}/checkout").status_code,
            503,
        )

        with override_settings(PAYMENT_SANDBOX_ENABLED=True):
            sandbox_checkout = self.truck_client.post(
                f"/api/bookings/{booking.id}/checkout"
            )
            self.assertTrue(sandbox_checkout.data["sandbox"])
            payment = self.truck_client.post(
                f"/api/bookings/{booking.id}/payments/sandbox-complete"
            )
        self.assertEqual(payment.status_code, 200, payment.data)
        booking.refresh_from_db()
        self.assertEqual(booking.payment_status, Booking.PaymentStatus.PAID)
        self.assertEqual(booking.status, Booking.Status.CONFIRMED)

        tracking = self.truck_client.patch(
            f"/api/bookings/{booking.id}/tracking",
            {"longitude": 76.3, "latitude": 9.95},
            format="json",
        )
        self.assertEqual(tracking.status_code, 200, tracking.data)

        for next_status in (
            Booking.Status.GOING_TO_PICKUP,
            Booking.Status.REACHED_PICKUP,
            Booking.Status.LOADING,
            Booking.Status.GOODS_PICKED_UP,
            Booking.Status.ON_THE_WAY,
            Booking.Status.NEAR_DELIVERY,
            Booking.Status.REACHED_DELIVERY,
            Booking.Status.DELIVERED,
            Booking.Status.COMPLETED,
        ):
            response = self.truck_client.patch(
                f"/api/bookings/{booking.id}/status",
                {"status": next_status},
                format="json",
            )
            self.assertEqual(response.status_code, 200, (next_status, response.data))

        rating = self.customer_client.post(
            f"/api/bookings/{booking.id}/ratings",
            {"score": 5, "review": "Excellent delivery"},
            format="json",
        )
        self.assertEqual(rating.status_code, 201, rating.data)
        duplicate = self.customer_client.post(
            f"/api/bookings/{booking.id}/ratings",
            {"score": 4},
            format="json",
        )
        self.assertEqual(duplicate.status_code, 400)
        self.load.refresh_from_db()
        self.truck.refresh_from_db()
        self.assertEqual(self.load.status, Load.Status.COMPLETED)
        self.assertTrue(self.truck.is_available)
        self.assertTrue(Notification.objects.filter(recipient=self.customer).exists())
        self.assertEqual(Rating.objects.filter(booking=booking).count(), 1)

    def test_booking_cancellation_releases_load_and_truck(self):
        self.make_load()
        self.make_truck()
        response = self.truck_client.post(
            "/api/bookings",
            {"loadId": self.load.id, "truckId": self.truck.id},
            format="json",
        )
        booking_id = response.data["booking"]["id"]
        cancelled = self.truck_client.patch(
            f"/api/bookings/{booking_id}/status",
            {"status": Booking.Status.CANCELLED},
            format="json",
        )
        self.assertEqual(cancelled.status_code, 200, cancelled.data)
        self.load.refresh_from_db()
        self.truck.refresh_from_db()
        self.assertEqual(self.load.status, Load.Status.SEARCHING)
        self.assertTrue(self.truck.is_available)


class MongoMigrationTests(TestCase):
    @patch("marketplace.management.commands.migrate_mongodb.MongoClient")
    def test_default_command_only_reports_record_counts(self, client_class):
        database = MagicMock()
        database.__getitem__.side_effect = lambda name: MagicMock(
            count_documents=lambda query: {
                "users": 1,
                "trucks": 0,
                "loads": 0,
                "bookings": 0,
            }[name]
        )
        client_class.return_value.__getitem__.return_value = database
        with patch("marketplace.management.commands.migrate_mongodb.settings.MONGODB_URI", "mongodb://example.test"):
            from io import StringIO

            output = StringIO()
            call_command("migrate_mongodb", stdout=output)
        self.assertIn("users: 1", output.getvalue())
        self.assertIn("Dry run only", output.getvalue())
        self.assertFalse(User.objects.exists())

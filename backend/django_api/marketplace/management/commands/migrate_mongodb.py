from datetime import datetime, timezone as datetime_timezone
from decimal import Decimal, InvalidOperation

from bson import ObjectId
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone
from pymongo import MongoClient

from marketplace.models import Booking, Load, Truck, User
from marketplace.views import normalize_phone


COLLECTIONS = ("users", "trucks", "loads", "bookings")


def parse_datetime(value, *, fallback=None):
    if isinstance(value, datetime):
        parsed = value
    elif value:
        try:
            parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError as error:
            raise CommandError("A MongoDB record contains an invalid timestamp.") from error
    else:
        parsed = fallback or timezone.now()
    if timezone.is_naive(parsed):
        return timezone.make_aware(parsed, datetime_timezone.utc)
    return parsed


def decimal_value(value, field, *, default="0"):
    try:
        return Decimal(str(default if value is None else value))
    except (InvalidOperation, TypeError, ValueError) as error:
        raise CommandError(f"A MongoDB {field} value is invalid.") from error


def object_id(value, field):
    if value is None:
        raise CommandError(f"A MongoDB record is missing its {field} relationship.")
    identifier = str(value)
    if len(identifier) != 24 or not ObjectId.is_valid(identifier):
        raise CommandError(f"A MongoDB {field} relationship is not a valid ObjectId.")
    return identifier


def normalize_legacy_password(encoded):
    if not encoded:
        return "!"
    if encoded.startswith(("bcrypt$", "$2a$", "$2b$", "$2y$")):
        raw = encoded.split("$", 1)[1] if encoded.startswith("bcrypt$") else encoded
        return f"bcrypt${raw}"
    return encoded


def normalized_location(value):
    if not isinstance(value, dict):
        return None
    coordinates = value.get("coordinates")
    if not isinstance(coordinates, (list, tuple)) or len(coordinates) != 2:
        return None
    try:
        longitude, latitude = map(float, coordinates)
    except (TypeError, ValueError):
        return None
    if not (-180 <= longitude <= 180 and -90 <= latitude <= 90):
        raise CommandError("A MongoDB truck location has coordinates outside the valid range.")
    return {"type": "Point", "coordinates": [longitude, latitude], **({"address": value["address"]} if value.get("address") else {})}


class Command(BaseCommand):
    help = "Safely migrate marketplace users, trucks, loads, and bookings from MongoDB."

    def add_arguments(self, parser):
        parser.add_argument(
            "--apply",
            action="store_true",
            help="Write records to PostgreSQL. Without this flag, only validates and counts source records.",
        )

    def handle(self, *args, **options):
        mongo_uri = settings.MONGODB_URI
        if not mongo_uri:
            raise CommandError("Set MONGODB_URI in the environment before migrating MongoDB data.")

        client = MongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
        try:
            client.admin.command("ping")
            database = client[settings.MONGODB_DATABASE]
            counts = {
                name: database[name].count_documents({})
                for name in COLLECTIONS
            }
            self.stdout.write(self.style.SUCCESS("MongoDB source counts:"))
            for collection, count in counts.items():
                self.stdout.write(f"  {collection}: {count}")

            if not options["apply"]:
                self.stdout.write(
                    self.style.WARNING(
                        "Dry run only: no PostgreSQL rows were written. Re-run with --apply after reviewing counts."
                    )
                )
                return

            try:
                with transaction.atomic():
                    migrated = {
                        "users": self.migrate_users(database),
                        "trucks": self.migrate_trucks(database),
                        "loads": self.migrate_loads(database),
                        "bookings": self.migrate_bookings(database),
                    }
            except (CommandError, IntegrityError, ValueError) as error:
                raise CommandError(
                    f"Migration rolled back; no partial migration was kept: {error}"
                ) from error

            self.stdout.write(self.style.SUCCESS("MongoDB migration complete:"))
            for collection, count in migrated.items():
                self.stdout.write(f"  {collection}: {count} records migrated")
        finally:
            client.close()

    def migrate_users(self, database):
        count = 0
        for document in database.users.find({}):
            identifier = object_id(document.get("_id"), "user id")
            email = (document.get("email") or "").strip().lower() or None
            phone = (document.get("phone") or "").strip() or None
            if phone:
                phone = normalize_phone(phone)
            role = document.get("role") or User.Role.CUSTOMER
            if role not in User.Role.values:
                role = User.Role.CUSTOMER
            created_at = parse_datetime(document.get("createdAt"))
            updated_at = parse_datetime(document.get("updatedAt"), fallback=created_at)
            User.objects.update_or_create(
                pk=identifier,
                defaults={
                    "name": str(document.get("name") or "Marketplace user").strip()[:100],
                    "email": email,
                    "phone": phone,
                    "password": normalize_legacy_password(document.get("password")),
                    "role": role,
                    "agency_name": str(document.get("agencyName") or "").strip()[:120],
                    "profile_image_url": str(document.get("profileImageUrl") or "")[:2048],
                    "is_verified": bool(document.get("isVerified", False)),
                    "is_active": bool(document.get("isActive", True)),
                    "is_staff": bool(document.get("isStaff", role == User.Role.ADMIN)),
                    "is_superuser": bool(document.get("isSuperuser", role == User.Role.ADMIN)),
                    "last_login": parse_datetime(document["lastLogin"]) if document.get("lastLogin") else None,
                    "created_at": created_at,
                    "updated_at": updated_at,
                },
            )
            count += 1
        return count

    def migrate_trucks(self, database):
        count = 0
        for document in database.trucks.find({}):
            identifier = object_id(document.get("_id"), "truck id")
            owner_id = object_id(document.get("owner"), "truck owner")
            if not User.objects.filter(pk=owner_id).exists():
                raise CommandError("A truck references a MongoDB user that was not migrated.")
            created_at = parse_datetime(document.get("createdAt"))
            defaults = {
                "owner_id": owner_id,
                "agency_name": str(document.get("agencyName") or "")[:120],
                "registration_number": str(document.get("registrationNumber") or "").strip().upper(),
                "truck_type": document.get("truckType") or "other",
                "capacity_tons": decimal_value(document.get("capacityTons"), "truck capacity"),
                "description": str(document.get("description") or "")[:1000],
                "document_urls": document.get("documentUrls") or [],
                "is_available": bool(document.get("isAvailable", True)),
                "current_location": normalized_location(document.get("currentLocation")),
                "created_at": created_at,
                "updated_at": parse_datetime(document.get("updatedAt"), fallback=created_at),
            }
            Truck.objects.update_or_create(pk=identifier, defaults=defaults)
            count += 1
        return count

    def migrate_loads(self, database):
        count = 0
        for document in database.loads.find({}):
            identifier = object_id(document.get("_id"), "load id")
            owner_id = object_id(document.get("owner"), "load owner")
            if not User.objects.filter(pk=owner_id).exists():
                raise CommandError("A load references a MongoDB user that was not migrated.")
            created_at = parse_datetime(document.get("createdAt"))
            status_value = document.get("status") or Load.Status.SEARCHING
            if status_value not in Load.Status.values:
                status_value = Load.Status.SEARCHING
            Load.objects.update_or_create(
                pk=identifier,
                defaults={
                    "owner_id": owner_id,
                    "pickup": document.get("pickup") or {},
                    "delivery": document.get("delivery") or {},
                    "load_type": str(document.get("loadType") or "Freight load")[:100],
                    "weight_tons": decimal_value(document.get("weightTons"), "load weight"),
                    "required_truck_type": document.get("requiredTruckType") or "other",
                    "pickup_date": parse_datetime(document.get("pickupDate")),
                    "price": decimal_value(document.get("price"), "load price"),
                    "description": str(document.get("description") or "")[:2000],
                    "image_urls": document.get("imageUrls") or [],
                    "status": status_value,
                    "created_at": created_at,
                    "updated_at": parse_datetime(document.get("updatedAt"), fallback=created_at),
                },
            )
            count += 1
        return count

    def migrate_bookings(self, database):
        count = 0
        for document in database.bookings.find({}):
            identifier = object_id(document.get("_id"), "booking id")
            load_id = object_id(document.get("load"), "booking load")
            truck_id = object_id(document.get("truck"), "booking truck")
            customer_id = object_id(document.get("customer"), "booking customer")
            owner_id = object_id(document.get("truckOwner"), "booking truck owner")
            if not Load.objects.filter(pk=load_id).exists():
                raise CommandError("A booking references a MongoDB load that was not migrated.")
            if not Truck.objects.filter(pk=truck_id).exists():
                raise CommandError("A booking references a MongoDB truck that was not migrated.")
            if not User.objects.filter(pk__in=[customer_id, owner_id]).count() == 2:
                raise CommandError("A booking references a MongoDB user that was not migrated.")
            created_at = parse_datetime(document.get("createdAt"))
            defaults = {
                "load_id": load_id,
                "truck_id": truck_id,
                "customer_id": customer_id,
                "truck_owner_id": owner_id,
                "status": document.get("status") or Booking.Status.PENDING,
                "agreed_price": decimal_value(document.get("agreedPrice"), "booking price"),
                "commission_rate": decimal_value(document.get("commissionRate"), "commission rate", default="5"),
                "commission_amount": decimal_value(document.get("commissionAmount"), "commission amount"),
                "payment_status": document.get("paymentStatus") or Booking.PaymentStatus.PENDING,
                "tracking_location": normalized_location(document.get("trackingLocation")),
                "notes": str(document.get("notes") or "")[:1000],
                "created_at": created_at,
                "updated_at": parse_datetime(document.get("updatedAt"), fallback=created_at),
            }
            if defaults["status"] not in Booking.Status.values:
                defaults["status"] = Booking.Status.PENDING
            if defaults["payment_status"] not in Booking.PaymentStatus.values:
                defaults["payment_status"] = Booking.PaymentStatus.PENDING
            Booking.objects.update_or_create(pk=identifier, defaults=defaults)
            count += 1
        return count

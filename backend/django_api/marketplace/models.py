import secrets

from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.contrib.auth.models import PermissionsMixin
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone


def new_document_id():
    return secrets.token_hex(12)


class TimestampedModel(models.Model):
    id = models.CharField(primary_key=True, max_length=24, default=new_document_id, editable=False)
    created_at = models.DateTimeField(default=timezone.now, db_index=True)
    updated_at = models.DateTimeField(default=timezone.now)

    class Meta:
        abstract = True


class UserManager(BaseUserManager):
    def create_user(self, phone=None, email=None, password=None, **extra_fields):
        if not phone and not email:
            raise ValueError("A phone number or email address is required")
        email = self.normalize_email(email) if email else None
        user = self.model(phone=phone, email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, phone=None, email=None, password=None, **extra_fields):
        extra_fields.setdefault("role", User.Role.ADMIN)
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("is_active", True)
        if not extra_fields.get("is_staff") or not extra_fields.get("is_superuser"):
            raise ValueError("A superuser must have is_staff and is_superuser enabled")
        return self.create_user(phone, email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    class Role(models.TextChoices):
        CUSTOMER = "customer", "Customer / Load owner"
        TRUCK_OWNER = "truckOwner", "Truck owner"
        AGENCY = "agency", "Transport agency"
        ADMIN = "admin", "Administrator"

    id = models.CharField(primary_key=True, max_length=24, default=new_document_id, editable=False)
    name = models.CharField(max_length=100)
    email = models.EmailField(max_length=254, unique=True, null=True, blank=True)
    phone = models.CharField(max_length=20, unique=True, null=True, blank=True)
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.CUSTOMER, db_index=True)
    agency_name = models.CharField(max_length=120, blank=True)
    profile_image_url = models.URLField(max_length=2048, blank=True)
    is_verified = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(default=timezone.now)

    objects = UserManager()

    USERNAME_FIELD = "phone"
    REQUIRED_FIELDS = ["name"]

    def __str__(self):
        return self.name


class OtpChallenge(TimestampedModel):
    phone = models.CharField(max_length=20, db_index=True)
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    verified_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["phone", "created_at"])]


class Load(TimestampedModel):
    class Status(models.TextChoices):
        SEARCHING = "searching", "Searching for truck"
        BOOKED = "booked", "Truck found"
        IN_TRANSIT = "inTransit", "In transit"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"

    owner = models.ForeignKey(User, on_delete=models.PROTECT, related_name="loads")
    pickup = models.JSONField()
    delivery = models.JSONField()
    load_type = models.CharField(max_length=100, db_column="load_type")
    weight_tons = models.DecimalField(max_digits=10, decimal_places=2)
    required_truck_type = models.CharField(max_length=20)
    pickup_date = models.DateTimeField()
    price = models.DecimalField(max_digits=14, decimal_places=2)
    description = models.TextField(blank=True)
    image_urls = models.JSONField(default=list, blank=True)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.SEARCHING, db_index=True
    )

    class Meta:
        ordering = ["-created_at"]


class Truck(TimestampedModel):
    owner = models.ForeignKey(User, on_delete=models.PROTECT, related_name="trucks")
    agency_name = models.CharField(max_length=120, blank=True)
    registration_number = models.CharField(max_length=40, unique=True)
    truck_type = models.CharField(max_length=20)
    capacity_tons = models.DecimalField(max_digits=10, decimal_places=2)
    description = models.TextField(blank=True)
    document_urls = models.JSONField(default=list, blank=True)
    is_available = models.BooleanField(default=True, db_index=True)
    current_location = models.JSONField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]


class Booking(TimestampedModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Awaiting commission payment"
        CONFIRMED = "confirmed", "Confirmed"
        GOING_TO_PICKUP = "goingToPickup", "Going to pickup"
        REACHED_PICKUP = "reachedPickup", "Reached pickup"
        LOADING = "loading", "Loading"
        GOODS_PICKED_UP = "goodsPickedUp", "Goods picked up"
        ON_THE_WAY = "onTheWay", "On the way"
        NEAR_DELIVERY = "nearDelivery", "Near delivery"
        REACHED_DELIVERY = "reachedDelivery", "Reached delivery"
        DELIVERED = "delivered", "Delivered"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"

    class PaymentStatus(models.TextChoices):
        NOT_REQUIRED = "notRequired", "Not required"
        PENDING = "pending", "Pending"
        PAID = "paid", "Paid"
        FAILED = "failed", "Failed"
        REFUNDED = "refunded", "Refunded"

    load = models.ForeignKey(Load, on_delete=models.PROTECT, related_name="bookings")
    truck = models.ForeignKey(Truck, on_delete=models.PROTECT, related_name="bookings")
    customer = models.ForeignKey(User, on_delete=models.PROTECT, related_name="customer_bookings")
    truck_owner = models.ForeignKey(User, on_delete=models.PROTECT, related_name="truck_owner_bookings")
    status = models.CharField(
        max_length=24, choices=Status.choices, default=Status.PENDING, db_index=True
    )
    agreed_price = models.DecimalField(max_digits=14, decimal_places=2)
    commission_rate = models.DecimalField(max_digits=5, decimal_places=2, default=5)
    commission_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    payment_status = models.CharField(
        max_length=20, choices=PaymentStatus.choices, default=PaymentStatus.PENDING
    )
    payment_provider = models.CharField(max_length=40, blank=True)
    payment_reference = models.CharField(max_length=120, blank=True)
    tracking_location = models.JSONField(null=True, blank=True)
    notes = models.CharField(max_length=1000, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["load"], condition=~models.Q(status="cancelled"), name="one_active_booking_per_load"),
        ]


class PaymentTransaction(TimestampedModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        PAID = "paid", "Paid"
        FAILED = "failed", "Failed"
        REFUNDED = "refunded", "Refunded"

    booking = models.ForeignKey(Booking, on_delete=models.PROTECT, related_name="payment_transactions")
    payer = models.ForeignKey(User, on_delete=models.PROTECT, related_name="payment_transactions")
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="INR")
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING, db_index=True)
    provider = models.CharField(max_length=40, blank=True)
    provider_reference = models.CharField(max_length=120, blank=True)
    paid_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["booking", "status"])]


class Notification(TimestampedModel):
    recipient = models.ForeignKey(User, on_delete=models.CASCADE, related_name="notifications")
    notification_type = models.CharField(max_length=40)
    title = models.CharField(max_length=160)
    message = models.CharField(max_length=500)
    payload = models.JSONField(default=dict, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["recipient", "read_at", "-created_at"])]


class Rating(TimestampedModel):
    booking = models.ForeignKey(Booking, on_delete=models.PROTECT, related_name="ratings")
    reviewer = models.ForeignKey(User, on_delete=models.PROTECT, related_name="ratings_given")
    reviewee = models.ForeignKey(User, on_delete=models.PROTECT, related_name="ratings_received")
    score = models.PositiveSmallIntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)])
    review = models.CharField(max_length=1000, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["booking", "reviewer"], name="one_rating_per_reviewer_per_booking"),
        ]
        ordering = ["-created_at"]


class PlatformSetting(models.Model):
    commission_rate = models.DecimalField(max_digits=5, decimal_places=2, default=5)
    matching_radius_km = models.PositiveSmallIntegerField(default=100)
    updated_at = models.DateTimeField(auto_now=True)

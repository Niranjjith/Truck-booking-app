from rest_framework import serializers

from .models import (
    Booking,
    Load,
    Notification,
    PlatformSetting,
    PaymentTransaction,
    Rating,
    Truck,
    User,
)


class PublicUserSerializer(serializers.ModelSerializer):
    agencyName = serializers.CharField(source="agency_name", read_only=True)
    profileImageUrl = serializers.CharField(source="profile_image_url", read_only=True)
    isVerified = serializers.BooleanField(source="is_verified", read_only=True)

    class Meta:
        model = User
        fields = ("id", "name", "email", "phone", "role", "agencyName", "profileImageUrl", "isVerified")


class LocationSerializer(serializers.DictField):
    def to_internal_value(self, data):
        result = super().to_internal_value(data)
        address = result.get("address")
        if not isinstance(address, str) or not address.strip():
            raise serializers.ValidationError({"address": "A pickup/delivery address is required."})
        coordinates = result.get("coordinates")
        if coordinates is not None:
            if not isinstance(coordinates, (list, tuple)) or len(coordinates) != 2:
                raise serializers.ValidationError({"coordinates": "Coordinates must be [longitude, latitude]."})
            try:
                longitude, latitude = map(float, coordinates)
            except (TypeError, ValueError):
                raise serializers.ValidationError({"coordinates": "Coordinates must be numeric."})
            if not (-180 <= longitude <= 180 and -90 <= latitude <= 90):
                raise serializers.ValidationError({"coordinates": "Coordinates are outside the valid range."})
            result["coordinates"] = [longitude, latitude]
        return result


class LoadSerializer(serializers.ModelSerializer):
    loadType = serializers.CharField(source="load_type")
    weightTons = serializers.DecimalField(source="weight_tons", max_digits=10, decimal_places=2)
    requiredTruckType = serializers.CharField(source="required_truck_type")
    pickupDate = serializers.DateTimeField(source="pickup_date")
    imageUrls = serializers.ListField(source="image_urls", child=serializers.URLField(), required=False)
    owner = PublicUserSerializer(read_only=True)

    class Meta:
        model = Load
        fields = (
            "id", "owner", "pickup", "delivery", "loadType", "weightTons",
            "requiredTruckType", "pickupDate", "price", "description", "imageUrls",
            "status", "created_at", "updated_at",
        )
        read_only_fields = ("id", "status", "created_at", "updated_at")

    def validate(self, attrs):
        truck_type = attrs.get("required_truck_type", getattr(self.instance, "required_truck_type", None))
        if truck_type not in TruckType.values:
            raise serializers.ValidationError({"requiredTruckType": "Choose a valid truck type."})
        return attrs

    def validate_weight_tons(self, value):
        if value <= 0:
            raise serializers.ValidationError("Weight must be greater than zero.")
        return value


class TruckType:
    values = ("mini", "pickup", "light", "medium", "heavy", "trailer", "container", "other")


class TruckSerializer(serializers.ModelSerializer):
    registrationNumber = serializers.CharField(source="registration_number")
    truckType = serializers.CharField(source="truck_type")
    capacityTons = serializers.DecimalField(source="capacity_tons", max_digits=10, decimal_places=2)
    documentUrls = serializers.ListField(source="document_urls", child=serializers.URLField(), required=False)
    isAvailable = serializers.BooleanField(source="is_available", required=False)
    currentLocation = serializers.JSONField(source="current_location", allow_null=True, required=False)
    agencyName = serializers.CharField(source="agency_name", required=False, allow_blank=True)
    owner = PublicUserSerializer(read_only=True)

    class Meta:
        model = Truck
        fields = (
            "id", "owner", "registrationNumber", "truckType", "capacityTons",
            "agencyName", "description", "documentUrls", "isAvailable",
            "currentLocation", "created_at", "updated_at",
        )
        read_only_fields = ("id", "owner", "created_at", "updated_at")

    def validate_truck_type(self, value):
        if value not in TruckType.values:
            raise serializers.ValidationError("Choose a valid truck type.")
        return value

    def validate_capacity_tons(self, value):
        if value <= 0:
            raise serializers.ValidationError("Capacity must be greater than zero.")
        return value

    def validate_current_location(self, value):
        if value is None:
            return value
        if not isinstance(value, dict) or value.get("type", "Point") != "Point":
            raise serializers.ValidationError("Current location must be a GeoJSON Point.")
        coordinates = value.get("coordinates")
        if not isinstance(coordinates, (list, tuple)) or len(coordinates) != 2:
            raise serializers.ValidationError({"coordinates": "Coordinates must be [longitude, latitude]."})
        try:
            longitude, latitude = map(float, coordinates)
        except (TypeError, ValueError):
            raise serializers.ValidationError({"coordinates": "Coordinates must be numeric."})
        if not (-180 <= longitude <= 180 and -90 <= latitude <= 90):
            raise serializers.ValidationError({"coordinates": "Coordinates are outside the valid range."})
        return {**value, "type": "Point", "coordinates": [longitude, latitude]}


class BookingSerializer(serializers.ModelSerializer):
    load = LoadSerializer(read_only=True)
    truck = TruckSerializer(read_only=True)
    customer = PublicUserSerializer(read_only=True)
    truckOwner = PublicUserSerializer(source="truck_owner", read_only=True)
    agreedPrice = serializers.DecimalField(source="agreed_price", max_digits=14, decimal_places=2)
    commissionRate = serializers.DecimalField(source="commission_rate", max_digits=5, decimal_places=2)
    commissionAmount = serializers.DecimalField(source="commission_amount", max_digits=12, decimal_places=2)
    paymentStatus = serializers.CharField(source="payment_status")
    trackingLocation = serializers.JSONField(source="tracking_location", allow_null=True)
    paymentProvider = serializers.CharField(source="payment_provider")
    paymentReference = serializers.CharField(source="payment_reference")

    class Meta:
        model = Booking
        fields = (
            "id", "load", "truck", "customer", "truckOwner", "status", "agreedPrice",
            "commissionRate", "commissionAmount", "paymentStatus", "paymentProvider",
            "paymentReference", "trackingLocation", "notes", "created_at", "updated_at",
        )
        read_only_fields = fields


class NotificationSerializer(serializers.ModelSerializer):
    notificationType = serializers.CharField(source="notification_type")
    readAt = serializers.DateTimeField(source="read_at", allow_null=True)

    class Meta:
        model = Notification
        fields = (
            "id", "notificationType", "title", "message", "payload", "readAt",
            "created_at",
        )
        read_only_fields = fields


class RatingSerializer(serializers.ModelSerializer):
    reviewer = PublicUserSerializer(read_only=True)
    reviewee = PublicUserSerializer(read_only=True)
    bookingId = serializers.CharField(source="booking_id", read_only=True)

    class Meta:
        model = Rating
        fields = ("id", "bookingId", "reviewer", "reviewee", "score", "review", "created_at")
        read_only_fields = ("id", "bookingId", "reviewer", "reviewee", "created_at")


class PaymentTransactionSerializer(serializers.ModelSerializer):
    bookingId = serializers.CharField(source="booking_id", read_only=True)
    providerReference = serializers.CharField(source="provider_reference", read_only=True)
    payer = PublicUserSerializer(read_only=True)

    class Meta:
        model = PaymentTransaction
        fields = (
            "id", "bookingId", "payer", "amount", "currency", "status",
            "provider", "providerReference", "paid_at", "created_at",
        )
        read_only_fields = fields


class ProfileUpdateSerializer(serializers.ModelSerializer):
    agencyName = serializers.CharField(source="agency_name", required=False, allow_blank=True)
    profileImageUrl = serializers.URLField(source="profile_image_url", required=False, allow_blank=True)

    class Meta:
        model = User
        fields = ("name", "email", "agencyName", "profileImageUrl")

    def validate_email(self, value):
        normalized = User.objects.normalize_email(value).lower() if value else None
        query = User.objects.filter(email__iexact=normalized).exclude(pk=self.instance.pk)
        if normalized and query.exists():
            raise serializers.ValidationError("Email address is already registered.")
        return normalized


def platform_commission_rate():
    setting = PlatformSetting.objects.order_by("-updated_at").first()
    if setting:
        return setting.commission_rate
    from django.conf import settings

    return settings.COMMISSION_RATE

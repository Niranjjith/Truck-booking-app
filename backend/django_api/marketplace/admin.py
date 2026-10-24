from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin

from .models import (
    Booking,
    Load,
    Notification,
    OtpChallenge,
    PaymentTransaction,
    PlatformSetting,
    Rating,
    Truck,
    User,
)


@admin.register(User)
class UserAdmin(DjangoUserAdmin):
    ordering = ("-created_at",)
    list_display = ("name", "phone", "email", "role", "is_verified", "is_active", "is_staff")
    list_filter = ("role", "is_verified", "is_active", "is_staff")
    search_fields = ("name", "phone", "email", "agency_name")
    readonly_fields = ("last_login", "created_at", "updated_at")
    fieldsets = (
        (None, {"fields": ("phone", "email", "password")}),
        ("Profile", {"fields": ("name", "role", "agency_name", "profile_image_url")}),
        ("Verification and access", {"fields": ("is_verified", "is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Dates", {"fields": ("last_login", "created_at", "updated_at")}),
    )
    add_fieldsets = (
        (
            None,
            {
                "classes": ("wide",),
                "fields": ("name", "phone", "email", "role", "password1", "password2"),
            },
        ),
    )
    filter_horizontal = ("groups", "user_permissions")


@admin.register(Load)
class LoadAdmin(admin.ModelAdmin):
    list_display = ("load_type", "owner", "required_truck_type", "weight_tons", "status", "pickup_date")
    list_filter = ("status", "required_truck_type", "created_at")
    search_fields = ("id", "load_type", "owner__name", "owner__phone")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(Truck)
class TruckAdmin(admin.ModelAdmin):
    list_display = ("registration_number", "owner", "truck_type", "capacity_tons", "is_available")
    list_filter = ("truck_type", "is_available", "created_at")
    search_fields = ("id", "registration_number", "owner__name", "owner__phone")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(Booking)
class BookingAdmin(admin.ModelAdmin):
    list_display = ("id", "load", "truck", "customer", "truck_owner", "status", "payment_status")
    list_filter = ("status", "payment_status", "created_at")
    search_fields = ("id", "load__load_type", "truck__registration_number", "customer__phone", "truck_owner__phone")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(PaymentTransaction)
class PaymentTransactionAdmin(admin.ModelAdmin):
    list_display = ("id", "booking", "payer", "amount", "currency", "status", "provider", "paid_at")
    list_filter = ("status", "provider", "created_at")
    search_fields = ("id", "booking__id", "provider_reference")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("title", "recipient", "notification_type", "read_at", "created_at")
    list_filter = ("notification_type", "read_at", "created_at")
    search_fields = ("title", "recipient__name", "recipient__phone")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(Rating)
class RatingAdmin(admin.ModelAdmin):
    list_display = ("booking", "reviewer", "reviewee", "score", "created_at")
    list_filter = ("score", "created_at")
    search_fields = ("booking__id", "reviewer__name", "reviewee__name", "review")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(PlatformSetting)
class PlatformSettingAdmin(admin.ModelAdmin):
    list_display = ("commission_rate", "matching_radius_km", "updated_at")

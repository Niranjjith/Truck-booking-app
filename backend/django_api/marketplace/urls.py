from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from . import views

urlpatterns = [
    path("health", views.health, name="health"),
    path("health/", views.health),
    path("auth/register", views.register, name="register"),
    path("auth/login", views.login, name="login"),
    path("auth/otp/request", views.request_otp, name="otp-request"),
    path("auth/otp/verify", views.verify_otp, name="otp-verify"),
    path("auth/token/refresh", TokenRefreshView.as_view(), name="token-refresh"),
    path("auth/me", views.profile, name="profile"),
    path("auth/me/", views.profile),
    path("loads", views.load_collection, name="loads"),
    path("loads/", views.load_collection),
    path("loads/matches", views.matching_loads, name="matching-loads"),
    path("loads/matches/", views.matching_loads),
    path("loads/<str:load_id>/matches", views.matching_loads, name="load-matches"),
    path("loads/<str:load_id>", views.load_detail, name="load-detail"),
    path("loads/<str:load_id>/cancel", views.cancel_load, name="load-cancel"),
    path("trucks", views.truck_collection, name="trucks"),
    path("trucks/", views.truck_collection),
    path("trucks/<str:truck_id>", views.truck_detail, name="truck-detail"),
    path("bookings", views.booking_collection, name="bookings"),
    path("bookings/", views.booking_collection),
    path("bookings/<str:booking_id>", views.booking_detail, name="booking-detail"),
    path("bookings/<str:booking_id>/status", views.update_booking_status, name="booking-status"),
    path("bookings/<str:booking_id>/tracking", views.update_tracking, name="booking-tracking"),
    path("routes/estimate", views.route_estimate, name="route-estimate"),
    path("bookings/<str:booking_id>/checkout", views.checkout, name="booking-checkout"),
    path(
        "bookings/<str:booking_id>/payments/razorpay-verify",
        views.razorpay_payment_verify,
        name="razorpay-payment-verify",
    ),
    path(
        "bookings/<str:booking_id>/payments/sandbox-complete",
        views.sandbox_payment_complete,
        name="sandbox-payment-complete",
    ),
    path("bookings/<str:booking_id>/ratings", views.booking_ratings, name="booking-ratings"),
    path("notifications", views.notification_collection, name="notifications"),
    path("notifications/<str:notification_id>/read", views.notification_detail, name="notification-read"),
    path("payments", views.payment_history, name="payment-history"),
]

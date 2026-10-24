import math
import secrets
from datetime import timedelta
from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import DatabaseError, transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import (
    api_view,
    authentication_classes,
    permission_classes,
)
from rest_framework.exceptions import (
    APIException,
    NotFound,
    PermissionDenied,
    ValidationError,
)
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from .matching import distance_km, matching_trucks
from .google_routes import GoogleRoutesError, compute_route
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
from .razorpay import RazorpayError, create_order, verify_payment
from .serializers import (
    BookingSerializer,
    LoadSerializer,
    NotificationSerializer,
    PaymentTransactionSerializer,
    ProfileUpdateSerializer,
    PublicUserSerializer,
    RatingSerializer,
    TruckSerializer,
    platform_commission_rate,
)
from .tasks import schedule_load_notifications

USER_ROLES = {choice for choice, _ in User.Role.choices}
TRUCK_TYPES = {"mini", "pickup", "light", "medium", "heavy", "trailer", "container", "other"}
NEXT_STATUSES = {
    Booking.Status.CONFIRMED: [Booking.Status.GOING_TO_PICKUP],
    Booking.Status.GOING_TO_PICKUP: [Booking.Status.REACHED_PICKUP],
    Booking.Status.REACHED_PICKUP: [Booking.Status.LOADING],
    Booking.Status.LOADING: [Booking.Status.GOODS_PICKED_UP],
    Booking.Status.GOODS_PICKED_UP: [Booking.Status.ON_THE_WAY],
    Booking.Status.ON_THE_WAY: [Booking.Status.NEAR_DELIVERY],
    Booking.Status.NEAR_DELIVERY: [Booking.Status.REACHED_DELIVERY],
    Booking.Status.REACHED_DELIVERY: [Booking.Status.DELIVERED],
    Booking.Status.DELIVERED: [Booking.Status.COMPLETED],
}


class ProviderUnavailable(APIException):
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    default_detail = "This service is not configured yet. No code or payment was sent."
    default_code = "provider_unavailable"


def normalize_phone(value):
    if not isinstance(value, str):
        raise ValidationError({"phone": "Enter a valid phone number."})
    raw_phone = value.strip()
    if any(character not in "+0123456789 ()-." for character in raw_phone):
        raise ValidationError({"phone": "Enter a valid phone number using digits and an optional country code."})
    phone = "".join(character for character in raw_phone if character.isdigit())
    if raw_phone.startswith("00"):
        phone = phone[2:]
    if len(phone) == 10:
        phone = f"91{phone}"
    elif len(phone) == 11 and phone.startswith("0"):
        phone = f"91{phone[1:]}"
    if not phone.isdigit() or not 8 <= len(phone) <= 15 or phone.startswith("0"):
        raise ValidationError({"phone": "Enter a valid international phone number."})
    return f"+{phone}"


def user_summary(user):
    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "phone": user.phone,
        "role": user.role,
    }


def auth_response(user):
    refresh = RefreshToken.for_user(user)
    return {
        "message": "Authentication successful",
        "token": str(refresh.access_token),
        "refresh": str(refresh),
        "user": user_summary(user),
    }


def issue_otp(user, *, enforce_throttle=True):
    if not settings.DEBUG:
        raise ProviderUnavailable(
            "SMS verification is not configured. No verification code was sent."
        )
    current_time = timezone.now()
    previous = OtpChallenge.objects.filter(phone=user.phone).order_by("-created_at").first()
    if (
        enforce_throttle
        and previous
        and current_time - previous.created_at < timedelta(seconds=settings.OTP_RESEND_SECONDS)
    ):
        raise ValidationError({"message": "Please wait before requesting another code."})
    code = f"{secrets.randbelow(1_000_000):06d}"
    OtpChallenge.objects.create(
        phone=user.phone,
        code_hash=make_password(code),
        expires_at=current_time + timedelta(minutes=settings.OTP_EXPIRY_MINUTES),
    )
    return code if settings.OTP_DEBUG_RETURN_CODE else None


def get_user_bookings(user):
    bookings = Booking.objects.select_related(
        "load__owner", "truck__owner", "customer", "truck_owner"
    )
    if user.role != User.Role.ADMIN:
        bookings = bookings.filter(Q(customer=user) | Q(truck_owner=user))
    return bookings


def get_booking_for_user(user, booking_id, *, lock=False):
    queryset = Booking.objects.select_related("load__owner", "truck__owner", "customer", "truck_owner")
    if lock:
        queryset = queryset.select_for_update()
    try:
        booking = queryset.get(pk=booking_id)
    except Booking.DoesNotExist:
        raise NotFound("Booking not found")
    if user.role != User.Role.ADMIN and user not in (booking.customer, booking.truck_owner):
        raise PermissionDenied("You cannot access this booking.")
    return booking


def valid_location_coordinates(location):
    if not isinstance(location, dict):
        return False
    coordinates = location.get("coordinates")
    if not isinstance(coordinates, (list, tuple)) or len(coordinates) != 2:
        return False
    try:
        longitude, latitude = map(float, coordinates)
    except (TypeError, ValueError):
        return False
    return (
        math.isfinite(longitude)
        and math.isfinite(latitude)
        and -180 <= longitude <= 180
        and -90 <= latitude <= 90
    )


@api_view(["GET"])
@permission_classes([AllowAny])
def health(request):
    try:
        from django.db import connection

        connection.ensure_connection()
    except DatabaseError:
        return Response(
            {"status": "unavailable", "database": "disconnected"},
            status=status.HTTP_503_SERVICE_UNAVAILABLE,
        )
    return Response({"status": "ok", "database": "connected"})


@api_view(["POST"])
@permission_classes([AllowAny])
def register(request):
    data = request.data
    name = data.get("name")
    password = data.get("password")
    if not isinstance(name, str) or not name.strip():
        raise ValidationError({"name": "Name is required."})
    if not isinstance(password, str) or len(password) < 8:
        raise ValidationError({"password": "Password must contain at least 8 characters."})
    role = data.get("role", User.Role.CUSTOMER)
    if role not in USER_ROLES - {User.Role.ADMIN}:
        raise ValidationError({"role": "Choose customer, truckOwner, or agency."})
    phone = normalize_phone(data.get("phone"))
    email = data.get("email")
    if email:
        from django.core.validators import validate_email

        try:
            validate_email(email)
        except DjangoValidationError as error:
            raise ValidationError({"email": error.messages})
        email = User.objects.normalize_email(email).lower()
    try:
        validate_password(password)
    except DjangoValidationError as error:
        raise ValidationError({"password": error.messages})
    if User.objects.filter(Q(phone=phone) | Q(email__iexact=email) if email else Q(phone=phone)).exists():
        return Response(
            {"message": "Phone or email is already registered."},
            status=status.HTTP_409_CONFLICT,
        )

    with transaction.atomic():
        user = User.objects.create_user(
            phone=phone,
            email=email,
            password=password,
            name=name.strip(),
            role=role,
            agency_name=str(data.get("agencyName", "")).strip()[:120],
            is_verified=False,
        )
        code = issue_otp(user, enforce_throttle=False)
    response = {
        "message": "Account created. Verify your phone number to finish signing in.",
        "otpRequired": True,
        "user": user_summary(user),
    }
    if code:
        response["developmentOtp"] = code
    return Response(response, status=status.HTTP_201_CREATED)


@api_view(["POST"])
@permission_classes([AllowAny])
def login(request):
    data = request.data
    password = data.get("password")
    if not isinstance(password, str) or not password:
        raise ValidationError({"password": "Password is required."})
    identifier = data.get("phone")
    email = data.get("email")
    if not identifier and not email:
        raise ValidationError({"message": "Provide your registered phone number and password."})

    user = None
    if identifier:
        identifier = str(identifier).strip()
        if "@" in identifier:
            user = User.objects.filter(email__iexact=identifier).first()
        else:
            phone = normalize_phone(identifier)
            user = User.objects.filter(phone=phone).first()
    elif email:
        user = User.objects.filter(email__iexact=str(email).strip()).first()
    if not user or not user.is_active or not check_password(password, user.password):
        return Response(
            {"message": "Invalid login credentials."},
            status=status.HTTP_401_UNAUTHORIZED,
        )
    if user.phone and not user.is_verified:
        code = issue_otp(user)
        result = {
            "message": "Verify your phone number to sign in.",
            "otpRequired": True,
        }
        if code:
            result["developmentOtp"] = code
        return Response(result)
    user.last_login = timezone.now()
    user.save(update_fields=["last_login"])
    return Response(auth_response(user))


@api_view(["POST"])
@permission_classes([AllowAny])
def request_otp(request):
    phone = normalize_phone(request.data.get("phone"))
    user = User.objects.filter(phone=phone, is_active=True).first()
    if not user:
        return Response({"message": "If the account exists, a code will be sent."})
    code = issue_otp(user)
    result = {"message": "A verification code was sent to your phone."}
    if code:
        result["developmentOtp"] = code
    return Response(result)


@api_view(["POST"])
@permission_classes([AllowAny])
def verify_otp(request):
    phone = normalize_phone(request.data.get("phone"))
    code = request.data.get("code")
    if not isinstance(code, str) or len(code) != 6 or not code.isdigit():
        raise ValidationError({"code": "Enter the six-digit verification code."})
    current_time = timezone.now()
    challenge = OtpChallenge.objects.filter(
        phone=phone,
        verified_at__isnull=True,
        expires_at__gt=current_time,
        attempts__lt=5,
    ).order_by("-created_at").first()
    if not challenge or not check_password(code, challenge.code_hash):
        if challenge:
            challenge.attempts += 1
            challenge.save(update_fields=["attempts", "updated_at"])
        return Response(
            {"message": "Verification code is invalid or expired."},
            status=status.HTTP_400_BAD_REQUEST,
        )
    user = User.objects.filter(phone=phone, is_active=True).first()
    if not user:
        return Response({"message": "Account not found."}, status=status.HTTP_404_NOT_FOUND)
    with transaction.atomic():
        challenge.verified_at = current_time
        challenge.save(update_fields=["verified_at", "updated_at"])
        user.is_verified = True
        user.last_login = current_time
        user.save(update_fields=["is_verified", "last_login"])
    return Response(auth_response(user))


@api_view(["GET", "PATCH"])
def profile(request):
    if request.method == "GET":
        return Response({"user": PublicUserSerializer(request.user).data})
    serializer = ProfileUpdateSerializer(request.user, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response({"message": "Profile updated", "user": PublicUserSerializer(request.user).data})


def load_list_response(request):
    loads = Load.objects.select_related("owner")
    if request.query_params.get("mine") == "true":
        loads = loads.filter(owner=request.user)
    include_closed = request.query_params.get("includeClosed") == "true"
    status_filter = request.query_params.get("status")
    if status_filter:
        loads = loads.filter(status=status_filter)
    elif not include_closed:
        loads = loads.filter(status=Load.Status.SEARCHING)
    truck_type = request.query_params.get("requiredTruckType")
    if truck_type:
        loads = loads.filter(required_truck_type=truck_type)
    try:
        if request.query_params.get("minWeight"):
            loads = loads.filter(weight_tons__gte=Decimal(request.query_params["minWeight"]))
        if request.query_params.get("maxWeight"):
            loads = loads.filter(weight_tons__lte=Decimal(request.query_params["maxWeight"]))
    except InvalidOperation:
        raise ValidationError({"weight": "Weight filters must be valid numbers."})
    results = list(loads[:500])
    return Response({"count": len(results), "loads": LoadSerializer(results, many=True).data})


@api_view(["GET", "POST"])
def load_collection(request):
    if request.method == "GET":
        return load_list_response(request)
    if request.user.role not in (User.Role.CUSTOMER, User.Role.AGENCY, User.Role.ADMIN):
        raise PermissionDenied("Only customers and agencies can post loads.")
    serializer = LoadSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    load = serializer.save(owner=request.user)
    schedule_load_notifications(load.id)
    return Response(
        {"message": "Load posted", "load": LoadSerializer(load).data},
        status=status.HTTP_201_CREATED,
    )


@api_view(["GET", "PATCH", "DELETE"])
def load_detail(request, load_id):
    try:
        load = Load.objects.select_related("owner").get(pk=load_id)
    except Load.DoesNotExist:
        raise NotFound("Load not found")
    if request.method == "GET":
        return Response({"load": LoadSerializer(load).data})
    if load.owner_id != request.user.id and request.user.role != User.Role.ADMIN:
        raise PermissionDenied("You cannot modify this load.")
    if request.method == "DELETE":
        if load.status not in (Load.Status.SEARCHING, Load.Status.CANCELLED):
            raise ValidationError({"message": "Only an unbooked load can be deleted."})
        load.delete()
        return Response({"message": "Load deleted."})
    if load.status != Load.Status.SEARCHING and request.user.role != User.Role.ADMIN:
        raise ValidationError({"message": "Only loads still searching can be edited."})
    serializer = LoadSerializer(load, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response({"message": "Load updated", "load": serializer.data})


@api_view(["PATCH"])
def cancel_load(request, load_id):
    try:
        load = Load.objects.get(pk=load_id)
    except Load.DoesNotExist:
        raise NotFound("Load not found")
    if load.owner_id != request.user.id and request.user.role != User.Role.ADMIN:
        raise PermissionDenied("You cannot cancel this load.")
    if load.status in (Load.Status.COMPLETED, Load.Status.CANCELLED, Load.Status.BOOKED):
        raise ValidationError({"message": "This load can no longer be cancelled directly."})
    load.status = Load.Status.CANCELLED
    load.save(update_fields=["status", "updated_at"])
    return Response({"message": "Load cancelled", "load": LoadSerializer(load).data})


@api_view(["GET"])
def matching_loads(request, load_id=None):
    if request.user.role not in (User.Role.TRUCK_OWNER, User.Role.AGENCY):
        raise PermissionDenied("Nearby matching is available to truck owners and agencies.")
    trucks = list(
        Truck.objects.filter(owner=request.user, is_available=True).order_by("created_at")
    )
    loads = Load.objects.filter(status=Load.Status.SEARCHING).select_related("owner")
    if load_id:
        loads = loads.filter(pk=load_id)
    loads = list(loads[:500])
    matches = {}
    for truck in trucks:
        if not valid_location_coordinates(truck.current_location):
            continue
        for load in loads:
            if load.weight_tons > truck.capacity_tons:
                continue
            if load.required_truck_type not in ("other", truck.truck_type, "other"):
                continue
            distance = distance_km(load.pickup, truck.current_location)
            if distance is not None and distance <= settings.MATCHING_RADIUS_KM:
                current = matches.get(load.id)
                if current is None or distance < current:
                    matches[load.id] = distance
    matched_loads = [load for load in loads if load.id in matches]
    matched_loads.sort(key=lambda load: matches[load.id])
    if load_id:
        if not loads:
            raise NotFound("Load not found")
        return Response(
            {
                "count": len(matched_loads),
                "trucks": [
                    {
                        **TruckSerializer(truck).data,
                        "distanceKm": round(distance, 2),
                    }
                    for truck, distance in matching_trucks(loads[0], settings.MATCHING_RADIUS_KM)
                    if truck.owner_id == request.user.id
                ],
            }
        )
    return Response(
        {
            "count": len(matched_loads),
            "loads": LoadSerializer(matched_loads, many=True).data,
            "distancesKm": {load.id: round(matches[load.id], 2) for load in matched_loads},
        }
    )


@api_view(["GET", "POST"])
def truck_collection(request):
    if request.method == "GET":
        trucks = Truck.objects.select_related("owner")
        if request.query_params.get("mine") == "true":
            trucks = trucks.filter(owner=request.user)
        truck_type = request.query_params.get("truckType")
        if truck_type:
            trucks = trucks.filter(truck_type=truck_type)
        availability = request.query_params.get("available")
        if availability in ("true", "false"):
            trucks = trucks.filter(is_available=availability == "true")
        try:
            if request.query_params.get("minCapacity"):
                trucks = trucks.filter(capacity_tons__gte=Decimal(request.query_params["minCapacity"]))
            if request.query_params.get("maxCapacity"):
                trucks = trucks.filter(capacity_tons__lte=Decimal(request.query_params["maxCapacity"]))
        except InvalidOperation:
            raise ValidationError({"capacity": "Capacity filters must be valid numbers."})
        results = list(trucks[:500])
        return Response({"count": len(results), "trucks": TruckSerializer(results, many=True).data})
    if request.user.role not in (User.Role.TRUCK_OWNER, User.Role.AGENCY, User.Role.ADMIN):
        raise PermissionDenied("Only truck owners and agencies can register trucks.")
    serializer = TruckSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    truck = serializer.save(owner=request.user)
    return Response(
        {"message": "Truck registered", "truck": TruckSerializer(truck).data},
        status=status.HTTP_201_CREATED,
    )


@api_view(["GET", "PATCH", "DELETE"])
def truck_detail(request, truck_id):
    try:
        truck = Truck.objects.select_related("owner").get(pk=truck_id)
    except Truck.DoesNotExist:
        raise NotFound("Truck not found")
    if request.method == "GET":
        return Response({"truck": TruckSerializer(truck).data})
    if truck.owner_id != request.user.id and request.user.role != User.Role.ADMIN:
        raise PermissionDenied("You cannot modify this truck.")
    if request.method == "DELETE":
        if truck.bookings.exclude(status=Booking.Status.CANCELLED).exists():
            raise ValidationError({"message": "A truck with active bookings cannot be deleted."})
        truck.delete()
        return Response({"message": "Truck deleted"})
    serializer = TruckSerializer(truck, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response({"message": "Truck updated", "truck": serializer.data})


@api_view(["GET", "POST"])
def booking_collection(request):
    if request.method == "GET":
        results = list(get_user_bookings(request.user)[:500])
        return Response({"count": len(results), "bookings": BookingSerializer(results, many=True).data})
    if request.user.role not in (User.Role.TRUCK_OWNER, User.Role.AGENCY, User.Role.ADMIN):
        raise PermissionDenied("Only truck owners or agencies can book a load.")
    load_id = request.data.get("loadId")
    truck_id = request.data.get("truckId")
    if not load_id or not truck_id:
        raise ValidationError({"message": "loadId and truckId are required."})
    notes = str(request.data.get("notes", "")).strip()
    if len(notes) > 1000:
        raise ValidationError({"notes": "Notes cannot exceed 1000 characters."})
    with transaction.atomic():
        try:
            load = Load.objects.select_for_update().select_related("owner").get(pk=load_id)
            truck = Truck.objects.select_for_update().select_related("owner").get(pk=truck_id)
        except Load.DoesNotExist:
            raise NotFound("Load not found")
        except Truck.DoesNotExist:
            raise NotFound("Truck not found")
        if load.status != Load.Status.SEARCHING:
            raise APIException("This load is no longer available.")
        if load.owner_id == request.user.id:
            raise ValidationError({"message": "You cannot book your own load."})
        if truck.owner_id != request.user.id and request.user.role != User.Role.ADMIN:
            raise PermissionDenied("You can only book using your own truck.")
        if not truck.is_available:
            raise ValidationError({"message": "Truck is not available."})
        if truck.capacity_tons < load.weight_tons:
            raise ValidationError({"message": "Truck capacity is too low for this load."})
        if load.required_truck_type != "other" and truck.truck_type not in (load.required_truck_type, "other"):
            raise ValidationError({"message": "Truck type does not match the load requirement."})
        if Booking.objects.filter(load=load).exclude(status=Booking.Status.CANCELLED).exists():
            raise ValidationError({"message": "A booking already exists for this load."})
        rate = Decimal(str(platform_commission_rate()))
        booking = Booking.objects.create(
            load=load,
            truck=truck,
            customer=load.owner,
            truck_owner=truck.owner,
            agreed_price=load.price,
            commission_rate=rate,
            commission_amount=(load.price * rate / Decimal("100")).quantize(Decimal("0.01")),
            payment_status=Booking.PaymentStatus.PENDING,
            notes=notes,
        )
        load.status = Load.Status.BOOKED
        load.save(update_fields=["status", "updated_at"])
        truck.is_available = False
        truck.save(update_fields=["is_available", "updated_at"])
        Notification.objects.bulk_create(
            [
                Notification(
                    recipient=load.owner,
                    notification_type="booking_payment_pending",
                    title="A truck has selected your load",
                    message="The order will be confirmed after commission payment.",
                    payload={"bookingId": booking.id, "loadId": load.id},
                ),
                Notification(
                    recipient=truck.owner,
                    notification_type="commission_payment_pending",
                    title="Commission payment required",
                    message=f"Pay ₹{booking.commission_amount} commission to confirm this order.",
                    payload={"bookingId": booking.id, "loadId": load.id},
                ),
            ]
        )
    booking = get_user_bookings(request.user).get(pk=booking.pk)
    return Response(
        {
            "message": "Truck reserved. The order is not confirmed until commission payment succeeds.",
            "booking": BookingSerializer(booking).data,
        },
        status=status.HTTP_201_CREATED,
    )


@api_view(["GET"])
def booking_detail(request, booking_id):
    booking = get_booking_for_user(request.user, booking_id)
    return Response({"booking": BookingSerializer(booking).data})


@api_view(["PATCH"])
def update_booking_status(request, booking_id):
    new_status = request.data.get("status")
    valid_statuses = {choice for choice, _ in Booking.Status.choices}
    if new_status not in valid_statuses:
        raise ValidationError({"status": "Choose a valid order status."})
    with transaction.atomic():
        booking = get_booking_for_user(request.user, booking_id, lock=True)
        if request.user.role != User.Role.ADMIN and booking.truck_owner_id != request.user.id:
            raise PermissionDenied("Only the assigned truck owner or admin can update this order.")
        if new_status == Booking.Status.CANCELLED:
            if booking.status not in (
                Booking.Status.PENDING,
                Booking.Status.CONFIRMED,
                Booking.Status.GOING_TO_PICKUP,
                Booking.Status.REACHED_PICKUP,
            ):
                raise ValidationError({"message": "This order can no longer be cancelled."})
        elif new_status not in NEXT_STATUSES.get(booking.status, []):
            raise ValidationError({"message": f"Cannot change status from {booking.status} to {new_status}."})
        if new_status != Booking.Status.CANCELLED and booking.payment_status != Booking.PaymentStatus.PAID:
            raise ValidationError({"message": "Pay the commission before confirming or advancing this order."})
        booking.status = new_status
        booking.save(update_fields=["status", "updated_at"])
        load = Load.objects.select_for_update().get(pk=booking.load_id)
        truck = Truck.objects.select_for_update().get(pk=booking.truck_id)
        if new_status == Booking.Status.CANCELLED:
            load.status = Load.Status.SEARCHING
            truck.is_available = True
        elif new_status == Booking.Status.COMPLETED:
            load.status = Load.Status.COMPLETED
            truck.is_available = True
        elif new_status in (Booking.Status.GOODS_PICKED_UP, Booking.Status.ON_THE_WAY):
            load.status = Load.Status.IN_TRANSIT
        load.save(update_fields=["status", "updated_at"])
        truck.save(update_fields=["is_available", "updated_at"])
        Notification.objects.create(
            recipient=booking.customer,
            notification_type="order_status",
            title="Order status updated",
            message=f"Order status: {booking.get_status_display()}",
            payload={"bookingId": booking.id, "status": booking.status},
        )
    booking = get_booking_for_user(request.user, booking_id)
    return Response({"message": "Booking status updated", "booking": BookingSerializer(booking).data})


@api_view(["PATCH"])
def update_tracking(request, booking_id):
    longitude = request.data.get("longitude")
    latitude = request.data.get("latitude")
    try:
        longitude = float(longitude)
        latitude = float(latitude)
    except (TypeError, ValueError):
        raise ValidationError({"message": "Valid longitude and latitude are required."})
    if not (
        math.isfinite(longitude)
        and math.isfinite(latitude)
        and -180 <= longitude <= 180
        and -90 <= latitude <= 90
    ):
        raise ValidationError({"message": "Valid longitude and latitude are required."})
    with transaction.atomic():
        booking = get_booking_for_user(request.user, booking_id, lock=True)
        if request.user.role != User.Role.ADMIN and booking.truck_owner_id != request.user.id:
            raise PermissionDenied("Only the assigned truck owner can update tracking.")
        if booking.payment_status != Booking.PaymentStatus.PAID:
            raise ValidationError({"message": "Tracking starts after commission payment confirms the order."})
        if booking.status in (Booking.Status.COMPLETED, Booking.Status.CANCELLED):
            raise ValidationError({"message": "Tracking is closed for this order."})
        location = {
            "type": "Point",
            "coordinates": [longitude, latitude],
            "updatedAt": timezone.now().isoformat(),
        }
        booking.tracking_location = location
        booking.save(update_fields=["tracking_location", "updated_at"])
        truck = booking.truck
        truck.current_location = {
            "type": "Point",
            "coordinates": [longitude, latitude],
        }
        truck.save(update_fields=["current_location", "updated_at"])
        Notification.objects.create(
            recipient=booking.customer,
            notification_type="tracking_update",
            title="Truck location updated",
            message="The active truck shared a new location.",
            payload={"bookingId": booking.id, "trackingLocation": location},
        )
    return Response({"message": "Location updated", "trackingLocation": location})


@api_view(["POST"])
def route_estimate(request):
    api_key = settings.GOOGLE_MAPS_API_KEY
    if not api_key:
        raise ProviderUnavailable("Google Maps route estimates are not configured.")

    def coordinates(field):
        values = request.data.get(field)
        if not isinstance(values, (list, tuple)) or len(values) != 2:
            raise ValidationError({field: "Coordinates must be [longitude, latitude]."})
        try:
            longitude, latitude = map(float, values)
        except (TypeError, ValueError):
            raise ValidationError({field: "Coordinates must be numeric."})
        if not (
            math.isfinite(longitude)
            and math.isfinite(latitude)
            and -180 <= longitude <= 180
            and -90 <= latitude <= 90
        ):
            raise ValidationError({field: "Coordinates are outside the valid range."})
        return [longitude, latitude]

    origin = coordinates("origin")
    destination = coordinates("destination")
    try:
        result = compute_route(origin, destination, api_key)
    except GoogleRoutesError as error:
        raise ProviderUnavailable(str(error)) from error
    return Response(result)


@api_view(["POST"])
def checkout(request, booking_id):
    with transaction.atomic():
        booking = get_booking_for_user(request.user, booking_id, lock=True)
        if request.user.role != User.Role.ADMIN and booking.truck_owner_id != request.user.id:
            raise PermissionDenied("Only the assigned truck owner can pay this commission.")
        if booking.payment_status == Booking.PaymentStatus.PAID:
            raise ValidationError({"message": "Commission has already been paid."})
        if booking.status != Booking.Status.PENDING:
            raise ValidationError({"message": "Commission payment is closed for this order."})
        if settings.PAYMENT_SANDBOX_ENABLED:
            return Response(
                {
                    "message": "Development sandbox only: no real payment will be charged.",
                    "sandbox": True,
                    "bookingId": booking.id,
                    "amount": str(booking.commission_amount),
                    "currency": "INR",
                }
            )
        if not settings.RAZORPAY_KEY_ID or not settings.RAZORPAY_KEY_SECRET:
            raise ProviderUnavailable(
                "Razorpay is not configured. No payment was taken; the order remains unconfirmed."
            )
        payment = PaymentTransaction.objects.filter(
            booking=booking,
            payer=request.user,
            provider="razorpay",
            status=PaymentTransaction.Status.PENDING,
        ).first()
        if payment is None:
            payment = PaymentTransaction.objects.create(
                booking=booking,
                payer=request.user,
                amount=booking.commission_amount,
                currency="INR",
                provider="razorpay",
                status=PaymentTransaction.Status.PENDING,
                provider_reference="",
            )
        if payment.provider_reference:
            order = {
                "id": payment.provider_reference,
                "amount": int(payment.amount * 100),
                "currency": payment.currency,
            }
        else:
            try:
                order = create_order(
                    payment,
                    key_id=settings.RAZORPAY_KEY_ID,
                    key_secret=settings.RAZORPAY_KEY_SECRET,
                )
            except RazorpayError as error:
                raise ProviderUnavailable(str(error)) from error

            payment.provider_reference = order["id"]
            payment.save(update_fields=["provider_reference", "updated_at"])

        response_data = {
            "message": "Razorpay checkout order created.",
            "provider": "razorpay",
            "keyId": settings.RAZORPAY_KEY_ID,
            "orderId": order["id"],
            "amountPaise": order["amount"],
            "amount": str(payment.amount),
            "currency": payment.currency,
            "name": "HaulMate",
            "description": f"Commission for booking {booking.id}",
            "bookingId": booking.id,
        }

    return Response(response_data)


@api_view(["POST"])
def razorpay_payment_verify(request, booking_id):
    order_id = request.data.get("razorpay_order_id")
    payment_id = request.data.get("razorpay_payment_id")
    signature = request.data.get("razorpay_signature")
    if not all(isinstance(value, str) and value for value in (order_id, payment_id, signature)):
        raise ValidationError({"message": "Razorpay order, payment, and signature are required."})
    if len(order_id) > 120 or len(payment_id) > 120 or len(signature) > 256:
        raise ValidationError({"message": "Razorpay payment details are invalid."})

    with transaction.atomic():
        booking = get_booking_for_user(request.user, booking_id, lock=True)
        if request.user.role != User.Role.ADMIN and booking.truck_owner_id != request.user.id:
            raise PermissionDenied("Only the assigned truck owner can verify this payment.")
        if booking.payment_status == Booking.PaymentStatus.PAID:
            raise ValidationError({"message": "Commission has already been paid."})
        if booking.status != Booking.Status.PENDING:
            raise ValidationError({"message": "Commission payment is closed for this order."})
        payment = PaymentTransaction.objects.select_for_update().filter(
            booking=booking,
            payer=request.user,
            provider="razorpay",
            provider_reference=order_id,
            status=PaymentTransaction.Status.PENDING,
        ).first()
        if payment is None:
            raise ValidationError({"message": "Razorpay order does not match this booking."})
        if not settings.RAZORPAY_KEY_ID or not settings.RAZORPAY_KEY_SECRET:
            raise ProviderUnavailable("Razorpay credentials are not configured.")
        expected_amount = int(payment.amount * 100)
        currency = payment.currency

    try:
        verify_payment(
            order_id=order_id,
            payment_id=payment_id,
            signature=signature,
            expected_amount=expected_amount,
            currency=currency,
            key_id=settings.RAZORPAY_KEY_ID,
            key_secret=settings.RAZORPAY_KEY_SECRET,
        )
    except RazorpayError as error:
        raise ValidationError({"message": str(error)}) from error

    with transaction.atomic():
        booking = get_booking_for_user(request.user, booking_id, lock=True)
        if request.user.role != User.Role.ADMIN and booking.truck_owner_id != request.user.id:
            raise PermissionDenied("Only the assigned truck owner can verify this payment.")
        if booking.payment_status == Booking.PaymentStatus.PAID:
            raise ValidationError({"message": "Commission has already been paid."})
        if booking.status != Booking.Status.PENDING:
            raise ValidationError({"message": "Commission payment is closed for this order."})
        payment = PaymentTransaction.objects.select_for_update().filter(
            pk=payment.pk,
            booking=booking,
            payer=request.user,
            provider="razorpay",
            provider_reference=order_id,
            status=PaymentTransaction.Status.PENDING,
        ).first()
        if payment is None:
            raise ValidationError({"message": "Razorpay order is no longer payable."})
        now = timezone.now()
        payment.status = PaymentTransaction.Status.PAID
        payment.provider_reference = payment_id
        payment.paid_at = now
        payment.save(
            update_fields=["status", "provider_reference", "paid_at", "updated_at"]
        )
        booking.payment_status = Booking.PaymentStatus.PAID
        booking.payment_provider = "razorpay"
        booking.payment_reference = payment_id
        booking.status = Booking.Status.CONFIRMED
        booking.save(
            update_fields=[
                "payment_status",
                "payment_provider",
                "payment_reference",
                "status",
                "updated_at",
            ]
        )
        Notification.objects.bulk_create(
            [
                Notification(
                recipient=booking.customer,
                notification_type="booking_confirmed",
                title="Booking confirmed",
                message="Commission payment was confirmed by Razorpay.",
                payload={"bookingId": booking.id, "status": booking.status},
                ),
                Notification(
                recipient=booking.truck_owner,
                notification_type="payment_confirmed",
                title="Commission payment confirmed",
                message="Razorpay confirmed your commission payment.",
                payload={"bookingId": booking.id, "status": booking.status},
                ),
            ]
        )
    booking = get_user_bookings(request.user).get(pk=booking.pk)
    return Response(
        {
            "message": "Razorpay payment verified and booking confirmed.",
            "booking": BookingSerializer(booking).data,
        }
    )


@api_view(["POST"])
def sandbox_payment_complete(request, booking_id):
    if not settings.PAYMENT_SANDBOX_ENABLED:
        raise ProviderUnavailable("Development sandbox payments are disabled.")
    with transaction.atomic():
        booking = get_booking_for_user(request.user, booking_id, lock=True)
        if request.user.role != User.Role.ADMIN and booking.truck_owner_id != request.user.id:
            raise PermissionDenied("Only the assigned truck owner can pay this commission.")
        if booking.payment_status == Booking.PaymentStatus.PAID:
            raise ValidationError({"message": "Commission has already been paid."})
        if booking.status != Booking.Status.PENDING:
            raise ValidationError({"message": "Commission payment is closed for this order."})
        now = timezone.now()
        transaction_record = PaymentTransaction.objects.create(
            booking=booking,
            payer=request.user,
            amount=booking.commission_amount,
            status=PaymentTransaction.Status.PAID,
            provider="development_sandbox",
            provider_reference=f"test_{booking.id}_{secrets.token_hex(6)}",
            paid_at=now,
        )
        booking.payment_status = Booking.PaymentStatus.PAID
        booking.payment_provider = transaction_record.provider
        booking.payment_reference = transaction_record.provider_reference
        booking.status = Booking.Status.CONFIRMED
        booking.save(
            update_fields=[
                "payment_status", "payment_provider", "payment_reference", "status", "updated_at",
            ]
        )
        Notification.objects.bulk_create(
            [
                Notification(
                    recipient=booking.customer,
                    notification_type="booking_confirmed",
                    title="Booking confirmed",
                    message="Commission payment was recorded in the development sandbox.",
                    payload={"bookingId": booking.id, "status": booking.status},
                ),
                Notification(
                    recipient=booking.truck_owner,
                    notification_type="payment_confirmed",
                    title="Development payment recorded",
                    message="This is a sandbox payment, not a real charge.",
                    payload={"bookingId": booking.id, "status": booking.status},
                ),
            ]
        )
    booking = get_booking_for_user(request.user, booking_id)
    return Response(
        {
            "message": "Development sandbox only: no real payment was charged.",
            "booking": BookingSerializer(booking).data,
        }
    )


@api_view(["GET", "POST"])
def booking_ratings(request, booking_id):
    booking = get_booking_for_user(request.user, booking_id)
    if request.method == "GET":
        ratings = booking.ratings.select_related("reviewer", "reviewee")
        return Response({"count": ratings.count(), "ratings": RatingSerializer(ratings, many=True).data})
    if booking.status != Booking.Status.COMPLETED:
        raise ValidationError({"message": "Ratings are available after order completion."})
    if request.user == booking.customer:
        reviewee = booking.truck_owner
    elif request.user == booking.truck_owner:
        reviewee = booking.customer
    else:
        raise PermissionDenied("Only the customer and assigned truck owner can rate this order.")
    score = request.data.get("score")
    try:
        score = int(score)
    except (TypeError, ValueError):
        raise ValidationError({"score": "Score must be an integer from 1 to 5."})
    if not 1 <= score <= 5:
        raise ValidationError({"score": "Score must be an integer from 1 to 5."})
    review = str(request.data.get("review", "")).strip()
    if len(review) > 1000:
        raise ValidationError({"review": "Review cannot exceed 1000 characters."})
    rating, created = Rating.objects.get_or_create(
        booking=booking,
        reviewer=request.user,
        defaults={"reviewee": reviewee, "score": score, "review": review},
    )
    if not created:
        raise ValidationError({"message": "You have already rated this order."})
    return Response({"message": "Rating saved", "rating": RatingSerializer(rating).data}, status=status.HTTP_201_CREATED)


@api_view(["GET"])
def notification_collection(request):
    notifications = Notification.objects.filter(recipient=request.user)
    unread_only = request.query_params.get("unread") == "true"
    if unread_only:
        notifications = notifications.filter(read_at__isnull=True)
    results = list(notifications[:500])
    return Response(
        {"count": len(results), "notifications": NotificationSerializer(results, many=True).data}
    )


@api_view(["PATCH"])
def notification_detail(request, notification_id):
    try:
        notification = Notification.objects.get(pk=notification_id, recipient=request.user)
    except Notification.DoesNotExist:
        raise NotFound("Notification not found")
    notification.read_at = timezone.now()
    notification.save(update_fields=["read_at", "updated_at"])
    return Response({"message": "Notification marked as read", "notification": NotificationSerializer(notification).data})


@api_view(["GET"])
def payment_history(request):
    payments = PaymentTransaction.objects.select_related("payer", "booking")
    if request.user.role != User.Role.ADMIN:
        payments = payments.filter(
            Q(payer=request.user)
            | Q(booking__customer=request.user)
            | Q(booking__truck_owner=request.user)
        )
    results = list(payments[:500])
    return Response(
        {
            "count": len(results),
            "transactions": PaymentTransactionSerializer(results, many=True).data,
        }
    )

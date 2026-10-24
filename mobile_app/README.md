# HaulMate Flutter App

Flutter client for the proposal-aligned Django REST API in `backend/django_api`
on port 8000.

## Features

- Phone registration and login with OTP verification
- Customer, truck-owner, and agency profiles
- Load posting, editing, cancellation, and available-load search
- Truck registration, editing, availability management, and deletion
- Nearby load matching, bookings, status updates, and cancellation
- Commission/payment history and Razorpay checkout on Android/iOS
- Foreground GPS sharing during an active booking
- Notifications and booking ratings/reviews
- Secure token storage and pull-to-refresh

## Run locally (Windows PowerShell)

1. Install Flutter and Python 3.10+, then fetch Flutter dependencies:
   ```powershell
   cd mobile_app
   flutter pub get
   ```
2. Start Django in another terminal:
   ```powershell
   cd backend/django_api
   python manage.py migrate
   python manage.py runserver 0.0.0.0:8000
   ```
   By default, local Django uses SQLite. See [backend setup](../backend/README.md)
   for PostgreSQL, Redis, and admin configuration.
3. Run the app:
   ```powershell
   cd mobile_app
   flutter run
   ```

The local development backend can return an OTP code for testing. This is
disabled outside Django debug mode. Razorpay credentials are configured on the
Django backend, never in the Flutter app; see [backend Razorpay configuration](../backend/README.md#razorpay-payments).
Checkout is currently available on Android and iOS, not web/desktop. The
development payment sandbox never charges money and is disabled outside debug
mode. Real SMS delivery, push-notification delivery, hosted document storage,
routed maps/ETA, and background GPS still require provider integrations.

## API address

The app's defaults are:

- Android emulator: `http://10.0.2.2:8000/api`
- Windows, iOS simulator, and Flutter web: `http://localhost:8000/api`

For a physical phone, set `API_BASE_URL` to your computer's LAN address (find it
with `ipconfig`):

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
```

Keep the phone and computer on the same Wi-Fi network, and allow the development
server through Windows Firewall on a private network. Do not use `localhost` on
the phone to reach the computer. Use HTTPS for release builds.

## Roles and administration

- Public registration supports `customer`, `truckOwner`, and `agency`.
- Customers and agencies can manage their loads. Truck owners and agencies can
  manage their trucks and book available loads.
- The Django web administration panel is available at
  `http://localhost:8000/admin/` after creating a Django superuser.

## Troubleshooting

- `Cannot connect to backend`: confirm Django is running on port 8000 and the
  configured `API_BASE_URL` matches the device/emulator.
- `EADDRINUSE`: another process already owns port 8000. Reuse that server or
  choose a different port and update `API_BASE_URL`.
- `401` or `403`: sign in again and confirm the account has the role required
  for the action.
- OTP unavailable: SMS delivery is not configured; local OTP is limited to
  Django debug mode.
- Razorpay unavailable: configure rotated Razorpay keys in the backend's
  private `.env` file and restart Django. Never put the key secret in Flutter.

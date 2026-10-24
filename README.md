# HaulMate Truck Booking Marketplace

HaulMate connects customers who need freight moved with truck owners and
transport agencies. The project contains a Django REST API and a Flutter app:

```text
truck-booking-app/
├── backend/
│   └── django_api/    # Django REST API, admin, and MongoDB import command
├── mobile_app/        # Flutter app for Android, iOS, Windows, and web
└── README.md          # Project overview and getting started
```

## Features

- Customer, truck-owner, and agency accounts and profiles
- Post, search, edit, and cancel loads; manage trucks and availability
- Nearby matching based on truck and load coordinates
- Bookings, commission tracking, order status updates, and cancellation
- Razorpay order creation and server-side payment verification
- In-app notifications, ratings, and reviews
- Foreground GPS sharing for active bookings
- Django admin site for marketplace administration
- Optional Google Routes estimates when a Google Maps API key is configured
- A transactional importer to preserve existing MongoDB records

## Run locally on Windows

Requirements: Python 3.10+, Flutter SDK, and PowerShell. Local development uses
SQLite by default; PostgreSQL and Redis are not required to run the app locally.

1. Install backend dependencies and initialize the local database:

   ```powershell
   cd backend/django_api
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install -r requirements.txt
   python manage.py migrate
   ```

2. In that terminal, start Django:

   ```powershell
   python manage.py runserver 0.0.0.0:8000
   ```

   Health endpoint: `http://localhost:8000/api/health`

3. In a second terminal, fetch Flutter dependencies and run the app:

   ```powershell
   cd mobile_app
   flutter pub get
   flutter run
   ```

The app uses `http://10.0.2.2:8000/api` for the Android emulator and
`http://localhost:8000/api` for web, Windows, and the iOS simulator. For a
physical phone, use the computer's LAN address:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
```

Replace the example address with the computer's IPv4 address from `ipconfig`.
The phone and computer must share a network, and the development server must be
allowed through Windows Firewall on a private network.

See the [Flutter app guide](mobile_app/README.md) for device-specific details.

## Local environment and provider configuration

Copy the backend example file to a private `.env` from the repository root:

```powershell
Copy-Item backend\.env.example backend\.env
```

## Proposal scope and current limitations

The Django and Flutter code implements the core marketplace workflows. Some
proposal items still need provider integration or production infrastructure:

- Real phone OTP delivery and push notifications are deferred; OTP codes are
  available only in Django debug mode, and notifications are in-app.
- S3-compatible image/document upload is not implemented yet.
- GPS sharing is foreground-only; background tracking is not implemented.
- Google Routes estimates need a configured key and valid coordinates. Without
  it, only straight-line matching distance is available.
- PostgreSQL and Redis/Celery are not provisioned here. Local checks use SQLite.
- MongoDB records have not been imported into PostgreSQL. Keep the MongoDB
  source intact until a separately managed PostgreSQL destination is available,
  backed up, and reviewed.

The payment sandbox is a development simulation only: it never charges money
and is disabled when Django debug mode is off. Do not use it as a substitute for
Razorpay verification.

## Preserve MongoDB records

The MongoDB importer defaults to a read-only count/dry-run. Configure
`MONGODB_URI` privately in `backend/.env`, start with the dry run, and review
the counts before considering an import:

```powershell
cd backend/django_api
python manage.py migrate_mongodb
```

Only run `python manage.py migrate_mongodb --apply` after setting up and backing
up a separately managed PostgreSQL destination and reviewing the dry-run. The
import writes to Django's configured destination inside one transaction and
does not delete or modify MongoDB source records. Never point production work at
a vendor-managed database without authorization.

## Administration

Create a Django administrator and open the admin site:

```powershell
cd backend/django_api
python manage.py createsuperuser
```

Admin URL: `http://localhost:8000/admin/`

## Verification

From `backend/django_api`:

```powershell
python manage.py check
python manage.py makemigrations --check --dry-run
python manage.py test marketplace
```

From `mobile_app`:

```powershell
flutter analyze
flutter test
flutter build web
```

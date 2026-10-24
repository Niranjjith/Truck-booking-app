import 'package:flutter_test/flutter_test.dart';
import 'package:truck_booking_mobile_app/main.dart';
import 'package:truck_booking_mobile_app/services/api_service.dart';

void main() {
  testWidgets('shows the sign-in form when no saved session exists',
      (tester) async {
    await tester.pumpWidget(
      TruckBookingApp(api: ApiService(), hasToken: false),
    );

    expect(find.text('Truck Booking'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('New here? Create an account'), findsOneWidget);
  });
}

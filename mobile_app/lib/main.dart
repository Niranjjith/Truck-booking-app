import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();
  final token = await api.readToken();
  var hasToken = false;
  if (token != null) {
    try {
      await api.getCurrentUser();
      hasToken = true;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await api.clearToken();
      } else {
        hasToken = true;
      }
    } catch (_) {
      hasToken = true;
    }
  }
  runApp(TruckBookingApp(api: api, hasToken: hasToken));
}

class TruckBookingApp extends StatelessWidget {
  final ApiService api;
  final bool hasToken;
  const TruckBookingApp({super.key, required this.api, required this.hasToken});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Truck Booking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2864E8)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(
            centerTitle: false,
            titleTextStyle: TextStyle(
                color: Color(0xFF142B4A),
                fontSize: 20,
                fontWeight: FontWeight.w800),
            iconTheme: IconThemeData(color: Color(0xFF142B4A))),
        navigationBarTheme: const NavigationBarThemeData(
            labelTextStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF2864E8), foregroundColor: Colors.white),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        cardTheme: CardThemeData(
            color: Colors.white, elevation: 0, margin: EdgeInsets.zero),
      ),
      home: hasToken ? HomeScreen(api: api) : AuthScreen(api: api),
    );
  }
}

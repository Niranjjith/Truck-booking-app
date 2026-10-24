import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();
  runApp(TruckBookingApp(api: api, restoreSession: true));
}

class TruckBookingApp extends StatefulWidget {
  final ApiService api;
  final bool hasToken;
  final bool restoreSession;

  const TruckBookingApp({
    super.key,
    required this.api,
    this.hasToken = false,
    this.restoreSession = false,
  });

  @override
  State<TruckBookingApp> createState() => _TruckBookingAppState();
}

class _TruckBookingAppState extends State<TruckBookingApp> {
  late bool _hasToken = widget.hasToken;
  late bool _isRestoring = widget.restoreSession;
  Object? _startupError;

  @override
  void initState() {
    super.initState();
    if (_isRestoring) _restoreSession();
  }

  Future<void> _restoreSession() async {
    final startedAt = DateTime.now();
    try {
      final token = await widget.api.readToken();
      var hasToken = false;
      if (token != null) {
        try {
          await widget.api.getCurrentUser();
          hasToken = true;
        } on ApiException catch (error) {
          if (error.statusCode == 401) {
            await widget.api.clearToken();
          } else {
            hasToken = true;
          }
        } catch (_) {
          hasToken = true;
        }
      }

      final remaining = const Duration(milliseconds: 1100) -
          DateTime.now().difference(startedAt);
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      if (!mounted) return;
      setState(() {
        _hasToken = hasToken;
        _isRestoring = false;
        _startupError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startupError = error;
        _isRestoring = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HaulMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2864E8),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: const Color(0xFF142B4A),
              displayColor: const Color(0xFF142B4A),
            ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF142B4A),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
          iconTheme: IconThemeData(color: Color(0xFF142B4A)),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF2864E8),
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(15)),
            borderSide: BorderSide(color: Color(0xFFE4EAF2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(15)),
            borderSide: BorderSide(color: Color(0xFFE4EAF2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(15)),
            borderSide: BorderSide(color: Color(0xFF2864E8), width: 1.5),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      home: _isRestoring
          ? const SplashScreen()
          : _startupError != null
              ? _StartupErrorScreen(
                  error: _startupError!,
                  onRetry: () => setState(() {
                    _startupError = null;
                    _isRestoring = true;
                    _restoreSession();
                  }),
                )
              : _hasToken
                  ? HomeScreen(api: widget.api)
                  : AuthScreen(api: widget.api),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _StartupErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Could not start HaulMate',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiService {
  static const String _configuredBaseUrl =
      String.fromEnvironment('API_BASE_URL');
  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://localhost:8000/api';
  }

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<String?> readToken() => _storage.read(key: 'auth_token');
  Future<void> saveToken(String token) =>
      _storage.write(key: 'auth_token', value: token);

  Future<void> _saveSession(Map<String, dynamic> result) async {
    final token = result['token'];
    final refresh = result['refresh'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Backend did not return an access token.');
    }
    await _storage.write(key: 'auth_token', value: token);
    if (refresh is String && refresh.isNotEmpty) {
      await _storage.write(key: 'refresh_token', value: refresh);
    }
  }

  Future<void> clearToken() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'refresh_token');
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic>? body,
  ) {
    final encodedBody = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'POST':
        return http
            .post(uri, headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 20));
      case 'PATCH':
        return http
            .patch(uri, headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 20));
      case 'DELETE':
        return http
            .delete(uri, headers: headers)
            .timeout(const Duration(seconds: 20));
      default:
        return http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 20));
    }
  }

  Future<Map<String, dynamic>?> _refreshAccessToken() async {
    final refresh = await _storage.read(key: 'refresh_token');
    if (refresh == null || refresh.isEmpty) {
      return null;
    }
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/token/refresh'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh': refresh}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        await clearToken();
      }
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['access'] is! String) {
      throw const FormatException(
          'Backend returned an invalid refreshed session.');
    }
    await _storage.write(key: 'auth_token', value: decoded['access'] as String);
    if (decoded['refresh'] is String) {
      await _storage.write(
        key: 'refresh_token',
        value: decoded['refresh'] as String,
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    var token = await readToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated && token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    final uri = Uri.parse('$baseUrl$path');
    late http.Response response;
    try {
      response = await _send(method, uri, headers, body);
      if (authenticated && response.statusCode == 401) {
        final refreshed = await _refreshAccessToken();
        token = refreshed?['access'] as String?;
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
          response = await _send(method, uri, headers, body);
        }
      }
    } on TimeoutException {
      throw Exception('The backend at $baseUrl did not respond in time.');
    } catch (error) {
      if (error is ApiException || error is FormatException) {
        rethrow;
      }
      throw Exception(
        'Cannot connect to the backend at $baseUrl. Check that Django is running and API_BASE_URL is correct.',
      );
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      decoded = <String, dynamic>{'message': response.body};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? (decoded['message'] ?? decoded['detail'] ?? 'Request failed')
          : 'Request failed';
      throw ApiException(response.statusCode, message.toString());
    }
    if (decoded is! Map) {
      throw const FormatException('Backend returned an unexpected response.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> login({
    String? email,
    String? phone,
    required String password,
  }) async {
    final result = await request(
      'POST',
      '/auth/login',
      authenticated: false,
      body: {
        'email': email,
        'phone': phone,
        'password': password,
      }..removeWhere(
          (key, value) => value == null || (value is String && value.isEmpty),
        ),
    );
    if (result['token'] != null) {
      await _saveSession(result);
    }
    return result;
  }

  Future<Map<String, dynamic>> register({
    required String name,
    String? email,
    String? phone,
    required String password,
    required String role,
    String? agencyName,
  }) async {
    final result = await request(
      'POST',
      '/auth/register',
      authenticated: false,
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role,
        'agencyName': agencyName,
      }..removeWhere(
          (key, value) => value == null || (value is String && value.isEmpty),
        ),
    );
    if (result['token'] != null) {
      await _saveSession(result);
    }
    return result;
  }

  Future<Map<String, dynamic>> requestOtp(String phone) =>
      request('POST', '/auth/otp/request',
          authenticated: false, body: {'phone': phone});

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final result = await request(
      'POST',
      '/auth/otp/verify',
      authenticated: false,
      body: {'phone': phone, 'code': code},
    );
    await _saveSession(result);
    return result;
  }

  Future<List<dynamic>> listLoads() async =>
      (await request('GET', '/loads'))['loads'] as List<dynamic>? ?? [];

  Future<List<dynamic>> listMyLoads() async =>
      (await request('GET', '/loads?mine=true&includeClosed=true'))['loads']
          as List<dynamic>? ??
      [];

  Future<List<dynamic>> listMatchingLoads() async =>
      (await request('GET', '/loads/matches'))['loads'] as List<dynamic>? ?? [];

  Future<List<dynamic>> listTrucks() async =>
      (await request('GET', '/trucks'))['trucks'] as List<dynamic>? ?? [];

  Future<List<dynamic>> listMyTrucks() async =>
      (await request('GET', '/trucks?mine=true'))['trucks'] as List<dynamic>? ??
      [];

  Future<List<dynamic>> listBookings() async =>
      (await request('GET', '/bookings'))['bookings'] as List<dynamic>? ?? [];

  Future<List<dynamic>> listNotifications() async =>
      (await request('GET', '/notifications'))['notifications']
          as List<dynamic>? ??
      [];

  Future<List<dynamic>> listPayments() async =>
      (await request('GET', '/payments'))['transactions'] as List<dynamic>? ??
      [];

  Future<Map<String, dynamic>> getCurrentUser() async =>
      (await request('GET', '/auth/me'))['user'] as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) =>
      request('PATCH', '/auth/me', body: body);

  Future<Map<String, dynamic>> createLoad(Map<String, dynamic> body) =>
      request('POST', '/loads', body: body);

  Future<Map<String, dynamic>> updateLoad(
    String loadId,
    Map<String, dynamic> body,
  ) =>
      request('PATCH', '/loads/$loadId', body: body);

  Future<Map<String, dynamic>> cancelLoad(String loadId) =>
      request('PATCH', '/loads/$loadId/cancel');

  Future<Map<String, dynamic>> deleteTruck(String truckId) =>
      request('DELETE', '/trucks/$truckId');

  Future<Map<String, dynamic>> createTruck(Map<String, dynamic> body) =>
      request('POST', '/trucks', body: body);

  Future<Map<String, dynamic>> updateTruck(
    String truckId,
    Map<String, dynamic> body,
  ) =>
      request('PATCH', '/trucks/$truckId', body: body);

  Future<Map<String, dynamic>> createBooking({
    required String loadId,
    required String truckId,
    String? notes,
  }) =>
      request('POST', '/bookings', body: {
        'loadId': loadId,
        'truckId': truckId,
        if (notes != null) 'notes': notes,
      });

  Future<Map<String, dynamic>> updateBookingStatus(
    String bookingId,
    String status,
  ) =>
      request('PATCH', '/bookings/$bookingId/status', body: {'status': status});

  Future<Map<String, dynamic>> updateTracking({
    required String bookingId,
    required double longitude,
    required double latitude,
  }) =>
      request(
        'PATCH',
        '/bookings/$bookingId/tracking',
        body: {'longitude': longitude, 'latitude': latitude},
      );

  Future<Map<String, dynamic>> estimateRoute({
    required List<double> origin,
    required List<double> destination,
  }) =>
      request(
        'POST',
        '/routes/estimate',
        body: {'origin': origin, 'destination': destination},
      );

  Future<Map<String, dynamic>> checkoutBooking(String bookingId) =>
      request('POST', '/bookings/$bookingId/checkout');

  Future<Map<String, dynamic>> verifyRazorpayPayment({
    required String bookingId,
    required String orderId,
    required String paymentId,
    required String signature,
  }) =>
      request(
        'POST',
        '/bookings/$bookingId/payments/razorpay-verify',
        body: {
          'razorpay_order_id': orderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
        },
      );

  Future<Map<String, dynamic>> completeSandboxPayment(String bookingId) =>
      request('POST', '/bookings/$bookingId/payments/sandbox-complete');

  Future<List<dynamic>> listRatings(String bookingId) async =>
      (await request('GET', '/bookings/$bookingId/ratings'))['ratings']
          as List<dynamic>? ??
      [];

  Future<Map<String, dynamic>> rateBooking({
    required String bookingId,
    required int score,
    String? review,
  }) =>
      request(
        'POST',
        '/bookings/$bookingId/ratings',
        body: {'score': score, if (review != null) 'review': review},
      );

  Future<Map<String, dynamic>> markNotificationRead(String notificationId) =>
      request('PATCH', '/notifications/$notificationId/read');
}

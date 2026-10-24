import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class BookingsScreen extends StatefulWidget {
  final ApiService api;

  const BookingsScreen({super.key, required this.api});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen>
    with WidgetsBindingObserver {
  late Future<List<dynamic>> _future;
  late Future<Map<String, dynamic>> _userFuture;
  Timer? _gpsTimer;
  Razorpay? _razorpay;
  String? _sharingBookingId;
  String? _busyBookingId;
  String? _razorpayBookingId;
  bool _sendingLocation = false;

  static const _nextStatuses = <String, String>{
    'pending': 'confirmed',
    'confirmed': 'goingToPickup',
    'goingToPickup': 'reachedPickup',
    'reachedPickup': 'loading',
    'loading': 'goodsPickedUp',
    'goodsPickedUp': 'onTheWay',
    'onTheWay': 'nearDelivery',
    'nearDelivery': 'reachedDelivery',
    'reachedDelivery': 'delivered',
    'delivered': 'completed',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = widget.api.listBookings();
    _userFuture = widget.api.getCurrentUser();
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      _razorpay = Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onRazorpaySuccess)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, _onRazorpayError);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _gpsTimer?.cancel();
      _gpsTimer = null;
      if (mounted && _sharingBookingId != null) {
        setState(() => _sharingBookingId = null);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsTimer?.cancel();
    _razorpay?.clear();
    super.dispose();
  }

  Future<void> _onRazorpaySuccess(PaymentSuccessResponse response) async {
    final bookingId = _razorpayBookingId;
    if (bookingId == null ||
        response.orderId == null ||
        response.paymentId == null ||
        response.signature == null) {
      return;
    }
    _razorpayBookingId = null;
    try {
      await widget.api.verifyRazorpayPayment(
        bookingId: bookingId,
        orderId: response.orderId!,
        paymentId: response.paymentId!,
        signature: response.signature!,
      );
      if (!mounted) return;
      setState(() => _busyBookingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment confirmed. Booking updated.')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyBookingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment was submitted, but confirmation failed. Contact support before retrying. ${error.toString()}',
          ),
        ),
      );
      await _refresh();
    }
  }

  void _onRazorpayError(PaymentFailureResponse response) {
    _razorpayBookingId = null;
    if (!mounted) return;
    setState(() => _busyBookingId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response.message ?? 'Razorpay checkout was cancelled or failed.',
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.api.listBookings();
      _userFuture = widget.api.getCurrentUser();
    });
    try {
      await Future.wait([_future, _userFuture]);
    } catch (_) {
      // FutureBuilder renders the request error.
    }
  }

  String? _id(dynamic value) {
    if (value is Map) {
      return value['_id']?.toString() ?? value['id']?.toString();
    }
    return value?.toString();
  }

  Future<void> _setStatus(String bookingId, String status) async {
    try {
      await widget.api.updateBookingStatus(bookingId, status);
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<Position> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Turn on location services to share delivery tracking.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception(
          'Allow location access while using the app to share GPS.');
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _sendCurrentLocation(String bookingId) async {
    if (_sendingLocation || !mounted) return;
    _sendingLocation = true;
    try {
      final position = await _currentPosition();
      await widget.api.updateTracking(
        bookingId: bookingId,
        longitude: position.longitude,
        latitude: position.latitude,
      );
    } catch (error) {
      _gpsTimer?.cancel();
      _gpsTimer = null;
      if (mounted) {
        setState(() => _sharingBookingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      _sendingLocation = false;
    }
  }

  Future<void> _toggleGps(String bookingId) async {
    if (_sharingBookingId == bookingId) {
      _gpsTimer?.cancel();
      _gpsTimer = null;
      setState(() => _sharingBookingId = null);
      return;
    }
    if (_sharingBookingId != null) {
      _gpsTimer?.cancel();
      _gpsTimer = null;
      _sharingBookingId = null;
    }
    setState(() => _sharingBookingId = bookingId);
    await _sendCurrentLocation(bookingId);
    if (!mounted || _sharingBookingId != bookingId) return;
    _gpsTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _sendCurrentLocation(bookingId),
    );
  }

  Future<void> _payCommission(String bookingId) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Razorpay checkout is available in the Android and iOS apps.'),
        ),
      );
      return;
    }
    setState(() => _busyBookingId = bookingId);
    try {
      final checkout = await widget.api.checkoutBooking(bookingId);
      if (!mounted) return;
      if (checkout['sandbox'] == true) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Development payment simulation'),
            content: Text(
              'This is a sandbox only. No real payment will be taken. Simulate payment of ₹${checkout['amount']} and confirm this booking?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Simulate payment'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await widget.api.completeSandboxPayment(bookingId);
        await _refresh();
      } else {
        final keyId = checkout['keyId']?.toString();
        final orderId = checkout['orderId']?.toString();
        final amount = checkout['amountPaise'];
        if (checkout['provider'] != 'razorpay' ||
            keyId == null ||
            orderId == null ||
            amount is! int ||
            _razorpay == null) {
          throw Exception('The payment provider returned an invalid checkout.');
        }
        _razorpayBookingId = bookingId;
        final user = await _userFuture;
        _razorpay!.open({
          'key': keyId,
          'order_id': orderId,
          'amount': amount,
          'currency': checkout['currency'] ?? 'INR',
          'name': checkout['name'] ?? 'HaulMate',
          'description': checkout['description'] ?? 'Booking commission',
          'prefill': {
            'contact': user['phone'] ?? '',
            'email': user['email'] ?? '',
          },
          'notes': {'booking_id': bookingId},
        });
      }
    } catch (error) {
      _razorpayBookingId = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted && _razorpayBookingId == null) {
        setState(() => _busyBookingId = null);
      }
    }
  }

  Future<void> _rateBooking(String bookingId) async {
    final review = TextEditingController();
    var score = 5;
    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Rate this delivery'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  children: List.generate(
                    5,
                    (index) => IconButton(
                      tooltip: '${index + 1} stars',
                      onPressed: () => setDialogState(() => score = index + 1),
                      icon: Icon(
                        index < score ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ),
                TextField(
                  controller: review,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Review (optional)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Submit rating'),
              ),
            ],
          ),
        ),
      );
      if (submitted != true || !mounted) return;
      await widget.api.rateBooking(
        bookingId: bookingId,
        score: score,
        review: review.text.trim().isEmpty ? null : review.text.trim(),
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      review.dispose();
    }
  }

  Widget _trackingSummary(Map<String, dynamic> location, dynamic delivery) {
    final coordinates = location['coordinates'];
    if (coordinates is! List || coordinates.length != 2) {
      return const SizedBox.shrink();
    }
    final longitude = num.tryParse(coordinates[0].toString());
    final latitude = num.tryParse(coordinates[1].toString());
    if (longitude == null || latitude == null) return const SizedBox.shrink();
    double? distanceKm;
    if (delivery is Map) {
      final destination = delivery['coordinates'];
      if (destination is List && destination.length == 2) {
        final destinationLongitude =
            num.tryParse(destination[0].toString())?.toDouble();
        final destinationLatitude =
            num.tryParse(destination[1].toString())?.toDouble();
        if (destinationLongitude != null && destinationLatitude != null) {
          distanceKm = Geolocator.distanceBetween(
                latitude.toDouble(),
                longitude.toDouble(),
                destinationLatitude,
                destinationLongitude,
              ) /
              1000;
        }
      }
    }
    final updatedAt =
        DateTime.tryParse(location['updatedAt']?.toString() ?? '');
    final destinationCoordinates =
        delivery is Map ? delivery['coordinates'] : null;
    final hasDestination = destinationCoordinates is List &&
        destinationCoordinates.length == 2 &&
        num.tryParse(destinationCoordinates[0].toString()) != null &&
        num.tryParse(destinationCoordinates[1].toString()) != null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF0FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latest shared truck location',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
            ),
            if (hasDestination) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _openDeliveryRoute(
                  longitude.toDouble(),
                  latitude.toDouble(),
                  destinationCoordinates,
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Route and ETA'),
              ),
            ],
            if (distanceKm != null) ...[
              const SizedBox(height: 4),
              Text(
                'About ${distanceKm.toStringAsFixed(1)} km from delivery (straight-line estimate; route ETA needs a maps provider).',
              ),
            ],
            if (updatedAt != null)
              Text(
                'Updated ${updatedAt.toLocal()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDeliveryRoute(
    double longitude,
    double latitude,
    List<dynamic> destination,
  ) async {
    final destinationLongitude =
        num.parse(destination[0].toString()).toDouble();
    final destinationLatitude = num.parse(destination[1].toString()).toDouble();
    try {
      final estimate = await widget.api.estimateRoute(
        origin: [longitude, latitude],
        destination: [destinationLongitude, destinationLatitude],
      );
      if (!mounted) return;
      final distanceMeters = estimate['distanceMeters'];
      final durationSeconds = estimate['durationSeconds'];
      if (distanceMeters is! num || durationSeconds is! num) {
        throw const FormatException('The route estimate response was invalid.');
      }
      final mapsUri = Uri.https(
        'www.google.com',
        '/maps/dir/',
        {
          'api': '1',
          'origin': '$latitude,$longitude',
          'destination': '$destinationLatitude,$destinationLongitude',
          'travelmode': 'driving',
        },
      );
      final openMaps = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Google Maps route estimate'),
          content: Text(
            '${(distanceMeters / 1000).toStringAsFixed(1)} km · '
            '${(durationSeconds / 60).round()} min (traffic-aware estimate)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open directions'),
            ),
          ],
        ),
      );
      if (openMaps == true && await canLaunchUrl(mapsUri)) {
        await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(snapshot.error.toString(), textAlign: TextAlign.center),
                TextButton(onPressed: _refresh, child: const Text('Try again')),
              ],
            );
          }

          final bookings = snapshot.data ?? [];
          if (bookings.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                Icon(Icons.receipt_long, size: 56, color: Colors.grey),
                SizedBox(height: 12),
                Center(child: Text('No bookings yet.')),
              ],
            );
          }

          return FutureBuilder<Map<String, dynamic>>(
            future: _userFuture,
            builder: (context, userSnapshot) {
              final userId =
                  _id(userSnapshot.data?['id'] ?? userSnapshot.data?['_id']);
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: bookings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final booking =
                      Map<String, dynamic>.from(bookings[index] as Map);
                  final load = booking['load'] is Map
                      ? Map<String, dynamic>.from(booking['load'] as Map)
                      : <String, dynamic>{};
                  final truck = booking['truck'] is Map
                      ? Map<String, dynamic>.from(booking['truck'] as Map)
                      : <String, dynamic>{};
                  final status = booking['status']?.toString() ?? 'pending';
                  final bookingId = _id(booking);
                  final isAssignedOwner =
                      userId != null && _id(booking['truckOwner']) == userId;
                  final nextStatus = _nextStatuses[status];
                  final paymentStatus =
                      booking['paymentStatus']?.toString() ?? 'pending';
                  final trackingLocation = booking['trackingLocation'] is Map
                      ? Map<String, dynamic>.from(
                          booking['trackingLocation'] as Map,
                        )
                      : <String, dynamic>{};
                  final isActiveOrder = paymentStatus == 'paid' &&
                      !{'pending', 'completed', 'cancelled'}.contains(status);
                  final canCancel = const {
                    'pending',
                    'confirmed',
                    'goingToPickup',
                    'reachedPickup',
                  }.contains(status);

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.local_shipping_outlined),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  load['loadType']?.toString() ??
                                      'Truck booking',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                              Text('₹${booking['agreedPrice'] ?? '-'}'),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                              'Truck: ${truck['registrationNumber'] ?? 'Not available'}'),
                          const SizedBox(height: 6),
                          Text(
                              'Status: ${status.replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}')}'),
                          Text(
                            'Commission: ₹${booking['commissionAmount'] ?? '-'} · Payment: $paymentStatus',
                          ),
                          if (booking['notes'] != null &&
                              booking['notes'].toString().isNotEmpty)
                            Text('Notes: ${booking['notes']}'),
                          if (trackingLocation.isNotEmpty)
                            _trackingSummary(
                                trackingLocation, load['delivery']),
                          if (isAssignedOwner &&
                              bookingId != null &&
                              status == 'pending') ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _busyBookingId == bookingId
                                    ? null
                                    : () => _payCommission(bookingId),
                                icon: const Icon(Icons.payments_outlined),
                                label: Text(
                                  _busyBookingId == bookingId
                                      ? 'Preparing secure checkout...'
                                      : 'Pay commission ₹${booking['commissionAmount'] ?? '-'}',
                                ),
                              ),
                            ),
                          ],
                          if (isAssignedOwner &&
                              bookingId != null &&
                              (nextStatus != null ||
                                  canCancel ||
                                  isActiveOrder)) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (nextStatus != null)
                                  OutlinedButton(
                                    onPressed: () =>
                                        _setStatus(bookingId, nextStatus),
                                    child: Text(
                                      'Update to ${nextStatus.replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}')}',
                                    ),
                                  ),
                                if (canCancel)
                                  TextButton(
                                    onPressed: () =>
                                        _setStatus(bookingId, 'cancelled'),
                                    child: const Text('Cancel booking'),
                                  ),
                                if (isActiveOrder)
                                  OutlinedButton.icon(
                                    onPressed: () => _toggleGps(bookingId),
                                    icon: Icon(
                                      _sharingBookingId == bookingId
                                          ? Icons.location_off
                                          : Icons.my_location,
                                    ),
                                    label: Text(
                                      _sharingBookingId == bookingId
                                          ? 'Stop GPS sharing'
                                          : 'Share live GPS',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (bookingId != null &&
                              status == 'completed' &&
                              userId != null &&
                              (userId == _id(booking['customer']) ||
                                  isAssignedOwner))
                            TextButton.icon(
                              onPressed: () => _rateBooking(bookingId),
                              icon: const Icon(Icons.star_outline),
                              label: const Text('Rate this delivery'),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

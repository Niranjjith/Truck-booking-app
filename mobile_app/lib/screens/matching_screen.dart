import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'create_booking_screen.dart';

class MatchingScreen extends StatefulWidget {
  final ApiService api;

  const MatchingScreen({super.key, required this.api});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.request('GET', '/loads/matches');
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.request('GET', '/loads/matches'));
    try {
      await _future;
    } catch (_) {
      // FutureBuilder renders the request error.
    }
  }

  Future<void> _book(Map<String, dynamic> load) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateBookingScreen(api: widget.api, load: load),
      ),
    );
    if (result == true) await _refresh();
  }

  String _place(dynamic value) {
    if (value is! Map) return 'Location not provided';
    return [
      value['city'],
      value['state'],
      value['address'],
    ]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby matching loads'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh matches',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
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
                  const SizedBox(height: 8),
                  const Text(
                    'Matching uses the current coordinates of your available trucks and each load pickup location.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                      onPressed: _refresh, child: const Text('Try again')),
                ],
              );
            }
            final loads = snapshot.data?['loads'] as List<dynamic>? ?? [];
            final distances = snapshot.data?['distancesKm'] as Map? ?? {};
            if (loads.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 80),
                  Icon(Icons.near_me_outlined, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Center(child: Text('No nearby matching loads.')),
                  SizedBox(height: 8),
                  Text(
                    'Make sure one of your available trucks has shared a current GPS location.',
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: loads.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final load = Map<String, dynamic>.from(loads[index] as Map);
                final distance = distances[load['id']?.toString()];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          load['loadType']?.toString() ?? 'Freight load',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                            '${_place(load['pickup'])} → ${_place(load['delivery'])}'),
                        const SizedBox(height: 6),
                        Text(
                          '${load['weightTons'] ?? '-'} tons · ${load['requiredTruckType'] ?? 'Any truck'} · ₹${load['price'] ?? '-'}',
                        ),
                        if (distance != null)
                          Text(
                              '${distance.toString()} km from your available fleet'),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => _book(load),
                            child: const Text('Choose truck and book'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

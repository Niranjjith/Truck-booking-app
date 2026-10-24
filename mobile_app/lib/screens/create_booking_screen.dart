import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CreateBookingScreen extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> load;

  const CreateBookingScreen({super.key, required this.api, required this.load});

  @override
  State<CreateBookingScreen> createState() => _CreateBookingScreenState();
}

class _CreateBookingScreenState extends State<CreateBookingScreen> {
  late Future<List<Map<String, dynamic>>> _trucks;
  final _notes = TextEditingController();
  String? _selectedTruckId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _trucks = _loadTrucks();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String? _id(dynamic value) {
    if (value is Map) {
      return value['_id']?.toString() ?? value['id']?.toString();
    }
    return value?.toString();
  }

  Future<List<Map<String, dynamic>>> _loadTrucks() async {
    final user = await widget.api.getCurrentUser();
    final userId = _id(user['id'] ?? user['_id']);
    if (userId == null) {
      throw Exception(
          'Could not identify the signed-in account. Please sign in again.');
    }

    final requiredType = widget.load['requiredTruckType']?.toString();
    final weight = num.tryParse(widget.load['weightTons']?.toString() ?? '');
    final trucks = await widget.api.listTrucks();
    return trucks
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((truck) {
      final ownerId = _id(truck['owner']);
      final truckType = truck['truckType']?.toString();
      final capacity = num.tryParse(truck['capacityTons']?.toString() ?? '');
      final typeMatches = truckType == requiredType ||
          requiredType == 'other' ||
          truckType == 'other';
      return ownerId == userId &&
          truck['isAvailable'] != false &&
          capacity != null &&
          weight != null &&
          capacity >= weight &&
          typeMatches;
    }).toList();
  }

  Future<void> _book(Map<String, dynamic> truck) async {
    final loadId = _id(widget.load);
    final truckId = _id(truck);
    if (loadId == null || truckId == null) {
      _showError('The load or truck is missing an ID. Refresh and try again.');
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.api.createBooking(
        loadId: loadId,
        truckId: truckId,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      _showError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a truck')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _trucks,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(snapshot.error.toString(),
                        textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () => setState(() => _trucks = _loadTrucks()),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final trucks = snapshot.data ?? [];
          if (trucks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You do not have an available truck that matches this load. Register a suitable truck or choose another load.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final selectedId =
              trucks.any((truck) => _id(truck) == _selectedTruckId)
                  ? _selectedTruckId
                  : _id(trucks.first);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${widget.load['loadType'] ?? 'Freight load'} · ${widget.load['weightTons'] ?? '-'} tons',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (final truck in trucks)
                Card(
                  child: ListTile(
                    selected: _id(truck) == selectedId,
                    leading: Icon(
                      _id(truck) == selectedId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: _busy
                        ? null
                        : () => setState(() => _selectedTruckId = _id(truck)),
                    title: Text(
                        truck['registrationNumber']?.toString() ?? 'Truck'),
                    subtitle: Text(
                      '${truck['truckType']} · ${truck['capacityTons']} tons capacity',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Notes (optional)'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || selectedId == null
                    ? null
                    : () {
                        final truck = trucks
                            .firstWhere((item) => _id(item) == selectedId);
                        _book(truck);
                      },
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Book this load'),
              ),
            ],
          );
        },
      ),
    );
  }
}

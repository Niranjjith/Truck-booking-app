import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PaymentsScreen extends StatefulWidget {
  final ApiService api;

  const PaymentsScreen({super.key, required this.api});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.listPayments();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.listPayments());
    try {
      await _future;
    } catch (_) {
      // FutureBuilder renders the request error.
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
          final payments = snapshot.data ?? [];
          if (payments.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                Icon(Icons.payments_outlined, size: 56, color: Colors.grey),
                SizedBox(height: 12),
                Center(child: Text('No commission transactions yet.')),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'A payment transaction appears here only when a payment provider confirms it. Pending payment requests are not charges.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: payments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final payment = Map<String, dynamic>.from(payments[index] as Map);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(
                      '₹${payment['amount'] ?? '-'} · ${payment['status'] ?? 'unknown'}'),
                  subtitle: Text(
                    'Order: ${payment['bookingId'] ?? '-'} · Provider: ${payment['provider']?.toString().isNotEmpty == true ? payment['provider'] : 'Not configured'}',
                  ),
                  trailing: Text(payment['currency']?.toString() ?? 'INR'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

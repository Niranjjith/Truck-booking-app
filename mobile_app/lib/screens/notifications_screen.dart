import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  final ApiService api;

  const NotificationsScreen({super.key, required this.api});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.listNotifications();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.listNotifications());
    try {
      await _future;
    } catch (_) {
      // FutureBuilder renders the request error.
    }
  }

  Future<void> _markRead(Map<String, dynamic> notification) async {
    final id =
        notification['id']?.toString() ?? notification['_id']?.toString();
    if (id == null || notification['readAt'] != null) return;
    try {
      await widget.api.markNotificationRead(id);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh notifications',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
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
                  TextButton(
                      onPressed: _refresh, child: const Text('Try again')),
                ],
              );
            }
            final notifications = snapshot.data ?? [];
            if (notifications.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.notifications_none, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Center(child: Text('No notifications yet.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item =
                    Map<String, dynamic>.from(notifications[index] as Map);
                final unread = item['readAt'] == null;
                return Card(
                  child: ListTile(
                    onTap: () => _markRead(item),
                    leading: Icon(
                      unread
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_none,
                    ),
                    title: Text(
                      item['title']?.toString() ?? 'Update',
                      style: TextStyle(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    subtitle: Text(
                      item['message']?.toString() ?? '',
                    ),
                    trailing: unread
                        ? const Icon(Icons.circle, size: 10, color: Colors.blue)
                        : null,
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

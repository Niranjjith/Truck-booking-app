import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  final ApiService api;

  const ProfileScreen({super.key, required this.api});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _agencyName = TextEditingController();
  late Future<Map<String, dynamic>> _future;
  String? _loadedUserId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getCurrentUser();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _agencyName.dispose();
    super.dispose();
  }

  void _populate(Map<String, dynamic> user) {
    final id = user['id']?.toString();
    if (_loadedUserId == id) return;
    _loadedUserId = id;
    _name.text = user['name']?.toString() ?? '';
    _email.text = user['email']?.toString() ?? '';
    _agencyName.text = user['agencyName']?.toString() ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = await widget.api.updateProfile({
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'agencyName': _agencyName.text.trim(),
      });
      final user = Map<String, dynamic>.from(result['user'] as Map);
      _loadedUserId = null;
      _populate(user);
      setState(() => _future = Future.value(user));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snapshot.error.toString(),
                    textAlign: TextAlign.center),
              ),
            );
          }
          final user = snapshot.data!;
          _populate(user);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: user['phone']?.toString() ?? '',
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Verified mobile number',
                    suffixIcon: Icon(
                      user['isVerified'] == true
                          ? Icons.verified
                          : Icons.info_outline,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                if (user['role'] == 'agency') ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _agencyName,
                    decoration: const InputDecoration(labelText: 'Agency name'),
                  ),
                ],
                const SizedBox(height: 14),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Account type'),
                  child: Text(user['role']?.toString() ?? 'customer'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const CircularProgressIndicator()
                      : const Text('Save profile'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

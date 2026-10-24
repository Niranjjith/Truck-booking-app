import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CreateTruckScreen extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic>? initialTruck;
  const CreateTruckScreen({super.key, required this.api, this.initialTruck});
  @override
  State<CreateTruckScreen> createState() => _CreateTruckScreenState();
}

class _CreateTruckScreenState extends State<CreateTruckScreen> {
  final _form = GlobalKey<FormState>();
  final _registration = TextEditingController(),
      _capacity = TextEditingController(),
      _agency = TextEditingController(),
      _description = TextEditingController();
  String _type = 'mini';
  bool _busy = false, _available = true;
  bool get _editing => widget.initialTruck != null;
  String? get _truckId =>
      widget.initialTruck?['id']?.toString() ??
      widget.initialTruck?['_id']?.toString();
  @override
  void initState() {
    super.initState();
    final truck = widget.initialTruck;
    if (truck != null) {
      _registration.text = truck['registrationNumber']?.toString() ?? '';
      _capacity.text = truck['capacityTons']?.toString() ?? '';
      _agency.text = truck['agencyName']?.toString() ?? '';
      _description.text = truck['description']?.toString() ?? '';
      _type = truck['truckType']?.toString() ?? 'mini';
      _available = truck['isAvailable'] != false;
    }
  }

  @override
  void dispose() {
    _registration.dispose();
    _capacity.dispose();
    _agency.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final body = {
        'registrationNumber': _registration.text.trim(),
        'truckType': _type,
        'capacityTons': double.parse(_capacity.text),
        'agencyName': _agency.text.trim(),
        'description': _description.text.trim(),
        'isAvailable': _available
      };
      if (_editing && _truckId != null) {
        await widget.api.updateTruck(_truckId!, body);
      } else {
        await widget.api.createTruck(body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar:
          AppBar(title: Text(_editing ? 'Manage truck' : 'Register a truck')),
      body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextFormField(
                controller: _registration,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    const InputDecoration(labelText: 'Registration number'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter registration number'
                    : null),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Truck type'),
                items: const [
                  'mini',
                  'pickup',
                  'light',
                  'medium',
                  'heavy',
                  'trailer',
                  'container',
                  'other'
                ]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? 'mini')),
            const SizedBox(height: 14),
            TextFormField(
                controller: _capacity,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Capacity (tons)'),
                validator: (v) => v == null ||
                        double.tryParse(v) == null ||
                        double.parse(v) <= 0
                    ? 'Enter capacity greater than zero'
                    : null),
            const SizedBox(height: 14),
            TextFormField(
                controller: _agency,
                decoration:
                    const InputDecoration(labelText: 'Agency name (optional)')),
            const SizedBox(height: 14),
            TextFormField(
                controller: _description,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)')),
            const SizedBox(height: 8),
            SwitchListTile(
                title: const Text('Available for bookings'),
                value: _available,
                onChanged: (v) => setState(() => _available = v)),
            const SizedBox(height: 18),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy
                    ? 'Saving...'
                    : _editing
                        ? 'Save changes'
                        : 'Register truck')),
          ])));
}

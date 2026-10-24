import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CreateLoadScreen extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic>? initialLoad;
  const CreateLoadScreen({super.key, required this.api, this.initialLoad});
  @override
  State<CreateLoadScreen> createState() => _CreateLoadScreenState();
}

class _CreateLoadScreenState extends State<CreateLoadScreen> {
  final _form = GlobalKey<FormState>();
  final _pickup = TextEditingController(),
      _pickupCity = TextEditingController(),
      _pickupState = TextEditingController(),
      _delivery = TextEditingController(),
      _deliveryCity = TextEditingController(),
      _deliveryState = TextEditingController(),
      _type = TextEditingController(),
      _weight = TextEditingController(),
      _price = TextEditingController(),
      _description = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  String _truckType = 'mini';
  bool _busy = false;
  bool get _editing => widget.initialLoad != null;
  String? get _loadId =>
      widget.initialLoad?['id']?.toString() ??
      widget.initialLoad?['_id']?.toString();
  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  @override
  void initState() {
    super.initState();
    final load = widget.initialLoad;
    if (load != null) {
      final pickup = _map(load['pickup']);
      final delivery = _map(load['delivery']);
      _pickup.text = pickup['address']?.toString() ?? '';
      _pickupCity.text = pickup['city']?.toString() ?? '';
      _pickupState.text = pickup['state']?.toString() ?? '';
      _delivery.text = delivery['address']?.toString() ?? '';
      _deliveryCity.text = delivery['city']?.toString() ?? '';
      _deliveryState.text = delivery['state']?.toString() ?? '';
      _type.text = load['loadType']?.toString() ?? '';
      _weight.text = load['weightTons']?.toString() ?? '';
      _price.text = load['price']?.toString() ?? '';
      _description.text = load['description']?.toString() ?? '';
      _truckType = load['requiredTruckType']?.toString() ?? 'mini';
      final date = DateTime.tryParse(load['pickupDate']?.toString() ?? '');
      if (date != null) {
        _date = date;
        _time = TimeOfDay.fromDateTime(date.toLocal());
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _pickup,
      _pickupCity,
      _pickupState,
      _delivery,
      _deliveryCity,
      _deliveryState,
      _type,
      _weight,
      _price,
      _description
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? 'Required' : null;
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final pickupDate = DateTime(
          _date.year, _date.month, _date.day, _time.hour, _time.minute);
      final body = {
        'pickup': {
          'address': _pickup.text.trim(),
          'city': _pickupCity.text.trim(),
          'state': _pickupState.text.trim()
        },
        'delivery': {
          'address': _delivery.text.trim(),
          'city': _deliveryCity.text.trim(),
          'state': _deliveryState.text.trim()
        },
        'loadType': _type.text.trim(),
        'weightTons': double.parse(_weight.text),
        'requiredTruckType': _truckType,
        'pickupDate': pickupDate.toIso8601String(),
        'price': double.parse(_price.text),
        'description': _description.text.trim()
      };
      if (_editing && _loadId != null) {
        await widget.api.updateLoad(_loadId!, body);
      } else {
        await widget.api.createLoad(body);
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
      appBar: AppBar(title: Text(_editing ? 'Edit load' : 'Post a load')),
      body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Pickup details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _field(_pickup, 'Pickup address'),
            _field(_pickupCity, 'Pickup city'),
            _field(_pickupState, 'Pickup state'),
            const SizedBox(height: 16),
            const Text('Delivery details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _field(_delivery, 'Delivery address'),
            _field(_deliveryCity, 'Delivery city'),
            _field(_deliveryState, 'Delivery state'),
            const SizedBox(height: 16),
            const Text('Freight details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _field(_type, 'Load type (e.g. building materials)'),
            _field(_weight, 'Weight in tons', numeric: true),
            _field(_price, 'Offered price in ₹', numeric: true),
            DropdownButtonFormField<String>(
                value: _truckType,
                decoration:
                    const InputDecoration(labelText: 'Required truck type'),
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
                onChanged: (v) => setState(() => _truckType = v ?? 'mini')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: () async {
                  final today = DateTime.now();
                  final firstDate = _date.isBefore(today) ? _date : today;
                  final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: firstDate,
                      lastDate: today.add(const Duration(days: 365)));
                  if (picked == null || !mounted) return;
                  final time = await showTimePicker(
                      context: context, initialTime: _time);
                  if (time != null)
                    setState(() {
                      _date = picked;
                      _time = time;
                    });
                },
                icon: const Icon(Icons.calendar_month),
                label: Text(
                    'Pickup: ${_date.day}/${_date.month}/${_date.year} ${_time.format(context)}')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _description,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)')),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy
                    ? 'Saving...'
                    : _editing
                        ? 'Save changes'
                        : 'Post load')),
          ])));
  Widget _field(TextEditingController c, String label,
          {bool numeric = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
              controller: c,
              keyboardType: numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(labelText: label),
              validator: (v) {
                final required = _required(v);
                if (required != null) return required;
                if (numeric &&
                    (double.tryParse(v!) == null ||
                        double.parse(v) < 0 ||
                        (label.contains('Weight') && double.parse(v) == 0)))
                  return 'Enter a valid number';
                return null;
              }));
}

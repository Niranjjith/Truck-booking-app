import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  final ApiService api;

  const AuthScreen({super.key, required this.api});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _agencyName = TextEditingController();
  final _otp = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _usePhone = true;
  bool _otpRequired = false;
  String? _developmentOtp;
  String _role = 'customer';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _agencyName.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_register && _phone.text.trim().isEmpty) {
      _showError('Enter a mobile number to verify your account.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = _register
          ? await widget.api.register(
              name: _name.text.trim(),
              email: _email.text.trim().isEmpty ? null : _email.text.trim(),
              phone: _phone.text.trim(),
              password: _password.text,
              role: _role,
              agencyName: _role == 'agency' ? _agencyName.text.trim() : null,
            )
          : await widget.api.login(
              email: _usePhone ? null : _email.text.trim(),
              phone: _usePhone ? _phone.text.trim() : null,
              password: _password.text,
            );
      if (!mounted) {
        return;
      }
      if (result['otpRequired'] == true) {
        setState(() {
          _otpRequired = true;
          _developmentOtp = result['developmentOtp']?.toString();
        });
        _showError(
          _developmentOtp == null
              ? 'Enter the verification code sent to your phone.'
              : 'Local development verification code: $_developmentOtp',
        );
        return;
      }
      await _openHome();
    } catch (error) {
      _showError(_message(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_otp.text.trim().length != 6) {
      _showError('Enter the six-digit verification code.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.verifyOtp(
        phone: _phone.text.trim(),
        code: _otp.text.trim(),
      );
      await _openHome();
    } catch (error) {
      _showError(_message(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _busy = true);
    try {
      final result = await widget.api.requestOtp(_phone.text.trim());
      if (!mounted) {
        return;
      }
      setState(
        () => _developmentOtp = result['developmentOtp']?.toString(),
      );
      _showError(
        _developmentOtp == null
            ? 'Request accepted. Check your phone for a new code.'
            : 'Local development verification code: $_developmentOtp',
      );
    } catch (error) {
      _showError(_message(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openHome() async {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(api: widget.api)),
    );
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 166,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF142B4A), Color(0xFF2864E8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF2864E8).withValues(alpha: .17),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -3,
                            bottom: -12,
                            child: Icon(
                              Icons.local_shipping_rounded,
                              size: 120,
                              color: Colors.white.withValues(alpha: .09),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                width: 43,
                                height: 43,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .16),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.local_shipping_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const Spacer(),
                              const Text(
                                'HAULMATE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .6,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Freight, in motion.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .75),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .08),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey('$_otpRequired-$_register'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _otpRequired
                                ? 'Verify your mobile number'
                                : _register
                                    ? 'Create your account'
                                    : 'Truck Booking',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.4,
                                ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            _otpRequired
                                ? 'Enter the six-digit code sent to ${_phone.text.trim()}.'
                                : _register
                                    ? 'Join the transport marketplace.'
                                    : 'Book trucks and manage freight in one place.',
                            style: const TextStyle(
                              color: Color(0xFF7A8799),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_otpRequired) ...[
                      TextFormField(
                        controller: _otp,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'Verification code',
                          prefixIcon: Icon(Icons.verified_user_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().length != 6
                                ? 'Enter the six-digit code'
                                : null,
                      ),
                      if (_developmentOtp != null)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'A development-only OTP is displayed after registration or resend.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                      FilledButton(
                        onPressed: _busy ? null : _verifyOtp,
                        child: _busy
                            ? const CircularProgressIndicator()
                            : const Text('Verify and continue'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _resendOtp,
                        child: const Text('Resend verification code'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _otpRequired = false;
                                  _developmentOtp = null;
                                  _otp.clear();
                                }),
                        child: const Text('Back to sign in'),
                      ),
                    ] else ...[
                      if (_register) ...[
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Enter your name'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Mobile number (required)',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Enter your mobile number'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email (optional)',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _role,
                          decoration:
                              const InputDecoration(labelText: 'Account type'),
                          items: const [
                            DropdownMenuItem(
                              value: 'customer',
                              child: Text('Customer / Load owner'),
                            ),
                            DropdownMenuItem(
                              value: 'truckOwner',
                              child: Text('Truck owner'),
                            ),
                            DropdownMenuItem(
                              value: 'agency',
                              child: Text('Transport agency'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _role = value ?? 'customer'),
                        ),
                        if (_role == 'agency') ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _agencyName,
                            decoration: const InputDecoration(
                              labelText: 'Agency name',
                              prefixIcon: Icon(Icons.business_outlined),
                            ),
                            validator: (value) => _role == 'agency' &&
                                    (value == null || value.trim().isEmpty)
                                ? 'Enter your agency name'
                                : null,
                          ),
                        ],
                        const SizedBox(height: 14),
                      ] else ...[
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              label: Text('Phone'),
                              icon: Icon(Icons.phone_outlined),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text('Email'),
                              icon: Icon(Icons.email_outlined),
                            ),
                          ],
                          selected: {_usePhone},
                          onSelectionChanged: (selection) =>
                              setState(() => _usePhone = selection.first),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _usePhone ? _phone : _email,
                          keyboardType: _usePhone
                              ? TextInputType.phone
                              : TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText:
                                _usePhone ? 'Phone number' : 'Email address',
                            prefixIcon: Icon(
                              _usePhone ? Icons.phone : Icons.email_outlined,
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'This field is required'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password (minimum 8 characters)',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (value) => value == null || value.length < 8
                            ? 'Use at least 8 characters'
                            : null,
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _busy
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_register
                                  ? 'Create account and verify phone'
                                  : 'Log in'),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _register = !_register;
                                  _otpRequired = false;
                                }),
                        child: Text(
                          _register
                              ? 'Already registered? Log in'
                              : 'New here? Create an account',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'SMS verification and payment provider credentials must be configured before production.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

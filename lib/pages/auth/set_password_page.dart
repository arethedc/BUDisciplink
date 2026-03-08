import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({super.key});

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _showNew = false;
  bool _showConfirm = false;
  String? _error;
  String? _oobCode;

  @override
  void initState() {
    super.initState();
    _initFromLink();
  }

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _extractParams() {
    final out = <String, String>{...Uri.base.queryParameters};
    final fragment = Uri.base.fragment;
    if (fragment.contains('?')) {
      final query = fragment.substring(fragment.indexOf('?') + 1);
      out.addAll(Uri.splitQueryString(query));
    }
    return out;
  }

  Future<void> _initFromLink() async {
    final params = _extractParams();
    final prefillEmail = (params['prefillEmail'] ?? params['email'] ?? '')
        .toString()
        .trim();
    final verifyOobCode = (params['verifyOobCode'] ?? '').toString().trim();
    if (prefillEmail.isNotEmpty) {
      _emailCtrl.text = prefillEmail;
    }

    if (verifyOobCode.isNotEmpty) {
      try {
        await FirebaseAuth.instance.applyActionCode(verifyOobCode);
      } catch (_) {}
    }

    try {
      final mode = (params['mode'] ?? '').trim();
      final code = (params['oobCode'] ?? '').trim();

      if (mode != 'resetPassword' || code.isEmpty) {
        setState(() {
          _error = prefillEmail.isNotEmpty
              ? 'Password was already set or link is incomplete. You can log in now.'
              : 'Invalid or missing set-password link.';
          _loading = false;
        });
        return;
      }

      final email = await FirebaseAuth.instance.verifyPasswordResetCode(code);
      setState(() {
        _oobCode = code;
        _emailCtrl.text = email;
        _loading = false;
      });
    } on FirebaseAuthException catch (e) {
      var msg = e.message ?? 'This link is invalid or expired.';
      if (e.code == 'expired-action-code') {
        msg = 'This link has expired. Please request a new one.';
      } else if (e.code == 'invalid-action-code') {
        msg = 'This link is already used. You can log in now.';
      }
      setState(() {
        _error = msg;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Could not validate set-password link.';
        _loading = false;
      });
    }
  }

  bool _hasUpper(String value) => RegExp(r'[A-Z]').hasMatch(value);
  bool _hasLower(String value) => RegExp(r'[a-z]').hasMatch(value);
  bool _hasDigit(String value) => RegExp(r'\d').hasMatch(value);
  bool _hasSpecial(String value) =>
      RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=~`/\[\]\\;]').hasMatch(value);
  bool _hasMinLen(String value) => value.length >= 8;

  int _score(String value) {
    var score = 0;
    if (_hasMinLen(value)) score++;
    if (_hasUpper(value)) score++;
    if (_hasLower(value)) score++;
    if (_hasDigit(value)) score++;
    if (_hasSpecial(value)) score++;
    return score;
  }

  String _strengthLabel(String value) {
    final score = _score(value);
    if (score >= 5) return 'Strong';
    if (score >= 3) return 'Medium';
    return 'Weak';
  }

  Color _strengthColor(String value) {
    final score = _score(value);
    if (score >= 5) return const Color(0xFF2E7D32);
    if (score >= 3) return const Color(0xFFF57F17);
    return Colors.red;
  }

  bool _isStrongPassword(String value) => _score(value) >= 5;

  Future<void> _setPassword() async {
    if (_saving) return;
    final code = _oobCode;
    if (code == null || code.isEmpty) return;

    final password = _newPasswordCtrl.text.trim();
    final confirm = _confirmPasswordCtrl.text.trim();

    if (password.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Please fill out both password fields.');
      return;
    }
    if (!_isStrongPassword(password)) {
      setState(() => _error = 'Password is weak. Follow all requirements.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.confirmPasswordReset(
        code: code,
        newPassword: password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password set successfully. Please log in.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (_) => false,
        arguments: {'prefillEmail': _emailCtrl.text.trim()},
      );
    } on FirebaseAuthException catch (e) {
      var msg = e.message ?? 'Failed to set password.';
      if (e.code == 'expired-action-code') {
        msg = 'This link has expired. Please request a new one.';
      } else if (e.code == 'invalid-action-code') {
        msg = 'This link is invalid or already used.';
      } else if (e.code == 'weak-password') {
        msg = 'Please use a stronger password.';
      }
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = 'Failed to set password: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
    bool enabled = true,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: hint,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(icon, color: primary.withValues(alpha: 0.85)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: enabled ? Colors.white : const Color(0xFFF1F4F1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _criteriaRow(bool ok, String label) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: ok ? const Color(0xFF2E7D32) : hint,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ok ? const Color(0xFF2E7D32) : hint,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final password = _newPasswordCtrl.text;
    final strengthLabel = _strengthLabel(password);
    final strengthColor = _strengthColor(password);
    final canSetPassword = _oobCode != null && _oobCode!.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        const fixedCardWidth = 420.0;
        final cardWidth =
            constraints.maxWidth < fixedCardWidth ? constraints.maxWidth : fixedCardWidth;

        return Scaffold(
          backgroundColor: bg,
          appBar: null,
          body: SafeArea(
            child: Center(
              child: SizedBox(
                width: cardWidth,
                child: Container(
                  margin: const EdgeInsets.all(14),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: primary.withValues(alpha: 0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: _loading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              const Text(
                                'SET YOUR PASSWORD',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                  fontSize: 24,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Create your account password to continue.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: hint,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (_error != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextField(
                                controller: _emailCtrl,
                                readOnly: true,
                                enabled: false,
                                decoration: _decor(
                                  label: 'Email Address',
                                  icon: Icons.email_outlined,
                                  enabled: false,
                                ),
                              ),
                              if (!canSetPassword) ...[
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                                      context,
                                      '/login',
                                      (_) => false,
                                      arguments: {'prefillEmail': _emailCtrl.text.trim()},
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primary,
                                      foregroundColor: Colors.white,
                                      elevation: 3,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'GO TO LOGIN',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ] else ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _newPasswordCtrl,
                                obscureText: !_showNew,
                                onChanged: (_) => setState(() {}),
                                decoration: _decor(
                                  label: 'New Password',
                                  icon: Icons.lock_outline,
                                  suffixIcon: IconButton(
                                    onPressed: () =>
                                        setState(() => _showNew = !_showNew),
                                    icon: Icon(
                                      _showNew
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                      color: primary.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Text(
                                    'Strength: ',
                                    style: TextStyle(
                                      color: hint,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    strengthLabel,
                                    style: TextStyle(
                                      color: strengthColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _criteriaRow(_hasMinLen(password), 'At least 8 characters'),
                              _criteriaRow(_hasUpper(password), 'At least 1 uppercase letter'),
                              _criteriaRow(_hasLower(password), 'At least 1 lowercase letter'),
                              _criteriaRow(_hasDigit(password), 'At least 1 number'),
                              _criteriaRow(_hasSpecial(password), 'At least 1 special character'),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _confirmPasswordCtrl,
                                obscureText: !_showConfirm,
                                decoration: _decor(
                                  label: 'Confirm Password',
                                  icon: Icons.verified_user_outlined,
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () => _showConfirm = !_showConfirm,
                                    ),
                                    icon: Icon(
                                      _showConfirm
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                      color: primary.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _saving ? null : _setPassword,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    foregroundColor: Colors.white,
                                    elevation: 3,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _saving
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'SET PASSWORD',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/login',
                                  (_) => false,
                                ),
                                child: const Text('Back to Login'),
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
      },
    );
  }
}

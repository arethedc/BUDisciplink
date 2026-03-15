import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../shared/widgets/app_branding.dart';

import '../../services/user_service.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  // ===== DESIGN THEME (from your reference) =====
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  // show/hide password (visual only; logic unchanged)
  bool _obscurePass = true;
  bool _obscureConfirm = true;

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

  String _resolveVerifyContinueUrl(String email) {
    if (kIsWeb) {
      final safeEmail = Uri.encodeQueryComponent(email.trim());
      return '${Uri.base.origin}/#/verify-email?prefillEmail=$safeEmail&source=signup';
    }
    const configured = String.fromEnvironment(
      'SELF_SIGNUP_VERIFY_CONTINUE_URL',
    );
    return configured;
  }

  Future<void> _sendVerifyEmailUsingSmtp(User user, String email) async {
    final continueUrl = _resolveVerifyContinueUrl(email);

    if (continueUrl.isNotEmpty) {
      try {
        final callable = FirebaseFunctions.instanceFor(
          region: 'asia-east1',
        ).httpsCallable('sendCurrentUserVerifyEmailLink');
        await callable.call(<String, dynamic>{
          'email': email,
          'continueUrl': continueUrl,
        });
        return;
      } catch (_) {}
    }

    if (continueUrl.isNotEmpty && kIsWeb) {
      await user.sendEmailVerification(
        ActionCodeSettings(url: continueUrl, handleCodeInApp: true),
      );
      return;
    }
    await user.sendEmailVerification();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submitSignUpFromKeyboard() {
    if (_loading) return;
    _signUp();
  }

  Future<void> _signUp() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      if (!_formKey.currentState!.validate()) {
        setState(() => _loading = false);
        return;
      }

      final email = _emailCtrl.text.trim();
      final password = _passCtrl.text;

      // 1) Create Auth user
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        throw Exception("Sign up failed. No user returned.");
      }

      // 2) Send verification email (prefer SMTP extension via callable)
      await _sendVerifyEmailUsingSmtp(user, email);

      // 3) Create users/{uid} using UserService (Option A: pending_profile)
      //    This prevents conflicting field sets and ensures status flow is correct.
      await UserService().ensureUserDocExists();

      // 4) Stay logged in and go to Verify Email page
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/verify-email',
        (r) => false,
        arguments: {'source': 'signup', 'prefillEmail': email},
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: hint, fontWeight: FontWeight.w700),
      prefixIcon: Icon(icon, color: primary.withValues(alpha: 0.85)),
      suffixIcon: suffix,
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

  @override
  Widget build(BuildContext context) {
    final password = _passCtrl.text;
    final confirmPassword = _confirmCtrl.text;
    final showPasswordValidation = password.trim().isNotEmpty;
    final showConfirmValidation = confirmPassword.trim().isNotEmpty;
    final passwordsMatch = showConfirmValidation && confirmPassword == password;
    final strengthLabel = _strengthLabel(password);
    final strengthColor = _strengthColor(password);

    return LayoutBuilder(
      builder: (context, constraints) {
        // ✅ fixed size (no stretch), but still fits small phones
        const double fixedCardWidth = 420.0;
        final double cardWidth = constraints.maxWidth < fixedCardWidth
            ? constraints.maxWidth
            : fixedCardWidth;

        return Scaffold(
          backgroundColor: bg,

          // ✅ remove AppBar (mobile + web)
          appBar: null,

          body: SafeArea(
            child: Center(
              child: SizedBox(
                width: cardWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.15),
                      width: 1,
                    ),
                    // ✅ shadow on mobile + web
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: AppBranding.logo(fit: BoxFit.contain),
                                ),
                                const Text(
                                  "BUDiscipLink",
                                  style: TextStyle(
                                    color: primary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          const Text(
                            "CREATE YOUR ACCOUNT",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                              fontSize: 24,
                              letterSpacing: 0.4,
                            ),
                          ),

                          const SizedBox(height: 14),

                          Text(
                            "Create your account to continue",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: hint,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),

                          const SizedBox(height: 18),

                          if (_error != null) ...[
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                _submitSignUpFromKeyboard(),
                            style: const TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: _decor(
                              label: 'Email',
                              icon: Icons.email,
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'Email is required';
                              if (!s.contains('@')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 6),

                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscurePass,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                _submitSignUpFromKeyboard(),
                            style: const TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: _decor(
                              label: 'Password',
                              icon: Icons.lock,
                              suffix: IconButton(
                                icon: Icon(
                                  _obscurePass
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: primary.withValues(alpha: 0.85),
                                ),
                                onPressed: () => setState(
                                  () => _obscurePass = !_obscurePass,
                                ),
                              ),
                            ),
                            validator: (v) {
                              final s = v ?? '';
                              if (s.trim().isEmpty)
                                return 'Password is required';
                              if (!_isStrongPassword(s)) {
                                return 'Password is weak. Follow all requirements.';
                              }
                              return null;
                            },
                          ),

                          if (showPasswordValidation) ...[
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
                            _criteriaRow(
                              _hasMinLen(password),
                              'At least 8 characters',
                            ),
                            _criteriaRow(
                              _hasUpper(password),
                              'At least 1 uppercase letter',
                            ),
                            _criteriaRow(
                              _hasLower(password),
                              'At least 1 lowercase letter',
                            ),
                            _criteriaRow(
                              _hasDigit(password),
                              'At least 1 number',
                            ),
                            _criteriaRow(
                              _hasSpecial(password),
                              'At least 1 special character',
                            ),
                          ],

                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _confirmCtrl,
                            obscureText: _obscureConfirm,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                _submitSignUpFromKeyboard(),
                            style: const TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: _decor(
                              label: 'Confirm Password',
                              icon: Icons.lock_outline_rounded,
                              suffix: IconButton(
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: primary.withValues(alpha: 0.85),
                                ),
                                onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                              ),
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'Please confirm password';
                              if (v != _passCtrl.text)
                                return 'Passwords do not match';
                              return null;
                            },
                          ),
                          if (showConfirmValidation) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  passwordsMatch
                                      ? Icons.check_circle
                                      : Icons.cancel_rounded,
                                  size: 16,
                                  color: passwordsMatch
                                      ? const Color(0xFF2E7D32)
                                      : Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  passwordsMatch
                                      ? 'Passwords match'
                                      : 'Passwords do not match',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: passwordsMatch
                                        ? const Color(0xFF2E7D32)
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _signUp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                elevation: 3,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Sign Up',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          Container(
                            height: 1,
                            width: double.infinity,
                            color: primary.withValues(alpha: 0.25),
                          ),

                          const SizedBox(height: 10),

                          TextButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    // Avoid stacking: replace signup with login
                                    Navigator.pushReplacementNamed(
                                      context,
                                      '/login',
                                    );
                                  },
                            style: TextButton.styleFrom(
                              foregroundColor: primary,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                            ),
                            child: const Text('Already have an account? Login'),
                          ),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F2E3),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: primary.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: primary.withValues(alpha: 0.9),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "Use your BU Outlook email for sign up.",
                                    style: TextStyle(
                                      color: textDark.withValues(alpha: 0.85),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),
                        ],
                      ),
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

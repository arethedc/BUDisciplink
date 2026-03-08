import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  String _resolveVerifyContinueUrl() {
    if (kIsWeb) {
      return '${Uri.base.origin}/#/verify-email';
    }
    const configured = String.fromEnvironment(
      'SELF_SIGNUP_VERIFY_CONTINUE_URL',
    );
    return configured;
  }

  Future<void> _sendVerifyEmailUsingSmtp(User user, String email) async {
    final continueUrl = _resolveVerifyContinueUrl();

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
      Navigator.pushNamedAndRemoveUntil(context, '/verify-email', (r) => false);
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
      prefixIcon: Icon(icon, color: primary.withOpacity(0.85)),
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
                    color: bg,
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
                            "Sign up using your email to continue",
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
                              if (!s.contains('@'))
                                return 'Enter a valid email';
                              return null;
                            },
                          ),

                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscurePass,
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
                              if (s.length < 6)
                                return 'Password must be at least 6 chars';
                              return null;
                            },
                          ),

                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _confirmCtrl,
                            obscureText: _obscureConfirm,
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
                              if (v != _passCtrl.text)
                                return 'Passwords do not match';
                              return null;
                            },
                          ),

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

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../shared/widgets/app_branding.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  // ===== THEME (match your green UI) =====
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  // Inline error/success
  String? _emailError;
  String? _infoMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String s) {
    final v = s.trim();
    if (v.isEmpty) return false;
    return v.contains('@') && v.contains('.');
  }

  String _webResetContinueUrl(String email) {
    final configured = const String.fromEnvironment(
      'PASSWORD_RESET_CONTINUE_URL',
    ).trim();
    final baseContinueUrl = configured.isNotEmpty
        ? configured
        : '${Uri.base.origin}/#/set-password';
    final separator = baseContinueUrl.contains('?') ? '&' : '?';
    return '$baseContinueUrl${separator}prefillEmail='
        '${Uri.encodeComponent(email)}';
  }

  ActionCodeSettings _webResetSettings(String email) {
    return ActionCodeSettings(
      url: _webResetContinueUrl(email),
      handleCodeInApp: true,
    );
  }

  Future<void> _sendResetLink() async {
    if (_loading) return;

    final email = _emailCtrl.text.trim();

    setState(() {
      _emailError = null;
      _infoMessage = null;
    });

    if (!_isValidEmail(email)) {
      setState(() {
        _emailError = 'Enter a valid email address';
      });
      return;
    }

    setState(() => _loading = true);

    try {
      String action = 'reset_password';
      try {
        final callable = FirebaseFunctions.instanceFor(
          region: 'asia-east1',
        ).httpsCallable('resolveForgotPasswordFlow');
        final res = await callable.call(<String, dynamic>{'email': email});
        final data = (res.data as Map?) ?? const <String, dynamic>{};
        action = (data['action'] ?? 'reset_password').toString().trim();
      } catch (_) {}

      if (action == 'needs_email_verification' ||
          action == 'needs_activation') {
        if (!mounted) return;
        Navigator.pushNamed(
          context,
          '/forgot-password-assist',
          arguments: <String, dynamic>{
            'email': email,
            'mode': action == 'needs_activation'
                ? 'activation'
                : 'verify_email',
          },
        );
        return;
      }

      var sentViaCallable = false;
      try {
        final callable = FirebaseFunctions.instanceFor(
          region: 'asia-east1',
        ).httpsCallable('sendPublicPasswordResetLink');
        await callable.call(<String, dynamic>{
          'email': email,
          if (kIsWeb) 'continueUrl': _webResetContinueUrl(email),
        });
        sentViaCallable = true;
      } catch (_) {}

      if (!sentViaCallable) {
        if (kIsWeb) {
          try {
            await FirebaseAuth.instance.sendPasswordResetEmail(
              email: email,
              actionCodeSettings: _webResetSettings(email),
            );
          } on FirebaseAuthException catch (e) {
            final fallbackToDefault =
                e.code == 'invalid-continue-uri' ||
                e.code == 'unauthorized-continue-uri' ||
                e.code == 'missing-continue-uri';
            if (!fallbackToDefault) rethrow;
            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
          }
        } else {
          await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        }
      }

      if (!mounted) return;
      setState(() {
        _infoMessage =
            "Password reset link sent. Please check your email inbox.";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password reset email sent."),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      // Keep message user-friendly
      String msg = e.message ?? 'Failed to send reset email';
      if (e.code == 'user-not-found') msg = 'No account found for that email.';
      if (e.code == 'invalid-email') msg = 'Invalid email address.';

      setState(() {
        _emailError = msg;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _emailError = 'Error: $e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      labelStyle: const TextStyle(color: hint, fontWeight: FontWeight.w700),
      prefixIcon: Icon(icon, color: primary.withValues(alpha: 0.85)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final contentMaxWidth = w >= 900 ? 420.0 : double.infinity;

    return Scaffold(
      backgroundColor: bg,
      appBar: null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Container(
              margin: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: primary.withValues(alpha: 0.15),
                  width: 1,
                ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    const SizedBox(height: 10),

                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        color: primary,
                        size: 40,
                      ),
                    ),

                    const SizedBox(height: 18),

                    const Text(
                      "RESET YOUR PASSWORD",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        fontSize: 18,
                        letterSpacing: 0.4,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      "Enter your email and we will send you a password reset link.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: hint,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),

                    const SizedBox(height: 18),

                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: _decor(
                        label: 'Email',
                        icon: Icons.email_outlined,
                        errorText: _emailError,
                      ),
                      onChanged: (_) {
                        if (_emailError != null || _infoMessage != null) {
                          setState(() {
                            _emailError = null;
                            _infoMessage = null;
                          });
                        }
                      },
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _sendResetLink,
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
                                "SEND RESET LINK",
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    if (_infoMessage != null) ...[
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
                                _infoMessage!,
                                style: TextStyle(
                                  color: textDark.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: primary,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                      child: const Text("Back to Login"),
                    ),
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

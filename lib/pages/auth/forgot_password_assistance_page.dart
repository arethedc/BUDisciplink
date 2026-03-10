import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum _AssistanceMode { verifyEmail, activation }

class ForgotPasswordAssistancePage extends StatefulWidget {
  const ForgotPasswordAssistancePage({super.key});

  @override
  State<ForgotPasswordAssistancePage> createState() =>
      _ForgotPasswordAssistancePageState();
}

class _ForgotPasswordAssistancePageState
    extends State<ForgotPasswordAssistancePage> {
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  bool _initialized = false;
  bool _sending = false;
  String _email = '';
  _AssistanceMode _mode = _AssistanceMode.verifyEmail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final rawEmail = (args['email'] ?? '').toString().trim();
      final rawMode = (args['mode'] ?? '').toString().trim().toLowerCase();
      if (rawEmail.isNotEmpty) {
        _email = rawEmail;
      }
      if (rawMode == 'activation') {
        _mode = _AssistanceMode.activation;
      } else {
        _mode = _AssistanceMode.verifyEmail;
      }
    }
  }

  String _verifyContinueUrl() {
    if (!kIsWeb) return '';
    return '${Uri.base.origin}/#/verify-email?prefillEmail=${Uri.encodeComponent(_email)}&source=signup';
  }

  String _setPasswordContinueUrl() {
    if (!kIsWeb) return '';
    return '${Uri.base.origin}/#/set-password?prefillEmail=${Uri.encodeComponent(_email)}&source=signup';
  }

  Future<void> _sendAssistanceEmail() async {
    if (_sending) return;
    if (_email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing email address.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-east1',
      ).httpsCallable('sendForgotPasswordAssistanceEmail');
      await callable.call(<String, dynamic>{
        'email': _email,
        'intent': _mode == _AssistanceMode.activation ? 'activation' : 'verify',
        'continueUrl': _mode == _AssistanceMode.activation
            ? _setPasswordContinueUrl()
            : _verifyContinueUrl(),
        'verifyContinueUrl': _verifyContinueUrl(),
      });

      if (!mounted) return;
      final message = _mode == _AssistanceMode.activation
          ? 'New activation email sent. Please check your inbox.'
          : 'Verification email sent. Please check your inbox.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to send email.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send email.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _goToLogin() {
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (_) => false,
      arguments: {'prefillEmail': _email},
    );
  }

  @override
  Widget build(BuildContext context) {
    final isActivation = _mode == _AssistanceMode.activation;
    final title = isActivation
        ? 'Account not yet activated'
        : 'Email not yet verified';
    final description = isActivation
        ? 'Your account is not yet activated.\nPlease set your password using the activation email we sent you.'
        : 'Your email address is not yet verified.\nPlease verify your email before resetting your password.';
    final primaryLabel = isActivation
        ? 'Resend Activation Email'
        : 'Resend Verification Email';

    return LayoutBuilder(
      builder: (context, constraints) {
        const fixedCardWidth = 420.0;
        final cardWidth = constraints.maxWidth < fixedCardWidth
            ? constraints.maxWidth
            : fixedCardWidth;

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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        isActivation
                            ? Icons.lock_clock_rounded
                            : Icons.mark_email_unread_outlined,
                        size: 76,
                        color: primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: hint,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.8,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_email.isNotEmpty)
                        Text(
                          _email,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _sending ? null : _sendAssistanceEmail,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _sending
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  primaryLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _goToLogin,
                        child: const Text('Back to Login'),
                      ),
                    ],
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

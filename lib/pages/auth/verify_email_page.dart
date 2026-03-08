import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../shared/widgets/logout_confirm_dialog.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage>
    with WidgetsBindingObserver {
  // Theme (match your app)
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  bool _checking = false;
  bool _verified = false;

  String? _email;

  // resend cooldown
  int _cooldown = 0;
  Timer? _cooldownTimer;

  // prevent spamming sendEmailVerification on init
  bool _sentOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    setState(() => _email = user.email);

    // If already verified, finish
    await user.reload();
    final fresh = FirebaseAuth.instance.currentUser;
    if (fresh != null && fresh.emailVerified) {
      await _finishVerified();
      return;
    }

    // Send verification email once (optional)
    if (!_sentOnce) {
      _sentOnce = true;
      await _safeSendVerificationEmail();
    }
  }

  // Called when user returns to app (after clicking email link)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_verified) {
      _checkNow(silent: true);
    }
  }

  Future<void> _safeSendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final continueUrl = kIsWeb ? '${Uri.base.origin}/#/verify-email' : '';
      if (continueUrl.isNotEmpty) {
        try {
          final callable = FirebaseFunctions.instanceFor(
            region: 'asia-east1',
          ).httpsCallable('sendCurrentUserVerifyEmailLink');
          await callable.call(<String, dynamic>{
            'email': user.email ?? '',
            'continueUrl': continueUrl,
          });
        } catch (_) {
          await user.sendEmailVerification(
            ActionCodeSettings(url: continueUrl, handleCodeInApp: true),
          );
        }
      } else {
        await user.sendEmailVerification();
      }
      _startCooldown(30);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Verification email sent to ${user.email ?? ''}."),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = "Could not send email: ${e.code}";
      if (e.code == 'too-many-requests') {
        msg = "Too many requests. Please wait a few minutes then try again.";
        _startCooldown(60);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.orange),
      );
    } catch (_) {
      // ignore
    }
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds);

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _checkNow({bool silent = false}) async {
    if (_checking || _verified) return;

    setState(() => _checking = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }

      await user.reload();
      final fresh = FirebaseAuth.instance.currentUser;

      if (fresh != null && fresh.emailVerified) {
        await _finishVerified();
      } else if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Not verified yet. Please click the link in your email then try again.",
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _finishVerified() async {
    setState(() => _verified = true);

    // Recommended flow: sign out -> login -> verified check passes -> route
    await Future.delayed(const Duration(milliseconds: 900));
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _logoutToLogin() async {
    final confirmed = await showLogoutConfirmDialog(context);
    if (!mounted || !confirmed) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    // card sizing like your other pages
    return LayoutBuilder(
      builder: (context, constraints) {
        const double fixedCardWidth = 420;
        final double cardWidth = constraints.maxWidth < fixedCardWidth
            ? constraints.maxWidth
            : fixedCardWidth;

        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: Center(
              child: SizedBox(
                width: cardWidth,
                child: Container(
                  margin: const EdgeInsets.all(14),
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
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
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _verified
                        ? _VerifiedState()
                        : Column(
                            key: const ValueKey('verify'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.mark_email_read_rounded,
                                size: 70,
                                color: primary,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                "Verify your email",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textDark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _email == null
                                    ? "We sent a verification link to your email."
                                    : "We sent a verification link to:\n$_email",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: hint,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 14),

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3F2E3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: primary.withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      color: primary.withValues(alpha: 0.9),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        "Open your email, click the verification link, then come back here.\n\nTip: Check Spam/Promotions.",
                                        style: TextStyle(
                                          color: textDark.withValues(
                                            alpha: 0.85,
                                          ),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 14),

                              SizedBox(
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _checking
                                      ? null
                                      : () => _checkNow(silent: false),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    foregroundColor: Colors.white,
                                    elevation: 3,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _checking
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          "I’VE VERIFIED MY EMAIL",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              TextButton(
                                onPressed: (_cooldown > 0)
                                    ? null
                                    : () async => _safeSendVerificationEmail(),
                                style: TextButton.styleFrom(
                                  foregroundColor: primary,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                child: Text(
                                  _cooldown > 0
                                      ? "Resend available in $_cooldown s"
                                      : "Resend verification email",
                                ),
                              ),

                              const SizedBox(height: 8),

                              TextButton(
                                onPressed: _logoutToLogin,
                                style: TextButton.styleFrom(
                                  foregroundColor: primary.withValues(
                                    alpha: 0.9,
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
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
      },
    );
  }
}

class _VerifiedState extends StatelessWidget {
  const _VerifiedState();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('verified'),
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.verified_rounded, size: 84, color: Colors.green),
        SizedBox(height: 12),
        Text(
          "Email verified!",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 6),
        Text("Redirecting you to login…", textAlign: TextAlign.center),
      ],
    );
  }
}

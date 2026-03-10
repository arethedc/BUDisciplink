import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/role_router.dart';
import '../shared/widgets/logout_confirm_dialog.dart';

enum _VerifyLinkState { none, expired, alreadyVerified }

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
  bool _processingActionLink = false;
  bool _verifiedFromActionLink = false;
  bool _didReadRouteArgs = false;
  bool _didBootstrap = false;
  bool _isSignupFlow = false;
  bool _isLoggedUnverifiedFlow = false;
  _VerifyLinkState _verifyLinkState = _VerifyLinkState.none;

  String? _email;
  String? _prefillEmailFromLink;

  // resend cooldown
  int _cooldown = 0;
  Timer? _cooldownTimer;

  // prevent spamming sendEmailVerification on init
  bool _sentOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didReadRouteArgs) return;
    _didReadRouteArgs = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final source = (args['source'] ?? '').toString().trim().toLowerCase();
      final prefill = (args['prefillEmail'] ?? args['email'] ?? '')
          .toString()
          .trim();

      if (source == 'signup') {
        _isSignupFlow = true;
        _isLoggedUnverifiedFlow = false;
      } else if (source == 'logged_unverified') {
        _isSignupFlow = false;
        _isLoggedUnverifiedFlow = true;
      }

      if (prefill.isNotEmpty) {
        _prefillEmailFromLink = prefill;
        _email ??= prefill;
      }
    }

    if (_didBootstrap) return;
    _didBootstrap = true;
    _bootstrap();
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
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (_) => false,
        arguments: {'prefillEmail': _resolvedPrefillEmail()},
      );
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

    // Send verification email once (signup flow only)
    if (!_sentOnce && _isSignupFlow) {
      _sentOnce = true;
      await _safeSendVerificationEmail();
    }
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

  Future<void> _bootstrap() async {
    final params = _extractParams();
    final source = (params['source'] ?? '').toString().trim().toLowerCase();
    if (source == 'signup') {
      _isSignupFlow = true;
      _isLoggedUnverifiedFlow = false;
    } else if (source == 'logged_unverified') {
      _isSignupFlow = false;
      _isLoggedUnverifiedFlow = true;
    }

    final prefillEmail = (params['prefillEmail'] ?? params['email'] ?? '')
        .toString()
        .trim();
    if (prefillEmail.isNotEmpty) {
      _prefillEmailFromLink = prefillEmail;
      _email ??= prefillEmail;
    }

    final handled = await _tryHandleActionLink(params);
    if (handled) return;
    await _init();
  }

  Future<bool> _tryHandleActionLink(Map<String, String> params) async {
    final mode = (params['mode'] ?? '').trim();
    final oobCode = (params['oobCode'] ?? '').trim();
    if (mode != 'verifyEmail' || oobCode.isEmpty) {
      return false;
    }

    setState(() => _processingActionLink = true);

    try {
      await FirebaseAuth.instance.applyActionCode(oobCode);
      await FirebaseAuth.instance.currentUser?.reload();
      if (!mounted) return true;
      setState(() {
        _processingActionLink = false;
        _verifiedFromActionLink = true;
      });
      await _finishVerified(autoRedirectToLogin: _isLoggedUnverifiedFlow);
      return true;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return true;
      if (e.code == 'expired-action-code') {
        setState(() {
          _processingActionLink = false;
          _verifyLinkState = _VerifyLinkState.expired;
        });
        return true;
      }
      if (e.code == 'invalid-action-code') {
        setState(() {
          _processingActionLink = false;
          _verifyLinkState = _VerifyLinkState.alreadyVerified;
        });
        return true;
      }
      setState(() => _processingActionLink = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Could not verify this email link.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (_) {
      if (!mounted) return true;
      setState(() => _processingActionLink = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not verify this email link.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return false;
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
      final safeEmail = Uri.encodeQueryComponent(user.email ?? '');
      final source = _isLoggedUnverifiedFlow ? 'logged_unverified' : 'signup';
      final continueUrl = kIsWeb
          ? '${Uri.base.origin}/#/verify-email?prefillEmail=$safeEmail&source=$source'
          : '';
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
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login',
          (_) => false,
          arguments: {'prefillEmail': _resolvedPrefillEmail()},
        );
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

  Future<void> _finishVerified({bool autoRedirectToLogin = true}) async {
    setState(() => _verified = true);

    if (!autoRedirectToLogin) return;

    if (_isLoggedUnverifiedFlow) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      await RoleRouter.route(context);
      return;
    }

    final verifiedEmail = _resolvedPrefillEmail();
    await Future<void>.delayed(const Duration(milliseconds: 850));
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (_) => false,
      arguments: {'prefillEmail': verifiedEmail},
    );
  }

  Future<void> _goToLogin() async {
    final verifiedEmail = _resolvedPrefillEmail();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (_) => false,
      arguments: {'prefillEmail': verifiedEmail},
    );
  }

  Future<void> _logoutFromVerify() async {
    final confirmed = await showLogoutConfirmDialog(context);
    if (!mounted || !confirmed) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (_) => false);
  }

  String _resolvedPrefillEmail() {
    final fromState = (_email ?? '').trim();
    if (fromState.isNotEmpty) return fromState;
    final fromLink = (_prefillEmailFromLink ?? '').trim();
    if (fromLink.isNotEmpty) return fromLink;
    return (FirebaseAuth.instance.currentUser?.email ?? '').trim();
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
                        ? _VerifiedState(
                            showLoginButton: _verifiedFromActionLink,
                            onGoToLogin: _goToLogin,
                          )
                        : _verifyLinkState != _VerifyLinkState.none
                        ? _VerifyLinkStateView(
                            state: _verifyLinkState,
                            onGoToLogin: _goToLogin,
                          )
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
                              if (_isLoggedUnverifiedFlow) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF8E1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFFFE082),
                                    ),
                                  ),
                                  child: const Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: Color(0xFF8D6E00),
                                        size: 18,
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          "Email is not yet verified. Check your email and click the verification link, or use resend below.",
                                          style: TextStyle(
                                            color: textDark,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],

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
                                  onPressed:
                                      (_checking || _processingActionLink)
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
                                  child: (_checking || _processingActionLink)
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          "I'VE VERIFIED MY EMAIL",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              TextButton(
                                onPressed:
                                    (_cooldown > 0 || _processingActionLink)
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
                              if (_isSignupFlow) ...[
                                const SizedBox(height: 4),
                                TextButton(
                                  onPressed: _processingActionLink
                                      ? null
                                      : _goToLogin,
                                  style: TextButton.styleFrom(
                                    foregroundColor: primary.withValues(
                                      alpha: 0.9,
                                    ),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  child: const Text('Back to Login'),
                                ),
                              ],
                              if (_isLoggedUnverifiedFlow) ...[
                                const SizedBox(height: 4),
                                TextButton.icon(
                                  onPressed: _processingActionLink
                                      ? null
                                      : _logoutFromVerify,
                                  icon: const Icon(
                                    Icons.logout_rounded,
                                    size: 18,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: primary.withValues(
                                      alpha: 0.9,
                                    ),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  label: const Text('Logout'),
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

class _VerifiedState extends StatelessWidget {
  const _VerifiedState({
    required this.showLoginButton,
    required this.onGoToLogin,
  });

  final bool showLoginButton;
  final VoidCallback onGoToLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('verified'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            final angle = (1 - value) * 0.9;
            return Transform.rotate(angle: angle, child: child);
          },
          child: const Icon(
            Icons.verified_rounded,
            size: 86,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          "Email verified successfully",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          "Your email has been verified. You can now log in to your account.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF6D7F62),
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        if (showLoginButton) ...[
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onGoToLogin,
            child: const Text('Go to Login'),
          ),
        ],
      ],
    );
  }
}

class _VerifyLinkStateView extends StatelessWidget {
  const _VerifyLinkStateView({required this.state, required this.onGoToLogin});

  final _VerifyLinkState state;
  final VoidCallback onGoToLogin;

  @override
  Widget build(BuildContext context) {
    final isExpired = state == _VerifyLinkState.expired;
    final title = isExpired
        ? 'Verification link expired'
        : 'Email already verified';
    final description = isExpired
        ? 'This link is no longer valid.\nPlease log in to request a new verification email.'
        : 'Your email is already verified.\nYou can now log in to your account.';

    return Column(
      key: ValueKey('verify-link-state-${state.name}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          isExpired ? Icons.link_off_rounded : Icons.verified_rounded,
          size: 82,
          color: isExpired ? const Color(0xFFEF6C00) : Colors.green,
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6D7F62),
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: onGoToLogin, child: const Text('Go to Login')),
      ],
    );
  }
}

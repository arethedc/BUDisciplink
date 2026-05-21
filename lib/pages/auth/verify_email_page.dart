import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';

enum _VerifyLinkState { none, expired }

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({
    super.key,
    this.prefillEmail,
    this.source,
    this.emailAlreadySent = false,
  });

  final String? prefillEmail;
  final String? source;
  final bool emailAlreadySent;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage>
    with WidgetsBindingObserver {
  static const bg = Colors.white;
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  bool _checking = false;
  bool _verified = false;
  bool _processingActionLink = false;
  bool _didReadRouteArgs = false;
  bool _didBootstrap = false;
  bool _didShowInitialSentSnack = false;
  bool _isSignupFlow = false;
  _VerifyLinkState _verifyLinkState = _VerifyLinkState.none;

  String? _email;
  String? _prefillEmailFromLink;

  // resend cooldown
  int _cooldown = 0;
  Timer? _cooldownTimer;
  StreamSubscription<User?>? _userChangeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readInitialUrlParams();
  }

  void _readInitialUrlParams() {
    final source = (widget.source ?? '').trim().toLowerCase();
    final prefill = (widget.prefillEmail ?? '').trim();
    if (source == 'signup') _isSignupFlow = true;
    if (prefill.isNotEmpty) {
      _prefillEmailFromLink = prefill;
      _email = prefill;
    }
    if (source == 'signup' || widget.emailAlreadySent) {
      _cooldown = 60;
    }
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
      }

      if (prefill.isNotEmpty) {
        _prefillEmailFromLink = prefill;
        _email ??= prefill;
      }

      if (args['verificationEmailAlreadySent'] == true) {
        _startCooldown(60);
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
    _userChangeSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final resolvedEmail = _resolvedPrefillEmail();
    if (resolvedEmail.isEmpty) {
      final current = FirebaseAuth.instance.currentUser;
      final currentEmail = current?.email?.trim() ?? '';
      if (currentEmail.isEmpty) {
        if (!mounted) return;
        context.go('/login');
        return;
      }
      if (mounted) setState(() => _email = currentEmail);
    } else if (mounted) {
      setState(() => _email = resolvedEmail);
    }

    _userChangeSub?.cancel();
    _userChangeSub = FirebaseAuth.instance.userChanges().listen((user) {
      if (user != null && user.emailVerified && !_verified) {
        _onVerified();
      }
    });

    await _checkNow(silent: true);
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
    final sentFromQuery =
        (params['verificationEmailAlreadySent'] ?? '').trim().toLowerCase() ==
        'true';
    final isSignupSource = source == 'signup';
    final shouldShowSentState = isSignupSource || sentFromQuery;

    final prefillEmail = (params['prefillEmail'] ?? params['email'] ?? '')
        .toString()
        .trim();
    if (mounted) {
      setState(() {
        if (isSignupSource) _isSignupFlow = true;
        if (prefillEmail.isNotEmpty) {
          _prefillEmailFromLink = prefillEmail;
          _email ??= prefillEmail;
        }
      });
    }

    if (shouldShowSentState) {
      if (_cooldownTimer == null) {
        _startCooldown(60);
      }
      if (!_didShowInitialSentSnack && mounted) {
        _didShowInitialSentSnack = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          AppScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email verification sent successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        });
      }
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
      try { await FirebaseAuth.instance.currentUser?.reload(); } catch (_) {}
      if (!mounted) return true;
      setState(() => _processingActionLink = false);
      await _onVerified();
      return true;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return true;
      if (e.code == 'expired-action-code' || e.code == 'invalid-action-code') {
        setState(() {
          _processingActionLink = false;
          _verifyLinkState = _VerifyLinkState.expired;
        });
        return true;
      }
      setState(() => _processingActionLink = false);
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Could not verify this email link.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (_) {
      if (!mounted) return true;
      setState(() => _processingActionLink = false);
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not verify this email link.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_verified) {
      _checkNow(silent: true);
    }
  }

  Future<void> _safeSendVerificationEmail() async {
    try {
      final email = _resolvedPrefillEmail();
      if (email.isEmpty) {
        if (!mounted) return;
        AppScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please sign up or log in first before requesting another verification email.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        AppScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please sign up or log in first before requesting another verification email.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final safeEmail = Uri.encodeQueryComponent(email);
      final continueUrl = kIsWeb
          ? '${Uri.base.origin}/verify-email?prefillEmail=$safeEmail&source=signup'
          : '';
      if (continueUrl.isEmpty) {
        throw StateError(
          'Missing verify-email continue URL for resend verification flow.',
        );
      }

      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-east1',
      ).httpsCallable('sendCurrentUserVerifyEmailLink');
      final res = await callable.call<Map<dynamic, dynamic>>(<String, dynamic>{
        'email': email,
        'continueUrl': continueUrl,
      });
      final data = res.data.cast<dynamic, dynamic>();
      if (data['mailQueued'] != true) {
        throw StateError('Verification email was not queued.');
      }

      _startCooldown(30);
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification email sent to $email.'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = 'Could not send email: ${e.code}';
      if (e.code == 'too-many-requests') {
        msg = 'Too many requests. Please wait a few minutes then try again.';
        _startCooldown(60);
      }
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.orange),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = e.message?.trim().isNotEmpty == true
          ? e.message!.trim()
          : 'Could not send verification email (${e.code}).';
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send verification email: $e'),
          backgroundColor: Colors.orange,
        ),
      );
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
        context.go('/login');
        return;
      }
      await user.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      if (fresh != null && fresh.emailVerified) {
        await _onVerified();
      } else if (!silent && mounted) {
        AppScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Not verified yet. Please click the link in your email then try again.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {
      if (!silent && mounted) {
        AppScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not check verification status right now. Please try again.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _onVerified() async {
    if (_verified) return;
    _userChangeSub?.cancel();
    _userChangeSub = null;
    if (!mounted) return;
    setState(() => _verified = true);
  }

  Future<void> _goToLogin() async {
    _userChangeSub?.cancel();
    _userChangeSub = null;
    final verifiedEmail = _resolvedPrefillEmail();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    context.go(
      Uri(
        path: '/login',
        queryParameters: {'prefillEmail': verifiedEmail},
      ).toString(),
    );
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
                            isSignupFlow: _isSignupFlow,
                            onGoToLogin: _goToLogin,
                          )
                        : _verifyLinkState != _VerifyLinkState.none
                        ? _VerifyLinkStateView(
                            state: _verifyLinkState,
                            onResendVerification: _safeSendVerificationEmail,
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
                                'Verify your email',
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
                                    ? 'We sent a verification link to your email.'
                                    : 'We sent a verification link to:\n$_email',
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
                                        _isSignupFlow
                                            ? 'Open your email, click the verification link, then come back here.\n\nAfter verification, log in and complete your student profile.\n\nTip: Check Spam/Promotions.'
                                            : 'Open your email, click the verification link, then come back here.\n\nTip: Check Spam/Promotions.',
                                        style: TextStyle(
                                          color: textDark.withValues(alpha: 0.85),
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
                                      ? 'Resend available in $_cooldown s'
                                      : 'Resend verification email',
                                ),
                              ),
                              const SizedBox(height: 2),
                              TextButton(
                                onPressed: _processingActionLink
                                    ? null
                                    : _goToLogin,
                                style: TextButton.styleFrom(
                                  foregroundColor: primary.withValues(alpha: 0.9),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                child: const Text('Go to Login'),
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
  const _VerifiedState({required this.isSignupFlow, required this.onGoToLogin});

  final bool isSignupFlow;
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
          'Email verified successfully',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          isSignupFlow
              ? 'Your email has been verified.\nLog in and complete your student profile to continue.'
              : 'Your email has been verified. You can now log in to your account.',
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

class _VerifyLinkStateView extends StatelessWidget {
  const _VerifyLinkStateView({
    required this.state,
    required this.onGoToLogin,
    required this.onResendVerification,
  });

  final _VerifyLinkState state;
  final VoidCallback onGoToLogin;
  final Future<void> Function() onResendVerification;

  @override
  Widget build(BuildContext context) {
    final isExpired = state == _VerifyLinkState.expired;
    const title = 'Verification link expired';
    const description =
        'This verification link is no longer valid or has expired.\nRequest a new link below, or go to Login if your email is already verified.';

    return Column(
      key: ValueKey('verify-link-state-${state.name}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.link_off_rounded,
          size: 82,
          color: Color(0xFFEF6C00),
        ),
        const SizedBox(height: 14),
        const Text(
          title,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          description,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF6D7F62),
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 18),
        if (isExpired) ...[
          FilledButton(
            onPressed: () => onResendVerification(),
            child: const Text('Resend verification email'),
          ),
          const SizedBox(height: 10),
        ],
        TextButton(
          onPressed: onGoToLogin,
          child: const Text('Go to Login'),
        ),
      ],
    );
  }
}

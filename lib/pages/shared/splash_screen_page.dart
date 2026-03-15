import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/role_router.dart';
import 'widgets/app_branding.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logoZoomController;
  late final Animation<double> _logoScale;
  late final Animation<double> _textOpacity;
  late final Animation<double> _colorOverlayOpacity;
  late final bool _hasSession;
  late final double _navigateAt;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _hasSession = FirebaseAuth.instance.currentUser != null;
    // Start authenticated routing earlier, while animation continues, to avoid
    // mid-zoom freeze on the logged-in handoff.
    _navigateAt = _hasSession ? 0.68 : 0.88;
    _logoZoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _logoScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.88,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 24,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 20),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 4.9,
        ).chain(CurveTween(curve: Curves.easeInExpo)),
        weight: 56,
      ),
    ]).animate(_logoZoomController);
    _textOpacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _logoZoomController,
        curve: const Interval(0.44, 0.70, curve: Curves.easeInOut),
      ),
    );
    _colorOverlayOpacity = _hasSession
        ? Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(
              parent: _logoZoomController,
              curve: const Interval(0.76, 0.98, curve: Curves.easeInOut),
            ),
          )
        : TweenSequence<double>([
            TweenSequenceItem(
              tween: Tween<double>(begin: 0.0, end: 0.62).chain(
                CurveTween(curve: Curves.easeIn),
              ),
              weight: 45,
            ),
            TweenSequenceItem(
              tween: Tween<double>(begin: 0.62, end: 0.0).chain(
                CurveTween(curve: Curves.easeOut),
              ),
              weight: 55,
            ),
          ]).animate(
            CurvedAnimation(
              parent: _logoZoomController,
              curve: const Interval(0.82, 1.0),
            ),
          );
    _logoZoomController.addListener(() {
      if (_navigated) return;
      if (_logoZoomController.value >= _navigateAt) {
        _navigated = true;
        _navigateAfterSplash();
      }
    });
    _logoZoomController.forward();
  }

  Future<void> _navigateAfterSplash() async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await RoleRouter.route(context, fastPathForSplash: true);
      return;
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/welcome');
  }

  @override
  void dispose() {
    _logoZoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF4FFF8),
              Color(0xFFCDEFD8),
              Color(0xFF4FAF67),
              Color(0xFF0A4D23),
            ],
            stops: [0.0, 0.36, 0.72, 1.0],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 900;
            final isTablet =
                constraints.maxWidth >= 600 && constraints.maxWidth < 900;
            final logoSize = isDesktop ? 350.0 : (isTablet ? 200.0 : 180.0);
            final titleSize = constraints.maxWidth >= 900
                ? 42.0
                : (constraints.maxWidth >= 600 ? 38.0 : 34.0);

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _logoScale,
                        child: AppBranding.logo(width: logoSize, height: logoSize),
                      ),
                      FadeTransition(
                        opacity: _textOpacity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.translate(
                              offset: const Offset(0, -16),
                              child: Text(
                                "Baliuag University DiscipLink",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: titleSize,
                                  height: 1.04,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                  color: Color(0xFF0D4B22),
                                  shadows: const [
                                    Shadow(
                                      offset: Offset(0, 1.2),
                                      blurRadius: 3.2,
                                      color: Color(0x33000000),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(0, -8),
                              child: Text(
                                "Student Violation and Counseling Management System\nwith Handbook Guidance Support",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: (titleSize * 0.38).clamp(12.0, 16.0),
                                  height: 1.3,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0D4B22),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
          FadeTransition(
            opacity: _colorOverlayOpacity,
            child: const ColoredBox(color: Color(0xFF0A4D23)),
          ),
        ],
      ),
    );
  }
}

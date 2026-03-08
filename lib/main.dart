import 'package:apps/pages/auth/complete_profile_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'pages/auth/firebase_options.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/set_password_page.dart';
import 'pages/auth/sign_up_page.dart';
import 'pages/auth/verify_email_page.dart';
import 'pages/shared/landing_page.dart';
import 'pages/shared/splash_screen_page.dart';
import 'pages/shared/temp_login_page.dart';
import 'pages/shared/welcome_screen_page.dart';

class _RootGate extends StatelessWidget {
  const _RootGate();

  bool _isSetPasswordDeepLink() {
    final base = Uri.base;
    final hasResetMode =
        (base.queryParameters['mode'] ?? '').trim() == 'resetPassword';
    final fragment = base.fragment;
    final hasSetPasswordRoute =
        fragment.startsWith('/set-password') ||
        fragment.startsWith('set-password');
    return hasResetMode || hasSetPasswordRoute;
  }

  @override
  Widget build(BuildContext context) {
    if (_isSetPasswordDeepLink()) {
      return const SetPasswordPage();
    }
    return const SplashScreen();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF1B5E20);
    final roundedButtonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Student Handbook',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: brandGreen,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 50),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            backgroundColor: brandGreen,
            foregroundColor: Colors.white,
            disabledBackgroundColor: brandGreen.withValues(alpha: 0.35),
            disabledForegroundColor: Colors.white70,
            elevation: 0,
            shape: roundedButtonShape,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 50),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            backgroundColor: brandGreen,
            foregroundColor: Colors.white,
            disabledBackgroundColor: brandGreen.withValues(alpha: 0.35),
            disabledForegroundColor: Colors.white70,
            shape: roundedButtonShape,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 50),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            foregroundColor: brandGreen,
            shape: roundedButtonShape,
            side: BorderSide(color: brandGreen.withValues(alpha: 0.45)),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            foregroundColor: brandGreen,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const _RootGate(),
        '/splash': (context) => const SplashScreen(),
        '/welcome': (context) => const WelcomeScreen(),
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignUpPage(),
        '/set-password': (context) => const SetPasswordPage(),
        '/complete-profile': (context) => const CompleteProfilePage(),
        '/landing': (context) => const LandingPage(),
        '/verify-email': (context) => const VerifyEmailPage(),
        '/temp-login': (context) => const TempLoginPage(),
      },
    );
  }
}

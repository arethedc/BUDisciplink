import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_web_plugins/url_strategy.dart';

import 'pages/auth/firebase_options.dart';
import 'services/app_router.dart';
import 'services/app_firestore.dart';
import 'services/push_notifications_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Firestore DB: ${AppFirestore.instance.databaseId}');
  await PushNotificationsService.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF1B5E20);
    final baseScheme = ColorScheme.fromSeed(seedColor: brandGreen);
    final roundedButtonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'BUDiscipLink',
      routerConfig: AppRouter.router,
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      supportedLocales: FlutterQuillLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: baseScheme.copyWith(
          surface: Colors.white,
          surfaceContainer: Colors.white,
          surfaceContainerHigh: Colors.white,
          surfaceContainerHighest: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        cardColor: Colors.white,
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: brandGreen, width: 1.6),
          ),
        ),
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
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/user_service.dart';
import '../../services/role_router.dart';
import '../auth/forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _prefilledFromArgs = false;

  bool isLoading = false;
  bool _obscurePassword = true;

  // ===== DESIGN THEME (copied from reference) =====
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  Future<void> login() async {
    if (isLoading) return;
    setState(() => isLoading = true);

    try {
      // 1️⃣ Firebase login
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final authUser = cred.user;
      if (authUser == null) {
        throw Exception("Login failed. No user returned.");
      }

      // 2️⃣ Refresh user + check email verification
      await authUser.reload();
      final freshUser = FirebaseAuth.instance.currentUser;
      if (freshUser != null && !freshUser.emailVerified) {
        // ✅ DO NOT sign out here. Keep logged in so VerifyEmailPage can resend/check.
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/verify-email',
          (r) => false,
        );
        return;
      }

      // 3️⃣ Ensure user doc exists (only after verified)
      await UserService().ensureUserDocExists();

      // 4️⃣ Route normally
      if (!mounted) return;
      await RoleRouter.route(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Login failed'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _goToForgotPassword() {
    // ✅ Clean behavior:
    // - Do NOT send email here
    // - Just open the ForgotPasswordPage
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilledFromArgs) return;
    _prefilledFromArgs = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final email = (args['prefillEmail'] ?? args['email'] ?? '')
          .toString()
          .trim();
      if (email.isNotEmpty) {
        emailController.text = email;
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
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
      filled: true,
      fillColor: Colors.white,
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
        final bool isMobile = constraints.maxWidth < 600;

        // ✅ fixed size (no stretch). Use 420 on all screens, but allow smaller phones.
        const double fixedCardWidth = 420.0;
        final double cardWidth = constraints.maxWidth < fixedCardWidth
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
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primary.withOpacity(0.15),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
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
                        const SizedBox(height: 8),

                        // Logo (Smaller for login)
                        Center(
                          child: SizedBox(
                            width: 100,
                            height: 100,
                            child: Image.asset(
                              "lib/assets/bu_logo.png",
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        const Text(
                          "WELCOME BACK",
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

                        const Text(
                          "Login to your account to continue",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: hint,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),

                        const SizedBox(height: 22),

                        // Email
                        TextField(
                          controller: emailController,
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: _decor(
                            label: 'Email',
                            icon: Icons.email_outlined,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Password
                        TextField(
                          controller: passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: _decor(
                            label: 'Password',
                            icon: Icons.lock_outline,
                            suffix: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                color: primary.withOpacity(0.85),
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),

                        // ✅ Forgot password -> redirects to ForgotPasswordPage
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: isLoading ? null : _goToForgotPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: primary,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                            ),
                            child: const Text("Forgot password?"),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Login Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    "LOGIN",
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
                          onPressed: () => Navigator.pushReplacementNamed(
                            context,
                            '/signup',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: primary,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                            ),
                          ),
                          child: const Text("Don't have account yet? Sign Up"),
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
                                  "Use your BU account to access the handbook.",
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
        );
      },
    );
  }
}

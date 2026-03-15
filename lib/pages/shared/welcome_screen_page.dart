import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../auth/login_page.dart';
import '../auth/sign_up_page.dart';
import '../counseling_admin/counseling_dashboard.dart';
import '../guard/guard_dashboard.dart';
import '../osa_admin/osa_dashboard.dart';
import '../professor/professor_dashboard.dart';
import '../student/student_dashboard.dart';
import '../super_admin/super_admin_dashboard.dart';
import 'widgets/app_branding.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});


  Widget _devNavButton(BuildContext context, String label, Widget page) {
    return OutlinedButton(
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1B5E20),
        side: const BorderSide(color: Color(0xFF1B5E20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF1B5E20);
    const lightBg = Color(0xFFF5FAF6);

    return Scaffold(
      backgroundColor: lightBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;

            final isDesktop = w >= 900;
            final isTablet = w >= 600 && w < 900;

            final contentMaxWidth = isDesktop
                ? 520.0
                : (isTablet ? 460.0 : double.infinity);

            final logoSize = isDesktop ? 350.0 : (isTablet ? 200.0 : 180.0);
            final titleSize = (w * 0.075).clamp(24.0, 42.0);
            final subSize = isDesktop ? 15.0 : 14.0;
            final bodySize = isDesktop ? 13.5 : 12.5;
            final buttonHeight = isDesktop ? 56.0 : 52.0;

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: isDesktop ? 18 : 10),

                      SizedBox(
                        width: logoSize,
                        height: logoSize,
                        child: AppBranding.logo(fit: BoxFit.contain),
                      ),


                      Transform.translate(
                        offset: const Offset(0, -30),
                        child: Text(
                          "Baliuag University DiscipLink",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: titleSize,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                            color: primaryGreen,
                            shadows: const [
                              Shadow(
                                offset: Offset(0, 1),
                                blurRadius: 2,
                                color: Color(0x26000000),
                              ),
                            ],
                          ),
                        ),
                      ),

        
                      const SizedBox(height: 2),


                      Text(
                     "Your unified platform for student discipline,\n"
                      "counseling referrals, appointments, and case tracking\n"
                      "at Baliuag University.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: bodySize,
                          height: 1.35,
                          color: primaryGreen,
                        ),
                      ),

                      const SizedBox(height: 26),

                      // SIGN UP
                      SizedBox(
                        width: double.infinity,
                        height: buttonHeight,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SignUpPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.group_add, size: 20),
                          label: const Text(
                            "Sign Up",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // LOG IN
                      SizedBox(
                        width: double.infinity,
                        height: buttonHeight,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.login,
                            size: 20,
                            color: primaryGreen,
                          ),
                          label: const Text(
                            "Log In",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryGreen,
                            side: const BorderSide(
                              color: primaryGreen,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

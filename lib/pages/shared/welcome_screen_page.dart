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

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static final RegExp _schoolYearRegex = RegExp(
    r'(20\d{2})\s*-\s*(20\d{2})',
    caseSensitive: false,
  );

  String? _normalizeSchoolYearLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    final match = _schoolYearRegex.firstMatch(value);
    if (match != null) {
      final start = match.group(1);
      final end = match.group(2);
      if (start != null && end != null) {
        return 'S.Y. $start-$end';
      }
    }

    final lower = value.toLowerCase();
    if (lower.startsWith('s.y.') || lower.startsWith('sy ')) {
      return value;
    }
    return null;
  }

  String? _extractSchoolYearFromHandbookMeta(Map<String, dynamic>? data) {
    if (data == null) return null;

    final candidates = [
      data['activeSchoolYearLabel'],
      data['schoolYearLabel'],
      data['academicYearLabel'],
      data['activeVersionLabel'],
      data['activeVersionId'],
    ];

    for (final candidate in candidates) {
      final normalized = _normalizeSchoolYearLabel((candidate ?? '').toString());
      if (normalized != null) return normalized;
    }
    return null;
  }

  String? _extractSchoolYearFromActiveAcademic(
    QuerySnapshot<Map<String, dynamic>>? snap,
  ) {
    if (snap == null || snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    final data = doc.data();
    return _normalizeSchoolYearLabel(
      (data['label'] ?? data['schoolYearLabel'] ?? doc.id).toString(),
    );
  }

  Widget _schoolYearLabel(double fontSize) {
    const styleColor = Color(0xFF1B5E20);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('handbook_meta')
          .doc('current')
          .snapshots(),
      builder: (context, handbookSnap) {
        final handbookLabel = _extractSchoolYearFromHandbookMeta(
          handbookSnap.data?.data(),
        );
        if (handbookLabel != null) {
          return Text(
            handbookLabel,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: styleColor,
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('academic_years')
              .where('status', isEqualTo: 'active')
              .limit(1)
              .snapshots(),
          builder: (context, academicSnap) {
            final activeLabel = _extractSchoolYearFromActiveAcademic(
              academicSnap.data,
            );
            return Text(
              activeLabel ?? 'S.Y. --',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: styleColor,
              ),
            );
          },
        );
      },
    );
  }

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

            final logoSize = isDesktop ? 150.0 : (isTablet ? 140.0 : 130.0);
            final titleSize = isDesktop ? 34.0 : (isTablet ? 32.0 : 30.0);
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
                        child: Image.asset(
                          "lib/assets/bu_logo.png",
                          fit: BoxFit.contain,
                        ),
                      ),

                      const SizedBox(height: 18),

                      Text(
                        "College Student\nDigital\nHandbook",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleSize,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: primaryGreen,
                        ),
                      ),

                      const SizedBox(height: 10),

                      _schoolYearLabel(subSize),

                      const SizedBox(height: 14),

                      Text(
                        "Welcome to your comprehensive digital\n"
                        "companion for the academic year. Access all\n"
                        "your college resources, schedules, and\n"
                        "important information in one place.",
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

                      if (kDebugMode) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 24),
                        const Text(
                          "Quick Role Access (Debug)",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: primaryGreen,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _devNavButton(
                              context,
                              "Student",
                              const StudentDashboard(),
                            ),
                            _devNavButton(
                              context,
                              "Professor",
                              const ProfessorDashboard(),
                            ),
                            _devNavButton(context, "OSA", const OsaDashboard()),
                            _devNavButton(
                              context,
                              "Counseling",
                              const CounselingDashboard(),
                            ),
                            _devNavButton(
                              context,
                              "Guard",
                              const GuardDashboard(),
                            ),
                            _devNavButton(
                              context,
                              "Super Admin",
                              const SuperAdminDashboard(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Debug-only shortcuts, bypass auth.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: primaryGreen.withValues(alpha: 0.75),
                          ),
                        ),
                      ],

                      Text(
                        "By continuing, you agree to our Terms of Service and\nPrivacy Policy",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isDesktop ? 11 : 10,
                          color: primaryGreen,
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
    );
  }
}



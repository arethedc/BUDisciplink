import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'widgets/logout_confirm_dialog.dart';

class PendingApprovalPage extends StatelessWidget {
  const PendingApprovalPage({super.key});

  // ===== DESIGN THEME (match your app) =====
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showLogoutConfirmDialog(context);
    if (!context.mounted || !confirmed) return;
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final contentMaxWidth = w >= 900 ? 520.0 : double.infinity;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        foregroundColor: primary,
        automaticallyImplyLeading: false,
        title: const Text(
          'Pending Approval',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Logout'),
            style: TextButton.styleFrom(
              foregroundColor: primary,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Icon(
                      Icons.hourglass_top_rounded,
                      color: primary,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    "PENDING APPROVAL",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Your profile has been submitted. Please wait for your department admin’s approval.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textDark.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
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
                            "You can log out and come back later. Once approved, you’ll be able to access your dashboard.",
                            style: TextStyle(
                              color: hint,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => _logout(context),
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: const Text(
                        "Log out",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: const BorderSide(color: primary, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:apps/pages/counseling_admin/counseling_dashboard.dart';
import 'package:apps/pages/osa_admin/osa_dashboard.dart';
import 'package:apps/pages/professor/professor_dashboard.dart';
import 'package:apps/pages/super_admin/super_admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:apps/pages/student/student_dashboard.dart';

class TempLoginPage extends StatelessWidget {
  const TempLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Temporary Login (Testing)'),
        backgroundColor: Colors.green,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.school, size: 100, color: Colors.green),

                const SizedBox(height: 20),

                const Text(
                  'Select Role to Continue',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),

                const SizedBox(height: 30),

                _roleButton(
                  context,
                  label: 'Student',
                  icon: Icons.person,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const StudentDashboard(),
                      ),
                    );
                    debugPrint('Logged in as: student');
                  },
                ),

                const SizedBox(height: 16),

                _roleButton(
                  context,
                  label: 'Teacher',
                  icon: Icons.school_outlined,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfessorDashboard(),
                      ),
                    );
                    debugPrint('Logged in as: teacher');
                  },
                ),

                const SizedBox(height: 16),

                _roleButton(
                  context,
                  label: 'Council Admin',
                  icon: Icons.admin_panel_settings,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CounselingDashboard(),
                      ),
                    );
                    debugPrint('Logged in as: counseling admin ');
                  },
                ),

                const SizedBox(height: 16),

                _roleButton(
                  context,
                  label: 'OSA Admin',
                  icon: Icons.support_agent,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const OsaDashboard(),
                      ),
                    );
                    debugPrint('Logged in as: osa admin');
                  },
                ),
                const SizedBox(height: 30),

                _roleButton(
                  context,
                  label: 'Super Admin',
                  icon: Icons.person,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SuperAdminDashboard(),
                      ),
                    );
                    debugPrint('Logged in as: super_admin');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(fontSize: 18, color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../pages/shared/handbook/handbook_sections_screen.dart';
import '../pages/professor/violation_report_page.dart';
import 'student_list_page.dart';
import 'create_user_page.dart';
import '../pages/shared/welcome_screen_page.dart';
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth >= 900;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Dashboard'),
            backgroundColor: Colors.green,
            automaticallyImplyLeading: !isDesktop,
          ),

          // Drawer only for mobile
          drawer: isDesktop ? null : _buildDrawer(context),

          body: Row(
            children: [
              // Sidebar for desktop
              if (isDesktop)
                SizedBox(
                  width: 260,
                  child: _buildDrawer(context),
                ),

              // Main content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Overview',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),

                      const SizedBox(height: 16),

                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            int columns = 2;

                            if (constraints.maxWidth >= 1200) {
                              columns = 4;
                            } else if (constraints.maxWidth >= 800) {
                              columns = 3;
                            }

                            return GridView.count(
                              crossAxisCount: columns,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              children: const [
                                DashboardCard(
                                  icon: Icons.warning,
                                  title: 'Total Violations',
                                  value: '25',
                                ),
                                DashboardCard(
                                  icon: Icons.pending_actions,
                                  title: 'Pending Reports',
                                  value: '5',
                                ),
                                DashboardCard(
                                  icon: Icons.person_off,
                                  title: 'Repeat Offenders',
                                  value: '8',
                                ),
                                DashboardCard(
                                  icon: Icons.book,
                                  title: 'Handbook Rules',
                                  value: '40',
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ================= DRAWER / SIDEBAR =================

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.green),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.school, color: Colors.white, size: 48),
                SizedBox(height: 10),
                Text(
                  'Digital Handbook',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
          ),

          ListTile(
            leading: const Icon(Icons.dashboard, color: Colors.green),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DashboardPage(),
                ),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.book, color: Colors.green),
            title: const Text('Student Handbook'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HandbookSectionsScreen(),
                ),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.report, color: Colors.green),
            title: const Text('Report Violation'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ViolationReportPage(),
                ),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.people, color: Colors.green),
            title: const Text('Students'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StudentListPage(),
                ),
              );
            },
          ),

          ExpansionTile(
            leading:
            const Icon(Icons.manage_accounts, color: Colors.green),
            title: const Text('Manage Users'),
            childrenPadding: const EdgeInsets.only(left: 30),
            children: [
              ListTile(
                leading:
                const Icon(Icons.person_add, color: Colors.green),
                title: const Text('Create User'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateUserPage(),
                    ),
                  );
                },
              ),
              ListTile(
                leading:
                const Icon(Icons.people, color: Colors.green),
                title: const Text('View Users'),
                onTap: () {},
              ),
            ],
          ),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.green),
            title: const Text('Logout'),
            onTap: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const WelcomeScreen(),
                ),
                    (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}

// ================= DASHBOARD CARD =================

class DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.green),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

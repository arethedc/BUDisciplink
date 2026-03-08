import 'package:apps/pages/professor/violation_report_page.dart';
import 'package:apps/pages/professor/MySubmittedReportPage.dart';
import 'package:apps/pages/shared/handbook/handbook_ai_assistant_sheet.dart';
import 'package:apps/pages/shared/handbook/handbook_sections_screen.dart';
import 'package:apps/pages/shared/notifications/app_notifications_ui.dart';
import 'package:apps/pages/shared/profile/unified_profile_page.dart';
import 'package:apps/pages/shared/welcome_screen_page.dart';
import 'package:apps/pages/shared/widgets/logout_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'professor_counseling_page.dart';
import 'professor_home_page.dart';

class ProfessorDashboard extends StatefulWidget {
  const ProfessorDashboard({super.key});

  @override
  State<ProfessorDashboard> createState() => _ProfessorDashboardState();
}

class _ProfessorDashboardState extends State<ProfessorDashboard> {
  int _currentIndex = 0;
  bool _showDesktopNotifications = false;

  // ================== THEME (same as StudentDashboard) ==================
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);
  static const surface = Color(0xFFFFFFFF);

  // ================== PAGES ==================
  final List<Widget> _pages = const [
    ProfessorHomePage(),
    HandbookSectionsScreen(),
    ViolationReportPage(),
    MySubmittedCasesPage(),
    ProfessorCounselingPage(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(Icons.home_rounded, 'Home'),
    _NavItem(Icons.menu_book_rounded, 'Handbook'),
    _NavItem(Icons.report_rounded, 'Report Violation'),
    _NavItem(Icons.assignment_rounded, 'My Reports'),
    _NavItem(Icons.support_agent_rounded, 'Counseling Referrals'),
  ];

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return "Home";
      case 1:
        return "Student Handbook";
      case 2:
        return "Report Violation";
      case 3:
        return "My Submitted Reports";
      case 4:
        return "Counseling Referrals";
      default:
        return "Professor Portal";
    }
  }

  Future<void> _logout() async {
    final confirmed = await showLogoutConfirmDialog(context);
    if (!mounted || !confirmed) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _go(int i) => setState(() => _currentIndex = i);

  Future<void> _openProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const UnifiedProfilePage()));
  }

  void _toggleDesktopNotifications() {
    setState(() => _showDesktopNotifications = !_showDesktopNotifications);
  }

  void _closeDesktopNotifications() {
    if (_showDesktopNotifications) {
      setState(() => _showDesktopNotifications = false);
    }
  }

  Future<void> _openNotificationsPage() async {
    _closeDesktopNotifications();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AppNotificationsPage()));
  }

  String _displayName(Map<String, dynamic> data, User user) {
    final dn = (data['displayName'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final full = ('$first $last').trim();
    if (full.isNotEmpty) return full;
    final email = (data['email'] ?? user.email ?? '').toString().trim();
    if (email.contains('@')) return email.split('@').first;
    return 'Professor';
  }

  String _email(Map<String, dynamic> data, User user) {
    final e = (data['email'] ?? user.email ?? '').toString().trim();
    return e.isEmpty ? '--' : e;
  }

  String _title(Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString().toLowerCase().trim();
    switch (role) {
      case 'professor':
        return 'Professor Account';
      default:
        return 'Professor Portal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Not logged in',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final accountName = _displayName(data, user);
        final accountEmail = _email(data, user);
        final accountTitle = _title(data);

        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;

            // ✅ same responsiveness rule as student dashboard
            final bool isDesktop = w >= 900;
            final bool isPhoneOrTablet = !isDesktop;

            return Scaffold(
              backgroundColor: bg,

              // ✅ Drawer only for phone/tablet
              drawer: isPhoneOrTablet
                  ? Drawer(
                      child: _MenuPanel(
                        currentIndex: _currentIndex,
                        navItems: _navItems,
                        primary: primary,
                        hint: hint,
                        textDark: textDark,
                        surface: surface,
                        onSelect: (i) {
                          Navigator.of(context).maybePop();
                          _go(i);
                        },
                        onProfile: () {
                          Navigator.of(context).maybePop();
                          _openProfile();
                        },
                        onSettings: () {
                          Navigator.of(context).maybePop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Settings tapped")),
                          );
                        },
                        onLogout: () {
                          Navigator.of(context).maybePop();
                          _logout();
                        },
                        accountTitle: accountTitle,
                        accountEmail: accountEmail,
                        accountName: accountName,
                      ),
                    )
                  : null,

              body: Row(
                children: [
                  // ✅ Permanent sidebar on desktop
                  if (isDesktop)
                    SizedBox(
                      width: 260,
                      child: Material(
                        color: surface,
                        child: _MenuPanel(
                          currentIndex: _currentIndex,
                          navItems: _navItems,
                          primary: primary,
                          hint: hint,
                          textDark: textDark,
                          surface: surface,
                          onSelect: _go,
                          onProfile: () {
                            _openProfile();
                          },
                          onSettings: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Settings tapped")),
                            );
                          },
                          onLogout: _logout,
                          accountTitle: accountTitle,
                          accountEmail: accountEmail,
                          accountName: accountName,
                        ),
                      ),
                    ),

                  // ✅ Main content
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
                              // ✅ Shared header controlled by dashboard
                              Builder(
                                builder: (ctx) {
                                  return Container(
                                    height: kToolbarHeight,
                                    width: double.infinity,
                                    color: primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        if (isPhoneOrTablet)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.menu_rounded,
                                              color: Colors.white,
                                            ),
                                            onPressed: () =>
                                                Scaffold.of(ctx).openDrawer(),
                                          )
                                        else
                                          const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _pageTitle(),
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.notifications_none_rounded,
                                            color: Colors.white,
                                          ),
                                          onPressed: () {
                                            if (isDesktop) {
                                              _toggleDesktopNotifications();
                                              return;
                                            }
                                            _openNotificationsPage();
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                              // ✅ Page content (keeps tab state)
                              Expanded(
                                child: IndexedStack(
                                  index: _currentIndex,
                                  children: _pages,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isDesktop && _showDesktopNotifications) ...[
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _closeDesktopNotifications,
                            ),
                          ),
                          Positioned(
                            top: kToolbarHeight + 8,
                            right: 14,
                            child: DesktopNotificationsPanel(
                              uid: user.uid,
                              onClose: _closeDesktopNotifications,
                              onSeeAll: _openNotificationsPage,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // ✅ Bottom nav only for phone/tablet
              bottomNavigationBar: isPhoneOrTablet
                  ? BottomNavigationBar(
                      currentIndex: _currentIndex,
                      type: BottomNavigationBarType.fixed,
                      selectedItemColor: primary,
                      unselectedItemColor: hint,
                      backgroundColor: surface,
                      onTap: _go,
                      items: _navItems
                          .map(
                            (item) => BottomNavigationBarItem(
                              icon: Icon(item.icon),
                              label: item.label,
                            ),
                          )
                          .toList(),
                    )
                  : null,

              floatingActionButton: FloatingActionButton(
                backgroundColor: primary,
                onPressed: () => showHandbookAiAssistantSheet(context),
                child: const Icon(Icons.chat, color: Colors.white),
              ),
            );
          },
        );
      },
    );
  }
}

// ================= MODELS =================

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

// ================= SHARED MENU PANEL (Drawer + Sidebar) =================

class _MenuPanel extends StatelessWidget {
  final int currentIndex;
  final List<_NavItem> navItems;

  final Color primary;
  final Color hint;
  final Color textDark;
  final Color surface;

  final ValueChanged<int> onSelect;
  final VoidCallback onProfile;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  // ✅ allow professor-specific header text without changing dashboard logic
  final String accountTitle;
  final String accountEmail;
  final String accountName;

  const _MenuPanel({
    required this.currentIndex,
    required this.navItems,
    required this.primary,
    required this.hint,
    required this.textDark,
    required this.surface,
    required this.onSelect,
    required this.onProfile,
    required this.onSettings,
    required this.onLogout,
    required this.accountTitle,
    required this.accountEmail,
    required this.accountName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: surface,
      child: Column(
        children: [
          // ✅ Account header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 42, 16, 18),
            width: double.infinity,
            decoration: BoxDecoration(
              color: surface,
              border: Border(
                bottom: BorderSide(color: primary.withValues(alpha: 0.12)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.account_circle, size: 52, color: primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        accountName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        accountEmail,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: hint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        accountTitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: textDark.withValues(alpha: 0.70),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ✅ Main nav
          ...navItems.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final active = currentIndex == i;

            final Color iconColor = active
                ? primary
                : textDark.withValues(alpha: 0.85);
            final Color textColor = active
                ? primary
                : textDark.withValues(alpha: 0.92);

            return InkWell(
              onTap: () => onSelect(i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? primary.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(item.icon, color: iconColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: active
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const Spacer(),

          Divider(color: primary.withValues(alpha: 0.15), height: 18),

          // ✅ Profile
          InkWell(
            onTap: onProfile,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    color: textDark.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Profile",
                    style: TextStyle(
                      color: textDark.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ✅ Settings
          InkWell(
            onTap: onSettings,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.settings_outlined,
                    color: textDark.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Settings",
                    style: TextStyle(
                      color: textDark.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Divider(color: primary.withValues(alpha: 0.15), height: 18),

          // ✅ Logout
          InkWell(
            onTap: onLogout,
            child: Container(
              margin: const EdgeInsets.fromLTRB(10, 4, 10, 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.logout_rounded, color: Colors.red),
                  SizedBox(width: 12),
                  Text(
                    "Logout",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

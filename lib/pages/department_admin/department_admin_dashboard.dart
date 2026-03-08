import 'package:apps/pages/shared/handbook/handbook_sections_screen.dart';
import 'package:apps/pages/shared/notifications/app_notifications_ui.dart';
import 'package:apps/pages/shared/profile/unified_profile_page.dart';
import 'package:apps/pages/shared/welcome_screen_page.dart';
import 'package:apps/pages/shared/widgets/logout_confirm_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../osa_admin/user_management_page.dart';
import 'department_admin_home_page.dart';
import 'department_violation_alerts_page.dart';

class DepartmentAdminDashboard extends StatefulWidget {
  const DepartmentAdminDashboard({super.key});

  @override
  State<DepartmentAdminDashboard> createState() =>
      _DepartmentAdminDashboardState();
}

class _DepartmentAdminDashboardState extends State<DepartmentAdminDashboard> {
  int _currentIndex = 0;
  bool _settingsOpen = false;
  bool _showDesktopNotifications = false;

  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);
  static const surface = Color(0xFFFFFFFF);

  List<Widget> get _pages => [
    DepartmentAdminHomePage(
      onOpenUserManagement: () => _goSettings(3),
      onOpenViolationReview: () => _go(2),
    ),
    const HandbookSectionsScreen(),
    const DepartmentViolationAlertsPage(),
    const UserManagementPage(studentsOnlyScope: true),
    const UnifiedProfilePage(),
  ];

  final List<_DeptNavItem> _navItems = const [
    _DeptNavItem(Icons.dashboard_rounded, 'Dashboard'),
    _DeptNavItem(Icons.menu_book_rounded, 'Handbook'),
    _DeptNavItem(Icons.rule_rounded, 'Violation Alerts'),
  ];

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Student Handbook';
      case 2:
        return 'Violation Alerts';
      case 3:
        return 'Student Management';
      case 4:
        return 'Profile';
      default:
        return 'Department Admin Portal';
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

  String _displayName(Map<String, dynamic> data, User user) {
    final dn = (data['displayName'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final full = ('$first $last').trim();
    if (full.isNotEmpty) return full;
    final email = (data['email'] ?? user.email ?? '').toString().trim();
    if (email.contains('@')) return email.split('@').first;
    return 'Department Admin';
  }

  String _email(Map<String, dynamic> data, User user) {
    final e = (data['email'] ?? user.email ?? '').toString().trim();
    return e.isEmpty ? '--' : e;
  }

  String _subtitle(Map<String, dynamic> data) {
    final dept = (data['employeeProfile']?['department'] ?? '')
        .toString()
        .trim();
    return dept.isEmpty ? 'Department Admin' : 'Department: $dept';
  }

  void _go(int i) => setState(() => _currentIndex = i);

  void _goSettings(int pageIndex) {
    setState(() {
      _settingsOpen = true;
      _currentIndex = pageIndex;
    });
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
        final accountSubtitle = _subtitle(data);

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 900;

            return Scaffold(
              backgroundColor: bg,
              drawer: isDesktop
                  ? null
                  : Drawer(
                      child: _DeptMenuPanel(
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
                          _go(4);
                        },
                        settingsOpen: _settingsOpen,
                        onToggleSettings: () {
                          setState(() => _settingsOpen = !_settingsOpen);
                        },
                        onSelectSettingsItem: (pageIndex) {
                          Navigator.of(context).maybePop();
                          _goSettings(pageIndex);
                        },
                        onLogout: () {
                          Navigator.of(context).maybePop();
                          _logout();
                        },
                        accountName: accountName,
                        accountEmail: accountEmail,
                        accountSubtitle: accountSubtitle,
                      ),
                    ),
              body: Row(
                children: [
                  if (isDesktop)
                    SizedBox(
                      width: 260,
                      child: Material(
                        color: surface,
                        child: _DeptMenuPanel(
                          currentIndex: _currentIndex,
                          navItems: _navItems,
                          primary: primary,
                          hint: hint,
                          textDark: textDark,
                          surface: surface,
                          onSelect: _go,
                          onProfile: () => _go(4),
                          settingsOpen: _settingsOpen,
                          onToggleSettings: () =>
                              setState(() => _settingsOpen = !_settingsOpen),
                          onSelectSettingsItem: _goSettings,
                          onLogout: _logout,
                          accountName: accountName,
                          accountEmail: accountEmail,
                          accountSubtitle: accountSubtitle,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
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
                                        if (!isDesktop)
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
            );
          },
        );
      },
    );
  }
}

class _DeptNavItem {
  final IconData icon;
  final String label;
  const _DeptNavItem(this.icon, this.label);
}

class _DeptMenuPanel extends StatelessWidget {
  final int currentIndex;
  final List<_DeptNavItem> navItems;

  final Color primary;
  final Color hint;
  final Color textDark;
  final Color surface;

  final ValueChanged<int> onSelect;
  final VoidCallback onProfile;
  final bool settingsOpen;
  final VoidCallback onToggleSettings;
  final ValueChanged<int> onSelectSettingsItem;
  final VoidCallback onLogout;

  final String accountName;
  final String accountEmail;
  final String accountSubtitle;

  const _DeptMenuPanel({
    required this.currentIndex,
    required this.navItems,
    required this.primary,
    required this.hint,
    required this.textDark,
    required this.surface,
    required this.onSelect,
    required this.onProfile,
    required this.settingsOpen,
    required this.onToggleSettings,
    required this.onSelectSettingsItem,
    required this.onLogout,
    required this.accountName,
    required this.accountEmail,
    required this.accountSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                        accountSubtitle,
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 10, bottom: 16),
              child: Column(
                children: [
                  ...navItems.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    final active = currentIndex == i;

                    final iconColor = active
                        ? primary
                        : textDark.withValues(alpha: 0.85);
                    final textColor = active
                        ? primary
                        : textDark.withValues(alpha: 0.92);

                    return InkWell(
                      onTap: () => onSelect(i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
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

                  const SizedBox(height: 8),
                  Divider(color: primary.withValues(alpha: 0.15), height: 18),

                  Builder(
                    builder: (_) {
                      final profileActive = currentIndex == 4;
                      final profileIconColor = profileActive
                          ? primary
                          : textDark.withValues(alpha: 0.85);
                      final profileTextColor = profileActive
                          ? primary
                          : textDark.withValues(alpha: 0.92);
                      return InkWell(
                        onTap: onProfile,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: profileActive
                                ? primary.withValues(alpha: 0.10)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                color: profileIconColor,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Profile",
                                style: TextStyle(
                                  color: profileTextColor,
                                  fontWeight: profileActive
                                      ? FontWeight.w900
                                      : FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  InkWell(
                    onTap: onToggleSettings,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: settingsOpen
                            ? primary.withValues(alpha: 0.08)
                            : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.settings_outlined,
                            color: textDark.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Settings",
                              style: TextStyle(
                                color: textDark.withValues(alpha: 0.92),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Icon(
                            settingsOpen
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: hint,
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (settingsOpen) ...[
                    const SizedBox(height: 4),
                    _DeptSubItem(
                      label: 'Student Management',
                      icon: Icons.groups_rounded,
                      active: currentIndex == 3,
                      primary: primary,
                      textDark: textDark,
                      onTap: () => onSelectSettingsItem(3),
                    ),
                    const SizedBox(height: 6),
                  ],

                  Divider(color: primary.withValues(alpha: 0.15), height: 18),

                  InkWell(
                    onTap: onLogout,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _DeptSubItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color primary;
  final Color textDark;
  final VoidCallback onTap;

  const _DeptSubItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.primary,
    required this.textDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? primary : textDark.withValues(alpha: 0.80);
    final textColor = active ? primary : textDark.withValues(alpha: 0.88);

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(22, 2, 10, 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? primary.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

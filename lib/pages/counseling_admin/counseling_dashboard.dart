import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../shared/handbook/handbook_sections_screen.dart';
import '../shared/notifications/app_notifications_ui.dart';
import '../shared/profile/unified_profile_page.dart';
import '../shared/welcome_screen_page.dart';
import '../shared/widgets/logout_confirm_dialog.dart';
import 'counseling_meeting_schedule_page.dart';
import 'archive/counseling_appointments_page.dart';
import 'archive/counseling_home_page.dart';

class CounselingDashboard extends StatefulWidget {
  const CounselingDashboard({super.key});

  @override
  State<CounselingDashboard> createState() => _CounselingDashboardState();
}

class _CounselingDashboardState extends State<CounselingDashboard> {
  int _currentIndex = 0;
  bool _settingsOpen = false;
  bool _showDesktopNotifications = false;

  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);
  static const surface = Color(0xFFFFFFFF);

  List<Widget> get _pages => const [
    CounselingHomePage(),
    HandbookSectionsScreen(),
    CounselingAppointmentsPage(),
    CounselingMeetingSchedulePage(),
    UnifiedProfilePage(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.menu_book_rounded, 'Handbook'),
    _NavItem(Icons.event_available_rounded, 'Appointments'),
  ];

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Student Handbook';
      case 2:
        return 'Appointments';
      case 3:
        return 'Meeting Schedule';
      case 4:
        return 'Profile';
      default:
        return 'Counseling Portal';
    }
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
    return 'Counseling Admin';
  }

  String _email(Map<String, dynamic> data, User user) {
    final e = (data['email'] ?? user.email ?? '').toString().trim();
    return e.isEmpty ? '--' : e;
  }

  String _title(Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString().toLowerCase().trim();
    switch (role) {
      case 'counseling_admin':
        return 'Counseling Administrator';
      default:
        return 'Counseling Portal';
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
            final isDesktop = constraints.maxWidth >= 900;
            final isPhoneOrTablet = !isDesktop;

            return Scaffold(
              backgroundColor: bg,
              drawer: isPhoneOrTablet
                  ? Drawer(
                      child: _CounselMenuPanel(
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
                        onToggleSettings: () =>
                            setState(() => _settingsOpen = !_settingsOpen),
                        onSelectSettingsItem: (pageIndex) {
                          Navigator.of(context).maybePop();
                          _goSettings(pageIndex);
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
                  if (isDesktop)
                    SizedBox(
                      width: 260,
                      child: Material(
                        color: surface,
                        child: _CounselMenuPanel(
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
                          accountTitle: accountTitle,
                          accountEmail: accountEmail,
                          accountName: accountName,
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
              bottomNavigationBar: isPhoneOrTablet
                  ? BottomNavigationBar(
                      currentIndex: _currentIndex < _navItems.length
                          ? _currentIndex
                          : 0,
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
            );
          },
        );
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

class _CounselMenuPanel extends StatelessWidget {
  final int currentIndex;
  final List<_NavItem> navItems;

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

  final String accountTitle;
  final String accountEmail;
  final String accountName;

  const _CounselMenuPanel({
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
    required this.accountTitle,
    required this.accountEmail,
    required this.accountName,
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 10, bottom: 16),
              child: Column(
                children: [
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
                                'Profile',
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
                              'Settings',
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
                    _CounselSubItem(
                      label: 'Meeting Schedule',
                      icon: Icons.calendar_month_rounded,
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
                            'Logout',
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

class _CounselSubItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color primary;
  final Color textDark;
  final VoidCallback onTap;

  const _CounselSubItem({
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

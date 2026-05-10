import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../shared/handbook/hb_handbook_page.dart';
import '../shared/notifications/app_notifications_ui.dart';
import '../shared/profile/unified_profile_page.dart';
import '../shared/welcome_screen_page.dart';
import '../shared/widgets/app_branding.dart';
import '../shared/widgets/app_theme_tokens.dart';
import '../shared/widgets/logout_confirm_dialog.dart';
import '../shared/widgets/responsive_layout_tokens.dart';
import '../shared/widgets/role_shell_scaffold.dart';
import '../professor/MySubmittedReportPage.dart';
import '../professor/professor_counseling_page.dart';
import '../professor/violation_report_page.dart';
import '../osa_admin/counseling_setup_page.dart';
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
  static const List<int> _mobileNavIndexes = <int>[0, 1, 2, 5, 6, 7];

  static const bg = AppColors.background;
  static const primary = AppColors.primary;
  static const hint = AppColors.hint;
  static const textDark = AppColors.textDark;
  static const surface = AppColors.surface;

  List<Widget> get _pages => [
    const CounselingHomePage(),
    const HbHandbookPage(hideTopHeader: true),
    const CounselingAppointmentsPage(),
    const ProfessorCounselingPage(),
    const ViolationReportPage(),
    MySubmittedCasesPage(
      onOpenViolationReport: _openViolationReportModal,
      onOpenCounselingReferral: _openCounselingReferralModal,
    ),
    const _CounselingRecordsPlaceholderPage(),
    const _CounselingAnalyticsPlaceholderPage(),
    const CounselingMeetingSchedulePage(),
    const CounselingSetupPage(),
    const UnifiedProfilePage(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.menu_book_rounded, 'Handbook'),
    _NavItem(Icons.event_available_rounded, 'Counseling Review'),
    _NavItem(Icons.support_agent_rounded, 'Counselling Referral'),
    _NavItem(Icons.report_rounded, 'Report Violation'),
    _NavItem(Icons.assignment_rounded, 'My Reports'),
    _NavItem(Icons.folder_open_rounded, 'Counselling Records'),
    _NavItem(Icons.insights_rounded, 'Counselling Analytics'),
  ];

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Student Handbook';
      case 2:
        return 'Counseling Review';
      case 3:
        return 'Counselling Referral';
      case 4:
        return 'Report Violation';
      case 5:
        return 'My Reports';
      case 6:
        return 'Counselling Records';
      case 7:
        return 'Counselling Analytics';
      case 8:
        return 'Meeting Schedule';
      case 9:
        return 'Counseling Setup';
      case 10:
        return 'Profile';
      default:
        return 'Counseling Portal';
    }
  }

  void _go(int i) {
    _goAsync(i);
  }

  Future<void> _goAsync(int i) async {
    if (i == 3) {
      await _openCounselingReferralModal();
      return;
    }
    if (i == 4) {
      await _openViolationReportModal();
      return;
    }
    if (!mounted) return;
    setState(() => _currentIndex = i);
  }

  Future<void> _openFormModal({
    required String title,
    required Widget child,
    String? subtitle,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final isFlatHeaderModal =
            title == 'Report Violation' || title == 'Counselling Referral';
        final size = MediaQuery.of(dialogContext).size;
        final isDesktop = size.width >= 900;
        final maxWidth = isDesktop ? 1180.0 : size.width - 20;
        final maxHeight = size.height * 0.92;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: maxWidth,
            height: maxHeight,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
                  decoration: BoxDecoration(
                    color: isFlatHeaderModal ? Colors.white : surface,
                    border: isFlatHeaderModal
                        ? null
                        : Border(
                            bottom: BorderSide(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: textDark,
                                fontSize: 16,
                              ),
                            ),
                            if ((subtitle ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!.trim(),
                                style: TextStyle(
                                  color: hint.withValues(alpha: 0.95),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.06),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCounselingReferralModal() async {
    await _openFormModal(
      title: 'Counselling Referral',
      child: const ProfessorCounselingPage(),
    );
  }

  Future<void> _openViolationReportModal() async {
    await _openFormModal(
      title: 'Report Violation',
      subtitle: 'Search a student, complete incident details, and submit.',
      child: ViolationReportPage(
        onOpenMyReportsInShell: () {
          Navigator.of(context, rootNavigator: true).pop();
          _go(5);
        },
      ),
    );
  }

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
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AppNotificationsPage(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
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
            final shell = ResponsiveLayoutTokens.resolveShellLayout(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              allowCompactDesktopDrawer: true,
            );

            final menuPanel = _CounselMenuPanel(
              currentIndex: _currentIndex,
              navItems: _navItems,
              primary: primary,
              hint: hint,
              textDark: textDark,
              surface: surface,
              onSelect: _go,
              onProfile: () => _go(10),
              settingsOpen: _settingsOpen,
              onToggleSettings: () =>
                  setState(() => _settingsOpen = !_settingsOpen),
              onSelectSettingsItem: _goSettings,
              onLogout: _logout,
              accountTitle: accountTitle,
              accountEmail: accountEmail,
              accountName: accountName,
            );

            return RoleShellScaffold(
              backgroundColor: bg,
              title: _pageTitle(),
              usesDrawerSidebar: shell.usesDrawerSidebar,
              showPermanentSidebar: shell.showPermanentSidebar,
              drawer: Drawer(
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
                    _go(10);
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
              ),
              sidebar: menuPanel,
              content: IndexedStack(index: _currentIndex, children: _pages),
              onNotificationsTap: () {
                if (shell.isDesktop) {
                  _toggleDesktopNotifications();
                } else {
                  _openNotificationsPage();
                }
              },
              notificationsUid: user.uid,
              suppressIncomingNotificationToasts: _showDesktopNotifications,
              hideNotificationsBadge: _showDesktopNotifications,
              enableNotificationSound: false,
              showDesktopOverlay: shell.isDesktop && _showDesktopNotifications,
              onDismissDesktopOverlay: _closeDesktopNotifications,
              desktopOverlay: DesktopNotificationsPanel(
                uid: user.uid,
                onClose: _closeDesktopNotifications,
                onSeeAll: _openNotificationsPage,
              ),
              bottomNavigationBar: shell.isDesktop
                  ? null
                  : BottomNavigationBar(
                      currentIndex: _mobileNavIndexes.contains(_currentIndex)
                          ? _mobileNavIndexes.indexOf(_currentIndex)
                          : 0,
                      type: BottomNavigationBarType.fixed,
                      selectedItemColor: primary,
                      unselectedItemColor: hint,
                      backgroundColor: surface,
                      onTap: (index) => _go(_mobileNavIndexes[index]),
                      items: _mobileNavIndexes
                          .map(
                            (itemIndex) => BottomNavigationBarItem(
                              icon: Icon(_navItems[itemIndex].icon),
                              label: _navItems[itemIndex].label,
                            ),
                          )
                          .toList(),
                    ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBranding.logo(width: 28, height: 28),
                  const SizedBox(width: 8),
                  Text(
                    'BUDiscipLink',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onProfile,
                child: Ink(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.80),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              accountName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              accountEmail,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.90),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              accountTitle,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.92),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                    if (item.label == 'Report Violation' ||
                        item.label == 'Counselling Referral') {
                      return const SizedBox.shrink();
                    }
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
                      active: currentIndex == 8,
                      primary: primary,
                      textDark: textDark,
                      onTap: () => onSelectSettingsItem(8),
                    ),
                    _CounselSubItem(
                      label: 'Counseling Setup',
                      icon: Icons.support_agent_rounded,
                      active: currentIndex == 9,
                      primary: primary,
                      textDark: textDark,
                      onTap: () => onSelectSettingsItem(9),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
          Divider(color: primary.withValues(alpha: 0.15), height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
            child: InkWell(
              onTap: onLogout,
              child: Container(
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

class _CounselingRecordsPlaceholderPage extends StatelessWidget {
  const _CounselingRecordsPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return const _CounselingPlaceholderScaffold(
      icon: Icons.folder_open_rounded,
      title: 'Counselling Records',
      subtitle: 'This module is not yet implemented.',
    );
  }
}

class _CounselingAnalyticsPlaceholderPage extends StatelessWidget {
  const _CounselingAnalyticsPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return const _CounselingPlaceholderScaffold(
      icon: Icons.insights_rounded,
      title: 'Counselling Analytics',
      subtitle: 'This module is not yet implemented.',
    );
  }
}

class _CounselingPlaceholderScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _CounselingPlaceholderScaffold({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.primary),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.hint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

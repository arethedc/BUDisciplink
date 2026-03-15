import 'package:apps/pages/shared/handbook/hb_handbook_page.dart';
import 'package:apps/pages/shared/notifications/app_notifications_ui.dart';
import 'package:apps/pages/shared/profile/unified_profile_page.dart';
import 'package:apps/pages/shared/welcome_screen_page.dart';
import 'package:apps/pages/shared/widgets/app_theme_tokens.dart';
import 'package:apps/pages/shared/widgets/app_branding.dart';
import 'package:apps/pages/shared/widgets/logout_confirm_dialog.dart';
import 'package:apps/pages/shared/widgets/responsive_layout_tokens.dart';
import 'package:apps/pages/shared/widgets/role_shell_scaffold.dart';
import 'package:apps/pages/shared/widgets/unsaved_changes_guard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../osa_admin/user_management_page.dart';
import '../professor/MySubmittedReportPage.dart';
import '../professor/professor_counseling_page.dart';
import '../professor/violation_report_page.dart';
import 'department_admin_home_page.dart';
import 'department_violation_alerts_page.dart';
import 'professor_management_page.dart';

class DepartmentAdminDashboard extends StatefulWidget {
  const DepartmentAdminDashboard({super.key});

  @override
  State<DepartmentAdminDashboard> createState() =>
      _DepartmentAdminDashboardState();
}

class _DepartmentAdminDashboardState extends State<DepartmentAdminDashboard> {
  int _currentIndex = 0;
  int _previousIndexBeforeNotifications = 0;
  bool _settingsOpen = false;
  bool _showDesktopNotifications = false;
  String? _preselectedStudentUid;
  String? _preselectedViolationCaseId;
  static const int _notificationsIndex = 9;
  final _violationUnsaved = UnsavedChangesController();
  final _counselingUnsaved = UnsavedChangesController();

  static const bg = Colors.white;
  static const primary = AppColors.primary;
  static const hint = AppColors.hint;
  static const textDark = AppColors.textDark;
  static const surface = AppColors.surface;

  List<Widget> get _pages => [
    DepartmentAdminHomePage(
      onOpenUserManagement: () => _openStudentManagement(),
      onOpenPendingApprovalProfile: (uid) =>
          _openStudentManagement(preselectUserId: uid),
      onOpenViolationReview: () => _openViolationAlerts(),
      onOpenViolationAlertCase: (caseId) =>
          _openViolationAlerts(preselectCaseId: caseId),
    ),
    const HbHandbookPage(),
    DepartmentViolationAlertsPage(
      initialSelectedCaseId: _preselectedViolationCaseId,
    ),
    ViolationReportPage(
      onOpenMyReportsInShell: () => _go(5),
      unsavedChangesController: _violationUnsaved,
    ),
    ProfessorCounselingPage(unsavedChangesController: _counselingUnsaved),
    const MySubmittedCasesPage(),
    UserManagementPage(
      studentsOnlyScope: true,
      headerTitle: 'Student Management',
      headerSubtitle: 'Manage student accounts under your department',
      initialSelectedUserId: _preselectedStudentUid,
      pageBackgroundColor: Colors.white,
    ),
    const ProfessorManagementPage(),
    const UnifiedProfilePage(),
    AppNotificationsContent(
      onBack: () {
        final backIndex =
            _previousIndexBeforeNotifications == _notificationsIndex
            ? 0
            : _previousIndexBeforeNotifications;
        _go(backIndex);
      },
      onViewNotification: _handleNotificationView,
    ),
  ];

  final List<_DeptNavItem> _navItems = const [
    _DeptNavItem(Icons.dashboard_rounded, 'Dashboard'),
    _DeptNavItem(Icons.menu_book_rounded, 'Handbook'),
    _DeptNavItem(Icons.rule_rounded, 'Violation Alerts'),
    _DeptNavItem(Icons.report_rounded, 'Report Violation'),
    _DeptNavItem(Icons.support_agent_rounded, 'Counselling Referral'),
    _DeptNavItem(Icons.assignment_rounded, 'My Reports'),
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
        return 'Report Violation';
      case 4:
        return 'Counselling Referral';
      case 5:
        return 'My Reports';
      case 6:
        return 'Student Management';
      case 7:
        return 'Professor Management';
      case 8:
        return 'Profile';
      case _notificationsIndex:
        return 'Notifications';
      default:
        return 'Department Admin Portal';
    }
  }

  Future<void> _logout() async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
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

  UnsavedChangesController? _controllerForIndex(int index) {
    switch (index) {
      case 3:
        return _violationUnsaved;
      case 4:
        return _counselingUnsaved;
      default:
        return null;
    }
  }

  Future<bool> _confirmLeaveCurrentPage() async {
    final controller = _controllerForIndex(_currentIndex);
    if (controller == null || !controller.isDirty) return true;

    final leave = await showUnsavedChangesDialog(
      context,
      title: 'Leave current form?',
      message:
          'You have unsaved changes on this form. If you continue, your draft will be discarded.',
    );
    if (leave) {
      controller.discardChanges();
    }
    return leave;
  }

  void _go(int i) {
    _goAsync(i);
  }

  Future<void> _goAsync(int i) async {
    if (i == _currentIndex) return;
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    setState(() {
      _currentIndex = i;
      if (i != 6) _preselectedStudentUid = null;
      if (i != 2) _preselectedViolationCaseId = null;
      if (i != _notificationsIndex) {
        _previousIndexBeforeNotifications = i;
      }
    });
  }

  void _goSettings(int pageIndex) {
    _goSettingsAsync(pageIndex);
  }

  Future<void> _goSettingsAsync(int pageIndex) async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    setState(() {
      _settingsOpen = true;
      _currentIndex = pageIndex;
      if (pageIndex != 6) _preselectedStudentUid = null;
      if (pageIndex != 2) _preselectedViolationCaseId = null;
    });
  }

  void _openStudentManagement({String? preselectUserId}) {
    _openStudentManagementAsync(preselectUserId: preselectUserId);
  }

  Future<void> _openStudentManagementAsync({String? preselectUserId}) async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    setState(() {
      _settingsOpen = true;
      _currentIndex = 6;
      final uid = (preselectUserId ?? '').trim();
      _preselectedStudentUid = uid.isEmpty ? null : uid;
      _preselectedViolationCaseId = null;
    });
  }

  void _openViolationAlerts({String? preselectCaseId}) {
    _openViolationAlertsAsync(preselectCaseId: preselectCaseId);
  }

  Future<void> _openViolationAlertsAsync({String? preselectCaseId}) async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    setState(() {
      _currentIndex = 2;
      final caseId = (preselectCaseId ?? '').trim();
      _preselectedViolationCaseId = caseId.isEmpty ? null : caseId;
      _preselectedStudentUid = null;
      _settingsOpen = false;
    });
  }

  Future<void> _handleNotificationView(AppNotificationViewIntent intent) async {
    switch (intent.target) {
      case AppNotificationViewTarget.pendingApproval:
        final uid = (intent.studentUid ?? '').trim();
        await _openStudentManagementAsync(
          preselectUserId: uid.isEmpty ? null : uid,
        );
        break;
      case AppNotificationViewTarget.violationAlert:
        await _openViolationAlertsAsync(preselectCaseId: intent.caseId);
        break;
    }
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
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    setState(() {
      if (_currentIndex != _notificationsIndex) {
        _previousIndexBeforeNotifications = _currentIndex;
      }
      _showDesktopNotifications = false;
      _currentIndex = _notificationsIndex;
    });
  }

  @override
  void dispose() {
    _violationUnsaved.dispose();
    _counselingUnsaved.dispose();
    super.dispose();
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
            final shell = ResponsiveLayoutTokens.resolveShellLayout(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            );

            final menuPanel = _DeptMenuPanel(
              currentIndex: _currentIndex,
              navItems: _navItems,
              primary: primary,
              hint: hint,
              textDark: textDark,
              surface: surface,
              onSelect: _go,
              onProfile: () => _go(8),
              settingsOpen: _settingsOpen,
              onToggleSettings: () =>
                  setState(() => _settingsOpen = !_settingsOpen),
              onSelectSettingsItem: _goSettings,
              onLogout: _logout,
              accountName: accountName,
              accountEmail: accountEmail,
              accountSubtitle: accountSubtitle,
            );

            return RoleShellScaffold(
              backgroundColor: bg,
              title: _pageTitle(),
              usesDrawerSidebar: shell.usesDrawerSidebar,
              showPermanentSidebar: shell.showPermanentSidebar,
              drawer: Drawer(
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
                    _go(8);
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
              sidebar: menuPanel,
              content: IndexedStack(
                index: _currentIndex,
                children: List<Widget>.generate(_pages.length, (index) {
                  return HeroMode(
                    enabled: index == _currentIndex,
                    child: _pages[index],
                  );
                }),
              ),
              onNotificationsTap: () {
                if (shell.isDesktop) {
                  _toggleDesktopNotifications();
                } else {
                  _openNotificationsPage();
                }
              },
              showDesktopOverlay: shell.isDesktop && _showDesktopNotifications,
              onDismissDesktopOverlay: _closeDesktopNotifications,
              desktopOverlay: DesktopNotificationsPanel(
                uid: user.uid,
                onClose: _closeDesktopNotifications,
                onSeeAll: _openNotificationsPage,
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
                    color: primary.withValues(
                      alpha: currentIndex == 8 ? 0.86 : 0.80,
                    ),
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
                              accountSubtitle,
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
                      active: currentIndex == 6,
                      primary: primary,
                      textDark: textDark,
                      onTap: () => onSelectSettingsItem(6),
                    ),
                    const SizedBox(height: 6),
                    _DeptSubItem(
                      label: 'Professor Management',
                      icon: Icons.school_rounded,
                      active: currentIndex == 7,
                      primary: primary,
                      textDark: textDark,
                      onTap: () => onSelectSettingsItem(7),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: primary.withValues(alpha: 0.15)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: InkWell(
              onTap: onLogout,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
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

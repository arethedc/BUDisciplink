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
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'osa_home_page.dart';

// ✅ SETTINGS SUB-PAGES (adjust paths to your project)
import 'academic/academic_years_page.dart';
import 'handbook_workflow_page.dart';
import 'handbook_docs_editor_page.dart';
import 'meeting_schedule_page.dart';
import '../professor/professor_counseling_page.dart';
import '../professor/violation_report_page.dart';
import 'student_management_page.dart';
import 'user_management_page.dart';
import 'violation_analytics_page.dart';
import 'violation_records_page.dart';
import 'violation_types_page.dart';
import 'osa_violation_review_page.dart';

class OsaDashboard extends StatefulWidget {
  const OsaDashboard({super.key});

  @override
  State<OsaDashboard> createState() => _OsaDashboardState();
}

class _OsaDashboardState extends State<OsaDashboard> {
  int _currentIndex = 0;
  int _previousIndexBeforeNotifications = 0;
  bool _showDesktopNotifications = false;
  ViolationRecordsFilterPreset? _recordsPreset;
  int _recordsPresetVersion = 0;
  int _handbookEditorReloadToken = 0;
  String? _preselectedStudentUid;
  String? _preselectedViolationCaseId;
  static const int _notificationsIndex = 15;
  final _violationUnsaved = UnsavedChangesController();
  final _counselingUnsaved = UnsavedChangesController();

  // ✅ Settings section open/close
  bool _settingsOpen = false;
  bool _handbookOpen = true;

  // ================== THEME (match reference dashboard) ==================
  static const bg = AppColors.background;
  static const primary = AppColors.primary;
  static const hint = AppColors.hint;
  static const textDark = AppColors.textDark;
  static const surface = AppColors.surface;

  // ================== PAGES ==================
  // Keep as a getter so hot reload reflects changes (initState doesn't rerun).
  List<Widget> get _pages => [
    OsaHomePage(onOpenAcademicSettings: () => _goSettings(3)),
    const HbHandbookPage(useSidebarDesktop: false),
    ViolationRecordsPage(
      key: ValueKey('violation-records-$_recordsPresetVersion'),
      initialFilterPreset: _recordsPreset,
      initialSelectedCaseId: _preselectedViolationCaseId,
    ),

    // ✅ Settings sub-pages
    const AcademicYearsPage(),
    const UserManagementPage(),
    StudentManagementPage(initialSelectedUserId: _preselectedStudentUid),
    const ViolationTypesPage(),
    const MeetingSchedulePage(),
    HandbookWorkflowPage(
      onOpenEditorForVersion: (_) {
        setState(() {
          _handbookEditorReloadToken++;
          _currentIndex = 12;
          _handbookOpen = true;
        });
      },
    ),
    const UnifiedProfilePage(),
    ViolationAnalyticsPage(
      onOpenRecords: (preset) {
        setState(() {
          _recordsPreset = preset;
          _recordsPresetVersion++;
          _currentIndex = 2;
        });
      },
    ),
    const OsaViolationReviewPage(),
    HandbookDocsEditorPage(
      key: ValueKey('hb-editor-$_handbookEditorReloadToken'),
      onBack: () {
        setState(() {
          _currentIndex = 8;
          _handbookOpen = true;
        });
      },
    ),
    ViolationReportPage(unsavedChangesController: _violationUnsaved),
    ProfessorCounselingPage(unsavedChangesController: _counselingUnsaved),
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

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return "Dashboard";
      case 1:
        return "Student Handbook";
      case 2:
        return "Violation Records";
      case 3:
        return "Academic Settings";

      // ✅ Settings pages
      case 4:
        return "User Management";
      case 5:
        return "Student Management";
      case 6:
        return "Violation Settings";
      case 7:
        return "Meeting Schedule";
      case 8:
        return "Manage Handbook";
      case 9:
        return "Profile";
      case 10:
        return "Violation Analytics";
      case 11:
        return "Violation Review";
      case 12:
        return "Manage Handbook";
      case 13:
        return "Report Violation";
      case 14:
        return "Counselling Referral";
      case _notificationsIndex:
        return "Notifications";

      default:
        return "OSA Portal";
    }
  }

  UnsavedChangesController? _controllerForIndex(int index) {
    switch (index) {
      case 13:
        return _violationUnsaved;
      case 14:
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

  void _go(int i) {
    _goAsync(i);
  }

  Future<void> _goAsync(int i) async {
    if (i == _currentIndex) return;
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    setState(() {
      _currentIndex = i;
      if (i != _notificationsIndex) {
        _previousIndexBeforeNotifications = i;
      }
      if (i != 5) _preselectedStudentUid = null;
      if (i != 2) _preselectedViolationCaseId = null;
      if (i == 1 || i == 8 || i == 12) {
        _handbookOpen = true;
      }
      if (i >= 3 && i <= 7) _settingsOpen = true;
    });
  }

  void _goSettings(int pageIndex) {
    _goSettingsAsync(pageIndex);
  }

  Future<void> _goSettingsAsync(int pageIndex) async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    setState(() {
      _settingsOpen = true; // keep open when selecting sub-item
      _currentIndex = pageIndex;
      if (pageIndex != 5) _preselectedStudentUid = null;
      if (pageIndex != 2) _preselectedViolationCaseId = null;
    });
  }

  Future<void> _openStudentManagementAsync({String? preselectUserId}) async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    setState(() {
      _settingsOpen = true;
      _currentIndex = 5;
      final uid = (preselectUserId ?? '').trim();
      _preselectedStudentUid = uid.isEmpty ? null : uid;
      _preselectedViolationCaseId = null;
    });
  }

  Future<void> _openViolationRecordsAsync({String? preselectCaseId}) async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    setState(() {
      _currentIndex = 2;
      _recordsPreset = const ViolationRecordsFilterPreset(clearExisting: true);
      _recordsPresetVersion++;
      final caseId = (preselectCaseId ?? '').trim();
      _preselectedViolationCaseId = caseId.isEmpty ? null : caseId;
      _preselectedStudentUid = null;
    });
  }

  Future<void> _handleNotificationView(AppNotificationViewIntent intent) async {
    switch (intent.target) {
      case AppNotificationViewTarget.pendingApproval:
        await _openStudentManagementAsync(preselectUserId: intent.studentUid);
        break;
      case AppNotificationViewTarget.violationAlert:
        await _openViolationRecordsAsync(preselectCaseId: intent.caseId);
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

  String _displayName(Map<String, dynamic> data, User user) {
    final dn = (data['displayName'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final full = ('$first $last').trim();
    if (full.isNotEmpty) return full;
    final email = (data['email'] ?? user.email ?? '').toString().trim();
    if (email.contains('@')) return email.split('@').first;
    return 'OSA Admin';
  }

  String _email(Map<String, dynamic> data, User user) {
    final e = (data['email'] ?? user.email ?? '').toString().trim();
    return e.isEmpty ? '--' : e;
  }

  String _title(Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString().toLowerCase().trim();
    switch (role) {
      case 'osa_admin':
        return 'OSA Administrator';
      default:
        return 'OSA Portal';
    }
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
        final accountTitle = _title(data);

        return LayoutBuilder(
          builder: (context, constraints) {
            final shell = ResponsiveLayoutTokens.resolveShellLayout(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              allowCompactDesktopDrawer: true,
            );

            final menuPanel = _MenuPanel(
              currentIndex: _currentIndex,
              primary: primary,
              hint: hint,
              textDark: textDark,
              surface: surface,
              onSelect: _go,
              onProfile: () => _go(9),
              settingsOpen: _settingsOpen,
              onToggleSettings: () =>
                  setState(() => _settingsOpen = !_settingsOpen),
              onSelectSettingsItem: (pageIndex) => _goSettings(pageIndex),
              handbookOpen: _handbookOpen,
              onToggleHandbook: () =>
                  setState(() => _handbookOpen = !_handbookOpen),
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
                child: _MenuPanel(
                  currentIndex: _currentIndex,
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
                    _go(9);
                  },
                  settingsOpen: _settingsOpen,
                  onToggleSettings: () =>
                      setState(() => _settingsOpen = !_settingsOpen),
                  onSelectSettingsItem: (pageIndex) {
                    Navigator.of(context).maybePop();
                    _goSettings(pageIndex);
                  },
                  handbookOpen: _handbookOpen,
                  onToggleHandbook: () =>
                      setState(() => _handbookOpen = !_handbookOpen),
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

// ================= SIDEBAR =================

class _MenuPanel extends StatelessWidget {
  final int currentIndex;

  final Color primary;
  final Color hint;
  final Color textDark;
  final Color surface;

  final ValueChanged<int> onSelect;
  final VoidCallback onProfile;

  final bool settingsOpen;
  final VoidCallback onToggleSettings;
  final ValueChanged<int> onSelectSettingsItem;

  final bool handbookOpen;
  final VoidCallback onToggleHandbook;

  final VoidCallback onLogout;

  final String accountTitle;
  final String accountEmail;
  final String accountName;

  const _MenuPanel({
    required this.currentIndex,
    required this.primary,
    required this.hint,
    required this.textDark,
    required this.surface,
    required this.onSelect,
    required this.onProfile,
    required this.settingsOpen,
    required this.onToggleSettings,
    required this.onSelectSettingsItem,
    required this.handbookOpen,
    required this.onToggleHandbook,
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
                    color: primary.withValues(
                      alpha: currentIndex == 9 ? 0.86 : 0.80,
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
                  _MenuItem(
                    icon: Icons.dashboard_rounded,
                    label: 'Dashboard',
                    active: currentIndex == 0,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(0),
                  ),
                  _ExpandableMenuItem(
                    icon: Icons.menu_book_rounded,
                    label: 'Handbook',
                    expanded: handbookOpen,
                    active:
                        currentIndex == 1 ||
                        currentIndex == 8 ||
                        currentIndex == 12,
                    primary: primary,
                    textDark: textDark,
                    hint: hint,
                    onTap: onToggleHandbook,
                  ),
                  if (handbookOpen) ...[
                    _SubItem(
                      label: 'Handbook Section View',
                      icon: Icons.menu_book_outlined,
                      active: currentIndex == 1,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelect(1),
                    ),
                    _SubItem(
                      label: 'Manage Handbook',
                      icon: Icons.published_with_changes_rounded,
                      active: currentIndex == 8,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelect(8),
                    ),
                    const SizedBox(height: 6),
                  ],
                  _MenuItem(
                    icon: Icons.rule_rounded,
                    label: 'Violation Review',
                    active: currentIndex == 11,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(11),
                  ),
                  _MenuItem(
                    icon: Icons.assignment_rounded,
                    label: 'Violation Records',
                    active: currentIndex == 2,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(2),
                  ),
                  _MenuItem(
                    icon: Icons.analytics_rounded,
                    label: 'Violation Analytics',
                    active: currentIndex == 10,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(10),
                  ),
                  _MenuItem(
                    icon: Icons.report_rounded,
                    label: 'Report Violation',
                    active: currentIndex == 13,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(13),
                  ),
                  _MenuItem(
                    icon: Icons.support_agent_rounded,
                    label: 'Counselling Referral',
                    active: currentIndex == 14,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(14),
                  ),
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
                    _SubItem(
                      label: 'Academic Settings',
                      icon: Icons.school_rounded,
                      active: currentIndex == 3,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(3),
                    ),
                    _SubItem(
                      label: 'User Management',
                      icon: Icons.people_alt_rounded,
                      active: currentIndex == 4,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(4),
                    ),
                    _SubItem(
                      label: 'Student Management',
                      icon: Icons.school_outlined,
                      active: currentIndex == 5,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(5),
                    ),
                    _SubItem(
                      label: 'Violation Settings',
                      icon: Icons.fact_check_rounded,
                      active: currentIndex == 6,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(6),
                    ),
                    _SubItem(
                      label: 'Meeting Schedule',
                      icon: Icons.calendar_month_rounded,
                      active: currentIndex == 7,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
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

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color primary;
  final Color textDark;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.primary,
    required this.textDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? primary : textDark.withValues(alpha: 0.85);
    final textColor = active ? primary : textDark.withValues(alpha: 0.92);

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? primary.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool expanded;
  final bool active;
  final Color primary;
  final Color textDark;
  final Color hint;
  final VoidCallback onTap;

  const _ExpandableMenuItem({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.active,
    required this.primary,
    required this.textDark,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? primary : textDark.withValues(alpha: 0.85);
    final textColor = active ? primary : textDark.withValues(alpha: 0.92);

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: expanded || active
              ? primary.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w900),
              ),
            ),
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: hint,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color primary;
  final Color textDark;
  final Color hint;
  final VoidCallback onTap;

  const _SubItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.primary,
    required this.textDark,
    required this.hint,
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

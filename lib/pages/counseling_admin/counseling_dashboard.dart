import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/handbook/hb_handbook_page.dart';
import '../shared/notifications/app_notifications_ui.dart';
import '../shared/profile/unified_profile_page.dart';
import '../shared/widgets/app_branding.dart';
import '../shared/widgets/app_theme_tokens.dart';
import '../shared/widgets/logout_confirm_dialog.dart';
import '../shared/widgets/responsive_layout_tokens.dart';
import '../shared/widgets/role_shell_scaffold.dart';
import 'package:apps/services/app_router.dart';
import '../professor/MySubmittedReportPage.dart';
import '../professor/professor_counseling_page.dart';
import '../professor/violation_report_page.dart';
import '../osa_admin/counseling_setup_page.dart';
import 'counseling_analytics_page.dart';
import 'counseling_meeting_schedule_page.dart';
import 'counseling_appointments_page.dart';
import 'counseling_home_page.dart';
import 'package:apps/services/app_firestore.dart';
import 'package:apps/services/counseling_setup_status_service.dart';

class CounselingDashboard extends StatefulWidget {
  final String section;
  final String? tabDeepLink;
  final String? handbookSectionId;
  final String? handbookHighlightText;

  const CounselingDashboard({
    super.key,
    this.section = 'dashboard',
    this.tabDeepLink,
    this.handbookSectionId,
    this.handbookHighlightText,
  });

  static const _sectionToIndex = <String, int>{
    'dashboard': 0,
    'handbook': 1,
    'review': 2,
    'referral': 3,
    'report': 4,
    'my-reports': 5,
    'records': 6,
    'analytics': 7,
    'meeting-schedule': 8,
    'setup': 9,
    'profile': 10,
    'notifications': 11,
  };

  static const _indexToSection = <int, String>{
    0: 'dashboard',
    1: 'handbook',
    2: 'review',
    3: 'referral',
    4: 'report',
    5: 'my-reports',
    6: 'records',
    7: 'analytics',
    8: 'meeting-schedule',
    9: 'setup',
    10: 'profile',
    11: 'notifications',
  };

  static int indexForSection(String section) => _sectionToIndex[section] ?? 0;

  static String sectionForIndex(int index) =>
      _indexToSection[index] ?? 'dashboard';

  static String pathForSection(String section, {Map<String, String>? query}) {
    final base = AppRoutes.withSection(AppRoutes.counselingAdmin, section);
    if (query == null || query.isEmpty) return base;
    return Uri(path: base, queryParameters: query).toString();
  }

  @override
  State<CounselingDashboard> createState() => _CounselingDashboardState();
}

class _CounselingDashboardState extends State<CounselingDashboard> {
  static final Map<String, String> _sessionTabBySection = <String, String>{};
  late int _currentIndex;
  bool _settingsOpen = false;
  bool _showDesktopNotifications = false;
  bool _counselingSetupChecked = false;
  bool _counselingMeetingScheduleModalShown = false;
  static const List<int> _mobileNavIndexes = <int>[0, 1, 2, 5, 6, 7];
  static const int _notificationsIndex = 11;

  static const bg = AppColors.background;
  static const primary = AppColors.primary;
  static const hint = AppColors.hint;
  static const textDark = AppColors.textDark;
  static const surface = AppColors.surface;

  @override
  void initState() {
    super.initState();
    _currentIndex = CounselingDashboard.indexForSection(widget.section);
    final incomingTab = (widget.tabDeepLink ?? '').trim();
    final incomingSection = widget.section.trim();
    if (incomingTab.isNotEmpty &&
        (incomingSection == 'review' ||
            incomingSection == 'my-reports' ||
            incomingSection == 'records')) {
      _sessionTabBySection[incomingSection] = incomingTab;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSectionTabQuery();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowCounselingSetupModal();
    });
  }

  @override
  void didUpdateWidget(covariant CounselingDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = CounselingDashboard.indexForSection(widget.section);
    if (_currentIndex != nextIndex) {
      setState(() => _currentIndex = nextIndex);
    }
    final incomingTab = (widget.tabDeepLink ?? '').trim();
    final incomingSection = widget.section.trim();
    if (incomingTab.isNotEmpty &&
        (incomingSection == 'review' ||
            incomingSection == 'my-reports' ||
            incomingSection == 'records')) {
      _sessionTabBySection[incomingSection] = incomingTab;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSectionTabQuery();
    });
  }

  List<Widget> get _pages => [
    const CounselingHomePage(),
    HbHandbookPage(
      hideTopHeader: true,
      initialSectionId: widget.handbookSectionId,
      initialHighlightText: widget.handbookHighlightText,
      openSelectedOnMobile: true,
    ),
    CounselingAppointmentsPage(
      initialTab: _effectiveTabForSection('review'),
      onTabChanged: (tabKey) => _syncSectionTab('review', tabKey),
    ),
    const ProfessorCounselingPage(),
    const ViolationReportPage(),
    MySubmittedCasesPage(
      onOpenViolationReport: () => _go(4),
      onOpenCounselingReferral: () => _go(3),
      initialTab: _effectiveTabForSection('my-reports'),
      onTabChanged: (tabKey) => _syncSectionTab('my-reports', tabKey),
    ),
    CounselingRecordsPage(
      initialTab: _effectiveTabForSection('records'),
      onTabChanged: (tabKey) => _syncSectionTab('records', tabKey),
    ),
    const CounselingAnalyticsPage(),
    const CounselingMeetingSchedulePage(),
    const CounselingSetupPage(),
    const UnifiedProfilePage(),
    AppNotificationsContent(onBack: () => _go(0)),
  ];

  String? _effectiveTabForSection(String section) {
    if (widget.section == section) {
      final explicit = (widget.tabDeepLink ?? '').trim();
      if (explicit.isNotEmpty) return explicit;
    }
    final remembered = (_sessionTabBySection[section] ?? '').trim();
    return remembered.isEmpty ? null : remembered;
  }

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
      case _notificationsIndex:
        return 'Notifications';
      default:
        return 'Counseling Portal';
    }
  }

  void _go(int i) {
    _goAsync(i);
  }

  Future<void> _goAsync(int i) async {
    final section = CounselingDashboard.sectionForIndex(i);
    final tab = _defaultTabForSection(section);
    final target = CounselingDashboard.pathForSection(
      section,
      query: tab == null ? null : <String, String>{'tab': tab},
    );
    if (GoRouterState.of(context).uri.toString() == target) return;
    context.go(target);
  }

  String? _defaultTabForSection(String section) {
    final remembered = (_sessionTabBySection[section] ?? '').trim();
    if (remembered.isNotEmpty) return remembered;
    switch (section) {
      case 'review':
      case 'records':
        return 'all';
      case 'my-reports':
        return 'violation';
      default:
        return null;
    }
  }

  void _ensureSectionTabQuery() {
    if (!mounted) return;
    final section = CounselingDashboard.sectionForIndex(_currentIndex);
    final defaultTab = _defaultTabForSection(section);
    if (defaultTab == null) return;
    final currentUri = GoRouterState.of(context).uri;
    final currentTab = (currentUri.queryParameters['tab'] ?? '').trim();
    if (currentTab.isNotEmpty) return;
    final target = CounselingDashboard.pathForSection(
      section,
      query: <String, String>{'tab': defaultTab},
    );
    if (target == currentUri.toString()) return;
    context.replace(target);
  }

  void _syncSectionTab(String section, String tabKey) {
    final currentSection = CounselingDashboard.sectionForIndex(_currentIndex);
    if (currentSection != section) return;
    _sessionTabBySection[section] = tabKey;
    final currentUri = GoRouterState.of(context).uri;
    final currentTab = (currentUri.queryParameters['tab'] ?? '').trim();
    if (currentTab == tabKey) return;
    final target = CounselingDashboard.pathForSection(
      section,
      query: <String, String>{'tab': tabKey},
    );
    if (target == currentUri.toString()) return;
    context.go(target);
  }

  Future<CounselingSetupStatus?> _loadCounselingSetupStatus() async {
    try {
      return await CounselingSetupStatusService().load();
    } catch (error) {
      debugPrint('Failed to load counseling setup status: $error');
      return null;
    }
  }

  String _meetingScheduleReminderKey(String userId) {
    return 'counseling_meeting_schedule_seen_term_$userId';
  }

  Future<String?> _loadLastSeenMeetingScheduleKey(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_meetingScheduleReminderKey(userId));
  }

  Future<void> _markMeetingScheduleSeen({
    required String userId,
    required CounselingSetupStatus status,
  }) async {
    final schoolYearId = status.activeSchoolYearId.trim();
    final termId = status.activeTermId.trim();
    if (schoolYearId.isEmpty || termId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _meetingScheduleReminderKey(userId),
      '$schoolYearId::$termId',
    );
  }

  Future<void> _maybeShowCounselingSetupModal() async {
    if (_counselingSetupChecked || !mounted || _currentIndex != 0) return;
    _counselingSetupChecked = true;

    final status = await _loadCounselingSetupStatus();
    if (!mounted || status == null || _currentIndex != 0) return;

    if (!status.hasCounselingSetup) {
      await _showCounselingSetupModal(status);
    }

    if (!mounted || _currentIndex != 0) return;
    await _maybeShowMeetingScheduleModalIfNeeded(status: status);
  }

  Future<void> _maybeShowMeetingScheduleModalIfNeeded({
    CounselingSetupStatus? status,
  }) async {
    if (_counselingMeetingScheduleModalShown ||
        !mounted ||
        _currentIndex != 0) {
      return;
    }

    final resolvedStatus = status ?? await _loadCounselingSetupStatus();
    if (!mounted || resolvedStatus == null || _currentIndex != 0) return;
    if (resolvedStatus.hasMeetingScheduleSetup) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final currentKey =
        '${resolvedStatus.activeSchoolYearId}::${resolvedStatus.activeTermId}';
    final lastSeenKey = await _loadLastSeenMeetingScheduleKey(user.uid);
    if (lastSeenKey == currentKey) return;

    _counselingMeetingScheduleModalShown = true;
    await _showMeetingScheduleModal(resolvedStatus);
    await _markMeetingScheduleSeen(userId: user.uid, status: resolvedStatus);
  }

  Future<void> _showCounselingSetupModal(CounselingSetupStatus status) async {
    await _showSetupDialog(
      title: 'Counseling setup required',
      subtitle:
          'Complete the minimum setup below before referrals can be submitted.',
      icon: Icons.checklist_rtl_rounded,
      sections: [
        _buildSetupSection(
          title: 'Minimum setup',
          subtitle:
              'This is the minimum counseling setup required for referrals.',
          children: [
            _buildSetupChecklistRow(
              label: 'Counseling group',
              ready: status.hasCounselingGroups,
              missingHint: 'Add at least one active counseling group.',
            ),
            const SizedBox(height: 8),
            _buildSetupChecklistRow(
              label: 'Counseling item',
              ready: status.hasCounselingItems,
              missingHint:
                  'Add at least one active counseling item inside a group.',
            ),
          ],
        ),
      ],
      primaryLabel: 'Open Counseling Setup',
      primaryIcon: Icons.open_in_new_rounded,
      onPrimaryPressed: () => _go(9),
    );
  }

  Future<void> _showMeetingScheduleModal(CounselingSetupStatus status) async {
    await _showSetupDialog(
      title: 'Meeting schedule required',
      subtitle:
          'The active semester changed. Confirm the schedule template before students reserve slots.',
      icon: Icons.calendar_month_rounded,
      sections: [
        _buildSetupSection(
          title: 'Meeting schedule',
          subtitle:
              'Use the current semester to keep booking slots aligned with the active term.',
          children: [
            _buildSetupChecklistRow(
              label: 'Active semester',
              ready: status.hasActiveTerm,
              missingHint:
                  'Set an active semester before generating meeting slots.',
            ),
            const SizedBox(height: 8),
            _buildSetupChecklistRow(
              label: 'Meeting schedule template',
              ready:
                  status.hasMeetingScheduleTemplate ||
                  status.hasMeetingScheduleSlots,
              missingHint:
                  'Create the meeting schedule template for the active term.',
            ),
          ],
        ),
      ],
      primaryLabel: 'Open Meeting Schedule',
      primaryIcon: Icons.open_in_new_rounded,
      onPrimaryPressed: () => _go(8),
    );
  }

  Future<void> _showSetupDialog({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> sections,
    required String primaryLabel,
    required IconData primaryIcon,
    required VoidCallback onPrimaryPressed,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: primary.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Icon(icon, color: primary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: primary,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: hint,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ...sections,
                  const SizedBox(height: 18),
                  _buildSetupDialogActions(
                    dialogContext: dialogContext,
                    primaryLabel: primaryLabel,
                    primaryIcon: primaryIcon,
                    onPrimaryPressed: () {
                      Navigator.of(dialogContext).pop();
                      onPrimaryPressed();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSetupDialogActions({
    required BuildContext dialogContext,
    required String primaryLabel,
    required IconData primaryIcon,
    required VoidCallback onPrimaryPressed,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 640;
        final primaryButton = FilledButton.icon(
          onPressed: onPrimaryPressed,
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          icon: Icon(primaryIcon, size: 18),
          label: Text(
            primaryLabel,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text(
                      'Later',
                      style: TextStyle(
                        color: hint,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: primaryButton),
            ],
          );
        }

        return Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Later',
                style: TextStyle(color: hint, fontWeight: FontWeight.w900),
              ),
            ),
            const Spacer(),
            primaryButton,
          ],
        );
      },
    );
  }

  Widget _buildSetupSection({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: hint,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSetupChecklistRow({
    required String label,
    required bool ready,
    required String missingHint,
  }) {
    final color = ready ? const Color(0xFF2F855A) : const Color(0xFFC53030);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: ready
                ? const Color(0xFF2F855A).withValues(alpha: 0.10)
                : const Color(0xFFC53030).withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Icon(
            ready ? Icons.check_rounded : Icons.close_rounded,
            size: 14,
            color: color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ready ? 'Ready' : missingHint,
                style: TextStyle(
                  color: ready ? const Color(0xFF2F855A) : hint,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.2,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
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
    _go(_notificationsIndex);
  }

  Future<void> _logout() async {
    final confirmed = await showLogoutConfirmDialog(context);
    if (!mounted || !confirmed) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    context.go('/welcome');
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

  String _profilePhotoUrl(Map<String, dynamic> data) {
    final direct = (data['photoUrl'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final profilePhoto = (data['profilePhotoUrl'] ?? '').toString().trim();
    if (profilePhoto.isNotEmpty) return profilePhoto;
    final studentProfile = data['studentProfile'] as Map<String, dynamic>?;
    final nestedStudentPhoto = (studentProfile?['photoUrl'] ?? '')
        .toString()
        .trim();
    if (nestedStudentPhoto.isNotEmpty) return nestedStudentPhoto;
    final employeeProfile = data['employeeProfile'] as Map<String, dynamic>?;
    final nestedEmployeePhoto = (employeeProfile?['photoUrl'] ?? '')
        .toString()
        .trim();
    if (nestedEmployeePhoto.isNotEmpty) return nestedEmployeePhoto;
    return '';
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
      stream: AppFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final accountName = _displayName(data, user);
        final accountEmail = _email(data, user);
        final accountTitle = _title(data);
        final profilePhotoUrl = _profilePhotoUrl(data);

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
              profilePhotoUrl: profilePhotoUrl,
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
                  profilePhotoUrl: profilePhotoUrl,
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
  final String profilePhotoUrl;

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
    required this.profilePhotoUrl,
  });

  bool _isHttpPhotoUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  Future<String> _resolvePhotoUrl(String source) async {
    final value = source.trim();
    if (value.isEmpty) return '';
    if (_isHttpPhotoUrl(value)) {
      if (value.contains('firebasestorage.googleapis.com') ||
          value.contains('firebasestorage.app')) {
        try {
          return await FirebaseStorage.instance
              .refFromURL(value)
              .getDownloadURL();
        } catch (_) {
          return value;
        }
      }
      return value;
    }
    try {
      if (value.startsWith('gs://')) {
        return await FirebaseStorage.instance
            .refFromURL(value)
            .getDownloadURL();
      }
      return await FirebaseStorage.instance.ref(value).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  Widget _buildProfileAvatar() {
    final source = profilePhotoUrl.trim();
    const fallback = Icon(
      Icons.person_outline_rounded,
      size: 24,
      color: Colors.white,
    );
    final fallbackAvatar = const CircleAvatar(
      backgroundColor: Colors.white24,
      child: fallback,
    );

    Widget photoAvatar(String url) {
      return ClipOval(
        child: Image.network(
          url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          errorBuilder: (_, _, _) => fallbackAvatar,
        ),
      );
    }

    if (source.isEmpty) return fallbackAvatar;
    if (_isHttpPhotoUrl(source)) {
      return FutureBuilder<String>(
        future: _resolvePhotoUrl(source),
        builder: (context, snapshot) {
          final resolved = (snapshot.data ?? source).trim();
          return resolved.isEmpty ? fallbackAvatar : photoAvatar(resolved);
        },
      );
    }
    return FutureBuilder<String>(
      future: _resolvePhotoUrl(source),
      builder: (context, snapshot) {
        final resolved = (snapshot.data ?? '').trim();
        return resolved.isEmpty ? fallbackAvatar : photoAvatar(resolved);
      },
    );
  }

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
                        child: _buildProfileAvatar(),
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

import 'package:apps/pages/professor/violation_report_page.dart';
import 'package:apps/pages/professor/MySubmittedReportPage.dart';
import 'package:apps/pages/shared/handbook/hb_handbook_page.dart';
import 'package:apps/pages/shared/notifications/app_notifications_ui.dart';
import 'package:apps/pages/shared/profile/unified_profile_page.dart';
import 'package:apps/pages/shared/welcome_screen_page.dart';
import 'package:apps/pages/shared/widgets/app_branding.dart';
import 'package:apps/pages/shared/widgets/app_theme_tokens.dart';
import 'package:apps/pages/shared/widgets/logout_confirm_dialog.dart';
import 'package:apps/pages/shared/widgets/responsive_layout_tokens.dart';
import 'package:apps/pages/shared/widgets/role_shell_scaffold.dart';
import 'package:apps/pages/shared/widgets/unsaved_changes_guard.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'professor_counseling_page.dart';
import 'professor_home_page.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';

class ProfessorDashboard extends StatefulWidget {
  const ProfessorDashboard({super.key});

  @override
  State<ProfessorDashboard> createState() => _ProfessorDashboardState();
}

class _ProfessorDashboardState extends State<ProfessorDashboard> {
  int _currentIndex = 0;
  int _previousIndexBeforeNotifications = 0;
  bool _showDesktopNotifications = false;
  final _violationUnsaved = UnsavedChangesController();
  final _counselingUnsaved = UnsavedChangesController();
  static const List<int> _mobileNavIndexes = <int>[0, 1, 3];
  static const int _notificationsIndex = 6;

  // ================== THEME (same as StudentDashboard) ==================
  static const bg = AppColors.background;
  static const primary = AppColors.primary;
  static const hint = AppColors.hint;
  static const textDark = AppColors.textDark;
  static const surface = AppColors.surface;

  // ================== PAGES ==================
  List<Widget> get _pages => [
    const ProfessorHomePage(),
    const HbHandbookPage(hideTopHeader: true),
    ViolationReportPage(
      onOpenMyReportsInShell: () => _go(3),
      unsavedChangesController: _violationUnsaved,
    ),
    MySubmittedCasesPage(
      onOpenViolationReport: _openViolationReportModal,
      onOpenCounselingReferral: _openCounselingReferralModal,
    ),
    ProfessorCounselingPage(unsavedChangesController: _counselingUnsaved),
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
      case 5:
        return "Profile";
      case _notificationsIndex:
        return "Notifications";
      default:
        return "Professor Portal";
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

  UnsavedChangesController? _controllerForIndex(int index) {
    switch (index) {
      case 2:
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

  Future<void> _openViolationReportModal() async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    await _openFormModal(
      title: 'Report Violation',
      subtitle: 'Search a student, complete incident details, and submit.',
      child: ViolationReportPage(
        onOpenMyReportsInShell: () {
          Navigator.of(context, rootNavigator: true).pop();
          _go(3);
        },
      ),
    );
  }

  Future<void> _openCounselingReferralModal() async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    await _openFormModal(
      title: 'Counselling Referral',
      child: const ProfessorCounselingPage(),
    );
  }

  void _go(int i) {
    _goAsync(i);
  }

  Future<void> _goAsync(int i) async {
    if (i == 2) {
      await _openViolationReportModal();
      return;
    }
    if (i == 4) {
      await _openCounselingReferralModal();
      return;
    }
    if (i == _currentIndex) return;
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    setState(() {
      _currentIndex = i;
      if (i != _notificationsIndex) {
        _previousIndexBeforeNotifications = i;
      }
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

  Future<void> _handleNotificationView(AppNotificationViewIntent intent) async {
    switch (intent.target) {
      case AppNotificationViewTarget.pendingApproval:
        _go(3);
        break;
      case AppNotificationViewTarget.violationAlert:
        _go(3);
        break;
    }
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
              navItems: _navItems,
              primary: primary,
              hint: hint,
              textDark: textDark,
              surface: surface,
              onSelect: _go,
              onProfile: () => _go(5),
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
                    _go(5);
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
                  if (_currentIndex == _notificationsIndex) {
                    final backIndex =
                        _previousIndexBeforeNotifications == _notificationsIndex
                        ? 0
                        : _previousIndexBeforeNotifications;
                    _go(backIndex);
                  } else {
                    _openNotificationsPage();
                  }
                }
              },
              notificationsUid: user.uid,
              suppressIncomingNotificationToasts:
                  _showDesktopNotifications ||
                  _currentIndex == _notificationsIndex,
              hideNotificationsBadge:
                  _showDesktopNotifications ||
                  _currentIndex == _notificationsIndex,
              enableNotificationSound: false,
              showDesktopOverlay: shell.isDesktop && _showDesktopNotifications,
              onDismissDesktopOverlay: _closeDesktopNotifications,
              desktopOverlay: DesktopNotificationsPanel(
                uid: user.uid,
                onClose: _closeDesktopNotifications,
                onSeeAll: _openNotificationsPage,
                onViewNotification: (intent) async {
                  _closeDesktopNotifications();
                  await _handleNotificationView(intent);
                },
              ),
              showBackButton:
                  shell.usesDrawerSidebar &&
                  _currentIndex == _notificationsIndex,
              onBackPressed: () {
                final backIndex =
                    _previousIndexBeforeNotifications == _notificationsIndex
                    ? 0
                    : _previousIndexBeforeNotifications;
                _go(backIndex);
              },
              bottomNavigationBar: shell.isDesktop
                  ? null
                  : (_mobileNavIndexes.isEmpty ||
                            !_mobileNavIndexes.contains(_currentIndex)
                        ? null
                        : BottomNavigationBar(
                            currentIndex: _mobileNavIndexes.indexOf(
                              _currentIndex,
                            ),
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
                          )),
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
  final VoidCallback onLogout;

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
                        item.label == 'Counseling Referrals') {
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
                ],
              ),
            ),
          ),
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
    );
  }
}

import 'package:apps/pages/shared/handbook/handbook_sections_screen.dart';
import 'package:apps/pages/shared/handbook/handbook_new_layout_page.dart';
import 'package:apps/pages/shared/notifications/app_notifications_ui.dart';
import 'package:apps/pages/shared/profile/unified_profile_page.dart';
import 'package:apps/pages/shared/welcome_screen_page.dart';
import 'package:apps/pages/shared/widgets/logout_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'osa_home_page.dart';

// ✅ SETTINGS SUB-PAGES (adjust paths to your project)
import 'academic/academic_years_page.dart';
import 'handbook_manage_page.dart';
import 'meeting_schedule_page.dart';
import 'student_management_page.dart';
import 'user_management_page.dart';
import 'violation_analytics_page.dart';
import 'violation_records_page.dart';
import 'violation_types_page.dart';
import 'handbook_docs_editor_page.dart';
import 'osa_violation_review_page.dart';

class OsaDashboard extends StatefulWidget {
  const OsaDashboard({super.key});

  @override
  State<OsaDashboard> createState() => _OsaDashboardState();
}

class _OsaDashboardState extends State<OsaDashboard> {
  int _currentIndex = 0;
  bool _showDesktopNotifications = false;
  ViolationRecordsFilterPreset? _recordsPreset;
  int _recordsPresetVersion = 0;

  // ✅ Settings section open/close
  bool _settingsOpen = false;
  bool _handbookOpen = true;

  // ================== THEME (match reference dashboard) ==================
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);
  static const surface = Color(0xFFFFFFFF);

  // ================== PAGES ==================
  // Keep as a getter so hot reload reflects changes (initState doesn't rerun).
  List<Widget> get _pages => [
    OsaHomePage(onOpenAcademicSettings: () => _goSettings(4)),
    const HandbookSectionsScreen(),
    const HandbookSectionsScreen(useSidebarDesktop: false),
    ViolationRecordsPage(
      key: ValueKey('violation-records-$_recordsPresetVersion'),
      initialFilterPreset: _recordsPreset,
    ),

    // ✅ Settings sub-pages
    const AcademicYearsPage(),
    const UserManagementPage(),
    const StudentManagementPage(),
    const ViolationTypesPage(),
    const MeetingSchedulePage(),
    const HandbookManagePage(),
    const UnifiedProfilePage(),
    const HandbookNewLayoutPage(),
    const HandbookDocsEditorPage(),
    ViolationAnalyticsPage(
      onOpenRecords: (preset) {
        setState(() {
          _recordsPreset = preset;
          _recordsPresetVersion++;
          _currentIndex = 3;
        });
      },
    ),
    const OsaViolationReviewPage(),
  ];

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return "Dashboard";
      case 1:
        return "Student Handbook";
      case 2:
        return "Student Handbook (Classic)";
      case 3:
        return "Violation Records";

      // ✅ Settings pages
      case 4:
        return "Academic Settings";
      case 5:
        return "User Management";
      case 6:
        return "Student Management";
      case 7:
        return "Violation Settings";
      case 8:
        return "Meeting Schedule";
      case 9:
        return "Manage Handbook";
      case 10:
        return "Profile";
      case 11:
        return "Student Handbook (New Layout)";
      case 12:
        return "Handbook Docs Editor";
      case 13:
        return "Violation Analytics";
      case 14:
        return "Violation Review";

      default:
        return "OSA Portal";
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

  void _go(int i) {
    setState(() {
      _currentIndex = i;
      if (i == 1 || i == 2 || i == 9 || i == 11 || i == 12) {
        _handbookOpen = true;
      }
      if (i >= 4 && i <= 8) _settingsOpen = true;
    });
  }

  void _goSettings(int pageIndex) {
    setState(() {
      _settingsOpen = true; // keep open when selecting sub-item
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

            // ✅ same responsiveness rule as reference
            final bool isDesktop = w >= 900;
            final double h = constraints.maxHeight;
            // Treat typical 1366x768 (and nearby compact laptop sizes) as hamburger mode.
            final bool compactDesktop = isDesktop && (w <= 1450 || h <= 820);
            final bool showPermanentSidebar = isDesktop && !compactDesktop;
            final bool useDrawerSidebar = !showPermanentSidebar;

            return Scaffold(
              backgroundColor: bg,

              // ✅ Drawer only for phone/tablet
              drawer: useDrawerSidebar
                  ? Drawer(
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
                          setState(() => _currentIndex = 10);
                        },

                        // ✅ SETTINGS SECTION
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
                    )
                  : null,

              body: Row(
                children: [
                  // ✅ Permanent sidebar on desktop
                  if (showPermanentSidebar)
                    SizedBox(
                      width: 260,
                      child: Material(
                        color: surface,
                        child: _MenuPanel(
                          currentIndex: _currentIndex,
                          primary: primary,
                          hint: hint,
                          textDark: textDark,
                          surface: surface,
                          onSelect: _go,
                          onProfile: () {
                            setState(() => _currentIndex = 10);
                          },

                          // ✅ SETTINGS SECTION
                          settingsOpen: _settingsOpen,
                          onToggleSettings: () =>
                              setState(() => _settingsOpen = !_settingsOpen),
                          onSelectSettingsItem: (pageIndex) =>
                              _goSettings(pageIndex),
                          handbookOpen: _handbookOpen,
                          onToggleHandbook: () =>
                              setState(() => _handbookOpen = !_handbookOpen),

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
                              // ✅ Shared header controlled by dashboard (same as reference)
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
                                        if (useDrawerSidebar)
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

                              // ✅ Page content (keeps state)
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
                  _SectionLabel(
                    label: 'MAIN',
                    color: hint.withValues(alpha: 0.95),
                  ),
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
                        currentIndex == 2 ||
                        currentIndex == 9 ||
                        currentIndex == 11 ||
                        currentIndex == 12,
                    primary: primary,
                    textDark: textDark,
                    hint: hint,
                    onTap: onToggleHandbook,
                  ),
                  if (handbookOpen) ...[
                    _SubItem(
                      label: 'Student Handbook',
                      icon: Icons.menu_book_rounded,
                      active: currentIndex == 1,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelect(1),
                    ),
                    _SubItem(
                      label: 'Handbook Classic',
                      icon: Icons.menu_book_outlined,
                      active: currentIndex == 2,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelect(2),
                    ),
                    _SubItem(
                      label: 'Manage Handbook',
                      icon: Icons.edit_note_rounded,
                      active: currentIndex == 9,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelect(9),
                    ),
                    _SubItem(
                      label: 'Handbook New Layout',
                      icon: Icons.auto_awesome_rounded,
                      active: currentIndex == 11,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelect(11),
                    ),
                    _SubItem(
                      label: 'Handbook Docs Editor',
                      icon: Icons.description_rounded,
                      active: currentIndex == 12,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelect(12),
                    ),
                    const SizedBox(height: 6),
                  ],
                  _SectionLabel(
                    label: 'OPERATIONS',
                    color: hint.withValues(alpha: 0.95),
                  ),
                  _MenuItem(
                    icon: Icons.rule_rounded,
                    label: 'Violation Review',
                    active: currentIndex == 14,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(14),
                  ),
                  _MenuItem(
                    icon: Icons.assignment_rounded,
                    label: 'Violation Records',
                    active: currentIndex == 3,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(3),
                  ),
                  _MenuItem(
                    icon: Icons.analytics_rounded,
                    label: 'Violation Analytics',
                    active: currentIndex == 13,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(13),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: primary.withValues(alpha: 0.15), height: 18),
                  _SectionLabel(
                    label: 'ADMINISTRATION',
                    color: hint.withValues(alpha: 0.95),
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
                    _SubItem(
                      label: 'Academic Settings',
                      icon: Icons.school_rounded,
                      active: currentIndex == 4,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(4),
                    ),
                    _SubItem(
                      label: 'User Management',
                      icon: Icons.people_alt_rounded,
                      active: currentIndex == 5,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(5),
                    ),
                    _SubItem(
                      label: 'Student Management',
                      icon: Icons.school_outlined,
                      active: currentIndex == 6,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(6),
                    ),
                    _SubItem(
                      label: 'Violation Settings',
                      icon: Icons.fact_check_rounded,
                      active: currentIndex == 7,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(7),
                    ),
                    _SubItem(
                      label: 'Meeting Schedule',
                      icon: Icons.calendar_month_rounded,
                      active: currentIndex == 8,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(8),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Divider(color: primary.withValues(alpha: 0.15), height: 18),
                  _SectionLabel(
                    label: 'ACCOUNT',
                    color: hint.withValues(alpha: 0.95),
                  ),
                  _MenuItem(
                    icon: Icons.person_outline_rounded,
                    label: 'Profile',
                    active: currentIndex == 10,
                    primary: primary,
                    textDark: textDark,
                    onTap: onProfile,
                  ),
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

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
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

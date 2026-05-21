import 'package:apps/pages/shared/notifications/app_notifications_ui.dart';
import 'package:apps/pages/shared/profile/unified_profile_page.dart';
import 'package:apps/pages/shared/widgets/app_branding.dart';
import 'package:apps/pages/shared/widgets/app_theme_tokens.dart';
import 'package:apps/pages/shared/widgets/logout_confirm_dialog.dart';
import 'package:apps/pages/shared/widgets/responsive_layout_tokens.dart';
import 'package:apps/pages/shared/widgets/role_shell_scaffold.dart';
import 'package:apps/services/app_router.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';

// ✅ your pages
import 'super_admin_home_page.dart';
import 'package:apps/pages/shared/handbook/hb_handbook_page.dart';
import 'package:apps/pages/super_admin/user_management_page.dart';
import 'package:apps/pages/super_admin/student_management_page.dart';
import 'package:apps/pages/osa_admin/institution_setup_page.dart';
import 'package:apps/services/app_firestore.dart';
import 'package:apps/services/institution_setup_status_service.dart';

class SuperAdminDashboard extends StatefulWidget {
  final String section;
  final String? initialEmployeeNo;
  final String? initialStudentNo;
  final String? tabDeepLink;
  final String? handbookSectionId;
  final String? handbookHighlightText;

  const SuperAdminDashboard({
    super.key,
    this.section = 'dashboard',
    this.initialEmployeeNo,
    this.initialStudentNo,
    this.tabDeepLink,
    this.handbookSectionId,
    this.handbookHighlightText,
  });

  static const _sectionToIndex = <String, int>{
    'dashboard': 0,
    'users': 1,
    'students': 2,
    'institution': 3,
    'handbook': 4,
    'profile': 5,
    'notifications': 6,
  };

  static const _indexToSection = <int, String>{
    0: 'dashboard',
    1: 'users',
    2: 'students',
    3: 'institution',
    4: 'handbook',
    5: 'profile',
    6: 'notifications',
  };

  static int indexForSection(String section) => _sectionToIndex[section] ?? 0;

  static String sectionForIndex(int index) =>
      _indexToSection[index] ?? 'dashboard';

  static String pathForSection(String section, {Map<String, String>? query}) {
    final base = AppRoutes.withSection(AppRoutes.superAdmin, section);
    if (query == null || query.isEmpty) return base;
    return Uri(path: base, queryParameters: query).toString();
  }

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  static final Map<String, String> _sessionTabBySection = <String, String>{};
  late int _currentIndex;
  bool _settingsOpen = false;
  int _previousIndexBeforeNotifications = 0;
  bool _showDesktopNotifications = false;
  bool _institutionSetupChecked = false;
  static const int _profileIndex = 5;
  static const int _notificationsIndex = 6;

  // ================== THEME (match StudentDashboard 2) ==================
  static const bg = AppColors.background;
  static const primary = AppColors.primary;
  static const hint = AppColors.hint;
  static const textDark = AppColors.textDark;
  static const surface = AppColors.surface;

  List<Widget> get _pages => [
    SuperAdminHomePage(),
    UserManagementPage(
      initialEmployeeNo: widget.initialEmployeeNo,
      initialTab: _effectiveTabForSection('users'),
      onTabChanged: (tabKey) => _syncSectionTab('users', tabKey),
    ),
    StudentManagementPage(
      initialStudentNo: widget.initialStudentNo,
      initialTab: _effectiveTabForSection('students'),
      onTabChanged: (tabKey) => _syncSectionTab('students', tabKey),
    ),
    InstitutionSetupPage(
      initialTab: _effectiveTabForSection('institution'),
      onTabChanged: (tabKey) => _syncSectionTab('institution', tabKey),
    ),
    HbHandbookPage(
      hideTopHeader: true,
      initialSectionId: widget.handbookSectionId,
      initialHighlightText: widget.handbookHighlightText,
      openSelectedOnMobile: true,
    ),
    const UnifiedProfilePage(),
    AppNotificationsContent(
      onBack: () {
        final backIndex =
            _previousIndexBeforeNotifications == _notificationsIndex
            ? 0
            : _previousIndexBeforeNotifications;
        _go(backIndex);
      },
    ),
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
    _NavItem(Icons.manage_accounts_rounded, 'User Management'),
    _NavItem(Icons.school_rounded, 'Student Management'),
    _NavItem(Icons.account_balance_rounded, 'Institution Setup'),
    _NavItem(Icons.menu_book_rounded, 'Handbook'),
  ];

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return "Dashboard";
      case 1:
        return "User Management";
      case 2:
        return "Student Management";
      case 3:
        return "Institution Setup";
      case 4:
        return "Handbook";
      case 5:
        return "Profile";
      case _notificationsIndex:
        return "Notifications";
      default:
        return "Super Administrator";
    }
  }

  @override
  void didUpdateWidget(covariant SuperAdminDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = SuperAdminDashboard.indexForSection(widget.section);
    if (_currentIndex != nextIndex) {
      setState(() {
        _currentIndex = nextIndex;
        _settingsOpen = _isSettingsIndex(_currentIndex);
      });
    }
    final incomingTab = (widget.tabDeepLink ?? '').trim();
    final incomingSection = widget.section.trim();
    if (incomingTab.isNotEmpty &&
        (incomingSection == 'users' ||
            incomingSection == 'students' ||
            incomingSection == 'institution')) {
      _sessionTabBySection[incomingSection] = incomingTab;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSectionTabQuery();
    });
  }

  void _go(int i) {
    if (i != _notificationsIndex) {
      _previousIndexBeforeNotifications = i;
    }
    final section = SuperAdminDashboard.sectionForIndex(i);
    final tab = _defaultTabForSection(section);
    final target = SuperAdminDashboard.pathForSection(
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
      case 'users':
        return 'active';
      case 'students':
        return 'pending';
      case 'institution':
        return 'school-year';
      default:
        return null;
    }
  }

  void _ensureSectionTabQuery() {
    if (!mounted) return;
    final section = SuperAdminDashboard.sectionForIndex(_currentIndex);
    final defaultTab = _defaultTabForSection(section);
    if (defaultTab == null) return;
    final currentUri = GoRouterState.of(context).uri;
    final currentTab = (currentUri.queryParameters['tab'] ?? '').trim();
    if (currentTab.isNotEmpty) return;
    final target = SuperAdminDashboard.pathForSection(
      section,
      query: <String, String>{'tab': defaultTab},
    );
    if (target == currentUri.toString()) return;
    context.replace(target);
  }

  void _syncSectionTab(String section, String tabKey) {
    final currentSection = SuperAdminDashboard.sectionForIndex(_currentIndex);
    if (currentSection != section) return;
    _sessionTabBySection[section] = tabKey;
    final currentUri = GoRouterState.of(context).uri;
    final currentTab = (currentUri.queryParameters['tab'] ?? '').trim();
    if (currentTab == tabKey) return;
    final target = SuperAdminDashboard.pathForSection(
      section,
      query: <String, String>{'tab': tabKey},
    );
    if (target == currentUri.toString()) return;
    context.go(target);
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = SuperAdminDashboard.indexForSection(widget.section);
    _settingsOpen = _isSettingsIndex(_currentIndex);
    final incomingTab = (widget.tabDeepLink ?? '').trim();
    final incomingSection = widget.section.trim();
    if (incomingTab.isNotEmpty &&
        (incomingSection == 'users' ||
            incomingSection == 'students' ||
            incomingSection == 'institution')) {
      _sessionTabBySection[incomingSection] = incomingTab;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSectionTabQuery();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowInstitutionSetupModal();
    });
  }

  bool _isSettingsIndex(int index) => index == 1 || index == 2 || index == 3;

  Future<void> _maybeShowInstitutionSetupModal() async {
    if (_institutionSetupChecked || !mounted) return;
    _institutionSetupChecked = true;

    InstitutionSetupStatus status;
    try {
      status = await InstitutionSetupStatusService().load();
    } catch (error) {
      debugPrint('Failed to load institution setup status: $error');
      return;
    }

    if (!mounted || status.isComplete) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _InstitutionSetupRequiredDialog(
          missingItems: status.missingItems,
          onOpenSetup: () {
            Navigator.of(dialogContext).pop();
            if (!mounted) return;
            _go(3);
          },
        );
      },
    );
  }

  Future<void> _logout() async {
    final confirmed = await showLogoutConfirmDialog(context);
    if (!mounted || !confirmed) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    context.go('/welcome');
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

  String _displayName(Map<String, dynamic> data, User user) {
    final dn = (data['displayName'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final full = ('$first $last').trim();
    if (full.isNotEmpty) return full;
    final email = (data['email'] ?? user.email ?? '').toString().trim();
    if (email.contains('@')) return email.split('@').first;
    return 'Administrator';
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
        final profilePhotoUrl = _profilePhotoUrl(data);

        return LayoutBuilder(
          builder: (context, constraints) {
            final shell = ResponsiveLayoutTokens.resolveShellLayout(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              allowCompactDesktopDrawer: true,
            );

            final menuPanel = _AdminMenuPanel(
              currentIndex: _currentIndex,
              navItems: _navItems,
              accountName: accountName,
              accountEmail: accountEmail,
              profilePhotoUrl: profilePhotoUrl,
              primary: primary,
              hint: hint,
              textDark: textDark,
              surface: surface,
              onSelect: _go,
              onProfile: () => _go(_profileIndex),
              settingsOpen: _settingsOpen,
              onToggleSettings: () =>
                  setState(() => _settingsOpen = !_settingsOpen),
              onSelectSettingsItem: _go,
              onLogout: _logout,
            );

            return RoleShellScaffold(
              backgroundColor: bg,
              title: _pageTitle(),
              usesDrawerSidebar: shell.usesDrawerSidebar,
              showPermanentSidebar: shell.showPermanentSidebar,
              sidebarWidth: 280,
              drawer: Drawer(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                child: _AdminMenuPanel(
                  currentIndex: _currentIndex,
                  navItems: _navItems,
                  accountName: accountName,
                  accountEmail: accountEmail,
                  profilePhotoUrl: profilePhotoUrl,
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
                    _go(_profileIndex);
                  },
                  settingsOpen: _settingsOpen,
                  onToggleSettings: () =>
                      setState(() => _settingsOpen = !_settingsOpen),
                  onSelectSettingsItem: (i) {
                    Navigator.of(context).maybePop();
                    _go(i);
                  },
                  onLogout: () {
                    Navigator.of(context).maybePop();
                    _logout();
                  },
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

class _InstitutionSetupRequiredDialog extends StatelessWidget {
  final List<String> missingItems;
  final VoidCallback onOpenSetup;

  const _InstitutionSetupRequiredDialog({
    required this.missingItems,
    required this.onOpenSetup,
  });

  @override
  Widget build(BuildContext context) {
    const primary = AppColors.primary;
    const hint = AppColors.hint;
    const textDark = AppColors.textDark;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
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
                    child: const Icon(
                      Icons.account_balance_rounded,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Institution Setup Required',
                          style: TextStyle(
                            color: primary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Before the system can fully support student workflows, complete the core institution setup.',
                          style: TextStyle(
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.025),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Missing items',
                      style: TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final item in missingItems) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.checklist_rtl_rounded,
                              size: 16,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (item != missingItems.last) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Later',
                      style: TextStyle(
                        color: hint,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onOpenSetup,
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text(
                      'Open Institution Setup',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= SHARED ADMIN MENU (Drawer + Sidebar) =================

class _AdminMenuPanel extends StatefulWidget {
  final int currentIndex;
  final List<_NavItem> navItems;
  final String accountName;
  final String accountEmail;
  final String profilePhotoUrl;

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

  const _AdminMenuPanel({
    required this.currentIndex,
    required this.navItems,
    required this.accountName,
    required this.accountEmail,
    required this.profilePhotoUrl,
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
  });

  @override
  State<_AdminMenuPanel> createState() => _AdminMenuPanelState();
}

class _AdminMenuPanelState extends State<_AdminMenuPanel> {
  Widget _buildNavTile({
    required _NavItem item,
    required int index,
    required bool active,
    required bool indented,
    VoidCallback? onTap,
  }) {
    final Color iconColor = active
        ? widget.primary
        : widget.textDark.withValues(alpha: 0.85);
    final Color textColor = active
        ? widget.primary
        : widget.textDark.withValues(alpha: 0.92);

    return InkWell(
      onTap: onTap ?? () => widget.onSelect(index),
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: indented ? 18 : 10,
          vertical: 4,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: indented ? 12 : 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: active
              ? widget.primary.withValues(alpha: 0.10)
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
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
    final source = widget.profilePhotoUrl.trim();
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
      color: widget.surface,
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
                      color: widget.primary,
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
                onTap: widget.onProfile,
                child: Ink(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: widget.primary.withValues(
                      alpha: widget.currentIndex == 5 ? 0.86 : 0.80,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: widget.primary.withValues(alpha: 0.22),
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
                              widget.accountName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.accountEmail,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.90),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Super Administrator',
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
                  if (widget.navItems.length > 4) ...[
                    _buildNavTile(
                      item: widget.navItems[0],
                      index: 0,
                      active: widget.currentIndex == 0,
                      indented: false,
                    ),
                    _buildNavTile(
                      item: widget.navItems[4],
                      index: 4,
                      active: widget.currentIndex == 4,
                      indented: false,
                    ),
                    const SizedBox(height: 8),
                    Divider(
                      color: widget.primary.withValues(alpha: 0.15),
                      height: 18,
                    ),
                    InkWell(
                      onTap: widget.onToggleSettings,
                      borderRadius: BorderRadius.circular(10),
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
                          color: widget.settingsOpen
                              ? widget.primary.withValues(alpha: 0.08)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.settings_outlined,
                              color: widget.textDark.withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Settings',
                                style: TextStyle(
                                  color: widget.textDark.withValues(
                                    alpha: 0.92,
                                  ),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Icon(
                              widget.settingsOpen
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: widget.hint,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.settingsOpen) ...[
                      const SizedBox(height: 4),
                      _buildNavTile(
                        item: widget.navItems[1],
                        index: 1,
                        active: widget.currentIndex == 1,
                        indented: true,
                        onTap: () => widget.onSelectSettingsItem(1),
                      ),
                      _buildNavTile(
                        item: widget.navItems[2],
                        index: 2,
                        active: widget.currentIndex == 2,
                        indented: true,
                        onTap: () => widget.onSelectSettingsItem(2),
                      ),
                      _buildNavTile(
                        item: widget.navItems[3],
                        index: 3,
                        active: widget.currentIndex == 3,
                        indented: true,
                        onTap: () => widget.onSelectSettingsItem(3),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ] else ...[
                    ...widget.navItems.asMap().entries.map(
                      (entry) => _buildNavTile(
                        item: entry.value,
                        index: entry.key,
                        active: widget.currentIndex == entry.key,
                        indented: false,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: widget.primary.withValues(alpha: 0.15)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: InkWell(
              onTap: widget.onLogout,
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

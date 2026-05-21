import 'package:apps/pages/shared/handbook/hb_handbook_page.dart';
import 'package:apps/pages/shared/notifications/app_notifications_ui.dart';
import 'package:apps/pages/shared/profile/unified_profile_page.dart';
import 'package:apps/pages/shared/widgets/app_branding.dart';
import 'package:apps/pages/shared/widgets/app_theme_tokens.dart';
import 'package:apps/pages/shared/widgets/logout_confirm_dialog.dart';
import 'package:apps/pages/shared/widgets/responsive_layout_tokens.dart';
import 'package:apps/pages/shared/widgets/role_shell_scaffold.dart';
import 'package:apps/services/app_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../professor/MySubmittedReportPage.dart';
import '../professor/violation_report_page.dart';
import 'package:apps/services/app_firestore.dart';

class GuardDashboard extends StatefulWidget {
  final String section;

  const GuardDashboard({super.key, this.section = 'home'});

  static const _sectionToIndex = <String, int>{
    'home': 0,
    'handbook': 1,
    'report': 2,
    'my-reports': 3,
    'profile': 4,
    'notifications': 5,
  };

  static const _indexToSection = <int, String>{
    0: 'home',
    1: 'handbook',
    2: 'report',
    3: 'my-reports',
    4: 'profile',
    5: 'notifications',
  };

  static int indexForSection(String section) => _sectionToIndex[section] ?? 0;

  static String sectionForIndex(int index) => _indexToSection[index] ?? 'home';

  static String pathForSection(String section) =>
      AppRoutes.withSection(AppRoutes.guard, section);

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> {
  late int _currentIndex;
  int _previousIndexBeforeNotifications = 0;
  bool _showDesktopNotifications = false;
  static const List<int> _mobileNavIndexes = <int>[0, 1, 3];
  static const int _notificationsIndex = 5;

  static const bg = AppColors.background;
  static const primary = AppColors.primary;
  static const hint = AppColors.hint;
  static const textDark = AppColors.textDark;
  static const surface = AppColors.surface;

  List<Widget> get _pages => [
    const _GuardHomePlaceholder(),
    const HbHandbookPage(hideTopHeader: true),
    ViolationReportPage(onOpenMyReportsInShell: () => _go(3)),
    MySubmittedCasesPage(
      showCounselingTab: false,
      onOpenViolationReport: () => _go(2),
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
      onViewNotification: _handleNotificationView,
    ),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(Icons.home_rounded, 'Home'),
    _NavItem(Icons.menu_book_rounded, 'Handbook'),
    _NavItem(Icons.report_rounded, 'Report Violation'),
    _NavItem(Icons.assignment_rounded, 'My Reports'),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = GuardDashboard.indexForSection(widget.section);
  }

  @override
  void didUpdateWidget(covariant GuardDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = GuardDashboard.indexForSection(widget.section);
    if (_currentIndex != nextIndex) {
      setState(() => _currentIndex = nextIndex);
    }
  }

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Home';
      case 1:
        return 'Student Handbook';
      case 2:
        return 'Report Violation';
      case 3:
        return 'My Reports';
      case 4:
        return 'Profile';
      case _notificationsIndex:
        return 'Notifications';
      default:
        return 'Guard Portal';
    }
  }

  void _go(int i) {
    if (i != _notificationsIndex) {
      _previousIndexBeforeNotifications = i;
    }
    final section = GuardDashboard.sectionForIndex(i);
    final target = GuardDashboard.pathForSection(section);
    if (GoRouterState.of(context).uri.path == target) return;
    context.go(target);
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
    if (_currentIndex != _notificationsIndex) {
      _previousIndexBeforeNotifications = _currentIndex;
    }
    _showDesktopNotifications = false;
    _go(_notificationsIndex);
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
    return 'Guard';
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
      case 'guard':
        return 'Security Personnel';
      default:
        return 'Guard Portal';
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

            final menuPanel = _MenuPanel(
              currentIndex: _currentIndex,
              navItems: _navItems,
              primary: primary,
              hint: hint,
              textDark: textDark,
              surface: surface,
              onSelect: _go,
              onProfile: () => _go(4),
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
                    _go(4);
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

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

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
  final String profilePhotoUrl;

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
                    if (item.label == 'Report Violation') {
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

class _GuardHomePlaceholder extends StatelessWidget {
  const _GuardHomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Guard Home',
        style: TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w900,
          fontSize: 28,
        ),
      ),
    );
  }
}

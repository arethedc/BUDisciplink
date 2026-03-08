import 'package:apps/pages/osa_admin/osa_cases_page.dart';
import 'package:apps/pages/shared/notifications/app_notifications_ui.dart';
import 'package:apps/pages/shared/profile/unified_profile_page.dart';
import 'package:apps/pages/shared/welcome_screen_page.dart';
import 'package:apps/pages/shared/widgets/logout_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ✅ your pages
import 'super_admin_home_page.dart';
import 'package:apps/pages/shared/handbook/handbook_sections_screen.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  int _currentIndex = 0;
  bool _showDesktopNotifications = false;

  // ================== THEME (match StudentDashboard 2) ==================
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);
  static const surface = Color(0xFFFFFFFF);

  final List<Widget> _pages = [
    SuperAdminHomePage(),
    OsaCasesPage(),
    HandbookSectionsScreen(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.manage_accounts_rounded, 'Manage Users'),
    _NavItem(Icons.menu_book_rounded, 'Handbook'),
  ];

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return "Dashboard";
      case 1:
        return "Manage Users";
      case 2:
        return "Handbook";
      default:
        return "Super Administrator";
    }
  }

  void _go(int i) => setState(() => _currentIndex = i);

  Future<void> _openProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const UnifiedProfilePage()));
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
    return 'Administrator';
  }

  String _email(Map<String, dynamic> data, User user) {
    final e = (data['email'] ?? user.email ?? '').toString().trim();
    return e.isEmpty ? '--' : e;
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

        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;

            // ✅ responsive:
            // phone/tablet => drawer
            // desktop => permanent sidebar
            final bool isDesktop = w >= 900;
            final bool useDrawer = !isDesktop;

            return Scaffold(
              backgroundColor: bg,

              // ✅ Drawer only on phone/tablet
              drawer: useDrawer
                  ? Drawer(
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      child: _AdminMenuPanel(
                        currentIndex: _currentIndex,
                        navItems: _navItems,
                        accountName: accountName,
                        accountEmail: accountEmail,
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
                          _openProfile();
                        },
                        onLogout: () {
                          Navigator.of(context).maybePop();
                          _logout();
                        },
                      ),
                    )
                  : null,

              body: Row(
                children: [
                  // ✅ Sidebar only on desktop
                  if (isDesktop)
                    SizedBox(
                      width: 280,
                      child: Material(
                        color: surface,
                        child: _AdminMenuPanel(
                          currentIndex: _currentIndex,
                          navItems: _navItems,
                          accountName: accountName,
                          accountEmail: accountEmail,
                          primary: primary,
                          hint: hint,
                          textDark: textDark,
                          surface: surface,
                          onSelect: _go,
                          onProfile: _openProfile,
                          onLogout: _logout,
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
                              // ✅ shared header controlled by dashboard (title changes)
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
                                        if (useDrawer)
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

                                        // ✅ Optional: keep actions if you want
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

                              // ✅ content (keeps state between tabs)
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

// ================= MODELS =================

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

// ================= SHARED ADMIN MENU (Drawer + Sidebar) =================

class _AdminMenuPanel extends StatelessWidget {
  final int currentIndex;
  final List<_NavItem> navItems;
  final String accountName;
  final String accountEmail;

  final Color primary;
  final Color hint;
  final Color textDark;
  final Color surface;

  final ValueChanged<int> onSelect;
  final VoidCallback onProfile;
  final VoidCallback onLogout;

  const _AdminMenuPanel({
    required this.currentIndex,
    required this.navItems,
    required this.accountName,
    required this.accountEmail,
    required this.primary,
    required this.hint,
    required this.textDark,
    required this.surface,
    required this.onSelect,
    required this.onProfile,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: surface,
      child: Column(
        children: [
          // ✅ Header
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
                Icon(Icons.security_rounded, size: 52, color: primary),
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
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ✅ Nav items
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
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

          const Spacer(),

          Divider(color: primary.withValues(alpha: 0.15), height: 18),

          // ✅ Paste these 2 blocks inside _AdminMenuPanel (same style as Student dashboard)
          // Put them ABOVE the Logout section (before the Divider + Logout InkWell)

          // ----------------- PROFILE BUTTON -----------------
          InkWell(
            onTap: onProfile,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    color: textDark.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Profile",
                    style: TextStyle(
                      color: textDark.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Divider(color: primary.withValues(alpha: 0.15), height: 18),

          // ✅ Logout
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
    );
  }
}

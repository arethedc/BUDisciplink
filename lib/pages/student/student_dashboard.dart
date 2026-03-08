import 'package:apps/pages/shared/handbook/handbook_sections_screen.dart';
import 'package:apps/pages/shared/handbook/handbook_ai_assistant_sheet.dart';
import 'package:apps/pages/shared/profile/unified_profile_page.dart';
import 'package:apps/pages/shared/welcome_screen_page.dart';
import 'package:apps/pages/shared/widgets/logout_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ✅ adjust these imports to your project paths
import 'student_home_page.dart';
import 'student_violations_page.dart';
import 'student_counseling_page.dart';
import 'student_notifications_page.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  int _currentIndex = 0;
  bool _showDesktopNotifications = false;

  // ================== THEME (keep Dashboard 2) ==================
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);
  static const surface = Color(0xFFFFFFFF);

  // ================== PAGES ==================
  final List<Widget> _pages = const [
    StudentHomePage(),
    HandbookSectionsScreen(),
    StudentViolationsPage(),
    StudentCounselingPage(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(Icons.home_rounded, 'Home'),
    _NavItem(Icons.menu_book_rounded, 'Handbook'),
    _NavItem(Icons.warning_rounded, 'Violations'),
    _NavItem(Icons.support_agent_rounded, 'Counseling'),
  ];

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return "Home";
      case 1:
        return "Student Handbook";
      case 2:
        return "Violations";
      case 3:
        return "Counseling";
      default:
        return "Student Portal";
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

  void _go(int i) => setState(() => _currentIndex = i);

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
    ).push(MaterialPageRoute(builder: (_) => const StudentNotificationsPage()));
  }

  Future<void> _openProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const UnifiedProfilePage()));
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
    return 'Student';
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

            // ✅ better responsiveness:
            // phone < 700, tablet 700-899 (still drawer+bottom nav), desktop >= 900 (sidebar)
            final bool isDesktop = w >= 900;
            final bool isPhoneOrTablet = !isDesktop;

            return Scaffold(
              backgroundColor: bg,

              // ✅ Drawer only for phone/tablet
              drawer: isPhoneOrTablet
                  ? Drawer(
                      child: _MenuPanel(
                        currentIndex: _currentIndex,
                        navItems: _navItems,
                        primary: primary,
                        hint: hint,
                        textDark: textDark,
                        surface: surface,
                        onSelect: (i) {
                          Navigator.of(context).maybePop(); // close drawer
                          _go(i);
                        },
                        onProfile: () {
                          Navigator.of(context).maybePop();
                          _openProfile();
                        },
                        onSettings: () {
                          Navigator.of(context).maybePop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Settings tapped")),
                          );
                        },
                        onLogout: () {
                          Navigator.of(context).maybePop();
                          _logout();
                        },
                        accountName: accountName,
                        accountEmail: accountEmail,
                      ),
                    )
                  : null,

              body: Row(
                children: [
                  // ✅ Permanent sidebar on desktop
                  if (isDesktop)
                    SizedBox(
                      width: 260,
                      child: Material(
                        color: surface,
                        child: _MenuPanel(
                          currentIndex: _currentIndex,
                          navItems: _navItems,
                          primary: primary,
                          hint: hint,
                          textDark: textDark,
                          surface: surface,
                          onSelect: _go,
                          onProfile: () {
                            _openProfile();
                          },
                          onSettings: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Settings tapped")),
                            );
                          },
                          onLogout: _logout,
                          accountName: accountName,
                          accountEmail: accountEmail,
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
                              // ✅ One shared header controlled by dashboard (title changes per tab)
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

                              // ✅ Page content (keeps tab state)
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
                            child: _DesktopNotificationsPanel(
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

              // ✅ Bottom nav only for phone/tablet
              bottomNavigationBar: isPhoneOrTablet
                  ? BottomNavigationBar(
                      currentIndex: _currentIndex,
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

              floatingActionButton: FloatingActionButton(
                backgroundColor: primary,
                onPressed: () => showHandbookAiAssistantSheet(context),
                child: const Icon(Icons.chat, color: Colors.white),
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
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  final String accountName;
  final String accountEmail;

  const _MenuPanel({
    required this.currentIndex,
    required this.navItems,
    required this.primary,
    required this.hint,
    required this.textDark,
    required this.surface,
    required this.onSelect,
    required this.onProfile,
    required this.onSettings,
    required this.onLogout,
    required this.accountName,
    required this.accountEmail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: surface,
      child: Column(
        children: [
          // ✅ Account header
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
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ✅ Main nav
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

          // ✅ Profile
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

          // ✅ Settings
          InkWell(
            onTap: onSettings,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.settings_outlined,
                    color: textDark.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Settings",
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

class _DesktopNotificationsPanel extends StatefulWidget {
  final String uid;
  final VoidCallback onClose;
  final Future<void> Function() onSeeAll;

  const _DesktopNotificationsPanel({
    required this.uid,
    required this.onClose,
    required this.onSeeAll,
  });

  @override
  State<_DesktopNotificationsPanel> createState() =>
      _DesktopNotificationsPanelState();
}

class _DesktopNotificationsPanelState
    extends State<_DesktopNotificationsPanel> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots();

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 430,
        minWidth: 380,
        maxHeight: 600,
      ),
      child: Material(
        color: Colors.white,
        elevation: 18,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF1B5E20).withValues(alpha: 0.22),
            ),
          ),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  height: 260,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final docs = snap.data!.docs;
              final visible = _showAll ? docs : docs.take(5).toList();
              final hasMore = docs.length > visible.length;

              final newList = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final yesterdayList =
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final olderList = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              for (final doc in visible) {
                final createdAt = _toDate(doc.data()['createdAt']);
                if (_isToday(createdAt)) {
                  newList.add(doc);
                } else if (_isYesterday(createdAt)) {
                  yesterdayList.add(doc);
                } else {
                  olderList.add(doc);
                }
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                    child: Row(
                      children: [
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            color: Color(0xFF1F2A1F),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            await widget.onSeeAll();
                          },
                          child: const Text('See all'),
                        ),
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF6D7F62),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (docs.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'No notifications yet.',
                          style: TextStyle(
                            color: Color(0xFF6D7F62),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: ListView(
                          padding: const EdgeInsets.all(10),
                          children: [
                            if (newList.isNotEmpty)
                              _buildSection('New', newList),
                            if (yesterdayList.isNotEmpty)
                              _buildSection('Yesterday', yesterdayList),
                            if (olderList.isNotEmpty)
                              _buildSection('Other days', olderList),
                            if (hasMore)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _showAll = true),
                                  icon: const Icon(Icons.history_rounded),
                                  label: const Text(
                                    'See previous notifications',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    String title,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF6D7F62),
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.2,
              ),
            ),
          ),
          ...docs.map(_buildNotificationTile),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final title = _safeText(d['title']).isEmpty
        ? 'Notification'
        : _safeText(d['title']);
    final body = _safeText(d['body']);
    final createdAt = _toDate(d['createdAt']);
    final isUnread = _toDate(d['readAt']) == null;

    return InkWell(
      onTap: () async {
        await _markReadIfNeeded(doc);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: isUnread
              ? const Color(0xFF1B5E20).withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnread
                ? const Color(0xFF1B5E20).withValues(alpha: 0.30)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isUnread
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: isUnread
                  ? const Color(0xFF1B5E20)
                  : const Color(0xFF6D7F62),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF1F2A1F),
                      fontWeight: isUnread ? FontWeight.w900 : FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF425742),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmtDesktopNotifTime(createdAt),
              style: const TextStyle(
                color: Color(0xFF6D7F62),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markReadIfNeeded(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final d = doc.data();
    if (_toDate(d['readAt']) != null) return;
    try {
      await doc.reference.update({'readAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }
}

String _safeText(dynamic value) => (value ?? '').toString().trim();

DateTime? _toDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  return null;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _isToday(DateTime? dateTime) {
  if (dateTime == null) return false;
  return _isSameDay(dateTime, DateTime.now());
}

bool _isYesterday(DateTime? dateTime) {
  if (dateTime == null) return false;
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  return _isSameDay(dateTime, yesterday);
}

String _fmtDesktopNotifTime(DateTime? dateTime) {
  if (dateTime == null) return 'Now';
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return 'Now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (_isYesterday(dateTime)) return 'Yesterday';
  return '${dateTime.month}/${dateTime.day}';
}

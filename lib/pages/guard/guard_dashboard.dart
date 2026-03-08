import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/handbook/handbook_sections_screen.dart';
import '../shared/handbook/handbook_ai_assistant_sheet.dart';
import '../shared/profile/unified_profile_page.dart';
import '../shared/welcome_screen_page.dart';
import '../shared/widgets/logout_confirm_dialog.dart';

class GuardDashboard extends StatefulWidget {
  const GuardDashboard({super.key});

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [HandbookSectionsScreen()];

  final List<_NavItem> _navItems = const [
    _NavItem(Icons.home, 'Home'),
    _NavItem(Icons.menu_book, 'Handbook'),
    _NavItem(Icons.warning, 'Violations'),
    _NavItem(Icons.support_agent, 'Counseling'),
  ];

  void _setIndex(int i) {
    final maxIndex = _pages.isEmpty ? 0 : _pages.length - 1;
    final clamped = i.clamp(0, maxIndex);
    setState(() => _currentIndex = clamped);
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
    return 'Guard';
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
            final bool isDesktop = constraints.maxWidth >= 900;
            final int safeIndex = _pages.isEmpty
                ? 0
                : _currentIndex.clamp(0, _pages.length - 1);

            return Scaffold(
              // ✅ AppBar ONLY on mobile
              appBar: isDesktop
                  ? null
                  : AppBar(
                      backgroundColor: Colors.green,
                      title: const Text(
                        'Student Portal',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

              drawer: isDesktop
                  ? null
                  : _buildMobileDrawer(accountName, accountEmail),

              body: Row(
                children: [
                  // ================= SIDEBAR (DESKTOP) =================
                  if (isDesktop) _buildSidebar(accountName, accountEmail),

                  // ================= MAIN CONTENT =================
                  Expanded(
                    child: Column(
                      children: [
                        // ✅ DESKTOP HEADER (PART OF LAYOUT, NOT OVERLAY)
                        if (isDesktop)
                          Container(
                            height: kToolbarHeight,
                            width: double.infinity,
                            color: Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.centerLeft,
                            child: const Text(
                              'Student Portal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                        // PAGE CONTENT
                        Expanded(
                          child: IndexedStack(
                            index: safeIndex,
                            children: _pages,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ✅ Bottom nav ONLY on mobile
              bottomNavigationBar: isDesktop ? null : _buildBottomNavigation(),

              floatingActionButton: FloatingActionButton(
                backgroundColor: Colors.green,
                onPressed: () => showHandbookAiAssistantSheet(context),
                child: const Icon(Icons.chat),
              ),
            );
          },
        );
      },
    );
  }

  // ================= MOBILE DRAWER =================

  Widget _buildMobileDrawer(String accountName, String accountEmail) {
    return Drawer(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Column(
        children: [
          _buildMobileAccountHeader(accountName, accountEmail),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              Navigator.pop(context);
              _openProfile();
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () => Navigator.pop(context),
          ),

          const Spacer(),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  // ================= SIDEBAR (DESKTOP) =================

  Widget _buildSidebar(String accountName, String accountEmail) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          // 👤 ACCOUNT HEADER (LEFT ALIGNED)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.account_circle, size: 48, color: Colors.green),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accountName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      accountEmail,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(),

          // MAIN NAV ITEMS
          ..._navItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;

            return _SidebarItem(
              icon: item.icon,
              label: item.label,
              isActive: _currentIndex == index,
              onTap: () {
                _setIndex(index);
              },
            );
          }),

          const Spacer(),
          const Divider(),

          _SidebarItem(
            icon: Icons.person,
            label: 'Profile',
            isActive: false,
            onTap: _openProfile,
          ),
          _SidebarItem(
            icon: Icons.settings,
            label: 'Settings',
            isActive: false,
            onTap: () {},
          ),

          const Divider(),

          _SidebarItem(
            icon: Icons.logout,
            label: 'Logout',
            isActive: false,
            isDanger: true,
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  // ================= BOTTOM NAV =================

  Widget _buildBottomNavigation() {
    return BottomNavigationBar(
      currentIndex: _pages.isEmpty
          ? 0
          : _currentIndex.clamp(0, _pages.length - 1),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.green,
      unselectedItemColor: Colors.grey,
      onTap: _setIndex,
      items: _navItems
          .map(
            (item) => BottomNavigationBarItem(
              icon: Icon(item.icon),
              label: item.label,
            ),
          )
          .toList(),
    );
  }

  // ================= MOBILE HEADER =================

  Widget _buildMobileAccountHeader(String accountName, String accountEmail) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.account_circle, size: 64, color: Colors.green),
          const SizedBox(height: 12),
          Text(
            accountName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 4),
          Text(accountEmail, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// ================= MODELS =================

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

// ================= SIDEBAR ITEM =================

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDanger;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger
        ? Colors.red
        : isActive
        ? Colors.green
        : Colors.black87;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: isActive ? Colors.green.withValues(alpha: 0.1) : null,
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

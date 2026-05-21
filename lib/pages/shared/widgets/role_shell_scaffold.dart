import 'dart:async';

import 'package:apps/services/notification_sound_service.dart';
import 'package:apps/services/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_theme_tokens.dart';
import 'package:apps/services/app_firestore.dart';

class RoleShellScaffold extends StatelessWidget {
  final Color backgroundColor;
  final Color headerColor;
  final String title;
  final bool usesDrawerSidebar;
  final bool showPermanentSidebar;
  final Widget? drawer;
  final Widget? sidebar;
  final double sidebarWidth;
  final Widget content;
  final List<Widget>? headerActions;
  final VoidCallback? onNotificationsTap;
  final String? notificationsUid;
  final bool suppressIncomingNotificationToasts;
  final bool hideNotificationsBadge;
  final bool enableNotificationSound;
  final bool showDesktopOverlay;
  final Widget? desktopOverlay;
  final VoidCallback? onDismissDesktopOverlay;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final double headerHeight;
  final bool showBackButton;
  final VoidCallback? onBackPressed;

  const RoleShellScaffold({
    super.key,
    required this.backgroundColor,
    this.headerColor = AppColors.primary,
    required this.title,
    required this.usesDrawerSidebar,
    required this.showPermanentSidebar,
    this.drawer,
    this.sidebar,
    this.sidebarWidth = 260,
    required this.content,
    this.headerActions,
    this.onNotificationsTap,
    this.notificationsUid,
    this.suppressIncomingNotificationToasts = false,
    this.hideNotificationsBadge = false,
    this.enableNotificationSound = true,
    this.showDesktopOverlay = false,
    this.desktopOverlay,
    this.onDismissDesktopOverlay,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.headerHeight = kToolbarHeight,
    this.showBackButton = false,
    this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    final hasPermanentSidebar = showPermanentSidebar && sidebar != null;
    double resolveDrawerWidth() {
      final screenWidth = MediaQuery.sizeOf(context).width;
      if (screenWidth >= 600) return sidebarWidth;
      return (screenWidth * 0.84).clamp(sidebarWidth, 300.0).toDouble();
    }

    PreferredSizeWidget buildHeaderAppBar(bool withDrawer) {
      return AppBar(
        toolbarHeight: headerHeight,
        automaticallyImplyLeading: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: headerColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        leading: showBackButton && onBackPressed != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: onBackPressed,
              )
            : withDrawer
            ? Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded, color: Colors.white),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              )
            : null,
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (headerActions != null && headerActions!.isNotEmpty)
            ...headerActions!,
          if (onNotificationsTap != null)
            _NotificationBellButton(
              uid: notificationsUid,
              onTap: onNotificationsTap!,
              suppressIncomingToasts: suppressIncomingNotificationToasts,
              hideBadge: hideNotificationsBadge,
              enableSound: enableNotificationSound,
            ),
        ],
      );
    }

    Widget buildOverlayStack() {
      return Stack(
        children: [
          Positioned.fill(child: content),
          if (showDesktopOverlay && desktopOverlay != null) ...[
            if (onDismissDesktopOverlay != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onDismissDesktopOverlay,
                ),
              ),
            Positioned(top: 8, right: 14, child: desktopOverlay!),
          ],
        ],
      );
    }

    if (hasPermanentSidebar) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Row(
          children: [
            Container(
              width: sidebarWidth,
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  right: BorderSide(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(2, 0),
                  ),
                ],
              ),
              child: Material(color: Colors.transparent, child: sidebar!),
            ),
            Expanded(
              child: Scaffold(
                backgroundColor: backgroundColor,
                appBar: buildHeaderAppBar(false),
                body: buildOverlayStack(),
              ),
            ),
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(
        drawerTheme: const DrawerThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          endShape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        drawer: usesDrawerSidebar && drawer != null
            ? SizedBox(width: resolveDrawerWidth(), child: drawer!)
            : null,
        appBar: buildHeaderAppBar(usesDrawerSidebar && drawer != null),
        body: buildOverlayStack(),
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}

class _NotificationBellButton extends StatefulWidget {
  final String? uid;
  final VoidCallback onTap;
  final bool suppressIncomingToasts;
  final bool hideBadge;
  final bool enableSound;

  const _NotificationBellButton({
    required this.uid,
    required this.onTap,
    required this.suppressIncomingToasts,
    required this.hideBadge,
    required this.enableSound,
  });

  @override
  State<_NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<_NotificationBellButton> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<UserPreferenceEvent>? _prefsSub;
  final Set<String> _knownIds = <String>{};
  bool _primed = false;
  bool _soundEnabled = false;
  DateTime? _lastNotificationsOpenedAt;
  int _unreadCount = 0;
  OverlayEntry? _toastEntry;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _listenPreferenceUpdates();
    _refreshSoundPreference();
    _refreshNotificationsOpenedAt();
    _startListener();
  }

  @override
  void didUpdateWidget(covariant _NotificationBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.uid ?? '') != (widget.uid ?? '')) {
      _sub?.cancel();
      _knownIds.clear();
      _primed = false;
      _unreadCount = 0;
      _lastNotificationsOpenedAt = null;
      _prefsSub?.cancel();
      _listenPreferenceUpdates();
      _refreshSoundPreference();
      _refreshNotificationsOpenedAt();
      _startListener();
    }
  }

  void _listenPreferenceUpdates() {
    final uid = (widget.uid ?? '').trim();
    if (uid.isEmpty) return;
    _prefsSub = UserPreferencesService.changes
        .where((event) => event.uid == uid)
        .listen((event) {
          if (!mounted) return;
          setState(() => _soundEnabled = event.notificationSoundEnabled);
        });
  }

  Future<void> _refreshSoundPreference() async {
    final uid = (widget.uid ?? '').trim();
    if (uid.isEmpty) {
      if (mounted) setState(() => _soundEnabled = false);
      return;
    }
    final enabled = await UserPreferencesService.getNotificationSoundEnabled(
      uid,
    );
    if (!mounted) return;
    setState(() => _soundEnabled = enabled);
  }

  Future<void> _refreshNotificationsOpenedAt() async {
    final uid = (widget.uid ?? '').trim();
    if (uid.isEmpty) {
      if (mounted) setState(() => _lastNotificationsOpenedAt = null);
      return;
    }
    final loaded = await UserPreferencesService.getNotificationLastOpenedAt(
      uid,
    );
    if (!mounted) return;
    if ((widget.uid ?? '').trim() != uid) return;
    setState(() => _lastNotificationsOpenedAt = loaded);
  }

  void _startListener() {
    final uid = (widget.uid ?? '').trim();
    if (uid.isEmpty) return;
    _sub = AppFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(40)
        .snapshots()
        .listen(_onSnapshot);
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    final docs = snap.docs;
    final unreadIds = docs
        .where((d) => _isUnreadForBadge(d.data()))
        .map((d) => d.id)
        .toSet();
    final unread = unreadIds.length;
    if (mounted && unread != _unreadCount) {
      setState(() => _unreadCount = unread);
    }

    if (!_primed) {
      _knownIds.addAll(docs.map((d) => d.id));
      _primed = true;
      if (!widget.suppressIncomingToasts && mounted && unread > 0) {
        final label = unread == 1
            ? '1 new notification'
            : '$unread new notifications';
        _showIncomingToast(title: label, body: 'Tap to open notifications.');
        if (widget.enableSound && _soundEnabled) {
          NotificationSoundService.instance.play();
        }
      }
      return;
    }

    final incoming = docs.where((d) => !_knownIds.contains(d.id)).toList();
    if (incoming.isEmpty) return;
    _knownIds.addAll(incoming.map((d) => d.id));

    if (widget.suppressIncomingToasts || !mounted) return;
    final newest = incoming.first.data();
    _showIncomingToast(
      title: (newest['title'] ?? 'New notification').toString().trim(),
      body: (newest['body'] ?? '').toString().trim(),
    );
    if (widget.enableSound && _soundEnabled) {
      NotificationSoundService.instance.play();
    }
  }

  DateTime? _toDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  bool _isUnreadForBadge(Map<String, dynamic> data) {
    if (data['readAt'] != null) return false;
    final lastOpened = _lastNotificationsOpenedAt;
    if (lastOpened == null) return true;
    final createdAt = _toDate(data['createdAt']);
    if (createdAt == null) return false;
    return createdAt.isAfter(lastOpened);
  }

  void _showIncomingToast({required String title, required String body}) {
    _toastTimer?.cancel();
    _toastEntry?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final isDesktop = size.width >= 900;
        final toastWidth = isDesktop ? 360.0 : size.width - 24;
        return Positioned(
          right: isDesktop ? 16 : null,
          left: isDesktop ? null : 12,
          bottom: 16,
          width: toastWidth,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.onTap,
              child: Ink(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty ? 'New notification' : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.hint,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Dismiss',
                      onPressed: () {
                        _toastTimer?.cancel();
                        entry.remove();
                        _toastEntry = null;
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.hint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    _toastEntry = entry;
    _toastTimer = Timer(const Duration(seconds: 4), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  Future<void> _toggleSound() async {
    if (!widget.enableSound) {
      _showIncomingToast(
        title: 'Notification sound disabled',
        body: 'Sound is disabled for this role.',
      );
      return;
    }
    final next = !_soundEnabled;
    setState(() => _soundEnabled = next);
    final uid = (widget.uid ?? '').trim();
    if (uid.isNotEmpty) {
      await UserPreferencesService.setNotificationSoundEnabled(uid, next);
    }
    _showIncomingToast(
      title: next ? 'Notification sound on' : 'Notification sound off',
      body: 'You can change this in Profile > System Preferences.',
    );
    if (next) {
      NotificationSoundService.instance.play();
    }
  }

  void _acknowledgeCurrentUnread() {
    final uid = (widget.uid ?? '').trim();
    if (uid.isEmpty) return;
    final now = DateTime.now();
    _lastNotificationsOpenedAt = now;
    unawaited(UserPreferencesService.setNotificationLastOpenedAt(uid, now));
    if (mounted && _unreadCount != 0) {
      setState(() => _unreadCount = 0);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _prefsSub?.cancel();
    _toastTimer?.cancel();
    _toastEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayCount = _unreadCount > 99 ? '99+' : '$_unreadCount';
    final tooltipSuffix = widget.enableSound
        ? ' · Long press to toggle sound (${_soundEnabled ? 'On' : 'Off'})'
        : '';
    return IconButton(
      tooltip:
          'Notifications${_unreadCount > 0 ? ' ($_unreadCount unread)' : ''}$tooltipSuffix',
      onPressed: () {
        _acknowledgeCurrentUnread();
        widget.onTap();
      },
      onLongPress: widget.enableSound ? _toggleSound : null,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: widget.hideBadge
                ? const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  )
                : null,
            child: Icon(
              Icons.notifications_none_rounded,
              color: widget.hideBadge ? AppColors.primary : Colors.white,
            ),
          ),
          if (!widget.hideBadge && _unreadCount > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
                child: Text(
                  displayCount,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

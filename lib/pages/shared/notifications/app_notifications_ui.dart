import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:apps/pages/shared/widgets/app_layout_tokens.dart';

enum AppNotificationViewTarget { pendingApproval, violationAlert }

class AppNotificationViewIntent {
  final AppNotificationViewTarget target;
  final String? studentUid;
  final String? caseId;
  final String? caseCode;

  const AppNotificationViewIntent._({
    required this.target,
    this.studentUid,
    this.caseId,
    this.caseCode,
  });

  factory AppNotificationViewIntent.pendingApproval({
    required String studentUid,
  }) {
    return AppNotificationViewIntent._(
      target: AppNotificationViewTarget.pendingApproval,
      studentUid: studentUid,
    );
  }

  factory AppNotificationViewIntent.violationAlert({
    String? caseId,
    String? caseCode,
  }) {
    return AppNotificationViewIntent._(
      target: AppNotificationViewTarget.violationAlert,
      caseId: caseId,
      caseCode: caseCode,
    );
  }
}

typedef AppNotificationViewHandler =
    Future<void> Function(AppNotificationViewIntent intent);

enum _NotificationsFilter { all, unread }

Future<void> showAppNotificationsSheet({
  required BuildContext context,
  Future<void> Function()? onSeeAll,
  AppNotificationViewHandler? onViewNotification,
}) async {
  const bg = Colors.white;
  const textDark = Color(0xFF1F2A1F);
  const hint = Color(0xFF6D7F62);

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.30),
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      final modalWidth = (size.width - 16).clamp(300.0, 430.0).toDouble();
      final modalHeight = (size.height - 24).clamp(420.0, 620.0).toDouble();

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: modalWidth,
            minWidth: 280,
            maxHeight: modalHeight,
          ),
          child: Material(
            color: Colors.white,
            elevation: 18,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.22),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                      child: Row(
                        children: [
                          const Text(
                            'Notifications',
                            style: TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          if (onSeeAll != null)
                            TextButton(
                              onPressed: () async {
                                Navigator.of(dialogContext).maybePop();
                                await onSeeAll();
                              },
                              child: const Text('See all'),
                            ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () =>
                                Navigator.of(dialogContext).maybePop(),
                            icon: const Icon(Icons.close_rounded, color: hint),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: AppNotificationsContent(
                        onBack: () => Navigator.of(dialogContext).maybePop(),
                        onViewNotification: onViewNotification == null
                            ? null
                            : (intent) async {
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).maybePop();
                                }
                                await onViewNotification(intent);
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class AppNotificationsPage extends StatefulWidget {
  const AppNotificationsPage({super.key});

  @override
  State<AppNotificationsPage> createState() => _AppNotificationsPageState();
}

class _AppNotificationsPageState extends State<AppNotificationsPage> {
  _NotificationsFilter _filter = _NotificationsFilter.all;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1B5E20);
    const bg = Colors.white;
    const muted = Color(0xFF6D7F62);

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

    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContentWidth = constraints.maxWidth >= 900
                ? 860.0
                : constraints.maxWidth;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _ErrorState(error: snap.error.toString());
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snap.data!.docs.toList();
                    final unreadCount = docs
                        .where((doc) => _toDate(doc.data()['readAt']) == null)
                        .length;
                    final filteredDocs = _filter == _NotificationsFilter.unread
                        ? docs
                              .where(
                                (doc) => _toDate(doc.data()['readAt']) == null,
                              )
                              .toList()
                        : docs;

                    final source = filteredDocs;
                    final visible = source;
                    final newList =
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final yesterdayList =
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final olderList =
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
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

                    return Container(
                      height: (constraints.maxHeight - 28).clamp(260.0, 1200.0),
                      margin: const EdgeInsets.all(14),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildNotificationsFilterBar(
                            selected: _filter,
                            unreadCount: unreadCount,
                            onChanged: (next) {
                              if (_filter == next) return;
                              setState(() {
                                _filter = next;
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                if (source.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Text(
                                      _filter == _NotificationsFilter.unread
                                          ? 'No unread notifications.'
                                          : 'No notifications yet.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: muted,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                if (newList.isNotEmpty)
                                  _buildPageNotificationSection(
                                    title: 'New',
                                    docs: newList,
                                    onOpen: (doc) => _openDetails(context, doc),
                                  ),
                                if (yesterdayList.isNotEmpty)
                                  _buildPageNotificationSection(
                                    title: 'Yesterday',
                                    docs: yesterdayList,
                                    onOpen: (doc) => _openDetails(context, doc),
                                  ),
                                if (olderList.isNotEmpty)
                                  _buildPageNotificationSection(
                                    title: 'Other days',
                                    docs: olderList,
                                    onOpen: (doc) => _openDetails(context, doc),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openDetails(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final d = doc.data();

    if (_toDate(d['readAt']) == null) {
      try {
        await doc.reference.update({'readAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    }

    if (!context.mounted) return;
    await _showNotificationDetailsDialog(context: context, data: d);
  }
}

class AppNotificationsContent extends StatefulWidget {
  final VoidCallback? onBack;
  final AppNotificationViewHandler? onViewNotification;

  const AppNotificationsContent({
    super.key,
    this.onBack,
    this.onViewNotification,
  });

  @override
  State<AppNotificationsContent> createState() =>
      _AppNotificationsContentState();
}

class _AppNotificationsContentState extends State<AppNotificationsContent> {
  _NotificationsFilter _filter = _NotificationsFilter.all;

  @override
  Widget build(BuildContext context) {
    const bg = Colors.white;
    const muted = Color(0xFF6D7F62);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
        child: Text(
          'Not logged in',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return Container(
      color: bg,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContentWidth = constraints.maxWidth >= 900
                ? 860.0
                : constraints.maxWidth;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: stream,
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return _ErrorState(error: snap.error.toString());
                            }
                            if (!snap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final docs = snap.data!.docs.toList();
                            final unreadCount = docs
                                .where(
                                  (doc) =>
                                      _toDate(doc.data()['readAt']) == null,
                                )
                                .length;
                            final filteredDocs =
                                _filter == _NotificationsFilter.unread
                                ? docs
                                      .where(
                                        (doc) =>
                                            _toDate(doc.data()['readAt']) ==
                                            null,
                                      )
                                      .toList()
                                : docs;

                            final source = filteredDocs;
                            final visible = source;
                            final newList =
                                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                            final yesterdayList =
                                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                            final olderList =
                                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                            for (final doc in visible) {
                              final createdAt = _toDate(
                                doc.data()['createdAt'],
                              );
                              if (_isToday(createdAt)) {
                                newList.add(doc);
                              } else if (_isYesterday(createdAt)) {
                                yesterdayList.add(doc);
                              } else {
                                olderList.add(doc);
                              }
                            }

                            return Container(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Column(
                                children: [
                                  _buildNotificationsFilterBar(
                                    selected: _filter,
                                    unreadCount: unreadCount,
                                    onChanged: (next) {
                                      if (_filter == next) return;
                                      setState(() {
                                        _filter = next;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: ListView(
                                      padding: EdgeInsets.zero,
                                      children: [
                                        if (source.isEmpty)
                                          Padding(
                                            padding: const EdgeInsets.all(18),
                                            child: Text(
                                              _filter ==
                                                      _NotificationsFilter
                                                          .unread
                                                  ? 'No unread notifications.'
                                                  : 'No notifications yet.',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: muted,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        if (newList.isNotEmpty)
                                          _buildPageNotificationSection(
                                            title: 'New',
                                            docs: newList,
                                            onOpen: (doc) =>
                                                _openDetails(context, doc),
                                          ),
                                        if (yesterdayList.isNotEmpty)
                                          _buildPageNotificationSection(
                                            title: 'Yesterday',
                                            docs: yesterdayList,
                                            onOpen: (doc) =>
                                                _openDetails(context, doc),
                                          ),
                                        if (olderList.isNotEmpty)
                                          _buildPageNotificationSection(
                                            title: 'Other days',
                                            docs: olderList,
                                            onOpen: (doc) =>
                                                _openDetails(context, doc),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openDetails(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final d = doc.data();

    if (_toDate(d['readAt']) == null) {
      try {
        await doc.reference.update({'readAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    }

    if (!context.mounted) return;
    await _showNotificationDetailsDialog(
      context: context,
      data: d,
      onViewNotification: widget.onViewNotification,
    );
  }
}

class DesktopNotificationsPanel extends StatefulWidget {
  final String uid;
  final VoidCallback onClose;
  final Future<void> Function() onSeeAll;
  final AppNotificationViewHandler? onViewNotification;

  const DesktopNotificationsPanel({
    super.key,
    required this.uid,
    required this.onClose,
    required this.onSeeAll,
    this.onViewNotification,
  });

  @override
  State<DesktopNotificationsPanel> createState() =>
      _DesktopNotificationsPanelState();
}

class _DesktopNotificationsPanelState extends State<DesktopNotificationsPanel> {
  _NotificationsFilter _filter = _NotificationsFilter.all;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
              final unreadCount = docs
                  .where((doc) => _toDate(doc.data()['readAt']) == null)
                  .length;
              final source = _filter == _NotificationsFilter.unread
                  ? docs
                        .where((doc) => _toDate(doc.data()['readAt']) == null)
                        .toList()
                  : docs;
              final visible = source;

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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    child: _buildNotificationsFilterBar(
                      selected: _filter,
                      unreadCount: unreadCount,
                      onChanged: (next) {
                        if (_filter == next) return;
                        setState(() {
                          _filter = next;
                        });
                      },
                    ),
                  ),
                  if (source.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          _filter == _NotificationsFilter.unread
                              ? 'No unread notifications.'
                              : 'No notifications yet.',
                          style: const TextStyle(
                            color: Color(0xFF6D7F62),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(10),
                          children: [
                            if (newList.isNotEmpty)
                              _buildSection('New', newList),
                            if (yesterdayList.isNotEmpty)
                              _buildSection('Yesterday', yesterdayList),
                            if (olderList.isNotEmpty)
                              _buildSection('Other days', olderList),
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
    final title = _safeStr(d['title']).isEmpty
        ? 'Notification'
        : _safeStr(d['title']);
    final body = _safeStr(d['body']);
    final createdAt = _toDate(d['createdAt']);
    final isUnread = _toDate(d['readAt']) == null;

    return InkWell(
      onTap: () async {
        await _openTileDetails(doc);
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

  Future<void> _openTileDetails(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    await _markReadIfNeeded(doc);
    if (!mounted) return;
    await _showNotificationDetailsDialog(
      context: context,
      data: data,
      onViewNotification: widget.onViewNotification,
    );
  }
}

class _NotificationDetailItem {
  final String label;
  final String value;
  const _NotificationDetailItem({required this.label, required this.value});
}

Future<void> _showNotificationDetailsDialog({
  required BuildContext context,
  required Map<String, dynamic> data,
  AppNotificationViewHandler? onViewNotification,
}) async {
  const primary = Color(0xFF1B5E20);
  const hint = Color(0xFF6D7F62);

  final payload = _payloadAsMap(data['payload']);
  final intent = _extractNotificationViewIntent(data: data, payload: payload);
  final canView = intent != null && onViewNotification != null;
  final initialDetails = _buildNotificationDetails(
    data: data,
    payload: payload,
    intent: intent,
  );
  final detailsFuture =
      intent?.target == AppNotificationViewTarget.violationAlert
      ? _buildLiveViolationDetails(
          data: data,
          payload: payload,
          intent: intent!,
          fallback: initialDetails,
        )
      : null;
  final title = _safeStr(data['title']).isEmpty
      ? 'Notification'
      : _safeStr(data['title']);
  final body = _safeStr(data['body']);

  final wantsView =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
            title: Row(
              children: [
                const Expanded(child: SizedBox.shrink()),
                IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, color: hint),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.06),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body.isEmpty
                          ? 'Review the notification details below.'
                          : body,
                      style: const TextStyle(
                        color: hint,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        canView
                            ? 'You can open this item directly from here.'
                            : 'This notification is for reference only.',
                        style: const TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (detailsFuture != null)
                      FutureBuilder<List<_NotificationDetailItem>>(
                        future: detailsFuture,
                        initialData: initialDetails,
                        builder: (context, snapshot) {
                          final details = snapshot.data ?? initialDetails;
                          return _buildNotificationDetailsCard(details);
                        },
                      )
                    else
                      _buildNotificationDetailsCard(initialDetails),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                onPressed: !canView
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text(
                  'View',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ) ??
      false;

  if (!wantsView || intent == null || onViewNotification == null) return;
  await onViewNotification(intent);
}

Widget _buildNotificationDetailsCard(List<_NotificationDetailItem> details) {
  const primary = Color(0xFF1B5E20);
  const hint = Color(0xFF6D7F62);
  const textDark = Color(0xFF1F2A1F);

  if (details.isEmpty) return const SizedBox.shrink();
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FBF8),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Details',
          style: TextStyle(color: primary, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        ...details.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: hint,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
                children: [
                  TextSpan(
                    text: '${entry.label}: ',
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(text: entry.value),
                ],
              ),
            ),
          );
        }),
      ],
    ),
  );
}

Widget _buildNotificationsFilterBar({
  required _NotificationsFilter selected,
  required int unreadCount,
  required ValueChanged<_NotificationsFilter> onChanged,
}) {
  const filterRadius = AppRadii.md;
  final options = <(_NotificationsFilter, String)>[
    (_NotificationsFilter.all, 'All'),
    (
      _NotificationsFilter.unread,
      unreadCount <= 0 ? 'Unread' : 'Unread ($unreadCount)',
    ),
  ];

  Widget filterTab(_NotificationsFilter value, String label) {
    final selectedTab = selected == value;
    return InkWell(
      borderRadius: BorderRadius.circular(filterRadius),
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selectedTab
              ? const Color(0xFF1B5E20).withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(filterRadius),
          border: Border.all(
            color: selectedTab
                ? const Color(0xFF1B5E20).withValues(alpha: 0.36)
                : Colors.black.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selectedTab
                ? const Color(0xFF1B5E20)
                : const Color(0xFF1F2A1F),
            fontWeight: selectedTab ? FontWeight.w900 : FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  return Align(
    alignment: Alignment.centerLeft,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            filterTab(options[i].$1, options[i].$2),
            if (i != options.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    ),
  );
}

Widget _buildPageNotificationSection({
  required String title,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  required Future<void> Function(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  )
  onOpen,
}) {
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
        ...docs.map(
          (doc) => _buildPageNotificationTile(doc: doc, onOpen: onOpen),
        ),
      ],
    ),
  );
}

Widget _buildPageNotificationTile({
  required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  required Future<void> Function(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  )
  onOpen,
}) {
  const primary = Color(0xFF1B5E20);
  const muted = Color(0xFF6D7F62);

  final d = doc.data();
  final title = _safeStr(d['title']).isEmpty
      ? 'Notification'
      : _safeStr(d['title']);
  final body = _safeStr(d['body']);
  final createdAt = _toDate(d['createdAt']);
  final isUnread = _toDate(d['readAt']) == null;

  return InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () async {
      await onOpen(doc);
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUnread
              ? primary.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.08),
          width: isUnread ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isUnread
                  ? primary.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isUnread
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: isUnread ? primary : muted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: isUnread
                              ? FontWeight.w900
                              : FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      createdAt == null ? '--' : _fmtWhen(createdAt),
                      style: const TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: muted,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<List<_NotificationDetailItem>> _buildLiveViolationDetails({
  required Map<String, dynamic> data,
  required Map<String, dynamic> payload,
  required AppNotificationViewIntent intent,
  required List<_NotificationDetailItem> fallback,
}) async {
  try {
    final live = await _fetchViolationCaseData(
      data: data,
      payload: payload,
      intent: intent,
    );
    if (live == null) return fallback;

    final details = _buildViolationNotificationDetails(
      data: data,
      payload: payload,
      live: live,
    );
    return details.isEmpty ? fallback : details;
  } catch (_) {
    return fallback;
  }
}

Future<Map<String, dynamic>?> _fetchViolationCaseData({
  required Map<String, dynamic> data,
  required Map<String, dynamic> payload,
  required AppNotificationViewIntent intent,
}) async {
  final db = FirebaseFirestore.instance;
  final directCaseId = _safeStr(intent.caseId).isNotEmpty
      ? _safeStr(intent.caseId)
      : _safeStr(data['caseId']);

  if (directCaseId.isNotEmpty) {
    final byId = await db.collection('violation_cases').doc(directCaseId).get();
    if (byId.exists) {
      final found = byId.data() ?? <String, dynamic>{};
      return <String, dynamic>{'__docId': byId.id, ...found};
    }
  }

  final code = _safeStr(intent.caseCode).isNotEmpty
      ? _safeStr(intent.caseCode)
      : _safeStr(payload['caseCode']);
  if (code.isEmpty) return null;

  final byCode = await db
      .collection('violation_cases')
      .where('caseCode', isEqualTo: code)
      .limit(1)
      .get();
  if (byCode.docs.isEmpty) return null;
  final doc = byCode.docs.first;
  return <String, dynamic>{'__docId': doc.id, ...doc.data()};
}

Map<String, dynamic> _payloadAsMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

AppNotificationViewIntent? _extractNotificationViewIntent({
  required Map<String, dynamic> data,
  required Map<String, dynamic> payload,
}) {
  final payloadType = _safeStr(payload['type']).toLowerCase();
  final studentUid = _safeStr(payload['studentUid']);
  if (payloadType == 'student_profile_pending_approval' &&
      studentUid.isNotEmpty) {
    return AppNotificationViewIntent.pendingApproval(studentUid: studentUid);
  }

  final caseId = _safeStr(payload['caseId']).isNotEmpty
      ? _safeStr(payload['caseId'])
      : _safeStr(data['caseId']);
  final caseCode = _safeStr(payload['caseCode']);
  final event = _safeStr(payload['event']).toLowerCase();
  final title = _safeStr(data['title']).toLowerCase();
  final body = _safeStr(data['body']).toLowerCase();

  final looksLikeViolation =
      caseId.isNotEmpty ||
      caseCode.isNotEmpty ||
      event.contains('report') ||
      title.contains('violation') ||
      body.contains('violation') ||
      title.contains('case update');

  if (looksLikeViolation && (caseId.isNotEmpty || caseCode.isNotEmpty)) {
    return AppNotificationViewIntent.violationAlert(
      caseId: caseId.isEmpty ? null : caseId,
      caseCode: caseCode.isEmpty ? null : caseCode,
    );
  }
  return null;
}

List<_NotificationDetailItem> _buildNotificationDetails({
  required Map<String, dynamic> data,
  required Map<String, dynamic> payload,
  required AppNotificationViewIntent? intent,
}) {
  final createdAt = _toDate(data['createdAt']);
  final details = <_NotificationDetailItem>[];
  final type = _safeStr(payload['type']).toLowerCase();
  final isViolationReportNotification =
      type == 'violation_report_submitted' ||
      intent?.target == AppNotificationViewTarget.violationAlert;

  if (type == 'student_profile_pending_approval') {
    details.add(
      const _NotificationDetailItem(label: 'Type', value: 'Pending Approval'),
    );
    _addDetail(details, 'Student', payload['studentName']);
    _addDetail(details, 'Student Number', payload['studentNo']);
    _addDetail(details, 'College', payload['collegeId']);
    _addDetail(details, 'Program', payload['programId']);
    if (createdAt != null) {
      details.add(
        _NotificationDetailItem(label: 'Received', value: _fmtWhen(createdAt)),
      );
    }
    return details;
  }

  if (isViolationReportNotification) {
    details.addAll(
      _buildViolationNotificationDetails(
        data: data,
        payload: payload,
        live: null,
      ),
    );
    return details;
  }

  for (final entry in payload.entries.take(8)) {
    final value = _valueToDisplayString(entry.value);
    if (value == '--') continue;
    details.add(
      _NotificationDetailItem(
        label: _humanizePayloadKey(entry.key),
        value: value,
      ),
    );
  }
  if (createdAt != null) {
    details.add(
      _NotificationDetailItem(label: 'Received', value: _fmtWhen(createdAt)),
    );
  }
  return details;
}

List<_NotificationDetailItem> _buildViolationNotificationDetails({
  required Map<String, dynamic> data,
  required Map<String, dynamic> payload,
  required Map<String, dynamic>? live,
}) {
  final details = <_NotificationDetailItem>[];
  final kind = _classifyViolationNotification(
    data: data,
    payload: payload,
    live: live,
  );
  final caseCode = _firstNonEmpty([
    live?['caseCode'],
    payload['caseCode'],
    data['caseCode'],
  ]);
  final createdAt = _toDate(data['createdAt']) ?? _toDate(live?['createdAt']);
  final concern = _humanizeSnakeOrTitle(
    _firstNonEmpty([live?['concern'], payload['concern']]),
  );
  final category = _firstNonEmpty([
    live?['categoryNameSnapshot'],
    live?['categoryName'],
    payload['categoryName'],
  ]);
  final violation = _firstNonEmpty([
    live?['violationTypeLabel'],
    live?['violationNameSnapshot'],
    live?['typeNameSnapshot'],
    live?['violationName'],
    payload['violationTypeLabel'],
  ]);
  final reportedBy = _formatReporterDisplay(
    name: _firstNonEmpty([live?['reportedByName'], payload['reportedByName']]),
    role: _firstNonEmpty([live?['reportedByRole'], payload['reportedByRole']]),
  );
  final incidentAt = _toDate(payload['incidentAt']) ?? _toDate(live?['incidentAt']);
  final action = _humanizeSnakeOrTitle(
    _firstNonEmpty([
      live?['actionSelected'],
      live?['actionType'],
      live?['actionTypeCode'],
      payload['actionSelected'],
      payload['actionTypeCode'],
    ]),
  );
  final severity = _humanizeSnakeOrTitle(
    _firstNonEmpty([live?['finalSeverity'], payload['finalSeverity']]),
  );
  final sanction = _humanizeSnakeOrTitle(
    _firstNonEmpty([
      live?['sanctionType'],
      live?['sanctionTypeCode'],
      payload['sanctionType'],
      payload['sanctionTypeCode'],
    ]),
  );
  final meetingRequired = _yesNoDisplay(
    live?['meetingRequired'] ?? payload['meetingRequired'],
  );
  final meetingStatus = _humanizeSnakeOrTitle(
    _firstNonEmpty([live?['meetingStatus'], payload['meetingStatus']]),
  );
  final scheduledAt = _toDate(payload['scheduledAt']) ?? _toDate(live?['scheduledAt']);
  final bookingDeadlineAt =
      _toDate(payload['bookingDeadlineAt']) ?? _toDate(live?['bookingDeadlineAt']);
  final status = _humanizeSnakeOrTitle(
    _firstNonEmpty([payload['status'], live?['status']]),
  );
  final reason = _humanizeSnakeOrTitle(
    _firstNonEmpty([payload['reason'], live?['actionReason']]),
  );

  if (caseCode.isNotEmpty) {
    details.add(_NotificationDetailItem(label: 'Case Code', value: caseCode));
  }

  switch (kind) {
    case 'report_submitted':
      _addDetail(details, 'Concern', concern);
      _addDetail(details, 'Category', category);
      _addDetail(details, 'Violation Type', violation);
      if (createdAt != null) {
        details.add(
          _NotificationDetailItem(
            label: 'Date Reported',
            value: _fmtDetailDateTime(createdAt),
          ),
        );
      }
      if (incidentAt != null) {
        details.add(
          _NotificationDetailItem(
            label: 'Date of Incident',
            value: _fmtDetailDateTime(incidentAt),
          ),
        );
      }
      _addDetail(details, 'Reported By', reportedBy);
      break;
    case 'osa_action_set':
      _addDetail(details, 'Action', action);
      _addDetail(details, 'Severity', severity);
      _addDetail(details, 'Meeting Required', meetingRequired);
      if (bookingDeadlineAt != null) {
        details.add(
          _NotificationDetailItem(
            label: 'Booking Deadline',
            value: _fmtDetailDateTime(bookingDeadlineAt),
          ),
        );
      }
      _addDetail(details, 'Status', status);
      break;
    case 'appointment_booked':
      _addDetail(details, 'Action', action);
      if (scheduledAt != null) {
        details.add(
          _NotificationDetailItem(
            label: 'Scheduled Meeting',
            value: _fmtDetailDateTime(scheduledAt),
          ),
        );
      }
      _addDetail(details, 'Meeting Status', meetingStatus);
      break;
    case 'booking_window_extended':
      _addDetail(details, 'Action', action);
      if (bookingDeadlineAt != null) {
        details.add(
          _NotificationDetailItem(
            label: 'New Booking Deadline',
            value: _fmtDetailDateTime(bookingDeadlineAt),
          ),
        );
      }
      _addDetail(details, 'Meeting Status', meetingStatus);
      break;
    case 'booking_missed':
      _addDetail(details, 'Action', action);
      if (bookingDeadlineAt != null) {
        details.add(
          _NotificationDetailItem(
            label: 'Booking Deadline',
            value: _fmtDetailDateTime(bookingDeadlineAt),
          ),
        );
      }
      _addDetail(details, 'Meeting Status', meetingStatus);
      _addDetail(details, 'Status', status);
      break;
    case 'meeting_missed':
      _addDetail(details, 'Action', action);
      if (scheduledAt != null) {
        details.add(
          _NotificationDetailItem(
            label: 'Missed Meeting',
            value: _fmtDetailDateTime(scheduledAt),
          ),
        );
      }
      _addDetail(details, 'Meeting Status', meetingStatus);
      _addDetail(details, 'Status', status);
      break;
    case 'meeting_completed':
    case 'case_resolved':
    case 'case_resolved_without_meeting':
      _addDetail(details, 'Action', action);
      _addDetail(details, 'Severity', severity);
      _addDetail(details, 'Sanction', sanction);
      _addDetail(details, 'Status', status);
      break;
    case 'case_unresolved':
      _addDetail(details, 'Action', action);
      _addDetail(details, 'Meeting Status', meetingStatus);
      _addDetail(details, 'Reason', reason);
      _addDetail(details, 'Status', status);
      break;
    case 'meeting_rescheduled':
      _addDetail(details, 'Action', action);
      if (bookingDeadlineAt != null) {
        details.add(
          _NotificationDetailItem(
            label: 'Booking Deadline',
            value: _fmtDetailDateTime(bookingDeadlineAt),
          ),
        );
      }
      _addDetail(details, 'Reason', reason);
      _addDetail(details, 'Meeting Status', meetingStatus);
      break;
    case 'case_reopened':
      _addDetail(details, 'Action', action);
      _addDetail(details, 'Reason', reason);
      _addDetail(details, 'Status', status);
      break;
    default:
      _addDetail(details, 'Concern', concern);
      _addDetail(details, 'Category', category);
      _addDetail(details, 'Violation Type', violation);
      _addDetail(details, 'Action', action);
      _addDetail(details, 'Meeting Status', meetingStatus);
      _addDetail(details, 'Status', status);
      break;
  }

  return details;
}

String _classifyViolationNotification({
  required Map<String, dynamic> data,
  required Map<String, dynamic> payload,
  required Map<String, dynamic>? live,
}) {
  final event = _safeStr(payload['event']).toLowerCase();
  if (event.isNotEmpty) {
    return event;
  }

  final type = _safeStr(payload['type']).toLowerCase();
  if (type == 'violation_report_submitted') {
    return 'report_submitted';
  }

  final title = _safeStr(data['title']).toLowerCase();
  final body = _safeStr(data['body']).toLowerCase();
  final status = _safeStr(payload['status']).toLowerCase();
  final meetingStatus = _firstNonEmpty([
    payload['meetingStatus'],
    live?['meetingStatus'],
  ]).toLowerCase();

  if (title.contains('new violation report') ||
      title.contains('violation report submitted') ||
      body.contains('new violation report')) {
    return 'report_submitted';
  }
  if (title.contains('osa action set')) return 'osa_action_set';
  if (title.contains('meeting booked')) return 'appointment_booked';
  if (title.contains('booking window extended')) {
    return 'booking_window_extended';
  }
  if (title.contains('booking window missed') ||
      meetingStatus.contains('booking_missed')) {
    return 'booking_missed';
  }
  if (title.contains('meeting missed') ||
      meetingStatus.contains('meeting_missed')) {
    return 'meeting_missed';
  }
  if (title.contains('case set to unresolved') ||
      status.contains('unresolved')) {
    return 'case_unresolved';
  }
  if (title.contains('case meeting outcome') ||
      title.contains('meeting completed')) {
    return 'meeting_completed';
  }
  if (title.contains('case reopened')) return 'case_reopened';
  if (title.contains('case resolved')) return 'case_resolved';
  return 'report_submitted';
}

String _firstNonEmpty(List<dynamic> values) {
  for (final value in values) {
    final text = _safeStr(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _yesNoDisplay(dynamic value) {
  if (value is bool) return value ? 'Yes' : 'No';
  final text = _safeStr(value).toLowerCase();
  if (text == 'true') return 'Yes';
  if (text == 'false') return 'No';
  return '';
}

void _addDetail(
  List<_NotificationDetailItem> list,
  String label,
  dynamic value,
) {
  final text = _valueToDisplayString(value);
  if (text == '--') return;
  list.add(_NotificationDetailItem(label: label, value: text));
}

String _valueToDisplayString(dynamic value) {
  if (value == null) return '--';
  if (value is Timestamp) return _fmtWhen(value.toDate());
  if (value is DateTime) return _fmtWhen(value);
  if (value is List) {
    if (value.isEmpty) return '--';
    return value
        .map((item) => _safeStr(item))
        .where((e) => e.isNotEmpty)
        .join(', ');
  }
  if (value is Map) {
    final text = value.entries
        .map((entry) => '${entry.key}: ${_safeStr(entry.value)}')
        .join(', ');
    return text.isEmpty ? '--' : text;
  }
  final text = _safeStr(value);
  return text.isEmpty ? '--' : text;
}

String _humanizePayloadKey(String key) {
  final raw = key.trim();
  if (raw.isEmpty) return 'Detail';
  final spaced = raw
      .replaceAll('_', ' ')
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (m) => '${m.group(1)} ${m.group(2)}',
      )
      .trim();
  if (spaced.isEmpty) return 'Detail';
  final words = spaced.split(RegExp(r'\s+'));
  return words
      .map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1).toLowerCase();
      })
      .join(' ');
}

String _formatReporterDisplay({required String name, required String role}) {
  final safeName = name.trim();
  final safeRole = _humanizeSnakeOrTitle(role.trim());
  if (safeName.isEmpty) return safeRole;
  if (safeRole.isEmpty) return safeName;
  return '$safeName ($safeRole)';
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          "Error loading notifications:\n$error",
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

String _safeStr(dynamic value) => (value ?? '').toString().trim();

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

String _humanizeSnakeOrTitle(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';
  final spaced = raw.replaceAll('_', ' ').replaceAll('-', ' ');
  return spaced
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

String _fmtDetailDateTime(DateTime dateTime) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = dateTime.toLocal();
  final month = months[local.month - 1];
  final day = local.day;
  final year = local.year;
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  return '$month $day, $year, $hour12:$minute $ampm';
}

String _fmtWhen(DateTime dateTime) {
  final now = DateTime.now();
  final delta = now.difference(dateTime);
  if (delta.inMinutes < 1) return 'Now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m';
  if (delta.inHours < 24) return '${delta.inHours}h';
  return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
}

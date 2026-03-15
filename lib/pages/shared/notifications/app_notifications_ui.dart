import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

class AppNotificationsPage extends StatelessWidget {
  const AppNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1B5E20);
    const bg = Color(0xFFF6FAF6);
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

                    if (docs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'No notifications yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: muted,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: docs.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data();

                        final title = _safeStr(d['title']).isEmpty
                            ? 'Notification'
                            : _safeStr(d['title']);
                        final body = _safeStr(d['body']);
                        final createdAt = _toDate(d['createdAt']);
                        final readAt = _toDate(d['readAt']);
                        final isUnread = readAt == null;

                        return InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () async {
                            await _openDetails(context, doc);
                          },
                          child: Container(
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                            createdAt == null
                                                ? '--'
                                                : _fmtWhen(createdAt),
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
                      },
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
      await doc.reference.update({'readAt': FieldValue.serverTimestamp()});
    }

    if (!context.mounted) return;
    await _showNotificationDetailsDialog(context: context, data: d);
  }
}

class AppNotificationsContent extends StatelessWidget {
  final VoidCallback? onBack;
  final AppNotificationViewHandler? onViewNotification;

  const AppNotificationsContent({
    super.key,
    this.onBack,
    this.onViewNotification,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1B5E20);
    const bg = Color(0xFFF6FAF6);
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
                      Row(
                        children: [
                          if (onBack != null)
                            IconButton(
                              onPressed: onBack,
                              tooltip: 'Back',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: primary,
                              ),
                            ),
                          const SizedBox(width: 4),
                          const Text(
                            'Notifications',
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                            if (docs.isEmpty) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(18),
                                  child: Text(
                                    'No notifications yet.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: muted,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.only(bottom: 10),
                              itemCount: docs.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final doc = docs[i];
                                final d = doc.data();

                                final title = _safeStr(d['title']).isEmpty
                                    ? 'Notification'
                                    : _safeStr(d['title']);
                                final body = _safeStr(d['body']);
                                final createdAt = _toDate(d['createdAt']);
                                final readAt = _toDate(d['readAt']);
                                final isUnread = readAt == null;

                                return InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () async {
                                    await _openDetails(context, doc);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: isUnread
                                            ? primary.withValues(alpha: 0.25)
                                            : Colors.black.withValues(
                                                alpha: 0.08,
                                              ),
                                        width: isUnread ? 1.4 : 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.03,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: isUnread
                                                ? primary.withValues(
                                                    alpha: 0.14,
                                                  )
                                                : Colors.black.withValues(
                                                    alpha: 0.05,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Icon(
                                            isUnread
                                                ? Icons
                                                      .notifications_active_rounded
                                                : Icons
                                                      .notifications_none_rounded,
                                            color: isUnread ? primary : muted,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                                                    createdAt == null
                                                        ? '--'
                                                        : _fmtWhen(createdAt),
                                                    style: const TextStyle(
                                                      color: muted,
                                                      fontWeight:
                                                          FontWeight.w800,
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                              },
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
      await doc.reference.update({'readAt': FieldValue.serverTimestamp()});
    }

    if (!context.mounted) return;
    await _showNotificationDetailsDialog(
      context: context,
      data: d,
      onViewNotification: onViewNotification,
    );
  }
}

class DesktopNotificationsPanel extends StatefulWidget {
  final String uid;
  final VoidCallback onClose;
  final Future<void> Function() onSeeAll;

  const DesktopNotificationsPanel({
    super.key,
    required this.uid,
    required this.onClose,
    required this.onSeeAll,
  });

  @override
  State<DesktopNotificationsPanel> createState() =>
      _DesktopNotificationsPanelState();
}

class _DesktopNotificationsPanelState extends State<DesktopNotificationsPanel> {
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
    final title = _safeStr(d['title']).isEmpty
        ? 'Notification'
        : _safeStr(d['title']);
    final body = _safeStr(d['body']);
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
  const textDark = Color(0xFF1F2A1F);

  final payload = _payloadAsMap(data['payload']);
  final intent = _extractNotificationViewIntent(data: data, payload: payload);
  final canView = intent != null && onViewNotification != null;
  final details = _buildNotificationDetails(
    data: data,
    payload: payload,
    intent: intent,
  );
  final title = _safeStr(data['title']).isEmpty
      ? 'Notification'
      : _safeStr(data['title']);
  final body = _safeStr(data['body']);

  final wantsView =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: primary.withValues(alpha: 0.16)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                              color: primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: textDark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Close',
                            color: hint,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          body,
                          style: const TextStyle(
                            color: hint,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ],
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FBF8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Details',
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w900,
                                ),
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
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: hint,
                              side: BorderSide(
                                color: Colors.black.withValues(alpha: 0.16),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: !canView
                                ? null
                                : () => Navigator.of(dialogContext).pop(true),
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 16,
                            ),
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ) ??
      false;

  if (!wantsView || intent == null || onViewNotification == null) return;
  await onViewNotification(intent);
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

  if (type == 'student_profile_pending_approval') {
    details.add(
      const _NotificationDetailItem(label: 'Type', value: 'Pending Approval'),
    );
    _addDetail(details, 'Student', payload['studentName']);
    _addDetail(details, 'Student Number', payload['studentNo']);
    _addDetail(details, 'College', payload['collegeId']);
    _addDetail(details, 'Program', payload['programId']);
    _addDetail(details, 'Year Level', payload['yearLevel']);
    if (createdAt != null) {
      details.add(
        _NotificationDetailItem(label: 'Received', value: _fmtWhen(createdAt)),
      );
    }
    return details;
  }

  if (intent?.target == AppNotificationViewTarget.violationAlert) {
    details.add(
      const _NotificationDetailItem(label: 'Type', value: 'Violation Alert'),
    );
    final caseCode = _safeStr(payload['caseCode']);
    final caseId = _safeStr(payload['caseId']).isEmpty
        ? _safeStr(data['caseId'])
        : _safeStr(payload['caseId']);
    if (caseCode.isNotEmpty) {
      details.add(_NotificationDetailItem(label: 'Case Code', value: caseCode));
    }
    if (caseId.isNotEmpty) {
      details.add(_NotificationDetailItem(label: 'Case ID', value: caseId));
    }
    _addDetail(details, 'Student', payload['studentName']);
    _addDetail(details, 'Status', payload['status']);
    _addDetail(details, 'Event', payload['event']);
    if (createdAt != null) {
      details.add(
        _NotificationDetailItem(label: 'Received', value: _fmtWhen(createdAt)),
      );
    }
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

String _fmtWhen(DateTime dateTime) {
  final now = DateTime.now();
  final delta = now.difference(dateTime);
  if (delta.inMinutes < 1) return 'Now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m';
  if (delta.inHours < 24) return '${delta.inHours}h';
  return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
}

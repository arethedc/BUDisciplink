import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

    final payload = d['payload'];

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          _safeStr(d['title']).isEmpty ? 'Notification' : _safeStr(d['title']),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_safeStr(d['body']).isNotEmpty) Text(_safeStr(d['body'])),
              if (payload is Map) ...[
                const SizedBox(height: 12),
                const Text(
                  'Details',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                ...payload.entries.map((e) {
                  final k = e.key.toString();
                  final v = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('$k: ${v ?? '--'}'),
                  );
                }),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
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

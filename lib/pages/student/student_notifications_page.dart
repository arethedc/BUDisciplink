import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:apps/pages/shared/widgets/app_layout_tokens.dart';
import 'package:apps/services/app_firestore.dart';

enum _StudentNotificationsFilter { all, unread }

class StudentNotificationsPage extends StatefulWidget {
  const StudentNotificationsPage({super.key});

  @override
  State<StudentNotificationsPage> createState() =>
      _StudentNotificationsPageState();
}

class _StudentNotificationsPageState extends State<StudentNotificationsPage> {
  _StudentNotificationsFilter _filter = _StudentNotificationsFilter.all;

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

    // Read from a per-user notifications subcollection to avoid collectionGroup indexes.
    final stream = AppFirestore.instance
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
                        .where((doc) => _tsToDate(doc.data()['readAt']) == null)
                        .length;
                    final filteredDocs =
                        _filter == _StudentNotificationsFilter.unread
                        ? docs
                              .where(
                                (doc) =>
                                    _tsToDate(doc.data()['readAt']) == null,
                              )
                              .toList()
                        : docs;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                          child: _buildStudentNotificationsFilterBar(
                            selected: _filter,
                            unreadCount: unreadCount,
                            onChanged: (next) {
                              if (_filter == next) return;
                              setState(() => _filter = next);
                            },
                          ),
                        ),
                        Expanded(
                          child: filteredDocs.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Text(
                                      _filter ==
                                              _StudentNotificationsFilter.unread
                                          ? 'No unread notifications.'
                                          : 'No notifications yet.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: muted,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    0,
                                    14,
                                    14,
                                  ),
                                  itemCount: filteredDocs.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final doc = filteredDocs[i];
                                    final d = doc.data();

                                    final title = _safeStr(d['title']).isEmpty
                                        ? 'Notification'
                                        : _safeStr(d['title']);
                                    final body = _safeStr(d['body']);
                                    final createdAt = _tsToDate(d['createdAt']);
                                    final readAt = _tsToDate(d['readAt']);
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
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          border: Border.all(
                                            color: isUnread
                                                ? primary.withValues(
                                                    alpha: 0.25,
                                                  )
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
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                isUnread
                                                    ? Icons
                                                          .notifications_active_rounded
                                                    : Icons
                                                          .notifications_none_rounded,
                                                color: isUnread
                                                    ? primary
                                                    : muted,
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
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: Colors.black,
                                                            fontWeight: isUnread
                                                                ? FontWeight
                                                                      .w900
                                                                : FontWeight
                                                                      .w800,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        createdAt == null
                                                            ? '--'
                                                            : _fmtWhen(
                                                                createdAt,
                                                              ),
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
                                                        fontWeight:
                                                            FontWeight.w700,
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
                                ),
                        ),
                      ],
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

    // Mark as read when opened.
    if (_tsToDate(d['readAt']) == null) {
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

Widget _buildStudentNotificationsFilterBar({
  required _StudentNotificationsFilter selected,
  required int unreadCount,
  required ValueChanged<_StudentNotificationsFilter> onChanged,
}) {
  const filterRadius = AppRadii.md;
  final options = <(_StudentNotificationsFilter, String)>[
    (_StudentNotificationsFilter.all, 'All'),
    (
      _StudentNotificationsFilter.unread,
      unreadCount <= 0 ? 'Unread' : 'Unread ($unreadCount)',
    ),
  ];

  Widget filterTab(_StudentNotificationsFilter value, String label) {
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

String _safeStr(dynamic v) => (v ?? '').toString().trim();

DateTime? _tsToDate(dynamic ts) {
  try {
    if (ts == null) return null;
    return (ts as Timestamp).toDate();
  } catch (_) {
    return null;
  }
}

String _fmtWhen(DateTime d) {
  final now = DateTime.now();
  final delta = now.difference(d);
  if (delta.inMinutes < 1) return 'Now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m';
  if (delta.inHours < 24) return '${delta.inHours}h';
  return '${d.month}/${d.day}/${d.year}';
}

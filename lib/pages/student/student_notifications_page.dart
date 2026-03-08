import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class StudentNotificationsPage extends StatelessWidget {
  const StudentNotificationsPage({super.key});

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

    // Read from a per-user notifications subcollection to avoid collectionGroup indexes.
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

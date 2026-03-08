import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TopicDetailScreen extends StatefulWidget {
  final String versionId;
  final String topicId;
  final String sectionCode;
  final String sectionTitle;
  final String topicCode;
  final String topicTitle;

  const TopicDetailScreen({
    super.key,
    required this.versionId,
    required this.topicId,
    required this.sectionCode,
    required this.sectionTitle,
    required this.topicCode,
    required this.topicTitle,
  });

  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> {
  // Theme colors (same as your detail vibe)
  static const bg = Color(0xFFECEEE6);
  static const headerBg = Color(0xFFE7EBDD);
  static const dark = Color(0xFF2E3B2B);
  static const muted = Color(0xFF7B8473);
  static const green = Color(0xFF6D7F62);
  static const card = Color(0xFFF7F7F4);

  bool _checked = false;

  DocumentReference<Map<String, dynamic>> get _contentRef =>
      FirebaseFirestore.instance.collection('handbook_contents').doc(widget.topicId);

  DocumentReference<Map<String, dynamic>>? get _progressRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('handbook_progress')
        .doc(widget.topicId);
  }

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _touchOpened();
  }

  Future<void> _touchOpened() async {
    final ref = _progressRef;
    if (ref == null) return;
    await ref.set({
      "topicId": widget.topicId,
      "versionId": widget.versionId,
      "lastOpenedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _loadProgress() async {
    final ref = _progressRef;
    if (ref == null) return;
    final snap = await ref.get();
    final data = snap.data();
    if (!mounted) return;
    setState(() => _checked = (data?['isRead'] == true));
  }

  Future<void> _setRead(bool v) async {
    final ref = _progressRef;
    if (ref == null) return;

    setState(() => _checked = v);

    await ref.set({
      "topicId": widget.topicId,
      "versionId": widget.versionId,
      "isRead": v,
      "readAt": v ? FieldValue.serverTimestamp() : null,
      "lastOpenedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: headerBg,
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: dark),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "${widget.topicCode} ${widget.topicTitle}".toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: dark,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _contentRef.snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snap.data!.data();
                  if (data == null) {
                    return const Center(child: Text("No content found."));
                  }

                  final blocks = (data['blocks'] as List?) ?? const [];

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(26),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Section ${widget.sectionCode}",
                                style: const TextStyle(
                                  color: muted,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.sectionTitle.toUpperCase(),
                                style: const TextStyle(
                                  color: dark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 14),

                              Container(
                                decoration: BoxDecoration(
                                  color: card,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 18,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.menu_book_rounded, color: green),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            "${widget.topicCode} ${widget.topicTitle}",
                                            style: const TextStyle(
                                              color: dark,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    const Divider(height: 1, color: Colors.black12),
                                    const SizedBox(height: 14),

                                    ...blocks.map(_renderBlock),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => _setRead(!_checked),
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: _checked ? green : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: green.withValues(alpha: 0.6),
                                      width: 2,
                                    ),
                                  ),
                                  child: _checked
                                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  "I have read and understood this section",
                                  style: TextStyle(
                                    color: dark,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _checked,
                                activeThumbColor: green,
                                onChanged: (v) => _setRead(v),
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
    );
  }

  Widget _renderBlock(dynamic raw) {
    if (raw is! Map) return const SizedBox.shrink();
    final type = (raw['type'] ?? '').toString();

    if (type == 'h2') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          (raw['text'] ?? '').toString(),
          style: const TextStyle(
            color: dark,
            fontWeight: FontWeight.w900,
            fontSize: 16.5,
          ),
        ),
      );
    }

    if (type == 'p') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          (raw['text'] ?? '').toString(),
          style: const TextStyle(
            color: Color(0xFF3D4438),
            fontSize: 14.5,
            height: 1.55,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (type == 'list') {
      final items = (raw['items'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items
              .map((it) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              "• $it",
              style: const TextStyle(
                color: Color(0xFF3D4438),
                fontSize: 14.5,
                height: 1.55,
                fontWeight: FontWeight.w700,
              ),
            ),
          ))
              .toList(),
        ),
      );
    }

    if (type == 'card') {
      final title = (raw['title'] ?? '').toString();
      final text = (raw['text'] ?? '').toString();

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black12),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: dark,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFF3D4438),
                fontSize: 14.5,
                height: 1.55,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

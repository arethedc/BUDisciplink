import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'topic_detail_screen.dart';

class SectionTopicsScreen extends StatefulWidget {
  final String versionId;
  final String sectionCode;
  final String sectionTitle;

  const SectionTopicsScreen({
    super.key,
    required this.versionId,
    required this.sectionCode,
    required this.sectionTitle,
  });

  @override
  State<SectionTopicsScreen> createState() => _SectionTopicsScreenState();
}

class _SectionTopicsScreenState extends State<SectionTopicsScreen> {
  // Theme colors
  static const bg = Color(0xFFEFF2EA);
  static const topBarGreen = Color(0xFF2F6C44);
  static const cardBg = Color(0xFFF5F6F2);
  static const textDark = Color(0xFF2B332B);

  final TextEditingController _search = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('handbook_topics')
        .where('versionId', isEqualTo: widget.versionId)
        .where('sectionCode', isEqualTo: widget.sectionCode)
        .where('isPublished', isEqualTo: true)
        .orderBy('order');

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: topBarGreen,
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Section ${widget.sectionCode} • ${widget.sectionTitle}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Color(0xFF8B9489)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: const InputDecoration(
                          hintText: "Search topics...",
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: q.snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs;

                  final items = docs.map((d) {
                    final data = d.data();
                    return _TopicVM(
                      id: d.id,
                      code: (data['code'] ?? '').toString(),
                      title: (data['title'] ?? '').toString(),
                      order: (data['order'] ?? 0) as int,
                    );
                  }).toList();

                  final qq = _query.trim().toLowerCase();
                  final filtered = qq.isEmpty
                      ? items
                      : items.where((t) => ("${t.code} ${t.title}").toLowerCase().contains(qq)).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text("No topics found."));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final t = filtered[i];

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TopicDetailScreen(
                                  versionId: widget.versionId,
                                  topicId: t.id,
                                  sectionCode: widget.sectionCode,
                                  sectionTitle: widget.sectionTitle,
                                  topicCode: t.code,
                                  topicTitle: t.title,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "${t.code}  ${t.title}",
                                    style: const TextStyle(
                                      color: textDark,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: Colors.black45),
                              ],
                            ),
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
    );
  }
}

class _TopicVM {
  final String id;
  final String code;
  final String title;
  final int order;

  const _TopicVM({
    required this.id,
    required this.code,
    required this.title,
    required this.order,
  });
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'section_topics_screen.dart';

class HandbookScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;
  const HandbookScreen({super.key, this.onBackToHome});

  @override
  State<HandbookScreen> createState() => _HandbookScreenState();
}

class _HandbookScreenState extends State<HandbookScreen> {
  // Colors (YOUR THEME)
  static const bg = Color(0xFFEFF2EA);
  static const topBarGreen = Color(0xFF2F6C44);

  static const cardBg = Color(0xFFF5F6F2);
  static const cardShadow = Color(0x22000000);

  static const textDark = Color(0xFF2B332B);
  static const textMuted = Color(0xFF7B857A);

  static const green = Color(0xFF5F7F5C);
  static const greenDark = Color(0xFF4E6B4B);

  static const pillGray = Color(0xFFE3E6DF);
  static const pillGrayText = Color(0xFF6A7268);

  final TextEditingController _search = TextEditingController();
  String _query = "";

  // Collections
  static const _colMeta = 'handbook_meta';
  static const _colSections = 'handbook_sections';
  static const _colProgress = 'handbook_progress';

  void _back() {
    if (widget.onBackToHome != null) {
      widget.onBackToHome!();
      return;
    }
    Navigator.maybePop(context);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final scale = (w / 430).clamp(1.0, 1.20);
    final pad = (16.0 * scale).clamp(16.0, 24.0);

    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // TOP BAR
            Container(
              color: topBarGreen,
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      "Digital Student Handbook",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("QR tapped")),
                      );
                    },
                    icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),

            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection(_colMeta)
                    .doc('current')
                    .snapshots(),
                builder: (context, metaSnap) {
                  // Quick fallback version while loading (prevents blank screen)
                  final versionId = (metaSnap.data?.data()?['activeVersionId'] as String?) ??
                      'SY2024-2025';

                  // Progress stream (only read topics)
                  final progressStream = (uid == null)
                      ? const Stream<QuerySnapshot<Map<String, dynamic>>>.empty()
                      : FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection(_colProgress)
                      .where('versionId', isEqualTo: versionId)
                      .where('isRead', isEqualTo: true)
                      .snapshots();

                  // Sections stream
                  final sectionsStream = FirebaseFirestore.instance
                      .collection(_colSections)
                      .where('versionId', isEqualTo: versionId)
                      .where('isPublished', isEqualTo: true)
                      .orderBy('order')
                      .snapshots();

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: progressStream,
                    builder: (context, progSnap) {
                      final readSectionCodes = <String>{};

                      if (progSnap.hasData) {
                        for (final d in progSnap.data!.docs) {
                          final topicId = d.id; // SY2024-2025_01_02
                          final parts = topicId.split('_');
                          if (parts.length >= 3) {
                            final sec = parts[1]; // "01"
                            final secCode = int.tryParse(sec)?.toString() ?? sec;
                            readSectionCodes.add(secCode);
                          }
                        }
                      }

                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: sectionsStream,
                        builder: (context, secSnap) {
                          if (!secSnap.hasData) {
                            return _LoadingBody(scale: scale, pad: pad);
                          }

                          final docs = secSnap.data!.docs;

                          final all = docs.map((d) {
                            final data = d.data();
                            final order = (data['order'] ?? 0) as int;
                            final code = (data['code'] ?? '').toString(); // "1"
                            final title = (data['title'] ?? '').toString();

                            final isRead = readSectionCodes.contains(code);

                            return _SectionVM(
                              order: order,
                              code: code,
                              title: title,
                              isRead: isRead,
                            );
                          }).toList();

                          final q = _query.trim().toLowerCase();
                          final filtered = q.isEmpty
                              ? all
                              : all.where((s) => s.title.toLowerCase().contains(q)).toList();

                          final readCount = all.where((s) => s.isRead).length;

                          return Scrollbar(
                            thumbVisibility: w >= 900,
                            child: SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(pad, 14 * scale, pad, 16 * scale),
                              child: Column(
                                children: [
                                  _SearchBar(
                                    controller: _search,
                                    onChanged: (v) => setState(() => _query = v),
                                    hintText: "Search handbook...",
                                    scale: scale,
                                  ),
                                  SizedBox(height: 12 * scale),

                                  _ProgressCard(
                                    readCount: readCount,
                                    total: all.length,
                                    green: green,
                                    cardBg: cardBg,
                                    textDark: textDark,
                                    textMuted: textMuted,
                                    scale: scale,
                                  ),
                                  SizedBox(height: 12 * scale),

                                  ListView.separated(
                                    itemCount: filtered.length,
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    separatorBuilder: (_, index) => SizedBox(height: 10 * scale),
                                    itemBuilder: (context, index) {
                                      final s = filtered[index];

                                      return _SectionTile(
                                        id: s.order,
                                        title: s.title,
                                        isRead: s.isRead,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => SectionTopicsScreen(
                                                versionId: versionId,
                                                sectionCode: s.code,
                                                sectionTitle: s.title,
                                              ),
                                            ),
                                          );
                                        },
                                        green: green,
                                        greenDark: greenDark,
                                        cardBg: cardBg,
                                        pillGray: pillGray,
                                        pillGrayText: pillGrayText,
                                        cardShadow: cardShadow,
                                        textDark: textDark,
                                        scale: scale,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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

// ===================== MODELS =====================
class _SectionVM {
  final int order;
  final String code;
  final String title;
  final bool isRead;

  const _SectionVM({
    required this.order,
    required this.code,
    required this.title,
    required this.isRead,
  });
}

// ===================== LOADING PLACEHOLDER =====================
class _LoadingBody extends StatelessWidget {
  final double scale;
  final double pad;

  const _LoadingBody({required this.scale, required this.pad});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 14 * scale, pad, 16 * scale),
      child: Column(
        children: [
          Container(
            height: (48.0 * scale).clamp(48.0, 58.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(18 * scale),
              border: Border.all(color: Colors.black12),
            ),
          ),
          SizedBox(height: 12 * scale),
          Container(
            height: 110 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6F2),
              borderRadius: BorderRadius.circular(20 * scale),
              border: Border.all(color: Colors.black12),
            ),
          ),
          SizedBox(height: 12 * scale),
          ...List.generate(6, (i) {
            return Padding(
              padding: EdgeInsets.only(bottom: 10 * scale),
              child: Container(
                height: (64.0 * scale).clamp(64.0, 78.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F2),
                  borderRadius: BorderRadius.circular(22 * scale),
                  border: Border.all(color: Colors.black12),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ===================== SEARCH BAR =====================
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final double scale;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.hintText,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final h = (48.0 * scale).clamp(48.0, 58.0);

    return Container(
      height: h,
      padding: EdgeInsets.symmetric(horizontal: 12 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: const Color(0xFF8B9489), size: 22 * scale),
          SizedBox(width: 8 * scale),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: (14 * scale).clamp(14.0, 16.0)),
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                hintStyle: TextStyle(
                  color: const Color(0xFF8B9489),
                  fontWeight: FontWeight.w600,
                  fontSize: (13.5 * scale).clamp(13.5, 15.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== PROGRESS CARD =====================
class _ProgressCard extends StatelessWidget {
  final int readCount;
  final int total;
  final Color green;
  final Color cardBg;
  final Color textDark;
  final Color textMuted;
  final double scale;

  const _ProgressCard({
    required this.readCount,
    required this.total,
    required this.green,
    required this.cardBg,
    required this.textDark,
    required this.textMuted,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (readCount / total).clamp(0.0, 1.0);

    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20 * scale),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: (12 * scale).clamp(10.0, 14.0),
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.8),
              valueColor: AlwaysStoppedAnimation<Color>(green),
            ),
          ),
          SizedBox(height: 10 * scale),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "$readCount / $total Sections Complete",
              style: TextStyle(
                color: textDark,
                fontWeight: FontWeight.w800,
                fontSize: (14 * scale).clamp(14.0, 16.0),
              ),
            ),
          ),
          SizedBox(height: 2 * scale),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Keep going — your progress is saved.",
              style: TextStyle(
                color: textMuted,
                fontWeight: FontWeight.w600,
                fontSize: (12.5 * scale).clamp(12.5, 14.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== SECTION TILE =====================
class _SectionTile extends StatelessWidget {
  final int id;
  final String title;
  final bool isRead;
  final VoidCallback onTap;

  final Color green;
  final Color greenDark;
  final Color cardBg;
  final Color pillGray;
  final Color pillGrayText;
  final Color cardShadow;
  final Color textDark;
  final double scale;

  const _SectionTile({
    required this.id,
    required this.title,
    required this.isRead,
    required this.onTap,
    required this.green,
    required this.greenDark,
    required this.cardBg,
    required this.pillGray,
    required this.pillGrayText,
    required this.cardShadow,
    required this.textDark,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final h = (64.0 * scale).clamp(64.0, 78.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22 * scale),
        onTap: onTap,
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(22 * scale),
            border: Border.all(color: Colors.black12),
            boxShadow: [
              BoxShadow(
                color: cardShadow,
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: (72 * scale).clamp(72.0, 88.0),
                height: double.infinity,
                decoration: BoxDecoration(
                  color: green,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(22 * scale),
                    bottomLeft: Radius.circular(22 * scale),
                  ),
                ),
                child: Center(
                  child: Text(
                    "$id",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (22 * scale).clamp(22.0, 28.0),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textDark,
                    fontSize: (16 * scale).clamp(16.0, 19.0),
                    fontWeight: FontWeight.w900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 10 * scale),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: (14 * scale).clamp(12.0, 16.0),
                  vertical: (8 * scale).clamp(7.0, 10.0),
                ),
                decoration: BoxDecoration(
                  color: isRead ? greenDark : pillGray,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isRead ? "Read" : "Not Read",
                  style: TextStyle(
                    color: isRead ? Colors.white : pillGrayText,
                    fontWeight: FontWeight.w900,
                    fontSize: (13 * scale).clamp(13.0, 15.5),
                  ),
                ),
              ),
              SizedBox(width: 10 * scale),
              Icon(Icons.chevron_right_rounded, color: const Color(0xFF8B9489), size: 28 * scale),
              SizedBox(width: 12 * scale),
            ],
          ),
        ),
      ),
    );
  }
}

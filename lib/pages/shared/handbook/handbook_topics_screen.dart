import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'handbook_topic_content_screen.dart';
import 'handbook_ai_assistant_sheet.dart';
import 'package:apps/models/handbook_section_doc.dart';
import 'package:apps/models/handbook_topic_doc.dart';

class HandbookTopicsScreen extends StatefulWidget {
  final HandbookSectionDoc section;
  final bool embedded;
  final VoidCallback? onBack;
  final ValueChanged<HandbookTopicDoc>? onTopicTap;

  const HandbookTopicsScreen({
    super.key,
    required this.section,
    this.embedded = false,
    this.onBack,
    this.onTopicTap,
  });

  @override
  State<HandbookTopicsScreen> createState() => _HandbookTopicsScreenState();
}

class _HandbookTopicsScreenState extends State<HandbookTopicsScreen> {
  static const bg = Color(0xFFEFF2EA);
  static const topBarGreen = Color(0xFF2F6C44);

  final TextEditingController _search = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<String> _getActiveVersionId() async {
    final snap = await FirebaseFirestore.instance
        .collection('handbook_meta')
        .doc('current')
        .get();

    final data = snap.data();
    if (data == null || data['activeVersionId'] == null) {
      throw Exception('handbook_meta/current missing activeVersionId');
    }
    return data['activeVersionId'] as String;
  }

  Stream<List<HandbookTopicDoc>> _topicsStream(String versionId) {
    return FirebaseFirestore.instance
        .collection('handbook_topics')
        .where('versionId', isEqualTo: versionId)
        .where('sectionCode', isEqualTo: widget.section.code)
        .where('isPublished', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .map((q) => q.docs.map((d) => HandbookTopicDoc.fromDoc(d)).toList());
  }

  bool _matches(String title, String code) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) || code.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Determine screen type
    final isDesktop = screenWidth >= 1024;
    final isTablet = screenWidth >= 600 && screenWidth < 1024;

    // Responsive values
    final maxContentWidth = isDesktop ? 1200.0 : double.infinity;
    final horizontalPadding = isDesktop ? 48.0 : (isTablet ? 32.0 : 16.0);
    final verticalPadding = isDesktop ? 32.0 : (isTablet ? 24.0 : 14.0);
    final searchBarMaxWidth = isDesktop ? 600.0 : double.infinity;

    // Grid configuration
    final crossAxisCount = isDesktop ? 2 : (isTablet ? 2 : 1);
    final childAspectRatio = isDesktop ? 4.0 : (isTablet ? 3.5 : 5.0);
    final mainAxisSpacing = isDesktop ? 20.0 : (isTablet ? 16.0 : 10.0);
    final crossAxisSpacing = isDesktop ? 20.0 : (isTablet ? 16.0 : 0.0);

    final body = Column(
      children: [
        if (!widget.embedded)
          Container(
            color: topBarGreen,
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 16 : 8,
              isDesktop ? 16 : 10,
              isDesktop ? 16 : 8,
              isDesktop ? 16 : 10,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: widget.onBack ?? () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: isDesktop ? 26 : 24,
                      ),
                      tooltip: 'Back to sections',
                    ),
                    SizedBox(width: isDesktop ? 12 : 6),
                    Expanded(
                      child: Text(
                        "${widget.section.code}. ${widget.section.title}",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isDesktop ? 22 : (isTablet ? 20 : 18),
                          fontWeight: FontWeight.w900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (widget.embedded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack ?? () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  tooltip: 'Back to sections',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Handbook / Section',
                        style: TextStyle(
                          color: Color(0xFF6D7F62),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "${widget.section.code}. ${widget.section.title}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1F2A1F),
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  16,
                ),
                child: Column(
                  children: [
                    // Subtitle on desktop
                    if (isDesktop) ...[
                      Text(
                        'Browse topics in this section',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF8B9489),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Search bar
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: searchBarMaxWidth,
                        ),
                        child: _SearchBar(
                          controller: _search,
                          hintText: "Search topics...",
                          isDesktop: isDesktop,
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                    ),
                    SizedBox(height: isDesktop ? 32 : (isTablet ? 20 : 12)),

                    Expanded(
                      child: FutureBuilder<String>(
                        future: _getActiveVersionId(),
                        builder: (context, metaSnap) {
                          if (metaSnap.hasError) {
                            return Center(
                              child: Text(
                                "Error:\n${metaSnap.error}",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }
                          if (!metaSnap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final versionId = metaSnap.data!;

                          return StreamBuilder<List<HandbookTopicDoc>>(
                            stream: _topicsStream(versionId),
                            builder: (context, snap) {
                              if (snap.hasError) {
                                return Center(
                                  child: Text(
                                    "Firestore error:\n${snap.error}",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                );
                              }
                              if (!snap.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final all = snap.data!;
                              final filtered = all
                                  .where((t) => _matches(t.title, t.code))
                                  .toList();

                              if (filtered.isEmpty) {
                                return const Center(
                                  child: Text(
                                    "No topics found.",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                );
                              }

                              // Grid for tablet/desktop, list for mobile
                              if (crossAxisCount > 1) {
                                return GridView.builder(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        childAspectRatio: childAspectRatio,
                                        mainAxisSpacing: mainAxisSpacing,
                                        crossAxisSpacing: crossAxisSpacing,
                                      ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    final t = filtered[i];
                                    return _TopicTile(
                                      code: t.code,
                                      title: t.title,
                                      isDesktop: isDesktop,
                                      isTablet: isTablet,
                                      onTap: () {
                                        final callback = widget.onTopicTap;
                                        if (callback != null) {
                                          callback(t);
                                          return;
                                        }
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                HandbookTopicContentScreen(
                                                  topic: t,
                                                ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              } else {
                                return ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, index) =>
                                      SizedBox(height: mainAxisSpacing),
                                  itemBuilder: (context, i) {
                                    final t = filtered[i];
                                    return _TopicTile(
                                      code: t.code,
                                      title: t.title,
                                      isDesktop: isDesktop,
                                      isTablet: isTablet,
                                      onTap: () {
                                        final callback = widget.onTopicTap;
                                        if (callback != null) {
                                          callback(t);
                                          return;
                                        }
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                HandbookTopicContentScreen(
                                                  topic: t,
                                                ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Container(color: bg, child: body);
    }
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(child: body),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => showHandbookAiAssistantSheet(context),
        backgroundColor: topBarGreen,
        foregroundColor: Colors.white,
        tooltip: 'Open Handbook AI',
        child: const Icon(Icons.menu_book_rounded),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// --------- local widgets ----------

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isDesktop;
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.controller,
    required this.hintText,
    required this.isDesktop,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final height = isDesktop ? 56.0 : 48.0;
    final borderRadius = isDesktop ? 16.0 : 18.0;
    final iconSize = isDesktop ? 24.0 : 22.0;
    final fontSize = isDesktop ? 15.0 : 13.5;

    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.black12),
        boxShadow: isDesktop
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: const Color(0xFF8B9489),
            size: iconSize,
          ),
          SizedBox(width: isDesktop ? 12 : 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                hintStyle: TextStyle(
                  color: const Color(0xFF8B9489),
                  fontWeight: FontWeight.w600,
                  fontSize: fontSize,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicTile extends StatefulWidget {
  final String code;
  final String title;
  final bool isDesktop;
  final bool isTablet;
  final VoidCallback onTap;

  const _TopicTile({
    required this.code,
    required this.title,
    required this.isDesktop,
    required this.isTablet,
    required this.onTap,
  });

  @override
  State<_TopicTile> createState() => _TopicTileState();
}

class _TopicTileState extends State<_TopicTile> {
  bool _isHovered = false;

  static const cardBg = Color(0xFFF5F6F2);
  static const textDark = Color(0xFF2B332B);
  static const green = Color(0xFF5F7F5C);

  @override
  Widget build(BuildContext context) {
    final height = widget.isDesktop ? 70.0 : (widget.isTablet ? 66.0 : 64.0);
    final borderRadius = widget.isDesktop ? 16.0 : 18.0;
    final codeBadgeWidth = widget.isDesktop
        ? 70.0
        : (widget.isTablet ? 66.0 : 62.0);
    final codeBadgeHeight = widget.isDesktop
        ? 46.0
        : (widget.isTablet ? 44.0 : 42.0);
    final codeFontSize = widget.isDesktop
        ? 15.0
        : (widget.isTablet ? 14.5 : 14.0);
    final titleFontSize = widget.isDesktop
        ? 16.5
        : (widget.isTablet ? 16.0 : 15.5);
    final iconSize = widget.isDesktop ? 30.0 : (widget.isTablet ? 29.0 : 28.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.identity()
          ..translate(0.0, _isHovered && widget.isDesktop ? -2.0 : 0.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: widget.onTap,
            child: Container(
              height: height,
              padding: EdgeInsets.symmetric(
                horizontal: widget.isDesktop ? 20 : 14,
              ),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: _isHovered && widget.isDesktop
                      ? green.withValues(alpha: 0.3)
                      : Colors.black12,
                ),
                boxShadow: widget.isDesktop
                    ? [
                        BoxShadow(
                          color: _isHovered
                              ? Colors.black.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.06),
                          blurRadius: _isHovered ? 12 : 8,
                          offset: Offset(0, _isHovered ? 6 : 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: codeBadgeWidth,
                    height: codeBadgeHeight,
                    decoration: BoxDecoration(
                      color: green,
                      borderRadius: BorderRadius.circular(
                        widget.isDesktop ? 12 : 14,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.code,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: codeFontSize,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: widget.isDesktop ? 16 : 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: titleFontSize,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: widget.isDesktop ? 2 : 1,
                    ),
                  ),
                  SizedBox(width: widget.isDesktop ? 12 : 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: const Color(0xFF8B9489),
                    size: iconSize,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

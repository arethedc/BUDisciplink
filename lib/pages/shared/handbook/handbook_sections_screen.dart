import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:apps/models/handbook_section_doc.dart';
import 'package:apps/models/handbook_topic_doc.dart';
import 'handbook_topic_content_screen.dart';
import 'handbook_topics_screen.dart';
import 'handbook_ai_assistant_sheet.dart';

class HandbookSectionsScreen extends StatefulWidget {
  final bool useSidebarDesktop;

  const HandbookSectionsScreen({super.key, this.useSidebarDesktop = true});

  @override
  State<HandbookSectionsScreen> createState() => _HandbookSectionsScreenState();
}

class _HandbookSectionsScreenState extends State<HandbookSectionsScreen> {
  static const bg = Color(0xFFF6FAF6);
  static const _textDark = Color(0xFF1F2A1F);
  static const _primary = Color(0xFF1B5E20);

  final TextEditingController _search = TextEditingController();
  String _query = "";
  HandbookSectionDoc? _selectedSection;
  HandbookTopicDoc? _selectedTopic;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(String title) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q);
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

  Stream<List<HandbookSectionDoc>> _sectionsStream(String versionId) {
    return FirebaseFirestore.instance
        .collection('handbook_sections')
        .where('versionId', isEqualTo: versionId)
        .where('isPublished', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .map((q) => q.docs.map((d) => HandbookSectionDoc.fromDoc(d)).toList());
  }

  Stream<List<HandbookTopicDoc>> _allTopicsStream(String versionId) {
    return FirebaseFirestore.instance
        .collection('handbook_topics')
        .where('versionId', isEqualTo: versionId)
        .snapshots()
        .map((q) {
          final topics =
              q.docs
                  .map((d) => HandbookTopicDoc.fromDoc(d))
                  .where((t) => t.isPublished)
                  .toList()
                ..sort((a, b) => a.order.compareTo(b.order));
          return topics;
        });
  }

  Widget _buildHandbookAiFab({required String heroTag}) {
    return FloatingActionButton(
      heroTag: heroTag,
      onPressed: () => showHandbookAiAssistantSheet(context),
      backgroundColor: _primary,
      foregroundColor: Colors.white,
      tooltip: 'Open Handbook AI',
      child: const Icon(Icons.menu_book_rounded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Determine if we're on desktop, tablet, or mobile
    final isDesktop = screenWidth >= 1024;
    final isTablet = screenWidth >= 600 && screenWidth < 1024;

    if (widget.useSidebarDesktop && !isDesktop && _selectedTopic != null) {
      return HandbookTopicContentScreen(
        key: ValueKey('shared_topic_${_selectedTopic!.id}'),
        topic: _selectedTopic!,
        embedded: true,
        onBack: () {
          if (!mounted) return;
          setState(() => _selectedTopic = null);
        },
      );
    }

    if (widget.useSidebarDesktop && !isDesktop && _selectedSection != null) {
      return HandbookTopicsScreen(
        key: ValueKey('shared_section_${_selectedSection!.id}'),
        section: _selectedSection!,
        embedded: true,
        onBack: () {
          if (!mounted) return;
          setState(() {
            _selectedSection = null;
            _selectedTopic = null;
          });
        },
        onTopicTap: (topic) {
          if (!mounted) return;
          setState(() => _selectedTopic = topic);
        },
      );
    }

    // Responsive values
    final maxContentWidth = isDesktop ? 1200.0 : double.infinity;
    final horizontalPadding = isDesktop ? 48.0 : (isTablet ? 32.0 : 16.0);
    final verticalPadding = isDesktop ? 32.0 : (isTablet ? 24.0 : 14.0);
    final searchBarMaxWidth = isDesktop ? 600.0 : double.infinity;

    // Grid/List configuration
    final crossAxisCount = isDesktop ? 3 : (isTablet ? 2 : 1);
    final childAspectRatio = isDesktop ? 3.5 : (isTablet ? 3.0 : 5.0);
    final mainAxisSpacing = isDesktop ? 20.0 : (isTablet ? 16.0 : 10.0);
    final crossAxisSpacing = isDesktop ? 20.0 : (isTablet ? 16.0 : 0.0);

    if (isDesktop && widget.useSidebarDesktop) {
      return Stack(
        children: [
          Container(
            color: bg,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'College Student Handbook',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: _textDark,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Sections and topics navigation',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8B9489),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: FutureBuilder<String>(
                        future: _getActiveVersionId(),
                        builder: (context, metaSnap) {
                          if (metaSnap.hasError) {
                            return _CenterMsg(text: "Error: ${metaSnap.error}");
                          }
                          if (!metaSnap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final versionId = metaSnap.data!;
                          return StreamBuilder<List<HandbookSectionDoc>>(
                            stream: _sectionsStream(versionId),
                            builder: (context, sectionSnap) {
                              if (sectionSnap.hasError) {
                                return _CenterMsg(
                                  text:
                                      "Firestore error:\n${sectionSnap.error}",
                                );
                              }
                              if (!sectionSnap.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final sections = sectionSnap.data!;
                              if (sections.isEmpty) {
                                return const _CenterMsg(
                                  text: "No sections found.",
                                );
                              }

                              return StreamBuilder<List<HandbookTopicDoc>>(
                                stream: _allTopicsStream(versionId),
                                builder: (context, topicSnap) {
                                  if (topicSnap.hasError) {
                                    return _CenterMsg(
                                      text:
                                          "Failed to load topics:\n${topicSnap.error}",
                                    );
                                  }
                                  if (!topicSnap.hasData) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }

                                  final allTopics = topicSnap.data!;
                                  final topicsBySection =
                                      <String, List<HandbookTopicDoc>>{};
                                  for (final topic in allTopics) {
                                    topicsBySection.putIfAbsent(
                                      topic.sectionCode,
                                      () => [],
                                    );
                                    topicsBySection[topic.sectionCode]!.add(
                                      topic,
                                    );
                                  }

                                  final hasSelectedSection =
                                      _selectedSection != null &&
                                      sections.any(
                                        (s) => s.id == _selectedSection!.id,
                                      );
                                  final activeSection = hasSelectedSection
                                      ? _selectedSection!
                                      : sections.first;

                                  final hasSelectedTopic =
                                      _selectedTopic != null &&
                                      allTopics.any(
                                        (t) => t.id == _selectedTopic!.id,
                                      );

                                  if (!hasSelectedSection ||
                                      !hasSelectedTopic) {
                                    HandbookTopicDoc? fallbackTopic;
                                    for (final section in sections) {
                                      final sectionTopics =
                                          topicsBySection[section.code] ??
                                          const [];
                                      if (sectionTopics.isNotEmpty) {
                                        fallbackTopic = sectionTopics.first;
                                        break;
                                      }
                                    }
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (!mounted) return;
                                          setState(() {
                                            _selectedSection = activeSection;
                                            _selectedTopic = hasSelectedTopic
                                                ? _selectedTopic
                                                : fallbackTopic;
                                          });
                                        });
                                  }

                                  return Row(
                                    children: [
                                      SizedBox(
                                        width: 430,
                                        child: ListView.separated(
                                          itemCount: sections.length,
                                          separatorBuilder: (_, _) =>
                                              const SizedBox(height: 10),
                                          itemBuilder: (context, i) {
                                            final section = sections[i];
                                            final isSectionSelected =
                                                _selectedSection?.id ==
                                                section.id;
                                            final sectionTopics =
                                                topicsBySection[section.code] ??
                                                const [];

                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _SectionNavTile(
                                                  code: section.code,
                                                  title: section.title,
                                                  selected: isSectionSelected,
                                                  onTap: () {
                                                    setState(() {
                                                      _selectedSection =
                                                          section;
                                                      if (sectionTopics
                                                          .isEmpty) {
                                                        return;
                                                      }
                                                      _selectedTopic =
                                                          sectionTopics.first;
                                                    });
                                                  },
                                                ),
                                                if (sectionTopics
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  ...sectionTopics.map(
                                                    (topic) => Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 6,
                                                          ),
                                                      child: _TopicNavTile(
                                                        code: topic.code,
                                                        title: topic.title,
                                                        selected:
                                                            _selectedTopic
                                                                ?.id ==
                                                            topic.id,
                                                        onTap: () {
                                                          setState(() {
                                                            _selectedSection =
                                                                section;
                                                            _selectedTopic =
                                                                topic;
                                                          });
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                ] else
                                                  const Padding(
                                                    padding: EdgeInsets.only(
                                                      top: 4,
                                                      bottom: 2,
                                                    ),
                                                    child: Text(
                                                      'No topics yet',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFF8B9489,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: Colors.black.withValues(
                                                alpha: 0.08,
                                              ),
                                            ),
                                          ),
                                          child: _selectedTopic == null
                                              ? const _CenterMsg(
                                                  text:
                                                      'Select a topic from the left sidebar.',
                                                )
                                              : HandbookTopicContentScreen(
                                                  key: ValueKey(
                                                    'shared_desktop_topic_${_selectedTopic!.id}',
                                                  ),
                                                  topic: _selectedTopic!,
                                                  embedded: true,
                                                  onBack: () {
                                                    if (!mounted) return;
                                                    setState(
                                                      () =>
                                                          _selectedTopic = null,
                                                    );
                                                  },
                                                ),
                                        ),
                                      ),
                                    ],
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
            ),
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: _buildHandbookAiFab(heroTag: 'handbook_sections_ai_fab'),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Container(
          color: bg,
          child: SafeArea(
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
                      // Header with title (desktop only)
                      if (isDesktop) ...[
                        Text(
                          'College Student Handbook',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF2B332B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Browse sections and topics',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF8B9489),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],

                      // Search bar (centered on desktop)
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: searchBarMaxWidth,
                          ),
                          child: _SearchBar(
                            controller: _search,
                            hintText: "Search sections...",
                            isDesktop: isDesktop,
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                      ),
                      SizedBox(height: isDesktop ? 32 : (isTablet ? 20 : 12)),

                      // Load active version, then stream sections
                      Expanded(
                        child: FutureBuilder<String>(
                          future: _getActiveVersionId(),
                          builder: (context, metaSnap) {
                            if (metaSnap.hasError) {
                              return _CenterMsg(
                                text: "Error: ${metaSnap.error}",
                              );
                            }
                            if (!metaSnap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final versionId = metaSnap.data!;

                            return StreamBuilder<List<HandbookSectionDoc>>(
                              stream: _sectionsStream(versionId),
                              builder: (context, snap) {
                                if (snap.hasError) {
                                  return _CenterMsg(
                                    text: "Firestore error:\n${snap.error}",
                                  );
                                }
                                if (!snap.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                final all = snap.data!;
                                final filtered = all
                                    .where((s) => _matches(s.title))
                                    .toList();

                                if (filtered.isEmpty) {
                                  return const _CenterMsg(
                                    text: "No matching sections.",
                                  );
                                }

                                // Use GridView for tablet and desktop, ListView for mobile
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
                                      final s = filtered[i];
                                      return _SectionTile(
                                        number: s.code,
                                        title: s.title,
                                        isDesktop: isDesktop,
                                        isTablet: isTablet,
                                        onTap: () {
                                          if (widget.useSidebarDesktop) {
                                            setState(
                                              () => _selectedSection = s,
                                            );
                                            return;
                                          }
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  HandbookTopicsScreen(
                                                    section: s,
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
                                      final s = filtered[i];
                                      return _SectionTile(
                                        number: s.code,
                                        title: s.title,
                                        isDesktop: isDesktop,
                                        isTablet: isTablet,
                                        onTap: () {
                                          if (widget.useSidebarDesktop) {
                                            setState(
                                              () => _selectedSection = s,
                                            );
                                            return;
                                          }
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  HandbookTopicsScreen(
                                                    section: s,
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
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: _buildHandbookAiFab(heroTag: 'handbook_sections_list_ai_fab'),
        ),
      ],
    );
  }
}

// ---------- small UI widgets ----------

class _CenterMsg extends StatelessWidget {
  final String text;
  const _CenterMsg({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SectionNavTile extends StatelessWidget {
  final String code;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _SectionNavTile({
    required this.code,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = selected
        ? const Color(0xFFE9F2E8)
        : const Color(0xFFF5F6F2);
    final borderColor = selected
        ? const Color(0xFF5F7F5C).withValues(alpha: 0.35)
        : Colors.black12;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: bgColor,
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 74,
              height: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF5F7F5C),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                code,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF2B332B),
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: selected
                  ? const Color(0xFF5F7F5C)
                  : const Color(0xFF8B9489),
              size: 28,
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _TopicNavTile extends StatelessWidget {
  final String code;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _TopicNavTile({
    required this.code,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = selected
        ? const Color(0xFFEFF5EC)
        : const Color(0xFFF5F6F2);
    final borderColor = selected
        ? const Color(0xFF5F7F5C).withValues(alpha: 0.30)
        : Colors.black12;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: bgColor,
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 68,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF5F7F5C),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                code,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF2B332B),
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: selected
                  ? const Color(0xFF5F7F5C)
                  : const Color(0xFF8B9489),
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}

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

class _SectionTile extends StatefulWidget {
  final String number;
  final String title;
  final bool isDesktop;
  final bool isTablet;
  final VoidCallback onTap;

  const _SectionTile({
    required this.number,
    required this.title,
    required this.isDesktop,
    required this.isTablet,
    required this.onTap,
  });

  @override
  State<_SectionTile> createState() => _SectionTileState();
}

class _SectionTileState extends State<_SectionTile> {
  bool _isHovered = false;

  static const cardBg = Color(0xFFF5F6F2);
  static const cardShadow = Color(0x22000000);
  static const textDark = Color(0xFF2B332B);
  static const green = Color(0xFF5F7F5C);

  @override
  Widget build(BuildContext context) {
    final height = widget.isDesktop ? 72.0 : (widget.isTablet ? 68.0 : 64.0);
    final borderRadius = widget.isDesktop ? 16.0 : 22.0;
    final numberWidth = widget.isDesktop
        ? 80.0
        : (widget.isTablet ? 76.0 : 72.0);
    final numberSize = widget.isDesktop
        ? 26.0
        : (widget.isTablet ? 24.0 : 22.0);
    final titleSize = widget.isDesktop ? 17.0 : (widget.isTablet ? 16.5 : 16.0);
    final iconSize = widget.isDesktop ? 30.0 : (widget.isTablet ? 29.0 : 28.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.identity()
          ..translateByDouble(
            0.0,
            _isHovered && widget.isDesktop ? -2.0 : 0.0,
            0.0,
            1.0,
          ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: widget.onTap,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: _isHovered && widget.isDesktop
                      ? green.withValues(alpha: 0.3)
                      : Colors.black12,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isHovered && widget.isDesktop
                        ? cardShadow.withValues(alpha: 0.3)
                        : cardShadow,
                    blurRadius: _isHovered && widget.isDesktop ? 20 : 16,
                    offset: Offset(0, _isHovered && widget.isDesktop ? 12 : 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: numberWidth,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: green,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(borderRadius),
                        bottomLeft: Radius.circular(borderRadius),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.number,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: numberSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: widget.isDesktop ? 20 : 14),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: textDark,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w900,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: widget.isDesktop ? 2 : 1,
                    ),
                  ),
                  SizedBox(width: widget.isDesktop ? 16 : 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: const Color(0xFF8B9489),
                    size: iconSize,
                  ),
                  SizedBox(width: widget.isDesktop ? 16 : 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

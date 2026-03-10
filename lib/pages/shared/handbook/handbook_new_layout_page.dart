import 'package:apps/models/handbook_section_doc.dart';
import 'package:apps/models/handbook_topic_doc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'handbook_ai_assistant_sheet.dart';

enum _MobilePanelTab { contents, anchors }

class HandbookNewLayoutPage extends StatefulWidget {
  const HandbookNewLayoutPage({super.key});

  @override
  State<HandbookNewLayoutPage> createState() => _HandbookNewLayoutPageState();
}

class _HandbookNewLayoutPageState extends State<HandbookNewLayoutPage> {
  static const _bg = Color(0xFFF6FAF6);
  static const _primary = Color(0xFF1B5E20);
  static const _text = Color(0xFF1F2A1F);
  static const _muted = Color(0xFF6D7F62);

  final _db = FirebaseFirestore.instance;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchCtrl = TextEditingController();
  final _contentScrollCtrl = ScrollController();
  final Map<String, GlobalKey> _anchorKeys = {};

  bool _loading = true;
  String? _loadError;
  String? _selectedVersionId;
  List<_VersionOption> _versionOptions = const [];

  String _query = '';
  String? _selectedSectionId;
  String? _selectedTopicId;
  _MobilePanelTab _mobilePanelTab = _MobilePanelTab.contents;

  List<_AnchorEntry> _currentAnchors = const [];
  String? _activeAnchorId;

  @override
  void initState() {
    super.initState();
    _contentScrollCtrl.addListener(_updateActiveAnchorFromScroll);
    _loadVersionContext();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _contentScrollCtrl
      ..removeListener(_updateActiveAnchorFromScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }
    if (_loadError != null) {
      return _buildErrorScaffold(_loadError!);
    }
    if (_selectedVersionId == null || _selectedVersionId!.trim().isEmpty) {
      return _buildErrorScaffold('No handbook version is available.');
    }

    final versionId = _selectedVersionId!;
    return StreamBuilder<List<HandbookSectionDoc>>(
      stream: _sectionsStream(versionId),
      builder: (context, sectionSnap) {
        if (sectionSnap.hasError) {
          return _buildErrorScaffold(
            'Failed to load sections:\n${sectionSnap.error}',
          );
        }
        if (!sectionSnap.hasData) {
          return const Scaffold(
            backgroundColor: _bg,
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        final sections = sectionSnap.data!;
        return StreamBuilder<List<HandbookTopicDoc>>(
          stream: _topicsStream(versionId),
          builder: (context, topicSnap) {
            if (topicSnap.hasError) {
              return _buildErrorScaffold(
                'Failed to load topics:\n${topicSnap.error}',
              );
            }
            if (!topicSnap.hasData) {
              return const Scaffold(
                backgroundColor: _bg,
                body: SafeArea(
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final topics = topicSnap.data!;
            final topicsBySection = <String, List<HandbookTopicDoc>>{};
            for (final topic in topics) {
              topicsBySection.putIfAbsent(topic.sectionCode, () => []);
              topicsBySection[topic.sectionCode]!.add(topic);
            }
            for (final list in topicsBySection.values) {
              list.sort((a, b) => a.order.compareTo(b.order));
            }

            final filteredSections = sections.where((section) {
              if (_query.trim().isEmpty) return true;
              if (_matches('${section.code} ${section.title}')) return true;
              final list =
                  topicsBySection[section.code] ?? const <HandbookTopicDoc>[];
              return list.any(
                (topic) => _matches('${topic.code} ${topic.title}'),
              );
            }).toList();

            final flatTopics = <HandbookTopicDoc>[];
            for (final section in sections) {
              flatTopics.addAll(topicsBySection[section.code] ?? const []);
            }

            final selectedTopic = flatTopics
                .where((t) => t.id == _selectedTopicId)
                .firstOrNull;
            if (selectedTopic == null && flatTopics.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _selectedTopicId = flatTopics.first.id;
                  _selectedSectionId = sections
                      .where((s) => s.code == flatTopics.first.sectionCode)
                      .firstOrNull
                      ?.id;
                });
              });
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 1280;
                final isCompact = !isDesktop;

                final contentsPanel = _buildContentsPanel(
                  sections: filteredSections,
                  topicsBySection: topicsBySection,
                );

                return Scaffold(
                  key: _scaffoldKey,
                  backgroundColor: _bg,
                  drawer: isCompact
                      ? Drawer(
                          child: SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: contentsPanel,
                            ),
                          ),
                        )
                      : null,
                  endDrawer: isCompact
                      ? Drawer(
                          child: SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _buildRightPanel(
                                selectedTopic: selectedTopic,
                                compact: true,
                              ),
                            ),
                          ),
                        )
                      : null,
                  body: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTopBar(showTabs: isCompact, compact: isCompact),
                        const Divider(height: 1),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: isDesktop
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: 300,
                                        child: contentsPanel,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildMainReader(
                                          selectedTopic,
                                          flatTopics,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: 270,
                                        child: _buildRightPanel(
                                          selectedTopic: selectedTopic,
                                          compact: false,
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      if (_mobilePanelTab ==
                                          _MobilePanelTab.contents)
                                        SizedBox(
                                          height: 190,
                                          child: contentsPanel,
                                        ),
                                      if (_mobilePanelTab ==
                                          _MobilePanelTab.anchors)
                                        SizedBox(
                                          height: 190,
                                          child: _buildRightPanel(
                                            selectedTopic: selectedTopic,
                                            compact: true,
                                          ),
                                        ),
                                      const SizedBox(height: 10),
                                      Expanded(
                                        child: _buildMainReader(
                                          selectedTopic,
                                          flatTopics,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  floatingActionButton: FloatingActionButton(
                    heroTag: 'handbook_new_layout_ai_fab',
                    onPressed: () => showHandbookAiAssistantSheet(context),
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    tooltip: 'Open Handbook AI',
                    child: const Icon(Icons.menu_book_rounded),
                  ),
                  floatingActionButtonLocation:
                      FloatingActionButtonLocation.endFloat,
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _loadVersionContext() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final currentMeta = await _db
          .collection('handbook_meta')
          .doc('current')
          .get();
      final activeVersionId = (currentMeta.data()?['activeVersionId'] ?? '')
          .toString()
          .trim();
      final activeVersionLabel =
          (currentMeta.data()?['activeVersionLabel'] ?? activeVersionId)
              .toString()
              .trim();

      final versionSnap = await _db.collection('handbook_versions').get();
      final options = <_VersionOption>[];
      for (final doc in versionSnap.docs) {
        final versionId = doc.id.trim();
        if (versionId.isEmpty) continue;
        final data = doc.data();
        final label = (data['label'] ?? versionId).toString().trim();
        options.add(_VersionOption(id: versionId, label: label));
      }
      if (options.isEmpty && activeVersionId.isNotEmpty) {
        options.add(
          _VersionOption(
            id: activeVersionId,
            label: activeVersionLabel.isEmpty
                ? activeVersionId
                : activeVersionLabel,
          ),
        );
      }
      options.sort((a, b) => b.id.compareTo(a.id));

      if (!mounted) return;
      setState(() {
        _versionOptions = options;
        _selectedVersionId = activeVersionId.isNotEmpty
            ? activeVersionId
            : (options.isNotEmpty ? options.first.id : null);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _updateActiveAnchorFromScroll() {
    if (_currentAnchors.isEmpty) return;
    String? activeId;
    double bestTop = -999999;
    for (final entry in _currentAnchors) {
      final context = entry.key.currentContext;
      if (context == null) continue;
      final render = context.findRenderObject();
      if (render is! RenderBox || !render.attached) continue;
      final top = render.localToGlobal(Offset.zero).dy;
      if (top <= 185 && top > bestTop) {
        bestTop = top;
        activeId = entry.id;
      }
    }
    activeId ??= _currentAnchors.first.id;
    if (activeId != _activeAnchorId && mounted) {
      setState(() => _activeAnchorId = activeId);
    }
  }

  Stream<List<HandbookSectionDoc>> _sectionsStream(String versionId) {
    return _db
        .collection('handbook_sections')
        .where('versionId', isEqualTo: versionId)
        .snapshots()
        .map((q) {
          final sections = q.docs
              .map((d) => HandbookSectionDoc.fromDoc(d))
              .where((s) => s.isPublished)
              .toList();
          sections.sort((a, b) => a.order.compareTo(b.order));
          return sections;
        });
  }

  Stream<List<HandbookTopicDoc>> _topicsStream(String versionId) {
    return _db
        .collection('handbook_topics')
        .where('versionId', isEqualTo: versionId)
        .snapshots()
        .map((q) {
          final topics = q.docs
              .map((d) => HandbookTopicDoc.fromDoc(d))
              .where((t) => t.isPublished)
              .toList();
          topics.sort((a, b) {
            final secCompare = a.sectionCode.compareTo(b.sectionCode);
            if (secCompare != 0) return secCompare;
            return a.order.compareTo(b.order);
          });
          return topics;
        });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _contentStream(
    String topicId,
  ) {
    return _db.collection('handbook_contents').doc(topicId).snapshots();
  }

  bool _matches(String value) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return value.toLowerCase().contains(q);
  }

  GlobalKey _anchorKey(String id) {
    return _anchorKeys.putIfAbsent(id, GlobalKey.new);
  }

  Future<void> _scrollToAnchor(String anchorId) async {
    final entry = _currentAnchors.where((a) => a.id == anchorId).firstOrNull;
    if (entry == null) return;
    final context = entry.key.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.10,
    );
  }

  List<_AnchorEntry> _extractAnchors(List<dynamic> blocks) {
    final anchors = <_AnchorEntry>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block is! Map) continue;
      final map = block.cast<String, dynamic>();
      final type = (map['type'] ?? '').toString();
      if (type != 'h1' && type != 'h2' && type != 'subsection') continue;
      final anchorTitle = type == 'subsection'
          ? '${(map['number'] ?? '').toString().trim()} ${(map['title'] ?? '').toString().trim()}'
                .trim()
          : (map['text'] ?? '').toString().trim();
      if (anchorTitle.isEmpty) continue;

      final anchorId = '${type}_$i';
      anchors.add(
        _AnchorEntry(
          id: anchorId,
          title: anchorTitle,
          key: _anchorKey(anchorId),
        ),
      );
    }
    return anchors;
  }

  Widget _buildTopBar({required bool showTabs, required bool compact}) {
    final activeVersionLabel =
        _versionOptions
            .where((v) => v.id == _selectedVersionId)
            .firstOrNull
            ?.label ??
        (_selectedVersionId ?? '--');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: compact
                    ? () => _scaffoldKey.currentState?.openDrawer()
                    : null,
                icon: Icon(
                  Icons.menu_rounded,
                  color: compact ? _primary : Colors.black26,
                ),
                tooltip: 'Contents',
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Digital Student Handbook',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _primary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              IconButton(
                onPressed: compact
                    ? () => _scaffoldKey.currentState?.openEndDrawer()
                    : null,
                icon: Icon(
                  Icons.view_sidebar_outlined,
                  color: compact ? _primary : Colors.black26,
                ),
                tooltip: 'On this page',
              ),
              const CircleAvatar(
                radius: 15,
                backgroundColor: Color(0xFFE8EFE8),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: _muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: compact ? 300 : 360, child: _searchField()),
              SizedBox(width: 260, child: _versionDropdown()),
              _headerChip('Active Version', activeVersionLabel),
            ],
          ),
          const SizedBox(height: 10),
          if (showTabs) ...[_buildCompactTabs(), const SizedBox(height: 10)],
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (value) => setState(() => _query = value),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          hintText: 'Search handbook...',
          hintStyle: TextStyle(
            color: _muted,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: _muted),
        ),
        style: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _versionDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedVersionId,
      items: _versionOptions
          .map(
            (version) => DropdownMenuItem<String>(
              value: version.id,
              child: Text(
                version.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null || value == _selectedVersionId) return;
        setState(() {
          _selectedVersionId = value;
          _selectedSectionId = null;
          _selectedTopicId = null;
          _activeAnchorId = null;
        });
      },
      decoration: InputDecoration(
        labelText: 'Handbook version',
        labelStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
      ),
    );
  }

  Widget _buildCompactTabs() {
    final selectedIndex = _mobilePanelTab == _MobilePanelTab.contents ? 0 : 1;
    return DefaultTabController(
      key: ValueKey(selectedIndex),
      length: 2,
      initialIndex: selectedIndex,
      child: Material(
        color: Colors.white,
        child: TabBar(
          labelColor: _primary,
          unselectedLabelColor: Colors.black54,
          indicatorColor: _primary,
          indicatorWeight: 2,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.black.withValues(alpha: 0.08),
          onTap: (index) {
            final next = index == 0
                ? _MobilePanelTab.contents
                : _MobilePanelTab.anchors;
            if (next == _mobilePanelTab) return;
            setState(() => _mobilePanelTab = next);
          },
          tabs: const [
            Tab(text: 'Contents'),
            Tab(text: 'On This Page'),
          ],
        ),
      ),
    );
  }

  Widget _headerChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _primary.withValues(alpha: 0.16)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'Roboto'),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainReader(
    HandbookTopicDoc? selectedTopic,
    List<HandbookTopicDoc> orderedTopics,
  ) {
    if (selectedTopic == null) {
      return _surface(
        child: const Center(
          child: Text(
            'Select a topic from the contents.',
            style: TextStyle(color: _muted, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _contentStream(selectedTopic.id),
      builder: (context, contentSnap) {
        if (contentSnap.hasError) {
          return _surface(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load topic content:\n${contentSnap.error}',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        if (!contentSnap.hasData) {
          return _surface(
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final contentData =
            contentSnap.data?.data() ?? const <String, dynamic>{};
        final blocks =
            (contentData['publishedBlocks'] as List<dynamic>?) ??
            (contentData['blocks'] as List<dynamic>? ?? const []);
        final anchors = _extractAnchors(blocks);
        _currentAnchors = anchors;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _updateActiveAnchorFromScroll(),
        );

        final topicIndex = orderedTopics.indexWhere(
          (t) => t.id == selectedTopic.id,
        );
        final prevTopic = topicIndex > 0 ? orderedTopics[topicIndex - 1] : null;
        final nextTopic =
            topicIndex >= 0 && topicIndex < orderedTopics.length - 1
            ? orderedTopics[topicIndex + 1]
            : null;

        return _surface(
          child: SingleChildScrollView(
            controller: _contentScrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Handbook / ${selectedTopic.sectionCode} / ${selectedTopic.code}',
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${selectedTopic.code} ${selectedTopic.title}',
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F7F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _primary.withValues(alpha: 0.20)),
                  ),
                  child: const Text(
                    'Read carefully and review related policies before taking action. This page follows the currently selected handbook version.',
                    style: TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ..._buildBlockWidgets(blocks, anchors),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: prevTopic == null
                            ? null
                            : () => setState(
                                () => _selectedTopicId = prevTopic.id,
                              ),
                        child: Text(
                          prevTopic == null
                              ? 'Previous'
                              : '← ${prevTopic.code}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: nextTopic == null
                            ? null
                            : () => setState(
                                () => _selectedTopicId = nextTopic.id,
                              ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _primary,
                        ),
                        child: Text(
                          nextTopic == null ? 'Next' : '${nextTopic.code} →',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildBlockWidgets(
    List<dynamic> blocks,
    List<_AnchorEntry> anchors,
  ) {
    final widgets = <Widget>[];
    final anchorById = {for (final anchor in anchors) anchor.id: anchor};

    for (var i = 0; i < blocks.length; i++) {
      final raw = blocks[i];
      if (raw is! Map) continue;
      final block = raw.cast<String, dynamic>();
      final type = (block['type'] ?? 'p').toString();
      final anchorId = '${type}_$i';
      final anchor = anchorById[anchorId];

      if (type == 'h1') {
        widgets.add(
          Padding(
            key: anchor?.key,
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              (block['text'] ?? '').toString(),
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w900,
                fontSize: 24,
                height: 1.2,
              ),
            ),
          ),
        );
      } else if (type == 'h2') {
        widgets.add(
          Padding(
            key: anchor?.key,
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Text(
              (block['text'] ?? '').toString(),
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w900,
                fontSize: 19,
                height: 1.25,
              ),
            ),
          ),
        );
      } else if (type == 'subsection') {
        widgets.add(_subsectionBlock(block, anchor?.key));
      } else if (type == 'image') {
        final url = (block['url'] ?? '').toString().trim();
        if (url.isNotEmpty) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 160,
                    color: const Color(0xFFE8EDE8),
                    alignment: Alignment.center,
                    child: const Text('Image unavailable'),
                  ),
                ),
              ),
            ),
          );
        }
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              (block['text'] ?? '').toString(),
              style: const TextStyle(
                color: Color(0xFF344034),
                fontWeight: FontWeight.w600,
                height: 1.62,
                fontSize: 15,
              ),
            ),
          ),
        );
      }
    }

    if (widgets.isEmpty) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'No published content yet for this topic.',
            style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _subsectionBlock(Map<String, dynamic> block, Key? key) {
    final number = (block['number'] ?? '').toString();
    final title = (block['title'] ?? '').toString();
    final text = (block['text'] ?? '').toString();
    return Container(
      key: key,
      margin: const EdgeInsets.only(top: 10, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number $title'.trim(),
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          if (text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFF344034),
                fontWeight: FontWeight.w600,
                height: 1.55,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContentsPanel({
    required List<HandbookSectionDoc> sections,
    required Map<String, List<HandbookTopicDoc>> topicsBySection,
  }) {
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Handbook Contents',
              style: TextStyle(
                color: _text,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: sections.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching sections.',
                        style: TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: sections.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final section = sections[i];
                        final topics =
                            topicsBySection[section.code] ??
                            const <HandbookTopicDoc>[];
                        final selected = _selectedSectionId == section.id;
                        return Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? _primary.withValues(alpha: 0.08)
                                : const Color(0xFFF6F8F6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? _primary.withValues(alpha: 0.35)
                                  : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            initiallyExpanded: selected,
                            onExpansionChanged: (_) {
                              setState(() => _selectedSectionId = section.id);
                            },
                            title: Text(
                              '${section.code} ${section.title}',
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            children: topics.isEmpty
                                ? const [
                                    Padding(
                                      padding: EdgeInsets.only(bottom: 10),
                                      child: Text(
                                        'No topics yet',
                                        style: TextStyle(
                                          color: _muted,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ]
                                : topics
                                      .where(
                                        (topic) =>
                                            _query.trim().isEmpty ||
                                            _matches(
                                              '${topic.code} ${topic.title}',
                                            ),
                                      )
                                      .map(
                                        (topic) => ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
                                          title: Text(
                                            '${topic.code} ${topic.title}',
                                            style: TextStyle(
                                              color:
                                                  _selectedTopicId == topic.id
                                                  ? _primary
                                                  : _text,
                                              fontWeight:
                                                  _selectedTopicId == topic.id
                                                  ? FontWeight.w900
                                                  : FontWeight.w700,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _selectedSectionId = section.id;
                                              _selectedTopicId = topic.id;
                                            });
                                          },
                                        ),
                                      )
                                      .toList(),
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

  Widget _buildRightPanel({
    required HandbookTopicDoc? selectedTopic,
    required bool compact,
  }) {
    return Column(
      children: [
        Expanded(
          flex: 8,
          child: _surface(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'On this page',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _currentAnchors.isEmpty
                        ? const Center(
                            child: Text(
                              'No headings yet.',
                              style: TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _currentAnchors.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final anchor = _currentAnchors[i];
                              final active = _activeAnchorId == anchor.id;
                              return InkWell(
                                onTap: () => _scrollToAnchor(anchor.id),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? _primary.withValues(alpha: 0.12)
                                        : const Color(0xFFF6F8F6),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: active
                                          ? _primary.withValues(alpha: 0.35)
                                          : Colors.black.withValues(
                                              alpha: 0.06,
                                            ),
                                    ),
                                  ),
                                  child: Text(
                                    anchor.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: active ? _primary : _text,
                                      fontWeight: active
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          flex: compact ? 5 : 4,
          child: _surface(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Related',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _relatedLink('FAQs'),
                  _relatedLink('Office Procedures'),
                  _relatedLink('Downloadable Forms'),
                  const Spacer(),
                  if (selectedTopic != null)
                    Text(
                      'Topic: ${selectedTopic.code}',
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _relatedLink(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.chevron_right_rounded, size: 16, color: _muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _surface({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }

  Widget _buildErrorScaffold(String message) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionOption {
  final String id;
  final String label;

  const _VersionOption({required this.id, required this.label});
}

class _AnchorEntry {
  final String id;
  final String title;
  final GlobalKey key;

  const _AnchorEntry({
    required this.id,
    required this.title,
    required this.key,
  });
}

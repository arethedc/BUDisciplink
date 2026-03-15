import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart'
    as quill_ext;

import 'handbook_ai_assistant_sheet.dart';

const String _hbTableEmbedType = 'x-embed-table';

class HbHandbookPage extends StatefulWidget {
  final bool useSidebarDesktop;
  final String? forcedVersionId;
  final String? forcedVersionLabel;
  final bool showAiFab;
  final bool hideTopHeader;

  const HbHandbookPage({
    super.key,
    this.useSidebarDesktop = true,
    this.forcedVersionId,
    this.forcedVersionLabel,
    this.showAiFab = true,
    this.hideTopHeader = false,
  });

  @override
  State<HbHandbookPage> createState() => _HbHandbookPageState();
}

class _HbHandbookPageState extends State<HbHandbookPage> {
  static const _bg = Colors.white;
  static const _primary = Color(0xFF1B5E20);
  static const _text = Color(0xFF1F2A1F);
  static const _muted = Color(0xFF6D7F62);

  static const _colHbVersion = 'hb_version';
  static const _colHbSection = 'hb_section';
  static const _colHbContents = 'hb_contents';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  String _query = '';
  String? _selectedSectionId;
  bool _mobileShowContent = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  quill.Document _parseDocument(String rawContent) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) {
      return quill.Document()..insert(0, '\n');
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        final normalizedOps = <Map<String, dynamic>>[];
        for (final rawOp in decoded) {
          if (rawOp is! Map) continue;
          final op = Map<String, dynamic>.from(rawOp);
          final insert = op['insert'];
          if (insert is Map) {
            final map = Map<String, dynamic>.from(insert);
            if (map.containsKey(_hbTableEmbedType)) {
              normalizedOps.add({
                'insert': {_hbTableEmbedType: map[_hbTableEmbedType].toString()},
              });
              continue;
            }
          }
          normalizedOps.add(op);
        }
        if (normalizedOps.isEmpty) {
          normalizedOps.add({'insert': '\n'});
        }
        final lastInsert = normalizedOps.last['insert'];
        if (lastInsert is String && !lastInsert.endsWith('\n')) {
          normalizedOps.add({'insert': '\n'});
        }
        return quill.Document.fromJson(normalizedOps);
      }
    } catch (_) {}

    return quill.Document()..insert(0, '$trimmed\n');
  }

  bool _hasDisplayableContent(String rawContent) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) return false;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        for (final rawOp in decoded) {
          if (rawOp is! Map) continue;
          final op = Map<String, dynamic>.from(rawOp);
          final insert = op['insert'];
          if (insert is String && insert.replaceAll('\n', '').trim().isNotEmpty) {
            return true;
          }
          if (insert is Map && insert.isNotEmpty) return true;
        }
        return false;
      }
    } catch (_) {}

    return trimmed.isNotEmpty;
  }

  bool _matches(_HbSection section) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return section.title.toLowerCase().contains(q) ||
        section.code.toLowerCase().contains(q);
  }

  List<_SectionRow> _flattenSections(List<_HbSection> sections) {
    final byParent = <String, List<_HbSection>>{};
    for (final section in sections) {
      byParent.putIfAbsent(section.parentId, () => <_HbSection>[]);
      byParent[section.parentId]!.add(section);
    }

    for (final list in byParent.values) {
      list.sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }

    final rows = <_SectionRow>[];
    void walk(String parentId, int depth) {
      final children = byParent[parentId] ?? const <_HbSection>[];
      for (final child in children) {
        rows.add(_SectionRow(section: child, depth: depth));
        walk(child.id, depth + 1);
      }
    }

    walk('', 0);
    return rows;
  }

  void _ensureSelection(List<_SectionRow> rows) {
    if (rows.isEmpty) return;
    final hasSelected = _selectedSectionId != null &&
        rows.any((row) => row.section.id == _selectedSectionId);
    if (hasSelected) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedSectionId = rows.first.section.id);
    });
  }

  Map<String, String> _buildDisplayCodeBySectionId(List<_SectionRow> rows) {
    final codeBySectionId = <String, String>{};
    final levelCounters = <int>[];

    for (final row in rows) {
      final depth = row.depth < 0 ? 0 : row.depth;

      while (levelCounters.length <= depth) {
        levelCounters.add(0);
      }
      if (levelCounters.length > depth + 1) {
        levelCounters.removeRange(depth + 1, levelCounters.length);
      }

      if (!row.section.useSectionNumbering) {
        codeBySectionId[row.section.id] = '';
        continue;
      }

      levelCounters[depth] = levelCounters[depth] + 1;
      codeBySectionId[row.section.id] = levelCounters
          .take(depth + 1)
          .where((value) => value > 0)
          .join('.');
    }

    return codeBySectionId;
  }

  String _displayTitle(_HbSection section) {
    final raw = section.title.trim();
    if (raw.isEmpty) return '(Untitled section)';

    var cleaned = raw.replaceFirst(
      RegExp(
        r'^\s*section\s*\d+(?:\.\d+)*\s*[:\-]?\s*',
        caseSensitive: false,
      ),
      '',
    );

    if (section.code.trim().isNotEmpty) {
      final escaped = RegExp.escape(section.code.trim());
      cleaned = cleaned.replaceFirst(
        RegExp('^\\s*$escaped\\s*[:\\-]?\\s*', caseSensitive: false),
        '',
      );
    }

    cleaned = cleaned.trim();
    return cleaned.isEmpty ? raw : cleaned;
  }

  String _composeSectionHeading({
    required String code,
    required String title,
  }) {
    final trimmedCode = code.trim();
    return trimmedCode.isEmpty ? title : '$trimmedCode. $title';
  }

  Widget _buildHeader({
    required bool isDesktop,
    required String activeVersionLabel,
    required int sectionCount,
  }) {
    final titleSize = isDesktop ? 26.0 : 22.0;
    final subtitleSize = isDesktop ? 13.0 : 12.0;

    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 20 : 16,
        isDesktop ? 16 : 14,
        isDesktop ? 20 : 16,
        isDesktop ? 14 : 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'College Student Handbook',
            style: TextStyle(
              color: _text,
              fontSize: titleSize,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Browse entries and content',
            style: TextStyle(
              color: _muted.withValues(alpha: 0.85),
              fontSize: subtitleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Version', activeVersionLabel),
              _chip('Entries', '$sectionCount'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _primary.withValues(alpha: 0.18)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSectionsPanel(
    List<_SectionRow> rows, {
    required Map<String, String> codeBySectionId,
    required bool isDesktop,
  }) {
    final filtered = rows.where((row) => _matches(row.section)).toList();
    final viewRows = filtered.isNotEmpty ? filtered : rows;
    _ensureSelection(viewRows);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: _ClassicSearchBar(
              controller: _searchCtrl,
              hintText: 'Search entries...',
              isDesktop: isDesktop,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: viewRows.isEmpty
                ? const _CenterMsg(
                    text: 'No entries available.',
                    color: _muted,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    itemCount: viewRows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = viewRows[index];
                      final section = row.section;
                      final selected = section.id == _selectedSectionId;
                      final leftPad = row.depth > 0 ? 16.0 * row.depth : 0.0;

                      return Padding(
                        padding: EdgeInsets.only(left: leftPad),
                        child: _HbSectionTile(
                          code: codeBySectionId[section.id] ?? '',
                          title: _displayTitle(section),
                          selected: selected,
                          nested: row.depth > 0,
                          onTap: () {
                            setState(() {
                              _selectedSectionId = section.id;
                              _mobileShowContent = true;
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentPanel({
    required _HbSection? selectedSection,
    required String selectedSectionCode,
    required String activeVersionLabel,
    required bool embedded,
    VoidCallback? onBack,
  }) {
    if (selectedSection == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: const _CenterMsg(
          text: 'Select an entry to view its content.',
          color: _muted,
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection(_colHbContents).doc(selectedSection.id).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final rawValue = data['content'];
        final rawContent = rawValue is String
            ? rawValue
            : (rawValue == null ? '' : jsonEncode(rawValue));
        final hasContent = _hasDisplayableContent(rawContent);
        final title = _displayTitle(selectedSection);
        final heading = _composeSectionHeading(
          code: selectedSectionCode,
          title: title,
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (embedded)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        tooltip: 'Back to entries',
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Handbook / Entry',
                              style: TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              heading,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Version: $activeVersionLabel',
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: !hasContent
                    ? const _CenterMsg(
                        text: 'No content yet for this section.',
                        color: _muted,
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                        child: _ReadOnlyQuillView(
                          document: _parseDocument(rawContent),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1024;
    final forcedVersionId = (widget.forcedVersionId ?? '').trim();
    final usingForcedVersion = forcedVersionId.isNotEmpty;

    Widget buildVersionBody({
      required String versionId,
      required String versionLabel,
    }) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection(_colHbSection)
            .where('versionId', isEqualTo: versionId)
            .snapshots(),
        builder: (context, sectionSnap) {
          if (sectionSnap.hasError) {
            return Center(
              child: Text(
                'Failed to load sections: ${sectionSnap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }
          if (!sectionSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final sections = sectionSnap.data!.docs
              .map(_HbSection.fromDoc)
              .where((s) => s.isVisible && s.status != 'archived')
              .toList(growable: false);

          final rows = _flattenSections(sections);
          final codeBySectionId = _buildDisplayCodeBySectionId(rows);
          _HbSection? selectedSection;
          for (final row in rows) {
            if (row.section.id == _selectedSectionId) {
              selectedSection = row.section;
              break;
            }
          }

          final sectionsPanel = _buildSectionsPanel(
            rows,
            codeBySectionId: codeBySectionId,
            isDesktop: isDesktop,
          );
          final contentPanel = _buildContentPanel(
            selectedSection: selectedSection,
            selectedSectionCode: selectedSection == null
                ? ''
                : (codeBySectionId[selectedSection.id] ?? ''),
            activeVersionLabel: versionLabel,
            embedded: !isDesktop && _mobileShowContent,
            onBack: () => setState(() => _mobileShowContent = false),
          );

          return Stack(
            children: [
              Container(
                color: _bg,
                child: Column(
                  children: [
                    if (!widget.hideTopHeader) ...[
                      _buildHeader(
                        isDesktop: isDesktop,
                        activeVersionLabel: versionLabel,
                        sectionCount: sections.length,
                      ),
                      const Divider(height: 1),
                    ],
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(isDesktop ? 14 : 12),
                        child: isDesktop
                            ? Row(
                                children: [
                                  SizedBox(width: 430, child: sectionsPanel),
                                  const SizedBox(width: 12),
                                  Expanded(child: contentPanel),
                                ],
                              )
                            : (_mobileShowContent ? contentPanel : sectionsPanel),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showAiFab)
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: FloatingActionButton(
                    heroTag: null,
                    onPressed: () => showHandbookAiAssistantSheet(context),
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    tooltip: 'Open Handbook AI',
                    child: const Icon(Icons.menu_book_rounded),
                  ),
                ),
            ],
          );
        },
      );
    }

    if (usingForcedVersion) {
      final forcedLabel = (widget.forcedVersionLabel ?? forcedVersionId)
          .toString()
          .trim();
      return buildVersionBody(
        versionId: forcedVersionId,
        versionLabel: forcedLabel.isEmpty ? forcedVersionId : forcedLabel,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection(_colHbVersion).doc('current').snapshots(),
      builder: (context, metaSnap) {
        if (metaSnap.hasError) {
          return Center(
            child: Text(
              'Failed to load handbook version: ${metaSnap.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }
        if (!metaSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final meta = metaSnap.data!.data() ?? const <String, dynamic>{};
        final activeVersionId = (meta['activeVersionId'] ?? '').toString().trim();
        final activeVersionLabel = (meta['activeVersionLabel'] ?? activeVersionId)
            .toString()
            .trim();

        if (activeVersionId.isEmpty) {
          return const Center(
            child: Text(
              'No active handbook version found.',
              style: TextStyle(color: _muted, fontWeight: FontWeight.w800),
            ),
          );
        }

        return buildVersionBody(
          versionId: activeVersionId,
          versionLabel: activeVersionLabel.isEmpty
              ? activeVersionId
              : activeVersionLabel,
        );
      },
    );
  }
}

class _ReadOnlyQuillView extends StatefulWidget {
  final quill.Document document;

  const _ReadOnlyQuillView({required this.document});

  @override
  State<_ReadOnlyQuillView> createState() => _ReadOnlyQuillViewState();
}

class _ReadOnlyQuillViewState extends State<_ReadOnlyQuillView> {
  late quill.QuillController _controller;

  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController(
      document: widget.document,
      selection: const TextSelection.collapsed(offset: 0),
    )..readOnly = true;
  }

  @override
  void didUpdateWidget(covariant _ReadOnlyQuillView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.document, widget.document)) return;
    final old = _controller;
    _controller = quill.QuillController(
      document: widget.document,
      selection: const TextSelection.collapsed(offset: 0),
    )..readOnly = true;
    old.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final embedBuilders = kIsWeb
        ? quill_ext.FlutterQuillEmbeds.editorWebBuilders()
        : quill_ext.FlutterQuillEmbeds.editorBuilders();

    return quill.QuillEditor.basic(
      controller: _controller,
      config: quill.QuillEditorConfig(
        autoFocus: false,
        showCursor: false,
        expands: false,
        scrollable: true,
        enableInteractiveSelection: true,
        padding: EdgeInsets.zero,
        embedBuilders: embedBuilders,
        unknownEmbedBuilder: const _HbUnknownEmbedBuilder(),
      ),
    );
  }
}

class _HbSection {
  final String id;
  final String versionId;
  final String parentId;
  final int sortOrder;
  final String title;
  final String code;
  final bool useSectionNumbering;
  final bool isVisible;
  final String status;

  const _HbSection({
    required this.id,
    required this.versionId,
    required this.parentId,
    required this.sortOrder,
    required this.title,
    required this.code,
    required this.useSectionNumbering,
    required this.isVisible,
    required this.status,
  });

  factory _HbSection.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    int sortOrder = 0;
    final rawOrder = data['sortOrder'];
    if (rawOrder is int) {
      sortOrder = rawOrder;
    } else if (rawOrder is num) {
      sortOrder = rawOrder.toInt();
    }

    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    final isVisibleRaw = data['isVisible'];
    final isVisible = isVisibleRaw is bool ? isVisibleRaw : true;
    final useSectionNumberingRaw = data['useSectionNumbering'];
    final useSectionNumbering = useSectionNumberingRaw is bool
        ? useSectionNumberingRaw
        : true;

    return _HbSection(
      id: doc.id,
      versionId: (data['versionId'] ?? '').toString().trim(),
      parentId: (data['parentId'] ?? '').toString().trim(),
      sortOrder: sortOrder,
      title: (data['title'] ?? '(Untitled section)').toString().trim(),
      code: (data['code'] ?? '').toString().trim(),
      useSectionNumbering: useSectionNumbering,
      isVisible: isVisible,
      status: status,
    );
  }
}

class _SectionRow {
  final _HbSection section;
  final int depth;

  const _SectionRow({required this.section, required this.depth});
}

class _HbUnknownEmbedBuilder extends quill.EmbedBuilder {
  const _HbUnknownEmbedBuilder();

  @override
  String get key => '__unknown_embed__';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final embedType = embedContext.node.value.type;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
      ),
      child: Text(
        'Embedded block: $embedType',
        style: const TextStyle(
          color: Color(0xFF6D7F62),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _CenterMsg extends StatelessWidget {
  final String text;
  final Color color;

  const _CenterMsg({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ClassicSearchBar extends StatelessWidget {
  static const _searchMuted = Color(0xFF6D7F62);

  final TextEditingController controller;
  final String hintText;
  final bool isDesktop;
  final ValueChanged<String> onChanged;

  const _ClassicSearchBar({
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
          Icon(Icons.search_rounded, color: _searchMuted, size: iconSize),
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
                  color: _searchMuted,
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

class _HbSectionTile extends StatelessWidget {
  static const _headerGreen = Color(0xFF1B5E20);
  final String code;
  final String title;
  final bool selected;
  final bool nested;
  final VoidCallback onTap;

  const _HbSectionTile({
    required this.code,
    required this.title,
    required this.selected,
    required this.nested,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasCode = code.trim().isNotEmpty;
    final bgColor = selected
        ? _headerGreen.withValues(alpha: 0.10)
        : Colors.white;
    final borderColor = selected
        ? _headerGreen.withValues(alpha: 0.35)
        : Colors.black12;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: nested ? 58 : 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: bgColor,
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            if (hasCode)
              Container(
                width: nested ? 62 : 74,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: _headerGreen,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  code,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: nested ? 15 : 21,
                  ),
                ),
              ),
            SizedBox(width: hasCode ? 12 : 14),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF2B332B),
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                  fontSize: nested ? 14 : 15.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: selected ? _headerGreen : const Color(0xFF8B9489),
              size: 26,
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

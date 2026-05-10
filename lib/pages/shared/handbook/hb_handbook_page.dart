import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart'
    as quill_ext;

import 'handbook_ai_assistant_sheet.dart';

const String _hbTableEmbedType = 'x-embed-table';

Map<String, dynamic> _normalizeHbTablePayload(String raw) {
  const fallback = {
    'headers': <String>[''],
    'rows': <List<String>>[
      <String>[''],
    ],
    'columnWidths': <double>[0],
    'cellStyles': <String, dynamic>{},
  };

  Map<String, dynamic>? decodeMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, data) => MapEntry(key.toString(), data),
      );
    }
    return null;
  }

  dynamic data = raw.trim();
  Map<String, dynamic>? parsed;
  for (var i = 0; i < 2; i++) {
    final map = decodeMap(data);
    if (map != null) {
      parsed = map;
      break;
    }
    if (data is! String || data.trim().isEmpty) break;
    try {
      data = jsonDecode(data);
    } catch (_) {
      break;
    }
  }

  if (parsed == null) return fallback;

  final headersRaw = parsed['headers'];
  final headers = headersRaw is List
      ? headersRaw.map((e) => e?.toString() ?? '').toList(growable: false)
      : const <String>[];
  final normalizedHeaders = headers.isEmpty ? const [''] : headers;
  final columns = normalizedHeaders.length;

  final rowsRaw = parsed['rows'];
  final rows = <List<String>>[];
  if (rowsRaw is List) {
    for (final row in rowsRaw) {
      if (row is! List) continue;
      final cells = row.map((e) => e?.toString() ?? '').toList(growable: false);
      if (cells.length < columns) {
        rows.add([...cells, ...List<String>.filled(columns - cells.length, '')]);
      } else if (cells.length > columns) {
        rows.add(cells.sublist(0, columns));
      } else {
        rows.add(cells);
      }
    }
  }
  final normalizedRows = rows.isEmpty
      ? <List<String>>[List<String>.filled(columns, '', growable: false)]
      : rows;

  final widthRaw = parsed['columnWidths'];
  final widths = List<double>.filled(columns, 0, growable: false);
  if (widthRaw is List) {
    final max = widthRaw.length < columns ? widthRaw.length : columns;
    for (var i = 0; i < max; i++) {
      final value = widthRaw[i];
      if (value is num && value.isFinite) {
        widths[i] = value.toDouble().clamp(110, 520);
      } else if (value is String) {
        final parsedWidth = double.tryParse(value.trim());
        if (parsedWidth != null && parsedWidth.isFinite) {
          widths[i] = parsedWidth.clamp(110, 520);
        }
      }
    }
  }

  final stylesRaw = parsed['cellStyles'];
  final styles = <String, Map<String, dynamic>>{};
  if (stylesRaw is Map) {
    stylesRaw.forEach((k, v) {
      if (v is! Map) return;
      final map = v.map((key, value) => MapEntry(key.toString(), value));
      final alignRaw = (map['align'] ?? '').toString().trim();
      final fontRaw = (map['font'] ?? '').toString().trim();
      final sizeRaw = map['size'];
      final size = switch (sizeRaw) {
        int value => value.clamp(10, 32),
        num value => value.round().clamp(10, 32),
        String value => (int.tryParse(value.trim()) ?? 12).clamp(10, 32),
        _ => 12,
      };
      styles[k.toString()] = {
        'bold': map['bold'] == true,
        'italic': map['italic'] == true,
        'align': switch (alignRaw) {
          'center' => 'center',
          'right' => 'right',
          'justify' => 'justify',
          _ => 'left',
        },
        'font': switch (fontRaw) {
          'serif' => 'serif',
          'monospace' => 'monospace',
          'sans-serif' => 'sans-serif',
          _ => 'default',
        },
        'size': size,
      };
    });
  }

  return {
    'headers': normalizedHeaders,
    'rows': normalizedRows,
    'columnWidths': widths,
    'cellStyles': styles,
  };
}

class _HbTableEmbedBuilder extends quill.EmbedBuilder {
  const _HbTableEmbedBuilder();

  @override
  String get key => _hbTableEmbedType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final payload = _normalizeHbTablePayload(
      embedContext.node.value.data.toString(),
    );
    return _HbReadOnlyTable(payload: payload);
  }
}

class _HbReadOnlyTable extends StatelessWidget {
  const _HbReadOnlyTable({required this.payload});

  final Map<String, dynamic> payload;

  static const double _minColWidth = 110;
  static const double _maxColWidth = 520;

  TextAlign _cellAlign(Map<String, dynamic> style) {
    final raw = (style['align'] ?? 'left').toString();
    return switch (raw) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.left,
    };
  }

  String? _fontFamily(Map<String, dynamic> style) {
    final raw = (style['font'] ?? 'default').toString();
    return switch (raw) {
      'serif' => 'serif',
      'monospace' => 'monospace',
      'sans-serif' => 'sans-serif',
      _ => null,
    };
  }

  List<double> _resolvedWidths({
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> configured,
    required double maxWidth,
  }) {
    final auto = <double>[];
    for (var col = 0; col < headers.length; col++) {
      var maxLen = headers[col].trim().length;
      for (final row in rows) {
        final valueLen = row[col].trim().length;
        if (valueLen > maxLen) maxLen = valueLen;
      }
      auto.add((maxLen * 8.4 + 48).clamp(_minColWidth, 360).toDouble());
    }

    final hasConfigured = configured.any((w) => w > 0);
    final widths = List<double>.generate(headers.length, (index) {
      final value = index < configured.length ? configured[index] : 0;
      if (hasConfigured && value > 0) {
        return value.clamp(_minColWidth, _maxColWidth).toDouble();
      }
      return auto[index];
    });
    final total = widths.fold<double>(0, (runningTotal, w) => runningTotal + w);
    if (total < maxWidth && total > 0 && !hasConfigured) {
      final scale = maxWidth / total;
      return widths
          .map((w) => (w * scale).clamp(_minColWidth, _maxColWidth).toDouble())
          .toList(growable: false);
    }
    return widths;
  }

  @override
  Widget build(BuildContext context) {
    final headers = (payload['headers'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);
    final rows = (payload['rows'] as List<dynamic>? ?? const [])
        .whereType<List>()
        .map(
          (row) => row.map((e) => e?.toString() ?? '').toList(growable: false),
        )
        .toList(growable: false);
    final widths = (payload['columnWidths'] as List<dynamic>? ?? const [])
        .map((e) => e is num ? e.toDouble() : 0.0)
        .toList(growable: false);
    final stylesRaw =
        payload['cellStyles'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final styles = stylesRaw.map(
      (key, value) => MapEntry(
        key,
        value is Map
            ? value.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{},
      ),
    );

    final safeHeaders = headers.isEmpty ? const [''] : headers;
    final safeRows = rows.isEmpty
        ? <List<String>>[List<String>.filled(safeHeaders.length, '')]
        : rows
            .map((row) {
              if (row.length == safeHeaders.length) return row;
              if (row.length < safeHeaders.length) {
                return [
                  ...row,
                  ...List<String>.filled(safeHeaders.length - row.length, ''),
                ];
              }
              return row.sublist(0, safeHeaders.length);
            })
            .toList(growable: false);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 920.0;
          final resolvedWidths = _resolvedWidths(
            headers: safeHeaders,
            rows: safeRows,
            configured: widths,
            maxWidth: maxWidth,
          );
          final totalWidth = resolvedWidths.fold<double>(
            0,
            (runningTotal, w) => runningTotal + w,
          );
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(totalWidth, maxWidth),
              child: Table(
                columnWidths: {
                  for (var i = 0; i < resolvedWidths.length; i++)
                    i: FixedColumnWidth(resolvedWidths[i]),
                },
                border: TableBorder.all(
                  color: Colors.black.withValues(alpha: 0.14),
                  width: 1,
                ),
                children: List.generate(safeRows.length, (rowIndex) {
                  return TableRow(
                    children: List.generate(safeHeaders.length, (colIndex) {
                      final value = safeRows[rowIndex][colIndex];
                      final style = styles['$rowIndex:$colIndex'] ?? const {};
                      final bold = style['bold'] == true;
                      final italic = style['italic'] == true;
                      final size = switch (style['size']) {
                        int v => v.toDouble(),
                        num v => v.toDouble(),
                        String v => double.tryParse(v.trim()) ?? 12,
                        _ => 12.0,
                      };
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: SelectableText(
                          value,
                          textAlign: _cellAlign(style),
                          style: TextStyle(
                            color: const Color(0xFF1F2A1F),
                            height: 1.35,
                            fontSize: size.clamp(10, 32),
                            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                            fontFamily: _fontFamily(style),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
          );
        },
      ),
    );
  }
}

class HbHandbookPage extends StatefulWidget {
  final bool useSidebarDesktop;
  final String? forcedVersionId;
  final String? forcedVersionLabel;
  final String? initialSectionId;
  final String? initialHighlightText;
  final bool openSelectedOnMobile;
  final bool showAiFab;
  final bool hideTopHeader;

  const HbHandbookPage({
    super.key,
    this.useSidebarDesktop = true,
    this.forcedVersionId,
    this.forcedVersionLabel,
    this.initialSectionId,
    this.initialHighlightText,
    this.openSelectedOnMobile = false,
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
  final FocusNode _searchFocusNode = FocusNode();

  String _query = '';
  String? _selectedSectionId;
  bool _mobileShowContent = false;
  String? _jumpSectionId;
  String _jumpHighlightText = '';
  int _jumpRequestTick = 0;
  bool _contentOutlineCollapsed = true;
  final Map<String, String> _activeOutlineHeadingBySectionId =
      <String, String>{};

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    final initialSectionId = (widget.initialSectionId ?? '').trim();
    if (initialSectionId.isNotEmpty) {
      _selectedSectionId = initialSectionId;
      _mobileShowContent = widget.openSelectedOnMobile;
      _jumpSectionId = initialSectionId;
      _jumpHighlightText = (widget.initialHighlightText ?? '').trim();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
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
                'insert': {
                  _hbTableEmbedType: map[_hbTableEmbedType].toString(),
                },
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
          if (insert is String &&
              insert.replaceAll('\n', '').trim().isNotEmpty) {
            return true;
          }
          if (insert is Map && insert.isNotEmpty) return true;
        }
        return false;
      }
    } catch (_) {}

    return trimmed.isNotEmpty;
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
    final hasSelected =
        _selectedSectionId != null &&
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
      RegExp(r'^\s*section\s*\d+(?:\.\d+)*\s*[:\-]?\s*', caseSensitive: false),
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

  String _composeSectionHeading({required String code, required String title}) {
    final trimmedCode = code.trim();
    return trimmedCode.isEmpty ? title : '$trimmedCode. $title';
  }

  String _rawContentAsString(dynamic rawValue) {
    if (rawValue is String) return rawValue;
    if (rawValue == null) return '';
    return jsonEncode(rawValue);
  }

  String _extractSearchablePlainText(String rawContent) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) return '';

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        final buffer = StringBuffer();
        for (final rawOp in decoded) {
          if (rawOp is! Map) continue;
          final op = Map<String, dynamic>.from(rawOp);
          final insert = op['insert'];
          if (insert is String) {
            buffer.write(insert.replaceAll('\n', ' '));
            buffer.write(' ');
          }
        }
        return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      }
    } catch (_) {}

    return trimmed.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<_HandbookOutlineHeading> _extractOutlineHeadings(String rawContent) {
    final document = _parseDocument(rawContent);
    final ops = document.toDelta().toJson();
    if (ops.isEmpty) return const [];
    final headings = <_HandbookOutlineHeading>[];
    final lineText = StringBuffer();
    var hasSeenH2 = false;

    for (final raw in ops) {
      final op = Map<String, dynamic>.from(raw as Map);
      final insert = op['insert'];
      final attrs = op['attributes'] is Map
          ? Map<String, dynamic>.from(op['attributes'] as Map)
          : null;
      final headerLevel = _extractHeaderLevel(attrs);

      if (insert is String) {
        for (var i = 0; i < insert.length; i++) {
          final ch = insert[i];
          if (ch == '\n') {
            final headingText = lineText.toString().trim();
            if (headingText.isNotEmpty &&
                (headerLevel == 1 || headerLevel == 2)) {
              final depth = headerLevel == 2 ? 0 : (hasSeenH2 ? 1 : 0);
              headings.add(
                _HandbookOutlineHeading(text: headingText, depth: depth),
              );
              if (headerLevel == 2) {
                hasSeenH2 = true;
              }
            }
            lineText.clear();
            continue;
          }
          lineText.write(ch);
        }
      }
    }
    return headings;
  }

  int? _extractHeaderLevel(Map<String, dynamic>? attrs) {
    if (attrs == null) return null;
    final raw = attrs['header'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  Widget _buildContentOutlinePanel({
    required _HbSection section,
    required List<_HandbookOutlineHeading> headings,
    VoidCallback? onHeadingSelected,
  }) {
    final selectedHeading = _activeOutlineHeadingBySectionId[section.id] ?? '';
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
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    'Page Outline',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: ListView.separated(
                itemCount: headings.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final heading = headings[index];
                  final selected = heading.text == selectedHeading;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    decoration: BoxDecoration(
                      color: selected
                          ? _primary.withValues(alpha: 0.10)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? _primary.withValues(alpha: 0.32)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() {
                            _jumpSectionId = section.id;
                            _jumpHighlightText = heading.text;
                            _jumpRequestTick++;
                            _activeOutlineHeadingBySectionId[section.id] =
                                heading.text;
                          });
                          onHeadingSelected?.call();
                        },
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            8 + (heading.depth * 14),
                            9,
                            8,
                            9,
                          ),
                          child: Text(
                            heading.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? _text : _primary,
                              fontSize: 12.5,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              decoration: selected
                                  ? TextDecoration.none
                                  : TextDecoration.underline,
                              decorationColor: _primary.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _outlineHeaderToggleButton({required bool expanded}) {
    return _outlineHeaderActionButton(
      expanded: expanded,
      tooltip: expanded ? 'Hide outline' : 'Show outline',
      onTap: () => setState(() => _contentOutlineCollapsed = expanded),
    );
  }

  Widget _outlineHeaderActionButton({
    required bool expanded,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: expanded ? _primary.withValues(alpha: 0.10) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: expanded
                  ? _primary.withValues(alpha: 0.30)
                  : Colors.black.withValues(alpha: 0.14),
            ),
          ),
          child: const Icon(Icons.toc_rounded, color: _primary, size: 18),
        ),
      ),
    );
  }

  Future<void> _openOutlineSideSheet({
    required _HbSection section,
    required List<_HandbookOutlineHeading> headings,
  }) async {
    if (headings.isEmpty) return;
    final screen = MediaQuery.sizeOf(context);
    final panelWidth = (screen.width * 0.9).clamp(280.0, 420.0);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close outline',
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: SizedBox(
                width: panelWidth,
                child: _buildContentOutlinePanel(
                  section: section,
                  headings: headings,
                  onHeadingSelected: () {
                    if (Navigator.of(dialogContext).canPop()) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  List<_SectionSearchHit> _buildSearchHits({
    required List<_SectionRow> rows,
    required Map<String, String> codeBySectionId,
    required Map<String, String> contentPlainBySectionId,
  }) {
    final query = _query.trim();
    if (query.isEmpty) return const <_SectionSearchHit>[];
    final queryLower = query.toLowerCase();
    final hits = <_SectionSearchHit>[];

    for (final row in rows) {
      final section = row.section;
      final code = codeBySectionId[section.id] ?? '';
      final title = _displayTitle(section);
      final heading = _composeSectionHeading(code: code, title: title);
      final headingLower = heading.toLowerCase();
      final plain = contentPlainBySectionId[section.id] ?? '';
      final plainLower = plain.toLowerCase();

      final titleIndex = headingLower.indexOf(queryLower);
      final contentIndex = plainLower.indexOf(queryLower);
      if (titleIndex < 0 && contentIndex < 0) continue;

      final snippet = titleIndex >= 0
          ? 'Entry: $heading'
          : _buildMatchSnippet(plain, contentIndex, query);

      hits.add(
        _SectionSearchHit(
          row: row,
          code: code,
          title: title,
          snippet: snippet,
          jumpText: query,
          matchedInTitle: titleIndex >= 0,
          matchIndex: titleIndex >= 0 ? titleIndex : contentIndex,
        ),
      );
    }

    hits.sort((a, b) {
      if (a.matchedInTitle != b.matchedInTitle) {
        return a.matchedInTitle ? -1 : 1;
      }
      final byIndex = a.matchIndex.compareTo(b.matchIndex);
      if (byIndex != 0) return byIndex;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return hits;
  }

  String _buildMatchSnippet(String text, int index, String query) {
    if (text.trim().isEmpty) return 'Match found in entry content.';
    if (index < 0) {
      final preview = text.length > 120 ? '${text.substring(0, 120)}...' : text;
      return preview;
    }
    final start = (index - 50).clamp(0, text.length);
    final end = (index + query.length + 90).clamp(0, text.length);
    final slice = text.substring(start, end).trim();
    if (slice.isEmpty) return 'Match found in entry content.';
    final left = start > 0 ? '...' : '';
    final right = end < text.length ? '...' : '';
    return '$left$slice$right';
  }

  Widget _buildHighlightedText({
    required String text,
    required String query,
    required TextStyle style,
  }) {
    final q = query.trim();
    if (q.isEmpty) return Text(text, style: style);

    final lowerText = text.toLowerCase();
    final lowerQuery = q.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (start < text.length) {
      final match = lowerText.indexOf(lowerQuery, start);
      if (match < 0) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (match > start) {
        spans.add(TextSpan(text: text.substring(start, match), style: style));
      }
      final end = match + q.length;
      spans.add(
        TextSpan(
          text: text.substring(match, end),
          style: style.copyWith(
            backgroundColor: const Color(0xFFFFF59D),
            color: _text,
          ),
        ),
      );
      start = end;
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  double _desktopMaxContentWidth(double viewportWidth) {
    if (viewportWidth >= 1920) return 1760;
    if (viewportWidth >= 1600) return 1540;
    if (viewportWidth >= 1366) return 1366;
    return viewportWidth;
  }

  Widget _buildHeader({
    required bool isDesktop,
    required String activeVersionLabel,
  }) {
    final viewport = MediaQuery.sizeOf(context);
    final isMobile = !isDesktop;
    final compactDesktopHeader =
        viewport.width >= 1024 &&
        viewport.width <= 1366 &&
        viewport.height <= 860;

    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        compactDesktopHeader ? 12 : (isMobile ? 14 : 20),
        isMobile ? 16 : 24,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Text(
              'College Student Handbook',
              style: const TextStyle(
                color: _primary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Browse entries and content',
              style: TextStyle(
                color: _muted.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            _chip('Version', activeVersionLabel, fullWidth: true),
          ] else if (!compactDesktopHeader)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'College Student Handbook',
                        style: TextStyle(
                          color: _primary,
                          fontSize: isDesktop ? 28 : 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Browse entries and content',
                        style: TextStyle(
                          color: _muted.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                _chip('Version', activeVersionLabel),
              ],
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: _chip('Version', activeVersionLabel),
            ),
          SizedBox(height: compactDesktopHeader ? 12 : 16),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, {bool fullWidth = false}) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _primary.withValues(alpha: 0.18)),
      ),
      child: Text(
        '$label: $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
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
    required Map<String, String> contentPlainBySectionId,
    required bool isDesktop,
  }) {
    final searchMode = _searchFocusNode.hasFocus || _query.trim().isNotEmpty;
    final searchHits = _buildSearchHits(
      rows: rows,
      codeBySectionId: codeBySectionId,
      contentPlainBySectionId: contentPlainBySectionId,
    );
    final viewRows = rows;
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
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 10 : 14,
              isDesktop ? 10 : 14,
              isDesktop ? 10 : 14,
              isDesktop ? 8 : 10,
            ),
            child: _ClassicSearchBar(
              controller: _searchCtrl,
              hintText: 'Search',
              isDesktop: isDesktop,
              focusNode: _searchFocusNode,
              onChanged: (v) {
                if (v == _query) return;
                setState(() => _query = v);
              },
              onClear: () {
                setState(() => _query = '');
                if (_searchCtrl.text.trim().isNotEmpty) {
                  _searchCtrl.clear();
                }
                _searchFocusNode.unfocus();
              },
            ),
          ),
          Expanded(
            child: searchMode
                ? _buildSearchResultsList(
                    hits: searchHits,
                    isDesktop: isDesktop,
                  )
                : (viewRows.isEmpty
                      ? const _CenterMsg(
                          text: 'No entries available.',
                          color: _muted,
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            isDesktop ? 10 : 14,
                            isDesktop ? 0 : 10,
                            isDesktop ? 10 : 14,
                            isDesktop ? 10 : 14,
                          ),
                          itemCount: viewRows.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(height: isDesktop ? 8 : 10),
                          itemBuilder: (context, index) {
                            final row = viewRows[index];
                            final section = row.section;
                            final selected = section.id == _selectedSectionId;
                            final leftPad = row.depth > 0
                                ? 16.0 * row.depth
                                : 0.0;

                            return Padding(
                              padding: EdgeInsets.only(left: leftPad),
                              child: _HbSectionTile(
                                code: codeBySectionId[section.id] ?? '',
                                title: _displayTitle(section),
                                selected: selected,
                                nested: row.depth > 0,
                                isDesktop: isDesktop,
                                onTap: () {
                                  setState(() {
                                    _selectedSectionId = section.id;
                                    _mobileShowContent = true;
                                    _activeOutlineHeadingBySectionId.remove(
                                      section.id,
                                    );
                                    if (_jumpSectionId != section.id) {
                                      _jumpSectionId = null;
                                      _jumpHighlightText = '';
                                      _jumpRequestTick = 0;
                                    }
                                  });
                                },
                              ),
                            );
                          },
                        )),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsList({
    required List<_SectionSearchHit> hits,
    required bool isDesktop,
  }) {
    final query = _query.trim();
    if (query.isEmpty) {
      return const _CenterMsg(
        text: 'Type a word or sentence to search handbook content.',
        color: _muted,
      );
    }
    if (hits.isEmpty) {
      return _CenterMsg(text: 'No matches found for "$query".', color: _muted);
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 10 : 14,
        isDesktop ? 0 : 10,
        isDesktop ? 10 : 14,
        isDesktop ? 10 : 14,
      ),
      itemCount: hits.length,
      separatorBuilder: (_, _) => SizedBox(height: isDesktop ? 8 : 10),
      itemBuilder: (context, index) {
        final hit = hits[index];
        final selected = hit.row.section.id == _selectedSectionId;
        final heading = _composeSectionHeading(
          code: hit.code,
          title: hit.title,
        );

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final jumpText = hit.jumpText;
            setState(() {
              _selectedSectionId = hit.row.section.id;
              _mobileShowContent = true;
              _jumpSectionId = hit.row.section.id;
              _jumpHighlightText = jumpText;
              _jumpRequestTick++;
              _activeOutlineHeadingBySectionId.remove(hit.row.section.id);
            });
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? _primary.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? _primary.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hit.snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.2,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContentPanel({
    required _HbSection? selectedSection,
    required String selectedSectionCode,
    required String jumpToText,
    required int jumpRequestTick,
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
      stream: _db
          .collection(_colHbContents)
          .doc(selectedSection.id)
          .snapshots(),
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
        final outlineHeadings = hasContent
            ? _extractOutlineHeadings(rawContent)
            : const <_HandbookOutlineHeading>[];
        final canOpenOutline = outlineHeadings.isNotEmpty;
        final useDesktopOutlineDock =
            !embedded && MediaQuery.sizeOf(context).width >= 1280;
        final showOutlinePanel =
            useDesktopOutlineDock &&
            canOpenOutline &&
            !_contentOutlineCollapsed;

        Widget buildReadView() {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _ReadOnlyQuillView(
                  document: _parseDocument(rawContent),
                  documentCacheKey: rawContent,
                  jumpToText: jumpToText,
                  jumpRequestTick: jumpRequestTick,
                ),
              ),
            ),
          );
        }

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
                            _buildHighlightedText(
                              text: heading,
                              query: selectedSection.id == _jumpSectionId
                                  ? _jumpHighlightText
                                  : '',
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canOpenOutline) ...[
                        const SizedBox(width: 8),
                        _outlineHeaderActionButton(
                          expanded: false,
                          tooltip: 'Open outline',
                          onTap: () => _openOutlineSideSheet(
                            section: selectedSection,
                            headings: outlineHeadings,
                          ),
                        ),
                      ],
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
                      Row(
                        children: [
                          Expanded(
                            child: _buildHighlightedText(
                              text: heading,
                              query: selectedSection.id == _jumpSectionId
                                  ? _jumpHighlightText
                                  : '',
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          if (canOpenOutline) ...[
                            const SizedBox(width: 8),
                            useDesktopOutlineDock
                                ? _outlineHeaderToggleButton(
                                    expanded: showOutlinePanel,
                                  )
                                : _outlineHeaderActionButton(
                                    expanded: false,
                                    tooltip: 'Open outline',
                                    onTap: () => _openOutlineSideSheet(
                                      section: selectedSection,
                                      headings: outlineHeadings,
                                    ),
                                  ),
                          ],
                        ],
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
                        child: buildReadView(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExternalOutlinePanel({required _HbSection? selectedSection}) {
    if (selectedSection == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection(_colHbContents)
          .doc(selectedSection.id)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final rawContent = _rawContentAsString(data['content']);
        final headings = _hasDisplayableContent(rawContent)
            ? _extractOutlineHeadings(rawContent)
            : const <_HandbookOutlineHeading>[];

        if (headings.isEmpty) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: const _CenterMsg(
              text: 'No outline headings in this entry.',
              color: _muted,
            ),
          );
        }

        return _buildContentOutlinePanel(
          section: selectedSection,
          headings: headings,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1024;
    final desktopMaxContentWidth = _desktopMaxContentWidth(width);
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
              .where((s) => s.isVisible)
              .toList(growable: false);

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection(_colHbContents)
                .where('versionId', isEqualTo: versionId)
                .snapshots(),
            builder: (context, contentsSnap) {
              final contentPlainBySectionId = <String, String>{};
              final shouldBuildSearchIndex = _query.trim().isNotEmpty;
              if (shouldBuildSearchIndex && contentsSnap.hasData) {
                for (final doc in contentsSnap.data!.docs) {
                  final data = doc.data();
                  final sectionId = (data['sectionId'] ?? doc.id)
                      .toString()
                      .trim();
                  if (sectionId.isEmpty) continue;
                  final rawContent = _rawContentAsString(data['content']);
                  contentPlainBySectionId[sectionId] =
                      _extractSearchablePlainText(rawContent);
                }
              }

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
                contentPlainBySectionId: contentPlainBySectionId,
                isDesktop: isDesktop,
              );
              final contentPanel = _buildContentPanel(
                selectedSection: selectedSection,
                selectedSectionCode: selectedSection == null
                    ? ''
                    : (codeBySectionId[selectedSection.id] ?? ''),
                jumpToText:
                    selectedSection != null &&
                        selectedSection.id == _jumpSectionId
                    ? _jumpHighlightText
                    : '',
                jumpRequestTick:
                    selectedSection != null &&
                        selectedSection.id == _jumpSectionId
                    ? _jumpRequestTick
                    : 0,
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
                          ),
                          const Divider(height: 1),
                        ],
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: isDesktop
                                    ? desktopMaxContentWidth
                                    : width,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(isDesktop ? 14 : 12),
                                child: isDesktop
                                    ? Row(
                                        children: [
                                          SizedBox(
                                            width: 400,
                                            child: sectionsPanel,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(child: contentPanel),
                                          if (width >= 1280 &&
                                              selectedSection != null) ...[
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 260,
                                              child: Visibility(
                                                visible:
                                                    !_contentOutlineCollapsed,
                                                maintainState: true,
                                                maintainAnimation: true,
                                                maintainSize: true,
                                                child:
                                                    _buildExternalOutlinePanel(
                                                      selectedSection:
                                                          selectedSection,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      )
                                    : (_mobileShowContent
                                          ? contentPanel
                                          : sectionsPanel),
                              ),
                            ),
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
                        tooltip: 'Open Student HandBot',
                        child: const Icon(Icons.smart_toy_rounded),
                      ),
                    ),
                ],
              );
            },
          );
        },
      );
    }

    final Widget pageBody;
    if (usingForcedVersion) {
      final forcedLabel = (widget.forcedVersionLabel ?? forcedVersionId)
          .toString()
          .trim();
      pageBody = buildVersionBody(
        versionId: forcedVersionId,
        versionLabel: forcedLabel.isEmpty ? forcedVersionId : forcedLabel,
      );
    } else {
      pageBody = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
          final activeVersionId = (meta['activeVersionId'] ?? '')
              .toString()
              .trim();
          final activeVersionLabel =
              (meta['activeVersionLabel'] ?? activeVersionId).toString().trim();

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

    return Material(color: _bg, child: pageBody);
  }
}

class _ReadOnlyQuillView extends StatefulWidget {
  final quill.Document document;
  final String documentCacheKey;
  final String jumpToText;
  final int jumpRequestTick;

  const _ReadOnlyQuillView({
    required this.document,
    required this.documentCacheKey,
    required this.jumpToText,
    required this.jumpRequestTick,
  });

  @override
  State<_ReadOnlyQuillView> createState() => _ReadOnlyQuillViewState();
}

class _ReadOnlyQuillViewState extends State<_ReadOnlyQuillView> {
  late quill.QuillController _controller;
  final GlobalKey<quill.EditorState> _editorKey =
      GlobalKey<quill.EditorState>();
  final ScrollController _editorScrollController = ScrollController();
  final FocusNode _editorFocusNode = FocusNode();
  String _lastAppliedJump = '';
  int _lastAppliedJumpTick = -1;

  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController(
      document: widget.document,
      selection: const TextSelection.collapsed(offset: 0),
    )..readOnly = true;
    _tryApplyJumpSelection();
  }

  @override
  void didUpdateWidget(covariant _ReadOnlyQuillView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentCacheKey != widget.documentCacheKey) {
      final old = _controller;
      _controller = quill.QuillController(
        document: widget.document,
        selection: const TextSelection.collapsed(offset: 0),
      )..readOnly = true;
      old.dispose();
      _lastAppliedJump = '';
      _lastAppliedJumpTick = -1;
      _tryApplyJumpSelection();
      return;
    }

    if (oldWidget.jumpToText != widget.jumpToText ||
        oldWidget.jumpRequestTick != widget.jumpRequestTick) {
      _tryApplyJumpSelection();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallbackBuilders = kIsWeb
        ? quill_ext.FlutterQuillEmbeds.editorWebBuilders()
        : quill_ext.FlutterQuillEmbeds.editorBuilders();
    final embedBuilders = <quill.EmbedBuilder>[
      const _HbTableEmbedBuilder(),
      ...fallbackBuilders.where((builder) => builder.key != _hbTableEmbedType),
    ];

    return quill.QuillEditor.basic(
      controller: _controller,
      focusNode: _editorFocusNode,
      scrollController: _editorScrollController,
      config: quill.QuillEditorConfig(
        autoFocus: false,
        showCursor: false,
        expands: false,
        scrollable: true,
        enableInteractiveSelection: true,
        padding: EdgeInsets.zero,
        editorKey: _editorKey,
        embedBuilders: embedBuilders,
        unknownEmbedBuilder: const _HbUnknownEmbedBuilder(),
      ),
    );
  }

  void _tryApplyJumpSelection() {
    final target = widget.jumpToText.trim();
    if (target.isEmpty) return;
    if (target == _lastAppliedJump &&
        widget.jumpRequestTick == _lastAppliedJumpTick) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final plain = _controller.document.toPlainText();
      final offset = _findCaseInsensitiveOffset(plain, target);
      if (offset < 0) return;
      var end = offset + target.length;
      if (end > plain.length) end = plain.length;
      if (end <= offset) return;

      try {
        _controller.updateSelection(
          TextSelection(baseOffset: offset, extentOffset: end),
          quill.ChangeSource.local,
        );
        _editorKey.currentState?.bringIntoView(TextPosition(offset: offset));
      } catch (_) {
        // Avoid repeated error loops on web when selection can't be applied.
      }
      _lastAppliedJump = target;
      _lastAppliedJumpTick = widget.jumpRequestTick;
    });
  }

  int _findCaseInsensitiveOffset(String source, String target) {
    final s = source.toLowerCase();
    final t = target.toLowerCase();
    final direct = s.indexOf(t);
    if (direct >= 0) return direct;

    final compactTarget = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compactTarget.isEmpty) return -1;
    return s.indexOf(compactTarget);
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

class _HandbookOutlineHeading {
  final String text;
  final int depth;

  const _HandbookOutlineHeading({required this.text, required this.depth});
}

class _SectionSearchHit {
  final _SectionRow row;
  final String code;
  final String title;
  final String snippet;
  final String jumpText;
  final bool matchedInTitle;
  final int matchIndex;

  const _SectionSearchHit({
    required this.row,
    required this.code,
    required this.title,
    required this.snippet,
    required this.jumpText,
    required this.matchedInTitle,
    required this.matchIndex,
  });
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
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ClassicSearchBar extends StatelessWidget {
  static const _searchMuted = Color(0xFF6D7F62);

  final TextEditingController controller;
  final String hintText;
  final bool isDesktop;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  const _ClassicSearchBar({
    required this.controller,
    required this.hintText,
    required this.isDesktop,
    this.focusNode,
    required this.onChanged,
    this.onClear,
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
              focusNode: focusNode,
              onChanged: onChanged,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintStyle: TextStyle(
                  color: _searchMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: fontSize,
                ),
              ),
            ),
          ),
          if (controller.text.trim().isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              onPressed: onClear,
              icon: Icon(
                Icons.close_rounded,
                color: _searchMuted.withValues(alpha: 0.85),
                size: isDesktop ? 20 : 18,
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
  final bool isDesktop;
  final VoidCallback onTap;

  const _HbSectionTile({
    required this.code,
    required this.title,
    required this.selected,
    required this.nested,
    required this.isDesktop,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasCode = code.trim().isNotEmpty;
    final showSelectedState = isDesktop && selected;
    final bgColor = showSelectedState
        ? _headerGreen.withValues(alpha: 0.10)
        : Colors.white;
    final borderColor = showSelectedState
        ? _headerGreen.withValues(alpha: 0.35)
        : Colors.black12;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      splashColor: isDesktop ? null : Colors.transparent,
      highlightColor: isDesktop ? null : Colors.transparent,
      hoverColor: isDesktop ? null : Colors.transparent,
      focusColor: isDesktop ? null : Colors.transparent,
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
                  fontWeight: showSelectedState
                      ? FontWeight.w900
                      : FontWeight.w800,
                  fontSize: nested ? 14 : 15.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: showSelectedState ? _headerGreen : const Color(0xFF8B9489),
              size: 26,
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

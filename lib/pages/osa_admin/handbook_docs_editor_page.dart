import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:apps/models/handbook_node_doc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart'
    as quill_ext;
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';
import 'package:apps/pages/shared/widgets/unsaved_changes_guard.dart';
import 'package:apps/services/app_firestore.dart';

const String _tableEmbedType = 'x-embed-table';
const double _tableMaxColWidth = 2000;
typedef _TableStyleSetter =
    void Function({
      bool? bold,
      bool? italic,
      String? align,
      String? fontFamilyKey,
      int? fontSizePoint,
    });

class _TableSelectionState {
  const _TableSelectionState({
    required this.hasActiveCell,
    required this.bold,
    required this.italic,
    required this.align,
    required this.fontFamilyKey,
    required this.fontSizePoint,
  });

  final bool hasActiveCell;
  final bool bold;
  final bool italic;
  final String align;
  final String fontFamilyKey;
  final int fontSizePoint;

  static const empty = _TableSelectionState(
    hasActiveCell: false,
    bold: false,
    italic: false,
    align: 'left',
    fontFamilyKey: 'default',
    fontSizePoint: 12,
  );
}

Map<String, dynamic> _buildTablePayload({
  required int columns,
  required int rows,
}) {
  final safeColumns = columns < 1 ? 1 : columns;
  final safeRows = rows < 1 ? 1 : rows;
  return {
    'headers': List.generate(safeColumns, (index) => ''),
    'rows': List.generate(
      safeRows,
      (rowIndex) => List.generate(safeColumns, (cellIndex) => ''),
    ),
    'columnWidths': List<double>.filled(safeColumns, 0),
    'cellStyles': <String, dynamic>{},
  };
}

Map<String, dynamic> _normalizeTablePayload(String raw) {
  final fallback = _buildTablePayload(columns: 1, rows: 1);

  List<String> normalizeCells(dynamic rawCells, int columns) {
    if (rawCells is! List) {
      return List<String>.filled(columns, '');
    }
    final values = rawCells
        .map((cell) => cell?.toString().trim() ?? '')
        .toList(growable: false);
    if (values.length < columns) {
      return [...values, ...List<String>.filled(columns - values.length, '')];
    }
    if (values.length > columns) {
      return values.sublist(0, columns);
    }
    return values;
  }

  List<double> normalizeWidths(dynamic rawWidths, int columns) {
    final values = List<double>.filled(columns, 0);
    if (rawWidths is! List) return values;
    final max = columns < rawWidths.length ? columns : rawWidths.length;
    for (var i = 0; i < max; i++) {
      final value = rawWidths[i];
      if (value is num && value.isFinite) {
        values[i] = value.toDouble().clamp(110, _tableMaxColWidth);
      } else if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null && parsed.isFinite) {
          values[i] = parsed.clamp(110, _tableMaxColWidth);
        }
      }
    }
    return values;
  }

  Map<String, dynamic> normalizeCellStyles(
    dynamic rawStyles,
    int rowCount,
    int colCount,
  ) {
    if (rawStyles is! Map) return <String, dynamic>{};
    final normalized = <String, dynamic>{};
    for (final entry in rawStyles.entries) {
      final key = entry.key.toString();
      final parts = key.split(':');
      if (parts.length != 2) continue;
      final row = int.tryParse(parts[0]);
      final col = int.tryParse(parts[1]);
      if (row == null || col == null) continue;
      if (row < 0 || row >= rowCount || col < 0 || col >= colCount) continue;
      final value = entry.value;
      if (value is! Map) continue;
      final rawMap = value.map((k, v) => MapEntry(k.toString(), v));
      final bold = rawMap['bold'] == true;
      final italic = rawMap['italic'] == true;
      final alignRaw = (rawMap['align'] ?? 'left').toString().trim();
      final align = switch (alignRaw) {
        'center' => 'center',
        'right' => 'right',
        'justify' => 'justify',
        _ => 'left',
      };
      final fontRaw = (rawMap['font'] ?? '').toString().trim();
      final font = switch (fontRaw) {
        'serif' => 'serif',
        'monospace' => 'monospace',
        'sans-serif' => 'sans-serif',
        _ => 'default',
      };
      final sizeRaw = rawMap['size'];
      int size = 12;
      if (sizeRaw is num) {
        size = sizeRaw.round().clamp(10, 32);
      } else if (sizeRaw is String) {
        size = (int.tryParse(sizeRaw.trim()) ?? 12).clamp(10, 32);
      }
      if (!bold &&
          !italic &&
          align == 'left' &&
          font == 'default' &&
          size == 12) {
        continue;
      }
      normalized['$row:$col'] = {
        'bold': bold,
        'italic': italic,
        'align': align,
        'font': font,
        'size': size,
      };
    }
    return normalized;
  }

  bool isAutoHeaderLabel(String value) {
    return RegExp(
      r'^column\s+\d+$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  bool isAutoCellLabel(String value) {
    return RegExp(
      r'^value\s+\d+\.\d+$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));
      final rawHeaders = map['headers'];
      final headers = rawHeaders is List
          ? rawHeaders
                .map((header) => header?.toString().trim() ?? '')
                .toList(growable: false)
          : const <String>[];
      final safeHeaders = headers.isEmpty ? const <String>[''] : headers;
      final columns = safeHeaders.length;
      final rawRows = map['rows'];
      final safeRows = rawRows is List
          ? rawRows.map((row) => normalizeCells(row, columns)).toList()
          : <List<String>>[List<String>.filled(columns, '')];
      final safeWidths = normalizeWidths(map['columnWidths'], columns);
      final normalizedStyles = normalizeCellStyles(
        map['cellStyles'],
        safeRows.isEmpty ? 1 : safeRows.length,
        columns,
      );

      final cleanedHeaders = safeHeaders
          .map((header) => isAutoHeaderLabel(header) ? '' : header)
          .toList(growable: false);
      final cleanedRows = safeRows
          .map(
            (row) => row
                .map((cell) => isAutoCellLabel(cell) ? '' : cell)
                .toList(growable: false),
          )
          .toList(growable: false);
      return {
        'headers': cleanedHeaders,
        'rows': cleanedRows.isEmpty
            ? <List<String>>[List<String>.filled(columns, '')]
            : cleanedRows,
        'columnWidths': safeWidths,
        'cellStyles': normalizedStyles,
      };
    }
  } catch (_) {}

  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && line.contains('|'))
      .toList(growable: false);

  if (lines.length < 2) {
    return fallback;
  }

  List<String> splitMarkdownRow(String line) {
    var value = line.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|')) value = value.substring(0, value.length - 1);
    return value.split('|').map((part) => part.trim()).toList(growable: false);
  }

  bool isDividerRow(List<String> cells) {
    if (cells.isEmpty) return false;
    return cells.every((cell) {
      final compact = cell.replaceAll(':', '').replaceAll('-', '').trim();
      return compact.isEmpty && cell.contains('-');
    });
  }

  final headers = splitMarkdownRow(lines.first);
  if (headers.isEmpty) return fallback;
  final hasDivider =
      lines.length > 1 && isDividerRow(splitMarkdownRow(lines[1]));
  final rowStart = hasDivider ? 2 : 1;
  final rows = <List<String>>[];
  for (var index = rowStart; index < lines.length; index++) {
    rows.add(normalizeCells(splitMarkdownRow(lines[index]), headers.length));
  }

  return {
    'headers': headers.map((h) => isAutoHeaderLabel(h) ? '' : h).toList(),
    'rows': rows.isEmpty
        ? <List<String>>[List<String>.filled(headers.length, '')]
        : rows
              .map(
                (row) => row
                    .map((cell) => isAutoCellLabel(cell) ? '' : cell)
                    .toList(growable: false),
              )
              .toList(growable: false),
    'columnWidths': List<double>.filled(headers.length, 0),
    'cellStyles': <String, dynamic>{},
  };
}

Map<String, dynamic>? _tryParseStandaloneMarkdownTable(String raw) {
  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.length < 2) return null;
  if (!lines.every((line) => line.startsWith('|') && line.endsWith('|'))) {
    return null;
  }

  final dividerCells = lines[1]
      .substring(1, lines[1].length - 1)
      .split('|')
      .map((cell) => cell.trim())
      .toList(growable: false);
  final hasDivider =
      dividerCells.isNotEmpty &&
      dividerCells.every((cell) {
        final compact = cell.replaceAll(':', '').replaceAll('-', '').trim();
        return compact.isEmpty && cell.contains('-');
      });
  if (!hasDivider) return null;

  return _normalizeTablePayload(lines.join('\n'));
}

class _TableEmbedBuilder extends quill.EmbedBuilder {
  const _TableEmbedBuilder({
    required this.onDraftChanged,
    required this.onCommitRequested,
    required this.onDeleteRequested,
    required this.onEditingStateChanged,
    required this.onSelectionStateChanged,
    required this.onStyleSetterChanged,
    required this.interactionGroupId,
  });

  final void Function(int offset, Map<String, dynamic> payload) onDraftChanged;
  final void Function(int offset, Map<String, dynamic> payload)
  onCommitRequested;
  final void Function(int offset) onDeleteRequested;
  final void Function(int offset, bool editing) onEditingStateChanged;
  final void Function(int offset, _TableSelectionState state)
  onSelectionStateChanged;
  final void Function(int offset, _TableStyleSetter? setter)
  onStyleSetterChanged;
  final Object interactionGroupId;

  @override
  String get key => _tableEmbedType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    return _TableEmbedFrame(
      offset: embedContext.node.documentOffset,
      payload: _normalizeTablePayload(embedContext.node.value.data.toString()),
      readOnly: embedContext.readOnly,
      onDraftChanged: onDraftChanged,
      onCommitRequested: onCommitRequested,
      onDeleteRequested: onDeleteRequested,
      onEditingStateChanged: onEditingStateChanged,
      onSelectionStateChanged: onSelectionStateChanged,
      onStyleSetterChanged: onStyleSetterChanged,
      interactionGroupId: interactionGroupId,
    );
  }
}

class _TableEmbedFrame extends StatefulWidget {
  const _TableEmbedFrame({
    required this.offset,
    required this.payload,
    required this.readOnly,
    required this.onDraftChanged,
    required this.onCommitRequested,
    required this.onDeleteRequested,
    required this.onEditingStateChanged,
    required this.onSelectionStateChanged,
    required this.onStyleSetterChanged,
    required this.interactionGroupId,
  });

  final int offset;
  final Map<String, dynamic> payload;
  final bool readOnly;
  final void Function(int offset, Map<String, dynamic> payload) onDraftChanged;
  final void Function(int offset, Map<String, dynamic> payload)
  onCommitRequested;
  final void Function(int offset) onDeleteRequested;
  final void Function(int offset, bool editing) onEditingStateChanged;
  final void Function(int offset, _TableSelectionState state)
  onSelectionStateChanged;
  final void Function(int offset, _TableStyleSetter? setter)
  onStyleSetterChanged;
  final Object interactionGroupId;

  @override
  State<_TableEmbedFrame> createState() => _TableEmbedFrameState();
}

class _TableEmbedFrameState extends State<_TableEmbedFrame> {
  static const double _minColWidth = 110;
  static const double _maxColWidth = _tableMaxColWidth;

  final FocusNode _tableFocusNode = FocusNode(debugLabel: 'table_embed_focus');
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _cellFocusNodes = <String, FocusNode>{};
  final Map<String, GlobalKey> _cellKeys = <String, GlobalKey>{};

  late List<String> _headers;
  late List<List<String>> _rows;
  late List<double> _columnWidths;
  late Map<String, Map<String, dynamic>> _cellStyles;
  bool _selected = false;
  bool _hovered = false;
  bool _optionsMenuOpen = false;
  int _activeRow = 0;
  int _activeCol = 0;
  int _selectionAnchorRow = 0;
  int _selectionAnchorCol = 0;
  int _selectionExtentRow = 0;
  int _selectionExtentCol = 0;
  bool _hasCellSelectionRange = false;
  bool _allCellsSelected = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadFromPayload(widget.payload);
    widget.onStyleSetterChanged(widget.offset, _setActiveCellStyle);
    _notifySelectionState();
  }

  @override
  void didUpdateWidget(covariant _TableEmbedFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(oldWidget.payload) != jsonEncode(widget.payload) &&
        !_anyCellHasFocus()) {
      _disposeCellControllers();
      _loadFromPayload(widget.payload);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    widget.onStyleSetterChanged(widget.offset, null);
    _tableFocusNode.dispose();
    _disposeCellControllers();
    super.dispose();
  }

  void _disposeCellControllers() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    for (final node in _cellFocusNodes.values) {
      node.dispose();
    }
    _controllers.clear();
    _cellFocusNodes.clear();
    _cellKeys.clear();
  }

  void _loadFromPayload(Map<String, dynamic> payload) {
    final normalized = _normalizeTablePayload(jsonEncode(payload));
    final rawHeaders = normalized['headers'] as List<dynamic>? ?? const [];
    final headers = rawHeaders.map((value) => value.toString()).toList();
    final columns = headers.isEmpty ? 1 : headers.length;

    final rawRows = normalized['rows'] as List<dynamic>? ?? const [];
    final rows = rawRows
        .whereType<List>()
        .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
        .map((row) {
          if (row.length == columns) return row;
          if (row.length < columns) {
            return [...row, ...List<String>.filled(columns - row.length, '')];
          }
          return row.sublist(0, columns);
        })
        .toList(growable: false);

    final widthRaw = normalized['columnWidths'] as List<dynamic>? ?? const [];
    final widths = List<double>.filled(columns, 0);
    final max = widthRaw.length < columns ? widthRaw.length : columns;
    for (var index = 0; index < max; index++) {
      final value = widthRaw[index];
      if (value is num && value.isFinite) {
        widths[index] = value.toDouble().clamp(_minColWidth, _maxColWidth);
      } else if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null && parsed.isFinite) {
          widths[index] = parsed.clamp(_minColWidth, _maxColWidth);
        }
      }
    }

    final normalizedHeaders = headers.isEmpty ? const [''] : headers;
    final normalizedRows = rows.isEmpty
        ? <List<String>>[List<String>.filled(columns, '', growable: true)]
        : rows;

    _headers = List<String>.from(normalizedHeaders, growable: true);
    _rows = normalizedRows
        .map((row) => List<String>.from(row, growable: true))
        .toList(growable: true);
    _columnWidths = List<double>.from(widths, growable: true);
    final rawStyles =
        normalized['cellStyles'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    _cellStyles = rawStyles.map(
      (key, value) => MapEntry(
        key,
        value is Map
            ? value.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{},
      ),
    );
  }

  bool _anyCellHasFocus() {
    for (final node in _cellFocusNodes.values) {
      if (node.hasFocus) return true;
    }
    return false;
  }

  String _cellKey({
    required bool isHeader,
    required int row,
    required int col,
  }) {
    return isHeader ? 'h_$col' : 'r_${row}_$col';
  }

  TextEditingController _controllerFor({
    required bool isHeader,
    required int row,
    required int col,
  }) {
    final key = _cellKey(isHeader: isHeader, row: row, col: col);
    final existing = _controllers[key];
    final text = isHeader ? _headers[col] : _rows[row][col];
    if (existing != null) {
      if (existing.text != text) {
        existing.text = text;
      }
      return existing;
    }
    final ctrl = TextEditingController(text: text);
    _controllers[key] = ctrl;
    return ctrl;
  }

  FocusNode _focusNodeFor({
    required bool isHeader,
    required int row,
    required int col,
  }) {
    final key = _cellKey(isHeader: isHeader, row: row, col: col);
    final existing = _cellFocusNodes[key];
    if (existing != null) return existing;

    final node = FocusNode(debugLabel: 'table_cell_$key');
    node.addListener(() {
      if (_isDisposed || !mounted) return;
      if (node.hasFocus) {
        _selected = false;
        widget.onEditingStateChanged(widget.offset, true);
        _activeRow = row;
        _activeCol = col;
        _notifySelectionState();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_anyCellHasFocus() && !_optionsMenuOpen) {
            if (!_allCellsSelected && !_hasCellSelectionRange) {
              widget.onEditingStateChanged(widget.offset, false);
              _commitNow();
            }
            _notifySelectionState();
          }
        });
      }
      if (mounted) {
        setState(() {});
      }
    });
    _cellFocusNodes[key] = node;
    return node;
  }

  void _emitDraft() {
    final payload = {
      'headers': _headers,
      'rows': _rows,
      'columnWidths': _columnWidths,
      'cellStyles': _cellStyles,
    };
    widget.onDraftChanged(widget.offset, payload);
  }

  void _commitNow() {
    if (!mounted) return;
    final payload = {
      'headers': _headers,
      'rows': _rows,
      'columnWidths': _columnWidths,
      'cellStyles': _cellStyles,
    };
    widget.onCommitRequested(widget.offset, payload);
  }

  void _clearTableInteraction({bool commit = true}) {
    if (_isDisposed || !mounted) return;
    var hadFocus = false;
    final hadSelection = _selected;
    _allCellsSelected = false;
    _hasCellSelectionRange = false;
    for (final node in _cellFocusNodes.values) {
      if (node.hasFocus) {
        hadFocus = true;
        node.unfocus();
      }
    }
    _tableFocusNode.unfocus();
    widget.onEditingStateChanged(widget.offset, false);
    _selected = false;
    _hovered = false;
    if (commit && (hadFocus || hadSelection)) {
      _commitNow();
    }
    _notifySelectionState();
    if (mounted) setState(() {});
  }

  bool _isShiftPressed() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
  }

  void _updateCellValue({
    required bool isHeader,
    required int row,
    required int col,
    required String value,
  }) {
    if (isHeader) {
      _headers[col] = value;
    } else {
      _rows[row][col] = value;
    }
    _emitDraft();
  }

  void _ensureMutableTableState() {
    _headers = List<String>.from(_headers, growable: true);
    _rows = _rows
        .map((row) => List<String>.from(row, growable: true))
        .toList(growable: true);
    _columnWidths = List<double>.from(_columnWidths, growable: true);
    _cellStyles = _cellStyles.map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
    );
  }

  String _styleKey(int row, int col) => '$row:$col';

  Map<String, dynamic> _cellStyleFor(int row, int col) {
    return _cellStyles[_styleKey(row, col)] ?? const <String, dynamic>{};
  }

  bool _cellBold(int row, int col) => _cellStyleFor(row, col)['bold'] == true;

  bool _cellItalic(int row, int col) =>
      _cellStyleFor(row, col)['italic'] == true;

  TextAlign _cellAlign(int row, int col) {
    final raw = (_cellStyleFor(row, col)['align'] ?? 'left').toString();
    return switch (raw) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.left,
    };
  }

  String _cellFontFamilyKey(int row, int col) {
    final raw = (_cellStyleFor(row, col)['font'] ?? 'default')
        .toString()
        .trim();
    return switch (raw) {
      'serif' => 'serif',
      'monospace' => 'monospace',
      'sans-serif' => 'sans-serif',
      _ => 'default',
    };
  }

  double _cellFontSize(int row, int col) {
    final raw = _cellStyleFor(row, col)['size'];
    if (raw is num) return raw.toDouble().clamp(10, 32);
    if (raw is String) {
      final parsed = double.tryParse(raw.trim());
      if (parsed != null) return parsed.clamp(10, 32);
    }
    return 12;
  }

  String? _fontFamilyFromKey(String key) {
    return switch (key) {
      'serif' => 'serif',
      'monospace' => 'monospace',
      'sans-serif' => 'sans-serif',
      _ => null,
    };
  }

  List<_TableCellPosition> _targetCellsForStyleUpdate() {
    if (_rows.isEmpty || _headers.isEmpty) return const <_TableCellPosition>[];
    if (_allCellsSelected) {
      return _allPositions();
    }
    if (_hasCellSelectionRange) {
      final minRow = math
          .min(_selectionAnchorRow, _selectionExtentRow)
          .clamp(0, _rows.length - 1);
      final maxRow = math
          .max(_selectionAnchorRow, _selectionExtentRow)
          .clamp(0, _rows.length - 1);
      final minCol = math
          .min(_selectionAnchorCol, _selectionExtentCol)
          .clamp(0, _headers.length - 1);
      final maxCol = math
          .max(_selectionAnchorCol, _selectionExtentCol)
          .clamp(0, _headers.length - 1);
      final cells = <_TableCellPosition>[];
      for (var row = minRow; row <= maxRow; row++) {
        for (var col = minCol; col <= maxCol; col++) {
          cells.add(_TableCellPosition(isHeader: false, row: row, col: col));
        }
      }
      return cells;
    }
    if (_activeRow < 0 ||
        _activeRow >= _rows.length ||
        _activeCol < 0 ||
        _activeCol >= _headers.length) {
      return const <_TableCellPosition>[];
    }
    return [
      _TableCellPosition(isHeader: false, row: _activeRow, col: _activeCol),
    ];
  }

  bool _isCellInsideSelection(int row, int col) {
    if (_allCellsSelected) return true;
    if (!_hasCellSelectionRange) return row == _activeRow && col == _activeCol;
    final minRow = math.min(_selectionAnchorRow, _selectionExtentRow);
    final maxRow = math.max(_selectionAnchorRow, _selectionExtentRow);
    final minCol = math.min(_selectionAnchorCol, _selectionExtentCol);
    final maxCol = math.max(_selectionAnchorCol, _selectionExtentCol);
    return row >= minRow && row <= maxRow && col >= minCol && col <= maxCol;
  }

  void _setCellSelection(int row, int col) {
    _activeRow = row;
    _activeCol = col;
    _selectionAnchorRow = row;
    _selectionAnchorCol = col;
    _selectionExtentRow = row;
    _selectionExtentCol = col;
    _hasCellSelectionRange = true;
    _allCellsSelected = false;
    widget.onEditingStateChanged(widget.offset, true);
    _notifySelectionState();
    if (mounted) setState(() {});
  }

  void _setActiveCellWithoutResettingAnchor(int row, int col) {
    _activeRow = row;
    _activeCol = col;
    _hasCellSelectionRange = true;
    _allCellsSelected = false;
    widget.onEditingStateChanged(widget.offset, true);
    _notifySelectionState();
    if (mounted) setState(() {});
  }

  void _updateDragSelectionExtent(int row, int col) {
    final clampedRow = row.clamp(0, _rows.length - 1);
    final clampedCol = col.clamp(0, _headers.length - 1);
    if (_selectionExtentRow == clampedRow &&
        _selectionExtentCol == clampedCol) {
      return;
    }
    _selectionExtentRow = clampedRow;
    _selectionExtentCol = clampedCol;
    _activeRow = clampedRow;
    _activeCol = clampedCol;
    _notifySelectionState();
    if (mounted) setState(() {});
  }

  void _selectWholeTable() {
    if (_rows.isEmpty || _headers.isEmpty) return;
    _selected = true;
    _allCellsSelected = true;
    _hasCellSelectionRange = false;
    _activeRow = 0;
    _activeCol = 0;
    _selectionAnchorRow = 0;
    _selectionAnchorCol = 0;
    _selectionExtentRow = _rows.length - 1;
    _selectionExtentCol = _headers.length - 1;
    widget.onEditingStateChanged(widget.offset, true);
    _notifySelectionState();
    if (mounted) setState(() {});
  }

  GlobalKey _cellContainerKey(int row, int col) {
    final key = _cellKey(isHeader: false, row: row, col: col);
    return _cellKeys.putIfAbsent(key, GlobalKey.new);
  }

  _TableCellPosition? _cellAtGlobalPosition(Offset globalPosition) {
    for (var row = 0; row < _rows.length; row++) {
      for (var col = 0; col < _headers.length; col++) {
        final key = _cellContainerKey(row, col);
        final context = key.currentContext;
        if (context == null) continue;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final local = box.globalToLocal(globalPosition);
        final inside =
            local.dx >= 0 &&
            local.dy >= 0 &&
            local.dx <= box.size.width &&
            local.dy <= box.size.height;
        if (inside) {
          return _TableCellPosition(isHeader: false, row: row, col: col);
        }
      }
    }
    return null;
  }

  void _setActiveCellStyle({
    bool? bold,
    bool? italic,
    String? align,
    String? fontFamilyKey,
    int? fontSizePoint,
  }) {
    final targets = _targetCellsForStyleUpdate();
    if (targets.isEmpty) return;
    _ensureMutableTableState();
    for (final cell in targets) {
      final key = _styleKey(cell.row, cell.col);
      final next = Map<String, dynamic>.from(_cellStyles[key] ?? const {});
      if (bold != null) next['bold'] = bold;
      if (italic != null) next['italic'] = italic;
      if (align != null) {
        next['align'] = switch (align) {
          'center' => 'center',
          'right' => 'right',
          'justify' => 'justify',
          _ => 'left',
        };
      }
      if (fontFamilyKey != null) {
        next['font'] = switch (fontFamilyKey) {
          'serif' => 'serif',
          'monospace' => 'monospace',
          'sans-serif' => 'sans-serif',
          _ => 'default',
        };
      }
      if (fontSizePoint != null) {
        next['size'] = fontSizePoint.clamp(10, 32);
      }
      final normalized = {
        'bold': next['bold'] == true,
        'italic': next['italic'] == true,
        'align': (next['align'] ?? 'left').toString(),
        'font': (next['font'] ?? 'default').toString(),
        'size': ((next['size'] ?? 12) as num).round().clamp(10, 32),
      };
      final isDefault =
          normalized['bold'] == false &&
          normalized['italic'] == false &&
          normalized['align'] == 'left' &&
          normalized['font'] == 'default' &&
          normalized['size'] == 12;
      if (isDefault) {
        _cellStyles.remove(key);
      } else {
        _cellStyles[key] = normalized;
      }
    }
    _emitDraft();
    _notifySelectionState();
    if (mounted) setState(() {});
  }

  void _notifySelectionState() {
    if (_isDisposed || !mounted) return;
    final targets = _targetCellsForStyleUpdate();
    if (targets.isEmpty) {
      widget.onSelectionStateChanged(widget.offset, _TableSelectionState.empty);
      return;
    }
    final first = targets.first;
    final baseAlign = switch (_cellAlign(first.row, first.col)) {
      TextAlign.center => 'center',
      TextAlign.right => 'right',
      TextAlign.justify => 'justify',
      _ => 'left',
    };
    final baseFont = _cellFontFamilyKey(first.row, first.col);
    final baseSize = _cellFontSize(first.row, first.col).round();

    var allBold = true;
    var allItalic = true;
    var sameAlign = true;
    var sameFont = true;
    var sameSize = true;
    for (final cell in targets) {
      if (!_cellBold(cell.row, cell.col)) allBold = false;
      if (!_cellItalic(cell.row, cell.col)) allItalic = false;
      final align = switch (_cellAlign(cell.row, cell.col)) {
        TextAlign.center => 'center',
        TextAlign.right => 'right',
        TextAlign.justify => 'justify',
        _ => 'left',
      };
      if (align != baseAlign) sameAlign = false;
      if (_cellFontFamilyKey(cell.row, cell.col) != baseFont) sameFont = false;
      if (_cellFontSize(cell.row, cell.col).round() != baseSize) {
        sameSize = false;
      }
    }

    widget.onSelectionStateChanged(
      widget.offset,
      _TableSelectionState(
        hasActiveCell: true,
        bold: allBold,
        italic: allItalic,
        align: sameAlign ? baseAlign : 'left',
        fontFamilyKey: sameFont ? baseFont : 'default',
        fontSizePoint: sameSize ? baseSize : 12,
      ),
    );
  }

  void _remapStylesOnRowInsert(int index) {
    final remapped = <String, Map<String, dynamic>>{};
    for (final entry in _cellStyles.entries) {
      final parts = entry.key.split(':');
      if (parts.length != 2) continue;
      final row = int.tryParse(parts[0]);
      final col = int.tryParse(parts[1]);
      if (row == null || col == null) continue;
      final nextRow = row >= index ? row + 1 : row;
      remapped[_styleKey(nextRow, col)] = Map<String, dynamic>.from(
        entry.value,
      );
    }
    _cellStyles = remapped;
  }

  void _remapStylesOnRowDelete(int index) {
    final remapped = <String, Map<String, dynamic>>{};
    for (final entry in _cellStyles.entries) {
      final parts = entry.key.split(':');
      if (parts.length != 2) continue;
      final row = int.tryParse(parts[0]);
      final col = int.tryParse(parts[1]);
      if (row == null || col == null) continue;
      if (row == index) continue;
      final nextRow = row > index ? row - 1 : row;
      remapped[_styleKey(nextRow, col)] = Map<String, dynamic>.from(
        entry.value,
      );
    }
    _cellStyles = remapped;
  }

  void _remapStylesOnColInsert(int index) {
    final remapped = <String, Map<String, dynamic>>{};
    for (final entry in _cellStyles.entries) {
      final parts = entry.key.split(':');
      if (parts.length != 2) continue;
      final row = int.tryParse(parts[0]);
      final col = int.tryParse(parts[1]);
      if (row == null || col == null) continue;
      final nextCol = col >= index ? col + 1 : col;
      remapped[_styleKey(row, nextCol)] = Map<String, dynamic>.from(
        entry.value,
      );
    }
    _cellStyles = remapped;
  }

  void _remapStylesOnColDelete(int index) {
    final remapped = <String, Map<String, dynamic>>{};
    for (final entry in _cellStyles.entries) {
      final parts = entry.key.split(':');
      if (parts.length != 2) continue;
      final row = int.tryParse(parts[0]);
      final col = int.tryParse(parts[1]);
      if (row == null || col == null) continue;
      if (col == index) continue;
      final nextCol = col > index ? col - 1 : col;
      remapped[_styleKey(row, nextCol)] = Map<String, dynamic>.from(
        entry.value,
      );
    }
    _cellStyles = remapped;
  }

  List<_TableCellPosition> _allPositions() {
    final positions = <_TableCellPosition>[];
    for (var row = 0; row < _rows.length; row++) {
      for (var col = 0; col < _headers.length; col++) {
        positions.add(_TableCellPosition(isHeader: false, row: row, col: col));
      }
    }
    return positions;
  }

  void _focusPosition(_TableCellPosition pos, {required bool moveToEnd}) {
    final node = _focusNodeFor(
      isHeader: pos.isHeader,
      row: pos.row,
      col: pos.col,
    );
    final ctrl = _controllerFor(
      isHeader: pos.isHeader,
      row: pos.row,
      col: pos.col,
    );
    node.requestFocus();
    ctrl.selection = TextSelection.collapsed(
      offset: moveToEnd ? ctrl.text.length : 0,
    );
  }

  KeyEventResult _handleCellKey({
    required KeyEvent event,
    required bool isHeader,
    required int row,
    required int col,
  }) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = _controllerFor(isHeader: isHeader, row: row, col: col);
    final sel = ctrl.selection;
    final collapsed = sel.isValid && sel.isCollapsed;
    final positions = _allPositions();
    final currentIndex = positions.indexWhere(
      (pos) => pos.isHeader == isHeader && pos.row == row && pos.col == col,
    );
    if (currentIndex < 0) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
      final nextIndex = shiftPressed ? currentIndex - 1 : currentIndex + 1;
      if (nextIndex >= 0 && nextIndex < positions.length) {
        _focusPosition(positions[nextIndex], moveToEnd: shiftPressed);
      }
      return KeyEventResult.handled;
    }

    if (collapsed &&
        event.logicalKey == LogicalKeyboardKey.arrowRight &&
        sel.baseOffset >= ctrl.text.length) {
      final nextIndex = currentIndex + 1;
      if (nextIndex < positions.length) {
        _focusPosition(positions[nextIndex], moveToEnd: false);
        return KeyEventResult.handled;
      }
    }

    if (collapsed &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        sel.baseOffset <= 0) {
      final prevIndex = currentIndex - 1;
      if (prevIndex >= 0) {
        _focusPosition(positions[prevIndex], moveToEnd: true);
        return KeyEventResult.handled;
      }
    }

    final isMultiLine = ctrl.text.contains('\n');
    final controlOrMetaPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final allowVerticalJump = !isMultiLine || controlOrMetaPressed;
    if (collapsed &&
        allowVerticalJump &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      final targetRow = event.logicalKey == LogicalKeyboardKey.arrowUp
          ? row - 1
          : row + 1;
      if (targetRow >= 0 && targetRow < _rows.length) {
        _focusPosition(
          _TableCellPosition(isHeader: false, row: targetRow, col: col),
          moveToEnd: event.logicalKey == LogicalKeyboardKey.arrowUp,
        );
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _insertRow({required bool above}) {
    _ensureMutableTableState();
    final insertIndex = above ? _activeRow : _activeRow + 1;
    final safeIndex = insertIndex.clamp(0, _rows.length);
    _remapStylesOnRowInsert(safeIndex);
    _rows.insert(
      safeIndex,
      List<String>.filled(_headers.length, '', growable: true),
    );
    _activeRow = safeIndex;
    _clearControllersAndFocusNodes();
    _emitDraft();
    if (mounted) setState(() {});
  }

  void _insertColumn({required bool left}) {
    _ensureMutableTableState();
    final insertIndex = left ? _activeCol : _activeCol + 1;
    final safeIndex = insertIndex.clamp(0, _headers.length);
    _remapStylesOnColInsert(safeIndex);
    _headers.insert(safeIndex, '');
    _columnWidths.insert(safeIndex, 0);
    for (final row in _rows) {
      row.insert(safeIndex, '');
    }
    _activeCol = safeIndex;
    _clearControllersAndFocusNodes();
    _emitDraft();
    if (mounted) setState(() {});
  }

  void _deleteActiveRow() {
    _ensureMutableTableState();
    if (_rows.length <= 1) return;
    final target = _activeRow;
    _remapStylesOnRowDelete(target.clamp(0, _rows.length - 1));
    _rows.removeAt(target.clamp(0, _rows.length - 1));
    _activeRow = (_activeRow - 1).clamp(0, _rows.length - 1);
    _clearControllersAndFocusNodes();
    _emitDraft();
    if (mounted) setState(() {});
  }

  void _deleteActiveColumn() {
    _ensureMutableTableState();
    if (_headers.length <= 1) return;
    final target = _activeCol.clamp(0, _headers.length - 1);
    _remapStylesOnColDelete(target);
    _headers.removeAt(target);
    _columnWidths.removeAt(target);
    for (final row in _rows) {
      row.removeAt(target);
    }
    _activeCol = (_activeCol - 1).clamp(0, _headers.length - 1);
    _clearControllersAndFocusNodes();
    _emitDraft();
    if (mounted) setState(() {});
  }

  void _clearControllersAndFocusNodes() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    for (final node in _cellFocusNodes.values) {
      node.dispose();
    }
    _controllers.clear();
    _cellFocusNodes.clear();
    _cellKeys.clear();
  }

  void _handleTableAction(String value) {
    switch (value) {
      case 'insert_row_above':
        _insertRow(above: true);
        break;
      case 'insert_row_below':
        _insertRow(above: false);
        break;
      case 'insert_col_left':
        _insertColumn(left: true);
        break;
      case 'insert_col_right':
        _insertColumn(left: false);
        break;
      case 'delete_row':
        _deleteActiveRow();
        break;
      case 'delete_col':
        _deleteActiveColumn();
        break;
      case 'delete_table':
        widget.onDeleteRequested(widget.offset);
        break;
      default:
        break;
    }
  }

  List<double> _resolvedWidths(double maxWidth) {
    for (var rowIndex = 0; rowIndex < _rows.length; rowIndex++) {
      final row = _rows[rowIndex];
      if (row.length < _headers.length) {
        row.addAll(List<String>.filled(_headers.length - row.length, ''));
      } else if (row.length > _headers.length) {
        _rows[rowIndex] = row.sublist(0, _headers.length);
      }
    }

    if (_columnWidths.length < _headers.length) {
      _columnWidths.addAll(
        List<double>.filled(_headers.length - _columnWidths.length, 0),
      );
    } else if (_columnWidths.length > _headers.length) {
      _columnWidths = _columnWidths.sublist(0, _headers.length);
    }

    final auto = <double>[];
    for (var col = 0; col < _headers.length; col++) {
      var maxLen = _headers[col].trim().length;
      for (final row in _rows) {
        final valueLen = row[col].trim().length;
        if (valueLen > maxLen) maxLen = valueLen;
      }
      auto.add((maxLen * 8.4 + 48).clamp(_minColWidth, 360).toDouble());
    }

    final hasConfigured = _columnWidths.any((width) => width > 0);
    final widths = List<double>.generate(_headers.length, (index) {
      final configured = index < _columnWidths.length
          ? _columnWidths[index]
          : 0;
      if (hasConfigured && configured > 0) {
        return configured.clamp(_minColWidth, _maxColWidth).toDouble();
      }
      return auto[index];
    });
    final total = widths.fold<double>(
      0,
      (runningTotal, value) => runningTotal + value,
    );
    if (total < maxWidth && total > 0) {
      if (!hasConfigured) {
        final scale = maxWidth / total;
        return widths
            .map(
              (value) =>
                  (value * scale).clamp(_minColWidth, _maxColWidth).toDouble(),
            )
            .toList(growable: false);
      }
      // Keep manual resize feel, but prevent left-collapsed layout by
      // distributing remainder across columns that can still grow.
      final expanded = List<double>.from(widths, growable: true);
      var remainder = maxWidth - total;
      var guard = 0;
      while (remainder > 0.5 && guard < 10) {
        final targets = <int>[
          for (var i = 0; i < expanded.length; i++)
            if (expanded[i] < _maxColWidth - 0.5) i,
        ];
        if (targets.isEmpty) break;
        final addPerColumn = remainder / targets.length;
        var consumed = 0.0;
        for (final index in targets) {
          final next = (expanded[index] + addPerColumn).clamp(
            _minColWidth,
            _maxColWidth,
          );
          consumed += (next - expanded[index]);
          expanded[index] = next;
        }
        if (consumed <= 0.01) break;
        remainder -= consumed;
        guard += 1;
      }
      return expanded.toList(growable: false);
    }
    return widths;
  }

  @override
  Widget build(BuildContext context) {
    final showTableControls =
        !widget.readOnly && (_hovered || _selected || _optionsMenuOpen);
    return TapRegion(
      groupId: widget.interactionGroupId,
      onTapOutside: (_) {
        if (_optionsMenuOpen) return;
        // Clicking outside the table should always exit table-cell selection
        // and restore normal editor typing/caret behavior.
        if (!_anyCellHasFocus() &&
            !_selected &&
            !_hasCellSelectionRange &&
            !_allCellsSelected) {
          return;
        }
        _clearTableInteraction();
      },
      child: Focus(
        focusNode: _tableFocusNode,
        onFocusChange: (focused) {
          if (!focused) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (!_anyCellHasFocus() && !_optionsMenuOpen) {
                if (!_allCellsSelected && !_hasCellSelectionRange) {
                  widget.onEditingStateChanged(widget.offset, false);
                  _selected = false;
                  _commitNow();
                }
                _notifySelectionState();
                if (mounted) setState(() {});
              }
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 920.0;
              final widths = _resolvedWidths(maxWidth);
              final totalWidth = widths.fold<double>(
                0,
                (runningTotal, value) => runningTotal + value,
              );
              return MouseRegion(
                onEnter: (_) {
                  if (_hovered) return;
                  _hovered = true;
                  if (mounted) setState(() {});
                },
                onExit: (_) {
                  if (!_hovered || _optionsMenuOpen) return;
                  _hovered = false;
                  if (mounted) setState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selected && !_anyCellHasFocus()
                          ? const Color(0xFF1B5E20)
                          : Colors.black.withValues(alpha: 0.10),
                      width: _selected && !_anyCellHasFocus() ? 1.6 : 1,
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (event) {
                            if (widget.readOnly) return;
                            final target = _cellAtGlobalPosition(
                              event.position,
                            );
                            if (target == null) return;
                            final targetNode = _focusNodeFor(
                              isHeader: false,
                              row: target.row,
                              col: target.col,
                            );
                            final shiftSelecting =
                                _isShiftPressed() &&
                                (_hasCellSelectionRange || _allCellsSelected);
                            if (shiftSelecting) {
                              _setActiveCellWithoutResettingAnchor(
                                target.row,
                                target.col,
                              );
                              _updateDragSelectionExtent(
                                target.row,
                                target.col,
                              );
                            } else {
                              // Normal click re-anchors selection to clicked cell.
                              _setCellSelection(target.row, target.col);
                            }
                            // If user is already editing this exact cell,
                            // preserve native text selection drag behavior.
                            if (targetNode.hasFocus) {
                              return;
                            }
                            targetNode.requestFocus();
                          },
                          onPointerMove: (event) {
                            if (widget.readOnly) return;
                            // Drag range selection across web text inputs can
                            // trigger active-input assertions in Flutter web.
                            // Keep selection stable and use Shift+click for range.
                            return;
                          },
                          onPointerUp: (_) {},
                          onPointerCancel: (_) {},
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: math.max(totalWidth, maxWidth),
                              child: Table(
                                columnWidths: {
                                  for (var i = 0; i < widths.length; i++)
                                    i: FixedColumnWidth(widths[i]),
                                },
                                border: TableBorder.all(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  width: 1,
                                ),
                                children: List.generate(_rows.length, (row) {
                                  return TableRow(
                                    children: List.generate(_headers.length, (
                                      col,
                                    ) {
                                      final ctrl = _controllerFor(
                                        isHeader: false,
                                        row: row,
                                        col: col,
                                      );
                                      final node = _focusNodeFor(
                                        isHeader: false,
                                        row: row,
                                        col: col,
                                      );
                                      final cellBold = _cellBold(row, col);
                                      final cellItalic = _cellItalic(row, col);
                                      final cellAlign = _cellAlign(row, col);
                                      final cellFontKey = _cellFontFamilyKey(
                                        row,
                                        col,
                                      );
                                      final cellFontSize = _cellFontSize(
                                        row,
                                        col,
                                      );
                                      final cellSelected =
                                          _isCellInsideSelection(row, col);
                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Positioned.fill(
                                            child: IgnorePointer(
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 90,
                                                ),
                                                color: cellSelected
                                                    ? const Color(
                                                        0xFF1B5E20,
                                                      ).withValues(alpha: 0.08)
                                                    : Colors.transparent,
                                              ),
                                            ),
                                          ),
                                          Focus(
                                            key: _cellContainerKey(row, col),
                                            onKeyEvent: (focusNode, event) =>
                                                _handleCellKey(
                                                  event: event,
                                                  isHeader: false,
                                                  row: row,
                                                  col: col,
                                                ),
                                            child: TextField(
                                              readOnly: widget.readOnly,
                                              enableInteractiveSelection: false,
                                              controller: ctrl,
                                              focusNode: node,
                                              textAlign: cellAlign,
                                              minLines: 1,
                                              maxLines: null,
                                              keyboardType:
                                                  TextInputType.multiline,
                                              textInputAction:
                                                  TextInputAction.newline,
                                              onTap: () {
                                                _selected = false;
                                                // Selection is handled on pointer-down.
                                                // Keep tap focused on entering text mode.
                                                widget.onEditingStateChanged(
                                                  widget.offset,
                                                  true,
                                                );
                                                if (!node.hasFocus) {
                                                  node.requestFocus();
                                                }
                                                if (mounted) setState(() {});
                                              },
                                              onChanged: (value) =>
                                                  _updateCellValue(
                                                    isHeader: false,
                                                    row: row,
                                                    col: col,
                                                    value: value,
                                                  ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                disabledBorder:
                                                    InputBorder.none,
                                                errorBorder: InputBorder.none,
                                                focusedErrorBorder:
                                                    InputBorder.none,
                                                filled: false,
                                                contentPadding:
                                                    EdgeInsets.fromLTRB(
                                                      10,
                                                      8,
                                                      10,
                                                      8,
                                                    ),
                                              ),
                                              style:
                                                  const TextStyle(
                                                    color: Color(0xFF1F2A1F),
                                                    height: 1.35,
                                                  ).copyWith(
                                                    fontWeight: cellBold
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                    fontStyle: cellItalic
                                                        ? FontStyle.italic
                                                        : FontStyle.normal,
                                                    fontFamily:
                                                        _fontFamilyFromKey(
                                                          cellFontKey,
                                                        ),
                                                    fontSize: cellFontSize,
                                                  ),
                                            ),
                                          ),
                                          if (!widget.readOnly &&
                                              row == 0 &&
                                              col < _headers.length - 1)
                                            Positioned(
                                              right: -4,
                                              top: 0,
                                              bottom: 0,
                                              width: 8,
                                              child: MouseRegion(
                                                cursor: SystemMouseCursors
                                                    .resizeLeftRight,
                                                child: GestureDetector(
                                                  behavior: HitTestBehavior
                                                      .translucent,
                                                  onHorizontalDragUpdate: (details) {
                                                    final next =
                                                        (_columnWidths[col] == 0
                                                            ? widths[col]
                                                            : _columnWidths[col]) +
                                                        details.delta.dx;
                                                    _columnWidths[col] = next
                                                        .clamp(
                                                          _minColWidth,
                                                          _maxColWidth,
                                                        );
                                                    _emitDraft();
                                                    if (mounted) {
                                                      setState(() {});
                                                    }
                                                  },
                                                  onHorizontalDragEnd: (_) {
                                                    _emitDraft();
                                                  },
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    }),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (showTableControls)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: 'Move table',
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.move,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        _selectWholeTable();
                                      },
                                      child: IconButton(
                                        tooltip: 'Move table',
                                        onPressed: () {
                                          _selectWholeTable();
                                        },
                                        mouseCursor: SystemMouseCursors.move,
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 18,
                                        color: _selected
                                            ? const Color(0xFF1B5E20)
                                            : const Color(0xFF6D7F62),
                                        icon: const Icon(
                                          Icons.drag_indicator_rounded,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: PopupMenuButton<String>(
                                    tooltip: 'Table options',
                                    onOpened: () {
                                      _optionsMenuOpen = true;
                                      _selectWholeTable();
                                      if (mounted) setState(() {});
                                    },
                                    onCanceled: () {
                                      _optionsMenuOpen = false;
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (!mounted) return;
                                            if (!_anyCellHasFocus()) {
                                              if (!_allCellsSelected &&
                                                  !_hasCellSelectionRange) {
                                                widget.onEditingStateChanged(
                                                  widget.offset,
                                                  false,
                                                );
                                                _commitNow();
                                              }
                                              _notifySelectionState();
                                            }
                                          });
                                      if (mounted) setState(() {});
                                    },
                                    onSelected: (value) {
                                      _optionsMenuOpen = false;
                                      _handleTableAction(value);
                                      if (mounted) setState(() {});
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'insert_row_above',
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Text('Insert row above'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'insert_row_below',
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Text('Insert row below'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'insert_col_left',
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Text('Insert column left'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'insert_col_right',
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Text('Insert column right'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete_row',
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Text('Delete row'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete_col',
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Text('Delete column'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete_table',
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Text('Delete table'),
                                        ),
                                      ),
                                    ],
                                    icon: Icon(
                                      Icons.more_horiz_rounded,
                                      size: 19,
                                      color: _selected
                                          ? const Color(0xFF1B5E20)
                                          : const Color(0xFF6D7F62),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TableCellPosition {
  const _TableCellPosition({
    required this.isHeader,
    required this.row,
    required this.col,
  });

  final bool isHeader;
  final int row;
  final int col;
}

class HandbookDocsEditorPage extends StatefulWidget {
  final VoidCallback? onBack;
  final UnsavedChangesController? unsavedChangesController;

  const HandbookDocsEditorPage({
    super.key,
    this.onBack,
    this.unsavedChangesController,
  });

  @override
  State<HandbookDocsEditorPage> createState() => _HandbookDocsEditorPageState();
}

class _UnknownEmbedBuilder extends quill.EmbedBuilder {
  const _UnknownEmbedBuilder();

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
        'Unsupported block: $embedType',
        style: const TextStyle(
          color: Color(0xFF6D7F62),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

enum _ImageHandleKind {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
  rotate,
}

class _InteractiveImageEmbedBuilder extends quill.EmbedBuilder {
  const _InteractiveImageEmbedBuilder({
    required this.selectedOffset,
    required this.cropMode,
    required this.onSelect,
    required this.onHandleDrag,
    required this.onRotateDrag,
    required this.onRotateQuarterTurn,
  });

  final int? Function() selectedOffset;
  final bool Function() cropMode;
  final void Function(int offset) onSelect;
  final void Function(int offset, _ImageHandleKind handle, Offset delta)
  onHandleDrag;
  final void Function(int offset, double degreeDelta) onRotateDrag;
  final void Function(int offset) onRotateQuarterTurn;

  @override
  String get key => quill.BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final node = embedContext.node;
    final offset = node.documentOffset;
    final imageSource = node.value.data.toString();

    final styleMap = _parseStyleMap(
      node.style.attributes[quill.Attribute.style.key]?.value?.toString() ?? '',
    );

    final width =
        _tryParseDouble(
          node.style.attributes[quill.Attribute.width.key]?.value?.toString(),
        ) ??
        _tryParseDouble(styleMap['width']) ??
        420;
    final height =
        _tryParseDouble(
          node.style.attributes[quill.Attribute.height.key]?.value?.toString(),
        ) ??
        _tryParseDouble(styleMap['height']) ??
        (width * 0.62);

    final rotationDegrees = _tryParseDouble(styleMap['rotation']) ?? 0;
    final alignment = _normalizeAlignment(styleMap['alignment']);
    final displayMode = _normalizeDisplayMode(styleMap['displayMode']);
    final caption = _decodeCaption(styleMap['caption']);
    final cropLeft = (_tryParseDouble(styleMap['cropLeft']) ?? 0).clamp(
      0.0,
      0.45,
    );
    final cropTop = (_tryParseDouble(styleMap['cropTop']) ?? 0).clamp(
      0.0,
      0.45,
    );
    final cropRight = (_tryParseDouble(styleMap['cropRight']) ?? 0).clamp(
      0.0,
      0.45,
    );
    final cropBottom = (_tryParseDouble(styleMap['cropBottom']) ?? 0).clamp(
      0.0,
      0.45,
    );

    return _InteractiveImageEmbedFrame(
      imageSource: imageSource,
      width: width,
      height: height,
      rotationDegrees: rotationDegrees,
      alignment: alignment,
      displayMode: displayMode,
      caption: caption,
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropRight: cropRight,
      cropBottom: cropBottom,
      readOnly: embedContext.readOnly,
      selected: selectedOffset() == offset,
      cropMode: cropMode(),
      onSelect: () => onSelect(offset),
      onHandleDrag: (handle, delta) => onHandleDrag(offset, handle, delta),
      onRotateDrag: (delta) => onRotateDrag(offset, delta),
      onRotateQuarterTurn: () => onRotateQuarterTurn(offset),
    );
  }

  static Map<String, String> _parseStyleMap(String style) {
    final map = <String, String>{};
    for (final segment in style.split(';')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length < 2) continue;
      final name = parts.first.trim();
      final value = parts.sublist(1).join(':').trim();
      if (name.isEmpty || value.isEmpty) continue;
      map[name] = value;
    }
    return map;
  }

  static double? _tryParseDouble(String? raw) {
    if (raw == null) return null;
    return double.tryParse(raw.trim());
  }

  static String _normalizeAlignment(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == 'left' || value == 'right') return value;
    return 'center';
  }

  static String _normalizeDisplayMode(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == 'full' || value == 'side') return value;
    return 'inline';
  }

  static String _decodeCaption(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }
}

class _InteractiveImageEmbedFrame extends StatelessWidget {
  const _InteractiveImageEmbedFrame({
    required this.imageSource,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.alignment,
    required this.displayMode,
    required this.caption,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.readOnly,
    required this.selected,
    required this.cropMode,
    required this.onSelect,
    required this.onHandleDrag,
    required this.onRotateDrag,
    required this.onRotateQuarterTurn,
  });

  final String imageSource;
  final double width;
  final double height;
  final double rotationDegrees;
  final String alignment;
  final String displayMode;
  final String caption;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final bool readOnly;
  final bool selected;
  final bool cropMode;
  final VoidCallback onSelect;
  final void Function(_ImageHandleKind handle, Offset delta) onHandleDrag;
  final void Function(double degreeDelta) onRotateDrag;
  final VoidCallback onRotateQuarterTurn;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: readOnly
          ? SystemMouseCursors.basic
          : selected
          ? SystemMouseCursors.grab
          : SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onSelect(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          onTapDown: (_) => onSelect(),
          onPanDown: (_) => onSelect(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxContentWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 920.0;

              var safeWidth = width.clamp(120.0, 1200.0);
              final safeHeight = height.clamp(90.0, 1200.0);

              if (displayMode == 'full') {
                safeWidth = math.max(160.0, maxContentWidth - 6);
              } else if (displayMode == 'side') {
                safeWidth = math.min(safeWidth, maxContentWidth * 0.48);
              } else {
                safeWidth = math.min(safeWidth, maxContentWidth - 4);
              }

              final rotatedFrameSize = _rotatedFrameSize(safeWidth, safeHeight);
              final imageFrame = _buildEditableImageFrame(
                safeWidth: safeWidth,
                safeHeight: safeHeight,
              );
              final captionWidget = caption.trim().isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        caption,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF6D7F62),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    );

              Widget content;
              if (displayMode == 'side') {
                final imageCard = SizedBox(
                  width: rotatedFrameSize.width,
                  child: imageFrame,
                );
                final textCard = Expanded(
                  child: Container(
                    constraints: BoxConstraints(minHeight: safeHeight * 0.65),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8F7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Text(
                      caption.trim().isEmpty
                          ? 'Side image block. Add paragraph text above or below this image block.'
                          : caption,
                      style: const TextStyle(
                        color: Color(0xFF556655),
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                  ),
                );
                final imageOnRight = alignment == 'right';
                content = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!imageOnRight) imageCard,
                    const SizedBox(width: 12),
                    textCard,
                    if (imageOnRight) ...[const SizedBox(width: 12), imageCard],
                  ],
                );
              } else {
                content = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [imageFrame, captionWidget],
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Align(
                  alignment: _blockAlignment(alignment),
                  child: content,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Alignment _blockAlignment(String alignment) {
    if (alignment == 'left') return Alignment.centerLeft;
    if (alignment == 'right') return Alignment.centerRight;
    return Alignment.center;
  }

  Size _rotatedFrameSize(double width, double height) {
    final angle = rotationDegrees * math.pi / 180;
    final cosA = math.cos(angle).abs();
    final sinA = math.sin(angle).abs();
    final rotatedWidth = math.max(1.0, (width * cosA) + (height * sinA));
    final rotatedHeight = math.max(1.0, (width * sinA) + (height * cosA));
    return Size(rotatedWidth, rotatedHeight);
  }

  Widget _buildEditableImageFrame({
    required double safeWidth,
    required double safeHeight,
  }) {
    final visibleWidthFactor = (1 - cropLeft - cropRight).clamp(0.10, 1.0);
    final visibleHeightFactor = (1 - cropTop - cropBottom).clamp(0.10, 1.0);
    final alignmentX = ((cropLeft - cropRight) / visibleWidthFactor).clamp(
      -1.0,
      1.0,
    );
    final alignmentY = ((cropTop - cropBottom) / visibleHeightFactor).clamp(
      -1.0,
      1.0,
    );
    final hasCrop =
        cropLeft > 0 || cropTop > 0 || cropRight > 0 || cropBottom > 0;
    final rotatedFrameSize = _rotatedFrameSize(safeWidth, safeHeight);

    final imageWidget = _buildImageWidget(
      imageSource: imageSource,
      width: safeWidth,
      height: safeHeight,
      fit: hasCrop ? BoxFit.cover : BoxFit.contain,
    );

    final croppedImage = ClipRect(
      child: Align(
        alignment: Alignment(alignmentX, alignmentY),
        widthFactor: visibleWidthFactor,
        heightFactor: visibleHeightFactor,
        child: imageWidget,
      ),
    );

    final frame = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: safeWidth,
          height: safeHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1B5E20)
                  : Colors.black.withValues(alpha: 0.06),
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: croppedImage,
          ),
        ),
        if (selected && !readOnly) ...[
          _handle(
            alignment: Alignment.topLeft,
            kind: _ImageHandleKind.topLeft,
            square: true,
          ),
          _handle(
            alignment: Alignment.topCenter,
            kind: _ImageHandleKind.top,
            square: true,
          ),
          _handle(
            alignment: Alignment.topRight,
            kind: _ImageHandleKind.topRight,
            square: true,
          ),
          _handle(
            alignment: Alignment.centerRight,
            kind: _ImageHandleKind.right,
            square: true,
          ),
          _handle(
            alignment: Alignment.bottomRight,
            kind: _ImageHandleKind.bottomRight,
            square: true,
          ),
          _handle(
            alignment: Alignment.bottomCenter,
            kind: _ImageHandleKind.bottom,
            square: true,
          ),
          _handle(
            alignment: Alignment.bottomLeft,
            kind: _ImageHandleKind.bottomLeft,
            square: true,
          ),
          _handle(
            alignment: Alignment.centerLeft,
            kind: _ImageHandleKind.left,
            square: true,
          ),
          _handle(
            alignment: const Alignment(0, -1.34),
            kind: _ImageHandleKind.rotate,
            square: false,
          ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.66),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                cropMode ? 'Crop handles' : 'Resize handles',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ],
    );
    return SizedBox(
      width: rotatedFrameSize.width,
      height: rotatedFrameSize.height,
      child: Center(
        child: Transform.rotate(
          angle: rotationDegrees * math.pi / 180,
          child: frame,
        ),
      ),
    );
  }

  Widget _handle({
    required Alignment alignment,
    required _ImageHandleKind kind,
    required bool square,
  }) {
    final handleSize = square ? 14.0 : 24.0;
    return Align(
      alignment: alignment,
      child: MouseRegion(
        cursor: _cursorForHandle(kind),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => onSelect(),
          onPanUpdate: (details) {
            if (kind == _ImageHandleKind.rotate) {
              onRotateDrag(details.delta.dx * 0.45);
              return;
            }
            onHandleDrag(kind, details.delta);
          },
          onTap: kind == _ImageHandleKind.rotate ? onRotateQuarterTurn : null,
          child: Container(
            width: handleSize,
            height: handleSize,
            decoration: BoxDecoration(
              color: square ? Colors.white : const Color(0xFF1B5E20),
              borderRadius: BorderRadius.circular(square ? 3 : 99),
              border: Border.all(
                color: square ? const Color(0xFF1B5E20) : Colors.white,
                width: square ? 1.4 : 1,
              ),
            ),
            child: square
                ? null
                : const Icon(
                    Icons.rotate_right_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }

  MouseCursor _cursorForHandle(_ImageHandleKind kind) {
    switch (kind) {
      case _ImageHandleKind.top:
      case _ImageHandleKind.bottom:
        return SystemMouseCursors.resizeUpDown;
      case _ImageHandleKind.left:
      case _ImageHandleKind.right:
        return SystemMouseCursors.resizeLeftRight;
      case _ImageHandleKind.topLeft:
      case _ImageHandleKind.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case _ImageHandleKind.topRight:
      case _ImageHandleKind.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case _ImageHandleKind.rotate:
        return SystemMouseCursors.grab;
    }
  }

  Widget _buildImageWidget({
    required String imageSource,
    required double width,
    required double height,
    required BoxFit fit,
  }) {
    final bytes = _tryDecodeDataUri(imageSource);
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _imageError(width, height),
      );
    }
    return Image.network(
      imageSource,
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => _imageError(width, height),
    );
  }

  Widget _imageError(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF2F2F2),
      alignment: Alignment.center,
      child: const Text(
        'Image unavailable',
        style: TextStyle(color: Color(0xFF6D7F62), fontWeight: FontWeight.w700),
      ),
    );
  }

  Uint8List? _tryDecodeDataUri(String imageSource) {
    if (!imageSource.startsWith('data:image/')) return null;
    final commaIndex = imageSource.indexOf(',');
    if (commaIndex < 0 || commaIndex >= imageSource.length - 1) return null;
    final encoded = imageSource.substring(commaIndex + 1);
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }
}

class _EditorSaveIntent extends Intent {
  const _EditorSaveIntent();
}

class _EditorSelectAllIntent extends Intent {
  const _EditorSelectAllIntent();
}

enum _InlineFormatType { bold, italic, underline, strike }

class _EditorToggleInlineIntent extends Intent {
  const _EditorToggleInlineIntent(this.type);

  final _InlineFormatType type;
}

enum _ListFormatType { bullet, numbered, check }

enum _CaseTransform { sentence, lowercase, uppercase, capitalize, toggle }

enum _EditorViewToggleAction { ribbon, entries, outline }

class _EditorToggleListIntent extends Intent {
  const _EditorToggleListIntent(this.type);

  final _ListFormatType type;
}

class _EditorIndentIntent extends Intent {
  const _EditorIndentIntent({required this.increase});

  final bool increase;
}

class _EditorUndoIntent extends Intent {
  const _EditorUndoIntent();
}

class _EditorRedoIntent extends Intent {
  const _EditorRedoIntent();
}

class _EditorInsertLinkIntent extends Intent {
  const _EditorInsertLinkIntent();
}

@immutable
class _EditorSaveViewState {
  const _EditorSaveViewState({
    required this.message,
    required this.isSaving,
    required this.hasUnsavedChanges,
    required this.autoSaveEnabled,
  });

  final String message;
  final bool isSaving;
  final bool hasUnsavedChanges;
  final bool autoSaveEnabled;
}

enum _UnsavedExitAction { save, discard, cancel }

class _SaveNotePromptResult {
  const _SaveNotePromptResult({required this.note});

  final String note;
}

class _EntryOutlineHeading {
  const _EntryOutlineHeading({
    required this.text,
    required this.offset,
    required this.depth,
  });

  final String text;
  final int offset;
  final int depth;
}

class _PendingNodeDraft {
  const _PendingNodeDraft({
    required this.title,
    required this.useSectionNumbering,
    required this.contentOps,
    required this.attachments,
  });

  final String title;
  final bool useSectionNumbering;
  final List<dynamic> contentOps;
  final List<Map<String, dynamic>> attachments;
}

class _CachedNodeContent {
  const _CachedNodeContent({
    required this.contentJson,
    required this.attachments,
  });

  final String contentJson;
  final List<Map<String, dynamic>> attachments;
}

class _HandbookDocsEditorPageState extends State<HandbookDocsEditorPage> {
  static const _bg = Colors.white;
  static const _primary = Color(0xFF1B5E20);
  static const _text = Color(0xFF1F2A1F);
  static const _muted = Color(0xFF6D7F62);
  static const _colHbVersion = 'hb_version';
  static const _colHbSection = 'hb_section';
  static const _colHbContents = 'hb_contents';
  static const _autosaveDebounce = Duration(seconds: 2);
  static const List<MapEntry<String, String>> _fontFamilyOptions = [
    MapEntry('default', 'Aptos (Body)'),
    MapEntry('sans-serif', 'Arial'),
    MapEntry('serif', 'Times New Roman'),
    MapEntry('monospace', 'Courier New'),
  ];
  static const List<String> _standardColorPalette = [
    '#C00000',
    '#FF0000',
    '#FFC000',
    '#FFFF00',
    '#92D050',
    '#00B050',
    '#00B0F0',
    '#0070C0',
    '#002060',
    '#7030A0',
  ];
  static const List<String> _extendedColorPalette = [
    '#FFFF00',
    '#00FF00',
    '#00FFFF',
    '#FF00FF',
    '#0000FF',
    '#FF0000',
    '#008080',
    '#006400',
    '#800080',
    '#4B0082',
    '#B8860B',
    '#2F4F4F',
    '#808000',
    '#708090',
    '#8B0000',
    '#1B5E20',
    '#000000',
    '#FFFFFF',
    '#D9D9D9',
    '#BFBFBF',
    '#A6A6A6',
    '#7F7F7F',
    '#595959',
    '#3F3F3F',
  ];

  final _db = AppFirestore.instance;
  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _editorFocusNode = FocusNode(debugLabel: 'handbook_editor_focus');
  final _editorScrollController = ScrollController();
  final ValueNotifier<_EditorSaveViewState> _saveViewState = ValueNotifier(
    const _EditorSaveViewState(
      message: 'Saved',
      isSaving: false,
      hasUnsavedChanges: false,
      autoSaveEnabled: false,
    ),
  );

  quill.QuillController _editorController = quill.QuillController.basic();
  late final List<quill.EmbedBuilder> _embedBuilders;
  StreamSubscription<quill.DocChange>? _docChangeSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _nodeSub;
  Timer? _autosaveTimer;
  Timer? _imageStyleFlushTimer;
  int? _pendingImageStyleOffset;
  Map<String, String>? _pendingImageStyleMap;
  final Map<int, Map<String, dynamic>> _pendingTablePayloadByOffset =
      <int, Map<String, dynamic>>{};
  final Map<int, _TableStyleSetter> _tableStyleSetters =
      <int, _TableStyleSetter>{};
  int? _activeTableOffset;
  _TableSelectionState _activeTableSelection = _TableSelectionState.empty;
  bool _isTableCellEditing = false;

  bool _loadingContext = true;
  String? _contextError;
  String? _handbookId;
  String _handbookVersion = '--';
  String _treeSnapshotSignature = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _versionSub;

  List<HandbookNodeDoc> _nodes = const [];
  final Set<String> _expandedNodeIds = <String>{};
  String? _selectedNodeId;
  int? _activeImageOffset;
  bool _imageCropMode = false;
  bool _imageInteractionMode = false;
  bool _editingEnabled = false;
  bool _showRibbon = true;
  final bool _enableImageBehavior = true;
  bool _useSectionNumbering = true;

  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  bool _currentNodeDirty = false;
  bool _suppressDirty = false;
  bool _autoSaveEnabled = false;
  Future<void>? _saveInFlight;
  int _editVersion = 0;
  int _switchVersion = 0;
  bool _isRootReordering = false;
  DateTime _sectionTapLockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String _saveMessage = 'Saved';
  String _lastSaveNote = '';
  String _query = '';
  final Map<String, _PendingNodeDraft> _pendingNodeDrafts =
      <String, _PendingNodeDraft>{};
  final Map<String, _CachedNodeContent> _contentCacheByNodeId =
      <String, _CachedNodeContent>{};
  bool _entriesPanelCollapsed = false;
  bool _outlinePanelCollapsed = true;
  double _paperZoom = 1.0;
  final GlobalKey _imageSizeButtonKey = GlobalKey();
  final Object _editorInteractionTapGroup = Object();
  OverlayEntry? _imageSizeOverlay;

  List<Map<String, dynamic>> _attachments = const [];

  @override
  void initState() {
    super.initState();
    final fallbackBuilders = kIsWeb
        ? quill_ext.FlutterQuillEmbeds.editorWebBuilders()
        : quill_ext.FlutterQuillEmbeds.editorBuilders();
    _embedBuilders = [
      _InteractiveImageEmbedBuilder(
        selectedOffset: () => _enableImageBehavior ? _activeImageOffset : null,
        cropMode: () => _enableImageBehavior && _imageCropMode,
        onSelect: (offset) {
          if (!_enableImageBehavior) return;
          _onImageOffsetSelected(offset);
        },
        onHandleDrag: (offset, handle, delta) {
          if (!_enableImageBehavior) return;
          _onImageHandleDrag(offset, handle, delta);
        },
        onRotateDrag: (offset, degreeDelta) {
          if (!_enableImageBehavior) return;
          _onImageRotateDrag(offset, degreeDelta);
        },
        onRotateQuarterTurn: (offset) {
          if (!_enableImageBehavior) return;
          _onImageRotateQuarterTurn(offset);
        },
      ),
      _TableEmbedBuilder(
        onDraftChanged: _onTableDraftChanged,
        onCommitRequested: _onTableCommitRequested,
        onDeleteRequested: _onTableDeleteRequested,
        onEditingStateChanged: _onTableEditingStateChanged,
        onSelectionStateChanged: _onTableSelectionStateChanged,
        onStyleSetterChanged: _onTableStyleSetterChanged,
        interactionGroupId: _editorInteractionTapGroup,
      ),
      ...fallbackBuilders.where(
        (builder) =>
            builder.key != quill.BlockEmbed.imageType &&
            builder.key != _tableEmbedType,
      ),
    ];
    _bindEditorDocChanges();
    _titleCtrl.addListener(_onMetaChanged);
    widget.unsavedChangesController?.setDiscardHandler(_discardDraftFromGuard);
    widget.unsavedChangesController?.setSaveHandler(_saveDraftFromGuard);
    widget.unsavedChangesController?.setDirty(_hasUnsavedChanges);
    _publishSaveViewState();
    _loadContext();
  }

  @override
  void dispose() {
    _closeImageSizeDropdown();
    _autosaveTimer?.cancel();
    _imageStyleFlushTimer?.cancel();
    _pendingTablePayloadByOffset.clear();
    _tableStyleSetters.clear();
    _docChangeSub?.cancel();
    _nodeSub?.cancel();
    _versionSub?.cancel();
    _editorController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _saveViewState.dispose();
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    widget.unsavedChangesController?.setDiscardHandler(null);
    widget.unsavedChangesController?.setSaveHandler(null);
    widget.unsavedChangesController?.clear();
    super.dispose();
  }

  void _discardDraftFromGuard() {
    unawaited(_discardCurrentDrafts());
  }

  Future<bool> _saveDraftFromGuard() async {
    await _saveAllPendingDrafts(source: 'guard');
    return !_hasUnsavedChanges;
  }

  HandbookNodeDoc? get _selectedNode => _nodeById(_selectedNodeId);

  HandbookNodeDoc? _nodeById(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    for (final node in _nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  List<HandbookNodeDoc> _childrenOf(String parentId) {
    final nodes = _nodes.where((node) => node.parentId == parentId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return nodes;
  }

  List<HandbookNodeDoc> _rootNodes() => _childrenOf('');

  bool _effectiveUseSectionNumberingForNode(HandbookNodeDoc node) {
    if (node.id == _selectedNodeId) return _useSectionNumbering;
    return node.useSectionNumbering;
  }

  Map<String, String> _buildRootSectionNumberMap() {
    final numbers = <String, String>{};
    var next = 0;
    for (final node in _rootNodes()) {
      if (_effectiveUseSectionNumberingForNode(node)) {
        next += 1;
        numbers[node.id] = '$next';
      } else {
        numbers[node.id] = '';
      }
    }
    return numbers;
  }

  List<HandbookNodeDoc> _sortNodes(List<HandbookNodeDoc> nodes) {
    final sorted = [...nodes]
      ..sort((a, b) {
        final parentCompare = a.parentId.compareTo(b.parentId);
        if (parentCompare != 0) return parentCompare;
        final orderCompare = a.sortOrder.compareTo(b.sortOrder);
        if (orderCompare != 0) return orderCompare;
        return a.title.compareTo(b.title);
      });
    return sorted;
  }

  String _buildTreeSnapshotSignature(List<HandbookNodeDoc> nodes) {
    final buffer = StringBuffer();
    for (final node in nodes) {
      buffer
        ..write(node.id)
        ..write('|')
        ..write(node.parentId)
        ..write('|')
        ..write(node.sortOrder)
        ..write('|')
        ..write(node.title)
        ..write('|')
        ..write(node.status)
        ..write('|')
        ..write(node.isVisible ? '1' : '0')
        ..write('|')
        ..write(node.tags.join(','))
        ..write(';');
    }
    return buffer.toString();
  }

  void _safeSetState(VoidCallback updater) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final inLayoutPhase =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (inLayoutPhase) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(updater);
      });
      return;
    }
    setState(updater);
  }

  void _scheduleSwitchToNode(String nodeId, {bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _switchToNode(nodeId, force: force);
    });
  }

  bool _canHandleSectionTap() {
    if (_isRootReordering) return false;
    return DateTime.now().isAfter(_sectionTapLockedUntil);
  }

  // Save state is pushed through a notifier so autosave status updates do not
  // trigger full-page rebuilds (which can steal focus in web editors).
  void _publishSaveViewState() {
    _saveViewState.value = _EditorSaveViewState(
      message: _saveMessage,
      isSaving: _isSaving,
      hasUnsavedChanges: _hasUnsavedChanges,
      autoSaveEnabled: _autoSaveEnabled,
    );
    widget.unsavedChangesController?.setDirty(_hasUnsavedChanges);
  }

  quill.Document _parseDocument(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) {
        final normalized = _normalizeLegacyEmbeds(decoded);
        return quill.Document.fromJson(normalized);
      }
    } catch (_) {}
    final plain = content.trim();
    if (plain.isNotEmpty) {
      return quill.Document()..insert(0, '$plain\n');
    }
    return quill.Document()..insert(0, '\n');
  }

  List<Map<String, dynamic>> _normalizeLegacyEmbeds(List<dynamic> rawOps) {
    final normalizedOps = <Map<String, dynamic>>[];

    for (final rawOp in rawOps) {
      if (rawOp is! Map) continue;
      final op = Map<String, dynamic>.from(rawOp);
      final insert = op['insert'];
      if (insert is Map) {
        final insertMap = Map<String, dynamic>.from(insert);
        final legacyTableData = insertMap['x-embed-table'];
        if (legacyTableData != null) {
          final payload = _normalizeTablePayload(legacyTableData.toString());
          normalizedOps.add({
            'insert': {_tableEmbedType: jsonEncode(payload)},
          });
          continue;
        }
      }
      if (insert is String) {
        final parsedTable = _tryParseStandaloneMarkdownTable(insert.trim());
        if (parsedTable != null) {
          normalizedOps.add({
            'insert': {_tableEmbedType: jsonEncode(parsedTable)},
          });
          normalizedOps.add({'insert': '\n'});
          continue;
        }
      }
      normalizedOps.add(op);
    }

    if (normalizedOps.isEmpty) {
      return [
        {'insert': '\n'},
      ];
    }

    final lastInsert = normalizedOps.last['insert'];
    if (lastInsert is String && !lastInsert.endsWith('\n')) {
      normalizedOps.add({'insert': '\n'});
    }
    return normalizedOps;
  }

  Future<Map<String, dynamic>> _loadEditorMeta() async {
    final hbMetaSnap = await _db.collection(_colHbVersion).doc('current').get();
    return hbMetaSnap.data() ?? const <String, dynamic>{};
  }

  Future<void> _loadContext() async {
    setState(() {
      _loadingContext = true;
      _contextError = null;
    });

    try {
      final data = await _loadEditorMeta();
      final activeVersion = (data['activeVersionId'] ?? '').toString().trim();
      final activeLabel = (data['activeVersionLabel'] ?? activeVersion)
          .toString()
          .trim();
      final editingVersion = (data['editingVersionId'] ?? activeVersion)
          .toString()
          .trim();
      if (editingVersion.isEmpty) {
        throw Exception(
          'No editing version selected. Open Manage Handbook and click Open.',
        );
      }
      final editingVersionSnap = await _db
          .collection(_colHbVersion)
          .doc(editingVersion)
          .get();
      if (!editingVersionSnap.exists) {
        throw Exception(
          'This handbook version no longer exists. Return to Manage Handbook and open a valid version.',
        );
      }
      final editingLabel =
          (data['editingVersionLabel'] ??
                  (editingVersion == activeVersion
                      ? activeLabel
                      : editingVersion))
              .toString()
              .trim();

      if (!mounted) return;
      setState(() {
        _handbookId = editingVersion;
        _handbookVersion = editingLabel;
        _loadingContext = false;
      });
      _bindVersionDoc();
      _bindNodes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contextError = e.toString();
        _loadingContext = false;
      });
    }
  }

  bool get _isWorkflowReadOnly => false;

  bool get _isEditorReadOnly => !_editingEnabled || _isWorkflowReadOnly;

  String get _editorReadOnlyMessage {
    if (!_editingEnabled) {
      return 'View mode - click Edit to make changes';
    }
    return 'Read-only mode';
  }

  void _showReadOnlyVersionWarning() {
    if (!mounted) return;
    AppScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This section is currently read-only.')),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    AppScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : _primary,
      ),
    );
  }

  void _bindNodes() {
    final handbookId = _handbookId;
    if (handbookId == null || handbookId.isEmpty) return;
    _nodeSub?.cancel();
    _nodeSub = _db
        .collection(_colHbSection)
        .where('versionId', isEqualTo: handbookId)
        .snapshots()
        .listen(
          (snapshot) {
            final nodes = _sortNodes(
              snapshot.docs.map(HandbookNodeDoc.fromDoc).toList(),
            );
            final nextTreeSignature = _buildTreeSnapshotSignature(nodes);
            if (!mounted) return;
            final treeChanged = nextTreeSignature != _treeSnapshotSignature;
            if (treeChanged) {
              _safeSetState(() {
                _nodes = nodes;
                _treeSnapshotSignature = nextTreeSignature;
              });
            } else {
              _nodes = nodes;
            }
            final nodeIds = nodes.map((n) => n.id).toSet();
            _pendingNodeDrafts.removeWhere((id, _) => !nodeIds.contains(id));
            _contentCacheByNodeId.removeWhere((id, _) => !nodeIds.contains(id));
            if (_selectedNodeId != null && !nodeIds.contains(_selectedNodeId)) {
              _currentNodeDirty = false;
            }
            _refreshUnsavedIndicator();

            final selectedId = _selectedNodeId;
            final hasSelectedNode =
                selectedId != null &&
                nodes.any((node) => node.id == selectedId);
            if (selectedId == null && nodes.isNotEmpty) {
              _scheduleSwitchToNode(nodes.first.id, force: true);
            } else if (selectedId != null && !hasSelectedNode) {
              if (nodes.isNotEmpty) {
                _scheduleSwitchToNode(nodes.first.id, force: true);
              } else {
                _resetEditorState();
              }
            }
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => _contextError = e.toString());
          },
        );
  }

  void _bindVersionDoc() {
    final handbookId = _handbookId;
    if (handbookId == null || handbookId.isEmpty) return;
    _versionSub?.cancel();
    _versionSub = _db
        .collection(_colHbVersion)
        .doc(handbookId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            if (!snapshot.exists) {
              _nodeSub?.cancel();
              _safeSetState(() {
                _contextError =
                    'This handbook version no longer exists. Return to Manage Handbook and open a valid version.';
                _loadingContext = false;
                _handbookId = null;
              });
              return;
            }

            final data = snapshot.data() ?? const <String, dynamic>{};
            final nextLabel = (data['label'] ?? _handbookVersion)
                .toString()
                .trim();
            if (nextLabel.isNotEmpty && nextLabel != _handbookVersion) {
              _safeSetState(() => _handbookVersion = nextLabel);
            }
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => _contextError = e.toString());
          },
        );
  }

  Future<void> _switchToNode(String nodeId, {bool force = false}) async {
    if (!force && nodeId == _selectedNodeId) return;
    final switchVersion = ++_switchVersion;
    if (_currentNodeDirty) {
      _stashCurrentNodeDraft();
      if (!mounted || switchVersion != _switchVersion) return;
    }
    final node = _nodeById(nodeId);
    if (node == null) return;
    await _loadNodeToEditor(node);
  }

  Future<void> _loadNodeToEditor(HandbookNodeDoc node) async {
    final pendingDraft = _pendingNodeDrafts[node.id];
    var resolvedContent = node.content;
    var resolvedAttachments = <Map<String, dynamic>>[];
    var resolvedTitle = node.title;
    var resolvedUseSectionNumbering = node.useSectionNumbering;
    quill.Document? prebuiltDocument;
    final loadedFromDraft = pendingDraft != null;
    if (loadedFromDraft) {
      prebuiltDocument = quill.Document.fromJson(
        _normalizeLegacyEmbeds(pendingDraft.contentOps),
      );
      resolvedAttachments = List<Map<String, dynamic>>.from(
        pendingDraft.attachments,
      );
      resolvedTitle = pendingDraft.title;
      resolvedUseSectionNumbering = pendingDraft.useSectionNumbering;
    }
    if (!loadedFromDraft) {
      final cached = _contentCacheByNodeId[node.id];
      if (cached != null) {
        resolvedContent = cached.contentJson;
        resolvedAttachments = List<Map<String, dynamic>>.from(
          cached.attachments,
        );
      } else {
        try {
          final contentSnap = await _db
              .collection(_colHbContents)
              .doc(node.id)
              .get();
          final contentData = contentSnap.data() ?? const <String, dynamic>{};
          final stored = (contentData['content'] ?? '').toString();
          if (stored.trim().isNotEmpty) {
            resolvedContent = stored;
          }
          final rawAttachments =
              (contentData['attachments'] as List?) ?? const [];
          resolvedAttachments = rawAttachments
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
              .toList();
          _contentCacheByNodeId[node.id] = _CachedNodeContent(
            contentJson: resolvedContent,
            attachments: List<Map<String, dynamic>>.from(resolvedAttachments),
          );
        } catch (_) {}
      }
    }

    final oldController = _editorController;
    final document = prebuiltDocument ?? _parseDocument(resolvedContent);
    _pendingTablePayloadByOffset.clear();
    _tableStyleSetters.clear();
    _activeTableOffset = null;
    _activeTableSelection = _TableSelectionState.empty;
    _isTableCellEditing = false;
    final nextController = quill.QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
    nextController.readOnly = _isEditorReadOnly;
    _editorController = nextController;
    _bindEditorDocChanges();

    _safeSetState(() {
      _selectedNodeId = node.id;
      _activeImageOffset = null;
      _imageCropMode = false;
      _imageInteractionMode = false;
      _suppressDirty = true;
      _titleCtrl.text = resolvedTitle;
      _useSectionNumbering = resolvedUseSectionNumbering;
      _attachments = List<Map<String, dynamic>>.from(resolvedAttachments);
      _currentNodeDirty = loadedFromDraft;
      _hasUnsavedChanges = loadedFromDraft || _pendingNodeDrafts.isNotEmpty;
      _saveMessage = _hasUnsavedChanges ? 'Unsaved changes' : 'Saved';
      _expandedNodeIds.add(node.parentId);
      _suppressDirty = false;
    });
    _publishSaveViewState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
      _requestEditorFocusIfEditable();
    });
  }

  void _bindEditorDocChanges() {
    _docChangeSub?.cancel();
    _docChangeSub = _editorController.document.changes.listen((_) {
      if (_suppressDirty) return;
      _markDirtyAndSchedule();
    });
  }

  void _onMetaChanged() {
    if (_suppressDirty) return;
    _markDirtyAndSchedule();
  }

  void _scheduleAutosaveDebounced() {
    _autosaveTimer?.cancel();
    if (!_autoSaveEnabled || !_currentNodeDirty) return;
    if (_isTableCellEditing) return;
    _autosaveTimer = Timer(
      _autosaveDebounce,
      () => _saveNodeNow(source: 'autosave'),
    );
  }

  void _markDirtyAndSchedule() {
    if (_selectedNode == null) return;
    _editVersion += 1;
    _currentNodeDirty = true;
    final shouldRefreshStatus =
        !_hasUnsavedChanges || _saveMessage == 'Saved' || _saveMessage == '';
    _hasUnsavedChanges = true;
    if (shouldRefreshStatus) {
      _saveMessage = 'Unsaved changes';
      _publishSaveViewState();
    }
    _scheduleAutosaveDebounced();
  }

  bool _shouldPromptSaveNote(String source) {
    return source == 'manual' ||
        source == 'back' ||
        source == 'view_mode' ||
        source == 'guard';
  }

  Future<_SaveNotePromptResult?> _promptSaveNoteOptional() async {
    final controller = TextEditingController(text: _lastSaveNote);
    final result = await showDialog<_SaveNotePromptResult>(
      context: context,
      builder: (context) {
        return _buildEditorStyledDialog(
          context: context,
          icon: Icons.save_rounded,
          title: 'Save changes',
          width: 500,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                decoration: _editorDialogInputDecoration(
                  label: 'Update note (optional)',
                  hintText: 'Add a short update note',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: _editorModalSecondaryButtonStyle(),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  context,
                  _SaveNotePromptResult(note: controller.text.trim()),
                );
              },
              style: _editorModalPrimaryButtonStyle(),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _discardCurrentDrafts() async {
    _pendingNodeDrafts.clear();
    _currentNodeDirty = false;
    final selected = _selectedNode;
    if (selected != null) {
      await _loadNodeToEditor(selected);
      return;
    }
    _safeSetState(() {
      _hasUnsavedChanges = false;
      _saveMessage = 'Saved';
    });
    _publishSaveViewState();
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasAnyUnsavedDrafts) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _buildEditorStyledDialog(
          context: context,
          icon: Icons.delete_outline_rounded,
          title: 'Discard unsaved changes?',
          width: 460,
          body: const Text(
            'This will remove all changes since your last save.',
            style: TextStyle(
              color: _text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          actions: [
            TextButton(
              style: _editorModalSecondaryButtonStyle(),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              style: _editorModalPrimaryButtonStyle(
                backgroundColor: const Color(0xFFC62828),
              ),
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text('Discard changes'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _confirmAndDiscardDraft() async {
    final confirmed = await _confirmDiscardChanges();
    if (!confirmed || !mounted) return;
    await _discardCurrentDrafts();
  }

  Future<void> _saveNodeNow({String source = 'implicit'}) async {
    if (_isSaving) {
      final inFlight = _saveInFlight;
      if (inFlight != null) {
        await inFlight;
      }
      if (!_currentNodeDirty) return;
    }
    if (!_currentNodeDirty) return;
    final selected = _selectedNode;
    if (selected == null) return;
    String note = '';
    if (_shouldPromptSaveNote(source)) {
      final noteResult = await _promptSaveNoteOptional();
      if (noteResult == null) return;
      note = noteResult.note;
      _lastSaveNote = note;
    }
    _flushPendingTablePayloads();
    _autosaveTimer?.cancel();
    final saveVersion = _editVersion;
    final contentJson = jsonEncode(
      _editorController.document.toDelta().toJson(),
    );
    final payload = <String, dynamic>{
      'title': _titleCtrl.text.trim().isEmpty
          ? '(Untitled node)'
          : _titleCtrl.text.trim(),
      'useSectionNumbering': _useSectionNumbering,
      'versionId': _handbookId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    batch.set(
      _db.collection(_colHbSection).doc(selected.id),
      payload,
      SetOptions(merge: true),
    );
    batch.set(_db.collection(_colHbContents).doc(selected.id), {
      'sectionId': selected.id,
      'versionId': _handbookId,
      'content': contentJson,
      'attachments': _attachments,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final saveFuture = batch.commit();
    _saveInFlight = saveFuture;
    _isSaving = true;
    _saveMessage = 'Saving...';
    _publishSaveViewState();
    try {
      await saveFuture;
      if (!mounted) return;
      final stillCurrentNode = _selectedNodeId == selected.id;
      final changedDuringSave = _editVersion != saveVersion;
      final logAction = source == 'autosave'
          ? 'autosave_save'
          : source == 'implicit'
          ? 'implicit_save'
          : 'save';
      try {
        await _appendHandbookEditLog(
          action: logAction,
          sectionId: selected.id,
          sectionTitle: payload['title']?.toString() ?? '',
          note: note,
        );
      } catch (_) {}
      if (!stillCurrentNode || changedDuringSave) {
        _currentNodeDirty = true;
        _hasUnsavedChanges = true;
        _saveMessage = 'Unsaved changes';
      } else {
        _contentCacheByNodeId[selected.id] = _CachedNodeContent(
          contentJson: contentJson,
          attachments: List<Map<String, dynamic>>.from(_attachments),
        );
        _currentNodeDirty = false;
        _pendingNodeDrafts.remove(selected.id);
        _hasUnsavedChanges = _pendingNodeDrafts.isNotEmpty;
        _saveMessage = _hasUnsavedChanges ? 'Unsaved changes' : 'Saved';
      }
      _publishSaveViewState();
    } catch (e) {
      if (!mounted) return;
      _saveMessage = 'Save failed';
      _publishSaveViewState();
      AppScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      _saveInFlight = null;
      if (mounted) {
        _isSaving = false;
        _publishSaveViewState();
        _scheduleAutosaveDebounced();
      }
    }
  }

  Future<void> _appendHandbookEditLog({
    required String action,
    required String sectionId,
    required String sectionTitle,
    String note = '',
  }) async {
    final versionId = (_handbookId ?? '').trim();
    if (versionId.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    await _db
        .collection(_colHbVersion)
        .doc(versionId)
        .collection('edit_logs')
        .add({
          'action': action,
          'sectionId': sectionId,
          'sectionTitle': sectionTitle,
          'note': note.trim(),
          'actorUid': user?.uid ?? '',
          'actorEmail': user?.email ?? '',
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _commitOpsInChunks(
    List<void Function(WriteBatch batch)> operations,
  ) async {
    const chunkSize = 380;
    for (var i = 0; i < operations.length; i += chunkSize) {
      final batch = _db.batch();
      final end = math.min(i + chunkSize, operations.length);
      for (var j = i; j < end; j++) {
        operations[j](batch);
      }
      await batch.commit();
    }
  }

  bool get _hasAnyUnsavedDrafts =>
      _currentNodeDirty || _pendingNodeDrafts.isNotEmpty;

  void _refreshUnsavedIndicator() {
    _hasUnsavedChanges = _hasAnyUnsavedDrafts;
    if (_isSaving) return;
    _saveMessage = _hasUnsavedChanges ? 'Unsaved changes' : 'Saved';
    _publishSaveViewState();
  }

  void _stashCurrentNodeDraft() {
    final selected = _selectedNode;
    if (selected == null) return;
    _flushPendingTablePayloads();
    final title = _titleCtrl.text.trim().isEmpty
        ? '(Untitled node)'
        : _titleCtrl.text.trim();
    final contentOps = _editorController.document.toDelta().toJson();
    _pendingNodeDrafts[selected.id] = _PendingNodeDraft(
      title: title,
      useSectionNumbering: _useSectionNumbering,
      contentOps: contentOps,
      attachments: List<Map<String, dynamic>>.from(_attachments),
    );
    _currentNodeDirty = false;
    _refreshUnsavedIndicator();
  }

  Future<bool> _saveAllPendingDrafts({String source = 'manual'}) async {
    if (_currentNodeDirty) {
      _stashCurrentNodeDraft();
    }
    if (_pendingNodeDrafts.isEmpty) {
      _currentNodeDirty = false;
      _refreshUnsavedIndicator();
      return true;
    }
    String note = '';
    if (_shouldPromptSaveNote(source)) {
      final noteResult = await _promptSaveNoteOptional();
      if (noteResult == null) return false;
      note = noteResult.note;
      _lastSaveNote = note;
    }
    final versionId = (_handbookId ?? '').trim();
    if (versionId.isEmpty) return false;

    _isSaving = true;
    _saveMessage = 'Saving...';
    _publishSaveViewState();
    try {
      final existingNodeIds = _nodes.map((node) => node.id).toSet();
      final ops = <void Function(WriteBatch batch)>[];
      _pendingNodeDrafts.forEach((nodeId, draft) {
        if (!existingNodeIds.contains(nodeId)) return;
        ops.add((batch) {
          batch.set(_db.collection(_colHbSection).doc(nodeId), {
            'title': draft.title,
            'useSectionNumbering': draft.useSectionNumbering,
            'versionId': versionId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          batch.set(_db.collection(_colHbContents).doc(nodeId), {
            'sectionId': nodeId,
            'versionId': versionId,
            'content': jsonEncode(draft.contentOps),
            'attachments': draft.attachments,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        });
      });
      if (ops.isNotEmpty) {
        await _commitOpsInChunks(ops);
      }
      _pendingNodeDrafts.forEach((nodeId, draft) {
        if (!existingNodeIds.contains(nodeId)) return;
        _contentCacheByNodeId[nodeId] = _CachedNodeContent(
          contentJson: jsonEncode(draft.contentOps),
          attachments: List<Map<String, dynamic>>.from(draft.attachments),
        );
      });
      try {
        await _appendHandbookEditLog(
          action: 'bulk_save_drafts_$source',
          sectionId: _selectedNodeId ?? '',
          sectionTitle:
              'Saved ${_pendingNodeDrafts.length} draft entr${_pendingNodeDrafts.length == 1 ? 'y' : 'ies'}',
          note: note,
        );
      } catch (_) {}
      _pendingNodeDrafts.clear();
      _currentNodeDirty = false;
      _hasUnsavedChanges = false;
      _saveMessage = 'Saved';
      _publishSaveViewState();
      return true;
    } catch (e) {
      _saveMessage = 'Save failed';
      _publishSaveViewState();
      _showSnack('Save failed: $e', isError: true);
      return false;
    } finally {
      _isSaving = false;
      _publishSaveViewState();
    }
  }

  void _selectAllInEditor() {
    final docLength = _editorController.document.length;
    if (docLength <= 0) return;
    _editorFocusNode.requestFocus();
    _editorController.updateSelection(
      TextSelection(baseOffset: 0, extentOffset: docLength - 1),
      quill.ChangeSource.local,
    );
  }

  bool get _canEditDocumentActions =>
      _selectedNode != null && !_isEditorReadOnly && !_isTableCellEditing;

  void _requestEditorFocusIfEditable() {
    if (!mounted) return;
    if (_selectedNode == null || _isEditorReadOnly || _isTableCellEditing) {
      return;
    }
    _editorController.skipRequestKeyboard = false;
    _editorFocusNode.requestFocus();
  }

  void _syncEditorReadOnlyState() {
    _editorController.readOnly = _isEditorReadOnly;
  }

  Future<_UnsavedExitAction> _askUnsavedChangesAction({
    bool leavingPage = true,
  }) async {
    final result = await showDialog<_UnsavedExitAction>(
      context: context,
      builder: (context) {
        final discardLabel = leavingPage
            ? 'Discard and leave'
            : 'Discard changes';
        final saveLabel = leavingPage ? 'Save and leave' : 'Save';
        final bodyMessage = leavingPage
            ? 'Do you want to save before leaving this page?'
            : 'Do you want to save before leaving edit mode?';
        return _buildEditorStyledDialog(
          context: context,
          icon: Icons.warning_amber_rounded,
          title: 'You have unsaved changes',
          width: 460,
          body: Text(
            bodyMessage,
            style: TextStyle(
              color: _text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          actions: [
            TextButton(
              style: _editorModalSecondaryButtonStyle(),
              onPressed: () =>
                  Navigator.pop(context, _UnsavedExitAction.cancel),
              child: const Text('Continue editing'),
            ),
            TextButton(
              style: _editorModalSecondaryButtonStyle().copyWith(
                foregroundColor: WidgetStatePropertyAll(
                  const Color(0xFFC62828),
                ),
              ),
              onPressed: () =>
                  Navigator.pop(context, _UnsavedExitAction.discard),
              child: Text(discardLabel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _UnsavedExitAction.save),
              style: _editorModalPrimaryButtonStyle(),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text(saveLabel),
            ),
          ],
        );
      },
    );
    return result ?? _UnsavedExitAction.cancel;
  }

  Future<bool> _setEditingEnabled(bool enabled) async {
    if (_editingEnabled == enabled) return true;
    if (!enabled && _hasAnyUnsavedDrafts) {
      final action = await _askUnsavedChangesAction(leavingPage: false);
      if (action == _UnsavedExitAction.cancel) return false;
      if (action == _UnsavedExitAction.save) {
        final saved = await _saveAllPendingDrafts(source: 'view_mode');
        if (!saved) return false;
      } else if (action == _UnsavedExitAction.discard) {
        await _discardCurrentDrafts();
      }
      if (!mounted) return false;
    }
    setState(() {
      _editingEnabled = enabled;
      _syncEditorReadOnlyState();
    });
    if (enabled) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _requestEditorFocusIfEditable(),
      );
    }
    return true;
  }

  int? _parseHeaderLevelValue(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  bool _isSelectionOnBlankLine(TextSelection selection) {
    if (!selection.isValid) return false;
    final plainText = _editorController.document.toPlainText();
    if (plainText.isEmpty) return true;
    final caret = selection.baseOffset.clamp(0, plainText.length);
    final start = caret <= 0 ? 0 : plainText.lastIndexOf('\n', caret - 1) + 1;
    final nextBreak = plainText.indexOf('\n', caret);
    final end = nextBreak < 0 ? plainText.length : nextBreak;
    final line = plainText.substring(start, end).trim();
    return line.isEmpty;
  }

  KeyEventResult _handleEditorKeyPress(KeyEvent event) {
    if (_isTableCellEditing) {
      // Never consume keys here while editing table cells.
      return KeyEventResult.ignored;
    }
    if (_imageInteractionMode && event is KeyDownEvent) {
      final key = event.logicalKey;
      final isTypingCharacter =
          event.character != null &&
          event.character!.isNotEmpty &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isAltPressed;
      final isNavigationOrEditKey =
          key == LogicalKeyboardKey.backspace ||
          key == LogicalKeyboardKey.delete ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.tab;
      if (isTypingCharacter || isNavigationOrEditKey) {
        final deletedImageOffset = _deleteSelectedImage();
        if (deletedImageOffset == null) {
          _setImageInteractionMode(false);
          return KeyEventResult.ignored;
        }
        if (!_isEditorReadOnly && _selectedNode != null) {
          _editorController.skipRequestKeyboard = false;
          _editorFocusNode.requestFocus();
        }
        if (key == LogicalKeyboardKey.backspace ||
            key == LogicalKeyboardKey.delete) {
          // Delete key should only remove the selected image on this press.
          return KeyEventResult.handled;
        }
        // For typing/enter/tab: image is removed, then allow normal key behavior.
        return KeyEventResult.ignored;
      }
    }
    if (!_imageInteractionMode) {
      final selection = _editorController.selection;
      if (selection.isValid &&
          selection.isCollapsed &&
          _isImageOffset(selection.baseOffset)) {
        final key = event.logicalKey;
        final isTypingCharacter =
            event is KeyDownEvent &&
            event.character != null &&
            event.character!.isNotEmpty &&
            !HardwareKeyboard.instance.isControlPressed &&
            !HardwareKeyboard.instance.isMetaPressed &&
            !HardwareKeyboard.instance.isAltPressed;
        final isDestructiveKey =
            key == LogicalKeyboardKey.backspace ||
            key == LogicalKeyboardKey.delete;
        if (isTypingCharacter && !isDestructiveKey) {
          final maxOffset = math.max(0, _editorController.document.length - 1);
          final safeOffset = math.min(maxOffset, selection.baseOffset + 1);
          _editorController.updateSelection(
            TextSelection.collapsed(offset: safeOffset),
            quill.ChangeSource.local,
          );
        }
      }
    }
    if (_canEditDocumentActions &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      final selection = _editorController.selection;
      if (selection.isValid && selection.isCollapsed) {
        final attrs = _editorController.getSelectionStyle().attributes;
        final headerLevel = _parseHeaderLevelValue(
          attrs[quill.Attribute.header.key]?.value,
        );
        if ((headerLevel == 1 || headerLevel == 2) &&
            !_isSelectionOnBlankLine(selection)) {
          final caret = selection.baseOffset;
          _editorController.replaceText(
            caret,
            0,
            '\n',
            TextSelection.collapsed(offset: caret + 1),
          );
          _editorController.formatSelection(
            quill.Attribute.fromKeyValue(
              quill.Attribute.header.key,
              headerLevel,
            ),
          );
          return KeyEventResult.handled;
        }
      }
    }
    return _handleEditorBackspace(event);
  }

  void _toggleInlineFormat(_InlineFormatType type) {
    if (_hasActiveTableStyleTarget) {
      switch (type) {
        case _InlineFormatType.bold:
          _applyTableCellStyle(bold: !_activeTableSelection.bold);
          return;
        case _InlineFormatType.italic:
          _applyTableCellStyle(italic: !_activeTableSelection.italic);
          return;
        case _InlineFormatType.underline:
        case _InlineFormatType.strike:
          return;
      }
    }
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    final attribute = switch (type) {
      _InlineFormatType.bold => quill.Attribute.bold,
      _InlineFormatType.italic => quill.Attribute.italic,
      _InlineFormatType.underline => quill.Attribute.underline,
      _InlineFormatType.strike => quill.Attribute.strikeThrough,
    };
    final active = _editorController.getSelectionStyle().attributes.containsKey(
      attribute.key,
    );
    _editorController.formatSelection(
      active ? quill.Attribute.clone(attribute, null) : attribute,
    );
  }

  void _toggleListFormat(_ListFormatType type) {
    if (_hasActiveTableStyleTarget) return;
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    final attribute = switch (type) {
      _ListFormatType.bullet => quill.Attribute.ul,
      _ListFormatType.numbered => quill.Attribute.ol,
      _ListFormatType.check => quill.Attribute.checked,
    };
    final currentList = _editorController
        .getSelectionStyle()
        .attributes[quill.Attribute.list.key];
    final isSameList = currentList?.value == attribute.value;
    _editorController.formatSelection(
      isSameList ? quill.Attribute.clone(attribute, null) : attribute,
    );
  }

  void _indentSelection({required bool increase}) {
    if (_hasActiveTableStyleTarget) return;
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    if (!increase && _tryRemoveTabCharacterNearCaret()) {
      return;
    }
    _editorController.indentSelection(increase);
  }

  bool _tryRemoveTabCharacterNearCaret() {
    final selection = _editorController.selection;
    if (!selection.isCollapsed || selection.start <= 0) return false;
    final plainText = _editorController.document.toPlainText();
    final caret = selection.start;
    if (caret > plainText.length) return false;

    // If the previous character is a literal tab, remove one tab stop.
    if (plainText[caret - 1] == '\t') {
      _editorController.replaceText(
        caret - 1,
        1,
        '',
        TextSelection.collapsed(offset: caret - 1),
      );
      return true;
    }

    // If cursor is at start of line and the line starts with a tab, remove it.
    final lineStart = plainText.lastIndexOf('\n', caret - 1) + 1;
    if (lineStart < plainText.length && plainText[lineStart] == '\t') {
      _editorController.replaceText(
        lineStart,
        1,
        '',
        TextSelection.collapsed(offset: lineStart),
      );
      return true;
    }
    return false;
  }

  KeyEventResult _handleEditorBackspace(KeyEvent event) {
    if (!_canEditDocumentActions) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }

    final selection = _editorController.selection;
    if (!selection.isCollapsed || selection.baseOffset <= 0) {
      return KeyEventResult.ignored;
    }

    final caret = selection.baseOffset;
    final imageAtCaret = _resolveImageOffset(caret);
    if (imageAtCaret != null && _isImageOffset(imageAtCaret)) {
      _onImageOffsetSelected(imageAtCaret);
      return KeyEventResult.handled;
    }
    final imageBeforeCaret = _resolveImageOffset(caret - 1);
    if (imageBeforeCaret != null &&
        _isImageOffset(imageBeforeCaret) &&
        caret > imageBeforeCaret) {
      _onImageOffsetSelected(imageBeforeCaret);
      return KeyEventResult.handled;
    }

    final plainText = _editorController.document.toPlainText();
    if (caret > plainText.length) return KeyEventResult.ignored;
    final lineStart = plainText.lastIndexOf('\n', caret - 1) + 1;
    if (caret != lineStart) return KeyEventResult.ignored;

    final attrs = _editorController.getSelectionStyle().attributes;
    final indentAttr = attrs[quill.Attribute.indent.key]?.value;
    final indentLevel = switch (indentAttr) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
    final hasIndent = attrs.containsKey(quill.Attribute.indent.key);
    final hasList = attrs.containsKey(quill.Attribute.list.key);
    if (hasList) {
      // Word/Docs-like behavior: backspace at the start of a list item exits
      // list formatting first (or decreases indent when nested).
      if (hasIndent && indentLevel > 0) {
        _indentSelection(increase: false);
      } else {
        _editorFocusNode.requestFocus();
        _editorController.formatSelection(
          quill.Attribute.fromKeyValue(quill.Attribute.list.key, null),
        );
        if (hasIndent) {
          _editorController.formatSelection(
            quill.Attribute.fromKeyValue(quill.Attribute.indent.key, null),
          );
        }
      }
      return KeyEventResult.handled;
    }

    if (hasIndent) {
      _indentSelection(increase: false);
      return KeyEventResult.handled;
    }

    if (_tryRemoveTabCharacterNearCaret()) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _undoEditorChange() {
    if (!_canEditDocumentActions || !_editorController.hasUndo) return;
    _editorFocusNode.requestFocus();
    _editorController.undo();
  }

  void _redoEditorChange() {
    if (!_canEditDocumentActions || !_editorController.hasRedo) return;
    _editorFocusNode.requestFocus();
    _editorController.redo();
  }

  void _insertLinkFromShortcut() {
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    unawaited(_promptInsertLink());
  }

  bool _isCodeBlockActive() =>
      _selectionAttributeValue(quill.Attribute.codeBlock.key) == true;

  void _toggleCodeBlock() {
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    final nextValue = _isCodeBlockActive() ? null : true;
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue(quill.Attribute.codeBlock.key, nextValue),
    );
  }

  dynamic _selectionAttributeValue(String key) {
    return _editorController.getSelectionStyle().attributes[key]?.value;
  }

  bool get _hasActiveTableStyleTarget {
    final activeOffset = _activeTableOffset;
    if (!_isTableCellEditing || activeOffset == null) return false;
    return _tableStyleSetters.containsKey(activeOffset) &&
        _activeTableSelection.hasActiveCell;
  }

  void _applyTableCellStyle({
    bool? bold,
    bool? italic,
    String? align,
    String? fontFamilyKey,
    int? fontSizePoint,
  }) {
    final activeOffset = _activeTableOffset;
    if (!_hasActiveTableStyleTarget || activeOffset == null) return;
    final setter = _tableStyleSetters[activeOffset];
    if (setter == null) return;
    setter(
      bold: bold,
      italic: italic,
      align: align,
      fontFamilyKey: fontFamilyKey,
      fontSizePoint: fontSizePoint,
    );
  }

  bool _isInlineActive(_InlineFormatType type) {
    if (_hasActiveTableStyleTarget) {
      return switch (type) {
        _InlineFormatType.bold => _activeTableSelection.bold,
        _InlineFormatType.italic => _activeTableSelection.italic,
        _InlineFormatType.underline => false,
        _InlineFormatType.strike => false,
      };
    }
    final key = switch (type) {
      _InlineFormatType.bold => quill.Attribute.bold.key,
      _InlineFormatType.italic => quill.Attribute.italic.key,
      _InlineFormatType.underline => quill.Attribute.underline.key,
      _InlineFormatType.strike => quill.Attribute.strikeThrough.key,
    };
    return _editorController.getSelectionStyle().attributes.containsKey(key);
  }

  bool _isListActive(_ListFormatType type) {
    final current = _selectionAttributeValue(quill.Attribute.list.key);
    final expected = switch (type) {
      _ListFormatType.bullet => quill.Attribute.ul.value,
      _ListFormatType.numbered => quill.Attribute.ol.value,
      _ListFormatType.check => quill.Attribute.checked.value,
    };
    return current == expected;
  }

  String _currentAlignment() {
    if (_hasActiveTableStyleTarget) {
      return _activeTableSelection.align;
    }
    final raw = _selectionAttributeValue('align')?.toString() ?? '';
    return switch (raw) {
      'center' => 'center',
      'right' => 'right',
      'justify' => 'justify',
      _ => 'left',
    };
  }

  String _currentFontSize() {
    if (_hasActiveTableStyleTarget) {
      return switch (_activeTableSelection.fontSizePoint) {
        <= 10 => 'small',
        >= 24 => 'huge',
        >= 18 => 'large',
        _ => 'normal',
      };
    }
    final raw = _selectionAttributeValue('size')?.toString() ?? '';
    return switch (raw) {
      'small' => 'small',
      'large' => 'large',
      'huge' => 'huge',
      _ => 'normal',
    };
  }

  int _currentFontSizePoint() {
    if (_hasActiveTableStyleTarget) {
      return _activeTableSelection.fontSizePoint.clamp(10, 32);
    }
    return switch (_currentFontSize()) {
      'small' => 10,
      'large' => 18,
      'huge' => 24,
      _ => 12,
    };
  }

  String _currentFontFamilyKey() {
    if (_hasActiveTableStyleTarget) {
      return _activeTableSelection.fontFamilyKey;
    }
    final raw = _selectionAttributeValue('font')?.toString().trim() ?? '';
    return switch (raw) {
      'serif' => 'serif',
      'monospace' => 'monospace',
      'sans-serif' => 'sans-serif',
      _ => 'default',
    };
  }

  String? _currentTextColorHex() {
    final raw = _selectionAttributeValue('color')?.toString().trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  String? _currentBackgroundColorHex() {
    final raw = _selectionAttributeValue('background')?.toString().trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  Color _hexToColor(String? raw, {required Color fallback}) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return fallback;
    var hex = value.startsWith('#') ? value.substring(1) : value;
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return fallback;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
  }

  String? _normalizeHexColor(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    var hex = value.startsWith('#') ? value.substring(1) : value;
    if (hex.length == 8) {
      hex = hex.substring(2);
    }
    if (hex.length != 6) return null;
    return '#${hex.toUpperCase()}';
  }

  Widget _toolPopupIcon({required Widget icon, required String tooltip}) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }

  Widget _toolbarDropdownField<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    required double width,
  }) {
    return Container(
      width: width,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          icon: const Icon(Icons.arrow_drop_down_rounded, size: 18),
          style: const TextStyle(
            color: _text,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _colorPaletteCell(
    BuildContext menuContext, {
    required String colorHex,
    required bool selected,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(menuContext, colorHex),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: _hexToColor(colorHex, fallback: Colors.white),
          border: Border.all(
            color: selected ? _text : Colors.black.withValues(alpha: 0.35),
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildColorPopupEntries({
    required bool forBackground,
  }) {
    final current = _normalizeHexColor(
      forBackground ? _currentBackgroundColorHex() : _currentTextColorHex(),
    );
    return [
      PopupMenuItem<String>(
        enabled: false,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Builder(
          builder: (menuContext) => SizedBox(
            width: 250,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Standard Colors',
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _standardColorPalette
                      .map(
                        (hex) => _colorPaletteCell(
                          menuContext,
                          colorHex: hex,
                          selected: current == hex,
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _extendedColorPalette
                      .map(
                        (hex) => _colorPaletteCell(
                          menuContext,
                          colorHex: hex,
                          selected: current == hex,
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(menuContext, 'none'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('No Color'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  int? _currentHeaderLevel() {
    final raw = _selectionAttributeValue('header');
    return _parseHeaderLevelValue(raw);
  }

  int? _deleteSelectedImage() {
    final selection = _editorController.selection;
    final imageOffset =
        _activeImageOffset ??
        (selection.isValid ? _resolveImageOffset(selection.baseOffset) : null);
    if (imageOffset == null || !_isImageOffset(imageOffset)) return null;
    try {
      _editorController.replaceText(
        imageOffset,
        1,
        '',
        TextSelection.collapsed(offset: imageOffset),
      );
      setState(() {
        _imageInteractionMode = false;
        _imageCropMode = false;
        _activeImageOffset = null;
      });
      return imageOffset;
    } catch (_) {
      return null;
    }
  }

  bool _isQuoteActive() => _selectionAttributeValue('blockquote') == true;

  void _setAlignment(String alignment) {
    if (_hasActiveTableStyleTarget) {
      final normalized = switch (alignment) {
        'center' => 'center',
        'right' => 'right',
        'justify' => 'justify',
        _ => 'left',
      };
      _applyTableCellStyle(align: normalized);
      return;
    }
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    final normalized = switch (alignment) {
      'center' => 'center',
      'right' => 'right',
      'justify' => 'justify',
      _ => 'left',
    };
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue(
        'align',
        normalized == 'left' ? null : normalized,
      ),
    );
  }

  void _setFontSize(String size) {
    if (_hasActiveTableStyleTarget) {
      final points = switch (size) {
        'small' => 10,
        'large' => 18,
        'huge' => 24,
        _ => 12,
      };
      _applyTableCellStyle(fontSizePoint: points);
      return;
    }
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    final normalized = switch (size) {
      'small' => 'small',
      'large' => 'large',
      'huge' => 'huge',
      _ => 'normal',
    };
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue(
        'size',
        normalized == 'normal' ? null : normalized,
      ),
    );
  }

  void _setFontSizePoint(int points) {
    if (_hasActiveTableStyleTarget) {
      _applyTableCellStyle(fontSizePoint: points.clamp(10, 32));
      return;
    }
    final value = switch (points) {
      <= 10 => 'small',
      >= 24 => 'huge',
      >= 18 => 'large',
      _ => 'normal',
    };
    _setFontSize(value);
  }

  void _stepFontSize({required bool increase}) {
    const options = <int>[10, 12, 14, 18, 24];
    final current = _currentFontSizePoint();
    final idx = options.indexOf(current);
    final safeIndex = idx < 0 ? 1 : idx;
    final next = increase
        ? options[math.min(options.length - 1, safeIndex + 1)]
        : options[math.max(0, safeIndex - 1)];
    _setFontSizePoint(next);
  }

  void _setFontFamily(String family) {
    if (_hasActiveTableStyleTarget) {
      _applyTableCellStyle(fontFamilyKey: family);
      return;
    }
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue('font', family == 'default' ? null : family),
    );
  }

  String _toSentenceCase(String input) {
    if (input.isEmpty) return input;
    final lower = input.toLowerCase();
    final sb = StringBuffer();
    var capitalizeNext = true;
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      final isLetter = RegExp(r'[a-z]').hasMatch(ch);
      if (capitalizeNext && isLetter) {
        sb.write(ch.toUpperCase());
        capitalizeNext = false;
      } else {
        sb.write(ch);
      }
      if (ch == '.' || ch == '!' || ch == '?') {
        capitalizeNext = true;
      }
    }
    return sb.toString();
  }

  String _toTitleCase(String input) {
    return input.replaceAllMapped(RegExp(r'[A-Za-z]+'), (match) {
      final word = match.group(0)!;
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    });
  }

  String _toggleCase(String input) {
    final sb = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (RegExp(r'[a-z]').hasMatch(ch)) {
        sb.write(ch.toUpperCase());
      } else if (RegExp(r'[A-Z]').hasMatch(ch)) {
        sb.write(ch.toLowerCase());
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }

  void _applyCaseTransform(_CaseTransform mode) {
    if (!_canEditDocumentActions) return;
    final selection = _editorController.selection;
    if (!selection.isValid || selection.isCollapsed) {
      _showSnack('Select text first to change case.', isError: true);
      return;
    }
    var start = selection.start;
    var end = selection.end;
    if (start > end) {
      final tmp = start;
      start = end;
      end = tmp;
    }
    final plain = _editorController.document.toPlainText();
    if (start < 0 || end > plain.length || start >= end) return;
    final original = plain.substring(start, end);
    final transformed = switch (mode) {
      _CaseTransform.sentence => _toSentenceCase(original),
      _CaseTransform.lowercase => original.toLowerCase(),
      _CaseTransform.uppercase => original.toUpperCase(),
      _CaseTransform.capitalize => _toTitleCase(original),
      _CaseTransform.toggle => _toggleCase(original),
    };
    if (transformed == original) return;
    _editorController.replaceText(
      start,
      end - start,
      transformed,
      TextSelection(
        baseOffset: start,
        extentOffset: start + transformed.length,
      ),
    );
  }

  void _setTextColor(String value) {
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue('color', value == 'none' ? null : value),
    );
  }

  void _setBackgroundColor(String value) {
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue(
        'background',
        value == 'none' ? null : value,
      ),
    );
  }

  void _applyStylePreset(String preset) {
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    switch (preset) {
      case 'h1':
        _editorController.formatSelection(
          quill.Attribute.fromKeyValue('blockquote', null),
        );
        _editorController.formatSelection(
          quill.Attribute.fromKeyValue('header', 1),
        );
        break;
      case 'h2':
        _editorController.formatSelection(
          quill.Attribute.fromKeyValue('blockquote', null),
        );
        _editorController.formatSelection(
          quill.Attribute.fromKeyValue('header', 2),
        );
        break;
      case 'quote':
        final next = _isQuoteActive() ? null : true;
        _editorController.formatSelection(
          quill.Attribute.fromKeyValue('header', null),
        );
        _editorController.formatSelection(
          quill.Attribute.fromKeyValue('blockquote', next),
        );
        break;
      default:
        _editorController.formatSelection(
          quill.Attribute.fromKeyValue('header', null),
        );
        _editorController.formatSelection(
          quill.Attribute.fromKeyValue('blockquote', null),
        );
        break;
    }
  }

  void _clearSelectionFormatting() {
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    _editorController.formatSelection(
      quill.Attribute.clone(quill.Attribute.bold, null),
    );
    _editorController.formatSelection(
      quill.Attribute.clone(quill.Attribute.italic, null),
    );
    _editorController.formatSelection(
      quill.Attribute.clone(quill.Attribute.underline, null),
    );
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue('size', null),
    );
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue('header', null),
    );
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue('list', null),
    );
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue('indent', null),
    );
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue('align', null),
    );
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue('blockquote', null),
    );
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue('color', null),
    );
    _editorController.formatSelection(
      quill.Attribute.fromKeyValue('background', null),
    );
  }

  Widget _groupedToolIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required bool active,
    Key? widgetKey,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        key: widgetKey,
        width: 30,
        height: 30,
        child: Material(
          color: active ? const Color(0xFFE7F1EA) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: onPressed,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(4),
            child: Center(child: Icon(icon, size: 16, color: _text)),
          ),
        ),
      ),
    );
  }

  Widget _toolbarGroupDivider() => Container(
    width: 1,
    height: 64,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Colors.black.withValues(alpha: 0.16),
  );

  List<Widget> _toolbarRowChildren(List<Widget> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(const SizedBox(width: 2));
      out.add(items[i]);
    }
    return out;
  }

  Widget _toolbarGroupBlock({
    required String label,
    required List<Widget> topRow,
    List<Widget> bottomRow = const [],
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _toolbarRowChildren(topRow),
            ),
          ),
          const SizedBox(height: 2),
          if (bottomRow.isEmpty)
            const SizedBox(height: 28)
          else
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _toolbarRowChildren(bottomRow),
              ),
            ),
          const SizedBox(height: 2),
          Center(
            child: Text(
              label,
              style: const TextStyle(
                color: _text,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editorGroupedHomeToolbar() {
    return ListenableBuilder(
      listenable: _editorController,
      builder: (context, child) {
        final alignment = _currentAlignment();
        final fontSizePt = _currentFontSizePoint();
        final fontFamilyKey = _currentFontFamilyKey();
        final headerLevel = _currentHeaderLevel();
        final quoteActive = _isQuoteActive();
        final textColor = _currentTextColorHex();
        final highlightColor = _currentBackgroundColorHex();
        final selectedImageOffset = _activeImageOffset;
        final hasSelectedImage = selectedImageOffset != null;
        final selectedImageAlignment = hasSelectedImage
            ? _readImageAlignment(selectedImageOffset)
            : 'center';
        final selectedImageDisplayMode = hasSelectedImage
            ? _readImageDisplayMode(selectedImageOffset)
            : 'inline';
        Widget quickRibbonIcon({
          required IconData icon,
          required String tooltip,
          required VoidCallback? onPressed,
          bool active = false,
        }) {
          return Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 30,
              height: 30,
              child: Material(
                color: active
                    ? const Color(0xFFE7F1EA)
                    : (onPressed == null
                          ? const Color(0xFFF6F7F7)
                          : Colors.white),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: onPressed,
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(4),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 16,
                      color: onPressed == null ? _muted : _text,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          color: Colors.white,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 34),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _toolbarGroupBlock(
                              label: 'Quick Access',
                              topRow: [
                                quickRibbonIcon(
                                  icon: Icons.undo_rounded,
                                  tooltip: 'Undo',
                                  onPressed:
                                      _canEditDocumentActions &&
                                          _editorController.hasUndo
                                      ? _undoEditorChange
                                      : null,
                                ),
                                quickRibbonIcon(
                                  icon: Icons.redo_rounded,
                                  tooltip: 'Redo',
                                  onPressed:
                                      _canEditDocumentActions &&
                                          _editorController.hasRedo
                                      ? _redoEditorChange
                                      : null,
                                ),
                                quickRibbonIcon(
                                  icon: Icons.save_outlined,
                                  tooltip: 'Save now',
                                  onPressed:
                                      (_isWorkflowReadOnly ||
                                          !_editingEnabled ||
                                          !_hasUnsavedChanges)
                                      ? null
                                      : () => _saveNodeNow(source: 'manual'),
                                ),
                                quickRibbonIcon(
                                  icon: _autoSaveEnabled
                                      ? Icons.sync_rounded
                                      : Icons.sync_disabled_rounded,
                                  tooltip: _autoSaveEnabled
                                      ? 'Auto Save: On'
                                      : 'Auto Save: Off',
                                  active: _autoSaveEnabled,
                                  onPressed:
                                      (_isWorkflowReadOnly || !_editingEnabled)
                                      ? null
                                      : () {
                                          setState(() {
                                            _autoSaveEnabled =
                                                !_autoSaveEnabled;
                                          });
                                          if (!_autoSaveEnabled) {
                                            _autosaveTimer?.cancel();
                                          } else {
                                            _scheduleAutosaveDebounced();
                                          }
                                          _publishSaveViewState();
                                        },
                                ),
                              ],
                            ),
                            _toolbarGroupDivider(),
                            _toolbarGroupBlock(
                              label: 'Font',
                              topRow: [
                                _toolbarDropdownField<String>(
                                  value: fontFamilyKey,
                                  width: 146,
                                  items: _fontFamilyOptions
                                      .map(
                                        (opt) => DropdownMenuItem<String>(
                                          value: opt.key,
                                          child: Text(
                                            opt.value,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: !_canEditDocumentActions
                                      ? null
                                      : (value) {
                                          if (value == null) return;
                                          _setFontFamily(value);
                                        },
                                ),
                                _toolbarDropdownField<int>(
                                  value: fontSizePt,
                                  width: 54,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 10,
                                      child: Text('10'),
                                    ),
                                    DropdownMenuItem(
                                      value: 12,
                                      child: Text('12'),
                                    ),
                                    DropdownMenuItem(
                                      value: 14,
                                      child: Text('14'),
                                    ),
                                    DropdownMenuItem(
                                      value: 18,
                                      child: Text('18'),
                                    ),
                                    DropdownMenuItem(
                                      value: 24,
                                      child: Text('24'),
                                    ),
                                  ],
                                  onChanged: !_canEditDocumentActions
                                      ? null
                                      : (value) {
                                          if (value == null) return;
                                          _setFontSizePoint(value);
                                        },
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.text_increase_rounded,
                                  tooltip: 'Increase font size',
                                  onPressed: () =>
                                      _stepFontSize(increase: true),
                                  active: false,
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.text_decrease_rounded,
                                  tooltip: 'Decrease font size',
                                  onPressed: () =>
                                      _stepFontSize(increase: false),
                                  active: false,
                                ),
                                PopupMenuButton<_CaseTransform>(
                                  onSelected: _applyCaseTransform,
                                  tooltip: 'Change case',
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: _CaseTransform.sentence,
                                      child: Text('Sentence case.'),
                                    ),
                                    PopupMenuItem(
                                      value: _CaseTransform.lowercase,
                                      child: Text('lowercase'),
                                    ),
                                    PopupMenuItem(
                                      value: _CaseTransform.uppercase,
                                      child: Text('UPPERCASE'),
                                    ),
                                    PopupMenuItem(
                                      value: _CaseTransform.capitalize,
                                      child: Text('Capitalize Each Word'),
                                    ),
                                    PopupMenuItem(
                                      value: _CaseTransform.toggle,
                                      child: Text('tOGGLE cASE'),
                                    ),
                                  ],
                                  child: _toolPopupIcon(
                                    tooltip: 'Change case',
                                    icon: const Text(
                                      'Aa',
                                      style: TextStyle(
                                        color: _text,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: _setTextColor,
                                  itemBuilder: (context) =>
                                      _buildColorPopupEntries(
                                        forBackground: false,
                                      ),
                                  tooltip: 'Text color',
                                  child: _toolPopupIcon(
                                    tooltip: 'Text color',
                                    icon: Icon(
                                      Icons.format_color_text_rounded,
                                      size: 16,
                                      color: textColor == null
                                          ? _text
                                          : _hexToColor(
                                              textColor,
                                              fallback: _text,
                                            ),
                                    ),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: _setBackgroundColor,
                                  itemBuilder: (context) =>
                                      _buildColorPopupEntries(
                                        forBackground: true,
                                      ),
                                  tooltip: 'Highlight color',
                                  child: _toolPopupIcon(
                                    tooltip: 'Highlight color',
                                    icon: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: highlightColor == null
                                            ? const Color(0xFFEFF3F0)
                                            : _hexToColor(
                                                highlightColor,
                                                fallback: const Color(
                                                  0xFFEFF3F0,
                                                ),
                                              ),
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(
                                          color: Colors.black.withValues(
                                            alpha: 0.16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              bottomRow: [
                                _groupedToolIconButton(
                                  icon: Icons.format_bold_rounded,
                                  tooltip: 'Bold',
                                  onPressed: () => _toggleInlineFormat(
                                    _InlineFormatType.bold,
                                  ),
                                  active: _isInlineActive(
                                    _InlineFormatType.bold,
                                  ),
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.format_italic_rounded,
                                  tooltip: 'Italic',
                                  onPressed: () => _toggleInlineFormat(
                                    _InlineFormatType.italic,
                                  ),
                                  active: _isInlineActive(
                                    _InlineFormatType.italic,
                                  ),
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.format_underline_rounded,
                                  tooltip: 'Underline',
                                  onPressed: () => _toggleInlineFormat(
                                    _InlineFormatType.underline,
                                  ),
                                  active: _isInlineActive(
                                    _InlineFormatType.underline,
                                  ),
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.format_strikethrough_rounded,
                                  tooltip: 'Strikethrough',
                                  onPressed: () => _toggleInlineFormat(
                                    _InlineFormatType.strike,
                                  ),
                                  active: _isInlineActive(
                                    _InlineFormatType.strike,
                                  ),
                                ),
                              ],
                            ),
                            _toolbarGroupDivider(),
                            _toolbarGroupBlock(
                              label: 'Paragraph',
                              topRow: [
                                _groupedToolIconButton(
                                  icon: Icons.format_list_bulleted_rounded,
                                  tooltip: 'Bulleted list',
                                  onPressed: () =>
                                      _toggleListFormat(_ListFormatType.bullet),
                                  active: _isListActive(_ListFormatType.bullet),
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.format_list_numbered_rounded,
                                  tooltip: 'Numbered list',
                                  onPressed: () => _toggleListFormat(
                                    _ListFormatType.numbered,
                                  ),
                                  active: _isListActive(
                                    _ListFormatType.numbered,
                                  ),
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.checklist_rounded,
                                  tooltip: 'Checklist',
                                  onPressed: () =>
                                      _toggleListFormat(_ListFormatType.check),
                                  active: _isListActive(_ListFormatType.check),
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.format_indent_decrease_rounded,
                                  tooltip: 'Outdent',
                                  onPressed: () =>
                                      _indentSelection(increase: false),
                                  active: false,
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.format_indent_increase_rounded,
                                  tooltip: 'Indent',
                                  onPressed: () =>
                                      _indentSelection(increase: true),
                                  active: false,
                                ),
                              ],
                              bottomRow: [
                                _groupedToolIconButton(
                                  icon: Icons.format_align_left_rounded,
                                  tooltip: 'Align left',
                                  onPressed: () => _setAlignment('left'),
                                  active: alignment == 'left',
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.format_align_center_rounded,
                                  tooltip: 'Align center',
                                  onPressed: () => _setAlignment('center'),
                                  active: alignment == 'center',
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.format_align_right_rounded,
                                  tooltip: 'Align right',
                                  onPressed: () => _setAlignment('right'),
                                  active: alignment == 'right',
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.format_align_justify_rounded,
                                  tooltip: 'Justify',
                                  onPressed: () => _setAlignment('justify'),
                                  active: alignment == 'justify',
                                ),
                              ],
                            ),
                            _toolbarGroupDivider(),
                            _toolbarGroupBlock(
                              label: 'Styles',
                              topRow: [
                                _groupedToolIconButton(
                                  icon: Icons.text_fields_rounded,
                                  tooltip: 'Normal text',
                                  onPressed: () => _applyStylePreset('normal'),
                                  active: headerLevel == null && !quoteActive,
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.title_rounded,
                                  tooltip: 'Heading 1',
                                  onPressed: () => _applyStylePreset('h1'),
                                  active: headerLevel == 1,
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.subtitles_rounded,
                                  tooltip: 'Heading 2',
                                  onPressed: () => _applyStylePreset('h2'),
                                  active: headerLevel == 2,
                                ),
                              ],
                              bottomRow: [
                                _groupedToolIconButton(
                                  icon: Icons.format_quote_rounded,
                                  tooltip: 'Quote',
                                  onPressed: () => _applyStylePreset('quote'),
                                  active: quoteActive,
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.code_rounded,
                                  tooltip: 'Code block',
                                  onPressed: _toggleCodeBlock,
                                  active: _isCodeBlockActive(),
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.format_clear_rounded,
                                  tooltip: 'Clear formatting',
                                  onPressed: _clearSelectionFormatting,
                                  active: false,
                                ),
                              ],
                            ),
                            _toolbarGroupDivider(),
                            _toolbarGroupBlock(
                              label: 'Insert',
                              topRow: [
                                _groupedToolIconButton(
                                  icon: Icons.table_rows_rounded,
                                  tooltip: 'Insert table',
                                  onPressed: () => _handleInsertAction('table'),
                                  active: false,
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.image_outlined,
                                  tooltip: 'Insert image',
                                  onPressed: () => _handleInsertAction('image'),
                                  active: false,
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.attach_file_rounded,
                                  tooltip: 'Insert attachment',
                                  onPressed: () =>
                                      _handleInsertAction('attachment'),
                                  active: false,
                                ),
                                _groupedToolIconButton(
                                  icon: Icons.link_rounded,
                                  tooltip: 'Insert hyperlink',
                                  onPressed: () => _handleInsertAction('link'),
                                  active: false,
                                ),
                              ],
                            ),
                            if (hasSelectedImage) ...[
                              _toolbarGroupDivider(),
                              _toolbarGroupBlock(
                                label: 'Image',
                                topRow: [
                                  _groupedToolIconButton(
                                    icon: Icons.photo_size_select_large_rounded,
                                    tooltip: 'Image size',
                                    onPressed: () =>
                                        _showImageSizeControlDialog(
                                          selectedImageOffset,
                                        ),
                                    active: false,
                                    widgetKey: _imageSizeButtonKey,
                                  ),
                                  _groupedToolIconButton(
                                    icon: _imageCropMode
                                        ? Icons.crop_free_rounded
                                        : Icons.crop_rounded,
                                    tooltip: _imageCropMode
                                        ? 'Crop mode on'
                                        : 'Crop mode off',
                                    onPressed: () {
                                      setState(() {
                                        _imageCropMode = !_imageCropMode;
                                      });
                                    },
                                    active: _imageCropMode,
                                  ),
                                  _groupedToolIconButton(
                                    icon: Icons.rotate_left_rounded,
                                    tooltip: 'Rotate left',
                                    onPressed: () =>
                                        _rotateImageLeft(selectedImageOffset),
                                    active: false,
                                  ),
                                  _groupedToolIconButton(
                                    icon: Icons.rotate_right_rounded,
                                    tooltip: 'Rotate right',
                                    onPressed: () =>
                                        _rotateImageRight(selectedImageOffset),
                                    active: false,
                                  ),
                                ],
                                bottomRow: [
                                  _groupedToolIconButton(
                                    icon: Icons.format_align_left_rounded,
                                    tooltip: 'Align left',
                                    onPressed: () => _setImageAlignment(
                                      selectedImageOffset,
                                      'left',
                                    ),
                                    active: selectedImageAlignment == 'left',
                                  ),
                                  _groupedToolIconButton(
                                    icon: Icons.format_align_center_rounded,
                                    tooltip: 'Align center',
                                    onPressed: () => _setImageAlignment(
                                      selectedImageOffset,
                                      'center',
                                    ),
                                    active: selectedImageAlignment == 'center',
                                  ),
                                  _groupedToolIconButton(
                                    icon: Icons.format_align_right_rounded,
                                    tooltip: 'Align right',
                                    onPressed: () => _setImageAlignment(
                                      selectedImageOffset,
                                      'right',
                                    ),
                                    active: selectedImageAlignment == 'right',
                                  ),
                                  _groupedToolIconButton(
                                    icon: Icons.view_agenda_rounded,
                                    tooltip: selectedImageDisplayMode == 'full'
                                        ? 'Display mode: full width'
                                        : 'Display mode: inline',
                                    onPressed: () => _setImageDisplayMode(
                                      selectedImageOffset,
                                      selectedImageDisplayMode == 'full'
                                          ? 'inline'
                                          : 'full',
                                    ),
                                    active: selectedImageDisplayMode == 'full',
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: _editorViewOptionsMenuButton(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createNode({required String parentId}) async {
    if (_isEditorReadOnly) {
      _showReadOnlyVersionWarning();
      return;
    }
    final titleCtrl = TextEditingController();
    var useSectionNumbering = true;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return _buildEditorStyledDialog(
              context: context,
              icon: Icons.note_add_rounded,
              title: 'Create Entry',
              subtitle: 'Add a new handbook entry.',
              width: 460,
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: _editorDialogInputDecoration(
                      label: 'Entry title',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _primary.withValues(alpha: 0.16),
                      ),
                    ),
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: useSectionNumbering,
                      onChanged: (value) {
                        setDialogState(() => useSectionNumbering = value);
                      },
                      title: const Text(
                        'Apply section numbering',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Turn off for entries like Annex or Table of Contents.',
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  style: _editorModalSecondaryButtonStyle(),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  style: _editorModalPrimaryButtonStyle(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != true) return;
    final handbookId = _handbookId;
    if (handbookId == null || handbookId.isEmpty) return;

    final title = titleCtrl.text.trim().isEmpty
        ? '(Untitled node)'
        : titleCtrl.text.trim();
    final siblings = _childrenOf(parentId);
    final nextSortOrder = siblings.isEmpty ? 0 : siblings.last.sortOrder + 1;

    final nodeRef = _db.collection(_colHbSection).doc();
    final initialContent = jsonEncode(
      (quill.Document()..insert(0, '\n')).toDelta().toJson(),
    );
    await nodeRef.set({
      'versionId': handbookId,
      'parentId': parentId,
      'title': title,
      'useSectionNumbering': useSectionNumbering,
      'sortOrder': nextSortOrder,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _db.collection(_colHbContents).doc(nodeRef.id).set({
      'sectionId': nodeRef.id,
      'versionId': handbookId,
      'content': initialContent,
      'attachments': const <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      if (parentId.isNotEmpty) _expandedNodeIds.add(parentId);
    });
    await _switchToNode(nodeRef.id, force: true);
  }

  Future<void> _deleteNode(String nodeId) async {
    if (_isEditorReadOnly) {
      _showReadOnlyVersionWarning();
      return;
    }
    final target = _nodeById(nodeId);
    if (target == null) return;
    final descendants = _collectDescendants(nodeId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _buildEditorStyledDialog(
          context: context,
          icon: Icons.delete_outline_rounded,
          title: 'Delete Entry',
          subtitle: 'This action cannot be undone.',
          width: 460,
          body: Text(
            descendants.isEmpty
                ? 'Delete "${target.title}"?'
                : 'Delete "${target.title}" and ${descendants.length} nested entries?',
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          actions: [
            TextButton(
              style: _editorModalSecondaryButtonStyle(),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              style: _editorModalPrimaryButtonStyle(
                backgroundColor: Colors.red.shade700,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final batch = _db.batch();
    batch.delete(_db.collection(_colHbSection).doc(nodeId));
    batch.delete(_db.collection(_colHbContents).doc(nodeId));
    _pendingNodeDrafts.remove(nodeId);
    for (final child in descendants) {
      batch.delete(_db.collection(_colHbSection).doc(child.id));
      batch.delete(_db.collection(_colHbContents).doc(child.id));
      _pendingNodeDrafts.remove(child.id);
    }
    await batch.commit();

    if (!mounted) return;
    if (_selectedNodeId == nodeId) {
      _currentNodeDirty = false;
      setState(() => _selectedNodeId = null);
    }
    _refreshUnsavedIndicator();
  }

  Future<void> _reorderRootNodes(int oldIndex, int newIndex) async {
    if (_isEditorReadOnly) {
      _showReadOnlyVersionWarning();
      return;
    }
    final orderedRoots = _rootNodes();
    if (oldIndex < 0 || oldIndex >= orderedRoots.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= orderedRoots.length) return;
    if (newIndex == oldIndex) return;

    final reordered = [...orderedRoots];
    try {
      final moved = reordered.removeAt(oldIndex);
      reordered.insert(newIndex, moved);
    } on RangeError {
      return;
    }

    final previousNodes = [..._nodes];
    final sortById = <String, int>{
      for (var i = 0; i < reordered.length; i++) reordered[i].id: i,
    };

    _safeSetState(() {
      _nodes = _sortNodes(
        _nodes.map((node) {
          final nextOrder = sortById[node.id];
          if (nextOrder == null) return node;
          return node.copyWith(parentId: '', sortOrder: nextOrder);
        }).toList(),
      );
    });

    final batch = _db.batch();
    for (var i = 0; i < reordered.length; i++) {
      batch.update(_db.collection(_colHbSection).doc(reordered[i].id), {
        'parentId': '',
        'sortOrder': i,
      });
    }
    try {
      await batch.commit();
    } catch (e) {
      if (!mounted) return;
      _safeSetState(() {
        _nodes = previousNodes;
      });
      AppScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reorder entries: $e')));
    }
  }

  List<HandbookNodeDoc> _collectDescendants(String parentId) {
    final result = <HandbookNodeDoc>[];
    void walk(String pid) {
      final children = _childrenOf(pid);
      for (final child in children) {
        result.add(child);
        walk(child.id);
      }
    }

    walk(parentId);
    return result;
  }

  Future<void> _insertTableTemplate() async {
    if (_isEditorReadOnly) {
      _showReadOnlyVersionWarning();
      return;
    }
    var columns = 3;
    var rows = 3;
    final shouldInsert = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return _buildEditorStyledDialog(
              context: context,
              icon: Icons.table_rows_rounded,
              title: 'Insert Table',
              subtitle: 'Choose the initial rows and columns.',
              width: 420,
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: columns,
                    items: List.generate(
                      8,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1} columns'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => columns = value);
                    },
                    decoration: _editorDialogInputDecoration(
                      label: 'Columns',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: rows,
                    items: List.generate(
                      12,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1} rows'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => rows = value);
                    },
                    decoration: _editorDialogInputDecoration(
                      label: 'Rows',
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  style: _editorModalSecondaryButtonStyle(),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  style: _editorModalPrimaryButtonStyle(),
                  icon: const Icon(Icons.add_box_outlined, size: 18),
                  label: const Text('Insert'),
                ),
              ],
            );
          },
        );
      },
    );
    if (shouldInsert != true) return;

    final index = _editorController.selection.baseOffset;
    var cursor = index < 0 ? _editorController.document.length - 1 : index;
    final plainText = _editorController.document.toPlainText();
    if (cursor > 0 &&
        cursor <= plainText.length &&
        plainText[cursor - 1] != '\n') {
      _editorController.replaceText(
        cursor,
        0,
        '\n',
        TextSelection.collapsed(offset: cursor + 1),
      );
      cursor += 1;
    }

    final payload = _buildTablePayload(columns: columns, rows: rows);
    _editorController.replaceText(
      cursor,
      0,
      quill.BlockEmbed(_tableEmbedType, jsonEncode(payload)),
      TextSelection.collapsed(offset: cursor + 1),
    );
    _editorController.replaceText(
      cursor + 1,
      0,
      '\n',
      TextSelection.collapsed(offset: cursor + 2),
    );
  }

  Future<void> _attachFile({required bool insertLinkIntoEditor}) async {
    if (_isEditorReadOnly) {
      _showReadOnlyVersionWarning();
      return;
    }
    final selected = _selectedNode;
    if (selected == null) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final safeName = (picked.name.isEmpty ? 'attachment' : picked.name)
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'hb_contents/${selected.id}/attachments/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(bytes);
    final url = await ref.getDownloadURL();

    final entry = <String, dynamic>{
      'name': picked.name,
      'url': url,
      'path': path,
      'size': picked.size,
      'uploadedAt': DateTime.now().toIso8601String(),
    };

    setState(() {
      _attachments = [..._attachments, entry];
      _hasUnsavedChanges = true;
    });

    var insertedInEditor = false;
    if (insertLinkIntoEditor) {
      final index = _editorController.selection.baseOffset;
      final cursor = index < 0 ? _editorController.document.length - 1 : index;
      if (_isImageFileName(picked.name)) {
        final imageSource = _buildImageEmbedSource(
          fileName: picked.name,
          bytes: bytes,
          downloadUrl: url,
        );
        _editorController.replaceText(
          cursor,
          0,
          quill.BlockEmbed.image(imageSource),
          TextSelection.collapsed(offset: cursor + 1),
        );
        _editorController.replaceText(
          cursor + 1,
          0,
          '\n',
          TextSelection.collapsed(offset: cursor + 2),
        );
        insertedInEditor = true;
      } else {
        final text = '\n${picked.name}: $url\n';
        _editorController.replaceText(
          cursor,
          0,
          text,
          TextSelection.collapsed(offset: cursor + text.length),
        );
        insertedInEditor = true;
      }
    }

    if (!insertedInEditor) {
      _markDirtyAndSchedule();
    }
  }

  void _onTableDraftChanged(int offset, Map<String, dynamic> payload) {
    _pendingTablePayloadByOffset[offset] = _normalizeTablePayload(
      jsonEncode(payload),
    );
    _markDirtyAndSchedule();
  }

  void _onTableCommitRequested(int offset, Map<String, dynamic> payload) {
    _pendingTablePayloadByOffset[offset] = _normalizeTablePayload(
      jsonEncode(payload),
    );
    // Keep table commits as draft-only during interaction. Flushing/replacing
    // the embed is deferred to explicit save/draft stash to avoid web input
    // target assertions while pointer selection is active.
    _markDirtyAndSchedule();
  }

  void _onTableDeleteRequested(int offset) {
    final resolved = _resolveTableOffset(offset);
    if (resolved == null) return;
    _pendingTablePayloadByOffset.remove(offset);
    _tableStyleSetters.remove(offset);
    if (_activeTableOffset == offset) {
      _activeTableOffset = null;
      _activeTableSelection = _TableSelectionState.empty;
      _isTableCellEditing = false;
    }
    _editorController.replaceText(
      resolved,
      1,
      '',
      TextSelection.collapsed(offset: math.max(0, resolved - 1)),
    );
    _markDirtyAndSchedule();
  }

  void _onTableEditingStateChanged(int offset, bool editing) {
    if (!mounted) return;
    if (editing) {
      _activeTableOffset = offset;
    } else if (_activeTableOffset == offset) {
      _activeTableOffset = null;
      _activeTableSelection = _TableSelectionState.empty;
    }
    if (_isTableCellEditing == editing) return;
    _safeSetState(() {
      _isTableCellEditing = editing;
    });
    _syncEditorReadOnlyState();
    if (editing) {
      _editorController.skipRequestKeyboard = true;
    } else {
      _editorController.skipRequestKeyboard = false;
      _scheduleAutosaveDebounced();
    }
  }

  int? _resolveTableOffset(int offset) {
    final maxOffset = _editorController.document.length - 1;
    final candidates = <int>{offset, offset - 1, offset + 1};
    for (final candidate in candidates) {
      if (candidate < 0 || candidate > maxOffset) continue;
      try {
        final embed = quill.getEmbedNode(_editorController, candidate);
        if (embed.value.value.type == _tableEmbedType) {
          return embed.offset;
        }
      } catch (_) {}
    }
    return null;
  }

  void _flushPendingTablePayloads({Set<int>? onlyOffsets}) {
    if (!mounted) return;
    if (_pendingTablePayloadByOffset.isEmpty) return;
    final offsets = onlyOffsets ?? _pendingTablePayloadByOffset.keys.toSet();
    if (offsets.isEmpty) return;

    final selectionBefore = _editorController.selection;
    final previousSuppress = _suppressDirty;
    _suppressDirty = true;
    try {
      for (final rawOffset in offsets) {
        final payload = _pendingTablePayloadByOffset[rawOffset];
        if (payload == null) continue;
        final resolved = _resolveTableOffset(rawOffset);
        if (resolved == null) continue;
        _editorController.replaceText(
          resolved,
          1,
          quill.BlockEmbed(_tableEmbedType, jsonEncode(payload)),
          selectionBefore.isValid
              ? selectionBefore
              : TextSelection.collapsed(offset: resolved + 1),
        );
        _pendingTablePayloadByOffset.remove(rawOffset);
      }
    } finally {
      _suppressDirty = previousSuppress;
    }
  }

  bool _isImageOffset(int offset) {
    try {
      final embedNode = quill.getEmbedNode(_editorController, offset);
      return embedNode.value.value.type == quill.BlockEmbed.imageType;
    } catch (_) {
      return false;
    }
  }

  void _onTableSelectionStateChanged(int offset, _TableSelectionState state) {
    if (!mounted) return;
    if (_activeTableOffset != offset) return;
    final changed =
        _activeTableSelection.hasActiveCell != state.hasActiveCell ||
        _activeTableSelection.bold != state.bold ||
        _activeTableSelection.italic != state.italic ||
        _activeTableSelection.align != state.align ||
        _activeTableSelection.fontFamilyKey != state.fontFamilyKey ||
        _activeTableSelection.fontSizePoint != state.fontSizePoint;
    if (!changed) return;
    _safeSetState(() {
      _activeTableSelection = state;
    });
  }

  void _onTableStyleSetterChanged(int offset, _TableStyleSetter? setter) {
    if (setter == null) {
      _tableStyleSetters.remove(offset);
      if (_activeTableOffset == offset) {
        _activeTableOffset = null;
        _activeTableSelection = _TableSelectionState.empty;
      }
      return;
    }
    _tableStyleSetters[offset] = setter;
  }

  void _onImageOffsetSelected(int imageOffset) {
    setState(() {
      _activeImageOffset = imageOffset;
      _imageInteractionMode = true;
    });
    _editorFocusNode.unfocus();
    _editorController.skipRequestKeyboard = true;
    _editorController.updateSelection(
      TextSelection.collapsed(offset: imageOffset),
      quill.ChangeSource.local,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_imageInteractionMode ||
          _activeImageOffset != imageOffset) {
        return;
      }
      _editorFocusNode.unfocus();
      _editorController.skipRequestKeyboard = true;
      _editorController.updateSelection(
        TextSelection.collapsed(offset: imageOffset),
        quill.ChangeSource.local,
      );
    });
  }

  void _setImageInteractionMode(bool enabled, {int? caretOffset}) {
    if (_imageInteractionMode == enabled) return;
    final previousImageOffset = _activeImageOffset;
    setState(() {
      _imageInteractionMode = enabled;
      if (!enabled) {
        _closeImageSizeDropdown();
        _imageCropMode = false;
        _activeImageOffset = null;
      }
    });
    if (!enabled) {
      final maxOffset = math.max(0, _editorController.document.length - 1);
      var targetOffset = caretOffset ?? _editorController.selection.baseOffset;
      if (previousImageOffset != null && targetOffset <= previousImageOffset) {
        targetOffset = previousImageOffset + 1;
      }
      if (_isImageOffset(targetOffset)) {
        targetOffset += 1;
      }
      final safeOffset = targetOffset.clamp(0, maxOffset);
      _editorController.updateSelection(
        TextSelection.collapsed(offset: safeOffset),
        quill.ChangeSource.local,
      );
      _editorController.skipRequestKeyboard = false;
      _editorFocusNode.requestFocus();
    } else {
      _editorFocusNode.unfocus();
    }
  }

  Map<String, String> _parseCssStyleMap(String style) {
    final values = <String, String>{};
    for (final segment in style.split(';')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length < 2) continue;
      final name = parts.first.trim();
      final value = parts.sublist(1).join(':').trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        values[name] = value;
      }
    }
    return values;
  }

  String _composeCssStyle(Map<String, String> values) {
    return values.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('; ');
  }

  int? _resolveImageOffset(int offset) {
    final maxOffset = _editorController.document.length - 1;
    final candidates = <int>{
      offset,
      offset - 1,
      offset + 1,
      _activeImageOffset ?? -1,
    };
    for (final candidate in candidates) {
      if (candidate < 0 || candidate > maxOffset) continue;
      try {
        final embed = quill.getEmbedNode(_editorController, candidate);
        if (embed.value.value.type == quill.BlockEmbed.imageType) {
          return embed.offset;
        }
      } catch (_) {}
    }
    return null;
  }

  String _imageStyleStringAt(int offset) {
    final resolvedOffset = _resolveImageOffset(offset);
    if (resolvedOffset == null) return '';
    final node = _editorController.queryNode(resolvedOffset);
    if (node == null) return '';
    return node.style.attributes[quill.Attribute.style.key]?.value
            ?.toString() ??
        '';
  }

  bool _safeFormatImage(int offset, quill.Attribute<dynamic> attribute) {
    final resolvedOffset = _resolveImageOffset(offset);
    if (resolvedOffset == null) return false;
    try {
      // Image drag/resize emits dense pointer updates; if the embed offset goes
      // stale between frames, formatting should fail safely instead of throwing.
      _editorController
        ..skipRequestKeyboard = true
        ..formatText(resolvedOffset, 1, attribute);
      return true;
    } on FormatException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _imageStyleMap(int offset) {
    return _parseCssStyleMap(_imageStyleStringAt(offset));
  }

  double _styleDouble(
    Map<String, String> map,
    String key, {
    double fallback = 0,
  }) {
    return double.tryParse(map[key] ?? '') ?? fallback;
  }

  double? _readImageHeight(int offset) {
    final resolvedOffset = _resolveImageOffset(offset);
    if (resolvedOffset == null) return null;
    final node = _editorController.queryNode(resolvedOffset);
    if (node == null) return null;
    final heightValue = node.style.attributes[quill.Attribute.height.key]?.value
        ?.toString();
    final styleMap = _imageStyleMap(resolvedOffset);
    final styleHeight = styleMap['height'];
    if (heightValue == null || heightValue.trim().isEmpty) {
      return double.tryParse(styleHeight ?? '');
    }
    return double.tryParse(heightValue) ?? double.tryParse(styleHeight ?? '');
  }

  void _setImageStyleMap(int offset, Map<String, String> styleMap) {
    final nextStyle = _composeCssStyle(styleMap);
    final currentStyle = _imageStyleStringAt(offset);
    if (nextStyle == currentStyle) return;
    _safeFormatImage(offset, quill.StyleAttribute(nextStyle));
  }

  void _setImageStyleMapThrottled(int offset, Map<String, String> styleMap) {
    _pendingImageStyleOffset = offset;
    _pendingImageStyleMap = Map<String, String>.from(styleMap);
    if (_imageStyleFlushTimer != null) return;
    _imageStyleFlushTimer = Timer(const Duration(milliseconds: 28), () {
      _imageStyleFlushTimer = null;
      final pendingOffset = _pendingImageStyleOffset;
      final pendingStyle = _pendingImageStyleMap;
      _pendingImageStyleOffset = null;
      _pendingImageStyleMap = null;
      if (pendingOffset == null || pendingStyle == null) return;
      _setImageStyleMap(pendingOffset, pendingStyle);
      if (_pendingImageStyleOffset != null && _pendingImageStyleMap != null) {
        _setImageStyleMapThrottled(
          _pendingImageStyleOffset!,
          _pendingImageStyleMap!,
        );
      }
    });
  }

  Map<String, String> _effectiveImageStyleMap(int offset) {
    final pendingOffset = _pendingImageStyleOffset;
    final pendingStyle = _pendingImageStyleMap;
    if (pendingOffset == null || pendingStyle == null) {
      return _imageStyleMap(offset);
    }
    final resolvedRequested = _resolveImageOffset(offset);
    final resolvedPending = _resolveImageOffset(pendingOffset);
    if (resolvedRequested != null &&
        resolvedPending != null &&
        resolvedRequested == resolvedPending) {
      return Map<String, String>.from(pendingStyle);
    }
    return _imageStyleMap(offset);
  }

  bool _isCornerHandle(_ImageHandleKind handle) {
    return _isHorizontalHandle(handle) && _isVerticalHandle(handle);
  }

  bool _isHorizontalHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.left ||
        handle == _ImageHandleKind.right ||
        handle == _ImageHandleKind.topLeft ||
        handle == _ImageHandleKind.bottomLeft ||
        handle == _ImageHandleKind.topRight ||
        handle == _ImageHandleKind.bottomRight;
  }

  bool _isVerticalHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.top ||
        handle == _ImageHandleKind.bottom ||
        handle == _ImageHandleKind.topLeft ||
        handle == _ImageHandleKind.topRight ||
        handle == _ImageHandleKind.bottomLeft ||
        handle == _ImageHandleKind.bottomRight;
  }

  bool _isLeftHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.left ||
        handle == _ImageHandleKind.topLeft ||
        handle == _ImageHandleKind.bottomLeft;
  }

  bool _isRightHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.right ||
        handle == _ImageHandleKind.topRight ||
        handle == _ImageHandleKind.bottomRight;
  }

  bool _isTopHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.top ||
        handle == _ImageHandleKind.topLeft ||
        handle == _ImageHandleKind.topRight;
  }

  bool _isBottomHandle(_ImageHandleKind handle) {
    return handle == _ImageHandleKind.bottom ||
        handle == _ImageHandleKind.bottomLeft ||
        handle == _ImageHandleKind.bottomRight;
  }

  void _onImageHandleDrag(int offset, _ImageHandleKind handle, Offset delta) {
    if (handle == _ImageHandleKind.rotate) return;
    if (_activeImageOffset != offset || !_imageInteractionMode) {
      setState(() {
        _activeImageOffset = offset;
        _imageInteractionMode = true;
      });
    }
    _editorFocusNode.unfocus();
    _editorController.skipRequestKeyboard = true;

    final styleMap = _effectiveImageStyleMap(offset);
    final currentWidth = (_styleDouble(
      styleMap,
      'width',
      fallback: _readImageWidth(offset) ?? 420,
    )).clamp(120, 1400);
    final currentHeight = (_styleDouble(
      styleMap,
      'height',
      fallback: _readImageHeight(offset) ?? (currentWidth * 0.62),
    )).clamp(90, 1400);

    if (_imageCropMode) {
      var cropLeft = _styleDouble(styleMap, 'cropLeft');
      var cropTop = _styleDouble(styleMap, 'cropTop');
      var cropRight = _styleDouble(styleMap, 'cropRight');
      var cropBottom = _styleDouble(styleMap, 'cropBottom');

      if (_isHorizontalHandle(handle)) {
        if (_isLeftHandle(handle)) {
          cropLeft += delta.dx / currentWidth;
        }
        if (_isRightHandle(handle)) {
          cropRight -= delta.dx / currentWidth;
        }
      }

      if (_isVerticalHandle(handle)) {
        if (_isTopHandle(handle)) {
          cropTop += delta.dy / currentHeight;
        }
        if (_isBottomHandle(handle)) {
          cropBottom -= delta.dy / currentHeight;
        }
      }

      cropLeft = cropLeft.clamp(0.0, 0.45);
      cropTop = cropTop.clamp(0.0, 0.45);
      cropRight = cropRight.clamp(0.0, 0.45);
      cropBottom = cropBottom.clamp(0.0, 0.45);

      final horizontalTotal = cropLeft + cropRight;
      if (horizontalTotal > 0.85) {
        final scale = 0.85 / horizontalTotal;
        cropLeft *= scale;
        cropRight *= scale;
      }
      final verticalTotal = cropTop + cropBottom;
      if (verticalTotal > 0.85) {
        final scale = 0.85 / verticalTotal;
        cropTop *= scale;
        cropBottom *= scale;
      }

      styleMap['cropLeft'] = cropLeft.toStringAsFixed(3);
      styleMap['cropTop'] = cropTop.toStringAsFixed(3);
      styleMap['cropRight'] = cropRight.toStringAsFixed(3);
      styleMap['cropBottom'] = cropBottom.toStringAsFixed(3);
      _setImageStyleMapThrottled(offset, styleMap);
      return;
    }

    final ratio = (currentHeight <= 0)
        ? (420 / 260)
        : (currentWidth / currentHeight).clamp(0.2, 8.0);

    var width = currentWidth.toDouble();
    var height = currentHeight.toDouble();
    final deltaX = _isRightHandle(handle)
        ? delta.dx
        : (_isLeftHandle(handle) ? -delta.dx : 0.0);
    final deltaY = _isBottomHandle(handle)
        ? delta.dy
        : (_isTopHandle(handle) ? -delta.dy : 0.0);

    if (_isCornerHandle(handle)) {
      final widthFromHorizontal = width + deltaX;
      final widthFromVertical = width + (deltaY * ratio);
      width =
          (widthFromHorizontal - width).abs() >=
              (widthFromVertical - width).abs()
          ? widthFromHorizontal
          : widthFromVertical;
      width = width.clamp(120.0, 1400.0);
      height = (width / ratio).clamp(90.0, 1400.0);
      width = (height * ratio).clamp(120.0, 1400.0);
    } else if (_isHorizontalHandle(handle)) {
      width = (width + deltaX).clamp(120.0, 1400.0);
      height = (width / ratio).clamp(90.0, 1400.0);
      width = (height * ratio).clamp(120.0, 1400.0);
    } else if (_isVerticalHandle(handle)) {
      height = (height + deltaY).clamp(90.0, 1400.0);
      width = (height * ratio).clamp(120.0, 1400.0);
      height = (width / ratio).clamp(90.0, 1400.0);
    }

    final updatedStyle = _effectiveImageStyleMap(offset);
    updatedStyle['width'] = width.toStringAsFixed(0);
    updatedStyle['height'] = height.toStringAsFixed(0);
    _setImageStyleMapThrottled(offset, updatedStyle);
  }

  void _onImageRotateDrag(int offset, double degreeDelta) {
    if (_activeImageOffset != offset || !_imageInteractionMode) {
      setState(() {
        _activeImageOffset = offset;
        _imageInteractionMode = true;
      });
    }
    _editorFocusNode.unfocus();
    _editorController.skipRequestKeyboard = true;
    final styleMap = _imageStyleMap(offset);
    final currentRotation = _styleDouble(styleMap, 'rotation');
    var updatedRotation = currentRotation + degreeDelta;
    while (updatedRotation >= 360) {
      updatedRotation -= 360;
    }
    while (updatedRotation < 0) {
      updatedRotation += 360;
    }
    styleMap['rotation'] = updatedRotation.toStringAsFixed(2);
    _setImageStyleMapThrottled(offset, styleMap);
  }

  void _onImageRotateQuarterTurn(int offset) {
    _onImageRotateDrag(offset, 90);
  }

  void _rotateImageLeft(int offset) {
    _onImageRotateDrag(offset, -90);
  }

  void _rotateImageRight(int offset) {
    _onImageRotateDrag(offset, 90);
  }

  void _showImageSizeControlDialog(int imageOffset) {
    _onImageOffsetSelected(imageOffset);
    final anchorContext = _imageSizeButtonKey.currentContext;
    final overlayState = Overlay.of(context);
    if (anchorContext == null) {
      return;
    }
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null) return;

    var previewWidth = (_readImageWidth(imageOffset) ?? 360).clamp(
      120.0,
      960.0,
    );
    const panelWidth = 260.0;
    const panelHeight = 98.0;
    const margin = 10.0;

    final anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final anchorBottomLeft = anchorBox.localToGlobal(
      Offset(0, anchorBox.size.height),
      ancestor: overlayBox,
    );
    final rightAlignedLeft =
        anchorBottomLeft.dx + anchorBox.size.width - panelWidth;
    final left = rightAlignedLeft.clamp(
      margin,
      math.max(margin, overlayBox.size.width - panelWidth - margin),
    );
    var top = anchorBottomLeft.dy + 6;
    final maxBottom = overlayBox.size.height - margin;
    if (top + panelHeight > maxBottom) {
      top = anchorTopLeft.dy - panelHeight - 6;
    }
    if (top < margin) top = margin;

    _closeImageSizeDropdown();
    _imageSizeOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeImageSizeDropdown,
              ),
            ),
            Positioned(
              left: left.toDouble(),
              top: top.toDouble(),
              width: panelWidth,
              child: Material(
                color: Colors.white,
                elevation: 10,
                borderRadius: BorderRadius.circular(10),
                child: StatefulBuilder(
                  builder: (context, setSheetState) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Slider(
                            value: previewWidth.toDouble(),
                            min: 120,
                            max: 960,
                            divisions: 84,
                            onChanged: (value) =>
                                setSheetState(() => previewWidth = value),
                            onChangeEnd: (value) =>
                                _setImageWidth(imageOffset, value),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Reset size',
                                onPressed: () {
                                  _clearImageWidth(imageOffset);
                                  setSheetState(() => previewWidth = 360);
                                },
                                icon: const Icon(Icons.restart_alt_rounded),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                onPressed: _closeImageSizeDropdown,
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
    overlayState.insert(_imageSizeOverlay!);
  }

  void _closeImageSizeDropdown() {
    _imageSizeOverlay?.remove();
    _imageSizeOverlay = null;
  }

  double? _readImageWidth(int offset) {
    final resolvedOffset = _resolveImageOffset(offset);
    if (resolvedOffset == null) return null;
    final node = _editorController.queryNode(resolvedOffset);
    if (node == null) return null;
    final widthValue = node.style.attributes[quill.Attribute.width.key]?.value
        ?.toString();
    final styleMap = _imageStyleMap(resolvedOffset);
    final styleWidth = styleMap['width'];
    if (widthValue == null || widthValue.trim().isEmpty) {
      return double.tryParse(styleWidth ?? '');
    }
    return double.tryParse(widthValue) ?? double.tryParse(styleWidth ?? '');
  }

  void _setImageWidth(int offset, double width) {
    final styleMap = _effectiveImageStyleMap(offset);
    final currentWidth = (_styleDouble(
      styleMap,
      'width',
      fallback: _readImageWidth(offset) ?? 420,
    )).clamp(120.0, 1400.0);
    final currentHeight = (_styleDouble(
      styleMap,
      'height',
      fallback: _readImageHeight(offset) ?? (currentWidth * 0.62),
    )).clamp(90.0, 1400.0);
    final ratio = (currentHeight <= 0)
        ? (420 / 260)
        : (currentWidth / currentHeight).clamp(0.2, 8.0);

    final nextWidth = width.clamp(120.0, 1400.0);
    final nextHeight = (nextWidth / ratio).clamp(90.0, 1400.0);
    styleMap['width'] = nextWidth.toStringAsFixed(0);
    styleMap['height'] = nextHeight.toStringAsFixed(0);
    _setImageStyleMap(offset, styleMap);
    _markDirtyAndSchedule();
  }

  void _clearImageWidth(int offset) {
    final styleMap = _imageStyleMap(offset);
    styleMap.remove('width');
    styleMap.remove('height');
    _setImageStyleMap(offset, styleMap);
    _markDirtyAndSchedule();
  }

  void _setImageAlignment(int offset, String alignment) {
    final currentStyle = _imageStyleStringAt(offset);
    final updatedStyle = _upsertCssStyle(
      currentStyle,
      'alignment',
      _normalizeImageAlignment(alignment),
    );

    _safeFormatImage(offset, quill.StyleAttribute(updatedStyle));
    _markDirtyAndSchedule();
  }

  String _upsertCssStyle(String style, String key, String value) {
    final values = <String, String>{};
    for (final segment in style.split(';')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length < 2) continue;
      final name = parts.first.trim();
      final val = parts.sublist(1).join(':').trim();
      if (name.isNotEmpty && val.isNotEmpty) {
        values[name] = val;
      }
    }
    values[key] = value;
    return values.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('; ');
  }

  String _normalizeImageAlignment(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'left' || normalized == 'right') return normalized;
    return 'center';
  }

  String _normalizeImageDisplayMode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'full' || normalized == 'side') return normalized;
    return 'inline';
  }

  String _readImageAlignment(int offset) {
    final styleMap = _imageStyleMap(offset);
    return _normalizeImageAlignment(styleMap['alignment'] ?? 'center');
  }

  String _readImageDisplayMode(int offset) {
    final styleMap = _imageStyleMap(offset);
    return _normalizeImageDisplayMode(styleMap['displayMode'] ?? 'inline');
  }

  void _setImageDisplayMode(int offset, String mode) {
    final currentStyle = _imageStyleStringAt(offset);
    final updatedStyle = _upsertCssStyle(
      currentStyle,
      'displayMode',
      _normalizeImageDisplayMode(mode),
    );
    _safeFormatImage(offset, quill.StyleAttribute(updatedStyle));
    _markDirtyAndSchedule();
  }

  bool _isImageFileName(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg');
  }

  String _buildImageEmbedSource({
    required String fileName,
    required List<int> bytes,
    required String downloadUrl,
  }) {
    if (!kIsWeb) return downloadUrl;
    final lower = fileName.toLowerCase();
    final mimeType = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.gif')
        ? 'image/gif'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : lower.endsWith('.bmp')
        ? 'image/bmp'
        : lower.endsWith('.svg')
        ? 'image/svg+xml'
        : 'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  Future<void> _handleInsertAction(String action) async {
    if (_isEditorReadOnly) {
      _showReadOnlyVersionWarning();
      return;
    }
    if (action == 'table') {
      await _insertTableTemplate();
      return;
    }
    if (action == 'image') {
      await _attachFile(insertLinkIntoEditor: true);
      return;
    }
    if (action == 'attachment') {
      await _attachFile(insertLinkIntoEditor: false);
      return;
    }
    if (action == 'link') {
      await _promptInsertLink();
      return;
    }
  }

  Future<void> _promptInsertLink() async {
    if (_isEditorReadOnly) {
      _showReadOnlyVersionWarning();
      return;
    }
    final selection = _editorController.selection;
    final length = (selection.end - selection.start).abs();
    final hasSelection = length > 0;

    final urlCtrl = TextEditingController();
    final textCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _buildEditorStyledDialog(
          context: context,
          icon: Icons.link_rounded,
          title: 'Insert Link',
          subtitle: 'Add a URL to selected text or insert a new linked label.',
          width: 460,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasSelection)
                TextField(
                  controller: textCtrl,
                  decoration: _editorDialogInputDecoration(
                    label: 'Display text',
                    isDense: true,
                  ),
                ),
              if (!hasSelection) const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                decoration: _editorDialogInputDecoration(
                  label: 'URL',
                  hintText: 'https://...',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: _editorModalSecondaryButtonStyle(),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              style: _editorModalPrimaryButtonStyle(),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('Insert'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    final url = urlCtrl.text.trim();
    if (url.isEmpty) return;

    if (hasSelection) {
      final start = selection.start < selection.end
          ? selection.start
          : selection.end;
      _editorController.formatText(
        start,
        length,
        quill.Attribute.fromKeyValue(quill.Attribute.link.key, url),
      );
      return;
    }

    final insertText = textCtrl.text.trim().isEmpty
        ? url
        : textCtrl.text.trim();
    final start = selection.start < 0 ? 0 : selection.start;
    _editorController.replaceText(
      start,
      0,
      insertText,
      TextSelection.collapsed(offset: start + insertText.length),
    );
    _editorController.formatText(
      start,
      insertText.length,
      quill.Attribute.fromKeyValue(quill.Attribute.link.key, url),
    );
  }

  void _resetEditorState() {
    final old = _editorController;
    _pendingTablePayloadByOffset.clear();
    _tableStyleSetters.clear();
    _activeTableOffset = null;
    _activeTableSelection = _TableSelectionState.empty;
    _isTableCellEditing = false;
    _pendingNodeDrafts.clear();
    _currentNodeDirty = false;
    _editorController = quill.QuillController.basic();
    _syncEditorReadOnlyState();
    _bindEditorDocChanges();
    _titleCtrl.clear();
    _safeSetState(() {
      _selectedNodeId = null;
      _activeImageOffset = null;
      _imageCropMode = false;
      _imageInteractionMode = false;
      _useSectionNumbering = true;
      _attachments = const [];
      _hasUnsavedChanges = false;
      _saveMessage = 'Saved';
    });
    _publishSaveViewState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
  }

  Future<void> _handleBackPressed() async {
    if (_hasAnyUnsavedDrafts) {
      final action = await _askUnsavedChangesAction(leavingPage: true);
      if (action == _UnsavedExitAction.cancel) return;
      if (action == _UnsavedExitAction.save) {
        final saved = await _saveAllPendingDrafts(source: 'back');
        if (!saved) return;
      } else if (action == _UnsavedExitAction.discard) {
        await _discardCurrentDrafts();
      }
    }
    if (!mounted) return;
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingContext) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_contextError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _contextError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Theme(
      data: _uniformUiTheme(context),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              _headerBar(),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1280;
                    final tablet = constraints.maxWidth >= 980 && !wide;

                    if (wide) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!_entriesPanelCollapsed) ...[
                              SizedBox(
                                width: 330,
                                child: RepaintBoundary(child: _leftTreePanel()),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: RepaintBoundary(child: _editorPanel()),
                            ),
                            if (!_outlinePanelCollapsed) ...[
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 280,
                                child: RepaintBoundary(
                                  child: _outlineSidePanel(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    if (tablet) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!_entriesPanelCollapsed) ...[
                              SizedBox(
                                width: 300,
                                child: RepaintBoundary(child: _leftTreePanel()),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: RepaintBoundary(child: _editorPanel()),
                            ),
                            if (!_outlinePanelCollapsed) ...[
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 240,
                                child: RepaintBoundary(
                                  child: _outlineSidePanel(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: (_entriesPanelCollapsed && _outlinePanelCollapsed)
                          ? RepaintBoundary(child: _editorPanel())
                          : Column(
                              children: [
                                if (!_entriesPanelCollapsed) ...[
                                  Expanded(
                                    flex: 6,
                                    child: RepaintBoundary(
                                      child: _leftTreePanel(),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                Expanded(
                                  flex: 8,
                                  child: RepaintBoundary(child: _editorPanel()),
                                ),
                                if (!_outlinePanelCollapsed) ...[
                                  const SizedBox(height: 10),
                                  Expanded(
                                    flex: 5,
                                    child: RepaintBoundary(
                                      child: _outlineSidePanel(),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: ValueListenableBuilder<_EditorSaveViewState>(
        valueListenable: _saveViewState,
        builder: (context, _, child) {
          final canUseWorkflowActions = !_isWorkflowReadOnly;
          final canSaveOrDiscard =
              canUseWorkflowActions && _hasAnyUnsavedDrafts && !_isSaving;
          final actionWidgets = <Widget>[
            if (!_editingEnabled)
              FilledButton.icon(
                onPressed: canUseWorkflowActions
                    ? () => _setEditingEnabled(true)
                    : null,
                style: FilledButton.styleFrom(backgroundColor: _primary),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Edit'),
              ),
            if (_editingEnabled)
              OutlinedButton.icon(
                onPressed: canSaveOrDiscard ? _confirmAndDiscardDraft : null,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Discard'),
              ),
            if (_editingEnabled)
              FilledButton.icon(
                onPressed: canSaveOrDiscard
                    ? () async {
                        await _saveAllPendingDrafts(source: 'manual');
                      }
                    : null,
                style: FilledButton.styleFrom(backgroundColor: _primary),
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save'),
              ),
            if (_editingEnabled)
              OutlinedButton.icon(
                onPressed: canUseWorkflowActions
                    ? () => _setEditingEnabled(false)
                    : null,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel'),
              ),
          ];

          return LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 980;
              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: _handleBackPressed,
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: _primary,
                          ),
                          tooltip: 'Back to Manage Handbook',
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.description_rounded, color: _primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _handbookVersion,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: actionWidgets),
                  ],
                );
              }
              return Row(
                children: [
                  IconButton(
                    onPressed: _handleBackPressed,
                    icon: const Icon(Icons.arrow_back_rounded, color: _primary),
                    tooltip: 'Back to Manage Handbook',
                  ),
                  const Icon(Icons.description_rounded, color: _primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _handbookVersion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...List<Widget>.generate(actionWidgets.length * 2 - 1, (
                    index,
                  ) {
                    if (index.isOdd) return const SizedBox(width: 8);
                    return actionWidgets[index ~/ 2];
                  }),
                ],
              );
            },
          );
        },
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

  ThemeData _uniformUiTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          color: _primary,
          fontWeight: FontWeight.w900,
          fontSize: 20,
        ),
        contentTextStyle: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        textStyle: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 1.6),
        ),
      ),
    );
  }

  InputDecoration _editorDialogInputDecoration({
    required String label,
    String? hintText,
    String? helperText,
    String? errorText,
    bool alignLabelWithHint = false,
    bool isDense = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      alignLabelWithHint: alignLabelWithHint,
      isDense: isDense,
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary, width: 1.35),
      ),
    );
  }

  ButtonStyle _editorModalPrimaryButtonStyle({Color? backgroundColor}) {
    return FilledButton.styleFrom(
      backgroundColor: backgroundColor ?? _primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
    );
  }

  ButtonStyle _editorModalSecondaryButtonStyle() {
    return TextButton.styleFrom(
      foregroundColor: _muted,
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _buildEditorStyledDialog({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget body,
    required List<Widget> actions,
    double width = 500,
  }) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      actionsAlignment: MainAxisAlignment.end,
      title: Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: _muted),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: _primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      if ((subtitle ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            body,
          ],
        ),
      ),
      actions: actions,
    );
  }

  Widget _editorViewOptionsMenuButton() {
    final canToggleOutline = _selectedNode != null;
    return Tooltip(
      message: 'View options',
      child: PopupMenuButton<_EditorViewToggleAction>(
        onSelected: (action) {
          setState(() {
            switch (action) {
              case _EditorViewToggleAction.ribbon:
                _showRibbon = !_showRibbon;
                break;
              case _EditorViewToggleAction.entries:
                _entriesPanelCollapsed = !_entriesPanelCollapsed;
                break;
              case _EditorViewToggleAction.outline:
                if (!canToggleOutline) return;
                _outlinePanelCollapsed = !_outlinePanelCollapsed;
                break;
            }
          });
        },
        itemBuilder: (context) => [
          CheckedPopupMenuItem<_EditorViewToggleAction>(
            value: _EditorViewToggleAction.ribbon,
            checked: _showRibbon,
            child: const Text('Show ribbon'),
          ),
          CheckedPopupMenuItem<_EditorViewToggleAction>(
            value: _EditorViewToggleAction.entries,
            checked: !_entriesPanelCollapsed,
            child: const Text('Show entries'),
          ),
          CheckedPopupMenuItem<_EditorViewToggleAction>(
            value: _EditorViewToggleAction.outline,
            enabled: canToggleOutline,
            checked: canToggleOutline && !_outlinePanelCollapsed,
            child: const Text('Show page outline'),
          ),
        ],
        tooltip: 'View options',
        padding: EdgeInsets.zero,
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 22,
          color: _primary,
        ),
      ),
    );
  }

  Widget _editorCollapsedRibbonStrip() {
    return Container(
      width: double.infinity,
      height: 26,
      padding: const EdgeInsets.only(right: 8),
      color: Colors.white,
      alignment: Alignment.centerRight,
      child: _editorViewOptionsMenuButton(),
    );
  }

  void _setPaperZoom(double nextValue) {
    final normalized = nextValue.clamp(0.8, 1.6).toDouble();
    if ((_paperZoom - normalized).abs() < 0.001) return;
    setState(() => _paperZoom = normalized);
  }

  void _stepPaperZoom({required bool increase}) {
    _setPaperZoom(_paperZoom + (increase ? 0.1 : -0.1));
  }

  Widget _paperZoomControl({bool compact = false}) {
    final label = '${(_paperZoom * 100).round()}%';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Zoom out',
          child: IconButton(
            onPressed: () => _stepPaperZoom(increase: false),
            icon: const Icon(Icons.remove_rounded, size: 16),
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            splashRadius: 16,
          ),
        ),
        SizedBox(
          width: compact ? 44 : 50,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Tooltip(
          message: 'Zoom in',
          child: IconButton(
            onPressed: () => _stepPaperZoom(increase: true),
            icon: const Icon(Icons.add_rounded, size: 16),
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            splashRadius: 16,
          ),
        ),
      ],
    );
  }

  Future<void> _showShortcutsDialog() async {
    const shortcuts = <String>[
      'Ctrl/Cmd + S  Save',
      'Ctrl/Cmd + B  Bold',
      'Ctrl/Cmd + I  Italic',
      'Ctrl/Cmd + U  Underline',
      'Ctrl/Cmd + K  Insert link',
      'Shift + 7/8  Numbered/Bullet list',
      'Tab / Shift + Tab  Indent / Outdent',
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildEditorStyledDialog(
          context: dialogContext,
          icon: Icons.info_outline_rounded,
          title: 'Editor Shortcuts',
          subtitle: 'Keyboard shortcuts available while editing.',
          width: 440,
          body: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: shortcuts
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: _text,
                          fontSize: 13.2,
                          fontWeight: FontWeight.w700,
                          height: 1.32,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          actions: [
            TextButton(
              style: _editorModalSecondaryButtonStyle(),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _shortcutsInfoButton() {
    return Tooltip(
      message: 'View editor shortcuts',
      child: IconButton(
        onPressed: _showShortcutsDialog,
        icon: const Icon(Icons.info_outline_rounded, size: 18),
        color: _primary,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
        splashRadius: 16,
      ),
    );
  }

  Widget _leftTreePanel() {
    final roots = _rootNodes();
    final filteredRoots = roots.where(_matchesNodeOrDescendant).toList();
    final sectionNumbers = _buildRootSectionNumberMap();
    final canReorder = _query.trim().isEmpty && !_isEditorReadOnly;
    return _surface(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Entries',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (!_isEditorReadOnly)
                  IconButton(
                    onPressed: () => _createNode(parentId: ''),
                    icon: const Icon(Icons.add_circle_rounded, color: _primary),
                    tooltip: 'Add entry',
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search entries',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: filteredRoots.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'No entries yet. Add your first entry.',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    buildDefaultDragHandles: false,
                    itemCount: filteredRoots.length,
                    onReorderStart: (_) {
                      _safeSetState(() {
                        _isRootReordering = true;
                        _sectionTapLockedUntil = DateTime.now().add(
                          const Duration(milliseconds: 900),
                        );
                      });
                    },
                    onReorderEnd: (_) {
                      _safeSetState(() {
                        _isRootReordering = false;
                        _sectionTapLockedUntil = DateTime.now().add(
                          const Duration(milliseconds: 350),
                        );
                      });
                    },
                    onReorder: (oldIndex, newIndex) {
                      if (!canReorder) return;
                      _reorderRootNodes(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final node = filteredRoots[index];
                      return _treeNodeTile(
                        node: node,
                        index: index,
                        sectionNumber: sectionNumbers[node.id] ?? '',
                        canReorder: canReorder,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _outlineSidePanel() {
    return _surface(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Expanded(
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
            child: ListenableBuilder(
              listenable: _editorController,
              builder: (context, child) {
                final headings = _buildEntryOutlineHeadings();
                if (headings.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(14, 6, 14, 14),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        'Add Heading 2 and Heading 1 in the editor to build the outline.',
                        style: TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: _entryOutlinePanel(headings),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryOutlinePanel(List<_EntryOutlineHeading> headings) {
    final activeOffset = _activeOutlineOffset(headings);
    return ListView.separated(
      itemCount: headings.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final heading = headings[index];
        final selected = heading.offset == activeOffset;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: selected ? _primary.withValues(alpha: 0.10) : Colors.white,
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
              mouseCursor: SystemMouseCursors.click,
              onTap: () => _jumpToHeadingOffset(heading.offset),
              child: Padding(
                padding: EdgeInsets.fromLTRB(8 + (heading.depth * 14), 9, 8, 9),
                child: Text(
                  heading.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _text : _primary,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
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
    );
  }

  int _activeOutlineOffset(List<_EntryOutlineHeading> headings) {
    if (headings.isEmpty) return -1;
    final caret = _editorController.selection.baseOffset;
    if (caret <= 0) return headings.first.offset;
    var best = headings.first.offset;
    for (final heading in headings) {
      if (heading.offset <= caret) {
        best = heading.offset;
      } else {
        break;
      }
    }
    return best;
  }

  List<_EntryOutlineHeading> _buildEntryOutlineHeadings() {
    final ops = _editorController.document.toDelta().toJson();
    if (ops.isEmpty) return const [];
    final headings = <_EntryOutlineHeading>[];
    final lineText = StringBuffer();
    var lineStartOffset = 0;
    var offset = 0;
    var hasSeenH2 = false;

    for (final raw in ops) {
      final op = Map<String, dynamic>.from(raw as Map);
      final insert = op['insert'];
      final attrs = op['attributes'] is Map
          ? Map<String, dynamic>.from(op['attributes'] as Map)
          : null;
      final headerLevel = _extractHeadingLevel(attrs);

      if (insert is String) {
        for (var i = 0; i < insert.length; i++) {
          final ch = insert[i];
          if (ch == '\n') {
            final headingText = lineText.toString().trim();
            if (headingText.isNotEmpty &&
                (headerLevel == 1 || headerLevel == 2)) {
              final depth = headerLevel == 2 ? 0 : (hasSeenH2 ? 1 : 0);
              headings.add(
                _EntryOutlineHeading(
                  text: headingText,
                  offset: lineStartOffset,
                  depth: depth,
                ),
              );
              if (headerLevel == 2) {
                hasSeenH2 = true;
              }
            }
            lineText.clear();
            offset += 1;
            lineStartOffset = offset;
            continue;
          }
          lineText.write(ch);
          offset += 1;
        }
        continue;
      }

      if (insert is Map) {
        offset += 1;
      }
    }
    return headings;
  }

  int? _extractHeadingLevel(Map<String, dynamic>? attrs) {
    if (attrs == null) return null;
    final raw = attrs['header'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  void _jumpToHeadingOffset(int offset) {
    final docLength = _editorController.document.length;
    if (docLength <= 0) return;
    final target = offset.clamp(0, docLength - 1);
    _editorController.updateSelection(
      TextSelection.collapsed(offset: target),
      quill.ChangeSource.local,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editorController.skipRequestKeyboard = _isEditorReadOnly;
      _editorFocusNode.requestFocus();
    });
  }

  Widget _treeNodeTile({
    required HandbookNodeDoc node,
    required int index,
    required String sectionNumber,
    required bool canReorder,
  }) {
    final selected = _selectedNodeId == node.id;
    final hasNumber = sectionNumber.trim().isNotEmpty;
    return SizedBox(
      key: ValueKey('section_${node.id}'),
      width: double.infinity,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: selected ? _primary.withValues(alpha: 0.10) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? _primary.withValues(alpha: 0.32)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          mouseCursor: SystemMouseCursors.click,
          onTap: () {
            if (!_canHandleSectionTap()) return;
            _switchToNode(node.id);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                canReorder
                    ? ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.drag_indicator,
                            color: _muted.withValues(alpha: 0.85),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.drag_indicator,
                          color: _muted.withValues(alpha: 0.45),
                        ),
                      ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasNumber
                            ? '$sectionNumber. ${node.title}'
                            : node.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _text,
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !_isEditorReadOnly,
                  onSelected: (value) {
                    if (value == 'delete') {
                      _deleteNode(node.id);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _matchesNodeOrDescendant(HandbookNodeDoc node) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final localHit =
        node.title.toLowerCase().contains(q) ||
        node.tags.any((tag) => tag.toLowerCase().contains(q));
    if (localHit) return true;
    return _childrenOf(node.id).any(_matchesNodeOrDescendant);
  }

  Widget _editorPanel() {
    if (_selectedNode == null) {
      return _surface(
        child: const Center(
          child: Text(
            'Select a node to start editing.',
            style: TextStyle(color: _muted, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    final selectedNode = _selectedNode!;
    final sectionNumbers = _buildRootSectionNumberMap();
    final selectedSectionNumber = selectedNode.parentId.trim().isEmpty
        ? (sectionNumbers[selectedNode.id] ?? '')
        : '';
    final showTitleSectionNumber = selectedSectionNumber.trim().isNotEmpty;

    final paperMaxWidth = (920 * _paperZoom).clamp(700.0, 1280.0).toDouble();
    final editorPadding = EdgeInsets.fromLTRB(
      (36 * _paperZoom).clamp(24.0, 56.0),
      (28 * _paperZoom).clamp(18.0, 46.0),
      (36 * _paperZoom).clamp(24.0, 56.0),
      (64 * _paperZoom).clamp(44.0, 100.0),
    );

    final editorWidget = quill.QuillEditor.basic(
      controller: _editorController,
      focusNode: _editorFocusNode,
      scrollController: _editorScrollController,
      config: quill.QuillEditorConfig(
        scrollable: true,
        autoFocus: false,
        expands: false,
        enableAlwaysIndentOnTab: false,
        enableInteractiveSelection: !_isEditorReadOnly && !_isTableCellEditing,
        onKeyPressed: (event, node) => _handleEditorKeyPress(event),
        showCursor:
            !_isEditorReadOnly &&
            !_isTableCellEditing &&
            !_imageInteractionMode,
        onTapDown: (details, getPositionForOffset) {
          if (!_imageInteractionMode) return false;
          final localOffset = details.localPosition;
          final textPosition = getPositionForOffset(localOffset);
          final tappedOffset = textPosition.offset;
          final activeImageOffset = _activeImageOffset;
          final resolvedTappedImage = _resolveImageOffset(tappedOffset);
          final onActiveImage =
              activeImageOffset != null &&
              resolvedTappedImage != null &&
              resolvedTappedImage == activeImageOffset &&
              _isImageOffset(activeImageOffset);
          if (!onActiveImage) {
            _setImageInteractionMode(false, caretOffset: tappedOffset);
          }
          return false;
        },
        padding: editorPadding,
        embedBuilders: _embedBuilders,
        unknownEmbedBuilder: const _UnknownEmbedBuilder(),
      ),
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _EditorSaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            _EditorSaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _EditorSelectAllIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            _EditorSelectAllIntent(),
        SingleActivator(LogicalKeyboardKey.tab): _EditorIndentIntent(
          increase: true,
        ),
        SingleActivator(LogicalKeyboardKey.tab, shift: true):
            _EditorIndentIntent(increase: false),
        SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _EditorToggleInlineIntent(_InlineFormatType.bold),
        SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            _EditorToggleInlineIntent(_InlineFormatType.bold),
        SingleActivator(LogicalKeyboardKey.keyI, control: true):
            _EditorToggleInlineIntent(_InlineFormatType.italic),
        SingleActivator(LogicalKeyboardKey.keyI, meta: true):
            _EditorToggleInlineIntent(_InlineFormatType.italic),
        SingleActivator(LogicalKeyboardKey.keyU, control: true):
            _EditorToggleInlineIntent(_InlineFormatType.underline),
        SingleActivator(LogicalKeyboardKey.keyU, meta: true):
            _EditorToggleInlineIntent(_InlineFormatType.underline),
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _EditorInsertLinkIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _EditorInsertLinkIntent(),
        SingleActivator(LogicalKeyboardKey.digit8, shift: true, control: true):
            _EditorToggleListIntent(_ListFormatType.bullet),
        SingleActivator(LogicalKeyboardKey.digit8, shift: true, meta: true):
            _EditorToggleListIntent(_ListFormatType.bullet),
        SingleActivator(LogicalKeyboardKey.digit7, shift: true, control: true):
            _EditorToggleListIntent(_ListFormatType.numbered),
        SingleActivator(LogicalKeyboardKey.digit7, shift: true, meta: true):
            _EditorToggleListIntent(_ListFormatType.numbered),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _EditorUndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            _EditorUndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, shift: true, control: true):
            _EditorRedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, shift: true, meta: true):
            _EditorRedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _EditorRedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, meta: true):
            _EditorRedoIntent(),
        SingleActivator(LogicalKeyboardKey.bracketRight, control: true):
            _EditorIndentIntent(increase: true),
        SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):
            _EditorIndentIntent(increase: true),
        SingleActivator(LogicalKeyboardKey.bracketLeft, control: true):
            _EditorIndentIntent(increase: false),
        SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            _EditorIndentIntent(increase: false),
      },
      child: Actions(
        actions: {
          _EditorSaveIntent: CallbackAction<_EditorSaveIntent>(
            onInvoke: (intent) {
              _saveNodeNow(source: 'manual');
              return null;
            },
          ),
          _EditorSelectAllIntent: CallbackAction<_EditorSelectAllIntent>(
            onInvoke: (intent) {
              if (!_editorFocusNode.hasFocus) return null;
              _selectAllInEditor();
              return null;
            },
          ),
          _EditorToggleInlineIntent: CallbackAction<_EditorToggleInlineIntent>(
            onInvoke: (intent) {
              if (!_editorFocusNode.hasFocus) return null;
              _toggleInlineFormat(intent.type);
              return null;
            },
          ),
          _EditorToggleListIntent: CallbackAction<_EditorToggleListIntent>(
            onInvoke: (intent) {
              if (!_editorFocusNode.hasFocus) return null;
              _toggleListFormat(intent.type);
              return null;
            },
          ),
          _EditorIndentIntent: CallbackAction<_EditorIndentIntent>(
            onInvoke: (intent) {
              if (!_editorFocusNode.hasFocus) return null;
              _indentSelection(increase: intent.increase);
              return null;
            },
          ),
          _EditorUndoIntent: CallbackAction<_EditorUndoIntent>(
            onInvoke: (intent) {
              if (!_editorFocusNode.hasFocus) return null;
              _undoEditorChange();
              return null;
            },
          ),
          _EditorRedoIntent: CallbackAction<_EditorRedoIntent>(
            onInvoke: (intent) {
              if (!_editorFocusNode.hasFocus) return null;
              _redoEditorChange();
              return null;
            },
          ),
          _EditorInsertLinkIntent: CallbackAction<_EditorInsertLinkIntent>(
            onInvoke: (intent) {
              if (!_editorFocusNode.hasFocus) return null;
              _insertLinkFromShortcut();
              return null;
            },
          ),
        },
        child: _surface(
          child: TapRegion(
            groupId: _editorInteractionTapGroup,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactHeight = constraints.maxHeight < 520;
                final minimalHeight = constraints.maxHeight < 320;
                final showRibbon =
                    !_isEditorReadOnly && !minimalHeight && _showRibbon;
                return Stack(
                  children: [
                    Column(
                      children: [
                        if (showRibbon) _editorGroupedHomeToolbar(),
                        if (!showRibbon &&
                            !_isEditorReadOnly &&
                            !minimalHeight &&
                            _showRibbon == false)
                          _editorCollapsedRibbonStrip(),
                        if (_isEditorReadOnly && !compactHeight)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                            color: _primary.withValues(alpha: 0.05),
                            child: Text(
                              _editorReadOnlyMessage,
                              style: TextStyle(
                                color: _primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              if (_isEditorReadOnly ||
                                  _isTableCellEditing ||
                                  _selectedNode == null) {
                                return;
                              }
                              if (_imageInteractionMode) {
                                // Let Quill onTapDown decide whether to keep or exit image mode.
                                // Avoid competing focus changes here.
                                return;
                              }
                              _editorController.skipRequestKeyboard = false;
                              _editorFocusNode.requestFocus();
                            },
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F6F5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Container(
                                        constraints: BoxConstraints(
                                          maxWidth: paperMaxWidth,
                                        ),
                                        margin: const EdgeInsets.fromLTRB(
                                          18,
                                          14,
                                          18,
                                          14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.black.withValues(
                                              alpha: 0.08,
                                            ),
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x12000000),
                                              blurRadius: 16,
                                              offset: Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          children: [
                                            if (!_isEditorReadOnly) ...[
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      22,
                                                      10,
                                                      22,
                                                      6,
                                                    ),
                                                child: LayoutBuilder(
                                                  builder: (context, titleConstraints) {
                                                    final compactTitleRow =
                                                        titleConstraints
                                                            .maxWidth <
                                                        860;
                                                    final titleField = Row(
                                                      children: [
                                                        if (showTitleSectionNumber) ...[
                                                          Text(
                                                            '$selectedSectionNumber. ',
                                                            style:
                                                                const TextStyle(
                                                                  color: _text,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                  fontSize: 22,
                                                                ),
                                                          ),
                                                        ],
                                                        Expanded(
                                                          child: TextField(
                                                            controller:
                                                                _titleCtrl,
                                                            readOnly:
                                                                _isEditorReadOnly,
                                                            style:
                                                                const TextStyle(
                                                                  color: _text,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                  fontSize: 22,
                                                                ),
                                                            decoration: const InputDecoration(
                                                              border:
                                                                  InputBorder
                                                                      .none,
                                                              enabledBorder:
                                                                  InputBorder
                                                                      .none,
                                                              focusedBorder:
                                                                  InputBorder
                                                                      .none,
                                                              disabledBorder:
                                                                  InputBorder
                                                                      .none,
                                                              filled: false,
                                                              isDense: true,
                                                              contentPadding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              hintText:
                                                                  'Node title',
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                    final toggle = Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Text(
                                                          'Section',
                                                          style: TextStyle(
                                                            color: _muted,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Switch.adaptive(
                                                          value:
                                                              _useSectionNumbering,
                                                          onChanged:
                                                              _isEditorReadOnly
                                                              ? null
                                                              : (value) {
                                                                  setState(() {
                                                                    _useSectionNumbering =
                                                                        value;
                                                                  });
                                                                },
                                                        ),
                                                      ],
                                                    );

                                                    if (compactTitleRow) {
                                                      return Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          titleField,
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Align(
                                                            alignment: Alignment
                                                                .centerRight,
                                                            child: toggle,
                                                          ),
                                                        ],
                                                      );
                                                    }
                                                    return Row(
                                                      children: [
                                                        Expanded(
                                                          child: titleField,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        toggle,
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ),
                                              Divider(
                                                height: 1,
                                                color: Colors.black.withValues(
                                                  alpha: 0.08,
                                                ),
                                              ),
                                            ],
                                            Expanded(
                                              child: ListenableBuilder(
                                                listenable: _editorController,
                                                child: MediaQuery(
                                                  data: MediaQuery.of(context)
                                                      .copyWith(
                                                        textScaler:
                                                            TextScaler.linear(
                                                              _paperZoom,
                                                            ),
                                                      ),
                                                  child: editorWidget,
                                                ),
                                                builder: (context, child) {
                                                  final plain =
                                                      _editorController.document
                                                          .toPlainText()
                                                          .replaceAll('\n', '')
                                                          .trim();
                                                  final showEmptyHint =
                                                      plain.isEmpty &&
                                                      !_isEditorReadOnly;
                                                  return Stack(
                                                    children: [
                                                      Positioned.fill(
                                                        child: child!,
                                                      ),
                                                      if (showEmptyHint)
                                                        const IgnorePointer(
                                                          child: Padding(
                                                            padding:
                                                                EdgeInsets.fromLTRB(
                                                                  38,
                                                                  30,
                                                                  38,
                                                                  24,
                                                                ),
                                                            child: Align(
                                                              alignment:
                                                                  Alignment
                                                                      .topLeft,
                                                              child: Text(
                                                                'Start writing this handbook section...',
                                                                style: TextStyle(
                                                                  color: _muted,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize: 15,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (!compactHeight && !_isEditorReadOnly)
                          _editorStatusBar(),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _editorStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      child: ValueListenableBuilder<_EditorSaveViewState>(
        valueListenable: _saveViewState,
        builder: (context, saveState, child) {
          const baseStyle = TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 980;
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _shortcutsInfoButton(),
                            const SizedBox(width: 6),
                            const Text(
                              'Editing entry content',
                              style: baseStyle,
                            ),
                          ],
                        ),
                        Text(
                          saveState.autoSaveEnabled
                              ? 'Autosave on'
                              : 'Autosave off',
                          style: baseStyle,
                        ),
                        Text(
                          saveState.message,
                          style: TextStyle(
                            color: saveState.isSaving ? _primary : _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text(
                          'Paper zoom',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _paperZoomControl(compact: true),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  _shortcutsInfoButton(),
                  const SizedBox(width: 6),
                  const Text('Editing entry content', style: baseStyle),
                  const Spacer(),
                  const Text(
                    'Paper zoom',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _paperZoomControl(),
                  const SizedBox(width: 12),
                  Text(
                    saveState.autoSaveEnabled ? 'Autosave on' : 'Autosave off',
                    style: baseStyle,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    saveState.message,
                    style: TextStyle(
                      color: saveState.isSaving ? _primary : _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

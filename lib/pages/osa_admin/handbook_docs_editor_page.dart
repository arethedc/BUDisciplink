import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:apps/models/handbook_node_doc.dart';
import 'package:apps/pages/shared/handbook/hb_handbook_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart'
    as quill_ext;

const String _tableEmbedType = 'x-embed-table';
const double _tableMaxColWidth = 2000;

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
        _ => 'left',
      };
      if (!bold && !italic && align == 'left') continue;
      normalized['$row:$col'] = {
        'bold': bold,
        'italic': italic,
        'align': align,
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
  });

  final void Function(int offset, Map<String, dynamic> payload) onDraftChanged;
  final void Function(int offset, Map<String, dynamic> payload)
  onCommitRequested;
  final void Function(int offset) onDeleteRequested;
  final void Function(bool editing) onEditingStateChanged;

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
  });

  final int offset;
  final Map<String, dynamic> payload;
  final bool readOnly;
  final void Function(int offset, Map<String, dynamic> payload) onDraftChanged;
  final void Function(int offset, Map<String, dynamic> payload)
  onCommitRequested;
  final void Function(int offset) onDeleteRequested;
  final void Function(bool editing) onEditingStateChanged;

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

  late List<String> _headers;
  late List<List<String>> _rows;
  late List<double> _columnWidths;
  late Map<String, Map<String, dynamic>> _cellStyles;
  bool _selected = false;
  bool _hovered = false;
  bool _optionsMenuOpen = false;
  int _activeRow = 0;
  int _activeCol = 0;

  @override
  void initState() {
    super.initState();
    _loadFromPayload(widget.payload);
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
      if (node.hasFocus) {
        widget.onEditingStateChanged(true);
        _selected = true;
        _activeRow = row;
        _activeCol = col;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_anyCellHasFocus() && !_optionsMenuOpen) {
            widget.onEditingStateChanged(false);
            _commitNow();
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
    final payload = {
      'headers': _headers,
      'rows': _rows,
      'columnWidths': _columnWidths,
      'cellStyles': _cellStyles,
    };
    widget.onCommitRequested(widget.offset, payload);
  }

  void _clearTableInteraction({bool commit = true}) {
    var hadFocus = false;
    final hadSelection = _selected;
    for (final node in _cellFocusNodes.values) {
      if (node.hasFocus) {
        hadFocus = true;
        node.unfocus();
      }
    }
    _tableFocusNode.unfocus();
    widget.onEditingStateChanged(false);
    _selected = false;
    _hovered = false;
    if (commit && (hadFocus || hadSelection)) {
      _commitNow();
    }
    if (mounted) setState(() {});
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
      _ => TextAlign.left,
    };
  }

  void _setActiveCellStyle({bool? bold, bool? italic, String? align}) {
    if (_activeRow < 0 ||
        _activeRow >= _rows.length ||
        _activeCol < 0 ||
        _activeCol >= _headers.length) {
      return;
    }
    _ensureMutableTableState();
    final key = _styleKey(_activeRow, _activeCol);
    final next = Map<String, dynamic>.from(_cellStyles[key] ?? const {});
    if (bold != null) next['bold'] = bold;
    if (italic != null) next['italic'] = italic;
    if (align != null) {
      next['align'] = switch (align) {
        'center' => 'center',
        'right' => 'right',
        _ => 'left',
      };
    }
    final normalized = {
      'bold': next['bold'] == true,
      'italic': next['italic'] == true,
      'align': (next['align'] ?? 'left').toString(),
    };
    final isDefault =
        normalized['bold'] == false &&
        normalized['italic'] == false &&
        normalized['align'] == 'left';
    if (isDefault) {
      _cellStyles.remove(key);
    } else {
      _cellStyles[key] = normalized;
    }
    _emitDraft();
    _commitNow();
    if (mounted) setState(() {});
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
    _commitNow();
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
    _commitNow();
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
    _commitNow();
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
    _commitNow();
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

  Widget _cellFormatButton({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 17,
          onPressed: onPressed,
          color: active ? const Color(0xFF1B5E20) : const Color(0xFF6D7F62),
          style: IconButton.styleFrom(
            backgroundColor: active
                ? const Color(0xFF1B5E20).withValues(alpha: 0.12)
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(icon),
        ),
      ),
    );
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
    final hasActiveCell =
        _activeRow >= 0 &&
        _activeRow < _rows.length &&
        _activeCol >= 0 &&
        _activeCol < _headers.length;
    final activeBold = hasActiveCell
        ? _cellBold(_activeRow, _activeCol)
        : false;
    final activeItalic = hasActiveCell
        ? _cellItalic(_activeRow, _activeCol)
        : false;
    final activeAlign = hasActiveCell
        ? _cellAlign(_activeRow, _activeCol)
        : TextAlign.left;
    return TapRegion(
      onTapOutside: (_) {
        if (_optionsMenuOpen) return;
        if (!_anyCellHasFocus() && !_selected) return;
        _clearTableInteraction();
      },
      child: Focus(
        focusNode: _tableFocusNode,
        onFocusChange: (focused) {
          if (!focused) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_anyCellHasFocus() && !_optionsMenuOpen) {
                widget.onEditingStateChanged(false);
                _selected = false;
                _commitNow();
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
                      color: _selected
                          ? const Color(0xFF1B5E20)
                          : Colors.black.withValues(alpha: 0.10),
                      width: _selected ? 1.6 : 1,
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SingleChildScrollView(
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
                                children: List.generate(_headers.length, (col) {
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
                                  final isActiveCell =
                                      row == _activeRow && col == _activeCol;
                                  final cellBold = _cellBold(row, col);
                                  final cellItalic = _cellItalic(row, col);
                                  final cellAlign = _cellAlign(row, col);
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 90,
                                            ),
                                            color: isActiveCell
                                                ? const Color(
                                                    0xFF1B5E20,
                                                  ).withValues(alpha: 0.08)
                                                : Colors.transparent,
                                          ),
                                        ),
                                      ),
                                      Focus(
                                        onKeyEvent: (focusNode, event) =>
                                            _handleCellKey(
                                              event: event,
                                              isHeader: false,
                                              row: row,
                                              col: col,
                                            ),
                                        child: TextField(
                                          readOnly: widget.readOnly,
                                          controller: ctrl,
                                          focusNode: node,
                                          textAlign: cellAlign,
                                          minLines: 1,
                                          maxLines: null,
                                          keyboardType: TextInputType.multiline,
                                          textInputAction:
                                              TextInputAction.newline,
                                          onTap: () {
                                            _selected = true;
                                            _activeRow = row;
                                            _activeCol = col;
                                            widget.onEditingStateChanged(true);
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
                                            contentPadding: EdgeInsets.fromLTRB(
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
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onHorizontalDragUpdate: (details) {
                                                final next =
                                                    (_columnWidths[col] == 0
                                                        ? widths[col]
                                                        : _columnWidths[col]) +
                                                    details.delta.dx;
                                                _columnWidths[col] = next.clamp(
                                                  _minColWidth,
                                                  _maxColWidth,
                                                );
                                                _emitDraft();
                                                if (mounted) setState(() {});
                                              },
                                              onHorizontalDragEnd: (_) {
                                                _commitNow();
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
                                if (hasActiveCell) ...[
                                  _cellFormatButton(
                                    icon: Icons.format_bold_rounded,
                                    tooltip: 'Bold cell',
                                    active: activeBold,
                                    onPressed: () =>
                                        _setActiveCellStyle(bold: !activeBold),
                                  ),
                                  _cellFormatButton(
                                    icon: Icons.format_italic_rounded,
                                    tooltip: 'Italic cell',
                                    active: activeItalic,
                                    onPressed: () => _setActiveCellStyle(
                                      italic: !activeItalic,
                                    ),
                                  ),
                                  _cellFormatButton(
                                    icon: Icons.format_align_left_rounded,
                                    tooltip: 'Align left',
                                    active: activeAlign == TextAlign.left,
                                    onPressed: () =>
                                        _setActiveCellStyle(align: 'left'),
                                  ),
                                  _cellFormatButton(
                                    icon: Icons.format_align_center_rounded,
                                    tooltip: 'Align center',
                                    active: activeAlign == TextAlign.center,
                                    onPressed: () =>
                                        _setActiveCellStyle(align: 'center'),
                                  ),
                                  _cellFormatButton(
                                    icon: Icons.format_align_right_rounded,
                                    tooltip: 'Align right',
                                    active: activeAlign == TextAlign.right,
                                    onPressed: () =>
                                        _setActiveCellStyle(align: 'right'),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 20,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    color: Colors.black.withValues(alpha: 0.12),
                                  ),
                                ],
                                Tooltip(
                                  message: 'Move table',
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.move,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        _selected = true;
                                        if (mounted) setState(() {});
                                      },
                                      child: IconButton(
                                        tooltip: 'Move table',
                                        onPressed: () {
                                          _selected = true;
                                          if (mounted) setState(() {});
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
                                      _selected = true;
                                      widget.onEditingStateChanged(true);
                                      if (mounted) setState(() {});
                                    },
                                    onCanceled: () {
                                      _optionsMenuOpen = false;
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (!_anyCellHasFocus()) {
                                              widget.onEditingStateChanged(
                                                false,
                                              );
                                              _commitNow();
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

  const HandbookDocsEditorPage({super.key, this.onBack});

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
                final imageCard = SizedBox(width: safeWidth, child: imageFrame);
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
                  children: [
                    SizedBox(width: safeWidth, child: imageFrame),
                    captionWidget,
                  ],
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

    return Stack(
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
            child: Transform.rotate(
              angle: rotationDegrees * math.pi / 180,
              child: croppedImage,
            ),
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

class _ImageCropPreview extends StatelessWidget {
  const _ImageCropPreview({
    required this.imageSource,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
  });

  final String imageSource;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;

  @override
  Widget build(BuildContext context) {
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

    final previewImage = _buildImage();
    return ClipRect(
      child: Align(
        alignment: Alignment(alignmentX, alignmentY),
        widthFactor: visibleWidthFactor,
        heightFactor: visibleHeightFactor,
        child: previewImage,
      ),
    );
  }

  Widget _buildImage() {
    final bytes = _tryDecodeDataUri(imageSource);
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity);
    }
    return Image.network(
      imageSource,
      fit: BoxFit.cover,
      width: double.infinity,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => Container(
        alignment: Alignment.center,
        color: const Color(0xFFF2F2F2),
        child: const Text(
          'Image preview unavailable',
          style: TextStyle(
            color: Color(0xFF6D7F62),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Uint8List? _tryDecodeDataUri(String source) {
    if (!source.startsWith('data:image/')) return null;
    final commaIndex = source.indexOf(',');
    if (commaIndex < 0 || commaIndex >= source.length - 1) return null;
    final encoded = source.substring(commaIndex + 1);
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

enum _InlineFormatType { bold, italic, underline }

class _EditorToggleInlineIntent extends Intent {
  const _EditorToggleInlineIntent(this.type);

  final _InlineFormatType type;
}

enum _ListFormatType { bullet, numbered }

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

class _HandbookDocsEditorPageState extends State<HandbookDocsEditorPage> {
  static const _bg = Color(0xFFF6FAF6);
  static const _primary = Color(0xFF1B5E20);
  static const _text = Color(0xFF1F2A1F);
  static const _muted = Color(0xFF6D7F62);
  static const _colHbVersion = 'hb_version';
  static const _colHbSection = 'hb_section';
  static const _colHbContents = 'hb_contents';
  static const _autosaveDebounce = Duration(seconds: 2);

  final _db = FirebaseFirestore.instance;
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
  bool _isTableCellEditing = false;

  bool _loadingContext = true;
  String? _contextError;
  String? _handbookId;
  String _handbookVersion = '--';
  String _editingVersionStatus = 'draft';
  String _treeSnapshotSignature = '';

  List<HandbookNodeDoc> _nodes = const [];
  final Set<String> _expandedNodeIds = <String>{};
  String? _selectedNodeId;
  int? _activeImageOffset;
  bool _imageCropMode = false;
  bool _imageInteractionMode = false;
  bool _previewMode = false;
  final bool _enableImageBehavior = false;
  bool _useSectionNumbering = true;

  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  bool _suppressDirty = false;
  bool _autoSaveEnabled = false;
  Future<void>? _saveInFlight;
  int _editVersion = 0;
  int _switchVersion = 0;
  bool _isRootReordering = false;
  DateTime _sectionTapLockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String _saveMessage = 'Saved';
  String _query = '';

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
      ),
      ...fallbackBuilders.where(
        (builder) =>
            builder.key != quill.BlockEmbed.imageType &&
            builder.key != _tableEmbedType,
      ),
    ];
    _bindEditorDocChanges();
    _titleCtrl.addListener(_onMetaChanged);
    _publishSaveViewState();
    _loadContext();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _imageStyleFlushTimer?.cancel();
    _pendingTablePayloadByOffset.clear();
    _docChangeSub?.cancel();
    _nodeSub?.cancel();
    _editorController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _saveViewState.dispose();
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
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

  Future<String> _loadVersionStatus(String versionId) async {
    final id = versionId.trim();
    if (id.isEmpty || id == 'current') return 'draft';
    final hbDoc = await _db.collection(_colHbVersion).doc(id).get();
    if (hbDoc.exists) {
      final hbData = hbDoc.data() ?? const <String, dynamic>{};
      return _normalizeVersionWorkflowStatus(
        (hbData['status'] ?? 'draft').toString(),
      );
    }
    return 'draft';
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
          'No editing version selected. Open Manage Handbook and click Edit Version.',
        );
      }
      final editingLabel =
          (data['editingVersionLabel'] ??
                  (editingVersion == activeVersion
                      ? activeLabel
                      : editingVersion))
              .toString()
              .trim();

      final editingStatus = await _loadVersionStatus(editingVersion);

      if (!mounted) return;
      setState(() {
        _handbookId = editingVersion;
        _handbookVersion = editingLabel;
        _editingVersionStatus = editingStatus;
        _loadingContext = false;
      });
      _bindNodes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contextError = e.toString();
        _loadingContext = false;
      });
    }
  }

  String _normalizeVersionWorkflowStatus(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(' ', '_');
    switch (value) {
      case 'draft':
      case 'under_review':
      case 'approved':
      case 'active':
      case 'archived':
      case 'published':
        return value;
      default:
        return 'draft';
    }
  }

  String _workflowStatusLabel(String status) {
    switch (_normalizeVersionWorkflowStatus(status)) {
      case 'draft':
        return 'Draft';
      case 'under_review':
        return 'Under Review';
      case 'approved':
        return 'Approved';
      case 'active':
        return 'Active';
      case 'archived':
        return 'Archived';
      case 'published':
        return 'Published';
      default:
        return 'Draft';
    }
  }

  bool get _isWorkflowReadOnly {
    final status = _normalizeVersionWorkflowStatus(_editingVersionStatus);
    return status == 'active' || status == 'published' || status == 'archived';
  }

  bool get _isEditorReadOnly => _previewMode || _isWorkflowReadOnly;

  String get _editorReadOnlyMessage {
    if (_previewMode) return 'Preview mode - read-only';
    return 'This handbook version is read-only.';
  }

  void _showReadOnlyVersionWarning() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This handbook version is read-only. Select a draft to edit.',
        ),
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

  Future<void> _switchToNode(String nodeId, {bool force = false}) async {
    if (!force && nodeId == _selectedNodeId) return;
    final switchVersion = ++_switchVersion;
    await _saveNodeNow();
    if (!mounted || switchVersion != _switchVersion) return;
    final node = _nodeById(nodeId);
    if (node == null) return;
    await _loadNodeToEditor(node);
  }

  Future<void> _loadNodeToEditor(HandbookNodeDoc node) async {
    var resolvedContent = node.content;
    var resolvedAttachments = <Map<String, dynamic>>[];
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
      final rawAttachments = (contentData['attachments'] as List?) ?? const [];
      resolvedAttachments = rawAttachments
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {}

    final oldController = _editorController;
    final document = _parseDocument(resolvedContent);
    _pendingTablePayloadByOffset.clear();
    _isTableCellEditing = false;
    _previewMode = false;
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
      _previewMode = false;
      _suppressDirty = true;
      _titleCtrl.text = node.title;
      _useSectionNumbering = node.useSectionNumbering;
      _attachments = List<Map<String, dynamic>>.from(resolvedAttachments);
      _hasUnsavedChanges = false;
      _saveMessage = 'Saved';
      _expandedNodeIds.add(node.parentId);
      _suppressDirty = false;
    });
    _publishSaveViewState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
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
    if (!_autoSaveEnabled || !_hasUnsavedChanges) return;
    if (_isTableCellEditing) return;
    _autosaveTimer = Timer(_autosaveDebounce, _saveNodeNow);
  }

  void _markDirtyAndSchedule() {
    if (_selectedNode == null) return;
    _editVersion += 1;
    final shouldRefreshStatus =
        !_hasUnsavedChanges || _saveMessage == 'Saved' || _saveMessage == '';
    _hasUnsavedChanges = true;
    if (shouldRefreshStatus) {
      _saveMessage = 'Unsaved changes';
      _publishSaveViewState();
    }
    _scheduleAutosaveDebounced();
  }

  Future<void> _saveNodeNow() async {
    if (_isWorkflowReadOnly) {
      _autosaveTimer?.cancel();
      if (_saveMessage != 'Read-only version' || _hasUnsavedChanges) {
        _hasUnsavedChanges = false;
        _saveMessage = 'Read-only version';
        _publishSaveViewState();
      }
      return;
    }
    if (_isSaving) {
      final inFlight = _saveInFlight;
      if (inFlight != null) {
        await inFlight;
      }
      if (!_hasUnsavedChanges) return;
    }
    if (!_hasUnsavedChanges) return;
    final selected = _selectedNode;
    if (selected == null) return;

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
      if (!stillCurrentNode || changedDuringSave) {
        _hasUnsavedChanges = true;
        _saveMessage = 'Unsaved changes';
      } else {
        _hasUnsavedChanges = false;
        _saveMessage = 'Saved';
      }
      _publishSaveViewState();
    } catch (e) {
      if (!mounted) return;
      _saveMessage = 'Save failed';
      _publishSaveViewState();
      ScaffoldMessenger.of(
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

  void _syncEditorReadOnlyState() {
    _editorController.readOnly = _isEditorReadOnly;
  }

  Future<void> _togglePreviewMode() async {
    if (!_previewMode) {
      await _saveNodeNow();
      if (!mounted) return;
    }
    setState(() {
      _previewMode = !_previewMode;
      _syncEditorReadOnlyState();
    });
  }

  KeyEventResult _handleEditorKeyPress(KeyEvent event) {
    if (_isTableCellEditing) {
      // Never consume keys here while editing table cells.
      return KeyEventResult.ignored;
    }
    return _handleEditorBackspace(event);
  }

  void _toggleInlineFormat(_InlineFormatType type) {
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    final attribute = switch (type) {
      _InlineFormatType.bold => quill.Attribute.bold,
      _InlineFormatType.italic => quill.Attribute.italic,
      _InlineFormatType.underline => quill.Attribute.underline,
    };
    final active = _editorController.getSelectionStyle().attributes.containsKey(
      attribute.key,
    );
    _editorController.formatSelection(
      active ? quill.Attribute.clone(attribute, null) : attribute,
    );
  }

  void _toggleListFormat(_ListFormatType type) {
    if (!_canEditDocumentActions) return;
    _editorFocusNode.requestFocus();
    final attribute = switch (type) {
      _ListFormatType.bullet => quill.Attribute.ul,
      _ListFormatType.numbered => quill.Attribute.ol,
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

    final plainText = _editorController.document.toPlainText();
    final caret = selection.baseOffset;
    if (caret > plainText.length) return KeyEventResult.ignored;
    final lineStart = plainText.lastIndexOf('\n', caret - 1) + 1;
    if (caret != lineStart) return KeyEventResult.ignored;

    final attrs = _editorController.getSelectionStyle().attributes;
    final hasIndent = attrs.containsKey(quill.Attribute.indent.key);
    final hasList = attrs.containsKey(quill.Attribute.list.key);
    if (hasIndent || hasList) {
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

  Future<void> _createNode({required String parentId}) async {
    if (_isWorkflowReadOnly) {
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
            return AlertDialog(
              title: const Text('Create entry'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Entry title',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
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
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Create'),
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
    if (_isWorkflowReadOnly) {
      _showReadOnlyVersionWarning();
      return;
    }
    final target = _nodeById(nodeId);
    if (target == null) return;
    final descendants = _collectDescendants(nodeId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete node'),
          content: Text(
            descendants.isEmpty
                ? 'Delete "${target.title}"?'
                : 'Delete "${target.title}" and ${descendants.length} nested nodes?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final batch = _db.batch();
    batch.delete(_db.collection(_colHbSection).doc(nodeId));
    batch.delete(_db.collection(_colHbContents).doc(nodeId));
    for (final child in descendants) {
      batch.delete(_db.collection(_colHbSection).doc(child.id));
      batch.delete(_db.collection(_colHbContents).doc(child.id));
    }
    await batch.commit();

    if (!mounted) return;
    if (_selectedNodeId == nodeId) setState(() => _selectedNodeId = null);
  }

  Future<void> _reorderRootNodes(int oldIndex, int newIndex) async {
    if (_isWorkflowReadOnly) {
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
      ScaffoldMessenger.of(
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
            return AlertDialog(
              title: const Text('Insert table'),
              content: Column(
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
                    decoration: const InputDecoration(
                      labelText: 'Columns',
                      border: OutlineInputBorder(),
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
                    decoration: const InputDecoration(
                      labelText: 'Rows',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Insert'),
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
    _flushPendingTablePayloads(onlyOffsets: {offset});
  }

  void _onTableDeleteRequested(int offset) {
    final resolved = _resolveTableOffset(offset);
    if (resolved == null) return;
    _pendingTablePayloadByOffset.remove(offset);
    _editorController.replaceText(
      resolved,
      1,
      '',
      TextSelection.collapsed(offset: math.max(0, resolved - 1)),
    );
    _markDirtyAndSchedule();
  }

  void _onTableEditingStateChanged(bool editing) {
    if (_isTableCellEditing == editing) return;
    setState(() {
      _isTableCellEditing = editing;
    });
    _syncEditorReadOnlyState();
    if (editing) {
      _editorController.skipRequestKeyboard = true;
      _editorFocusNode.unfocus();
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
          TextSelection.collapsed(offset: resolved + 1),
        );
        _pendingTablePayloadByOffset.remove(rawOffset);
      }
    } finally {
      _suppressDirty = previousSuppress;
      if (selectionBefore.isValid) {
        _editorController.updateSelection(
          selectionBefore,
          quill.ChangeSource.local,
        );
      }
    }
  }

  quill.OffsetValue<quill.Embed>? _selectedImageEmbed() {
    try {
      final embedNode = quill.getEmbedNode(
        _editorController,
        _editorController.selection.start,
      );
      if (embedNode.value.value.type == quill.BlockEmbed.imageType) {
        return embedNode;
      }
    } catch (_) {}
    return null;
  }

  void _onImageOffsetSelected(int imageOffset) {
    if (_previewMode) return;
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
  }

  void _setImageInteractionMode(bool enabled) {
    if (_imageInteractionMode == enabled) return;
    setState(() {
      _imageInteractionMode = enabled;
      if (!enabled) {
        _imageCropMode = false;
        _activeImageOffset = null;
      }
    });
    if (!enabled) {
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
    if (_previewMode || handle == _ImageHandleKind.rotate) return;
    if (_activeImageOffset != offset || !_imageInteractionMode) {
      setState(() {
        _activeImageOffset = offset;
        _imageInteractionMode = true;
      });
    }
    _editorFocusNode.unfocus();
    _editorController.skipRequestKeyboard = true;

    final currentWidth = (_readImageWidth(offset) ?? 420).clamp(120, 1400);
    final currentHeight = (_readImageHeight(offset) ?? (currentWidth * 0.62))
        .clamp(90, 1400);
    final styleMap = _imageStyleMap(offset);

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

    var width = currentWidth.toDouble();
    var height = currentHeight.toDouble();

    if (_isHorizontalHandle(handle)) {
      if (_isRightHandle(handle)) width += delta.dx;
      if (_isLeftHandle(handle)) width -= delta.dx;
    }
    if (_isVerticalHandle(handle)) {
      if (_isBottomHandle(handle)) height += delta.dy;
      if (_isTopHandle(handle)) height -= delta.dy;
    }

    final updatedStyle = _imageStyleMap(offset);
    updatedStyle['width'] = width.clamp(120, 1400).toStringAsFixed(0);
    updatedStyle['height'] = height.clamp(90, 1400).toStringAsFixed(0);
    _setImageStyleMapThrottled(offset, updatedStyle);
  }

  void _onImageRotateDrag(int offset, double degreeDelta) {
    if (_previewMode) return;
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

  void _openImageCropEditor(int offset) {
    final styleMap = _imageStyleMap(offset);
    var cropLeft = _styleDouble(styleMap, 'cropLeft').clamp(0.0, 0.45);
    var cropTop = _styleDouble(styleMap, 'cropTop').clamp(0.0, 0.45);
    var cropRight = _styleDouble(styleMap, 'cropRight').clamp(0.0, 0.45);
    var cropBottom = _styleDouble(styleMap, 'cropBottom').clamp(0.0, 0.45);

    final imageSource = _imageSourceAtOffset(offset);
    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void normalizeCrop() {
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
            }

            void updateCropValues() {
              normalizeCrop();
              final updatedStyle = _imageStyleMap(offset);
              updatedStyle['cropLeft'] = cropLeft.toStringAsFixed(3);
              updatedStyle['cropTop'] = cropTop.toStringAsFixed(3);
              updatedStyle['cropRight'] = cropRight.toStringAsFixed(3);
              updatedStyle['cropBottom'] = cropBottom.toStringAsFixed(3);
              _setImageStyleMap(offset, updatedStyle);
            }

            return AlertDialog(
              title: const Text('Crop image'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageSource.isNotEmpty)
                        Container(
                          height: 190,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F4F3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: _ImageCropPreview(
                            imageSource: imageSource,
                            cropLeft: cropLeft,
                            cropTop: cropTop,
                            cropRight: cropRight,
                            cropBottom: cropBottom,
                          ),
                        ),
                      const SizedBox(height: 10),
                      _cropSlider(
                        label: 'Left',
                        value: cropLeft,
                        onChanged: (value) {
                          setDialogState(() {
                            cropLeft = value;
                            normalizeCrop();
                          });
                          updateCropValues();
                        },
                      ),
                      _cropSlider(
                        label: 'Top',
                        value: cropTop,
                        onChanged: (value) {
                          setDialogState(() {
                            cropTop = value;
                            normalizeCrop();
                          });
                          updateCropValues();
                        },
                      ),
                      _cropSlider(
                        label: 'Right',
                        value: cropRight,
                        onChanged: (value) {
                          setDialogState(() {
                            cropRight = value;
                            normalizeCrop();
                          });
                          updateCropValues();
                        },
                      ),
                      _cropSlider(
                        label: 'Bottom',
                        value: cropBottom,
                        onChanged: (value) {
                          setDialogState(() {
                            cropBottom = value;
                            normalizeCrop();
                          });
                          updateCropValues();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    final resetStyle = _imageStyleMap(offset);
                    resetStyle.remove('cropLeft');
                    resetStyle.remove('cropTop');
                    resetStyle.remove('cropRight');
                    resetStyle.remove('cropBottom');
                    _setImageStyleMap(offset, resetStyle);
                    Navigator.pop(context);
                  },
                  child: const Text('Reset'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _imageSourceAtOffset(int offset) {
    final resolvedOffset = _resolveImageOffset(offset) ?? offset;
    final ops = _editorController.document.toDelta().toList();
    var cursor = 0;
    for (final op in ops) {
      final data = op.data;
      if (data is String) {
        cursor += data.length;
        continue;
      }
      if (data is Map) {
        if (cursor == resolvedOffset) {
          final source = data[quill.BlockEmbed.imageType];
          if (source != null) return source.toString();
        }
        cursor += 1;
      }
    }
    return '';
  }

  Widget _cropSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label ${(value * 100).round()}%',
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
        ),
        Slider(
          value: value,
          min: 0,
          max: 0.45,
          divisions: 45,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _showImageLayoutTools() {
    final fallbackOffset = _activeImageOffset ?? _selectedImageEmbed()?.offset;
    if (fallbackOffset != null) {
      _onImageOffsetSelected(fallbackOffset);
    }
    _showImageLayoutSheet(forcedImageOffset: fallbackOffset);
  }

  void _showImageLayoutSheet({int? forcedImageOffset}) {
    final imageOffset =
        forcedImageOffset ??
        _activeImageOffset ??
        _selectedImageEmbed()?.offset;
    if (imageOffset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an image in the editor first.')),
      );
      return;
    }
    _onImageOffsetSelected(imageOffset);
    var previewWidth = _readImageWidth(imageOffset) ?? 360;
    var currentAlignment = _readImageAlignment(imageOffset);
    var currentDisplayMode = _readImageDisplayMode(imageOffset);
    final captionCtrl = TextEditingController(
      text: _readImageCaption(imageOffset),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Image options',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text(
                          'Width',
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${previewWidth.round()} px',
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: previewWidth.clamp(120, 960).toDouble(),
                      min: 120,
                      max: 960,
                      divisions: 84,
                      label: '${previewWidth.round()}',
                      onChanged: (value) =>
                          setSheetState(() => previewWidth = value),
                      onChangeEnd: (value) {
                        _setImageWidth(imageOffset, value);
                      },
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Small'),
                          onPressed: () {
                            _setImageWidth(imageOffset, 220);
                            setSheetState(() => previewWidth = 220);
                          },
                        ),
                        ActionChip(
                          label: const Text('Medium'),
                          onPressed: () {
                            _setImageWidth(imageOffset, 360);
                            setSheetState(() => previewWidth = 360);
                          },
                        ),
                        ActionChip(
                          label: const Text('Large'),
                          onPressed: () {
                            _setImageWidth(imageOffset, 520);
                            setSheetState(() => previewWidth = 520);
                          },
                        ),
                        ActionChip(
                          label: const Text('Reset'),
                          onPressed: () {
                            _clearImageWidth(imageOffset);
                            setSheetState(() => previewWidth = 360);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Alignment',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Left'),
                          selected: currentAlignment == 'left',
                          onSelected: (_) {
                            _setImageAlignment(imageOffset, 'left');
                            setSheetState(() => currentAlignment = 'left');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Center'),
                          selected: currentAlignment == 'center',
                          onSelected: (_) {
                            _setImageAlignment(imageOffset, 'center');
                            setSheetState(() => currentAlignment = 'center');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Right'),
                          selected: currentAlignment == 'right',
                          onSelected: (_) {
                            _setImageAlignment(imageOffset, 'right');
                            setSheetState(() => currentAlignment = 'right');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Display mode',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Inline'),
                          selected: currentDisplayMode == 'inline',
                          onSelected: (_) {
                            _setImageDisplayMode(imageOffset, 'inline');
                            setSheetState(() => currentDisplayMode = 'inline');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Full Width'),
                          selected: currentDisplayMode == 'full',
                          onSelected: (_) {
                            _setImageDisplayMode(imageOffset, 'full');
                            setSheetState(() => currentDisplayMode = 'full');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Side Image'),
                          selected: currentDisplayMode == 'side',
                          onSelected: (_) {
                            _setImageDisplayMode(imageOffset, 'side');
                            setSheetState(() => currentDisplayMode = 'side');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _rotateImageLeft(imageOffset),
                          icon: const Icon(Icons.rotate_left_rounded),
                          label: const Text('Rotate Left'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _rotateImageRight(imageOffset),
                          icon: const Icon(Icons.rotate_right_rounded),
                          label: const Text('Rotate Right'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _openImageCropEditor(imageOffset),
                          icon: const Icon(Icons.crop_rounded),
                          label: const Text('Crop Editor'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: captionCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Caption',
                        hintText: 'Add image caption',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (value) =>
                          _setImageCaption(imageOffset, value),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () =>
                            _setImageCaption(imageOffset, captionCtrl.text),
                        child: const Text('Apply Caption'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(captionCtrl.dispose);
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
    final styleMap = _imageStyleMap(offset);
    styleMap['width'] = width.toStringAsFixed(0);
    _setImageStyleMap(offset, styleMap);
    _markDirtyAndSchedule();
  }

  void _clearImageWidth(int offset) {
    final styleMap = _imageStyleMap(offset);
    styleMap.remove('width');
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

  String _readImageCaption(int offset) {
    final styleMap = _imageStyleMap(offset);
    final raw = (styleMap['caption'] ?? '').trim();
    if (raw.isEmpty) return '';
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
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

  void _setImageCaption(int offset, String caption) {
    final currentStyle = _imageStyleStringAt(offset);
    final encoded = caption.trim().isEmpty
        ? ''
        : Uri.encodeComponent(caption.trim());
    final updatedStyle = encoded.isEmpty
        ? _removeCssStyleKey(currentStyle, 'caption')
        : _upsertCssStyle(currentStyle, 'caption', encoded);
    _safeFormatImage(offset, quill.StyleAttribute(updatedStyle));
    _markDirtyAndSchedule();
  }

  String _removeCssStyleKey(String style, String key) {
    final values = <String, String>{};
    for (final segment in style.split(';')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length < 2) continue;
      final name = parts.first.trim();
      final val = parts.sublist(1).join(':').trim();
      if (name.isNotEmpty && val.isNotEmpty && name != key) {
        values[name] = val;
      }
    }
    return values.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('; ');
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
        return AlertDialog(
          title: const Text('Insert link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasSelection)
                TextField(
                  controller: textCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display text',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              if (!hasSelection) const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Insert'),
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
    _isTableCellEditing = false;
    _previewMode = false;
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
    await _saveNodeNow();
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

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _headerBar(),
            const Divider(height: 1),
            Expanded(
              child: _previewMode
                  ? Builder(
                      builder: (context) {
                        final versionId = (_handbookId ?? '').trim();
                        if (versionId.isEmpty) {
                          return const Center(
                            child: Text(
                              'No version selected for preview.',
                              style: TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: HbHandbookPage(
                            useSidebarDesktop: false,
                            forcedVersionId: versionId,
                            forcedVersionLabel: _handbookVersion,
                            showAiFab: false,
                            hideTopHeader: true,
                          ),
                        );
                      },
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1280;
                        final tablet = constraints.maxWidth >= 980 && !wide;

                        if (wide) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: 330,
                                  child: RepaintBoundary(
                                    child: _leftTreePanel(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: RepaintBoundary(child: _editorPanel()),
                                ),
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
                                SizedBox(
                                  width: 300,
                                  child: RepaintBoundary(
                                    child: _leftTreePanel(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: RepaintBoundary(child: _editorPanel()),
                                ),
                              ],
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Expanded(
                                flex: 6,
                                child: RepaintBoundary(child: _leftTreePanel()),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                flex: 8,
                                child: RepaintBoundary(child: _editorPanel()),
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

  Widget _headerBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: ValueListenableBuilder<_EditorSaveViewState>(
        valueListenable: _saveViewState,
        builder: (context, saveState, child) {
          final editingStatusLabel = _workflowStatusLabel(
            _editingVersionStatus,
          );
          final actionWidgets = <Widget>[
            _statusChip('Version Name', _handbookVersion),
            _statusChip('Status', editingStatusLabel),
            _statusChip(
              'Save',
              saveState.autoSaveEnabled
                  ? 'Auto | ${saveState.message}'
                  : saveState.message,
            ),
            OutlinedButton.icon(
              onPressed: _isWorkflowReadOnly
                  ? null
                  : () {
                      _autoSaveEnabled = !_autoSaveEnabled;
                      if (!_autoSaveEnabled) {
                        _autosaveTimer?.cancel();
                      } else {
                        _scheduleAutosaveDebounced();
                      }
                      _publishSaveViewState();
                    },
              icon: Icon(
                saveState.autoSaveEnabled
                    ? Icons.sync_rounded
                    : Icons.sync_disabled_rounded,
              ),
              label: Text(saveState.autoSaveEnabled ? 'Auto On' : 'Auto Off'),
            ),
            FilledButton.icon(
              onPressed: (_handbookId == null || _handbookId!.trim().isEmpty)
                  ? null
                  : _togglePreviewMode,
              style: FilledButton.styleFrom(backgroundColor: _primary),
              icon: Icon(
                _previewMode ? Icons.edit_rounded : Icons.visibility_rounded,
              ),
              label: Text(_previewMode ? 'Edit' : 'Preview'),
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
                        const Expanded(
                          child: Text(
                            'Manage Handbook',
                            style: TextStyle(
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
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: _primary,
                    ),
                    tooltip: 'Back to Manage Handbook',
                  ),
                  const Icon(Icons.description_rounded, color: _primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Manage Handbook',
                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
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

  Widget _statusChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _primary.withValues(alpha: 0.15)),
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

  Widget _leftTreePanel() {
    final roots = _rootNodes();
    final filteredRoots = roots.where(_matchesNodeOrDescendant).toList();
    final sectionNumbers = _buildRootSectionNumberMap();
    final canReorder = _query.trim().isEmpty && !_isWorkflowReadOnly;
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
                IconButton(
                  onPressed: _isWorkflowReadOnly
                      ? null
                      : () => _createNode(parentId: ''),
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
                  enabled: !_isWorkflowReadOnly,
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

    final currentImageOffset =
        _activeImageOffset ?? _selectedImageEmbed()?.offset;
    final hasSelectedImage = currentImageOffset != null;

    final editorWidget = quill.QuillEditor.basic(
      controller: _editorController,
      focusNode: _editorFocusNode,
      scrollController: _editorScrollController,
      config: quill.QuillEditorConfig(
        scrollable: true,
        autoFocus: false,
        expands: false,
        enableAlwaysIndentOnTab: false,
        onKeyPressed: (event, node) => _handleEditorKeyPress(event),
        showCursor: !_imageInteractionMode && !_isTableCellEditing,
        onTapDown: (details, getPositionForOffset) {
          if (_imageInteractionMode) {
            return true;
          }
          return false;
        },
        padding: const EdgeInsets.fromLTRB(36, 28, 36, 64),
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
              _saveNodeNow();
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactHeight = constraints.maxHeight < 520;
              final minimalHeight = constraints.maxHeight < 320;
              return Column(
                children: [
                  if (!minimalHeight)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _titleCtrl,
                                  readOnly: _isWorkflowReadOnly,
                                  style: const TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 24,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Node title',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Tooltip(
                                message: 'Section Numbering',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.format_list_numbered_rounded,
                                      size: 18,
                                      color: _muted.withValues(alpha: 0.9),
                                    ),
                                    const SizedBox(width: 4),
                                    Switch.adaptive(
                                      value: _useSectionNumbering,
                                      onChanged: _isWorkflowReadOnly
                                          ? null
                                          : (value) {
                                              if (_useSectionNumbering ==
                                                  value) {
                                                return;
                                              }
                                              setState(() {
                                                _useSectionNumbering = value;
                                              });
                                              _markDirtyAndSchedule();
                                            },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (!minimalHeight) const Divider(height: 1),
                  if (!_isEditorReadOnly && !compactHeight)
                    quill.QuillSimpleToolbar(
                      controller: _editorController,
                      config: quill.QuillSimpleToolbarConfig(
                        showBoldButton: true,
                        showItalicButton: true,
                        showUnderLineButton: true,
                        showStrikeThrough: true,
                        showHeaderStyle: true,
                        showListBullets: true,
                        showListNumbers: true,
                        showListCheck: true,
                        showIndent: true,
                        showQuote: true,
                        showLink: true,
                        showCodeBlock: true,
                        showInlineCode: false,
                        showClearFormat: true,
                        showLineHeightButton: true,
                        showAlignmentButtons: true,
                        showLeftAlignment: true,
                        showCenterAlignment: true,
                        showRightAlignment: true,
                        showJustifyAlignment: true,
                        showSearchButton: false,
                        showDirection: false,
                        showSubscript: false,
                        showSuperscript: false,
                        showFontFamily: false,
                        showFontSize: true,
                        showClipboardCut: true,
                        showClipboardCopy: true,
                        showClipboardPaste: true,
                        showUndo: true,
                        showRedo: true,
                        multiRowsDisplay: false,
                      ),
                    ),
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
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      10,
                      compactHeight ? 4 : 6,
                      10,
                      compactHeight ? 4 : 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                PopupMenuButton<String>(
                                  enabled: !_isEditorReadOnly,
                                  onSelected: _handleInsertAction,
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'table',
                                      child: Text('Table'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'link',
                                      child: Text('Hyperlink'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'attachment',
                                      child: Text('Attachment'),
                                    ),
                                  ],
                                  child: IgnorePointer(
                                    child: OutlinedButton.icon(
                                      onPressed: () {},
                                      icon: const Icon(
                                        Icons.add_box_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Insert'),
                                    ),
                                  ),
                                ),
                                if (_enableImageBehavior) ...[
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: _isEditorReadOnly
                                        ? null
                                        : _showImageLayoutTools,
                                    icon: const Icon(
                                      Icons.photo_size_select_large,
                                      size: 18,
                                    ),
                                    label: const Text('Image Layout'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        (!_isEditorReadOnly && hasSelectedImage)
                                        ? () => _rotateImageLeft(
                                            currentImageOffset,
                                          )
                                        : null,
                                    icon: const Icon(
                                      Icons.rotate_left_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Rotate L'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        (!_isEditorReadOnly && hasSelectedImage)
                                        ? () => _rotateImageRight(
                                            currentImageOffset,
                                          )
                                        : null,
                                    icon: const Icon(
                                      Icons.rotate_right_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Rotate R'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        (!_isEditorReadOnly && hasSelectedImage)
                                        ? () {
                                            setState(() {
                                              _imageCropMode = !_imageCropMode;
                                            });
                                          }
                                        : null,
                                    icon: Icon(
                                      _imageCropMode
                                          ? Icons.crop_free_rounded
                                          : Icons.crop_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _imageCropMode ? 'Crop On' : 'Crop Off',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        (!_isEditorReadOnly && hasSelectedImage)
                                        ? () {
                                            final styleMap = _imageStyleMap(
                                              currentImageOffset,
                                            );
                                            styleMap.remove('cropLeft');
                                            styleMap.remove('cropTop');
                                            styleMap.remove('cropRight');
                                            styleMap.remove('cropBottom');
                                            _setImageStyleMap(
                                              currentImageOffset,
                                              styleMap,
                                            );
                                            setState(
                                              () => _imageCropMode = false,
                                            );
                                          }
                                        : null,
                                    icon: const Icon(
                                      Icons.filter_none_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Clear Crop'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_enableImageBehavior) ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: !_isEditorReadOnly && hasSelectedImage
                                ? () => _setImageInteractionMode(
                                    !_imageInteractionMode,
                                  )
                                : null,
                            icon: Icon(
                              _imageInteractionMode
                                  ? Icons.keyboard_rounded
                                  : Icons.photo_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _imageInteractionMode
                                  ? 'Type Mode'
                                  : 'Image Mode',
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _isWorkflowReadOnly ? null : _saveNodeNow,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Save now'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F6F5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 920),
                          margin: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x12000000),
                                blurRadius: 16,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListenableBuilder(
                            listenable: _editorController,
                            child: editorWidget,
                            builder: (context, child) {
                              final plain = _editorController.document
                                  .toPlainText()
                                  .replaceAll('\n', '')
                                  .trim();
                              final showEmptyHint =
                                  plain.isEmpty && !_isEditorReadOnly;
                              return Stack(
                                children: [
                                  Positioned.fill(child: child!),
                                  if (showEmptyHint)
                                    const IgnorePointer(
                                      child: Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          38,
                                          30,
                                          38,
                                          24,
                                        ),
                                        child: Align(
                                          alignment: Alignment.topLeft,
                                          child: Text(
                                            'Start writing this handbook section...',
                                            style: TextStyle(
                                              color: _muted,
                                              fontWeight: FontWeight.w600,
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
                      ),
                    ),
                  ),
                  if (!compactHeight) _editorStatusBar(),
                ],
              );
            },
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
          const shortcutsText =
              'Ctrl/Cmd + S | B/I/U | K link | Shift+7/8 lists | Tab/Shift+Tab';
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
                        const Text('Editing entry content', style: baseStyle),
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
                    Text(shortcutsText, style: baseStyle),
                  ],
                );
              }
              return Row(
                children: [
                  const Text('Editing entry content', style: baseStyle),
                  const Spacer(),
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
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Text(
                      shortcutsText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: baseStyle,
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

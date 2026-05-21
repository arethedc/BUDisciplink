import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

List<List<String>> readXlsxRows(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final sharedStringsXml = _readArchiveText(archive, 'xl/sharedStrings.xml');
  final sharedStrings = sharedStringsXml == null
      ? const <String>[]
      : _parseSharedStrings(sharedStringsXml);
  final sheetXml = _readArchiveText(archive, 'xl/worksheets/sheet1.xml');
  if (sheetXml == null || sheetXml.trim().isEmpty) return const [];

  final rows = <List<String>>[];
  final rowMatches = RegExp(
    r'<row\b[^>]*>(.*?)</row>',
    dotAll: true,
  ).allMatches(sheetXml);
  for (final rowMatch in rowMatches) {
    final rowXml = rowMatch.group(1) ?? '';
    final valuesByIndex = <int, String>{};
    var highestIndex = -1;
    final cellMatches = RegExp(
      r'<c\b([^>]*)>(.*?)</c>',
      dotAll: true,
    ).allMatches(rowXml);
    for (final cellMatch in cellMatches) {
      final attrs = cellMatch.group(1) ?? '';
      final cellXml = cellMatch.group(2) ?? '';
      final ref = _attr(attrs, 'r');
      final index = _columnIndex(ref);
      if (index < 0) continue;
      highestIndex = index > highestIndex ? index : highestIndex;
      valuesByIndex[index] = _cellValue(attrs, cellXml, sharedStrings);
    }
    if (highestIndex < 0) continue;
    final row = List<String>.generate(
      highestIndex + 1,
      (index) => valuesByIndex[index] ?? '',
    );
    if (row.any((value) => value.trim().isNotEmpty)) {
      rows.add(row);
    }
  }
  return rows;
}

String? _readArchiveText(Archive archive, String path) {
  for (final file in archive.files) {
    if (file.name == path && file.isFile) {
      final content = file.readBytes();
      if (content == null) return null;
      return utf8.decode(content, allowMalformed: true);
    }
  }
  return null;
}

List<String> _parseSharedStrings(String xml) {
  return RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true)
      .allMatches(xml)
      .map((match) {
        final siXml = match.group(1) ?? '';
        final parts = RegExp(
          r'<t\b[^>]*>(.*?)</t>',
          dotAll: true,
        ).allMatches(siXml).map((t) => _unescapeXml(t.group(1) ?? '')).join();
        return parts.trim();
      })
      .toList(growable: false);
}

String _cellValue(String attrs, String cellXml, List<String> sharedStrings) {
  final type = _attr(attrs, 't');
  if (type == 'inlineStr') {
    final text = RegExp(
      r'<t\b[^>]*>(.*?)</t>',
      dotAll: true,
    ).firstMatch(cellXml)?.group(1);
    return _unescapeXml(text ?? '').trim();
  }
  final rawValue = RegExp(
    r'<v\b[^>]*>(.*?)</v>',
    dotAll: true,
  ).firstMatch(cellXml)?.group(1);
  final value = _unescapeXml(rawValue ?? '').trim();
  if (type == 's') {
    final index = int.tryParse(value);
    if (index == null || index < 0 || index >= sharedStrings.length) {
      return '';
    }
    return sharedStrings[index];
  }
  return value;
}

String _attr(String attrs, String name) {
  return RegExp('$name="([^"]*)"').firstMatch(attrs)?.group(1) ?? '';
}

int _columnIndex(String cellRef) {
  final letters = RegExp(
    r'^[A-Z]+',
    caseSensitive: false,
  ).firstMatch(cellRef)?.group(0)?.toUpperCase();
  if (letters == null || letters.isEmpty) return -1;
  var result = 0;
  for (final codeUnit in letters.codeUnits) {
    result = (result * 26) + (codeUnit - 64);
  }
  return result - 1;
}

String _unescapeXml(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

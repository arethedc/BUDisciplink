import 'package:apps/services/app_firestore.dart';

class InstitutionLabelService {
  InstitutionLabelService._();

  static final Map<String, String> _collegeCache = {};
  static final Map<String, String> _programCache = {};

  static String _codeNameLabel({required String code, required String name}) {
    final cleanCode = code.trim();
    final cleanName = name.trim();
    if (cleanCode.isEmpty) return cleanName;
    if (cleanName.isEmpty || cleanName == cleanCode) return cleanCode;
    return '$cleanCode - $cleanName';
  }

  static Future<String> resolveCollegeLabel(String collegeId) async {
    final id = collegeId.trim();
    if (id.isEmpty) return '--';
    final cached = _collegeCache[id];
    if (cached != null && cached.trim() != id) return cached;

    try {
      final colleges = AppFirestore.instance.collection('colleges');
      final doc = await colleges.doc(id).get();
      final data = doc.data();
      if (data != null) {
        final code = (data['collegeCode'] ?? '').toString();
        final name =
            (data['name'] ?? data['collegeName'] ?? data['title'] ?? '')
                .toString();
        final label = _codeNameLabel(code: code, name: name).trim();
        if (label.isNotEmpty) {
          _collegeCache[id] = label;
          return label;
        }
        final fallback = name.trim().isNotEmpty ? name.trim() : '--';
        _collegeCache[id] = fallback;
        return fallback;
      }

      final byCode = await colleges
          .where('collegeCode', isEqualTo: id)
          .limit(1)
          .get();
      if (byCode.docs.isNotEmpty) {
        final matched = byCode.docs.first.data();
        final code = (matched['collegeCode'] ?? '').toString();
        final name =
            (matched['name'] ??
                    matched['collegeName'] ??
                    matched['title'] ??
                    '')
                .toString();
        final label = _codeNameLabel(code: code, name: name).trim();
        if (label.isNotEmpty) {
          _collegeCache[id] = label;
          return label;
        }
        final fallback = name.trim().isNotEmpty ? name.trim() : '--';
        _collegeCache[id] = fallback;
        return fallback;
      }

      return '--';
    } catch (_) {
      return '--';
    }
  }

  static Future<String> resolveProgramLabel(String programId) async {
    final id = programId.trim();
    if (id.isEmpty) return '--';
    final cached = _programCache[id];
    if (cached != null && cached.trim() != id) return cached;

    try {
      final programs = AppFirestore.instance.collection('programs');
      final doc = await programs.doc(id).get();
      final data = doc.data();
      if (data != null) {
        final code = (data['programCode'] ?? '').toString();
        final name =
            (data['name'] ?? data['programName'] ?? data['title'] ?? '')
                .toString();
        final label = _codeNameLabel(code: code, name: name).trim();
        if (label.isNotEmpty) {
          _programCache[id] = label;
          return label;
        }
        final fallback = name.trim().isNotEmpty ? name.trim() : '--';
        _programCache[id] = fallback;
        return fallback;
      }

      final byCode = await programs
          .where('programCode', isEqualTo: id)
          .limit(1)
          .get();
      if (byCode.docs.isNotEmpty) {
        final matched = byCode.docs.first.data();
        final code = (matched['programCode'] ?? '').toString();
        final name =
            (matched['name'] ??
                    matched['programName'] ??
                    matched['title'] ??
                    '')
                .toString();
        final label = _codeNameLabel(code: code, name: name).trim();
        if (label.isNotEmpty) {
          _programCache[id] = label;
          return label;
        }
        final fallback = name.trim().isNotEmpty ? name.trim() : '--';
        _programCache[id] = fallback;
        return fallback;
      }

      return '--';
    } catch (_) {
      return '--';
    }
  }
}

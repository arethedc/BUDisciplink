import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../shared/widgets/app_layout_tokens.dart';
import 'widgets/osa_common_widgets.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';

class HandbookWorkflowPage extends StatefulWidget {
  final ValueChanged<String>? onOpenEditorForVersion;

  const HandbookWorkflowPage({super.key, this.onOpenEditorForVersion});

  @override
  State<HandbookWorkflowPage> createState() => _HandbookWorkflowPageState();
}

class _HandbookWorkflowPageState extends State<HandbookWorkflowPage> {
  static const _bg = Colors.white;
  static const _primary = Color(0xFF1B5E20);
  static const _hint = Color(0xFF6D7F62);
  static const _textDark = Color(0xFF1F2A1F);
  static const _colHbVersion = 'hb_version';
  static const _colHbSection = 'hb_section';
  static const _colHbContents = 'hb_contents';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _loading = true;
  bool _busy = false;
  String? _error;

  String? _activeVersionId;

  final List<_VersionEntry> _versions = <_VersionEntry>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  String _normalizeStatus(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(' ', '_');
    switch (value) {
      case 'active':
        return 'active';
      default:
        return 'inactive';
    }
  }

  DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String? _normalizeSchoolYearValue(String raw) {
    final input = raw.trim();
    final match = RegExp(
      r'^sy\s*(\d{4})\s*-\s*(\d{4})$',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final startYear = int.tryParse(match.group(1) ?? '');
    final endYear = int.tryParse(match.group(2) ?? '');
    if (startYear == null || endYear == null) return null;
    if (endYear != startYear + 1) return null;
    return 'SY $startYear-$endYear';
  }

  int? _extractSchoolYearStart(String raw) {
    final normalized = _normalizeSchoolYearValue(raw);
    if (normalized == null) return null;
    final match = RegExp(r'^SY (\d{4})-(\d{4})$').firstMatch(normalized);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  String _formatSchoolYearFromStart(int startYear) {
    return 'SY $startYear-${startYear + 1}';
  }

  InputDecoration _modalDecor({
    required String label,
    required IconData icon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      labelStyle: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
      prefixIcon: Icon(icon, color: _primary.withValues(alpha: 0.85)),
      filled: true,
      fillColor: Colors.white,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  ButtonStyle _modalPrimaryButtonStyle({Color? backgroundColor}) {
    return FilledButton.styleFrom(
      backgroundColor: backgroundColor ?? _primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    );
  }

  ButtonStyle _modalSecondaryButtonStyle() {
    return TextButton.styleFrom(
      foregroundColor: _hint,
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _buildWorkflowStyledDialog({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget content,
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
            icon: const Icon(Icons.close_rounded, color: _hint),
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
                            color: _hint,
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
            content,
          ],
        ),
      ),
      actions: actions,
    );
  }

  ThemeData _uniformUiTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          color: _primary,
          fontWeight: FontWeight.w900,
          fontSize: 20,
        ),
        contentTextStyle: const TextStyle(
          color: _textDark,
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
          color: _textDark,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 1.6),
        ),
      ),
    );
  }

  int _defaultSchoolYearStart() {
    final starts = <int>[];
    for (final entry in _versions) {
      final fromId = _extractSchoolYearStart(entry.id);
      if (fromId != null) starts.add(fromId);
      final fromLabel = _extractSchoolYearStart(entry.label);
      if (fromLabel != null) starts.add(fromLabel);
    }
    if (starts.isNotEmpty) {
      starts.sort();
      return starts.last + 1;
    }
    final now = DateTime.now();
    final currentSchoolYearStart = now.month >= 6 ? now.year : now.year - 1;
    return currentSchoolYearStart + 1;
  }

  Future<_GeneratedVersionCode> _generateVersionCodeForSchoolYear(
    String schoolYear,
  ) async {
    final startYear = _extractSchoolYearStart(schoolYear);
    if (startYear == null) {
      throw Exception('Invalid school year format.');
    }
    final endYear = startYear + 1;
    final prefix =
        'HB${(startYear % 100).toString().padLeft(2, '0')}${(endYear % 100).toString().padLeft(2, '0')}';
    final codePattern = RegExp('^${RegExp.escape(prefix)}(\\d+)\$');

    final yearDocs = await _db
        .collection(_colHbVersion)
        .where('schoolYear', isEqualTo: schoolYear)
        .get();

    var maxSequence = 0;
    for (final doc in yearDocs.docs) {
      final data = doc.data();
      final seqRaw = data['sequence'];
      int? seq;
      if (seqRaw is int) {
        seq = seqRaw;
      } else if (seqRaw is num) {
        seq = seqRaw.toInt();
      } else if (seqRaw != null) {
        seq = int.tryParse(seqRaw.toString());
      }
      if (seq != null && seq > maxSequence) {
        maxSequence = seq;
      }

      final match = codePattern.firstMatch(doc.id.trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1) ?? '');
        if (parsed != null && parsed > maxSequence) {
          maxSequence = parsed;
        }
      }
    }

    var nextSequence = maxSequence + 1;
    var versionCode = '$prefix$nextSequence';
    while ((await _db.collection(_colHbVersion).doc(versionCode).get()).exists) {
      nextSequence += 1;
      versionCode = '$prefix$nextSequence';
    }

    return _GeneratedVersionCode(code: versionCode, sequence: nextSequence);
  }

  Future<Set<String>> _discoverVersionIds() async {
    final found = <String>{};

    final nodeSnap = await _db.collection(_colHbSection).get();
    for (final doc in nodeSnap.docs) {
      final data = doc.data();
      final id = (data['versionId'] ?? '').toString().trim();
      if (id.isNotEmpty) found.add(id);
    }

    return found;
  }

  Future<Map<String, dynamic>> _loadEditorMeta() async {
    final hbMetaSnap = await _db.collection(_colHbVersion).doc('current').get();
    return hbMetaSnap.data() ?? const <String, dynamic>{};
  }

  Future<void> _normalizeVersionStatuses({
    required String? activeVersionId,
    required QuerySnapshot<Map<String, dynamic>> versionsSnap,
  }) async {
    final activeId = (activeVersionId ?? '').trim();
    final writes = <void Function(WriteBatch batch)>[];
    for (final doc in versionsSnap.docs) {
      final id = doc.id.trim();
      if (id.isEmpty || id == 'current') continue;
      final desired = (activeId.isNotEmpty && id == activeId)
          ? 'active'
          : 'inactive';
      final current = _normalizeStatus((doc.data()['status'] ?? '').toString());
      if (current == desired) continue;
      writes.add((batch) {
        batch.set(doc.reference, {
          'status': desired,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    }
    if (writes.isEmpty) return;
    await _commitChunkedBatch(writes);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final meta = await _loadEditorMeta();
      final activeVersionIdRaw = (meta['activeVersionId'] ?? '')
          .toString()
          .trim();
      final activeVersionId = activeVersionIdRaw.isEmpty
          ? null
          : activeVersionIdRaw;
      final editingVersionIdRaw = (meta['editingVersionId'] ?? activeVersionIdRaw)
          .toString()
          .trim();
      final editingVersionId = editingVersionIdRaw.isEmpty
          ? null
          : editingVersionIdRaw;

      final versionsSnap = await _db.collection(_colHbVersion).get();
      await _normalizeVersionStatuses(
        activeVersionId: activeVersionId,
        versionsSnap: versionsSnap,
      );
      final map = <String, _VersionEntry>{};
      for (final doc in versionsSnap.docs) {
        final id = doc.id.trim();
        if (id.isEmpty || id == 'current') continue;
        final data = doc.data();
        final seqRaw = data['sequence'];
        int? sequence;
        if (seqRaw is int) {
          sequence = seqRaw;
        } else if (seqRaw is num) {
          sequence = seqRaw.toInt();
        } else if (seqRaw != null) {
          sequence = int.tryParse(seqRaw.toString().trim());
        }
        final originRaw = (data['origin'] ?? '').toString().trim().toLowerCase();
        final isOriginal = originRaw == 'original'
            ? true
            : originRaw == 'duplicate'
            ? false
            : sequence == 1;
        map[id] = _VersionEntry(
          id: id,
          label: (data['label'] ?? id).toString().trim(),
          isOriginal: isOriginal,
          note: (data['note'] ?? '').toString().trim().isEmpty
              ? null
              : (data['note'] ?? '').toString().trim(),
          updatedAt: _asDateTime(data['updatedAt'] ?? data['createdAt']),
        );
      }

      final discovered = await _discoverVersionIds();
      if (activeVersionId != null) discovered.add(activeVersionId);
      if (editingVersionId != null) discovered.add(editingVersionId);
      for (final id in discovered) {
        map.putIfAbsent(
          id,
          () => _VersionEntry(
            id: id,
            label: id,
            isOriginal: true,
            note: null,
            updatedAt: null,
          ),
        );
      }

      final versions = map.values.toList()
        ..sort((a, b) {
          final aIsActive = a.id == activeVersionId;
          final bIsActive = b.id == activeVersionId;
          if (aIsActive && !bIsActive) return -1;
          if (!aIsActive && bIsActive) return 1;

          final aTime = a.updatedAt;
          final bTime = b.updatedAt;
          if (aTime != null && bTime != null) {
            final timeCompare = bTime.compareTo(aTime);
            if (timeCompare != 0) return timeCompare;
          } else if (aTime != null) {
            return -1;
          } else if (bTime != null) {
            return 1;
          }
          return b.id.compareTo(a.id);
        });

      if (!mounted) return;
      setState(() {
        _activeVersionId = activeVersionId;
        _versions
          ..clear()
          ..addAll(versions);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
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

  Future<void> _setBusyWhile(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _editVersion(_VersionEntry entry) async {
    await _setBusyWhile(() async {
      await _db.collection(_colHbVersion).doc('current').set({
        'editingVersionId': entry.id,
        'editingVersionLabel': entry.label,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      try {
        await _appendHandbookVersionLog(
          versionId: entry.id,
          action: 'set_editing_version',
        );
      } catch (_) {}
      await _reload();
      _showSnack('Opening editor for ${entry.label}');
      widget.onOpenEditorForVersion?.call(entry.id);
    });
  }

  Future<void> _setActiveVersion(_VersionEntry target) async {
    final activeId = _activeVersionId;
    if (activeId != null && activeId == target.id) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _buildWorkflowStyledDialog(
        context: context,
        icon: Icons.verified_rounded,
        title: 'Set Active Handbook Version',
        subtitle: 'This will switch the active version for all users.',
        width: 500,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _primary.withValues(alpha: 0.18)),
              ),
              child: Text(
                'Set "${target.label}" as the active handbook version? '
                'The previous active version will become inactive.',
                style: const TextStyle(
                  color: _primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.8,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: _modalSecondaryButtonStyle(),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: _modalPrimaryButtonStyle(),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: const Text('Set Active'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _setBusyWhile(() async {
      final batch = _db.batch();
      batch.set(_db.collection(_colHbVersion).doc('current'), {
        'activeVersionId': target.id,
        'activeVersionLabel': target.label,
        'editingVersionId': target.id,
        'editingVersionLabel': target.label,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(_db.collection(_colHbVersion).doc(target.id), {
        'label': target.label,
        'schoolYear': target.label,
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (activeId != null &&
          activeId.trim().isNotEmpty &&
          activeId != target.id) {
        final previousLabel =
            _versions
                .where((v) => v.id == activeId)
                .map((v) => v.label)
                .cast<String?>()
                .firstWhere((_) => true, orElse: () => activeId) ??
            activeId;
        batch.set(_db.collection(_colHbVersion).doc(activeId), {
          'label': previousLabel,
          'status': 'inactive',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
      try {
        await _appendHandbookVersionLog(
          versionId: target.id,
          action: 'set_active',
        );
      } catch (_) {}
      await _reload();
      _showSnack('Active handbook set to ${target.label}');
    });
  }

  Future<void> _appendHandbookVersionLog({
    required String versionId,
    required String action,
    Map<String, dynamic>? details,
  }) async {
    final id = versionId.trim();
    if (id.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    await _db.collection(_colHbVersion).doc(id).collection('edit_logs').add({
      'action': action,
      'details': details ?? const <String, dynamic>{},
      'actorUid': user?.uid ?? '',
      'actorEmail': user?.email ?? '',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _commitChunkedBatch(
    List<void Function(WriteBatch batch)> operations,
  ) async {
    const chunkSize = 400;
    for (var i = 0; i < operations.length; i += chunkSize) {
      final batch = _db.batch();
      final end = math.min(i + chunkSize, operations.length);
      for (var j = i; j < end; j++) {
        operations[j](batch);
      }
      await batch.commit();
    }
  }

  Future<void> _cloneNodes({
    required String sourceVersionId,
    required String targetVersionId,
  }) async {
    final nodeSnap = await _db
        .collection(_colHbSection)
        .where('versionId', isEqualTo: sourceVersionId)
        .get();
    if (nodeSnap.docs.isEmpty) return;

    final idMap = <String, String>{};
    final newDocBySourceId =
        <String, DocumentReference<Map<String, dynamic>>>{};
    for (final doc in nodeSnap.docs) {
      final ref = _db.collection(_colHbSection).doc();
      idMap[doc.id] = ref.id;
      newDocBySourceId[doc.id] = ref;
    }

    final writeOps = <void Function(WriteBatch batch)>[];
    for (final doc in nodeSnap.docs) {
      final targetRef = newDocBySourceId[doc.id]!;
      final data = Map<String, dynamic>.from(doc.data());
      final sourceParentId = (data['parentId'] ?? '').toString().trim();
      data['parentId'] = sourceParentId.isEmpty
          ? ''
          : (idMap[sourceParentId] ?? '');
      data['versionId'] = targetVersionId;
      data.remove('handbookId');
      data.remove('handbookVersion');
      data.remove('status');
      data.remove('isVisible');
      data.remove('linkedOffice');
      data.remove('tags');
      data.remove('type');
      data.remove('category');
      data.remove('attachments');
      data.remove('content');
      data['title'] = (data['title'] ?? '(Untitled node)').toString();
      data['sortOrder'] = (data['sortOrder'] ?? 0) is int
          ? data['sortOrder']
          : ((data['sortOrder'] as num?)?.toInt() ?? 0);
      data['updatedAt'] = FieldValue.serverTimestamp();
      data['createdAt'] = data['createdAt'] ?? FieldValue.serverTimestamp();
      writeOps.add((batch) => batch.set(targetRef, data));
    }

    await _commitChunkedBatch(writeOps);

    final contentOps = <void Function(WriteBatch batch)>[];
    for (final doc in nodeSnap.docs) {
      final sourceId = doc.id;
      final targetId = idMap[sourceId]!;
      var content = (doc.data()['content'] ?? '').toString();
      final sourceContent = await _db
          .collection(_colHbContents)
          .doc(sourceId)
          .get();
      if (sourceContent.exists) {
        final contentData = sourceContent.data() ?? const <String, dynamic>{};
        final stored = (contentData['content'] ?? '').toString();
        if (stored.trim().isNotEmpty) {
          content = stored;
        }
      }
      final targetContentRef = _db.collection(_colHbContents).doc(targetId);
      contentOps.add((batch) {
        batch.set(targetContentRef, {
          'sectionId': targetId,
          'versionId': targetVersionId,
          'content': content,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    }
    if (contentOps.isNotEmpty) {
      await _commitChunkedBatch(contentOps);
    }
  }

  Future<void> _createVersion({
    required String versionId,
    required String label,
    required String schoolYear,
    int? sequence,
    String? cloneFromVersionId,
    String? note,
  }) async {
    await _setBusyWhile(() async {
      if (versionId.trim().toLowerCase() == 'current') {
        throw Exception('Version ID "current" is reserved.');
      }
      final existing = await _db.collection(_colHbVersion).doc(versionId).get();
      if (existing.exists) {
        throw Exception('Version ID already exists: $versionId');
      }
      final source = (cloneFromVersionId ?? '').trim();
      final noteValue = (note ?? '').trim();

      await _db.collection(_colHbVersion).doc(versionId).set({
        'label': label,
        'schoolYear': schoolYear,
        'sequence': sequence,
        'code': versionId,
        'origin': source.isEmpty ? 'original' : 'duplicate',
        'sourceVersionId': source.isEmpty ? null : source,
        'note': noteValue.isEmpty ? null : noteValue,
        'status': 'inactive',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (source.isNotEmpty) {
        await _cloneNodes(sourceVersionId: source, targetVersionId: versionId);
      }

      await _db.collection(_colHbVersion).doc('current').set({
        'editingVersionId': versionId,
        'editingVersionLabel': label,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      try {
        await _appendHandbookVersionLog(
          versionId: versionId,
          action: source.isEmpty ? 'create_version' : 'clone_version',
          details: <String, dynamic>{
            'cloneFromVersionId': source,
            'hasNote': noteValue.isNotEmpty,
          },
        );
      } catch (_) {}

      await _reload();
      _showSnack(
        source.isEmpty
            ? 'Original version created: $label'
            : 'Duplicate version created: $label',
      );
    });
  }

  Future<_CreateVersionInput?> _showCreateVersionDialog({
    required String title,
    String? cloneFromVersionId,
  }) async {
    final defaultStartYear = _defaultSchoolYearStart();
    final currentYear = DateTime.now().year;
    final selectableStartYears = <int>{
      for (int y = currentYear - 5; y <= currentYear + 5; y++) y,
      defaultStartYear,
    }.toList()
      ..sort();

    final noteController = TextEditingController();
    final result = await showDialog<_CreateVersionInput>(
      context: context,
      builder: (context) {
        int? selectedStartYear;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final schoolYear = selectedStartYear == null
                ? null
                : _formatSchoolYearFromStart(selectedStartYear!);
            return _buildWorkflowStyledDialog(
              context: context,
              icon: Icons.library_add_rounded,
              title: title,
              subtitle: 'Configure school year and note for this version.',
              width: 460,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((cloneFromVersionId ?? '').trim().isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        'Source version: $cloneFromVersionId',
                        style: const TextStyle(
                          color: _primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<int>(
                    initialValue: selectedStartYear,
                    isDense: true,
                    decoration: _modalDecor(
                      label: 'School Year',
                      icon: Icons.calendar_month_rounded,
                    ),
                    items: selectableStartYears
                        .map(
                          (start) => DropdownMenuItem<int>(
                            value: start,
                            child: Text(_formatSchoolYearFromStart(start)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => selectedStartYear = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: _modalDecor(
                      label: 'Note (Optional)',
                      icon: Icons.sticky_note_2_outlined,
                      helperText: 'Optional context for this handbook version.',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  style: _modalSecondaryButtonStyle(),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: schoolYear == null
                      ? null
                      : () {
                          Navigator.pop(
                            context,
                            _CreateVersionInput(
                              schoolYear: schoolYear,
                              cloneFromVersionId: cloneFromVersionId,
                              note: noteController.text.trim(),
                            ),
                          );
                        },
                  style: _modalPrimaryButtonStyle(),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
    noteController.dispose();
    return result;
  }

  Future<void> _onCreateDraftPressed({String? cloneFromVersionId}) async {
    final input = await _showCreateVersionDialog(
      title: cloneFromVersionId == null
          ? 'Create Original Version'
          : 'Create Duplicate Version',
      cloneFromVersionId: cloneFromVersionId,
    );
    if (input == null) return;

    final schoolYear = _normalizeSchoolYearValue(input.schoolYear);
    if (schoolYear == null) {
      _showSnack(
        'Use school year format: SY 2025-2026',
        isError: true,
      );
      return;
    }

    try {
      final generated = await _generateVersionCodeForSchoolYear(schoolYear);
      await _createVersion(
        versionId: generated.code,
        label: schoolYear,
        schoolYear: schoolYear,
        sequence: generated.sequence,
        cloneFromVersionId: input.cloneFromVersionId,
        note: input.note,
      );
    } catch (e) {
      _showSnack('Failed to create version: $e', isError: true);
    }
  }

  Future<void> _editVersionNote(_VersionEntry entry) async {
    final noteController = TextEditingController(text: entry.note ?? '');
    final updatedNote = await showDialog<String?>(
      context: context,
      builder: (context) => _buildWorkflowStyledDialog(
        context: context,
        icon: Icons.edit_note_rounded,
        title: entry.note == null || entry.note!.trim().isEmpty
            ? 'Add Note'
            : 'Edit Note',
        subtitle: 'Update note details for this handbook version.',
        width: 460,
        content: TextFormField(
          controller: noteController,
          minLines: 3,
          maxLines: 6,
          decoration: _modalDecor(
            label: 'Version Note (Optional)',
            icon: Icons.sticky_note_2_outlined,
            helperText: 'Leave empty to clear the note.',
          ),
        ),
        actions: [
          TextButton(
            style: _modalSecondaryButtonStyle(),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, noteController.text.trim()),
            style: _modalPrimaryButtonStyle(),
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save'),
          ),
        ],
      ),
    );
    noteController.dispose();
    if (updatedNote == null) return;

    await _setBusyWhile(() async {
      await _db.collection(_colHbVersion).doc(entry.id).set({
        'note': updatedNote.isEmpty ? FieldValue.delete() : updatedNote,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      try {
        await _appendHandbookVersionLog(
          versionId: entry.id,
          action: 'update_note',
          details: <String, dynamic>{
            'hasNote': updatedNote.isNotEmpty,
          },
        );
      } catch (_) {}
      await _reload();
      _showSnack(
        updatedNote.isEmpty
            ? 'Note removed for ${entry.label}'
            : 'Note updated for ${entry.label}',
      );
    });
  }

  String _formatLastEdited(DateTime? value) {
    if (value == null) return '--';
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[value.month - 1];
    return '$month ${value.day}, ${value.year}';
  }

  Widget _buildVersionCard(_VersionEntry entry) {
    final isActive = entry.id == _activeVersionId;
    final canSetActive = !isActive;
    final versionKindLabel = entry.isOriginal ? 'Original' : 'Duplicate';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;

        Widget compactStatusIndicator(bool active) {
          final color = active ? const Color(0xFF2E7D32) : const Color(0xFF9E9E9E);
          final label = active ? 'Active' : 'Inactive';
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          );
        }

        final editButton = FilledButton.icon(
          onPressed: _busy ? null : () => _editVersion(entry),
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text(
            'Open',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        );

        final moreButton = PopupMenuButton<String>(
          enabled: !_busy,
          tooltip: 'More actions',
          onSelected: (value) {
            switch (value) {
              case 'duplicate':
                _onCreateDraftPressed(cloneFromVersionId: entry.id);
                break;
              case 'note':
                _editVersionNote(entry);
                break;
              case 'publish':
                _setActiveVersion(entry);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'duplicate',
              child: Row(
                children: [
                  Icon(Icons.copy_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Duplicate',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'note',
              child: Row(
                children: [
                  Icon(
                    entry.note == null || entry.note!.trim().isEmpty
                        ? Icons.note_add_outlined
                        : Icons.edit_note_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.note == null || entry.note!.trim().isEmpty
                        ? 'Add Note'
                        : 'Edit Note',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (canSetActive)
              const PopupMenuItem<String>(
                value: 'publish',
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Set Active',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: _textDark.withValues(alpha: 0.20),
              ),
              color: Colors.white,
            ),
            child: const Icon(Icons.more_vert_rounded, size: 18),
          ),
        );

        return OsaPanelCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.label,
                          style: const TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          versionKindLabel,
                          style: const TextStyle(
                            color: _hint,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: compactStatusIndicator(isActive),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Last Edited: ${_formatLastEdited(entry.updatedAt)}',
                style: const TextStyle(
                  color: _hint,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              if ((entry.note ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Note: ${entry.note!.trim()}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (compact)
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _editVersion(entry),
                        style: FilledButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(40, 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text(
                          'Open',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      )
                    else
                      editButton,
                    moreButton,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPanelHeaderActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _primary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildPaneHeader({required Widget action}) {
    const title = 'Handbook Versions';
    const subtitle = 'Create and manage handbook versions by school year.';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                action,
              ],
            );
          }

          return Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            _error!,
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
      child: Container(
        color: _bg,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: OsaPanelCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPaneHeader(
                            action: _buildPanelHeaderActionButton(
                              onPressed: _busy
                                  ? null
                                  : () => _onCreateDraftPressed(),
                              icon: Icons.add_rounded,
                              label: 'Create Draft',
                            ),
                          ),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _versions.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No versions found.',
                                      style: TextStyle(
                                        color: _hint,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _versions.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) =>
                                        _buildVersionCard(_versions[index]),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionEntry {
  final String id;
  final String label;
  final bool isOriginal;
  final String? note;
  final DateTime? updatedAt;

  const _VersionEntry({
    required this.id,
    required this.label,
    required this.isOriginal,
    required this.note,
    required this.updatedAt,
  });
}

class _CreateVersionInput {
  final String schoolYear;
  final String? cloneFromVersionId;
  final String? note;

  const _CreateVersionInput({
    required this.schoolYear,
    required this.cloneFromVersionId,
    required this.note,
  });
}

class _GeneratedVersionCode {
  final String code;
  final int sequence;

  const _GeneratedVersionCode({required this.code, required this.sequence});
}



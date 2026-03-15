import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../shared/widgets/app_layout_tokens.dart';
import 'widgets/osa_common_widgets.dart';

class HandbookWorkflowPage extends StatefulWidget {
  final ValueChanged<String>? onOpenEditorForVersion;

  const HandbookWorkflowPage({super.key, this.onOpenEditorForVersion});

  @override
  State<HandbookWorkflowPage> createState() => _HandbookWorkflowPageState();
}

class _HandbookWorkflowPageState extends State<HandbookWorkflowPage> {
  static const _bg = Color(0xFFF6FAF6);
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
  String? _activeVersionLabel;
  String? _editingVersionId;

  final List<_VersionEntry> _versions = <_VersionEntry>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  String _normalizeStatus(String raw) {
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

  String _statusLabel(String status) {
    switch (_normalizeStatus(status)) {
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

  DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _buildDefaultVersionId() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return 'HB-${now.year}$month$day-$hour$minute';
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
      final activeVersionLabelRaw = (meta['activeVersionLabel'] ?? activeVersionIdRaw)
          .toString()
          .trim();
      final activeVersionLabel = activeVersionLabelRaw.isEmpty
          ? null
          : activeVersionLabelRaw;
      final editingVersionIdRaw = (meta['editingVersionId'] ?? activeVersionIdRaw)
          .toString()
          .trim();
      final editingVersionId = editingVersionIdRaw.isEmpty
          ? null
          : editingVersionIdRaw;

      final versionsSnap = await _db.collection(_colHbVersion).get();
      final map = <String, _VersionEntry>{};
      for (final doc in versionsSnap.docs) {
        final id = doc.id.trim();
        if (id.isEmpty || id == 'current') continue;
        final data = doc.data();
        map[id] = _VersionEntry(
          id: id,
          label: (data['label'] ?? id).toString().trim(),
          status: _normalizeStatus((data['status'] ?? 'draft').toString()),
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
            status: id == activeVersionId ? 'active' : 'draft',
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
        _activeVersionLabel = activeVersionLabel;
        _editingVersionId = editingVersionId;
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
    ScaffoldMessenger.of(context).showSnackBar(
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
      await _reload();
      _showSnack('Opening editor for ${entry.label}');
      widget.onOpenEditorForVersion?.call(entry.id);
    });
  }

  Future<void> _setVersionStatus({
    required String versionId,
    required String status,
  }) async {
    final label =
        _versions
            .where((v) => v.id == versionId)
            .map((v) => v.label)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => versionId) ??
        versionId;

    await _db.collection(_colHbVersion).doc(versionId).set({
      'label': label,
      'status': _normalizeStatus(status),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _setActiveVersion(_VersionEntry target) async {
    final activeId = _activeVersionId;
    if (activeId != null && activeId == target.id) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish handbook version'),
        content: Text(
          'Set "${target.label}" as the active published handbook version? '
          'The current active version will be archived.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _primary),
            child: const Text('Publish'),
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
          'status': 'archived',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
      await _reload();
      _showSnack('Active handbook set to ${target.label}');
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
    String? cloneFromVersionId,
  }) async {
    await _setBusyWhile(() async {
      if (versionId.trim().toLowerCase() == 'current') {
        throw Exception('Version ID "current" is reserved.');
      }
      final existing = await _db.collection(_colHbVersion).doc(versionId).get();
      if (existing.exists) {
        throw Exception('Version ID already exists: $versionId');
      }

      await _db.collection(_colHbVersion).doc(versionId).set({
        'label': label,
        'status': 'draft',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final source = (cloneFromVersionId ?? '').trim();
      if (source.isNotEmpty) {
        await _cloneNodes(sourceVersionId: source, targetVersionId: versionId);
      }

      await _db.collection(_colHbVersion).doc('current').set({
        'editingVersionId': versionId,
        'editingVersionLabel': label,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _reload();
      _showSnack(
        source.isEmpty
            ? 'Draft version created: $label'
            : 'Draft cloned from $source: $label',
      );
    });
  }

  Future<_CreateVersionInput?> _showCreateVersionDialog({
    required String title,
    String? cloneFromVersionId,
  }) async {
    final idController = TextEditingController(text: _buildDefaultVersionId());
    final labelController = TextEditingController(
      text: _buildDefaultVersionId(),
    );

    final result = await showDialog<_CreateVersionInput>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((cloneFromVersionId ?? '').trim().isNotEmpty) ...[
                  Text(
                    'Source version: $cloneFromVersionId',
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: idController,
                  decoration: const InputDecoration(
                    labelText: 'Version ID',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Version Label',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final id = idController.text.trim();
                final label = labelController.text.trim();
                if (id.isEmpty || label.isEmpty) return;
                Navigator.pop(
                  context,
                  _CreateVersionInput(
                    id: id,
                    label: label,
                    cloneFromVersionId: cloneFromVersionId,
                  ),
                );
              },
              style: FilledButton.styleFrom(backgroundColor: _primary),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    idController.dispose();
    labelController.dispose();
    return result;
  }

  Future<void> _onCreateDraftPressed({String? cloneFromVersionId}) async {
    final input = await _showCreateVersionDialog(
      title: cloneFromVersionId == null
          ? 'Create Draft Version'
          : 'Clone as New Draft',
      cloneFromVersionId: cloneFromVersionId,
    );
    if (input == null) return;

    final idPattern = RegExp(r'^[a-zA-Z0-9._-]+$');
    if (!idPattern.hasMatch(input.id)) {
      _showSnack(
        'Version ID must use letters, numbers, dot, underscore, or hyphen only.',
        isError: true,
      );
      return;
    }

    try {
      await _createVersion(
        versionId: input.id,
        label: input.label,
        cloneFromVersionId: input.cloneFromVersionId,
      );
    } catch (e) {
      _showSnack('Failed to create version: $e', isError: true);
    }
  }

  Future<void> _archiveVersion(_VersionEntry entry) async {
    if (entry.id == _activeVersionId) {
      _showSnack('Active version cannot be archived directly.', isError: true);
      return;
    }
    await _setBusyWhile(() async {
      await _setVersionStatus(versionId: entry.id, status: 'archived');
      await _reload();
      _showSnack('${entry.label} moved to Archived');
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
    final status = _normalizeStatus(entry.status);
    final isActive = entry.id == _activeVersionId;
    final isEditing = entry.id == _editingVersionId;
    final canPublish = !isActive && (status == 'draft' || status == 'approved');
    final canReactivate = !isActive && status == 'archived';
    final statusLabels = <String>[
      if (isActive) 'Active',
      if (status == 'active' || status == 'published') 'Published',
      if (isEditing) 'Editing',
      if (!isActive && !isEditing && status != 'active' && status != 'published')
        _statusLabel(status),
    ];
    final statusLine = statusLabels.map((label) => '* $label').join('   ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;

        final editButton = OutlinedButton.icon(
          onPressed: _busy ? null : () => _editVersion(entry),
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          label: const Text(
            'Edit Version',
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
              case 'publish':
                _setActiveVersion(entry);
                break;
              case 'reactivate':
                _setActiveVersion(entry);
                break;
              case 'archive':
                _archiveVersion(entry);
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
            if (canPublish)
              const PopupMenuItem<String>(
                value: 'publish',
                child: Row(
                  children: [
                    Icon(Icons.publish_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Publish',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            if (canReactivate)
              const PopupMenuItem<String>(
                value: 'reactivate',
                child: Row(
                  children: [
                    Icon(Icons.restore_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Re-Activate',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            if (!isActive && status != 'archived')
              const PopupMenuItem<String>(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(Icons.archive_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Archive',
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
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.id,
                          style: TextStyle(
                            color: _textDark.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    editButton,
                    const SizedBox(width: 8),
                    moreButton,
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Status: $statusLine',
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Last Edited: ${_formatLastEdited(entry.updatedAt)}',
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              if (compact)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [editButton, moreButton],
                ),
            ],
          ),
        );
      },
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

    return Container(
      color: _bg,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manage Handbook',
                  style: TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Manage versions: click Edit Version to open the editor in that selected version, then publish when ready.',
                  style: TextStyle(
                    color: _hint,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OsaStatChip(
                      label: 'Active',
                      value: _activeVersionLabel ?? _activeVersionId ?? '--',
                      primaryColor: _primary,
                      hintColor: _hint,
                      textColor: _textDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
                        const Text(
                          'Handbook Versions',
                          style: TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 560;
                            if (compact) {
                              return Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _reload,
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Refresh',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _onCreateDraftPressed(),
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Create Draft',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : _reload,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Refresh',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _onCreateDraftPressed(),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text(
                                    'Create Draft',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
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
    );
  }
}

class _VersionEntry {
  final String id;
  final String label;
  final String status;
  final DateTime? updatedAt;

  const _VersionEntry({
    required this.id,
    required this.label,
    required this.status,
    required this.updatedAt,
  });
}

class _CreateVersionInput {
  final String id;
  final String label;
  final String? cloneFromVersionId;

  const _CreateVersionInput({
    required this.id,
    required this.label,
    required this.cloneFromVersionId,
  });
}


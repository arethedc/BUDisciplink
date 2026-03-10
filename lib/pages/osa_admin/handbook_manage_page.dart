import 'package:apps/models/handbook_topic_doc.dart';
import 'package:apps/pages/shared/handbook/handbook_topic_content_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class HandbookManagePage extends StatefulWidget {
  const HandbookManagePage({super.key});

  @override
  State<HandbookManagePage> createState() => _HandbookManagePageState();
}

class _HandbookManagePageState extends State<HandbookManagePage> {
  static const _bg = Color(0xFFF6FAF6);
  static const _primary = Color(0xFF1B5E20);
  static const _hint = Color(0xFF6D7F62);
  static const _textDark = Color(0xFF1F2A1F);

  final _db = FirebaseFirestore.instance;
  final _sectionSearchCtrl = TextEditingController();
  final _topicSearchCtrl = TextEditingController();

  int _manageTabIndex = 0;
  String? _activeVersionId;
  String? _activeVersionLabel;
  String? _editingVersionId;
  String? _editingVersionStatus;
  bool _loadingVersionOptions = false;
  bool _savingActiveVersion = false;
  String? _versionOptionsError;
  final List<String> _versionOptions = [];
  final Map<String, String> _versionStatusById = {};
  final Map<String, String> _versionLabelById = {};
  bool _loadingVersion = true;
  String? _versionError;
  String? _selectedSectionId;
  String? _selectedSectionCode;
  String? _selectedSectionTitle;
  HandbookTopicDoc? _selectedTopicForContent;
  bool _loadingSections = false;
  String? _sectionsError;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _sectionDocs = [];
  bool _loadingTopics = false;
  String? _topicsError;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _topicDocs = [];
  String _sectionQuery = '';
  String _topicQuery = '';

  @override
  void initState() {
    super.initState();
    _loadActiveVersion();
  }

  @override
  void dispose() {
    _sectionSearchCtrl.dispose();
    _topicSearchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(String source, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return source.toLowerCase().contains(q);
  }

  int _countStatus(String status) {
    final normalized = _normalizeVersionStatus(status);
    return _versionOptions
        .where(
          (id) => _normalizeVersionStatus(_versionStatusById[id] ?? 'draft') ==
              normalized,
        )
        .length;
  }

  Future<void> _loadActiveVersion() async {
    setState(() {
      _loadingVersion = true;
      _versionError = null;
    });
    try {
      final snap = await _db.collection('handbook_meta').doc('current').get();
      final data = snap.data() ?? const <String, dynamic>{};
      final activeVersionId = (snap.data()?['activeVersionId'] ?? '')
          .toString()
          .trim();
      if (activeVersionId.isEmpty) {
        throw Exception('Missing handbook_meta/current.activeVersionId');
      }
      if (!mounted) return;
      setState(() {
        _activeVersionId = activeVersionId;
        _activeVersionLabel = (data['activeVersionLabel'] ?? activeVersionId)
            .toString()
            .trim();
        _editingVersionId = activeVersionId;
        _loadingVersion = false;
      });
      await _loadSections();
      await _loadVersionOptions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _versionError = e.toString();
        _loadingVersion = false;
      });
    }
  }

  Future<void> _loadVersionOptions() async {
    setState(() {
      _loadingVersionOptions = true;
      _versionOptionsError = null;
    });

    try {
      final options = <String>{};
      final statusMap = <String, String>{};
      final labelMap = <String, String>{};

      final versions = await _db.collection('handbook_versions').get();
      for (final doc in versions.docs) {
        final versionId = doc.id.trim();
        if (versionId.isEmpty) continue;
        final data = doc.data();
        options.add(versionId);
        statusMap[versionId] = _normalizeVersionStatus(
          (data['status'] ?? 'draft').toString(),
        );
        labelMap[versionId] = (data['label'] ?? versionId).toString().trim();
      }

      if (options.isEmpty) {
        final sectionSnap = await _db.collection('handbook_sections').get();
        final topicSnap = await _db.collection('handbook_topics').get();
        for (final doc in sectionSnap.docs) {
          final versionId = (doc.data()['versionId'] ?? '').toString().trim();
          if (versionId.isNotEmpty) options.add(versionId);
        }
        for (final doc in topicSnap.docs) {
          final versionId = (doc.data()['versionId'] ?? '').toString().trim();
          if (versionId.isNotEmpty) options.add(versionId);
        }
      }

      if (_activeVersionId != null && _activeVersionId!.trim().isNotEmpty) {
        options.add(_activeVersionId!.trim());
      }

      for (final versionId in options) {
        statusMap.putIfAbsent(
          versionId,
          () => versionId == _activeVersionId ? 'active' : 'draft',
        );
        labelMap.putIfAbsent(versionId, () => versionId);
      }

      final sorted = options.toList()..sort((a, b) => b.compareTo(a));
      if (!mounted) return;
      setState(() {
        _versionOptions
          ..clear()
          ..addAll(sorted);
        _versionStatusById
          ..clear()
          ..addAll(statusMap);
        _versionLabelById
          ..clear()
          ..addAll(labelMap);
        if (_editingVersionId == null || !_versionOptions.contains(_editingVersionId)) {
          _editingVersionId = _activeVersionId;
        }
        _editingVersionStatus = _editingVersionId == null
            ? null
            : _versionStatusById[_editingVersionId!];
        _loadingVersionOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVersionOptions = false;
        _versionOptionsError = e.toString();
      });
    }
  }

  String _normalizeVersionStatus(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(' ', '_');
    switch (value) {
      case 'draft':
      case 'under_review':
      case 'approved':
      case 'active':
      case 'archived':
        return value;
      default:
        return 'draft';
    }
  }

  String _statusLabel(String status) {
    switch (_normalizeVersionStatus(status)) {
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
      default:
        return 'Draft';
    }
  }

  Color _statusColor(String status) {
    switch (_normalizeVersionStatus(status)) {
      case 'draft':
        return Colors.blueGrey;
      case 'under_review':
        return Colors.deepOrange;
      case 'approved':
        return Colors.teal;
      case 'active':
        return _primary;
      case 'archived':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  bool get _isEditingVersionEditable =>
      _normalizeVersionStatus(_editingVersionStatus ?? '') == 'draft';

  Future<void> _setVersionStatus(
    String versionId,
    String status, {
    bool showFeedback = true,
  }) async {
    final normalizedStatus = _normalizeVersionStatus(status);
    await _db.collection('handbook_versions').doc(versionId).set({
      'label': _versionLabelById[versionId] ?? versionId,
      'status': normalizedStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _loadVersionOptions();
    if (showFeedback) {
      _showSnack('$versionId moved to ${_statusLabel(normalizedStatus)}');
    }
  }

  Future<void> _setActiveVersion(String nextVersion) async {
    final target = nextVersion.trim();
    if (target.isEmpty) return;
    if (_normalizeVersionStatus(_versionStatusById[target] ?? '') != 'approved' &&
        target != _activeVersionId) {
      _showSnack(
        'Only approved versions can be activated.',
        isError: true,
      );
      return;
    }

    setState(() => _savingActiveVersion = true);
    try {
      final prevActive = _activeVersionId;
      await _db.collection('handbook_meta').doc('current').set({
        'activeVersionId': target,
        'activeVersionLabel': _versionLabelById[target] ?? target,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _setVersionStatus(target, 'active', showFeedback: false);
      if (prevActive != null && prevActive.isNotEmpty && prevActive != target) {
        await _setVersionStatus(prevActive, 'archived', showFeedback: false);
      }

      if (!mounted) return;
      setState(() {
        _activeVersionId = target;
        _activeVersionLabel = _versionLabelById[target] ?? target;
      });
      await _loadVersionOptions();
      _showSnack('Active handbook version updated to $target');
    } catch (e) {
      _showSnack('Failed to set active version: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _savingActiveVersion = false);
      }
    }
  }

  Future<void> _openVersionForContent(String versionId) async {
    if (versionId.trim().isEmpty) return;
    if (!mounted) return;
    setState(() {
      _editingVersionId = versionId;
      _editingVersionStatus = _versionStatusById[versionId];
      _sectionQuery = '';
      _topicQuery = '';
      _sectionSearchCtrl.clear();
      _topicSearchCtrl.clear();
      _selectedSectionId = null;
      _selectedSectionCode = null;
      _selectedSectionTitle = null;
      _selectedTopicForContent = null;
      _manageTabIndex = 0;
    });
    await _loadSections();
  }

  Future<void> _createVersionId() async {
    final controller = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Create Handbook Version',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Version ID',
              hintText: 'e.g. 2026-2027',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _primary),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    final versionId = (created ?? '').trim();
    if (versionId.isEmpty) return;

    try {
      await _db.collection('handbook_versions').doc(versionId).set({
        'label': versionId,
        'status': 'draft',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      await _loadVersionOptions();
      _showSnack('Version $versionId added');
    } catch (e) {
      _showSnack('Failed to create version: $e', isError: true);
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

  int _docOrder(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final value = doc.data()['order'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  int _adjustedNewIndex(int oldIndex, int newIndex) {
    return newIndex > oldIndex ? newIndex - 1 : newIndex;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _reorderedDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int oldIndex,
    int newIndex,
  ) {
    final list = [...docs];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    return list;
  }

  Future<void> _loadSections() async {
    final versionId = _editingVersionId;
    if (versionId == null || versionId.isEmpty) return;
    setState(() {
      _loadingSections = true;
      _sectionsError = null;
    });
    try {
      final snap = await _db
          .collection('handbook_sections')
          .where('versionId', isEqualTo: versionId)
          .get();
      final docs = [...snap.docs]
        ..sort((a, b) => _docOrder(a).compareTo(_docOrder(b)));
      if (!mounted) return;
      setState(() {
        _sectionDocs
          ..clear()
          ..addAll(docs);
        _loadingSections = false;
      });

      if (_sectionDocs.isEmpty) {
        if (!mounted) return;
        setState(() {
          _selectedSectionId = null;
          _selectedSectionCode = null;
          _selectedSectionTitle = null;
          _selectedTopicForContent = null;
          _topicDocs.clear();
        });
        return;
      }

      final hasSelection = _sectionDocs.any((d) => d.id == _selectedSectionId);
      if (!hasSelection) {
        final first = _sectionDocs.first;
        if (!mounted) return;
        setState(() {
          _selectedSectionId = first.id;
          _selectedSectionCode = (first.data()['code'] ?? '').toString();
          _selectedSectionTitle = (first.data()['title'] ?? '').toString();
          _selectedTopicForContent = null;
        });
      }
      await _loadTopicsForSelectedSection();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sectionsError = e.toString();
        _loadingSections = false;
      });
    }
  }

  Future<void> _loadTopicsForSelectedSection() async {
    final versionId = _editingVersionId;
    if (versionId == null ||
        versionId.isEmpty ||
        _selectedSectionCode == null ||
        _selectedSectionCode!.isEmpty) {
      if (!mounted) return;
      setState(() {
        _topicDocs.clear();
        _topicsError = null;
        _loadingTopics = false;
      });
      return;
    }

    final sectionCode = _selectedSectionCode!;
    setState(() {
      _loadingTopics = true;
      _topicsError = null;
    });
    try {
      final snap = await _db
          .collection('handbook_topics')
          .where('versionId', isEqualTo: versionId)
          .where('sectionCode', isEqualTo: sectionCode)
          .get();
      final docs = [...snap.docs]
        ..sort((a, b) => _docOrder(a).compareTo(_docOrder(b)));
      if (!mounted) return;
      setState(() {
        _topicDocs
          ..clear()
          ..addAll(docs);
        final currentId = _selectedTopicForContent?.id;
        if (currentId != null && !docs.any((d) => d.id == currentId)) {
          _selectedTopicForContent = null;
        }
        _loadingTopics = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _topicsError = e.toString();
        _loadingTopics = false;
      });
    }
  }

  Future<void> _saveDocumentOrder(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orderedDocs, {
    required String successMessage,
  }) async {
    final batch = _db.batch();
    var changed = false;
    for (var i = 0; i < orderedDocs.length; i++) {
      final nextOrder = i + 1;
      if (_docOrder(orderedDocs[i]) != nextOrder) {
        changed = true;
        batch.update(orderedDocs[i].reference, {
          'order': nextOrder,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    if (!changed) return;
    await batch.commit();
    _showSnack(successMessage);
  }

  Future<void> _onReorderSections(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int oldIndex,
    int newIndex,
  ) async {
    if (!_isEditingVersionEditable) return;
    if (oldIndex < 0 || oldIndex >= docs.length) return;
    final adjustedNewIndex = _adjustedNewIndex(oldIndex, newIndex);
    if (adjustedNewIndex < 0 || adjustedNewIndex >= docs.length) return;
    if (adjustedNewIndex == oldIndex) return;

    final reordered = _reorderedDocs(docs, oldIndex, adjustedNewIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _sectionDocs
          ..clear()
          ..addAll(reordered);
      });
    });

    try {
      await _saveDocumentOrder(
        reordered,
        successMessage: 'Section order updated',
      );
    } catch (e) {
      _showSnack('Failed to reorder sections: $e', isError: true);
      await _loadSections();
    }
  }

  Future<void> _onReorderTopics(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int oldIndex,
    int newIndex,
  ) async {
    if (!_isEditingVersionEditable) return;
    final sectionCode = _selectedSectionCode;
    if (sectionCode == null || sectionCode.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= docs.length) return;
    final adjustedNewIndex = _adjustedNewIndex(oldIndex, newIndex);
    if (adjustedNewIndex < 0 || adjustedNewIndex >= docs.length) return;
    if (adjustedNewIndex == oldIndex) return;

    final reordered = _reorderedDocs(docs, oldIndex, adjustedNewIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _topicDocs
          ..clear()
          ..addAll(reordered);
      });
    });

    try {
      await _saveDocumentOrder(
        reordered,
        successMessage: 'Topic order updated',
      );
    } catch (e) {
      _showSnack('Failed to reorder topics: $e', isError: true);
      await _loadTopicsForSelectedSection();
    }
  }

  Future<Map<String, String>?> _showSectionDialog({
    String? initialCode,
    String? initialTitle,
  }) async {
    final codeCtrl = TextEditingController(text: initialCode ?? '');
    final titleCtrl = TextEditingController(text: initialTitle ?? '');
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            initialCode == null ? 'Add Section' : 'Edit Section',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Section Code'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Section Title'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final code = codeCtrl.text.trim();
                final title = titleCtrl.text.trim();
                if (code.isEmpty || title.isEmpty) return;
                Navigator.pop(context, {'code': code, 'title': title});
              },
              style: FilledButton.styleFrom(backgroundColor: _primary),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, String>?> _showTopicDialog({
    String? initialCode,
    String? initialTitle,
  }) async {
    final codeCtrl = TextEditingController(text: initialCode ?? '');
    final titleCtrl = TextEditingController(text: initialTitle ?? '');
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            initialCode == null ? 'Add Topic' : 'Edit Topic',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Topic Code'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Topic Title'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final code = codeCtrl.text.trim();
                final title = titleCtrl.text.trim();
                if (code.isEmpty || title.isEmpty) return;
                Navigator.pop(context, {'code': code, 'title': title});
              },
              style: FilledButton.styleFrom(backgroundColor: _primary),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addSection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (!_isEditingVersionEditable) {
      _showSnack(
        'This version is locked. Only Draft versions are editable.',
        isError: true,
      );
      return;
    }
    final versionId = _editingVersionId;
    if (versionId == null || versionId.isEmpty) return;
    final values = await _showSectionDialog();
    if (values == null) return;
    final nextOrder = docs.isEmpty
        ? 1
        : docs.map(_docOrder).reduce((a, b) => a > b ? a : b) + 1;
    await _db.collection('handbook_sections').add({
      'versionId': versionId,
      'code': values['code'],
      'title': values['title'],
      'order': nextOrder,
      'isPublished': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _loadSections();
    _showSnack('Section added');
  }

  Future<void> _editSection(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!_isEditingVersionEditable) {
      _showSnack(
        'This version is locked. Only Draft versions are editable.',
        isError: true,
      );
      return;
    }
    final data = doc.data();
    final values = await _showSectionDialog(
      initialCode: (data['code'] ?? '').toString(),
      initialTitle: (data['title'] ?? '').toString(),
    );
    if (values == null) return;
    await doc.reference.update({
      'code': values['code'],
      'title': values['title'],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _loadSections();
    _showSnack('Section updated');
  }

  Future<void> _deleteSection(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!_isEditingVersionEditable) {
      _showSnack(
        'This version is locked. Only Draft versions are editable.',
        isError: true,
      );
      return;
    }
    final sectionCode = (doc.data()['code'] ?? '').toString().trim();
    final versionId = _editingVersionId;
    if (sectionCode.isEmpty || versionId == null || versionId.isEmpty) return;

    final topics = await _db
        .collection('handbook_topics')
        .where('versionId', isEqualTo: versionId)
        .where('sectionCode', isEqualTo: sectionCode)
        .limit(1)
        .get();
    if (topics.docs.isNotEmpty) {
      _showSnack('Delete topics under this section first.', isError: true);
      return;
    }

    await doc.reference.delete();
    if (_selectedSectionId == doc.id) {
      setState(() {
        _selectedSectionId = null;
        _selectedSectionCode = null;
        _selectedSectionTitle = null;
      });
    }
    await _loadSections();
    _showSnack('Section deleted');
  }

  Future<void> _addTopic(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (!_isEditingVersionEditable) {
      _showSnack(
        'This version is locked. Only Draft versions are editable.',
        isError: true,
      );
      return;
    }
    final versionId = _editingVersionId;
    if (versionId == null || versionId.isEmpty || _selectedSectionCode == null) {
      return;
    }
    final values = await _showTopicDialog();
    if (values == null) return;
    final nextOrder = docs.isEmpty
        ? 1
        : docs.map(_docOrder).reduce((a, b) => a > b ? a : b) + 1;
    await _db.collection('handbook_topics').add({
      'versionId': versionId,
      'sectionCode': _selectedSectionCode,
      'code': values['code'],
      'title': values['title'],
      'order': nextOrder,
      'isPublished': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _loadTopicsForSelectedSection();
    _showSnack('Topic added');
  }

  Future<void> _editTopic(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!_isEditingVersionEditable) {
      _showSnack(
        'This version is locked. Only Draft versions are editable.',
        isError: true,
      );
      return;
    }
    final data = doc.data();
    final values = await _showTopicDialog(
      initialCode: (data['code'] ?? '').toString(),
      initialTitle: (data['title'] ?? '').toString(),
    );
    if (values == null) return;
    await doc.reference.update({
      'code': values['code'],
      'title': values['title'],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _loadTopicsForSelectedSection();
    _showSnack('Topic updated');
  }

  Future<void> _deleteTopic(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!_isEditingVersionEditable) {
      _showSnack(
        'This version is locked. Only Draft versions are editable.',
        isError: true,
      );
      return;
    }
    await doc.reference.delete();
    if (_selectedTopicForContent?.id == doc.id) {
      setState(() => _selectedTopicForContent = null);
    }
    await _loadTopicsForSelectedSection();
    _showSnack('Topic deleted');
  }

  Widget _sectionPanel() {
    final docs = _sectionDocs;
    final filteredDocs = docs
        .where((doc) {
          final data = doc.data();
          final code = (data['code'] ?? '').toString();
          final title = (data['title'] ?? '').toString();
          return _matchesQuery('$code $title', _sectionQuery);
        })
        .toList();
    final canReorder = _isEditingVersionEditable && _sectionQuery.trim().isEmpty;
    if (_sectionsError != null) {
      return _PanelError(title: 'Failed to load sections', details: _sectionsError!);
    }
    if (_loadingSections) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Sections',
                  style: TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _isEditingVersionEditable ? () => _addSection(docs) : null,
                style: FilledButton.styleFrom(backgroundColor: _primary),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _compactSearchField(
            controller: _sectionSearchCtrl,
            hintText: 'Search sections',
            onChanged: (value) => setState(() => _sectionQuery = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Showing ${filteredDocs.length} of ${docs.length}',
                style: const TextStyle(
                  color: _hint,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filteredDocs.isEmpty
                ? const Center(
                    child: Text(
                      'No matching sections.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  )
                : ReorderableListView.builder(
                    key: const PageStorageKey('handbook_manage_sections'),
                    itemCount: filteredDocs.length,
                    buildDefaultDragHandles: canReorder,
                    onReorder: (oldIndex, newIndex) =>
                        _onReorderSections(
                          canReorder ? docs : filteredDocs,
                          oldIndex,
                          newIndex,
                        ),
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data();
                      final selected = _selectedSectionId == doc.id;
                      final isPublished = data['isPublished'] == true;
                      final code = (data['code'] ?? '').toString();
                      final title = (data['title'] ?? '').toString();
                      return SizedBox(
                        key: ValueKey('section_${doc.id}'),
                        width: double.infinity,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedSectionId = doc.id;
                              _selectedSectionCode = code;
                              _selectedSectionTitle = title;
                              _topicQuery = '';
                              _topicSearchCtrl.clear();
                              _selectedTopicForContent = null;
                            });
                            _loadTopicsForSelectedSection();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _primary.withValues(alpha: 0.10)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? _primary.withValues(alpha: 0.40)
                                    : Colors.black.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Icon(
                                        Icons.drag_indicator_rounded,
                                        color: _hint,
                                      ),
                                    ),
                                    Text(
                                      code,
                                      style: const TextStyle(
                                        color: _primary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _textDark,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    _StatusPill(
                                      text: isPublished ? 'Published' : 'Draft',
                                      color: isPublished
                                          ? _primary
                                          : Colors.orange.shade700,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 2,
                                  children: [
                                    IconButton(
                                      tooltip: 'Edit section',
                                      onPressed: _isEditingVersionEditable
                                          ? () => _editSection(doc)
                                          : null,
                                      icon: const Icon(Icons.edit_rounded),
                                    ),
                                    IconButton(
                                      tooltip: isPublished ? 'Unpublish' : 'Publish',
                                      onPressed: _isEditingVersionEditable ? () async {
                                        await doc.reference.update({
                                          'isPublished': !isPublished,
                                          'updatedAt': FieldValue.serverTimestamp(),
                                        });
                                        await _loadSections();
                                      } : null,
                                      icon: Icon(
                                        isPublished
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete section',
                                      onPressed: _isEditingVersionEditable
                                          ? () => _deleteSection(doc)
                                          : null,
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topicsPanel() {
    if (_selectedSectionCode == null || _selectedSectionCode!.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Select a section to manage topics.',
          style: TextStyle(fontWeight: FontWeight.w800, color: _hint),
        ),
      );
    }

    if (_topicsError != null) {
      return _PanelError(title: 'Failed to load topics', details: _topicsError!);
    }
    if (_loadingTopics) {
      return const Center(child: CircularProgressIndicator());
    }

    final docs = _topicDocs;
    final filteredDocs = docs
        .where((doc) {
          final data = doc.data();
          final code = (data['code'] ?? '').toString();
          final title = (data['title'] ?? '').toString();
          return _matchesQuery('$code $title', _topicQuery);
        })
        .toList();
    final canReorder = _isEditingVersionEditable && _topicQuery.trim().isEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Topics',
                      style: TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_selectedSectionCode!} ${_selectedSectionTitle ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _isEditingVersionEditable ? () => _addTopic(docs) : null,
                style: FilledButton.styleFrom(backgroundColor: _primary),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _compactSearchField(
            controller: _topicSearchCtrl,
            hintText: 'Search topics',
            onChanged: (value) => setState(() => _topicQuery = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Showing ${filteredDocs.length} of ${docs.length}',
                style: const TextStyle(
                  color: _hint,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filteredDocs.isEmpty
                ? const Center(
                    child: Text(
                      'No matching topics.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  )
                : ReorderableListView.builder(
                    key: const PageStorageKey('handbook_manage_topics'),
                    itemCount: filteredDocs.length,
                    buildDefaultDragHandles: canReorder,
                    onReorder: (oldIndex, newIndex) =>
                        _onReorderTopics(
                          canReorder ? docs : filteredDocs,
                          oldIndex,
                          newIndex,
                        ),
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data();
                      final selected = _selectedTopicForContent?.id == doc.id;
                      final isPublished = data['isPublished'] == true;
                      final code = (data['code'] ?? '').toString();
                      final title = (data['title'] ?? '').toString();
                      return SizedBox(
                        key: ValueKey('topic_${doc.id}'),
                        width: double.infinity,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            if (!mounted) return;
                            setState(
                              () =>
                                  _selectedTopicForContent =
                                      HandbookTopicDoc.fromDoc(doc),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: selected
                                ? _primary.withValues(alpha: 0.10)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? _primary.withValues(alpha: 0.40)
                                  : Colors.black.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Icon(
                                      Icons.drag_indicator_rounded,
                                      color: _hint,
                                    ),
                                  ),
                                  Text(
                                    code,
                                    style: const TextStyle(
                                      color: _primary,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _textDark,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  _StatusPill(
                                    text: isPublished ? 'Published' : 'Draft',
                                    color: isPublished
                                        ? _primary
                                        : Colors.orange.shade700,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 2,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit topic',
                                    onPressed: _isEditingVersionEditable
                                        ? () => _editTopic(doc)
                                        : null,
                                    icon: const Icon(Icons.edit_rounded),
                                  ),
                                  IconButton(
                                    tooltip: isPublished ? 'Unpublish' : 'Publish',
                                    onPressed: _isEditingVersionEditable ? () async {
                                      await doc.reference.update({
                                        'isPublished': !isPublished,
                                        'updatedAt': FieldValue.serverTimestamp(),
                                      });
                                      await _loadTopicsForSelectedSection();
                                    } : null,
                                    icon: Icon(
                                      isPublished
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete topic',
                                    onPressed: _isEditingVersionEditable
                                        ? () => _deleteTopic(doc)
                                        : null,
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _contentPanel() {
    final selectedTopic = _selectedTopicForContent;
    final versionLabel = _versionLabelById[_editingVersionId] ?? _editingVersionId ?? '--';
    final statusLabel = _statusLabel(_editingVersionStatus ?? 'draft');
    final statusColor = _statusColor(_editingVersionStatus ?? 'draft');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Editing: $versionLabel',
                    style: const TextStyle(
                      color: _textDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusPill(text: statusLabel, color: statusColor),
              ],
            ),
          ),
          if (!_isEditingVersionEditable)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                ),
                child: Text(
                  'This version is read-only. Switch to a Draft version to edit.',
                  style: const TextStyle(
                    color: _hint,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: selectedTopic == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 38,
                          color: _hint,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Select a topic from the sidebar\nto manage content.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _hint,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  )
                : HandbookTopicContentScreen(
                    key: ValueKey('manage_topic_${selectedTopic.id}_${_editingVersionId ?? ''}'),
                    topic: selectedTopic,
                    manageMode: _isEditingVersionEditable,
                    overrideTitle: 'Manage ${selectedTopic.code} ${selectedTopic.title}',
                    embedded: true,
                    onBack: () {
                      if (!mounted) return;
                      setState(() => _selectedTopicForContent = null);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarPanel() {
    return Column(
      children: [
        Expanded(flex: 10, child: _sectionPanel()),
        const SizedBox(height: 12),
        Expanded(flex: 12, child: _topicsPanel()),
      ],
    );
  }

  Widget _compactSearchField({
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(
          color: _textDark,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: _hint),
        ).copyWith(hintText: hintText),
      ),
    );
  }

  Widget _pageHeader() {
    final editingLabel =
        _versionLabelById[_editingVersionId] ?? _editingVersionId ?? '--';
    final editingStatus = _editingVersionStatus ?? 'draft';
    final normalizedStatus = _statusLabel(editingStatus);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manage Handbook',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: _primary,
              letterSpacing: -0.5,
            ),
          ),
          const Text(
            'Manage sections, topics, and handbook version workflow.',
            style: TextStyle(
              color: _hint,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _topStatChip(
                  'Active Version',
                  _activeVersionLabel ?? _activeVersionId ?? '--',
                ),
                const SizedBox(width: 8),
                _topStatChip('Editing Version', editingLabel),
                const SizedBox(width: 8),
                _topStatChip('Editing Status', normalizedStatus),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (!_isEditingVersionEditable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
              ),
              child: const Text(
                'Current editing version is locked. Switch to a Draft version to edit content.',
                style: TextStyle(
                  color: Color(0xFF7A5B00),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(height: 10),
          _manageNavBar(),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _manageNavBar() {
    return DefaultTabController(
      key: ValueKey(_manageTabIndex),
      length: 2,
      initialIndex: _manageTabIndex,
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
            if (index == _manageTabIndex) return;
            setState(() => _manageTabIndex = index);
          },
          tabs: const [
            Tab(text: 'Manage Content'),
            Tab(text: 'Version Workflow'),
          ],
        ),
      ),
    );
  }

  Widget _topStatChip(String label, String value) {
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
              style: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workflowStatCard({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      width: 152,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsPanel() {
    final activeAcademicYearStream = _db
        .collection('academic_years')
        .where('status', isEqualTo: 'active')
        .limit(1)
        .snapshots();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Handbook Version Workflow',
                style: TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Statuses: Draft (editable), Under Review (locked), Approved (waiting activation), Active (published), Archived (history).',
                style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusPill(
                    text: 'Active: ${_activeVersionLabel ?? _activeVersionId ?? '--'}',
                    color: _primary,
                  ),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: activeAcademicYearStream,
                    builder: (context, snap) {
                      final label = snap.data?.docs.isNotEmpty == true
                          ? (snap.data!.docs.first.data()['label'] ??
                                    snap.data!.docs.first.id)
                                .toString()
                          : '--';
                      return _StatusPill(
                        text: 'Academic Year: $label',
                        color: const Color(0xFF0F766E),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _workflowStatCard(
                    label: 'Draft',
                    count: _countStatus('draft'),
                    color: _statusColor('draft'),
                  ),
                  _workflowStatCard(
                    label: 'Under Review',
                    count: _countStatus('under_review'),
                    color: _statusColor('under_review'),
                  ),
                  _workflowStatCard(
                    label: 'Approved',
                    count: _countStatus('approved'),
                    color: _statusColor('approved'),
                  ),
                  _workflowStatCard(
                    label: 'Active',
                    count: _countStatus('active'),
                    color: _statusColor('active'),
                  ),
                  _workflowStatCard(
                    label: 'Archived',
                    count: _countStatus('archived'),
                    color: _statusColor('archived'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_versionOptionsError != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Failed to load version options: $_versionOptionsError',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _loadingVersionOptions ? null : _loadVersionOptions,
                    style: FilledButton.styleFrom(backgroundColor: _primary),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Refresh Versions',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _createVersionId,
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                    label: const Text(
                      'Create Version',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _versionOptions.isEmpty
                    ? const Center(
                        child: Text(
                          'No handbook versions found.',
                          style: TextStyle(
                            color: _hint,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _versionOptions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final versionId = _versionOptions[index];
                          final versionLabel = _versionLabelById[versionId] ?? versionId;
                          final status = _normalizeVersionStatus(
                            _versionStatusById[versionId] ?? 'draft',
                          );
                          final isActive = versionId == _activeVersionId;
                          final isEditing = versionId == _editingVersionId;
                          final statusColor = _statusColor(status);
                          final canActivate = status == 'approved' &&
                              !isActive &&
                              !_savingActiveVersion;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? _primary.withValues(alpha: 0.06)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isActive
                                    ? _primary.withValues(alpha: 0.30)
                                    : Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        versionLabel,
                                        style: const TextStyle(
                                          color: _textDark,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    if (isEditing) ...[
                                      const Padding(
                                        padding: EdgeInsets.only(right: 8),
                                        child: _StatusPill(
                                          text: 'In Content',
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                    if (isActive) ...[
                                      const Padding(
                                        padding: EdgeInsets.only(right: 8),
                                        child: _StatusPill(
                                          text: 'Published',
                                          color: _primary,
                                        ),
                                      ),
                                    ],
                                    _StatusPill(
                                      text: _statusLabel(status),
                                      color: statusColor,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _openVersionForContent(versionId),
                                      icon: const Icon(Icons.edit_note_rounded, size: 18),
                                      label: Text(
                                        status == 'draft'
                                            ? 'Manage Content'
                                            : 'View Content',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (status == 'draft')
                                      FilledButton.icon(
                                        onPressed: () => _setVersionStatus(
                                          versionId,
                                          'under_review',
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.deepOrange,
                                        ),
                                        icon: const Icon(
                                          Icons.rate_review_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Submit Review',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    if (status == 'under_review')
                                      OutlinedButton.icon(
                                        onPressed: () => _setVersionStatus(
                                          versionId,
                                          'draft',
                                        ),
                                        icon: const Icon(
                                          Icons.undo_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Back to Draft',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    if (status == 'under_review')
                                      FilledButton.icon(
                                        onPressed: () => _setVersionStatus(
                                          versionId,
                                          'approved',
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFF0F766E),
                                        ),
                                        icon: const Icon(
                                          Icons.task_alt_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Approve',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    if (status == 'approved')
                                      FilledButton.icon(
                                        onPressed: canActivate
                                            ? () => _setActiveVersion(versionId)
                                            : null,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _primary,
                                        ),
                                        icon: _savingActiveVersion
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.publish_rounded,
                                                size: 18,
                                              ),
                                        label: const Text(
                                          'Set Active',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    if (status == 'active')
                                      OutlinedButton.icon(
                                        onPressed: () => _setVersionStatus(
                                          versionId,
                                          'archived',
                                        ),
                                        icon: const Icon(
                                          Icons.archive_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Archive',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                  ],
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingVersion) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_versionError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _versionError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1100;

    if (_manageTabIndex == 0 && !isDesktop && _selectedTopicForContent != null) {
      return Container(
        color: _bg,
        child: Column(
          children: [
            _pageHeader(),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _contentPanel(),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: _bg,
      child: Column(
        children: [
          _pageHeader(),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _manageTabIndex == 1
                  ? _settingsPanel()
                  : (isDesktop
                      ? Row(
                          children: [
                            SizedBox(width: 460, child: _sidebarPanel()),
                            const SizedBox(width: 14),
                            Expanded(child: _contentPanel()),
                          ],
                        )
                      : _sidebarPanel()),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _PanelError extends StatelessWidget {
  final String title;
  final String details;

  const _PanelError({required this.title, required this.details});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.red.shade700,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                details,
                style: const TextStyle(
                  color: Color(0xFF6D7F62),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

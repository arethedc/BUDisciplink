import 'package:flutter/material.dart';

import '../../services/counseling_setup_service.dart';

class CounselingSetupPage extends StatefulWidget {
  const CounselingSetupPage({super.key});

  @override
  State<CounselingSetupPage> createState() => _CounselingSetupPageState();
}

class _CounselingSetupPageState extends State<CounselingSetupPage> {
  static const Color _bg = Colors.white;
  static const Color _surface = Colors.white;
  static const Color _surfaceSoft = Color(0xFFF7FBF7);
  static const Color _primary = Color(0xFF1B5E20);
  static const Color _textDark = Color(0xFF1F2A1F);
  static const Color _hint = Color(0xFF6D7F62);

  final CounselingSetupService _service = CounselingSetupService();

  bool _loading = true;
  bool _saving = false;
  List<CounselingSetupGroup> _groups = <CounselingSetupGroup>[];
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final config = await _service.getConfig();
      if (!mounted) return;
      setState(() {
        _groups = List<CounselingSetupGroup>.from(config.groups);
        _selectedGroupId = _resolveSelectedGroupId(
          existing: _selectedGroupId,
          groups: _groups,
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load counseling setup: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _resolveSelectedGroupId({
    required String? existing,
    required List<CounselingSetupGroup> groups,
  }) {
    if (groups.isEmpty) return null;
    if (existing != null && groups.any((g) => g.id == existing)) {
      return existing;
    }
    return groups.first.id;
  }

  CounselingSetupGroup? get _selectedGroup {
    final id = _selectedGroupId;
    if (id == null) return null;
    for (final group in _groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  Future<void> _persist() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final titles = <String, String>{
        for (final group in _groups) group.id: group.title,
      };
      final byId = <String, List<String>>{
        for (final group in _groups) group.id: group.items,
      };
      final config = CounselingSetupConfig(
        moodsBehaviors:
            byId[CounselingSetupConfig.moodsKey] ??
            CounselingSetupConfig.defaults.moodsBehaviors,
        schoolConcerns:
            byId[CounselingSetupConfig.schoolKey] ??
            CounselingSetupConfig.defaults.schoolConcerns,
        relationships:
            byId[CounselingSetupConfig.relationshipsKey] ??
            CounselingSetupConfig.defaults.relationships,
        homeConcerns:
            byId[CounselingSetupConfig.homeKey] ??
            CounselingSetupConfig.defaults.homeConcerns,
        sectionTitles: titles,
        groups: _groups,
      );
      await _service.saveConfig(config);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save changes: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _slugify(String value) {
    final lower = value.toLowerCase().trim();
    final normalized = lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? 'group' : normalized;
  }

  String _uniqueGroupId(String preferred) {
    final base = _slugify(preferred);
    var next = base;
    var i = 2;
    while (_groups.any((g) => g.id == next)) {
      next = '${base}_$i';
      i++;
    }
    return next;
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    String initialValue = '',
    String confirmLabel = 'Save',
  }) async {
    final ctrl = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onSubmitted: (_) => Navigator.of(context).pop(ctrl.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: _primary),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    final trimmed = (result ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _addGroup() async {
    final title = await _promptText(
      title: 'Add Group',
      hint: 'Enter group title',
      confirmLabel: 'Add',
    );
    if (title == null) return;

    final id = _uniqueGroupId(title);
    setState(() {
      _groups = <CounselingSetupGroup>[
        ..._groups,
        CounselingSetupGroup(id: id, title: title, items: const <String>[]),
      ];
      _selectedGroupId = id;
    });
    await _persist();
  }

  Future<void> _renameGroup(CounselingSetupGroup group) async {
    final title = await _promptText(
      title: 'Edit Group',
      hint: 'Enter group title',
      initialValue: group.title,
      confirmLabel: 'Update',
    );
    if (title == null) return;

    setState(() {
      _groups = _groups.map((g) {
        if (g.id != group.id) return g;
        return g.copyWith(title: title);
      }).toList();
    });
    await _persist();
  }

  Future<void> _deleteGroup(CounselingSetupGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete group?'),
          content: Text(
            'Delete "${group.title}" and all checklist items under it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() {
      _groups = _groups.where((g) => g.id != group.id).toList();
      _selectedGroupId = _resolveSelectedGroupId(
        existing: _selectedGroupId == group.id ? null : _selectedGroupId,
        groups: _groups,
      );
    });
    await _persist();
  }

  Future<void> _addItem(CounselingSetupGroup group) async {
    final value = await _promptText(
      title: 'Add Checklist Item',
      hint: 'Enter checklist item',
      confirmLabel: 'Add',
    );
    if (value == null) return;

    final trimmed = value.trim();
    if (group.items.contains(trimmed)) return;

    setState(() {
      _groups = _groups.map((g) {
        if (g.id != group.id) return g;
        final items = <String>[...g.items, trimmed]..sort();
        return g.copyWith(items: items);
      }).toList();
    });
    await _persist();
  }

  Future<void> _editItem(CounselingSetupGroup group, String item) async {
    final value = await _promptText(
      title: 'Edit Checklist Item',
      hint: 'Enter checklist item',
      initialValue: item,
      confirmLabel: 'Update',
    );
    if (value == null) return;
    final trimmed = value.trim();

    setState(() {
      _groups = _groups.map((g) {
        if (g.id != group.id) return g;
        final items = g.items.map((e) => e == item ? trimmed : e).toSet().toList()
          ..sort();
        return g.copyWith(items: items);
      }).toList();
    });
    await _persist();
  }

  Future<void> _deleteItem(CounselingSetupGroup group, String item) async {
    setState(() {
      _groups = _groups.map((g) {
        if (g.id != group.id) return g;
        final items = g.items.where((e) => e != item).toList();
        return g.copyWith(items: items);
      }).toList();
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _selectedGroupId == null
                    ? _buildGroupsLevel()
                    : _buildItemsLevel(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader({
    required String title,
    required String subtitle,
    Widget? action,
  }) {
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                if (action != null) ...[const SizedBox(height: 10), action],
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 12), action],
            ],
          );
        },
      ),
    );
  }

  Widget _buildPathHeader({
    required String title,
    required String subtitle,
    required VoidCallback onBack,
    Widget? action,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;
          final heading = Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, color: _primary),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (!stacked && action != null) ...[
                const SizedBox(width: 6),
                action,
              ],
            ],
          );
          if (!stacked || action == null) return heading;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupsLevel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopHeader(
          title: 'Counseling Setup',
          subtitle: 'Select a group to view and manage checklist items.',
          action: FilledButton.icon(
            onPressed: _saving ? null : _addGroup,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Group'),
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: _surfaceSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _primary.withValues(alpha: 0.14)),
            ),
            child: Column(
              children: [
                if (_groups.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: const Text(
                      'No groups yet. Add your first group.',
                      style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  ..._groups.map((group) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _selectedGroupId = group.id),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.title,
                                      style: const TextStyle(
                                        color: _textDark,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${group.items.length} item(s)',
                                      style: TextStyle(
                                        color: _hint.withValues(alpha: 0.92),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit group',
                                onPressed: _saving ? null : () => _renameGroup(group),
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: _primary,
                                  size: 18,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete group',
                                onPressed: _saving ? null : () => _deleteGroup(group),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.red,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsLevel() {
    final group = _selectedGroup;
    if (group == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedGroupId = null);
      });
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPathHeader(
          title: group.title,
          subtitle: 'Manage checklist items in this group.',
          onBack: () => setState(() => _selectedGroupId = null),
          action: FilledButton.icon(
            onPressed: _saving ? null : () => _addItem(group),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Item'),
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: _surfaceSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _primary.withValues(alpha: 0.14)),
            ),
            child: Column(
              children: [
                if (group.items.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: const Text(
                      'No items yet in this group.',
                      style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  ...group.items.map((item) {
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(
                                color: _textDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit item',
                            onPressed: _saving ? null : () => _editItem(group, item),
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: _primary,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete item',
                            onPressed: _saving ? null : () => _deleteItem(group, item),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

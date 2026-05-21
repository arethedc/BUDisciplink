import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/counseling_setup_service.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';
import 'widgets/osa_common_widgets.dart';

enum _SetupStatusFilter { active, inactive, all }

class _InlineFilterTab {
  final String value;
  final String label;

  const _InlineFilterTab({required this.value, required this.label});
}

bool _matchesStatusFilter(bool active, _SetupStatusFilter filter) {
  switch (filter) {
    case _SetupStatusFilter.active:
      return active;
    case _SetupStatusFilter.inactive:
      return !active;
    case _SetupStatusFilter.all:
      return true;
  }
}

const Color _dialogBg = Colors.white;
const Color _dialogPrimary = Color(0xFF1B5E20);
const Color _dialogTextDark = Color(0xFF1F2A1F);
const Color _dialogHint = Color(0xFF6D7F62);

ButtonStyle _dialogPrimaryButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: _dialogPrimary,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

InputDecoration _modalDecor({
  required String label,
  required IconData icon,
  String? helperText,
}) {
  return InputDecoration(
    labelText: label,
    helperText: helperText,
    labelStyle: const TextStyle(
      color: _dialogHint,
      fontWeight: FontWeight.w700,
    ),
    prefixIcon: Icon(icon, color: _dialogPrimary.withValues(alpha: 0.85)),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: _dialogPrimary, width: 1.6),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

Future<({String value, bool active})?> _showCounselingEditDialog({
  required BuildContext context,
  required String title,
  required String fieldLabel,
  required String initialValue,
  required bool initialActive,
  required IconData icon,
  String confirmLabel = 'Save',
}) async {
  final valueCtrl = TextEditingController(text: initialValue);
  var active = initialActive;
  var saving = false;

  final result = await showDialog<({String value, bool active})>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: _dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: _dialogPrimary,
              ),
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: valueCtrl,
                      enabled: !saving,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _dialogTextDark,
                      ),
                      decoration: _modalDecor(label: fieldLabel, icon: icon),
                    ),
                    if (saving) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(color: _dialogPrimary),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              SizedBox(
                width: 500,
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: saving
                          ? null
                          : () => setDialogState(() => active = !active),
                      style: TextButton.styleFrom(
                        foregroundColor: active ? _dialogPrimary : _dialogHint,
                        backgroundColor: active
                            ? _dialogPrimary.withValues(alpha: 0.10)
                            : Colors.grey.withValues(alpha: 0.10),
                        side: BorderSide(
                          color: active
                              ? _dialogPrimary.withValues(alpha: 0.55)
                              : Colors.black.withValues(alpha: 0.20),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      icon: Icon(
                        active
                            ? Icons.toggle_on_rounded
                            : Icons.toggle_off_rounded,
                      ),
                      label: Text(
                        active ? 'Active' : 'Inactive',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.pop(dialogContext, null),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _dialogHint,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: _dialogPrimaryButtonStyle(),
                      onPressed: saving
                          ? null
                          : () {
                              final value = valueCtrl.text.trim();
                              if (value.isEmpty) return;
                              Navigator.pop(dialogContext, (
                                value: value,
                                active: active,
                              ));
                            },
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );

  valueCtrl.dispose();
  final value = (result?.value ?? '').trim();
  if (value.isEmpty) return null;
  return (value: value, active: result?.active ?? true);
}

Widget _buildReviewStyleFilterBar({
  required List<_InlineFilterTab> tabs,
  required String selectedValue,
  required ValueChanged<String> onSelect,
}) {
  const filterRadius = 12.0;

  Widget filterTab(_InlineFilterTab tab) {
    final selected = selectedValue == tab.value;
    return InkWell(
      borderRadius: BorderRadius.circular(filterRadius),
      onTap: () {
        if (selected) return;
        onSelect(tab.value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1B5E20).withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(filterRadius),
          border: Border.all(
            color: selected
                ? const Color(0xFF1B5E20).withValues(alpha: 0.36)
                : Colors.black.withValues(alpha: 0.10),
          ),
        ),
        child: Text(
          tab.label,
          style: TextStyle(
            color: selected ? const Color(0xFF1B5E20) : const Color(0xFF1F2A1F),
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  return Align(
    alignment: Alignment.centerLeft,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            filterTab(tabs[i]),
            if (i != tabs.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    ),
  );
}

class _CounselingEntryRowControllers {
  final TextEditingController label;
  bool active = true;

  _CounselingEntryRowControllers({String initialLabel = ''})
    : label = TextEditingController(text: initialLabel);

  void dispose() {
    label.dispose();
  }
}

class _CounselingEntriesDialog extends StatefulWidget {
  final String title;
  final String fieldLabelPrefix;
  final String hint;
  final IconData icon;
  final bool showActiveToggle;
  final Future<bool> Function(List<({String label, bool active})> rows) onSave;

  const _CounselingEntriesDialog({
    required this.title,
    required this.fieldLabelPrefix,
    required this.hint,
    required this.icon,
    required this.onSave,
    this.showActiveToggle = false,
  });

  @override
  State<_CounselingEntriesDialog> createState() =>
      _CounselingEntriesDialogState();
}

class _CounselingEntriesDialogState extends State<_CounselingEntriesDialog> {
  final List<_CounselingEntryRowControllers> _rows = [
    _CounselingEntryRowControllers(),
  ];
  bool _saving = false;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _rows.add(_CounselingEntryRowControllers()));
  }

  void _removeRow(int index) {
    if (_rows.length == 1) return;
    final row = _rows.removeAt(index);
    row.dispose();
    setState(() {});
  }

  List<({String label, bool active})> _validRows() {
    return _rows
        .map((row) => (label: row.label.text.trim(), active: row.active))
        .where((row) => row.label.isNotEmpty)
        .toList(growable: false);
  }

  Widget _buildRows() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _rows.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _rows[i].label,
                  enabled: !_saving,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _dialogTextDark,
                  ),
                  decoration: InputDecoration(
                    labelText: '${widget.fieldLabelPrefix} ${i + 1}',
                    hintText: widget.hint,
                    labelStyle: const TextStyle(
                      color: _dialogHint,
                      fontWeight: FontWeight.w700,
                    ),
                    prefixIcon: Icon(
                      widget.icon,
                      color: _dialogPrimary.withValues(alpha: 0.85),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: _dialogPrimary, width: 1.6),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove row',
                onPressed: _saving || _rows.length == 1
                    ? null
                    : () => _removeRow(i),
                icon: const Icon(Icons.close_rounded),
                color: _dialogHint,
              ),
            ],
          ),
          if (widget.showActiveToggle) ...[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _rows[i].active,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _rows[i].active = value),
              title: const Text(
                'Active',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                _rows[i].active
                    ? 'Visible in the setup'
                    : 'Hidden from the setup',
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: _saving ? null : _addRow,
          style: OutlinedButton.styleFrom(
            foregroundColor: _dialogPrimary,
            side: BorderSide(color: _dialogPrimary.withValues(alpha: 0.35)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Add Row',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        widget.title,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: _dialogPrimary,
        ),
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRows(),
              if (_saving) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(color: _dialogPrimary),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, null),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: _dialogHint),
          ),
        ),
        FilledButton(
          style: _dialogPrimaryButtonStyle(),
          onPressed: _saving
              ? null
              : () async {
                  final rows = _validRows();
                  if (rows.isEmpty) return;
                  setState(() => _saving = true);
                  try {
                    final ok = await widget.onSave(rows);
                    if (!mounted) return;
                    if (ok) {
                      Navigator.pop(context, true);
                      return;
                    }
                  } catch (_) {
                    // The callback is responsible for surfacing errors.
                  }
                  if (mounted) setState(() => _saving = false);
                },
          child: const Text(
            'Save All',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

Widget _buildPanelHeaderActionButton({
  required VoidCallback? onPressed,
  required IconData icon,
  required String label,
}) {
  return FilledButton.icon(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF1B5E20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: Icon(icon, size: 18),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
  );
}

String _normalizedTitle(String value) => value.trim().toLowerCase();

String _countLabel(int count, String singular, String plural) {
  return count == 1 ? singular : plural;
}

int _maxSortOrder(Iterable<int> values) {
  var maxValue = 0;
  for (final value in values) {
    if (value > maxValue) maxValue = value;
  }
  return maxValue;
}

class CounselingSetupPage extends StatefulWidget {
  const CounselingSetupPage({super.key});

  @override
  State<CounselingSetupPage> createState() => _CounselingSetupPageState();
}

class _CounselingSetupPageState extends State<CounselingSetupPage> {
  static const Color _bg = Colors.white;
  static const Color _surface = Colors.white;
  static const Color _primary = Color(0xFF1B5E20);
  static const Color _textDark = Color(0xFF1F2A1F);
  static const Color _hint = Color(0xFF6D7F62);

  final CounselingSetupService _service = CounselingSetupService();
  late final Stream<CounselingSetupConfig> _configStream = _service
      .streamConfig();

  bool _loading = true;
  bool _saving = false;
  bool _seeding = false;
  _SetupStatusFilter _groupFilter = _SetupStatusFilter.active;
  _SetupStatusFilter _itemFilter = _SetupStatusFilter.active;
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
      AppScaffoldMessenger.of(context).showSnackBar(
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
    return null;
  }

  CounselingSetupGroup? get _selectedGroup {
    final id = _selectedGroupId;
    if (id == null) return null;
    for (final group in _groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  bool _sameGroups(
    List<CounselingSetupGroup> left,
    List<CounselingSetupGroup> right,
  ) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      final a = left[i];
      final b = right[i];
      if (a.id != b.id ||
          a.key != b.key ||
          a.title != b.title ||
          a.sortOrder != b.sortOrder ||
          a.active != b.active) {
        return false;
      }
      if (a.items.length != b.items.length) return false;
      for (var j = 0; j < a.items.length; j++) {
        if (a.items[j] != b.items[j]) return false;
      }
    }
    return true;
  }

  void _syncFromSnapshot(List<CounselingSetupGroup> groups) {
    final nextSelected = _resolveSelectedGroupId(
      existing: _selectedGroupId,
      groups: groups,
    );
    if (_sameGroups(_groups, groups) && nextSelected == _selectedGroupId) {
      return;
    }
    setState(() {
      _groups = List<CounselingSetupGroup>.from(groups);
      _selectedGroupId = nextSelected;
    });
  }

  Future<void> _persist() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final config = CounselingSetupConfig(
        academicPerformanceInformation: const <String>[],
        physicalAttributes: const <String>[],
        crisisIndicators: const <String>[],
        atypicalBehavior: const <String>[],
        groups: _groups,
      );
      await _service.saveConfig(config);
    } catch (error) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save changes: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _seedDefaultSetup() async {
    if (_seeding) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Seed Counseling Setup?',
            style: TextStyle(color: _primary, fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'This will load the default counseling checklist groups and items into the setup page.',
            style: TextStyle(color: _textDark, fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _hint, fontWeight: FontWeight.w900),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: _primary),
              child: const Text(
                'Seed',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _seeding = true);
    try {
      final result = await _service.seedDefaultConfig();
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Seeded ${result['groups']} ${_countLabel(result['groups'] ?? 0, 'counseling group', 'counseling groups')} and ${result['items']} ${_countLabel(result['items'] ?? 0, 'checklist item', 'checklist items')}.',
          ),
          backgroundColor: _primary,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to seed counseling setup: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  String _newGroupId() {
    return FirebaseFirestore.instance.collection('counseling_groups').doc().id;
  }

  Future<void> _addGroup() async {
    final currentGroups = List<CounselingSetupGroup>.from(_groups);
    var savedCount = 0;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _CounselingEntriesDialog(
          title: 'Add Group',
          fieldLabelPrefix: 'Group Title',
          hint: 'Enter group title',
          icon: Icons.folder_open_rounded,
          showActiveToggle: false,
          onSave: (rows) async {
            final existingTitles = currentGroups
                .map((group) => _normalizedTitle(group.title))
                .toSet();
            final seenNewTitles = <String>{};
            for (final row in rows) {
              final title = row.label.trim();
              final normalized = _normalizedTitle(title);
              if (title.isEmpty) continue;
              if (!seenNewTitles.add(normalized) ||
                  existingTitles.contains(normalized)) {
                if (!context.mounted) return false;
                AppScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Remove duplicate counseling group titles first.',
                    ),
                  ),
                );
                return false;
              }
            }

            final nextSortBase =
                _maxSortOrder(currentGroups.map((g) => g.sortOrder)) + 1;
            final updated = [
              ...currentGroups,
              for (var i = 0; i < rows.length; i++)
                CounselingSetupGroup(
                  id: _newGroupId(),
                  title: rows[i].label.trim(),
                  items: const <CounselingSetupItem>[],
                  active: rows[i].active,
                  sortOrder: nextSortBase + i,
                ),
            ];
            try {
              await _service.saveConfig(
                CounselingSetupConfig(
                  academicPerformanceInformation: const <String>[],
                  physicalAttributes: const <String>[],
                  crisisIndicators: const <String>[],
                  atypicalBehavior: const <String>[],
                  groups: updated,
                ),
              );
              savedCount = rows.length;
              return true;
            } catch (error) {
              if (!context.mounted) return false;
              AppScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to add counseling groups: $error'),
                  backgroundColor: Colors.red,
                ),
              );
              return false;
            }
          },
        );
      },
    );
    if (!mounted) return;
    if (result == true) {
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created $savedCount ${_countLabel(savedCount, 'counseling group', 'counseling groups')}.',
          ),
          backgroundColor: _primary,
        ),
      );
    }
  }

  Future<void> _renameGroup(CounselingSetupGroup group) async {
    final result = await _showCounselingEditDialog(
      context: context,
      title: 'Edit Group',
      fieldLabel: 'Group Title',
      initialValue: group.title,
      confirmLabel: 'Update',
      initialActive: group.active,
      icon: Icons.folder_open_rounded,
    );
    if (result == null) return;

    setState(() {
      _groups = _groups.map((g) {
        if (g.id != group.id) return g;
        return g.copyWith(title: result.value, active: result.active);
      }).toList();
    });
    await _persist();
  }

  Future<void> _addItem(CounselingSetupGroup group) async {
    final currentGroups = List<CounselingSetupGroup>.from(_groups);
    var savedCount = 0;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _CounselingEntriesDialog(
          title: 'Add Item',
          fieldLabelPrefix: 'Item',
          hint: 'Enter checklist item',
          icon: Icons.checklist_rounded,
          showActiveToggle: false,
          onSave: (rows) async {
            final selected = currentGroups.firstWhere(
              (g) => g.id == group.id,
              orElse: () => group,
            );
            final existingItems = selected.items
                .map((item) => _normalizedTitle(item.label))
                .toSet();
            final seenNewItems = <String>{};
            for (final row in rows) {
              final label = row.label.trim();
              final normalized = _normalizedTitle(label);
              if (label.isEmpty) continue;
              if (!seenNewItems.add(normalized) ||
                  existingItems.contains(normalized)) {
                if (!context.mounted) return false;
                AppScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Remove duplicate checklist items first.'),
                  ),
                );
                return false;
              }
            }

            final updatedGroups = currentGroups.map((g) {
              if (g.id != group.id) return g;
              final nextSortBase =
                  _maxSortOrder(g.items.map((item) => item.sortOrder)) + 1;
              final items = <CounselingSetupItem>[
                ...g.items,
                for (var i = 0; i < rows.length; i++)
                  CounselingSetupItem(
                    id: '',
                    label: rows[i].label.trim(),
                    sortOrder: nextSortBase + i,
                    active: rows[i].active,
                  ),
              ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
              return g.copyWith(items: items);
            }).toList();

            try {
              await _service.saveConfig(
                CounselingSetupConfig(
                  academicPerformanceInformation: const <String>[],
                  physicalAttributes: const <String>[],
                  crisisIndicators: const <String>[],
                  atypicalBehavior: const <String>[],
                  groups: updatedGroups,
                ),
              );
              savedCount = rows.length;
              return true;
            } catch (error) {
              if (!context.mounted) return false;
              AppScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to add checklist items: $error'),
                  backgroundColor: Colors.red,
                ),
              );
              return false;
            }
          },
        );
      },
    );
    if (!mounted) return;
    if (result == true) {
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created $savedCount ${_countLabel(savedCount, 'checklist item', 'checklist items')} in ${group.title}.',
          ),
          backgroundColor: _primary,
        ),
      );
    }
  }

  Future<void> _editItem(
    CounselingSetupGroup group,
    CounselingSetupItem item,
  ) async {
    final result = await _showCounselingEditDialog(
      context: context,
      title: 'Edit Checklist Item',
      fieldLabel: 'Checklist Item',
      initialValue: item.label,
      confirmLabel: 'Update',
      initialActive: item.active,
      icon: Icons.checklist_rounded,
    );
    if (result == null) return;
    final trimmed = result.value.trim();

    setState(() {
      _groups = _groups.map((g) {
        if (g.id != group.id) return g;
        final items = g.items.map((e) {
          if (e.id == item.id && item.id.isNotEmpty) {
            return e.copyWith(label: trimmed, active: result.active);
          }
          if (item.id.isEmpty && e.label == item.label) {
            return e.copyWith(label: trimmed, active: result.active);
          }
          return e;
        }).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return g.copyWith(items: items);
      }).toList();
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CounselingSetupConfig>(
      stream: _configStream,
      builder: (context, snapshot) {
        final config = snapshot.data;
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: _bg,
            body: Center(
              child: Text(
                'Failed to load counseling setup: ${snapshot.error}',
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }

        if (config == null) {
          if (_groups.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: _bg,
              body: Center(child: CircularProgressIndicator()),
            );
          }
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncFromSnapshot(List<CounselingSetupGroup>.from(config.groups));
          });
        }

        return Scaffold(
          backgroundColor: _bg,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final maxPanelWidth = constraints.maxWidth >= 1600
                  ? 1180.0
                  : constraints.maxWidth >= 1200
                  ? 1080.0
                  : constraints.maxWidth;
              final body = _selectedGroupId == null
                  ? _buildGroupsLevel()
                  : _buildItemsLevel();
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxPanelWidth),
                    child: SizedBox(
                      width: double.infinity,
                      child: OsaPanelCard(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: body,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
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

  Widget _buildStatusFilterBar({
    required int activeCount,
    required int inactiveCount,
    required int allCount,
    required _SetupStatusFilter selected,
    required ValueChanged<_SetupStatusFilter> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _buildReviewStyleFilterBar(
        selectedValue: selected.name,
        onSelect: (value) {
          onChanged(
            value == 'inactive'
                ? _SetupStatusFilter.inactive
                : value == 'all'
                ? _SetupStatusFilter.all
                : _SetupStatusFilter.active,
          );
        },
        tabs: [
          _InlineFilterTab(value: 'active', label: 'Active ($activeCount)'),
          _InlineFilterTab(
            value: 'inactive',
            label: 'Inactive ($inactiveCount)',
          ),
          _InlineFilterTab(value: 'all', label: 'All ($allCount)'),
        ],
      ),
    );
  }

  Widget _buildStatusChip(bool active) {
    final color = active ? const Color(0xFF2E7D32) : const Color(0xFF9E9E9E);
    final label = active ? 'Active' : 'Inactive';
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
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
      ),
    );
  }

  Widget _buildNoDataSetupCard({
    required String title,
    required String subtitle,
    required String primaryButtonLabel,
    required IconData primaryIcon,
    required VoidCallback? primaryOnPressed,
    String? secondaryButtonLabel,
    IconData? secondaryIcon,
    VoidCallback? secondaryOnPressed,
    bool secondaryLoading = false,
    double maxWidth = 640,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 520;
                    final primaryButton = FilledButton.icon(
                      onPressed: primaryOnPressed,
                      style: FilledButton.styleFrom(
                        backgroundColor: _primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: Icon(primaryIcon, size: 18),
                      label: Text(
                        primaryButtonLabel,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    );

                    final hasSecondary =
                        secondaryButtonLabel != null &&
                        secondaryOnPressed != null &&
                        secondaryIcon != null;
                    final secondaryButton = hasSecondary
                        ? OutlinedButton.icon(
                            onPressed: secondaryOnPressed,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _primary,
                              side: BorderSide(
                                color: _primary.withValues(alpha: 0.35),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: secondaryLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _primary,
                                    ),
                                  )
                                : Icon(secondaryIcon, size: 18),
                            label: Text(
                              secondaryLoading
                                  ? 'Seeding...'
                                  : secondaryButtonLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          )
                        : null;

                    if (secondaryButton == null) return primaryButton;

                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          primaryButton,
                          const SizedBox(height: 12),
                          secondaryButton,
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(child: primaryButton),
                        const SizedBox(width: 12),
                        Flexible(child: secondaryButton),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupsLevel() {
    final allGroups = [..._groups]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final visibleGroups =
        _groups
            .where((group) => _matchesStatusFilter(group.active, _groupFilter))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final activeCount = allGroups.where((g) => g.active).length;
    final inactiveCount = allGroups.length - activeCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopHeader(
          title: 'Counseling Setup',
          subtitle: 'Seed or add counseling checklist groups and items.',
          action: _groups.isEmpty
              ? null
              : _buildPanelHeaderActionButton(
                  onPressed: _saving ? null : _addGroup,
                  icon: Icons.add_rounded,
                  label: 'Add Group',
                ),
        ),
        if (_groups.isNotEmpty)
          _buildStatusFilterBar(
            activeCount: activeCount,
            inactiveCount: inactiveCount,
            allCount: allGroups.length,
            selected: _groupFilter,
            onChanged: (value) => setState(() => _groupFilter = value),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _groups.isEmpty
                ? _buildNoDataSetupCard(
                    title: 'Start counseling setup',
                    subtitle:
                        'Add your first counseling checklist group or load the default setup to speed up initial configuration.',
                    primaryButtonLabel: 'Add Group',
                    primaryIcon: Icons.add_rounded,
                    primaryOnPressed: _saving ? null : _addGroup,
                    secondaryButtonLabel: 'Seed Default Setup',
                    secondaryIcon: Icons.download_rounded,
                    secondaryOnPressed: _seeding ? null : _seedDefaultSetup,
                    secondaryLoading: _seeding,
                    maxWidth: 720,
                  )
                : visibleGroups.isEmpty
                ? const Center(
                    child: Text(
                      'No groups for this filter.',
                      style: TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: visibleGroups.length,
                    itemBuilder: (context, index) {
                      final group = visibleGroups[index];
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
                          onTap: () =>
                              setState(() => _selectedGroupId = group.id),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${group.title} (${group.items.length})',
                                        style: const TextStyle(
                                          color: _textDark,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_groupFilter == _SetupStatusFilter.all)
                                  _buildStatusChip(group.active),
                                IconButton(
                                  tooltip: 'Edit group',
                                  onPressed: _saving
                                      ? null
                                      : () => _renameGroup(group),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: _primary,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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

    final allItems = [...group.items]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final visibleItems =
        group.items
            .where((item) => _matchesStatusFilter(item.active, _itemFilter))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final activeCount = allItems.where((item) => item.active).length;
    final inactiveCount = allItems.length - activeCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPathHeader(
          title: group.title,
          subtitle: 'Manage checklist items in this group.',
          onBack: () => setState(() => _selectedGroupId = null),
          action: _buildPanelHeaderActionButton(
            onPressed: _saving ? null : () => _addItem(group),
            icon: Icons.add_rounded,
            label: 'Add Item',
          ),
        ),
        _buildStatusFilterBar(
          activeCount: activeCount,
          inactiveCount: inactiveCount,
          allCount: allItems.length,
          selected: _itemFilter,
          onChanged: (value) => setState(() => _itemFilter = value),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: group.items.isEmpty
                ? const Center(
                    child: Text(
                      'No items yet in this group.',
                      style: TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : visibleItems.isEmpty
                ? const Center(
                    child: Text(
                      'No items for this filter.',
                      style: TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: visibleItems.length,
                    itemBuilder: (context, index) {
                      final item = visibleItems[index];
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label,
                                    style: const TextStyle(
                                      color: _textDark,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_itemFilter == _SetupStatusFilter.all)
                              _buildStatusChip(item.active),
                            IconButton(
                              tooltip: 'Edit item',
                              onPressed: _saving
                                  ? null
                                  : () => _editItem(group, item),
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: _primary,
                              ),
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
  }
}

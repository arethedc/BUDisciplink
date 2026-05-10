import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../services/institution_setup_service.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';
import 'osa_common_widgets.dart';

const _bg = Colors.white;
const _primary = Color(0xFF1B5E20);
const _hint = Color(0xFF6D7F62);
const _text = Color(0xFF1F2A1F);

enum _StatusFilterOption { active, inactive, all }

bool _matchesStatusFilter(bool isActive, _StatusFilterOption filter) {
  switch (filter) {
    case _StatusFilterOption.active:
      return isActive;
    case _StatusFilterOption.inactive:
      return !isActive;
    case _StatusFilterOption.all:
      return true;
  }
}

class _InlineFilterTab {
  final String value;
  final String label;

  const _InlineFilterTab({required this.value, required this.label});
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
          color: selected ? _primary.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(filterRadius),
          border: Border.all(
            color: selected
                ? _primary.withValues(alpha: 0.36)
                : Colors.black.withValues(alpha: 0.10),
          ),
        ),
        child: Text(
          tab.label,
          style: TextStyle(
            color: selected ? _primary : _text,
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

InputDecoration _modalDecor({
  required String label,
  required IconData icon,
  String? helperText,
  bool enabled = true,
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
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _primary, width: 1.6),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

ButtonStyle _modalPrimaryButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: _primary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  );
}

Widget _buildPanelHeaderActionButton({
  required VoidCallback onPressed,
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

class _CategoryListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool active;
  final bool showStatus;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  const _CategoryListTile({
    required this.title,
    this.subtitle,
    required this.active,
    this.showStatus = false,
    required this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
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
            if (showStatus) _CompactStatusIndicator(active: active),
            if (onEdit != null)
              IconButton(
                tooltip: 'Edit Category',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: _primary,
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _ViolationTypeListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool active;
  final bool showStatus;
  final VoidCallback? onEdit;

  const _ViolationTypeListTile({
    required this.title,
    this.subtitle,
    required this.active,
    this.showStatus = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
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
          if (showStatus) _CompactStatusIndicator(active: active),
          if (onEdit != null)
            IconButton(
              tooltip: 'Edit Program',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: _primary,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _CompactStatusIndicator extends StatelessWidget {
  final bool active;

  const _CompactStatusIndicator({required this.active});

  @override
  Widget build(BuildContext context) {
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
}

class CollegesProgramsPane extends StatelessWidget {
  final String searchQuery;

  const CollegesProgramsPane({super.key, this.searchQuery = ''});

  @override
  Widget build(BuildContext context) {
    return _CollegesProgramsPane(searchQuery: searchQuery);
  }
}

class _CollegesProgramsPane extends StatefulWidget {
  final String searchQuery;

  const _CollegesProgramsPane({required this.searchQuery});

  @override
  State<_CollegesProgramsPane> createState() => _CollegesProgramsPaneState();
}

class _CollegesProgramsPaneState extends State<_CollegesProgramsPane> {
  final _institutionSvc = InstitutionSetupService();
  String? _selectedCollegeId;
  _StatusFilterOption _statusFilter = _StatusFilterOption.active;

  bool _matches(String source, String query) {
    if (query.isEmpty) return true;
    return source.toLowerCase().contains(query.toLowerCase());
  }

  String _str(dynamic value) => (value ?? '').toString().trim();

  void _showPaneSnack(String message, {bool error = false}) {
    if (!mounted) return;
    AppScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : _primary,
      ),
    );
  }

  Future<void> _openEditCollegeDialog({
    required String collegeId,
    required String initialCode,
    required String initialName,
    required bool initialActive,
  }) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditCollegeDialog(
        collegeId: collegeId,
        initialCode: initialCode,
        initialName: initialName,
        initialActive: initialActive,
      ),
    );
    if (updated == true) {
      _showPaneSnack('College updated.');
    }
  }

  Future<void> _openAddCollegeDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddCollegeDialog(),
    );
    if (created == true) {
      _showPaneSnack('College added.');
    }
  }

  Future<void> _openEditProgramDialog({
    required String programId,
    required String collegeId,
    required String initialCode,
    required String initialName,
    required bool initialActive,
  }) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditProgramDialog(
        programId: programId,
        collegeId: collegeId,
        initialCode: initialCode,
        initialName: initialName,
        initialActive: initialActive,
      ),
    );
    if (updated == true) {
      _showPaneSnack('Program updated.');
    }
  }

  Future<void> _openAddProgramDialog({required String collegeId}) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddProgramDialog(collegeId: collegeId),
    );
    if (created == true) {
      _showPaneSnack('Program added.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _institutionSvc.streamColleges(),
      builder: (context, collegesSnap) {
        if (collegesSnap.hasError) {
          return Center(
            child: Text('Error loading colleges: ${collegesSnap.error}'),
          );
        }
        if (!collegesSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _institutionSvc.streamPrograms(),
          builder: (context, programsSnap) {
            if (programsSnap.hasError) {
              return Center(
                child: Text('Error loading programs: ${programsSnap.error}'),
              );
            }
            if (!programsSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final collegeDocs = collegesSnap.data!.docs.toList();
            final programDocs = programsSnap.data!.docs.toList();

            final programsByCollege =
                <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
            for (final programDoc in programDocs) {
              final row = programDoc.data();
              final collegeId = _str(row['collegeId']);
              if (collegeId.isEmpty) continue;
              programsByCollege
                  .putIfAbsent(collegeId, () => [])
                  .add(programDoc);
            }

            final sortedColleges = [...collegeDocs]
              ..sort((a, b) {
                final ao = (a.data()['sortOrder'] as num?)?.toInt() ?? 999;
                final bo = (b.data()['sortOrder'] as num?)?.toInt() ?? 999;
                if (ao != bo) return ao.compareTo(bo);
                return _str(
                  a.data()['collegeCode'],
                ).compareTo(_str(b.data()['collegeCode']));
              });

            if (_selectedCollegeId != null &&
                sortedColleges.every((doc) => doc.id != _selectedCollegeId)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _selectedCollegeId = null;
                });
              });
            }

            if (sortedColleges.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final maxPanelWidth = constraints.maxWidth >= 1600
                      ? 1180.0
                      : constraints.maxWidth >= 1200
                      ? 1080.0
                      : constraints.maxWidth;
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxPanelWidth),
                        child: SizedBox(
                          width: double.infinity,
                          child: OsaPanelCard(
                            child: const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No colleges/programs found yet.',
                                style: TextStyle(
                                  color: _hint,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            }

            final body = _selectedCollegeId == null
                ? _buildCollegesLevel(
                    colleges: sortedColleges,
                    programsByCollege: programsByCollege,
                  )
                : _buildProgramsLevel(
                    colleges: sortedColleges,
                    programsByCollege: programsByCollege,
                    selectedCollegeId: _selectedCollegeId!,
                  );

            return LayoutBuilder(
              builder: (context, constraints) {
                final maxPanelWidth = constraints.maxWidth >= 1600
                    ? 1180.0
                    : constraints.maxWidth >= 1200
                    ? 1080.0
                    : constraints.maxWidth;
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
            );
          },
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
                        color: _text,
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
                        color: _text,
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
    required VoidCallback onBack,
    String? subtitle,
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
                        color: _text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
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
                  ],
                ),
              ),
              if (!stacked && action != null) ...[
                const SizedBox(width: 4),
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
    required int allCount,
    required int activeCount,
    required int inactiveCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _buildReviewStyleFilterBar(
        selectedValue: _statusFilter.name,
        onSelect: (value) {
          setState(() {
            _statusFilter = value == 'inactive'
                ? _StatusFilterOption.inactive
                : value == 'all'
                ? _StatusFilterOption.all
                : _StatusFilterOption.active;
          });
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

  Widget _buildCollegesLevel({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> colleges,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    programsByCollege,
  }) {
    final query = widget.searchQuery.trim();
    final filteredByQuery = colleges.where((collegeDoc) {
      final c = collegeDoc.data();
      final code = _str(c['collegeCode']).isEmpty
          ? collegeDoc.id
          : _str(c['collegeCode']);
      final name = _str(c['name']);
      final programs =
          programsByCollege[collegeDoc.id] ??
          <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final searchable =
          '$code $name ${programs.map((p) => '${_str(p.data()['programCode'])} ${_str(p.data()['name'])}').join(' ')}';
      return _matches(searchable, query);
    }).toList();

    final allCount = filteredByQuery.length;
    final activeCount = filteredByQuery
        .where((doc) => doc.data()['active'] != false)
        .length;
    final inactiveCount = allCount - activeCount;
    final listDocs = filteredByQuery
        .where(
          (doc) => _matchesStatusFilter(
            doc.data()['active'] != false,
            _statusFilter,
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopHeader(
          title: 'Colleges & Programs',
          subtitle: 'Select a college to view and manage programs.',
          action: _buildPanelHeaderActionButton(
            onPressed: _openAddCollegeDialog,
            icon: Icons.add_rounded,
            label: 'Add College',
          ),
        ),
        _buildStatusFilterBar(
          allCount: allCount,
          activeCount: activeCount,
          inactiveCount: inactiveCount,
        ),
        Expanded(
          child: listDocs.isEmpty
              ? Center(
                  child: Text(
                    query.isNotEmpty
                        ? 'No matching colleges.'
                        : 'No colleges for this filter.',
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: listDocs.length,
                  itemBuilder: (context, index) {
                    final doc = listDocs[index];
                    final data = doc.data();
                    final code = _str(data['collegeCode']).isEmpty
                        ? doc.id
                        : _str(data['collegeCode']);
                    final name = _str(data['name']);
                    final programsCount =
                        (programsByCollege[doc.id] ?? const []).length;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: _CategoryListTile(
                        title: '$code ($programsCount)',
                        subtitle: name.isEmpty ? null : name,
                        active: data['active'] != false,
                        showStatus: _statusFilter == _StatusFilterOption.all,
                        onEdit: () => _openEditCollegeDialog(
                          collegeId: doc.id,
                          initialCode: code,
                          initialName: name,
                          initialActive: data['active'] != false,
                        ),
                        onTap: () {
                          setState(() {
                            _selectedCollegeId = doc.id;
                          });
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProgramsLevel({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> colleges,
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    programsByCollege,
    required String selectedCollegeId,
  }) {
    final query = widget.searchQuery.trim();
    final selectedCollege = colleges.firstWhere(
      (doc) => doc.id == selectedCollegeId,
      orElse: () => colleges.first,
    );
    final collegeData = selectedCollege.data();
    final collegeCode = _str(collegeData['collegeCode']).isEmpty
        ? selectedCollege.id
        : _str(collegeData['collegeCode']);

    final allPrograms =
        (programsByCollege[selectedCollegeId] ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .toList()
          ..sort((a, b) {
            final ao = (a.data()['sortOrder'] as num?)?.toInt() ?? 999;
            final bo = (b.data()['sortOrder'] as num?)?.toInt() ?? 999;
            if (ao != bo) return ao.compareTo(bo);
            final ac = _str(a.data()['programCode']).isEmpty
                ? a.id
                : _str(a.data()['programCode']);
            final bc = _str(b.data()['programCode']).isEmpty
                ? b.id
                : _str(b.data()['programCode']);
            return ac.compareTo(bc);
          });

    final filteredByQuery = allPrograms.where((programDoc) {
      final p = programDoc.data();
      final code = _str(p['programCode']).isEmpty
          ? programDoc.id
          : _str(p['programCode']);
      final name = _str(p['name']);
      return _matches('$code $name', query);
    }).toList();

    final allCount = filteredByQuery.length;
    final activeCount = filteredByQuery
        .where((doc) => doc.data()['active'] != false)
        .length;
    final inactiveCount = allCount - activeCount;
    final listDocs = filteredByQuery
        .where(
          (doc) => _matchesStatusFilter(
            doc.data()['active'] != false,
            _statusFilter,
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPathHeader(
          title: 'Programs',
          subtitle: collegeCode,
          onBack: () => setState(() {
            _selectedCollegeId = null;
          }),
          action: _buildPanelHeaderActionButton(
            onPressed: () =>
                _openAddProgramDialog(collegeId: selectedCollegeId),
            icon: Icons.add_rounded,
            label: 'Add Program',
          ),
        ),
        _buildStatusFilterBar(
          allCount: allCount,
          activeCount: activeCount,
          inactiveCount: inactiveCount,
        ),
        Expanded(
          child: listDocs.isEmpty
              ? Center(
                  child: Text(
                    query.isNotEmpty
                        ? 'No matching programs.'
                        : 'No programs for this filter.',
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: listDocs.length,
                  itemBuilder: (context, index) {
                    final doc = listDocs[index];
                    final data = doc.data();
                    final code = _str(data['programCode']).isEmpty
                        ? doc.id
                        : _str(data['programCode']);
                    final name = _str(data['name']);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: _ViolationTypeListTile(
                        title: code,
                        subtitle: name.isEmpty ? null : name,
                        active: data['active'] != false,
                        showStatus: _statusFilter == _StatusFilterOption.all,
                        onEdit: () => _openEditProgramDialog(
                          programId: doc.id,
                          collegeId: selectedCollegeId,
                          initialCode: code,
                          initialName: name,
                          initialActive: data['active'] != false,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AddCollegeDialog extends StatefulWidget {
  const _AddCollegeDialog();

  @override
  State<_AddCollegeDialog> createState() => _AddCollegeDialogState();
}

class _AddCollegeDialogState extends State<_AddCollegeDialog> {
  final _institutionSvc = InstitutionSetupService();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Add College',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _codeCtrl,
                enabled: !_saving,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'College Code',
                  icon: Icons.account_balance_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                enabled: !_saving,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'College Name',
                  icon: Icons.school_outlined,
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(color: _primary),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
          ),
        ),
        FilledButton(
          style: _modalPrimaryButtonStyle(),
          onPressed: _saving
              ? null
              : () async {
                  final rawCode = _codeCtrl.text.trim();
                  final name = _nameCtrl.text.trim();
                  if (rawCode.isEmpty || name.isEmpty) return;
                  final code = rawCode.toUpperCase();
                  setState(() => _saving = true);
                  try {
                    final duplicate = await _institutionSvc.collegeCodeExists(
                      code,
                    );
                    if (duplicate) {
                      if (!context.mounted) return;
                      AppScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('College code already exists.'),
                        ),
                      );
                      setState(() => _saving = false);
                      return;
                    }

                    await _institutionSvc.createCollege(code: code, name: name);
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    AppScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Add failed: $e')));
                    setState(() => _saving = false);
                  }
                },
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _AddProgramDialog extends StatefulWidget {
  final String collegeId;

  const _AddProgramDialog({required this.collegeId});

  @override
  State<_AddProgramDialog> createState() => _AddProgramDialogState();
}

class _AddProgramDialogState extends State<_AddProgramDialog> {
  final _institutionSvc = InstitutionSetupService();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Add Program',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _codeCtrl,
                enabled: !_saving,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Program Code',
                  icon: Icons.badge_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                enabled: !_saving,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Program Name',
                  icon: Icons.menu_book_rounded,
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(color: _primary),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
          ),
        ),
        FilledButton(
          style: _modalPrimaryButtonStyle(),
          onPressed: _saving
              ? null
              : () async {
                  final rawCode = _codeCtrl.text.trim();
                  final name = _nameCtrl.text.trim();
                  if (rawCode.isEmpty || name.isEmpty) return;
                  final code = rawCode.toUpperCase();
                  setState(() => _saving = true);
                  try {
                    final duplicate = await _institutionSvc
                        .programCodeExistsInCollege(widget.collegeId, code);
                    if (duplicate) {
                      if (!context.mounted) return;
                      AppScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Program code already exists for this college.',
                          ),
                        ),
                      );
                      setState(() => _saving = false);
                      return;
                    }

                    await _institutionSvc.createProgram(
                      collegeId: widget.collegeId,
                      code: code,
                      name: name,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    AppScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Add failed: $e')));
                    setState(() => _saving = false);
                  }
                },
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _EditCollegeDialog extends StatefulWidget {
  final String collegeId;
  final String initialCode;
  final String initialName;
  final bool initialActive;

  const _EditCollegeDialog({
    required this.collegeId,
    required this.initialCode,
    required this.initialName,
    required this.initialActive,
  });

  @override
  State<_EditCollegeDialog> createState() => _EditCollegeDialogState();
}

class _EditCollegeDialogState extends State<_EditCollegeDialog> {
  final _institutionSvc = InstitutionSetupService();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.initialCode);
    _nameCtrl = TextEditingController(text: widget.initialName);
    _active = widget.initialActive;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Edit College',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _codeCtrl,
                enabled: !_saving,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'College Code',
                  icon: Icons.account_balance_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                enabled: !_saving,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'College Name',
                  icon: Icons.school_outlined,
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(color: _primary),
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
                onPressed: _saving
                    ? null
                    : () => setState(() => _active = !_active),
                style: TextButton.styleFrom(
                  foregroundColor: _active ? _primary : _hint,
                  backgroundColor: _active
                      ? _primary.withValues(alpha: 0.10)
                      : Colors.grey.withValues(alpha: 0.10),
                  side: BorderSide(
                    color: _active
                        ? _primary.withValues(alpha: 0.55)
                        : Colors.black.withValues(alpha: 0.20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: Icon(
                  _active ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                ),
                label: Text(
                  _active ? 'Active' : 'Inactive',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: _modalPrimaryButtonStyle(),
                onPressed: _saving
                    ? null
                    : () async {
                        final code = _codeCtrl.text.trim();
                        final name = _nameCtrl.text.trim();
                        if (code.isEmpty || name.isEmpty) return;
                        setState(() => _saving = true);
                        try {
                          await _institutionSvc.updateCollege(
                            collegeId: widget.collegeId,
                            code: code,
                            name: name,
                            active: _active,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } catch (e) {
                          if (!context.mounted) return;
                          AppScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Update failed: $e')),
                          );
                          setState(() => _saving = false);
                        }
                      },
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditProgramDialog extends StatefulWidget {
  final String programId;
  final String collegeId;
  final String initialCode;
  final String initialName;
  final bool initialActive;

  const _EditProgramDialog({
    required this.programId,
    required this.collegeId,
    required this.initialCode,
    required this.initialName,
    required this.initialActive,
  });

  @override
  State<_EditProgramDialog> createState() => _EditProgramDialogState();
}

class _EditProgramDialogState extends State<_EditProgramDialog> {
  final _institutionSvc = InstitutionSetupService();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.initialCode);
    _nameCtrl = TextEditingController(text: widget.initialName);
    _active = widget.initialActive;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Edit Program',
        style: TextStyle(fontWeight: FontWeight.w900, color: _primary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _codeCtrl,
                enabled: !_saving,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Program Code',
                  icon: Icons.badge_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                enabled: !_saving,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
                decoration: _modalDecor(
                  label: 'Program Name',
                  icon: Icons.menu_book_rounded,
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(color: _primary),
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
                onPressed: _saving
                    ? null
                    : () => setState(() => _active = !_active),
                style: TextButton.styleFrom(
                  foregroundColor: _active ? _primary : _hint,
                  backgroundColor: _active
                      ? _primary.withValues(alpha: 0.10)
                      : Colors.grey.withValues(alpha: 0.10),
                  side: BorderSide(
                    color: _active
                        ? _primary.withValues(alpha: 0.55)
                        : Colors.black.withValues(alpha: 0.20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: Icon(
                  _active ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                ),
                label: Text(
                  _active ? 'Active' : 'Inactive',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w900, color: _hint),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: _modalPrimaryButtonStyle(),
                onPressed: _saving
                    ? null
                    : () async {
                        final code = _codeCtrl.text.trim();
                        final name = _nameCtrl.text.trim();
                        if (code.isEmpty || name.isEmpty) return;
                        setState(() => _saving = true);
                        try {
                          await _institutionSvc.updateProgram(
                            programId: widget.programId,
                            collegeId: widget.collegeId,
                            code: code,
                            name: name,
                            active: _active,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } catch (e) {
                          if (!context.mounted) return;
                          AppScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Update failed: $e')),
                          );
                          setState(() => _saving = false);
                        }
                      },
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

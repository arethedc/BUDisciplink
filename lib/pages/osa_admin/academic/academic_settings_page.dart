import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:apps/services/academic_settings_service.dart';

/// ============================================================
/// ACADEMIC SETTINGS (ADMIN) — UI TEMPLATE ONLY
/// ✅ Desktop-first layout (table + right panel)
/// ✅ No real data details / no validation logic yet
/// ✅ Placeholders only for Firestore service calls
/// ✅ You already have sidebar + appbar, so this is body-only.
/// ============================================================
///
/// Firestore target structure (for later):
/// academic_years/{syId}
///   - label, status(active/archived), activeTermId
/// academic_years/{syId}/terms/{term1|term2|term3}
///   - name, order, startAt, endAt

class AcademicSettingsPage extends StatefulWidget {
  const AcademicSettingsPage({super.key});

  @override
  State<AcademicSettingsPage> createState() => _AcademicSettingsPageState();
}

class _AcademicSettingsPageState extends State<AcademicSettingsPage> {
  // UI state only
  String _search = '';
  int? _selectedIndex;

  // Create SY modal state
  final _syLabelCtrl = TextEditingController();

  final _academicService = AcademicSettingsService();

  @override
  void dispose() {
    _syLabelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final desktop = w >= 1100;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _Header(
                    title: 'Academic Settings',
                    subtitle:
                        'Create school years, configure 3 semesters, and set the active term.',
                    onCreateSY: () => _openCreateSYModal(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: _Toolbar(
                    onSearchChanged: (v) => setState(() => _search = v),
                    onRefresh: () => setState(() {}),
                  ),
                ),

                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _academicService.streamYears(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(child: Text('Error: ${snap.error}'));
                      }
                      if (!snap.hasData || snap.data!.docs.isEmpty) {
                        return const _EmptyState(
                          text: 'No school years found.',
                        );
                      }

                      final raw = snap.data!.docs;

                      final docs = raw.where((d) {
                        if (_search.trim().isEmpty) return true;
                        final q = _search.toLowerCase().trim();
                        final label = _safeStr(d.data()['label']).toLowerCase();
                        final status = _safeStr(
                          d.data()['status'],
                        ).toLowerCase();
                        return label.contains(q) || status.contains(q);
                      }).toList();

                      if (_selectedIndex != null &&
                          (_selectedIndex! < 0 ||
                              _selectedIndex! >= docs.length)) {
                        _selectedIndex = null;
                      }

                      final selected = (_selectedIndex != null)
                          ? docs[_selectedIndex!]
                          : null;

                      final showTableOnly = desktop && selected == null;
                      final showTableAndPanel = desktop && selected != null;

                      if (!desktop) {
                        // Mobile fallback: list + open modal for manage
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _MobileList(
                            docs: docs,
                            onOpenManage: (doc) =>
                                _openManageTermsModal(context, doc),
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: showTableAndPanel ? 3 : 1,
                              child: _SYTablePanel(
                                docs: docs,
                                selectedIndex: _selectedIndex,
                                onSelect: (i) => setState(
                                  () => _selectedIndex = (_selectedIndex == i
                                      ? null
                                      : i),
                                ),
                              ),
                            ),
                            if (selected != null) ...[
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 2,
                                child: _ManageTermsPanel(
                                  syDoc: selected,
                                  onClose: () =>
                                      setState(() => _selectedIndex = null),
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
            );
          },
        ),
      ),
    );
  }

  // -------------------------
  // Create School Year Modal
  // -------------------------
  void _openCreateSYModal(BuildContext context) {
    _syLabelCtrl.clear();

    showDialog(
      context: context,
      builder: (_) {
        final cs = Theme.of(context).colorScheme;

        return AlertDialog(
          backgroundColor: cs.surface,
          surfaceTintColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'New School Year',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter the label for the new academic year.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _syLabelCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'SY Label',
                    hintText: 'e.g. 2025-2026',
                    filled: true,
                    fillColor: cs.surfaceContainerLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: cs.onSecondaryContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You will configure term dates after creating.',
                          style: TextStyle(
                            color: cs.onSecondaryContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final label = _syLabelCtrl.text.trim();
                if (label.isEmpty) return;

                try {
                  await _academicService.createSchoolYear(
                    syId: label,
                    label: label,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('School Year created.')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }

                if (context.mounted) Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  // -------------------------
  // Manage Terms Modal (Mobile)
  // -------------------------
  void _openManageTermsModal(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> syDoc,
  ) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.60,
          maxChildSize: 0.96,
          builder: (context, scrollCtrl) {
            return Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
              ),
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                child: _ManageTermsPanel(
                  syDoc: syDoc,
                  isModal: true,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ======================================================================
// HEADER + TOOLBAR
// ======================================================================

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onCreateSY;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.onCreateSY,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 450;

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: isNarrow ? 22 : 28,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: isNarrow ? 12 : 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isNarrow)
              IconButton.filled(
                onPressed: onCreateSY,
                icon: const Icon(Icons.add_rounded),
                tooltip: 'New School Year',
              )
            else
              FilledButton.icon(
                onPressed: onCreateSY,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'New School Year',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;

  const _Toolbar({required this.onSearchChanged, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search school years...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: cs.surfaceContainerLowest,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed: onRefresh,
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
        ),
      ],
    );
  }
}

// ======================================================================
// LEFT: SY TABLE PANEL (DESKTOP)
// ======================================================================

class _SYTablePanel extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  const _SYTablePanel({
    required this.docs,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelTitle(
            icon: Icons.calendar_month_rounded,
            title: 'School Years',
            subtitle: 'Select a school year to manage terms.',
          ),
          const Divider(height: 1),
          const _SYHeaderRow(),
          const Divider(height: 1),
          Expanded(
            child: docs.isEmpty
                ? const _EmptyState(text: 'No school years found.')
                : ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      return _SYRow(
                        doc: docs[i],
                        selected: selectedIndex == i,
                        onTap: () => onSelect(i),
                        isLast: i == docs.length - 1,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SYHeaderRow extends StatelessWidget {
  const _SYHeaderRow();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.bold,
      fontSize: 12,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final hideTerm = constraints.maxWidth < 500;

        return Container(
          color: cs.surfaceContainerLowest,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('SCHOOL YEAR', style: style)),
              Expanded(flex: 2, child: Text('STATUS', style: style)),
              if (!hideTerm)
                Expanded(flex: 2, child: Text('ACTIVE TERM', style: style)),
              const SizedBox(width: 48), // Space for action/chevron
            ],
          ),
        );
      },
    );
  }
}

class _SYRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;
  final VoidCallback onTap;
  final bool isLast;

  const _SYRow({
    required this.doc,
    required this.selected,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = doc.data();

    final label = _safeStr(d['label']).isEmpty ? doc.id : _safeStr(d['label']);
    final status = _safeStr(d['status']).isEmpty
        ? 'archived'
        : _safeStr(d['status']);
    final activeTermId = _safeStr(d['activeTermId']).isEmpty
        ? 'term1'
        : _safeStr(d['activeTermId']);

    final isActive = status.toLowerCase() == 'active';

    return LayoutBuilder(
      builder: (context, constraints) {
        final hideTerm = constraints.maxWidth < 500;

        return Column(
          children: [
            InkWell(
              onTap: onTap,
              child: Container(
                color: selected
                    ? cs.primaryContainer.withValues(alpha: 0.3)
                    : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: isActive
                                    ? cs.onPrimaryContainer
                                    : cs.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!hideTerm)
                      Expanded(
                        flex: 2,
                        child: Text(
                          _termIdToLabel(activeTermId),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    Icon(
                      selected
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_right_rounded,
                      color: selected
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
            if (!isLast) const Divider(height: 1, indent: 24, endIndent: 24),
          ],
        );
      },
    );
  }
}

// ======================================================================
// RIGHT: MANAGE TERMS PANEL (DESKTOP / MODAL CONTENT)
// ======================================================================

class _ManageTermsPanel extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> syDoc;
  final bool isModal;
  final VoidCallback? onClose;

  const _ManageTermsPanel({
    required this.syDoc,
    this.isModal = false,
    this.onClose,
  });

  @override
  State<_ManageTermsPanel> createState() => _ManageTermsPanelState();
}

class _ManageTermsPanelState extends State<_ManageTermsPanel> {
  final _academicService = AcademicSettingsService();
  String _activeTermId = 'term1';
  DateTime? _t1Start, _t1End;
  DateTime? _t2Start, _t2End;
  DateTime? _t3Start, _t3End;

  bool _saving = false;

  String? _validateDates() {
    final pairs = [
      ('1st Sem', _t1Start, _t1End),
      ('2nd Sem', _t2Start, _t2End),
      ('3rd Sem', _t3Start, _t3End),
    ];

    for (final p in pairs) {
      final name = p.$1;
      final s = p.$2;
      final e = p.$3;
      if (s == null || e == null) {
        return '$name: start and end dates are required.';
      }
      if (!s.isBefore(e)) return '$name: start date must be before end date.';
    }

    if (!(_t1End!.isBefore(_t2Start!) || _sameDay(_t1End!, _t2Start!))) {
      return '1st Sem must end before 2nd Sem starts.';
    }
    if (!(_t2End!.isBefore(_t3Start!) || _sameDay(_t2End!, _t3Start!))) {
      return '2nd Sem must end before 3rd Sem starts.';
    }

    return null;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate(BuildContext context, bool start, String term) async {
    final initial = (term == 'term1')
        ? (start ? _t1Start : _t1End)
        : (term == 'term2')
        ? (start ? _t2Start : _t2End)
        : (start ? _t3Start : _t3End);

    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date == null) return;
    setState(() {
      if (term == 'term1') {
        if (start) {
          _t1Start = date;
        } else {
          _t1End = date;
        }
      } else if (term == 'term2') {
        if (start) {
          _t2Start = date;
        } else {
          _t2End = date;
        }
      } else if (term == 'term3') {
        if (start) {
          _t3Start = date;
        } else {
          _t3End = date;
        }
      }
    });
  }

  void _loadTerms() async {
    final termsSnap = await _academicService.streamTerms(widget.syDoc.id).first;
    if (!mounted) return;
    setState(() {
      for (final doc in termsSnap.docs) {
        final data = doc.data();
        final start = data['startAt'] as Timestamp?;
        final end = data['endAt'] as Timestamp?;
        if (doc.id == 'term1') {
          _t1Start = start?.toDate();
          _t1End = end?.toDate();
        } else if (doc.id == 'term2') {
          _t2Start = start?.toDate();
          _t2End = end?.toDate();
        } else if (doc.id == 'term3') {
          _t3Start = start?.toDate();
          _t3End = end?.toDate();
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final d = widget.syDoc.data();
    _activeTermId = _safeStr(d['activeTermId']).isEmpty
        ? 'term1'
        : _safeStr(d['activeTermId']);
    _loadTerms();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.syDoc.data();
    final label = _safeStr(d['label']).isEmpty
        ? widget.syDoc.id
        : _safeStr(d['label']);
    final status = _safeStr(d['status']).toLowerCase();
    final isActive = status == 'active';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: cs.surfaceContainerLowest,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.tune_rounded, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage SY $label',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        isActive ? 'Currently Active' : 'Archived School Year',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TermSection(
                    title: '1st Semester',
                    start: _t1Start,
                    end: _t1End,
                    onPickStart: () => _pickDate(context, true, 'term1'),
                    onPickEnd: () => _pickDate(context, false, 'term1'),
                  ),
                  const SizedBox(height: 16),
                  _TermSection(
                    title: '2nd Semester',
                    start: _t2Start,
                    end: _t2End,
                    onPickStart: () => _pickDate(context, true, 'term2'),
                    onPickEnd: () => _pickDate(context, false, 'term2'),
                  ),
                  const SizedBox(height: 16),
                  _TermSection(
                    title: '3rd Semester',
                    start: _t3Start,
                    end: _t3End,
                    onPickStart: () => _pickDate(context, true, 'term3'),
                    onPickEnd: () => _pickDate(context, false, 'term3'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Active Semester',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _activeTermId,
                    items: const [
                      DropdownMenuItem(
                        value: 'term1',
                        child: Text('1st Semester'),
                      ),
                      DropdownMenuItem(
                        value: 'term2',
                        child: Text('2nd Semester'),
                      ),
                      DropdownMenuItem(
                        value: 'term3',
                        child: Text('3rd Semester'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _activeTermId = v ?? 'term1'),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cs.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_saving)
                    const LinearProgressIndicator()
                  else
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () async {
                              final err = _validateDates();
                              if (err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Cannot activate: $err'),
                                  ),
                                );
                                return;
                              }

                              setState(() => _saving = true);
                              try {
                                await _academicService.saveTermsAndActiveTerm(
                                  syId: widget.syDoc.id,
                                  activeTermId: _activeTermId,
                                  termDates: {
                                    'term1': TermDates(
                                      startAt: Timestamp.fromDate(_t1Start!),
                                      endAt: Timestamp.fromDate(_t1End!),
                                    ),
                                    'term2': TermDates(
                                      startAt: Timestamp.fromDate(_t2Start!),
                                      endAt: Timestamp.fromDate(_t2End!),
                                    ),
                                    'term3': TermDates(
                                      startAt: Timestamp.fromDate(_t3Start!),
                                      endAt: Timestamp.fromDate(_t3End!),
                                    ),
                                  },
                                );
                                await _academicService.setActiveSchoolYear(
                                  widget.syDoc.id,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'School Year set as active.',
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Set as Active School Year'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () async {
                              setState(() => _saving = true);
                              try {
                                await _academicService.saveTermsAndActiveTerm(
                                  syId: widget.syDoc.id,
                                  activeTermId: _activeTermId,
                                  termDates: {
                                    'term1': TermDates(
                                      startAt: _t1Start != null
                                          ? Timestamp.fromDate(_t1Start!)
                                          : null,
                                      endAt: _t1End != null
                                          ? Timestamp.fromDate(_t1End!)
                                          : null,
                                    ),
                                    'term2': TermDates(
                                      startAt: _t2Start != null
                                          ? Timestamp.fromDate(_t2Start!)
                                          : null,
                                      endAt: _t2End != null
                                          ? Timestamp.fromDate(_t2End!)
                                          : null,
                                    ),
                                    'term3': TermDates(
                                      startAt: _t3Start != null
                                          ? Timestamp.fromDate(_t3Start!)
                                          : null,
                                      endAt: _t3End != null
                                          ? Timestamp.fromDate(_t3End!)
                                          : null,
                                    ),
                                  },
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Changes saved.'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Save Draft'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TermSection extends StatelessWidget {
  final String title;
  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _TermSection({
    required this.title,
    this.start,
    this.end,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useVertical = constraints.maxWidth < 340;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (useVertical) ...[
              _DateButton(label: 'Start Date', date: start, onTap: onPickStart),
              const SizedBox(height: 8),
              _DateButton(label: 'End Date', date: end, onTap: onPickEnd),
            ] else
              Row(
                children: [
                  Expanded(
                    child: _DateButton(
                      label: 'Start Date',
                      date: start,
                      onTap: onPickStart,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateButton(
                      label: 'End Date',
                      date: end,
                      onTap: onPickEnd,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateButton({required this.label, this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              date == null
                  ? 'Select'
                  : '${date!.month}/${date!.day}/${date!.year}',
              style: TextStyle(
                color: date == null ? cs.onSurfaceVariant : cs.onSurface,
                fontSize: 13,
                fontWeight: date == null ? FontWeight.normal : FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// MOBILE LIST
// ======================================================================

class _MobileList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final void Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)
  onOpenManage;

  const _MobileList({required this.docs, required this.onOpenManage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (docs.isEmpty) {
      return const _EmptyState(text: 'No school years found.');
    }

    return ListView.builder(
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final d = docs[i].data();
        final label = _safeStr(d['label']).isEmpty
            ? docs[i].id
            : _safeStr(d['label']);
        final status = _safeStr(d['status']).isEmpty
            ? 'archived'
            : _safeStr(d['status']);
        final activeTermId = _safeStr(d['activeTermId']).isEmpty
            ? 'term1'
            : _safeStr(d['activeTermId']);
        final isActive = status.toLowerCase() == 'active';

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onOpenManage(docs[i]),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.calendar_today_rounded,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? cs.primaryContainer
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: isActive
                                      ? cs.onPrimaryContainer
                                      : cs.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _termIdToLabel(activeTermId),
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ======================================================================
// REUSABLE UI PIECES
// ======================================================================

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PanelTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _TermCard extends StatelessWidget {
  final String title;
  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _TermCard({
    required this.title,
    required this.start,
    required this.end,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String fmt(DateTime? d) => d == null
        ? 'Not set'
        : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DateBox(
                  label: 'Start Date',
                  value: fmt(start),
                  onTap: onPickStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateBox(
                  label: 'End Date',
                  value: fmt(end),
                  onTap: onPickEnd,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateBox({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                fontSize: 12.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final _Tone tone;

  const _Pill({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: tone.text,
          fontWeight: FontWeight.w900,
          fontSize: 12.0,
        ),
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  final String text;
  const _HintText(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        fontSize: 12.2,
      ),
    );
  }
}

// ======================================================================
// STATES
// ======================================================================

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          "Error:\n$error",
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.error, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

// ======================================================================
// HELPERS
// ======================================================================

class _Tone {
  final Color fill;
  final Color border;
  final Color text;

  const _Tone({required this.fill, required this.border, required this.text});
}

String _safeStr(dynamic v) => (v ?? '').toString().trim();

String _titleCase(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  final parts = t.replaceAll('_', ' ').split(RegExp(r'\s+'));
  return parts
      .map(
        (p) =>
            p.isEmpty ? p : p[0].toUpperCase() + p.substring(1).toLowerCase(),
      )
      .join(' ');
}

String _termIdToLabel(String termId) {
  switch (termId) {
    case 'term1':
      return '1st Sem';
    case 'term2':
      return '2nd Sem';
    case 'term3':
      return '3rd Sem';
    default:
      return termId;
  }
}

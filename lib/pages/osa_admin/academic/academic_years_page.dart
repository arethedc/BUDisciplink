import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/modern_table_layout.dart';
import '../../../services/academic_settings_service.dart';

const bg = Color(0xFFF5F6FB);
const headerGreen = Color(0xFF2F6C44);
const dark = Color(0xFF243024);
const muted = Color(0xFF5B665B);

class AcademicYearsPage extends StatefulWidget {
  const AcademicYearsPage({super.key});

  @override
  State<AcademicYearsPage> createState() => _AcademicYearsPageState();
}

class _AcademicYearsPageState extends State<AcademicYearsPage> {
  final _svc = AcademicSettingsService();
  final _searchCtrl = TextEditingController();
  String? _selectedSyId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1100;
        return Scaffold(
          backgroundColor: bg,
          body: ModernTableLayout(
            detailsWidth: (constraints.maxWidth * 0.38)
                .clamp(380.0, 520.0)
                .toDouble(),
            header: ModernTableHeader(
              title: 'Academic Settings',
              subtitle:
                  'Create school years, configure terms, and set active school year.',
              action: FilledButton.icon(
                onPressed: _openCreateSY,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Create School Year',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              searchBar: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search school year...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _svc.streamYears(),
              builder: (context, snap) {
                if (snap.hasError) return _ErrorBox(snap.error.toString());
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final q = _searchCtrl.text.toLowerCase().trim();
                final docs = snap.data!.docs.where((doc) {
                  if (q.isEmpty) return true;
                  final d = doc.data();
                  final label = (d['label'] ?? doc.id).toString().toLowerCase();
                  final status = _normalizeYearStatus(
                    (d['status'] ?? 'inactive').toString(),
                  );
                  return label.contains(q) || status.contains(q);
                }).toList();

                if (_selectedSyId != null &&
                    !docs.any((d) => d.id == _selectedSyId)) {
                  _selectedSyId = null;
                }

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No School Years yet. Click "Create School Year".',
                      style: TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  );
                }

                if (!isDesktop) return _buildMobileList(docs);
                return _buildDesktopTable(docs);
              },
            ),
            showDetails: isDesktop && _selectedSyId != null,
            details: isDesktop && _selectedSyId != null
                ? _YearDetailsPanel(
                    syId: _selectedSyId!,
                    service: _svc,
                    onClose: () => setState(() => _selectedSyId = null),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildDesktopTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DataTable(
            showCheckboxColumn: false,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF6FAF6)),
            dataRowColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return headerGreen.withValues(alpha: 0.10);
              }
              return null;
            }),
            columnSpacing: 16,
            horizontalMargin: 12,
            columns: const [
              DataColumn(
                label: Text(
                  'SCHOOL YEAR',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: muted,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'ACTIVE TERM',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: muted,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'STATUS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: muted,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
            rows: docs.map((doc) {
              final d = doc.data();
              final label = (d['label'] ?? doc.id).toString();
              final status = _normalizeYearStatus(
                (d['status'] ?? 'inactive').toString(),
              );
              final activeTermId = (d['activeTermId'] ?? 'term1').toString();
              final selected = _selectedSyId == doc.id;

              return DataRow(
                selected: selected,
                onSelectChanged: (_) =>
                    setState(() => _selectedSyId = selected ? null : doc.id),
                cells: [
                  DataCell(
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: dark,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _termLabel(activeTermId),
                      style: const TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataCell(_buildStatusChip(status)),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final d = doc.data();
        final label = (d['label'] ?? doc.id).toString();
        final status = _normalizeYearStatus(
          (d['status'] ?? 'inactive').toString(),
        );
        final activeTermId = (d['activeTermId'] ?? 'term1').toString();

        return GestureDetector(
          onTap: () => _openMobileManageSheet(doc.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: dark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusChip(status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: headerGreen.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: headerGreen.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Text(
                          'ACTIVE TERM: ${_termLabel(activeTermId).toUpperCase()}',
                          style: const TextStyle(
                            color: headerGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (status != 'active') ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () =>
                                _confirmAndSetActiveYear(syId: doc.id, label: label),
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('Set Active'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: muted),
              ],
            ),
          ),
        );
      },
    );
  }

  String _normalizeYearStatus(String status) {
    final normalized = status.toLowerCase().trim();
    if (normalized == 'archived') return 'inactive';
    if (normalized.isEmpty) return 'inactive';
    return normalized;
  }

  Widget _buildStatusChip(String status) {
    final normalized = _normalizeYearStatus(status);
    final isActive = normalized == 'active';
    final color = isActive ? Colors.green : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        normalized.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _confirmAndSetActiveYear({
    required String syId,
    required String label,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Activate School Year?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Are you sure you want to activate $label?\n\n'
          'All other school years will be set to inactive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _svc.setActiveSchoolYear(syId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label is now ACTIVE')));
  }

  String _termLabel(String activeTermId) {
    if (activeTermId == 'term1') return '1st Sem';
    if (activeTermId == 'term2') return '2nd Sem';
    return '3rd Sem';
  }

  Future<void> _openCreateSY() async {
    Set<String> existingLabels = <String>{};
    String? currentAcademicYearLabel;

    try {
      final snap = await _svc.streamYears().first;
      final docs = snap.docs;
      existingLabels = docs
          .map((d) => (d.data()['label'] ?? d.id).toString())
          .toSet();
      currentAcademicYearLabel = _pickCurrentAcademicYearLabel(docs);
    } catch (_) {
      // Fallback: allow opening dialog even if prefetch fails.
    }

    if (!mounted) return;
    final res = await showDialog<_CreateSYResult>(
      context: context,
      builder: (_) => _CreateSYDialog(
        existingLabels: existingLabels,
        currentAcademicYearLabel: currentAcademicYearLabel,
      ),
    );
    if (res == null) return;

    try {
      await _svc.createSchoolYear(syId: res.syId, label: res.label);
      if (!mounted) return;
      setState(() => _selectedSyId = res.syId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created ${res.label}. Configure terms on right panel.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create failed: $e')));
    }
  }

  Future<void> _openMobileManageSheet(String syId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: _YearDetailsPanel(
            syId: syId,
            service: _svc,
            onClose: () => Navigator.of(context).pop(),
          ),
        );
      },
    );
  }
}

class _YearDetailsPanel extends StatefulWidget {
  final String syId;
  final AcademicSettingsService service;
  final VoidCallback onClose;

  const _YearDetailsPanel({
    required this.syId,
    required this.service,
    required this.onClose,
  });

  @override
  State<_YearDetailsPanel> createState() => _YearDetailsPanelState();
}

class _YearDetailsPanelState extends State<_YearDetailsPanel> {
  String? _loadedSyId;
  String _activeTermId = 'term1';
  bool _editing = false;

  DateTime? _t1Start;
  DateTime? _t1End;
  DateTime? _t2Start;
  DateTime? _t2End;
  DateTime? _t3Start;
  DateTime? _t3End;

  String _fsActiveTermId = 'term1';
  DateTime? _fsT1Start;
  DateTime? _fsT1End;
  DateTime? _fsT2Start;
  DateTime? _fsT2End;
  DateTime? _fsT3Start;
  DateTime? _fsT3End;

  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('academic_years')
            .doc(widget.syId)
            .snapshots(),
        builder: (context, yearSnap) {
          if (yearSnap.hasError) return _ErrorBox(yearSnap.error.toString());
          if (!yearSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final year = yearSnap.data!.data();
          if (year == null) return const _ErrorBox('School year not found');

          final label = (year['label'] ?? widget.syId).toString();
          final rawStatus = (year['status'] ?? 'inactive').toString();
          final status = rawStatus.toLowerCase().trim() == 'archived'
              ? 'inactive'
              : rawStatus.toLowerCase().trim();
          final firestoreActiveTerm = (year['activeTermId'] ?? 'term1')
              .toString();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.service.streamTerms(widget.syId),
            builder: (context, termsSnap) {
              if (termsSnap.hasError) {
                return _ErrorBox(termsSnap.error.toString());
              }
              if (!termsSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final terms = termsSnap.data!.docs;
              _syncFromFirestore(terms, firestoreActiveTerm);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.school_rounded, color: headerGreen),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: dark,
                                ),
                              ),
                              Text(
                                status == 'active' ? 'ACTIVE' : 'INACTIVE',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _CardBlock(
                            title: 'Term Dates',
                            child: Column(
                              children: [
                                _TermDateRow(
                                  title: '1st Semester',
                                  start: _t1Start,
                                  end: _t1End,
                                  enabled: _editing,
                                  isActive: _activeTermId == 'term1',
                                  activeToggleEnabled: _editing && !_saving,
                                  onToggleActive: () =>
                                      _tryActivateTerm('term1'),
                                  onPickStart: () => _pickDate(
                                    initialDate: _t1Start,
                                    lastDate: _t1End,
                                    onPicked: (d) =>
                                        setState(() => _t1Start = d),
                                  ),
                                  onPickEnd: () => _pickDate(
                                    initialDate: _t1End,
                                    firstDate: _t1Start,
                                    onPicked: (d) => setState(() => _t1End = d),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _TermDateRow(
                                  title: '2nd Semester',
                                  start: _t2Start,
                                  end: _t2End,
                                  enabled: _editing,
                                  isActive: _activeTermId == 'term2',
                                  activeToggleEnabled: _editing && !_saving,
                                  onToggleActive: () =>
                                      _tryActivateTerm('term2'),
                                  onPickStart: () => _pickDate(
                                    initialDate: _t2Start,
                                    lastDate: _t2End,
                                    onPicked: (d) =>
                                        setState(() => _t2Start = d),
                                  ),
                                  onPickEnd: () => _pickDate(
                                    initialDate: _t2End,
                                    firstDate: _t2Start,
                                    onPicked: (d) => setState(() => _t2End = d),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _TermDateRow(
                                  title: '3rd Semester',
                                  start: _t3Start,
                                  end: _t3End,
                                  enabled: _editing,
                                  isActive: _activeTermId == 'term3',
                                  activeToggleEnabled: _editing && !_saving,
                                  onToggleActive: () =>
                                      _tryActivateTerm('term3'),
                                  onPickStart: () => _pickDate(
                                    initialDate: _t3Start,
                                    lastDate: _t3End,
                                    onPicked: (d) =>
                                        setState(() => _t3Start = d),
                                  ),
                                  onPickEnd: () => _pickDate(
                                    initialDate: _t3End,
                                    firstDate: _t3Start,
                                    onPicked: (d) => setState(() => _t3End = d),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Only one semester can be active at a time.',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!_editing) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _editing = true),
                              child: const Text(
                                'Edit',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          if (status != 'active') ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: _saving
                                    ? null
                                    : () => _confirmAndSetSchoolYearActive(
                                        label: label,
                                      ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: headerGreen,
                                ),
                                child: const Text(
                                  'Set Active',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ],
                        ] else ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : _discardChanges,
                              child: const Text(
                                'Discard Changes',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving
                                  ? null
                                  : () => _save(widget.syId),
                              style: FilledButton.styleFrom(
                                backgroundColor: headerGreen,
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Save Changes',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ],
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

  void _syncFromFirestore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> terms,
    String firestoreActiveTerm,
  ) {
    final syChanged = _loadedSyId != widget.syId;
    _fsActiveTermId = firestoreActiveTerm;
    _fsT1Start = null;
    _fsT1End = null;
    _fsT2Start = null;
    _fsT2End = null;
    _fsT3Start = null;
    _fsT3End = null;

    for (final t in terms) {
      final d = t.data();
      final slot = _resolveTermSlot(t.id, d);
      final s = _readDate(d, const ['startAt', 'startDate', 'start']);
      final e = _readDate(d, const ['endAt', 'endDate', 'end']);
      if (slot == 'term1') {
        _fsT1Start = s;
        _fsT1End = e;
      } else if (slot == 'term2') {
        _fsT2Start = s;
        _fsT2End = e;
      } else if (slot == 'term3') {
        _fsT3Start = s;
        _fsT3End = e;
      }
    }

    if (syChanged) {
      _loadedSyId = widget.syId;
      _editing = false;
    }

    if (!_editing && !_saving) _loadDraftFromFirestore();
  }

  String _resolveTermSlot(String termDocId, Map<String, dynamic> d) {
    final id = termDocId.toLowerCase().trim();
    if (id == 'term1' || id == '1' || id.contains('1st')) return 'term1';
    if (id == 'term2' || id == '2' || id.contains('2nd')) return 'term2';
    if (id == 'term3' || id == '3' || id.contains('3rd')) return 'term3';

    final order = d['order'];
    if (order == 1 || order == '1') return 'term1';
    if (order == 2 || order == '2') return 'term2';
    if (order == 3 || order == '3') return 'term3';

    final name = (d['name'] ?? '').toString().toLowerCase();
    if (name.contains('1st') || name.contains('first')) return 'term1';
    if (name.contains('2nd') || name.contains('second')) return 'term2';
    if (name.contains('3rd') ||
        name.contains('third') ||
        name.contains('short')) {
      return 'term3';
    }
    return '';
  }

  DateTime? _readDate(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final value = d[k];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  void _loadDraftFromFirestore() {
    _activeTermId = _fsActiveTermId;
    _t1Start = _fsT1Start;
    _t1End = _fsT1End;
    _t2Start = _fsT2Start;
    _t2End = _fsT2End;
    _t3Start = _fsT3Start;
    _t3End = _fsT3End;
  }

  void _discardChanges() {
    setState(() {
      _editing = false;
      _loadDraftFromFirestore();
    });
  }

  Future<void> _tryActivateTerm(String termId) async {
    if (_saving || termId == _activeTermId) return;
    if (!_editing) {
      _toast('Click Edit first to change active semester.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Activate Semester?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Are you sure you want to activate ${_termLabelForDisplay(termId)}?\n\n'
          'All new violation records after saving will be tagged to this semester.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Activate'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _activeTermId = termId);
  }

  String _termLabelForDisplay(String termId) {
    switch (termId) {
      case 'term1':
        return '1st Semester';
      case 'term2':
        return '2nd Semester';
      case 'term3':
        return '3rd Semester';
      default:
        return 'Selected Semester';
    }
  }

  Future<void> _confirmAndSetSchoolYearActive({
    required String label,
  }) async {
    final err = _validateDates();
    if (err != null) {
      _toast('Set dates first. $err');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Activate School Year?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Are you sure you want to activate $label?\n\n'
          'All other school years will be set to inactive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Activate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.service.saveTermsAndActiveTerm(
        syId: widget.syId,
        activeTermId: _activeTermId,
        termDates: _termMap(),
      );
      await widget.service.setActiveSchoolYear(widget.syId);
      _toast('$label is now ACTIVE.');
    } catch (e) {
      _toast('Set active failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate({
    required ValueChanged<DateTime> onPicked,
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final now = DateTime.now();
    final init = initialDate ?? now;
    final first = firstDate ?? DateTime(now.year - 2);
    final last = lastDate ?? DateTime(now.year + 5);
    final safeInitial = init.isBefore(first)
        ? first
        : init.isAfter(last)
        ? last
        : init;
    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) onPicked(picked);
  }

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

  Map<String, TermDates> _termMap() {
    return {
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
    };
  }

  Future<void> _save(String syId) async {
    final err = _validateDates();
    if (err != null) {
      _toast(err);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.service.saveTermsAndActiveTerm(
        syId: syId,
        activeTermId: _activeTermId,
        termDates: _termMap(),
      );
      if (mounted) {
        setState(() => _editing = false);
      }
      _toast('Saved term dates and active term.');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _TermDateRow extends StatelessWidget {
  final String title;
  final DateTime? start;
  final DateTime? end;
  final bool enabled;
  final bool isActive;
  final bool activeToggleEnabled;
  final VoidCallback onToggleActive;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _TermDateRow({
    required this.title,
    required this.start,
    required this.end,
    required this.enabled,
    required this.isActive,
    required this.activeToggleEnabled,
    required this.onToggleActive,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: dark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                color: isActive ? headerGreen : muted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: isActive,
              onChanged: activeToggleEnabled
                  ? (value) {
                      if (!value && isActive) return;
                      if (value) onToggleActive();
                    }
                  : null,
              activeTrackColor: headerGreen.withValues(alpha: 0.55),
              activeThumbColor: headerGreen,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: enabled ? onPickStart : null,
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(start == null ? 'Start Date' : _fmtDate(start!)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: enabled ? onPickEnd : null,
                icon: const Icon(Icons.event_available_outlined, size: 16),
                label: Text(end == null ? 'End Date' : _fmtDate(end!)),
              ),
            ),
          ],
        ),
        if (!enabled) ...[
          const SizedBox(height: 6),
          const Text(
            'Click Edit to change dates',
            style: TextStyle(
              fontSize: 11,
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  static String _fmtDate(DateTime d) {
    const months = [
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _CardBlock extends StatelessWidget {
  final String title;
  final Widget child;
  const _CardBlock({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: dark, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String msg;
  const _ErrorBox(this.msg);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Error: $msg',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
      ),
    );
  }
}

String? _pickCurrentAcademicYearLabel(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  if (docs.isEmpty) return null;

  for (final doc in docs) {
    final data = doc.data();
    final status = (data['status'] ?? '').toString().toLowerCase();
    if (status == 'active') {
      return (data['label'] ?? doc.id).toString();
    }
  }

  String? latestLabel;
  int? latestStart;
  final reg = RegExp(r'^(\d{4})-(\d{4})$');
  for (final doc in docs) {
    final label = (doc.data()['label'] ?? doc.id).toString().trim();
    final m = reg.firstMatch(label);
    if (m == null) continue;
    final start = int.tryParse(m.group(1)!);
    if (start == null) continue;
    if (latestStart == null || start > latestStart) {
      latestStart = start;
      latestLabel = label;
    }
  }
  return latestLabel;
}

class _CreateSYResult {
  final String syId;
  final String label;
  const _CreateSYResult({required this.syId, required this.label});
}

class _CreateSYDialog extends StatefulWidget {
  final Set<String> existingLabels;
  final String? currentAcademicYearLabel;

  const _CreateSYDialog({
    required this.existingLabels,
    required this.currentAcademicYearLabel,
  });

  @override
  State<_CreateSYDialog> createState() => _CreateSYDialogState();
}

class _CreateSYDialogState extends State<_CreateSYDialog> {
  late final List<int> _availableStartYears;
  int? _selectedStartYear;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().year;
    final current = _parseSy(widget.currentAcademicYearLabel);
    const yearsAhead = 10;
    final minBase = now;
    final maxBase = now + yearsAhead;

    _availableStartYears = [
      for (int y = minBase; y <= maxBase; y++)
        if (!widget.existingLabels.contains('$y-${y + 1}')) y,
    ]..sort((a, b) => b.compareTo(a));

    final expectedStart = current?.end;
    if (expectedStart != null && _availableStartYears.contains(expectedStart)) {
      _selectedStartYear = expectedStart;
    } else if (_availableStartYears.isNotEmpty) {
      _selectedStartYear = _availableStartYears.first;
    }
  }

  ({int start, int end})? _parseSy(String? label) {
    if (label == null) return null;
    final normalized = label.trim().replaceAll('–', '-').replaceAll('—', '-');
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(normalized);
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    if (start == null || end == null || end != start + 1) return null;
    return (start: start, end: end);
  }

  Future<bool> _confirmNonConsecutiveYear({
    required String currentLabel,
    required String expectedLabel,
    required String selectedLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Create Non-Consecutive Year?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'This year is not the following year of the current academic year.\n\n'
          'Current: $currentLabel\n'
          'Expected next: $expectedLabel\n'
          'Selected: $selectedLabel\n\n'
          'Are you sure you want to create it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create Anyway'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().year;
    final hasOptions = _availableStartYears.isNotEmpty;
    final selectedStart = _selectedStartYear;
    final selectedEnd = selectedStart == null ? null : selectedStart + 1;
    final selectedLabel = (selectedStart == null || selectedEnd == null)
        ? ''
        : '$selectedStart-$selectedEnd';

    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      title: const Text(
        'Create School Year',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: dark,
          fontSize: 19,
        ),
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set the school year range for a new academic cycle.',
              style: TextStyle(
                color: muted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'AVAILABLE YEARS (BASED ON CURRENT YEAR: $now)',
              style: const TextStyle(
                color: muted,
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6FAF6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select academic year range',
                    style: TextStyle(
                      color: dark,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedStart,
                          decoration: const InputDecoration(
                            labelText: 'Start Year',
                            border: OutlineInputBorder(),
                          ),
                          items: _availableStartYears
                              .map(
                                (year) => DropdownMenuItem<int>(
                                  value: year,
                                  child: Text('$year'),
                                ),
                              )
                              .toList(),
                          onChanged: hasOptions
                              ? (v) => setState(() {
                                  _selectedStartYear = v;
                                  _error = null;
                                })
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedEnd,
                          decoration: const InputDecoration(
                            labelText: 'End Year',
                            border: OutlineInputBorder(),
                          ),
                          items: selectedEnd == null
                              ? const []
                              : [
                                  DropdownMenuItem<int>(
                                    value: selectedEnd,
                                    child: Text('$selectedEnd'),
                                  ),
                                ],
                          onChanged: null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              hasOptions
                  ? 'School Year ID: $selectedLabel'
                  : 'No available school year from $now to ${now + 10}.',
              style: TextStyle(
                color: hasOptions ? headerGreen : Colors.red.shade700,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !hasOptions
              ? null
              : () async {
                  if (selectedStart == null || selectedEnd == null) {
                    setState(() => _error = 'Please select a school year.');
                    return;
                  }

                  final syLabel = '$selectedStart-$selectedEnd';
                  if (widget.existingLabels.contains(syLabel)) {
                    setState(() => _error = 'School year already exists.');
                    return;
                  }

                  final current = _parseSy(widget.currentAcademicYearLabel);
                  if (current != null && selectedStart != current.end) {
                    final shouldProceed = await _confirmNonConsecutiveYear(
                      currentLabel: '${current.start}-${current.end}',
                      expectedLabel: '${current.end}-${current.end + 1}',
                      selectedLabel: syLabel,
                    );
                    if (!shouldProceed) return;
                  }

                  if (!context.mounted) return;
                  Navigator.of(
                    context,
                  ).pop(_CreateSYResult(syId: syLabel, label: syLabel));
                },
          child: const Text(
            'Create',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

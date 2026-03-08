import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/academic_settings_service.dart';

const bg = Color(0xFFF5F6FB);
const headerGreen = Color(0xFF2F6C44);
const cardOuter = Color(0xFFFFFFFF);
const cardInner = Color(0xFFF7F7F4);
const dark = Color(0xFF243024);
const muted = Color(0xFF5B665B);

class AcademicYearManagePage extends StatefulWidget {
  final String syId;
  const AcademicYearManagePage({super.key, required this.syId});

  @override
  State<AcademicYearManagePage> createState() => _AcademicYearManagePageState();
}

class _AcademicYearManagePageState extends State<AcademicYearManagePage> {
  final _svc = AcademicSettingsService();

  String _activeTermId = '';
  bool _activeTermTouched = false;

  DateTime? _t1Start, _t1End;
  DateTime? _t2Start, _t2End;
  DateTime? _t3Start, _t3End;

  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('academic_years')
                .doc(widget.syId)
                .snapshots(),
            builder: (context, yearSnap) {
              if (yearSnap.hasError) return _Error(yearSnap.error.toString());
              if (!yearSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final year = yearSnap.data!.data();
              if (year == null) return const _Error('SY not found.');

              final label = (year['label'] ?? widget.syId).toString();
              final rawStatus = (year['status'] ?? 'inactive').toString();
              final status = rawStatus.toLowerCase().trim() == 'archived'
                  ? 'inactive'
                  : rawStatus.toLowerCase().trim();
              final activeTermId = (year['activeTermId'] ?? 'term1').toString();

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _svc.streamTerms(widget.syId),
                builder: (context, termsSnap) {
                  if (termsSnap.hasError) {
                    return _Error(termsSnap.error.toString());
                  }
                  if (!termsSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final terms = termsSnap.data!.docs;
                  _hydrateFromFirestore(terms, activeTermId);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopBar(
                        label: label,
                        status: status,
                        onBack: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _Card(
                                title: 'Semester Dates',
                                child: Column(
                                  children: [
                                    _TermRow(
                                      title: '1st Semester',
                                      start: _t1Start,
                                      end: _t1End,
                                      onPickStart: () => _pickDate(
                                        onPicked: (d) =>
                                            setState(() => _t1Start = d),
                                        initialDate: _t1Start,
                                        lastDate: _t1End,
                                      ),
                                      onPickEnd: () => _pickDate(
                                        onPicked: (d) =>
                                            setState(() => _t1End = d),
                                        initialDate: _t1End,
                                        firstDate: _t1Start,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    _TermRow(
                                      title: '2nd Semester',
                                      start: _t2Start,
                                      end: _t2End,
                                      onPickStart: () => _pickDate(
                                        onPicked: (d) =>
                                            setState(() => _t2Start = d),
                                        initialDate: _t2Start,
                                        lastDate: _t2End,
                                      ),
                                      onPickEnd: () => _pickDate(
                                        onPicked: (d) =>
                                            setState(() => _t2End = d),
                                        initialDate: _t2End,
                                        firstDate: _t2Start,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    _TermRow(
                                      title: '3rd Semester',
                                      start: _t3Start,
                                      end: _t3End,
                                      onPickStart: () => _pickDate(
                                        onPicked: (d) =>
                                            setState(() => _t3Start = d),
                                        initialDate: _t3Start,
                                        lastDate: _t3End,
                                      ),
                                      onPickEnd: () => _pickDate(
                                        onPicked: (d) =>
                                            setState(() => _t3End = d),
                                        initialDate: _t3End,
                                        firstDate: _t3Start,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              _Card(
                                title: 'Active Term',
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _activeTermId.isEmpty
                                            ? activeTermId
                                            : _activeTermId,
                                        decoration: const InputDecoration(
                                          labelText: 'Active Term',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'term1',
                                            child: Text('1st Sem'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'term2',
                                            child: Text('2nd Sem'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'term3',
                                            child: Text('3rd Sem'),
                                          ),
                                        ],
                                        onChanged: (v) => setState(() {
                                          _activeTermTouched = true;
                                          _activeTermId = v ?? 'term1';
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 90),
                            ],
                          ),
                        ),
                      ),
                      _BottomBar(
                        saving: _saving,
                        isActiveYear: status == 'active',
                        onSave: () => _saveDatesOnly(widget.syId),
                        onSetActiveSY: () => _setActiveSY(widget.syId),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _hydrateFromFirestore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> terms,
    String firestoreActiveTermId,
  ) {
    // Only hydrate dates if local is still null (so user edits won't be overwritten)
    DateTime? toDate(dynamic ts) {
      if (ts == null) return null;
      if (ts is Timestamp) return ts.toDate();
      return null;
    }

    for (final t in terms) {
      final d = t.data();
      final id = t.id;
      final s = toDate(d['startAt']);
      final e = toDate(d['endAt']);

      if (id == 'term1') {
        _t1Start ??= s;
        _t1End ??= e;
      } else if (id == 'term2') {
        _t2Start ??= s;
        _t2End ??= e;
      } else if (id == 'term3') {
        _t3Start ??= s;
        _t3End ??= e;
      }
    }

    // Sync active term from Firestore unless user already changed it locally.
    if (!_activeTermTouched) _activeTermId = firestoreActiveTermId;
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
    // Ensure each term has both dates
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

    // No overlaps and ordered
    // 1st end < 2nd start, 2nd end < 3rd start
    if (!(_t1End!.isBefore(_t2Start!) || _sameDay(_t1End!, _t2Start!))) {
      return '1st Sem must end before 2nd Sem starts.';
    }
    if (!(_t2End!.isBefore(_t3Start!) || _sameDay(_t2End!, _t3Start!))) {
      return '2nd Sem must end before 3rd Sem starts.';
    }

    // Optional: disallow exact same day boundary? (if you want)
    // For now, we allow end == next start.

    return null;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Map<String, TermDates> _buildTermDatesMap() {
    return <String, TermDates>{
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

  Future<void> _persistTermsAndActiveTerm({
    required String syId,
    bool showSuccessToast = true,
  }) async {
    final err = _validateDates();
    if (err != null) {
      _toast(err);
      return;
    }

    setState(() => _saving = true);
    try {
      final map = _buildTermDatesMap();
      final termId = _activeTermId.isEmpty ? 'term1' : _activeTermId;

      await _svc.saveTermsAndActiveTerm(
        syId: syId,
        activeTermId: termId,
        termDates: map,
      );

      if (showSuccessToast) _toast('Saved term dates and active term.');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveDatesOnly(String syId) async {
    await _persistTermsAndActiveTerm(syId: syId);
  }

  Future<void> _setActiveSY(String syId) async {
    // Don’t allow making active if dates aren’t set.
    final err = _validateDates();
    if (err != null) {
      _toast('Set dates first. $err');
      return;
    }

    setState(() => _saving = true);
    try {
      // Save first to ensure activeTermId/dates are persisted.
      final map = _buildTermDatesMap();
      final termId = _activeTermId.isEmpty ? 'term1' : _activeTermId;
      await _svc.saveTermsAndActiveTerm(
        syId: syId,
        activeTermId: termId,
        termDates: map,
      );
      await _svc.setActiveSchoolYear(syId);
      _toast('This School Year is now ACTIVE.');
    } catch (e) {
      _toast('Set active failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _TopBar extends StatelessWidget {
  final String label;
  final String status;
  final VoidCallback onBack;

  const _TopBar({
    required this.label,
    required this.status,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardOuter,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Back',
          ),
          const Icon(Icons.calendar_month_rounded, color: headerGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage SY $label',
                  style: const TextStyle(
                    color: dark,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isActive ? 'Status: ACTIVE' : 'Status: Archived',
                  style: const TextStyle(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? headerGreen.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isActive
                    ? headerGreen.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.10),
              ),
            ),
            child: Text(
              isActive ? 'ACTIVE' : 'INACTIVE',
              style: TextStyle(
                color: isActive ? headerGreen : muted,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardOuter,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: dark,
              fontWeight: FontWeight.w900,
              fontSize: 13.6,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TermRow extends StatelessWidget {
  final String title;
  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _TermRow({
    required this.title,
    required this.start,
    required this.end,
    required this.onPickStart,
    required this.onPickEnd,
  });

  String _fmt(DateTime? d) {
    if (d == null) return 'Select date';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    // You can replace with intl later if you want.
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardInner,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: dark, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickStart,
                  icon: const Icon(
                    Icons.play_arrow_rounded,
                    color: headerGreen,
                  ),
                  label: Text(
                    'Start: ${_fmt(start)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: dark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.black.withValues(alpha: 0.10),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickEnd,
                  icon: const Icon(Icons.stop_rounded, color: headerGreen),
                  label: Text(
                    'End: ${_fmt(end)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: dark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.black.withValues(alpha: 0.10),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool saving;
  final bool isActiveYear;
  final VoidCallback onSave;
  final VoidCallback onSetActiveSY;

  const _BottomBar({
    required this.saving,
    required this.isActiveYear,
    required this.onSave,
    required this.onSetActiveSY,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardOuter,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: saving ? null : onSave,
              style: OutlinedButton.styleFrom(
                foregroundColor: headerGreen,
                side: BorderSide(color: headerGreen.withValues(alpha: 0.35)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                saving ? 'Saving...' : 'Save Changes',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: (saving || isActiveYear) ? null : onSetActiveSY,
              style: ElevatedButton.styleFrom(
                backgroundColor: headerGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                isActiveYear ? 'ACTIVE' : 'Set as ACTIVE SY',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  final String msg;
  const _Error(this.msg);

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

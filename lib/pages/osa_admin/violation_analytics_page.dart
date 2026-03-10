import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../shared/widgets/modern_table_layout.dart';
import 'violation_records_page.dart';

enum _AnalyticsTab { overview, violations, students, departments }

class ViolationAnalyticsPage extends StatefulWidget {
  final ValueChanged<ViolationRecordsFilterPreset>? onOpenRecords;
  const ViolationAnalyticsPage({super.key, this.onOpenRecords});

  @override
  State<ViolationAnalyticsPage> createState() => _ViolationAnalyticsPageState();
}

class _ViolationAnalyticsPageState extends State<ViolationAnalyticsPage> {
  static const _bg = Color(0xFFF6FAF6);
  static const _primary = Color(0xFF1B5E20);
  static const _textDark = Color(0xFF1F2A1F);
  static const _hint = Color(0xFF6D7F62);

  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  String _search = '';
  String _schoolYear = 'All';
  String _term = 'All';
  String _department = 'All';
  String _concern = 'All';
  String _category = 'All';
  String _violationType = 'All';
  String _reporter = 'All';
  String _outcome = 'All';
  DateTimeRange? _dateRange;
  _AnalyticsTab _tab = _AnalyticsTab.overview;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('violation_cases')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snap.data!.docs
              .map((d) => _Case.fromDoc(d))
              .toList(growable: false);
          final filtered = all.where(_matches).toList(growable: false);
          final compact = MediaQuery.sizeOf(context).width < 920;
          final m = _Metrics.from(filtered);

          final syOpt = _opts(all.map((e) => e.schoolYear));
          final termOpt = _opts(all.map((e) => e.term));
          final deptOpt = _opts(all.map((e) => e.department));
          final catOpt = _opts(all.map((e) => e.category));
          final vioOpt = _opts(all.map((e) => e.violation));
          final repOpt = _opts(all.map((e) => e.reporter));
          final outOpt = _opts(all.map((e) => e.outcome));

          return ModernTableLayout(
            header: ModernTableHeader(
              title: 'Violation Analytics',
              subtitle: 'Student conduct insights and trends',
              searchBar: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search student name, student number, or violation',
                  prefixIcon: const Icon(Icons.search, color: _primary),
                  filled: true,
                  fillColor: _bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              tabs: compact
                  ? null
                  : _toolbar(
                      syOpt,
                      termOpt,
                      deptOpt,
                      catOpt,
                      vioOpt,
                      repOpt,
                      outOpt,
                    ),
              filters: compact
                  ? [
                      _filterButton(
                        () => _openCompactFilters(
                          syOpt,
                          termOpt,
                          deptOpt,
                          catOpt,
                          vioOpt,
                          repOpt,
                          outOpt,
                        ),
                      ),
                    ]
                  : null,
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    filtered.length == all.length
                        ? 'Showing all ${all.length} records'
                        : 'Showing ${filtered.length} of ${all.length} records · Filters applied',
                    style: const TextStyle(
                      color: _textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _tabBar(),
                const SizedBox(height: 10),
                Expanded(
                  child: filtered.isEmpty
                      ? _empty()
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: _tabContent(m),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _toolbar(
    List<String> sy,
    List<String> term,
    List<String> dept,
    List<String> cat,
    List<String> vio,
    List<String> rep,
    List<String> out,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _dd(
            'School Year',
            _schoolYear,
            sy,
            (v) => setState(() => _schoolYear = v),
          ),
          _dd('Term', _term, term, (v) => setState(() => _term = v)),
          _dd(
            'Department',
            _department,
            dept,
            (v) => setState(() => _department = v),
          ),
          _dd('Concern', _concern, const [
            'All',
            'Basic',
            'Serious',
          ], (v) => setState(() => _concern = v)),
          _filterButton(() => _openAdvanced(cat, vio, rep, out)),
        ],
      ),
    );
  }

  Widget _dd(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    final selected = options.contains(value) ? value : options.first;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          items: options
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    '$label: $e',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _filterButton(VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        onTap: onTap,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 16),
            SizedBox(width: 8),
            Text(
              'More Filters',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAdvanced(
    List<String> cat,
    List<String> vio,
    List<String> rep,
    List<String> out,
  ) async {
    var dCat = _category,
        dVio = _violationType,
        dRep = _reporter,
        dOut = _outcome;
    var dRange = _dateRange;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Advanced Filters',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _panelDd(
                      'Category',
                      dCat,
                      cat,
                      (v) => setModal(() => dCat = v),
                    ),
                    _panelDd(
                      'Violation Type',
                      dVio,
                      vio,
                      (v) => setModal(() => dVio = v),
                    ),
                    _panelDd(
                      'Reporter',
                      dRep,
                      rep,
                      (v) => setModal(() => dRep = v),
                    ),
                    _panelDd(
                      'Outcome',
                      dOut,
                      out,
                      (v) => setModal(() => dOut = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2018, 1, 1),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            initialDateRange: dRange,
                            helpText: 'Select Date Range',
                            saveText: 'Apply',
                          );
                          if (picked != null) setModal(() => dRange = picked);
                        },
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text(
                          dRange == null
                              ? 'Date Range: Any'
                              : '${DateFormat('MMM d, yyyy').format(dRange!.start)} - ${DateFormat('MMM d, yyyy').format(dRange!.end)}',
                        ),
                      ),
                    ),
                    if (dRange != null)
                      TextButton(
                        onPressed: () => setModal(() => dRange = null),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _category = dCat;
                            _violationType = dVio;
                            _reporter = dRep;
                            _outcome = dOut;
                            _dateRange = dRange;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Apply Filters'),
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
  }

  Future<void> _openCompactFilters(
    List<String> sy,
    List<String> term,
    List<String> dept,
    List<String> cat,
    List<String> vio,
    List<String> rep,
    List<String> out,
  ) async {
    var dSchoolYear = _schoolYear;
    var dTerm = _term;
    var dDepartment = _department;
    var dConcern = _concern;
    var dCategory = _category;
    var dViolation = _violationType;
    var dReporter = _reporter;
    var dOutcome = _outcome;
    var dRange = _dateRange;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModal) {
            return DraggableScrollableSheet(
              initialChildSize: 0.9,
              minChildSize: 0.55,
              maxChildSize: 0.95,
              builder: (context, controller) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    children: [
                      const Text(
                        'Filters',
                        style: TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _panelDd('School Year', dSchoolYear, sy, (v) {
                        setModal(() => dSchoolYear = v);
                      }),
                      _panelDd('Term', dTerm, term, (v) {
                        setModal(() => dTerm = v);
                      }),
                      _panelDd('Department / Program', dDepartment, dept, (v) {
                        setModal(() => dDepartment = v);
                      }),
                      _panelDd(
                        'Concern',
                        dConcern,
                        const ['All', 'Basic', 'Serious'],
                        (v) {
                          setModal(() => dConcern = v);
                        },
                      ),
                      _panelDd('Category', dCategory, cat, (v) {
                        setModal(() => dCategory = v);
                      }),
                      _panelDd('Violation Type', dViolation, vio, (v) {
                        setModal(() => dViolation = v);
                      }),
                      _panelDd('Reporter', dReporter, rep, (v) {
                        setModal(() => dReporter = v);
                      }),
                      _panelDd('Outcome', dOutcome, out, (v) {
                        setModal(() => dOutcome = v);
                      }),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2018, 1, 1),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                  initialDateRange: dRange,
                                  helpText: 'Select Date Range',
                                  saveText: 'Apply',
                                );
                                if (picked != null) {
                                  setModal(() => dRange = picked);
                                }
                              },
                              icon: const Icon(Icons.calendar_month_rounded),
                              label: Text(
                                dRange == null
                                    ? 'Date Range: Any'
                                    : '${DateFormat('MMM d, yyyy').format(dRange!.start)} - ${DateFormat('MMM d, yyyy').format(dRange!.end)}',
                              ),
                            ),
                          ),
                          if (dRange != null)
                            TextButton(
                              onPressed: () => setModal(() => dRange = null),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _schoolYear = dSchoolYear;
                                  _term = dTerm;
                                  _department = dDepartment;
                                  _concern = dConcern;
                                  _category = dCategory;
                                  _violationType = dViolation;
                                  _reporter = dReporter;
                                  _outcome = dOutcome;
                                  _dateRange = dRange;
                                });
                                Navigator.pop(sheetContext);
                              },
                              child: const Text('Apply Filters'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _panelDd(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value : options.first,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: options
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(e, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _tabBar() {
    Widget button(_AnalyticsTab t, String label) {
      final active = _tab == t;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = t),
          child: Container(
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? _primary.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? _primary.withValues(alpha: 0.30)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? _primary : _hint,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            button(_AnalyticsTab.overview, 'Overview'),
            button(_AnalyticsTab.violations, 'Violations'),
            button(_AnalyticsTab.students, 'Students'),
            button(_AnalyticsTab.departments, 'Departments'),
          ],
        ),
      ),
    );
  }

  Widget _tabContent(_Metrics m) {
    switch (_tab) {
      case _AnalyticsTab.overview:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _stat(
                  'Total Violations',
                  '${m.total}',
                  () => _drill(const ViolationRecordsFilterPreset()),
                ),
                _stat(
                  'Basic Violations',
                  '${m.basic}',
                  () => _drill(
                    const ViolationRecordsFilterPreset(concern: 'Basic'),
                  ),
                ),
                _stat(
                  'Serious Violations',
                  '${m.serious}',
                  () => _drill(
                    const ViolationRecordsFilterPreset(concern: 'Serious'),
                  ),
                ),
                _stat('Repeat Offenders', '${m.repeatOffenders}', null),
              ],
            ),
            const SizedBox(height: 12),
            _card(
              'Violations Over Time',
              _bars(
                m.monthCounts,
                (k) => _drill(
                  ViolationRecordsFilterPreset(dateRange: _monthRange(k)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Violations by Category',
              _bars(
                m.categoryCounts,
                (k) => _drill(ViolationRecordsFilterPreset(category: k)),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Violations by Department',
              _bars(
                m.departmentCounts,
                (k) =>
                    _drill(ViolationRecordsFilterPreset(departmentProgram: k)),
              ),
            ),
          ],
        );
      case _AnalyticsTab.violations:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _card(
              'Most Common Violations',
              _table(
                const ['Violation', 'Total'],
                m.violationCounts.entries
                    .take(12)
                    .map((e) => [e.key, '${e.value}'])
                    .toList(),
                onRowTap: (row) =>
                    _drill(ViolationRecordsFilterPreset(violationType: row[0])),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Violation Category Breakdown',
              _bars(
                m.categoryCounts,
                (k) => _drill(ViolationRecordsFilterPreset(category: k)),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Basic vs Serious Distribution',
              Row(
                children: [
                  Expanded(
                    child: _miniDist(
                      'Basic',
                      m.basic,
                      m.total,
                      () => _drill(
                        const ViolationRecordsFilterPreset(concern: 'Basic'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _miniDist(
                      'Serious',
                      m.serious,
                      m.total,
                      () => _drill(
                        const ViolationRecordsFilterPreset(concern: 'Serious'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Monthly Violation Trend',
              _bars(
                m.monthCounts,
                (k) => _drill(
                  ViolationRecordsFilterPreset(dateRange: _monthRange(k)),
                ),
              ),
            ),
          ],
        );
      case _AnalyticsTab.students:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _card(
              'Top Repeat Offenders',
              _table(
                const ['Student Name', 'Student Number', 'Total Violations'],
                m.students
                    .where((e) => e.count >= 2)
                    .take(12)
                    .map((e) => [e.name, e.no, '${e.count}'])
                    .toList(),
                onRowTap: (r) => _drill(
                  ViolationRecordsFilterPreset(
                    searchQuery: r[1] == '--' ? r[0] : r[1],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Students with Most Violations',
              _table(
                const ['Student Name', 'Student Number', 'Total Violations'],
                m.students
                    .take(12)
                    .map((e) => [e.name, e.no, '${e.count}'])
                    .toList(),
                onRowTap: (r) => _drill(
                  ViolationRecordsFilterPreset(
                    searchQuery: r[1] == '--' ? r[0] : r[1],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Student Violation Distribution by Department',
              _bars(
                m.departmentCounts,
                (k) =>
                    _drill(ViolationRecordsFilterPreset(departmentProgram: k)),
              ),
            ),
          ],
        );
      case _AnalyticsTab.departments:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _card(
              'Violations by Department',
              _bars(
                m.departmentCounts,
                (k) =>
                    _drill(ViolationRecordsFilterPreset(departmentProgram: k)),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Department Breakdown',
              _table(
                const ['Department', 'Total', 'Basic', 'Serious'],
                m.departmentRows
                    .map(
                      (e) => [
                        e.department,
                        '${e.total}',
                        '${e.basic}',
                        '${e.serious}',
                      ],
                    )
                    .toList(),
                onRowTap: (r) => _drill(
                  ViolationRecordsFilterPreset(departmentProgram: r[0]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Department Violation Trends',
              _table(
                const ['Department', 'Top 3 Months'],
                m.departmentTrends.map((e) => [e.$1, e.$2]).toList(),
                onRowTap: (r) => _drill(
                  ViolationRecordsFilterPreset(departmentProgram: r[0]),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _empty() => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No data available for the selected filters.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try adjusting or clearing the filters.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => setState(_clearFilters),
            child: const Text('Clear Filters'),
          ),
        ],
      ),
    ),
  );

  Widget _stat(String label, String value, VoidCallback? onTap) {
    final child = Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _primary,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return onTap == null
        ? child
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: child,
          );
  }

  Widget _card(String title, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
    ),
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
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Widget _bars(Map<String, int> data, ValueChanged<String> onTap) {
    if (data.isEmpty) {
      return const Text(
        'No analytics data yet.',
        style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
      );
    }
    final maxVal = data.values.fold<int>(1, (a, b) => a > b ? a : b);
    return Column(
      children: data.entries.take(12).map((e) {
        final ratio = maxVal == 0 ? 0.0 : e.value / maxVal;
        return InkWell(
          onTap: () => onTap(e.key),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${e.value}',
                      style: const TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: _primary.withValues(alpha: 0.10),
                    valueColor: const AlwaysStoppedAnimation<Color>(_primary),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _miniDist(String label, int count, int total, VoidCallback onTap) {
    final ratio = total == 0 ? 0.0 : count / total;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: _hint, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: const TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: ratio.clamp(0, 1),
                minHeight: 8,
                backgroundColor: _primary.withValues(alpha: 0.10),
                valueColor: const AlwaysStoppedAnimation<Color>(_primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(
    List<String> headers,
    List<List<String>> rows, {
    required ValueChanged<List<String>> onRowTap,
  }) {
    if (rows.isEmpty) {
      return const Text(
        'No data available.',
        style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        headingRowColor: WidgetStateProperty.all(_bg),
        columns: headers
            .map(
              (h) => DataColumn(
                label: Text(
                  h.toUpperCase(),
                  style: const TextStyle(
                    color: _hint,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                  ),
                ),
              ),
            )
            .toList(),
        rows: rows
            .map(
              (r) => DataRow(
                onSelectChanged: (_) => onRowTap(r),
                cells: r
                    .map(
                      (c) => DataCell(
                        Text(
                          c,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _search = v.trim().toLowerCase());
    });
  }

  bool _matches(_Case c) {
    if (_search.isNotEmpty &&
        !('${c.studentName} ${c.studentNo} ${c.violation} ${c.caseCode}'
            .toLowerCase()
            .contains(_search))) {
      return false;
    }
    if (_schoolYear != 'All' && c.schoolYear != _schoolYear) return false;
    if (_term != 'All' && c.term != _term) return false;
    if (_department != 'All' && c.department != _department) return false;
    if (_concern != 'All' &&
        c.concern.toLowerCase() != _concern.toLowerCase()) {
      return false;
    }
    if (_category != 'All' && c.category != _category) return false;
    if (_violationType != 'All' && c.violation != _violationType) return false;
    if (_reporter != 'All' && c.reporter != _reporter) return false;
    if (_outcome != 'All' && c.outcome != _outcome) return false;
    if (_dateRange != null) {
      if (c.date == null) return false;
      final s = DateTime(
        _dateRange!.start.year,
        _dateRange!.start.month,
        _dateRange!.start.day,
      );
      final e = DateTime(
        _dateRange!.end.year,
        _dateRange!.end.month,
        _dateRange!.end.day,
        23,
        59,
        59,
      );
      if (c.date!.isBefore(s) || c.date!.isAfter(e)) return false;
    }
    return true;
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _search = '';
    _schoolYear = 'All';
    _term = 'All';
    _department = 'All';
    _concern = 'All';
    _category = 'All';
    _violationType = 'All';
    _reporter = 'All';
    _outcome = 'All';
    _dateRange = null;
  }

  void _drill(ViolationRecordsFilterPreset preset) {
    final merged = ViolationRecordsFilterPreset(
      clearExisting: true,
      searchQuery:
          preset.searchQuery ??
          (_search.isEmpty ? null : _searchCtrl.text.trim()),
      concern: preset.concern ?? (_concern == 'All' ? null : _concern),
      dateRange: preset.dateRange ?? _dateRange,
      category: preset.category ?? (_category == 'All' ? null : _category),
      violationType:
          preset.violationType ??
          (_violationType == 'All' ? null : _violationType),
      reporter: _reporter == 'All' ? null : _reporter,
      departmentProgram:
          preset.departmentProgram ??
          (_department == 'All' ? null : _department),
      outcome: _outcome == 'All' ? null : _outcome,
      schoolYear: _schoolYear == 'All' ? null : _schoolYear,
      term: _term == 'All' ? null : _term,
    );
    if (widget.onOpenRecords != null) {
      widget.onOpenRecords!(merged);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ViolationRecordsPage(initialFilterPreset: merged),
        ),
      );
    }
  }

  DateTimeRange? _monthRange(String label) {
    try {
      final d = DateFormat('MMM yyyy').parseStrict(label);
      return DateTimeRange(
        start: DateTime(d.year, d.month, 1),
        end: DateTime(d.year, d.month + 1, 0),
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _opts(Iterable<String> raw) {
    final s = <String>{'All'};
    for (final v in raw) {
      final x = v.trim();
      if (x.isNotEmpty && x != '--') s.add(x);
    }
    final r = s.toList()..remove('All');
    r.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All', ...r];
  }
}

class _Case {
  final String caseCode,
      studentName,
      studentNo,
      concern,
      category,
      violation,
      reporter,
      department,
      outcome,
      schoolYear,
      term;
  final DateTime? date;
  const _Case(
    this.caseCode,
    this.studentName,
    this.studentNo,
    this.concern,
    this.category,
    this.violation,
    this.reporter,
    this.department,
    this.outcome,
    this.schoolYear,
    this.term,
    this.date,
  );

  factory _Case.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    String v(dynamic x) => (x ?? '').toString().trim();
    DateTime? best() {
      for (final c in [
        m['resolvedAt'],
        m['updatedAt'],
        m['createdAt'],
        m['incidentAt'],
        m['submittedAt'],
      ]) {
        if (c is Timestamp) return c.toDate();
      }
      return null;
    }

    final concernRaw = v(
      m['concern'] ?? m['concernType'] ?? m['reportedConcernType'],
    );
    final concern = concernRaw.toLowerCase().contains('serious')
        ? 'Serious'
        : concernRaw.toLowerCase().contains('basic')
        ? 'Basic'
        : (concernRaw.isEmpty ? '--' : concernRaw);
    final dept = v(
      m['studentDepartment'] ?? m['studentCollegeId'] ?? m['department'],
    );
    final prog = v(
      m['programId'] ??
          m['studentProgramId'] ??
          m['studentProgram'] ??
          m['program'],
    );
    return _Case(
      v(m['caseCode']).isEmpty
          ? (d.id.length > 8 ? d.id.substring(0, 8) : d.id)
          : v(m['caseCode']),
      v(m['studentName']).isEmpty ? 'Unknown' : v(m['studentName']),
      v(m['studentNo']).isEmpty ? '--' : v(m['studentNo']),
      concern,
      v(
            m['categoryNameSnapshot'] ??
                m['reportedCategoryNameSnapshot'] ??
                m['categoryName'],
          ).isEmpty
          ? '--'
          : v(
              m['categoryNameSnapshot'] ??
                  m['reportedCategoryNameSnapshot'] ??
                  m['categoryName'],
            ),
      v(
            m['violationTypeLabel'] ??
                m['typeNameSnapshot'] ??
                m['violationNameSnapshot'] ??
                m['violationName'],
          ).isEmpty
          ? '--'
          : v(
              m['violationTypeLabel'] ??
                  m['typeNameSnapshot'] ??
                  m['violationNameSnapshot'] ??
                  m['violationName'],
            ),
      v(m['reportedByName'] ?? m['reporterName'] ?? m['reportedByRole']).isEmpty
          ? '--'
          : v(m['reportedByName'] ?? m['reporterName'] ?? m['reportedByRole']),
      dept.isNotEmpty ? dept : (prog.isEmpty ? '--' : prog),
      v(
            m['outcome'] ?? m['resolution'] ?? m['finalAction'] ?? m['status'],
          ).isEmpty
          ? '--'
          : v(
              m['outcome'] ??
                  m['resolution'] ??
                  m['finalAction'] ??
                  m['status'],
            ),
      v(
            m['schoolYearName'] ??
                m['schoolYearLabel'] ??
                m['schoolYearId'] ??
                m['syId'],
          ).isEmpty
          ? '--'
          : v(
              m['schoolYearName'] ??
                  m['schoolYearLabel'] ??
                  m['schoolYearId'] ??
                  m['syId'],
            ),
      v(m['termName'] ?? m['termLabel'] ?? m['termId']).isEmpty
          ? '--'
          : v(m['termName'] ?? m['termLabel'] ?? m['termId']),
      best(),
    );
  }
}

class _StudentCount {
  final String name;
  final String no;
  final int count;
  const _StudentCount(this.name, this.no, this.count);
}

class _DeptRow {
  final String department;
  final int total;
  final int basic;
  final int serious;
  const _DeptRow(this.department, this.total, this.basic, this.serious);
}

class _Metrics {
  final int total, basic, serious, repeatOffenders;
  final Map<String, int> monthCounts,
      categoryCounts,
      departmentCounts,
      violationCounts;
  final List<_StudentCount> students;
  final List<_DeptRow> departmentRows;
  final List<(String, String)> departmentTrends;
  const _Metrics(
    this.total,
    this.basic,
    this.serious,
    this.repeatOffenders,
    this.monthCounts,
    this.categoryCounts,
    this.departmentCounts,
    this.violationCounts,
    this.students,
    this.departmentRows,
    this.departmentTrends,
  );

  factory _Metrics.from(List<_Case> cases) {
    final month = <String, int>{},
        cat = <String, int>{},
        dept = <String, int>{},
        vio = <String, int>{};
    final studentAgg = <String, _StudentCount>{};
    final deptAgg = <String, _DeptRow>{};
    final deptMonth = <String, Map<String, int>>{};
    var basic = 0, serious = 0;
    for (final c in cases) {
      if (c.concern.toLowerCase() == 'basic') basic++;
      if (c.concern.toLowerCase() == 'serious') serious++;
      final m = c.date == null
          ? 'Unknown'
          : DateFormat('MMM yyyy').format(c.date!);
      month[m] = (month[m] ?? 0) + 1;
      cat[c.category] = (cat[c.category] ?? 0) + 1;
      dept[c.department] = (dept[c.department] ?? 0) + 1;
      vio[c.violation] = (vio[c.violation] ?? 0) + 1;
      final key = c.studentNo == '--' ? c.studentName : c.studentNo;
      final s = studentAgg[key];
      studentAgg[key] = _StudentCount(
        c.studentName,
        c.studentNo,
        (s?.count ?? 0) + 1,
      );
      final d = deptAgg[c.department];
      deptAgg[c.department] = _DeptRow(
        c.department,
        (d?.total ?? 0) + 1,
        (d?.basic ?? 0) + (c.concern.toLowerCase() == 'basic' ? 1 : 0),
        (d?.serious ?? 0) + (c.concern.toLowerCase() == 'serious' ? 1 : 0),
      );
      final dm = deptMonth.putIfAbsent(c.department, () => {});
      dm[m] = (dm[m] ?? 0) + 1;
    }
    Map<String, int> sort(Map<String, int> m) {
      final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return {for (final x in e) x.key: x.value};
    }

    final students = studentAgg.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final dRows = deptAgg.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final trends = deptMonth.entries.map((e) {
      final top =
          (e.value.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .take(3)
              .map((x) => '${x.key}: ${x.value}')
              .join(' · ');
      return (e.key, top);
    }).toList()..sort((a, b) => a.$1.compareTo(b.$1));
    return _Metrics(
      cases.length,
      basic,
      serious,
      students.where((e) => e.count >= 2).length,
      sort(month),
      sort(cat),
      sort(dept),
      sort(vio),
      students,
      dRows,
      trends,
    );
  }
}

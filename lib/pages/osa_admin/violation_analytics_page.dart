import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/violation_case_service.dart';
import '../shared/widgets/modern_table_layout.dart';
import 'violation_records_page.dart';

enum _AnalyticsTab { overview, violations, students, departments }

enum _DistributionChartKind { vertical, horizontal, table, donut }

class ViolationAnalyticsPage extends StatefulWidget {
  final ValueChanged<ViolationRecordsFilterPreset>? onOpenRecords;
  const ViolationAnalyticsPage({super.key, this.onOpenRecords});

  @override
  State<ViolationAnalyticsPage> createState() => _ViolationAnalyticsPageState();
}

class _ViolationAnalyticsPageState extends State<ViolationAnalyticsPage> {
  static const _bg = Colors.white;
  static const _primary = Color(0xFF1B5E20);
  static const _textDark = Color(0xFF1F2A1F);
  static const _hint = Color(0xFF6D7F62);
  bool _useDummyOverviewData = true;
  bool _useEmptyOverviewData = false;

  String _schoolYear = 'All';
  String _term = 'All';
  String _department = 'All';
  String _concern = 'All';
  String _category = 'All';
  String _violationType = 'All';
  String _reporter = 'All';
  String _outcome = 'All';
  DateTimeRange? _dateRange;
  bool _showAdvancedFilters = false;
  _AnalyticsTab _tab = _AnalyticsTab.overview;
  _DistributionChartKind _categoryChartKind = _DistributionChartKind.vertical;
  _DistributionChartKind _violationChartKind = _DistributionChartKind.vertical;

  @override
  Widget build(BuildContext context) {
    if (_useDummyOverviewData || _useEmptyOverviewData) {
      final all = _useEmptyOverviewData ? const <_Case>[] : _buildDummyCases();
      final sy = _safeOpts(all.map((e) => e.schoolYear));
      final term = _safeOpts(all.map((e) => e.term));
      final dept = _safeOpts(all.map((e) => e.department));
      final cat = _safeOpts(all.map((e) => e.category));
      final vio = _safeOpts(all.map((e) => e.violation));
      final rep = _safeOpts(all.map((e) => e.reporter));
      final filtered = all.where(_matches).toList(growable: false);
      final m = _Metrics.from(filtered);
      return Scaffold(
        backgroundColor: _bg,
        body: _buildAnalyticsLayout(
          filtered: filtered,
          metrics: m,
          schoolYears: sy,
          terms: term,
          departments: dept,
          categories: cat,
          violationTypes: vio,
          reporters: rep,
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ViolationCaseService().streamAllCases(limit: 1500),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snap.data!.docs
              .map((d) => _Case.fromDoc(d))
              .toList(growable: false);
          final sy = _safeOpts(all.map((e) => e.schoolYear));
          final term = _safeOpts(all.map((e) => e.term));
          final dept = _safeOpts(all.map((e) => e.department));
          final cat = _safeOpts(all.map((e) => e.category));
          final vio = _safeOpts(all.map((e) => e.violation));
          final rep = _safeOpts(all.map((e) => e.reporter));
          final filtered = all.where(_matches).toList(growable: false);
          final m = _Metrics.from(filtered);

          return _buildAnalyticsLayout(
            filtered: filtered,
            metrics: m,
            schoolYears: sy,
            terms: term,
            departments: dept,
            categories: cat,
            violationTypes: vio,
            reporters: rep,
          );
        },
      ),
    );
  }

  List<String> _safeOpts(Iterable<String> values) {
    final opts = _opts(values);
    return opts.isEmpty ? const ['All'] : opts;
  }

  bool get _previewMutedCharts =>
      _useDummyOverviewData || _useEmptyOverviewData;

  Color _previewGreen(Color color) {
    if (!_previewMutedCharts) return color;
    return const Color(0xFFB7BDB7);
  }

  Color _previewGreenDark(Color color) {
    if (!_previewMutedCharts) return color;
    return const Color(0xFF8F998F);
  }

  Widget _buildAnalyticsLayout({
    required List<_Case> filtered,
    required _Metrics metrics,
    required List<String> schoolYears,
    required List<String> terms,
    required List<String> departments,
    required List<String> categories,
    required List<String> violationTypes,
    required List<String> reporters,
  }) {
    return ModernTableLayout(
      header: ModernTableHeader(
        showTitleSection: false,
        showTopControlsWhenTitleHidden: true,
        showSearchBar: false,
        searchBar: const SizedBox.shrink(),
        tabs: _tabsWithFilters(
          _toolbar(
            schoolYears,
            terms,
            departments,
            categories,
            violationTypes,
            reporters,
          ),
        ),
        filters: const [],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: _tabContent(metrics),
            ),
          ),
        ],
      ),
    );
  }

  List<_Case> _buildDummyCases() {
    final cases = <_Case>[];
    final months = List<DateTime>.generate(12, (i) => DateTime(2025, 6 + i, 1));
    const departments = <String>[
      'CCS',
      'CBA',
      'COE',
      'COA',
      'CAS',
      'Senior High',
    ];
    const reporters = <String>[
      'Prof. Santos',
      'Prof. Reyes',
      'Prof. Cruz',
      'Guard Team A',
      'Guard Team B',
    ];
    const outcomes = <String>[
      'Resolved',
      'Resolved',
      'Resolved',
      'Unresolved',
      'Cancelled',
    ];
    const violationDefs = <(String, String, String, int)>[
      ('Cheating', 'Academic Integrity', 'Serious', 34),
      ('Dress Code', 'Conduct', 'Basic', 28),
      ('Tardiness', 'Attendance', 'Basic', 26),
      ('Disrespect', 'Conduct', 'Serious', 22),
      ('Vandalism', 'Property', 'Serious', 18),
      ('Unauthorized Entry', 'Security', 'Serious', 14),
      ('Class Disturbance', 'Conduct', 'Basic', 16),
      ('ID Violation', 'Security', 'Basic', 20),
    ];

    var seq = 1;
    for (var monthIndex = 0; monthIndex < months.length; monthIndex++) {
      final month = months[monthIndex];
      for (var vIndex = 0; vIndex < violationDefs.length; vIndex++) {
        final def = violationDefs[vIndex];
        final count = math.max(
          2,
          def.$4 - (monthIndex * (vIndex.isEven ? 1 : 0)),
        );
        for (var n = 0; n < count; n++) {
          final studentSeed = (monthIndex * 97) + (vIndex * 17) + n;
          final studentNo =
              '19-${(1000 + (studentSeed % 8999)).toString().padLeft(4, '0')}';
          final firstName = [
            'Reynaldo',
            'Maria',
            'John',
            'Angela',
            'Carlo',
            'Mika',
            'Paolo',
            'Nina',
          ][studentSeed % 8];
          final lastName = [
            'Dela Cruz',
            'Santos',
            'Garcia',
            'Mendoza',
            'Reyes',
            'Bautista',
            'Torres',
            'Lopez',
          ][(studentSeed ~/ 3) % 8];
          final incidentDay = 1 + ((studentSeed * 3) % 26);
          final incidentDate = DateTime(month.year, month.month, incidentDay);
          final term = switch (incidentDate.month) {
            6 || 7 || 8 || 9 || 10 => '1st Semester',
            11 || 12 || 1 || 2 => '2nd Semester',
            _ => '3rd Semester',
          };

          cases.add(
            _Case(
              'VC-2627-${seq.toString().padLeft(4, '0')}',
              '$lastName, $firstName',
              studentNo,
              def.$3,
              def.$2,
              def.$1,
              reporters[(studentSeed + vIndex) % reporters.length],
              departments[(studentSeed + monthIndex) % departments.length],
              outcomes[(studentSeed + n) % outcomes.length],
              'SY 2026-2027',
              term,
              incidentDate,
            ),
          );
          seq++;
        }
      }
    }
    return cases;
  }

  Widget _dataSourceToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _useEmptyOverviewData
                ? 'Empty: ON'
                : (_useDummyOverviewData ? 'Dummy: ON' : 'Live: ON'),
            style: TextStyle(
              color: (_useEmptyOverviewData || _useDummyOverviewData)
                  ? _primary
                  : _hint,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: _useEmptyOverviewData || _useDummyOverviewData,
            activeColor: _primary,
            onChanged: (value) {
              setState(() {
                if (!value) {
                  _useDummyOverviewData = false;
                  _useEmptyOverviewData = false;
                } else if (_useEmptyOverviewData) {
                  _useEmptyOverviewData = false;
                  _useDummyOverviewData = true;
                } else {
                  _useDummyOverviewData = !_useDummyOverviewData;
                }
              });
            },
          ),
        ],
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
  ) {
    final hasActive = _hasActiveAnalyticsFilters();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterLeadingIcon(onTap: () => _openAdvanced(cat, vio, rep)),
          const SizedBox(width: 8),
          _dd(
            'School Year',
            _schoolYear,
            sy,
            (v) => setState(() => _schoolYear = v),
          ),
          _dd('Semester', _term, term, (v) => setState(() => _term = v)),
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
          if (hasActive) ...[
            const SizedBox(width: 2),
            _clearFiltersIconButton(),
          ],
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
      width: 220,
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        decoration: _reportLikeDropdownDecoration(label: label),
        items: options
            .map(
              (e) => DropdownMenuItem<String>(
                value: e,
                child: Text(
                  e,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _textDark,
                  ),
                ),
              ),
            )
            .toList(),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        borderRadius: BorderRadius.circular(12),
        menuMaxHeight: 360,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Future<void> _openAdvanced(
    List<String> cat,
    List<String> vio,
    List<String> rep,
  ) async {
    if (_showAdvancedFilters) return;
    var dataSource = _useEmptyOverviewData
        ? 'Empty Data'
        : (_useDummyOverviewData ? 'Dummy Data' : 'Live Firestore');
    var concern = _concern;
    var dCat = _category;
    var dVio = _violationType;
    var dRep = _reporter;
    var dRange = _dateRange;

    setState(() => _showAdvancedFilters = true);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Advanced Filters',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> pickDateFrom() async {
                final picked = await _showSingleFilterDatePicker(
                  initialDate: dRange?.start,
                );
                if (picked == null) return;
                final currentEnd = dRange?.end;
                setModalState(() {
                  if (currentEnd != null && currentEnd.isBefore(picked)) {
                    dRange = DateTimeRange(start: picked, end: picked);
                  } else {
                    dRange = DateTimeRange(
                      start: picked,
                      end: currentEnd ?? picked,
                    );
                  }
                });
              }

              Future<void> pickDateTo() async {
                final picked = await _showSingleFilterDatePicker(
                  initialDate: dRange?.end ?? dRange?.start,
                );
                if (picked == null) return;
                final currentStart = dRange?.start ?? picked;
                setModalState(() {
                  if (picked.isBefore(currentStart)) {
                    dRange = DateTimeRange(start: picked, end: picked);
                  } else {
                    dRange = DateTimeRange(start: currentStart, end: picked);
                  }
                });
              }

              return Material(
                color: Colors.transparent,
                child: SafeArea(
                  child: Container(
                    width: 390,
                    margin: const EdgeInsets.fromLTRB(10, 12, 12, 12),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 28,
                          offset: const Offset(-2, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Advanced Filters',
                                style: TextStyle(
                                  color: _textDark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Filter analytics by key attributes.',
                          style: TextStyle(
                            color: _hint,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Divider(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                _panelDropdown(
                                  label: 'Data Source',
                                  value: dataSource,
                                  options: const [
                                    'Dummy Data',
                                    'Empty Data',
                                    'Live Firestore',
                                  ],
                                  onChanged: (v) =>
                                      setModalState(() => dataSource = v),
                                ),
                                const SizedBox(height: 14),
                                _panelDropdown(
                                  label: 'Concern Type',
                                  value: concern,
                                  options: const ['All', 'Basic', 'Serious'],
                                  onChanged: (v) =>
                                      setModalState(() => concern = v),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildDateBoundField(
                                        label: 'Date from',
                                        value: dRange?.start,
                                        onTap: pickDateFrom,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildDateBoundField(
                                        label: 'Date to',
                                        value: dRange?.end,
                                        onTap: pickDateTo,
                                      ),
                                    ),
                                  ],
                                ),
                                if (dRange != null) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          setModalState(() => dRange = null),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Clear dates'),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _panelDropdown(
                                  label: 'Category',
                                  value: dCat,
                                  options: cat,
                                  onChanged: (v) =>
                                      setModalState(() => dCat = v),
                                ),
                                const SizedBox(height: 14),
                                _panelDropdown(
                                  label: 'Violation Type',
                                  value: dVio,
                                  options: vio,
                                  onChanged: (v) =>
                                      setModalState(() => dVio = v),
                                ),
                                const SizedBox(height: 14),
                                _panelDropdown(
                                  label: 'Reporter',
                                  value: dRep,
                                  options: rep,
                                  onChanged: (v) =>
                                      setModalState(() => dRep = v),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  setState(() {
                                    _useDummyOverviewData =
                                        dataSource == 'Dummy Data';
                                    _useEmptyOverviewData =
                                        dataSource == 'Empty Data';
                                    _concern = concern;
                                    _category = dCat;
                                    _violationType = dVio;
                                    _reporter = dRep;
                                    _dateRange = dRange;
                                  });
                                  Navigator.of(context).pop();
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
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final offsetTween = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        );
        return SlideTransition(
          position: offsetTween.animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
    if (!mounted) return;
    setState(() => _showAdvancedFilters = false);
  }

  Widget _filterLeadingIcon({required VoidCallback onTap}) {
    return Tooltip(
      message: 'Advanced Filters',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.tune_rounded,
            size: 20,
            color: _primary.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Widget _clearFiltersIconButton() {
    return Tooltip(
      message: 'Clear filters',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => setState(_clearFilters),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.filter_alt_off_rounded,
            size: 19,
            color: _primary.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  bool _hasActiveAnalyticsFilters() {
    return _schoolYear != 'All' ||
        _term != 'All' ||
        _department != 'All' ||
        _concern != 'All' ||
        _category != 'All' ||
        _violationType != 'All' ||
        _reporter != 'All' ||
        _outcome != 'All' ||
        _dateRange != null;
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

  Widget _analyticsTabBar() {
    const tabs = [
      _AnalyticsTab.overview,
      _AnalyticsTab.violations,
      _AnalyticsTab.students,
      _AnalyticsTab.departments,
    ];
    final currentIndex = tabs.indexOf(_tab);
    final safeInitialIndex = currentIndex < 0 ? 0 : currentIndex;
    return DefaultTabController(
      length: tabs.length,
      initialIndex: safeInitialIndex,
      child: Builder(
        builder: (context) {
          return TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: _primary,
            unselectedLabelColor: _hint,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900),
            indicatorColor: _primary,
            dividerColor: Colors.transparent,
            onTap: (index) {
              final next = tabs[index];
              if (next != _tab) {
                setState(() => _tab = next);
              }
            },
            tabs: tabs
                .map((tab) => Tab(text: _analyticsTabLabel(tab)))
                .toList(),
          );
        },
      ),
    );
  }

  String _analyticsTabLabel(_AnalyticsTab tab) {
    switch (tab) {
      case _AnalyticsTab.overview:
        return 'Overview';
      case _AnalyticsTab.violations:
        return 'Violation Patterns';
      case _AnalyticsTab.students:
        return 'Student Risk';
      case _AnalyticsTab.departments:
        return 'Department Insights';
    }
  }

  Widget _tabContent(_Metrics m) {
    switch (_tab) {
      case _AnalyticsTab.overview:
        return _buildOverviewTab(m);
      case _AnalyticsTab.violations:
        final isWide = MediaQuery.sizeOf(context).width >= 1120;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _card(
                      'Category Distribution',
                      _buildDistributionContent(
                        data: m.categoryCounts,
                        kind: _categoryChartKind,
                        onTap: (k) =>
                            _drill(ViolationRecordsFilterPreset(category: k)),
                        barColor: _previewGreen(const Color(0xFF43A047)),
                      ),
                      trailing: _distributionKindSelector(
                        value: _categoryChartKind,
                        onChanged: (next) =>
                            setState(() => _categoryChartKind = next),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _card(
                      'Violation Type Distribution',
                      _buildDistributionContent(
                        data: m.violationCounts,
                        kind: _violationChartKind,
                        onTap: (k) => _drill(
                          ViolationRecordsFilterPreset(violationType: k),
                        ),
                        maxItems: 14,
                        barColor: _previewGreen(const Color(0xFF1B5E20)),
                      ),
                      trailing: _distributionKindSelector(
                        value: _violationChartKind,
                        onChanged: (next) =>
                            setState(() => _violationChartKind = next),
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              _card(
                'Category Distribution',
                _buildDistributionContent(
                  data: m.categoryCounts,
                  kind: _categoryChartKind,
                  onTap: (k) =>
                      _drill(ViolationRecordsFilterPreset(category: k)),
                  barColor: _previewGreen(const Color(0xFF43A047)),
                ),
                trailing: _distributionKindSelector(
                  value: _categoryChartKind,
                  onChanged: (next) =>
                      setState(() => _categoryChartKind = next),
                ),
              ),
              const SizedBox(height: 12),
              _card(
                'Violation Type Distribution',
                _buildDistributionContent(
                  data: m.violationCounts,
                  kind: _violationChartKind,
                  onTap: (k) =>
                      _drill(ViolationRecordsFilterPreset(violationType: k)),
                  maxItems: 14,
                  barColor: _previewGreen(const Color(0xFF1B5E20)),
                ),
                trailing: _distributionKindSelector(
                  value: _violationChartKind,
                  onChanged: (next) =>
                      setState(() => _violationChartKind = next),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _card(
              'Basic vs Serious Distribution',
              _concernDonut(
                basic: m.basic,
                serious: m.serious,
                onTapBasic: () => _drill(
                  const ViolationRecordsFilterPreset(concern: 'Basic'),
                ),
                onTapSerious: () => _drill(
                  const ViolationRecordsFilterPreset(concern: 'Serious'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Monthly Trend (Focused)',
              _verticalBarChart(
                m.monthCounts,
                (k) => _drill(
                  ViolationRecordsFilterPreset(dateRange: _monthRange(k)),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
          ],
        );
      case _AnalyticsTab.students:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _card('Students by Violation Count', _studentHistogram(m.students)),
            const SizedBox(height: 12),
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
          ],
        );
      case _AnalyticsTab.departments:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _card(
              'Department Totals',
              _verticalBarChart(
                m.departmentCounts,
                (k) =>
                    _drill(ViolationRecordsFilterPreset(departmentProgram: k)),
                barColor: _previewGreen(const Color(0xFF33691E)),
              ),
            ),
            const SizedBox(height: 12),
            _card(
              'Department Concern Mix',
              _stackedDepartmentBars(m.departmentRows),
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

  Widget _buildOverviewTab(_Metrics m) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 1120;

    final topViolations = {
      for (final e in m.violationCounts.entries.take(5)) e.key: e.value,
    };
    final topDepartments = {
      for (final e in m.departmentCounts.entries.take(5)) e.key: e.value,
    };
    const topSummaryRowHeight = 356.0;
    const topKpiColumnWidth = 220.0;
    const middleOverviewRowHeight = 340.0;

    final kpiCards = [
      _stat(
        'Total Violations',
        '${m.total}',
        () => _drill(const ViolationRecordsFilterPreset()),
      ),
      _stat(
        'Basic',
        '${m.basic}',
        () => _drill(const ViolationRecordsFilterPreset(concern: 'Basic')),
      ),
      _stat(
        'Serious',
        '${m.serious}',
        () => _drill(const ViolationRecordsFilterPreset(concern: 'Serious')),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: topKpiColumnWidth,
                height: topSummaryRowHeight,
                child: Column(
                  children: [
                    Expanded(child: kpiCards[0]),
                    const SizedBox(height: 8),
                    Expanded(child: kpiCards[1]),
                    const SizedBox(height: 8),
                    Expanded(child: kpiCards[2]),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: topSummaryRowHeight,
                  child: _card(
                    'Monthly Violations Trend by Severity',
                    _monthlySeverityTrendChart(
                      m.monthSeverityTrend,
                      (k) => _drill(
                        ViolationRecordsFilterPreset(dateRange: _monthRange(k)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        else ...[
          _kpiGrid(columns: 1, children: kpiCards),
          const SizedBox(height: 12),
          _card(
            'Monthly Violations Trend by Severity',
            _monthlySeverityTrendChart(
              m.monthSeverityTrend,
              (k) => _drill(
                ViolationRecordsFilterPreset(dateRange: _monthRange(k)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: middleOverviewRowHeight,
                  child: _card(
                    'Basic vs Serious',
                    _concernDonut(
                      basic: m.basic,
                      serious: m.serious,
                      onTapBasic: () => _drill(
                        const ViolationRecordsFilterPreset(concern: 'Basic'),
                      ),
                      onTapSerious: () => _drill(
                        const ViolationRecordsFilterPreset(concern: 'Serious'),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: middleOverviewRowHeight,
                  child: _card(
                    'Top 5 Violation Types',
                    _bars(
                      topViolations,
                      (k) => _drill(
                        ViolationRecordsFilterPreset(violationType: k),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: middleOverviewRowHeight,
                  child: _card(
                    'Top 5 Departments by Violations',
                    _verticalBarChart(
                      topDepartments,
                      (k) => _drill(
                        ViolationRecordsFilterPreset(departmentProgram: k),
                      ),
                      maxItems: 5,
                      barColor: _previewGreen(const Color(0xFF33691E)),
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              _card(
                'Basic vs Serious',
                _concernDonut(
                  basic: m.basic,
                  serious: m.serious,
                  onTapBasic: () => _drill(
                    const ViolationRecordsFilterPreset(concern: 'Basic'),
                  ),
                  onTapSerious: () => _drill(
                    const ViolationRecordsFilterPreset(concern: 'Serious'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _card(
                'Top 5 Violation Types',
                _bars(
                  topViolations,
                  (k) => _drill(ViolationRecordsFilterPreset(violationType: k)),
                ),
              ),
              const SizedBox(height: 12),
              _card(
                'Top 5 Departments by Violations',
                _verticalBarChart(
                  topDepartments,
                  (k) => _drill(
                    ViolationRecordsFilterPreset(departmentProgram: k),
                  ),
                  maxItems: 5,
                  barColor: _previewGreen(const Color(0xFF33691E)),
                ),
              ),
            ],
          ),
      ],
    );
  }

  InputDecoration _reportLikeDropdownDecoration({required String label}) {
    final baseBorderColor = _primary.withValues(alpha: 0.20);
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _hint, fontWeight: FontWeight.w700),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: baseBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: baseBorderColor),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    );
  }

  Widget _tabsWithFilters(Widget filtersRow) {
    final chips = _activeAnalyticsFilterChips();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        filtersRow,
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          _activeFiltersRow(chips),
        ],
        const SizedBox(height: 8),
        _analyticsTabBar(),
      ],
    );
  }

  Widget _activeFiltersRow(List<_ActiveAnalyticsFilterChipData> chips) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: chips
            .map(
              (chip) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _HoverDismissFilterChip(
                  label: chip.label,
                  onRemove: chip.onRemove,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  List<_ActiveAnalyticsFilterChipData> _activeAnalyticsFilterChips() {
    final chips = <_ActiveAnalyticsFilterChipData>[];

    void addChip({
      required String current,
      required String label,
      required VoidCallback onRemove,
    }) {
      if (current == 'All') return;
      chips.add(
        _ActiveAnalyticsFilterChipData(
          label: '$label: $current',
          onRemove: onRemove,
        ),
      );
    }

    addChip(
      current: _schoolYear,
      label: 'School Year',
      onRemove: () => setState(() => _schoolYear = 'All'),
    );
    addChip(
      current: _term,
      label: 'Semester',
      onRemove: () => setState(() => _term = 'All'),
    );
    addChip(
      current: _department,
      label: 'Department',
      onRemove: () => setState(() => _department = 'All'),
    );
    addChip(
      current: _concern,
      label: 'Concern',
      onRemove: () => setState(() => _concern = 'All'),
    );
    addChip(
      current: _category,
      label: 'Category',
      onRemove: () => setState(() => _category = 'All'),
    );
    addChip(
      current: _violationType,
      label: 'Violation',
      onRemove: () => setState(() => _violationType = 'All'),
    );
    addChip(
      current: _reporter,
      label: 'Reporter',
      onRemove: () => setState(() => _reporter = 'All'),
    );
    addChip(
      current: _outcome,
      label: 'Outcome',
      onRemove: () => setState(() => _outcome = 'All'),
    );
    if (_dateRange != null) {
      final rangeLabel =
          '${DateFormat('MMM d, yyyy').format(_dateRange!.start)} - ${DateFormat('MMM d, yyyy').format(_dateRange!.end)}';
      chips.add(
        _ActiveAnalyticsFilterChipData(
          label: 'Date: $rangeLabel',
          onRemove: () => setState(() => _dateRange = null),
        ),
      );
    }

    return chips;
  }

  Widget _kpiGrid({required int columns, required List<Widget> children}) {
    final ratio = columns == 1
        ? 1.9
        : columns == 2
        ? 2.25
        : 2.55;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: ratio,
      ),
      itemBuilder: (context, index) => children[index],
    );
  }

  Widget _stat(String label, String value, VoidCallback? onTap) {
    final accent = _kpiAccentColor(label);
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 106;
          final tiny = constraints.maxHeight < 84;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: compact ? 15 : 20,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w800,
                        fontSize: tiny ? 12.0 : (compact ? 13.0 : 14.0),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        color: accent,
                        fontSize: tiny ? 22 : (compact ? 24 : 30),
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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

  Color _kpiAccentColor(String label) {
    final key = label.toLowerCase();
    if (key.contains('serious')) return const Color(0xFFEF6C00);
    if (key.contains('basic')) {
      return _previewGreen(const Color(0xFF2E7D32));
    }
    return _primary;
  }

  int _axisStepForMax(int maxValue) {
    if (maxValue <= 25) return 5;
    if (maxValue <= 60) return 10;
    if (maxValue <= 120) return 20;
    if (maxValue <= 300) return 50;
    return 100;
  }

  int _niceAxisMax(int value) {
    if (value <= 0) return 20;
    final step = _axisStepForMax(value);
    return ((value + step - 1) ~/ step) * step;
  }

  List<int> _axisTicks(int maxValue) {
    final step = _axisStepForMax(maxValue);
    final axisMax = _niceAxisMax(maxValue);
    final ticks = <int>[];
    for (var v = axisMax; v >= 0; v -= step) {
      ticks.add(v);
    }
    if (ticks.isEmpty || ticks.last != 0) {
      ticks.add(0);
    }
    return ticks;
  }

  Widget _distributionKindSelector({
    required _DistributionChartKind value,
    required ValueChanged<_DistributionChartKind> onChanged,
  }) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<_DistributionChartKind>(
        value: value,
        isDense: true,
        borderRadius: BorderRadius.circular(10),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        style: const TextStyle(
          color: _hint,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        items: _DistributionChartKind.values
            .map(
              (kind) => DropdownMenuItem<_DistributionChartKind>(
                value: kind,
                child: Text(_distributionKindLabel(kind)),
              ),
            )
            .toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  String _distributionKindLabel(_DistributionChartKind kind) {
    switch (kind) {
      case _DistributionChartKind.vertical:
        return 'Vertical';
      case _DistributionChartKind.horizontal:
        return 'Horizontal';
      case _DistributionChartKind.table:
        return 'Table';
      case _DistributionChartKind.donut:
        return 'Donut';
    }
  }

  Widget _buildDistributionContent({
    required Map<String, int> data,
    required _DistributionChartKind kind,
    required ValueChanged<String> onTap,
    required Color barColor,
    int maxItems = 12,
  }) {
    final limited = Map<String, int>.fromEntries(data.entries.take(maxItems));
    switch (kind) {
      case _DistributionChartKind.vertical:
        return _verticalBarChart(
          limited,
          onTap,
          maxItems: maxItems,
          barColor: barColor,
        );
      case _DistributionChartKind.horizontal:
        return _bars(limited, onTap);
      case _DistributionChartKind.table:
        return _table(
          const ['Label', 'Total'],
          limited.entries.map((e) => [e.key, '${e.value}']).toList(),
          onRowTap: (row) => onTap(row[0]),
        );
      case _DistributionChartKind.donut:
        return _donutDistributionChart(limited, onTap, accent: barColor);
    }
  }

  Widget _donutDistributionChart(
    Map<String, int> data,
    ValueChanged<String> onTap, {
    required Color accent,
  }) {
    final isNoData = data.isEmpty || data.values.every((v) => v == 0);
    final working = isNoData ? const {'No data': 1} : data;

    final sorted = working.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();
    final otherTotal = sorted.skip(5).fold<int>(0, (sum, e) => sum + e.value);

    final palette = <Color>[
      isNoData ? const Color(0xFFB7BDB7) : accent,
      isNoData
          ? const Color(0xFFB7BDB7)
          : _previewGreen(const Color(0xFF43A047)),
      isNoData
          ? const Color(0xFFB7BDB7)
          : _previewGreen(const Color(0xFF66BB6A)),
      isNoData
          ? const Color(0xFFB7BDB7)
          : _previewGreen(const Color(0xFF8BC34A)),
      const Color(0xFF26A69A),
      const Color(0xFF90A4AE),
    ];

    final slices = <_DonutSlice>[
      for (var i = 0; i < top.length; i++)
        _DonutSlice(top[i].key, top[i].value, palette[i % palette.length]),
      if (otherTotal > 0)
        _DonutSlice('Others', otherTotal, palette.last.withValues(alpha: 0.9)),
    ];
    final total = isNoData ? 0 : slices.fold<int>(0, (sum, s) => sum + s.value);

    return SizedBox(
      height: 230,
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 154,
                    height: 154,
                    child: CustomPaint(
                      painter: _DonutDistributionPainter(slices: slices),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isNoData ? '0' : '$total',
                        style: const TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        isNoData ? 'No data' : 'Total',
                        style: const TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: slices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final s = slices[index];
                final pct = total == 0 ? 0 : ((s.value / total) * 100);
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: isNoData || s.label == 'Others'
                      ? null
                      : () => onTap(s.label),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
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
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: isNoData ? const Color(0xFFB7BDB7) : s.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isNoData ? 'No data' : s.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isNoData
                              ? '0'
                              : '${s.value} (${pct.toStringAsFixed(0)}%)',
                          style: TextStyle(
                            color: isNoData ? _hint : _hint,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.8,
                          ),
                        ),
                      ],
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

  Widget _card(String title, Widget child, {Widget? trailing}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF8FBF8)],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black.withValues(alpha: 0.09)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1B5E20).withValues(alpha: 0.04),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 22,
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 16.5,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing],
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 1,
          width: double.infinity,
          color: Colors.black.withValues(alpha: 0.06),
        ),
        const SizedBox(height: 12),
        DefaultTextStyle.merge(
          style: const TextStyle(color: _textDark),
          child: child,
        ),
      ],
    ),
  );

  Widget _bars(Map<String, int> data, ValueChanged<String> onTap) {
    final isNoData = data.isEmpty || data.values.every((v) => v == 0);
    final renderData = isNoData ? const {'No data': 0} : data;
    final maxVal = renderData.values.fold<int>(1, (a, b) => a > b ? a : b);
    final axisMax = _niceAxisMax(maxVal);
    final axisTicks = _axisTicks(maxVal);
    final tickValues = axisTicks.reversed.toList(); // 0 -> max
    const barHeight = 12.0;
    const rowHeight = 24.0;
    const rowGap = 10.0;
    const labelWidth = 88.0;
    const labelGap = 0.0;
    const valueWidth = 28.0;
    final rows = renderData.entries.take(12).toList();
    final placeholderCount = isNoData ? 0 : math.max(0, 5 - rows.length);
    final displayRows = <MapEntry<String, int>>[
      ...rows,
      ...List.generate(placeholderCount, (_) => const MapEntry('', 0)),
    ];
    final barAreaHeight =
        (displayRows.length * rowHeight) + ((displayRows.length - 1) * rowGap);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Column(
                  children: [
                    ...displayRows.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final e = entry.value;
                      final isPlaceholder = e.key.isEmpty;
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: idx == displayRows.length - 1 ? 0 : rowGap,
                        ),
                        child: SizedBox(
                          height: rowHeight,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              isPlaceholder
                                  ? ' '
                                  : (isNoData ? 'No data' : e.key),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(width: labelGap),
              Expanded(
                child: SizedBox(
                  height: barAreaHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final maxIndex = tickValues.length - 1;
                            return Stack(
                              children: List.generate(tickValues.length, (
                                index,
                              ) {
                                final fraction = maxIndex <= 0
                                    ? 0.0
                                    : index / maxIndex;
                                final x = (constraints.maxWidth - 1) * fraction;
                                return Positioned(
                                  left: x,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 1,
                                    color: Colors.black.withValues(alpha: 0.12),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ),
                      Column(
                        children: [
                          ...displayRows.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final e = entry.value;
                            final isPlaceholder = e.key.isEmpty;
                            final ratio = axisMax == 0
                                ? 0.0
                                : e.value / axisMax;
                            final displayRatio = isNoData ? 0.28 : ratio;
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: idx == displayRows.length - 1
                                    ? 0
                                    : rowGap,
                              ),
                              child: SizedBox(
                                height: rowHeight,
                                child: InkWell(
                                  onTap: isNoData || isPlaceholder
                                      ? null
                                      : () => onTap(e.key),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          height: barHeight,
                                          color: Colors.black.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                        if (!isPlaceholder)
                                          TweenAnimationBuilder<double>(
                                            tween: Tween<double>(
                                              begin: 0,
                                              end: displayRatio.clamp(0.0, 1.0),
                                            ),
                                            duration: const Duration(
                                              milliseconds: 550,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            builder: (context, animatedRatio, _) {
                                              return FractionallySizedBox(
                                                widthFactor: animatedRatio,
                                                child: Container(
                                                  height: barHeight,
                                                  width: double.infinity,
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        isNoData
                                                            ? const Color(
                                                                0xFFB7BDB7,
                                                              )
                                                            : _previewGreen(
                                                                const Color(
                                                                  0xFF2E7D32,
                                                                ),
                                                              ),
                                                        isNoData
                                                            ? const Color(
                                                                0xFF9FA59F,
                                                              )
                                                            : _previewGreenDark(
                                                                const Color(
                                                                  0xFF1B5E20,
                                                                ),
                                                              ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: valueWidth,
                child: Column(
                  children: [
                    ...displayRows.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final e = entry.value;
                      final isPlaceholder = e.key.isEmpty;
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: idx == displayRows.length - 1 ? 0 : rowGap,
                        ),
                        child: SizedBox(
                          height: rowHeight,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              isPlaceholder
                                  ? ''
                                  : (isNoData ? '0' : '${e.value}'),
                              style: const TextStyle(
                                color: _hint,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0x1F000000)),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: labelWidth + labelGap),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxIndex = tickValues.length - 1;
                    return SizedBox(
                      height: 16,
                      child: Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: List.generate(tickValues.length, (index) {
                          final fraction = maxIndex <= 0
                              ? 0.0
                              : index / maxIndex;
                          final x = constraints.maxWidth * fraction;
                          Widget label = Text(
                            '${tickValues[index]}',
                            style: const TextStyle(
                              color: _hint,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                          if (index == 0) {
                            return Positioned(left: 0, child: label);
                          }
                          if (index == maxIndex) {
                            return Positioned(right: 0, child: label);
                          }
                          return Positioned(
                            left: x - 10,
                            child: SizedBox(
                              width: 20,
                              child: Center(child: label),
                            ),
                          );
                        }),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: valueWidth),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panelDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    final normalized = _normalizeSelected(value, options);
    return DropdownButtonFormField<String>(
      initialValue: normalized,
      isExpanded: true,
      menuMaxHeight: 360,
      decoration: _reportLikeDropdownDecoration(label: label),
      items: options
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  String _normalizeSelected(String value, List<String> options) {
    if (options.isEmpty) return value;
    if (options.contains(value)) return value;
    return options.first;
  }

  Widget _buildDateBoundField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final text = value == null
        ? 'Any'
        : DateFormat('MMM d, yyyy').format(value);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: _reportLikeDropdownDecoration(label: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value == null ? _hint : _textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.calendar_today_rounded, size: 16, color: _hint),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _showSingleFilterDatePicker({DateTime? initialDate}) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 6, 1, 1);
    final lastDate = DateTime(now.year + 2, 12, 31);
    final initial = initialDate == null
        ? now
        : (initialDate.isBefore(firstDate)
              ? firstDate
              : (initialDate.isAfter(lastDate) ? lastDate : initialDate));
    return showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: initial,
      helpText: 'Select Date',
    );
  }

  Widget _verticalBarChart(
    Map<String, int> data,
    ValueChanged<String> onTap, {
    int maxItems = 12,
    Color barColor = _primary,
  }) {
    final isNoData = data.isEmpty || data.values.every((v) => v == 0);
    final entries = isNoData
        ? const [MapEntry<String, int>('No data', 0)]
        : data.entries.take(maxItems).toList();
    final maxVal = entries.fold<int>(1, (p, e) => math.max(p, e.value));
    final axisMax = _niceAxisMax(maxVal);
    final ticks = _axisTicks(maxVal);
    const valueLabelHeight = 16.0;
    const valueGap = 6.0;
    const plotHeight = 150.0;
    const xLabelGap = 8.0;
    const xLabelHeight = 28.0;
    const chartTotalHeight =
        valueLabelHeight + valueGap + plotHeight + xLabelGap + xLabelHeight;
    const plotTop = valueLabelHeight + valueGap;
    const plotBottom = xLabelHeight + xLabelGap;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: SizedBox(
        height: chartTotalHeight,
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: SizedBox(
                height: chartTotalHeight,
                child: Column(
                  children: [
                    const SizedBox(height: plotTop),
                    SizedBox(
                      height: plotHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: ticks
                            .map(
                              (tick) => Text(
                                '$tick',
                                style: const TextStyle(
                                  color: _hint,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: plotBottom),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: plotTop,
                    bottom: plotBottom,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        ticks.length,
                        (_) => Container(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                  ),
                  ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final ratio = isNoData
                          ? 0.28
                          : (e.value / axisMax).clamp(0.0, 1.0);
                      final displayValue = isNoData ? '0' : '${e.value}';
                      final displayLabel = isNoData ? 'No data' : e.key;
                      final displayBarColor = isNoData
                          ? const Color(0xFFB7BDB7)
                          : barColor;
                      const railHeight = plotHeight;
                      return InkWell(
                        onTap: isNoData ? null : () => onTap(e.key),
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 68,
                          child: Column(
                            children: [
                              SizedBox(
                                height: valueLabelHeight,
                                child: Center(
                                  child: Text(
                                    displayValue,
                                    style: const TextStyle(
                                      color: _hint,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: valueGap),
                              SizedBox(
                                height: railHeight,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: 34,
                                    height: railHeight,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween<double>(
                                          begin: 0,
                                          end: ratio,
                                        ),
                                        duration: const Duration(
                                          milliseconds: 600,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, animatedRatio, _) {
                                          return Container(
                                            width: 34,
                                            height: railHeight * animatedRatio,
                                            decoration: BoxDecoration(
                                              color: displayBarColor,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: displayBarColor
                                                      .withValues(alpha: 0.25),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: xLabelGap),
                              SizedBox(
                                height: xLabelHeight,
                                child: Center(
                                  child: Text(
                                    displayLabel,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _textDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthlySeverityTrendChart(
    Map<String, _MonthSeverityPoint> data,
    ValueChanged<String> onTap,
  ) {
    final isNoData = data.isEmpty || data.values.every((v) => v.total == 0);
    final entries = isNoData
        ? const [
            MapEntry<String, _MonthSeverityPoint>(
              'No data',
              _MonthSeverityPoint(basic: 0, serious: 0),
            ),
          ]
        : data.entries.toList();
    final maxVal = entries.fold<int>(1, (p, e) => math.max(p, e.value.total));
    final axisMax = _niceAxisMax(maxVal);
    final ticks = _axisTicks(maxVal);
    const valueLabelHeight = 16.0;
    const valueGap = 6.0;
    const plotHeight = 152.0;
    const xLabelGap = 8.0;
    const xLabelHeight = 28.0;
    const chartTotalHeight =
        valueLabelHeight + valueGap + plotHeight + xLabelGap + xLabelHeight;
    const plotTop = valueLabelHeight + valueGap;
    const plotBottom = xLabelHeight + xLabelGap;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: SizedBox(
        height: chartTotalHeight,
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: SizedBox(
                height: chartTotalHeight,
                child: Column(
                  children: [
                    const SizedBox(height: plotTop),
                    SizedBox(
                      height: plotHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: ticks
                            .map(
                              (tick) => Text(
                                '$tick',
                                style: const TextStyle(
                                  color: _hint,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: plotBottom),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: plotTop,
                    bottom: plotBottom,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        ticks.length,
                        (_) => Container(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                  ),
                  ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final totalRatio = isNoData
                          ? 0.28
                          : (e.value.total / axisMax).clamp(0.0, 1.0);
                      final basicShare = e.value.total == 0
                          ? 0.0
                          : e.value.basic / e.value.total;
                      final seriousShare = e.value.total == 0
                          ? 0.0
                          : e.value.serious / e.value.total;
                      final displayTotal = isNoData ? '0' : '${e.value.total}';
                      final displayLabel = isNoData ? 'No data' : e.key;
                      final mutedGray = const Color(0xFFB7BDB7);
                      const railHeight = plotHeight;
                      return InkWell(
                        onTap: isNoData ? null : () => onTap(e.key),
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 72,
                          child: Column(
                            children: [
                              SizedBox(
                                height: valueLabelHeight,
                                child: Center(
                                  child: Text(
                                    displayTotal,
                                    style: const TextStyle(
                                      color: _hint,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: valueGap),
                              SizedBox(
                                height: railHeight,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: 36,
                                    height: railHeight,
                                    color: Colors.black.withValues(alpha: 0.12),
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween<double>(
                                          begin: 0,
                                          end: totalRatio,
                                        ),
                                        duration: const Duration(
                                          milliseconds: 600,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, animatedRatio, _) {
                                          return SizedBox(
                                            width: 36,
                                            height: railHeight * animatedRatio,
                                            child: Column(
                                              children: [
                                                Expanded(
                                                  flex: isNoData
                                                      ? 1
                                                      : (seriousShare * 1000)
                                                            .round()
                                                            .clamp(1, 1000),
                                                  child: Container(
                                                    color: isNoData
                                                        ? mutedGray
                                                        : const Color(
                                                            0xFFEF6C00,
                                                          ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: isNoData
                                                      ? 1
                                                      : (basicShare * 1000)
                                                            .round()
                                                            .clamp(1, 1000),
                                                  child: Container(
                                                    color: isNoData
                                                        ? mutedGray
                                                        : _previewGreen(
                                                            const Color(
                                                              0xFF2E7D32,
                                                            ),
                                                          ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: xLabelGap),
                              SizedBox(
                                height: xLabelHeight,
                                child: Center(
                                  child: Text(
                                    displayLabel,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _textDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _concernDonut({
    required int basic,
    required int serious,
    required VoidCallback onTapBasic,
    required VoidCallback onTapSerious,
  }) {
    final total = basic + serious;
    final isNoData = total == 0;
    final basicRatio = isNoData ? 0.0 : basic / total;
    final seriousRatio = isNoData ? 0.0 : serious / total;
    int hoveredSegment = -1; // -1 none, 0 basic, 1 serious

    int detectHoveredSegment(Offset localPosition, double size) {
      if (isNoData) return -1;
      final center = Offset(size / 2, size / 2);
      final dx = localPosition.dx - center.dx;
      final dy = localPosition.dy - center.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      final stroke = size * 0.14;
      final outerRadius = size / 2;
      final innerRadius = outerRadius - stroke;
      if (dist < innerRadius - 6 || dist > outerRadius + 6) return -1;

      final start = -math.pi / 2;
      var angle = math.atan2(dy, dx);
      var normalized = angle - start;
      final full = math.pi * 2;
      while (normalized < 0) {
        normalized += full;
      }
      while (normalized >= full) {
        normalized -= full;
      }

      final basicSweep = (basicRatio.clamp(0.0, 1.0)) * full;
      final seriousSweep = (seriousRatio.clamp(0.0, 1.0)) * full;

      if (basicSweep > 0 && normalized <= basicSweep) return 0;
      if (seriousSweep > 0 && normalized <= basicSweep + seriousSweep) return 1;
      return -1;
    }

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final showBasic = hoveredSegment == 0;
        final showSerious = hoveredSegment == 1;
        final basicPercent = isNoData ? 0 : ((basic / total) * 100).round();
        final seriousPercent = isNoData ? 0 : ((serious / total) * 100).round();
        final neutral = const Color(0xFFB7BDB7);

        return Column(
          children: [
            SizedBox(
              height: 174,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onHover: (event) {
                      final next = detectHoveredSegment(
                        event.localPosition,
                        150,
                      );
                      if (next != hoveredSegment) {
                        setLocalState(() => hoveredSegment = next);
                      }
                    },
                    onExit: (_) {
                      if (hoveredSegment != -1) {
                        setLocalState(() => hoveredSegment = -1);
                      }
                    },
                    child: GestureDetector(
                      onTapDown: (details) {
                        final hit = detectHoveredSegment(
                          details.localPosition,
                          150,
                        );
                        if (hit == 0) onTapBasic();
                        if (hit == 1) onTapSerious();
                      },
                      child: CustomPaint(
                        size: const Size(150, 150),
                        painter: _DonutSplitPainter(
                          basicRatio: basicRatio,
                          seriousRatio: seriousRatio,
                          muted: _previewMutedCharts,
                        ),
                      ),
                    ),
                  ),
                  if (showBasic || showSerious)
                    Positioned(
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.14),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isNoData
                                    ? neutral
                                    : (showBasic
                                          ? _previewGreen(
                                              const Color(0xFF2E7D32),
                                            )
                                          : const Color(0xFFEF6C00)),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isNoData
                                  ? 'No data'
                                  : (showBasic
                                        ? 'Basic $basicPercent%'
                                        : 'Serious $seriousPercent%'),
                              style: TextStyle(
                                color: isNoData
                                    ? neutral
                                    : (showBasic
                                          ? _previewGreen(
                                              const Color(0xFF2E7D32),
                                            )
                                          : const Color(0xFFEF6C00)),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isNoData ? '0' : '$total',
                        style: const TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                        ),
                      ),
                      Text(
                        isNoData ? 'No data' : 'Total',
                        style: TextStyle(
                          color: _hint,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendPill(
                  label: 'Basic',
                  count: basic,
                  color: isNoData
                      ? neutral
                      : _previewGreen(const Color(0xFF2E7D32)),
                  onTap: onTapBasic,
                ),
                const SizedBox(width: 14),
                _legendPill(
                  label: 'Serious',
                  count: serious,
                  color: isNoData ? neutral : const Color(0xFFEF6C00),
                  onTap: onTapSerious,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _legendPill({
    required String label,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '$label ($count)',
              style: const TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stackedDepartmentBars(List<_DeptRow> rows) {
    final isNoData = rows.isEmpty || rows.every((r) => r.total == 0);
    final top = isNoData
        ? const [_DeptRow('No data', 0, 0, 0)]
        : rows.take(10).toList();
    final maxTotal = top.fold<int>(1, (p, r) => math.max(p, r.total));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F9F7), Color(0xFFEFF3EF)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: top.map((r) {
          final totalRatio = isNoData
              ? 0.26
              : (r.total / maxTotal).clamp(0.0, 1.0);
          final basicShare = r.total == 0 ? 0.0 : r.basic / r.total;
          final seriousShare = r.total == 0 ? 0.0 : r.serious / r.total;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.department,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      isNoData ? '0' : '${r.total}',
                      style: const TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 10,
                        color: const Color(0xFFDDE3DD),
                      ),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: totalRatio),
                        duration: const Duration(milliseconds: 550),
                        curve: Curves.easeOutCubic,
                        builder: (context, animatedRatio, _) {
                          return FractionallySizedBox(
                            widthFactor: animatedRatio,
                            child: SizedBox(
                              height: 10,
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: isNoData
                                        ? 1
                                        : (basicShare * 1000).round().clamp(
                                            1,
                                            1000,
                                          ),
                                    child: Container(
                                      color: isNoData
                                          ? const Color(0xFFB7BDB7)
                                          : _previewGreen(
                                              const Color(0xFF2E7D32),
                                            ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: isNoData
                                        ? 1
                                        : (seriousShare * 1000).round().clamp(
                                            1,
                                            1000,
                                          ),
                                    child: Container(
                                      color: isNoData
                                          ? const Color(0xFFB7BDB7)
                                          : const Color(0xFFEF6C00),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _studentHistogram(List<_StudentCount> students) {
    final buckets = <String, int>{'1': 0, '2': 0, '3': 0, '4+': 0};
    for (final s in students) {
      if (s.count >= 4) {
        buckets['4+'] = (buckets['4+'] ?? 0) + 1;
      } else {
        final key = '${s.count}';
        buckets[key] = (buckets[key] ?? 0) + 1;
      }
    }
    return _verticalBarChart(
      buckets,
      (_) {},
      maxItems: 4,
      barColor: _previewGreen(const Color(0xFF558B2F)),
    );
  }

  Widget _table(
    List<String> headers,
    List<List<String>> rows, {
    required ValueChanged<List<String>> onRowTap,
  }) {
    final displayRows = rows.isEmpty
        ? [
            ['No data', for (var i = 1; i < headers.length; i++) '0'],
          ]
        : rows;
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
        rows: displayRows
            .map(
              (r) => DataRow(
                onSelectChanged: rows.isEmpty ? null : (_) => onRowTap(r),
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

  bool _matches(_Case c) {
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
      searchQuery: preset.searchQuery,
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

  Widget _chartEmptyState({
    required double height,
    required String message,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No data available',
            style: TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: const TextStyle(
              color: _hint,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: math.max(64, height - 92),
            child: Center(child: child),
          ),
        ],
      ),
    );
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

class _ActiveAnalyticsFilterChipData {
  final String label;
  final VoidCallback onRemove;
  const _ActiveAnalyticsFilterChipData({
    required this.label,
    required this.onRemove,
  });
}

class _HoverDismissFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _HoverDismissFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onRemove,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F8F3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF1F2A1F),
                fontWeight: FontWeight.w700,
                fontSize: 12.2,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: const Color(0xFF1B5E20).withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      ),
    );
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
    DateTime? incidentDate() {
      for (final c in [
        m['incidentAt'],
        m['incidentDate'],
        m['dateOfIncident'],
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
      incidentDate(),
    );
  }
}

class _SkeletonVBar extends StatelessWidget {
  final double height;
  const _SkeletonVBar({required this.height});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonHBar extends StatelessWidget {
  final double widthFactor;
  const _SkeletonHBar({required this.widthFactor});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 12,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

class _SkeletonTableRow extends StatelessWidget {
  const _SkeletonTableRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Container(
            height: 11,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Container(
            height: 11,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Container(
            height: 11,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ],
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

class _MonthSeverityPoint {
  final int basic;
  final int serious;
  const _MonthSeverityPoint({required this.basic, required this.serious});

  int get total => basic + serious;
}

class _Metrics {
  final int total, basic, serious, repeatOffenders;
  final Map<String, int> monthCounts,
      categoryCounts,
      departmentCounts,
      violationCounts;
  final Map<String, _MonthSeverityPoint> monthSeverityTrend;
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
    this.monthSeverityTrend,
    this.students,
    this.departmentRows,
    this.departmentTrends,
  );

  factory _Metrics.from(List<_Case> cases) {
    final month = <String, int>{},
        cat = <String, int>{},
        dept = <String, int>{},
        vio = <String, int>{};
    final monthSeverity = <String, _MonthSeverityPoint>{};
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
      final currentSeverity =
          monthSeverity[m] ?? const _MonthSeverityPoint(basic: 0, serious: 0);
      monthSeverity[m] = _MonthSeverityPoint(
        basic:
            currentSeverity.basic +
            (c.concern.toLowerCase() == 'basic' ? 1 : 0),
        serious:
            currentSeverity.serious +
            (c.concern.toLowerCase() == 'serious' ? 1 : 0),
      );
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

    int monthOrder(String label) {
      if (label == 'Unknown') return -1;
      try {
        final d = DateFormat('MMM yyyy').parseStrict(label);
        return d.year * 100 + d.month;
      } catch (_) {
        return -1;
      }
    }

    Map<String, int> sortMonthsChronological(Map<String, int> m) {
      final e = m.entries.toList()
        ..sort((a, b) {
          final ao = monthOrder(a.key);
          final bo = monthOrder(b.key);
          if (ao < 0 && bo < 0) return a.key.compareTo(b.key);
          if (ao < 0) return 1;
          if (bo < 0) return -1;
          return ao.compareTo(bo);
        });
      return {for (final x in e) x.key: x.value};
    }

    Map<String, _MonthSeverityPoint> sortMonthSeverityChronological(
      Map<String, _MonthSeverityPoint> m,
    ) {
      final e = m.entries.toList()
        ..sort((a, b) {
          final ao = monthOrder(a.key);
          final bo = monthOrder(b.key);
          if (ao < 0 && bo < 0) return a.key.compareTo(b.key);
          if (ao < 0) return 1;
          if (bo < 0) return -1;
          return ao.compareTo(bo);
        });
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
      sortMonthsChronological(month),
      sort(cat),
      sort(dept),
      sort(vio),
      sortMonthSeverityChronological(monthSeverity),
      students,
      dRows,
      trends,
    );
  }
}

class _DonutSplitPainter extends CustomPainter {
  final double basicRatio;
  final double seriousRatio;
  final bool muted;

  const _DonutSplitPainter({
    required this.basicRatio,
    required this.seriousRatio,
    this.muted = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final rect = Offset.zero & size;
    final start = -math.pi / 2;

    final basePaint = Paint()
      ..color = muted ? const Color(0xFFE0E3E0) : const Color(0xFFE8F2E8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false, basePaint);

    final basicSweep = (basicRatio.clamp(0.0, 1.0)) * math.pi * 2;
    final seriousSweep = (seriousRatio.clamp(0.0, 1.0)) * math.pi * 2;

    final basicPaint = Paint()
      ..color = muted ? const Color(0xFFB7BDB7) : const Color(0xFF2E7D32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final seriousPaint = Paint()
      ..color = const Color(0xFFEF6C00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    if (basicSweep > 0) {
      canvas.drawArc(
        rect.deflate(stroke / 2),
        start,
        basicSweep,
        false,
        basicPaint,
      );
    }
    if (seriousSweep > 0) {
      canvas.drawArc(
        rect.deflate(stroke / 2),
        start + basicSweep,
        seriousSweep,
        false,
        seriousPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DonutSplitPainter oldDelegate) {
    return oldDelegate.basicRatio != basicRatio ||
        oldDelegate.seriousRatio != seriousRatio;
  }
}

class _DonutSlice {
  final String label;
  final int value;
  final Color color;
  const _DonutSlice(this.label, this.value, this.color);
}

class _DonutDistributionPainter extends CustomPainter {
  final List<_DonutSlice> slices;
  const _DonutDistributionPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (sum, s) => sum + s.value);
    if (total <= 0) return;
    final stroke = size.width * 0.17;
    final rect = Offset.zero & size;
    var start = -math.pi / 2;

    for (final s in slices) {
      final sweep = (s.value / total) * math.pi * 2;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect.deflate(stroke / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutDistributionPainter oldDelegate) {
    if (oldDelegate.slices.length != slices.length) return true;
    for (var i = 0; i < slices.length; i++) {
      if (oldDelegate.slices[i].label != slices[i].label ||
          oldDelegate.slices[i].value != slices[i].value ||
          oldDelegate.slices[i].color != slices[i].color) {
        return true;
      }
    }
    return false;
  }
}

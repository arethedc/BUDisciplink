import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:intl/intl.dart';

import '../shared/widgets/modern_table_layout.dart';
import '../shared/widgets/app_layout_tokens.dart';
import '../../services/osa_meeting_schedule_service.dart';
import '../../services/violation_case_service.dart';
import '../../services/violation_types_service.dart';
import 'osa_violation_ai_assistant_sheet.dart';

// âœ… YOUR COLORS (applied everywhere)
const bg = Color(0xFFF6FAF6);
const primaryColor = Color(0xFF1B5E20);

const textDark = Color(0xFF1F2A1F);
const hintColor = Color(0xFF6D7F62);

/// âœ… Enhanced OSA Review Inbox
enum _CaseTab { review, needsBooking, scheduled, unresolved, resolved }

class _CaseTabConfig {
  final _CaseTab tab;
  final String label;
  final bool showMeetingColumn;
  final bool showSeverityColumn;

  const _CaseTabConfig({
    required this.tab,
    required this.label,
    this.showMeetingColumn = false,
    this.showSeverityColumn = false,
  });
}

class OsaViolationReviewPage extends StatefulWidget {
  const OsaViolationReviewPage({super.key});

  @override
  State<OsaViolationReviewPage> createState() => _OsaViolationReviewPageState();
}

class _OsaViolationReviewPageState extends State<OsaViolationReviewPage> {
  static const List<_CaseTabConfig> _tabConfigs = [
    _CaseTabConfig(tab: _CaseTab.review, label: 'Review Inbox'),
    _CaseTabConfig(
      tab: _CaseTab.needsBooking,
      label: 'Needs Booking',
      showMeetingColumn: true,
    ),
    _CaseTabConfig(
      tab: _CaseTab.scheduled,
      label: 'Scheduled',
      showMeetingColumn: true,
    ),
    _CaseTabConfig(tab: _CaseTab.unresolved, label: 'Unresolved'),
    _CaseTabConfig(
      tab: _CaseTab.resolved,
      label: 'Resolved',
      showSeverityColumn: true,
    ),
  ];

  final _svc = ViolationCaseService();
  final _meetingScheduleSvc = OsaMeetingScheduleService();

  // UI state
  final _searchCtrl = TextEditingController();
  _CaseTab _tab = _CaseTab.review;

  String _concernFilter = 'All';
  String _actionFilter = 'All';
  String _meetingFilter = 'All';
  String _dateFilter = 'All';

  String? _selectedCaseId;
  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _visibleCaseDocs =
      ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        const [],
      );
  final ValueNotifier<Map<_CaseTab, int>> _tabCounts =
      ValueNotifier<Map<_CaseTab, int>>({
        _CaseTab.review: 0,
        _CaseTab.needsBooking: 0,
        _CaseTab.scheduled: 0,
        _CaseTab.unresolved: 0,
        _CaseTab.resolved: 0,
      });

  bool _bookingSweepRunning = false;
  String? _departmentScopeCollegeId;
  Set<String>? _departmentStudentUids;
  bool _loadingDepartmentScope = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _deptStudentsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tabCountsSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestRawCaseDocs =
      const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

  @override
  void initState() {
    super.initState();
    _runBookingExpirySweep();
    _initDepartmentScope();
    _bindTabCountsStream();
  }

  Future<void> _initDepartmentScope() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get();
      final data = doc.data() ?? <String, dynamic>{};
      final role = (data['role'] ?? '').toString().trim().toLowerCase();
      if (role != 'department_admin' && role != 'dean') return;

      final dept = (data['employeeProfile']?['department'] ?? '')
          .toString()
          .trim();
      if (dept.isEmpty) {
        if (!mounted) return;
        setState(() {
          _departmentScopeCollegeId = '';
          _departmentStudentUids = <String>{};
          _loadingDepartmentScope = false;
        });
        _recomputeTabCounts();
        return;
      }

      if (!mounted) return;
      setState(() {
        _departmentScopeCollegeId = dept;
        _loadingDepartmentScope = true;
      });
      _recomputeTabCounts();

      await _deptStudentsSub?.cancel();
      _deptStudentsSub = FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'student')
          .snapshots()
          .listen(
            (snap) {
              if (!mounted) return;
              final ids = snap.docs
                  .where((d) {
                    final college =
                        (d.data()['studentProfile']?['collegeId'] ?? '')
                            .toString()
                            .trim();
                    return college == dept;
                  })
                  .map((d) => d.id)
                  .toSet();
              setState(() {
                _departmentStudentUids = ids;
                _loadingDepartmentScope = false;
              });
              _recomputeTabCounts();
            },
            onError: (_) {
              if (!mounted) return;
              setState(() {
                _departmentStudentUids = <String>{};
                _loadingDepartmentScope = false;
              });
              _recomputeTabCounts();
            },
          );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _departmentScopeCollegeId = null;
        _departmentStudentUids = null;
        _loadingDepartmentScope = false;
      });
      _recomputeTabCounts();
    }
  }

  Future<void> _runBookingExpirySweep() async {
    if (_bookingSweepRunning) return;
    _bookingSweepRunning = true;
    try {
      await _meetingScheduleSvc.expireOverduePendingBookings();
    } catch (_) {
    } finally {
      _bookingSweepRunning = false;
    }
  }

  void _bindTabCountsStream() {
    _tabCountsSub?.cancel();
    _tabCountsSub = _svc.streamAllCases().listen((snapshot) {
      _latestRawCaseDocs = snapshot.docs;
      _recomputeTabCounts();
    });
  }

  void _recomputeTabCounts() {
    final allowedStudentUids = _departmentScopeCollegeId == null
        ? null
        : (_departmentStudentUids ?? <String>{});
    final next = <_CaseTab, int>{
      _CaseTab.review: 0,
      _CaseTab.needsBooking: 0,
      _CaseTab.scheduled: 0,
      _CaseTab.unresolved: 0,
      _CaseTab.resolved: 0,
    };

    for (final doc in _latestRawCaseDocs) {
      final d = doc.data();
      if (allowedStudentUids != null) {
        final studentUid = _safeStr(d['studentUid']);
        if (studentUid.isEmpty || !allowedStudentUids.contains(studentUid)) {
          continue;
        }
      }
      for (final config in _tabConfigs) {
        if (_matchesTabFor(d, config.tab)) {
          next[config.tab] = (next[config.tab] ?? 0) + 1;
        }
      }
    }
    _tabCounts.value = next;
  }

  @override
  void dispose() {
    _tabCountsSub?.cancel();
    _deptStudentsSub?.cancel();
    _tabCounts.dispose();
    _searchCtrl.dispose();
    _visibleCaseDocs.dispose();
    super.dispose();
  }

  // -----------------------------
  // Firestore date helpers
  // -----------------------------
  DateTime? _tsToDate(dynamic ts) {
    try {
      if (ts == null) return null;
      return (ts as Timestamp).toDate();
    } catch (_) {
      return null;
    }
  }

  DateTime? _bestDate(Map<String, dynamic> d) =>
      _tsToDate(d['createdAt']) ?? _tsToDate(d['incidentAt']);

  String _fmtShort(DateTime d) {
    return _TableRow._fmtShortGlobal(d);
  }

  _CaseTabConfig get _activeTabConfig {
    for (final config in _tabConfigs) {
      if (config.tab == _tab) return config;
    }
    return _tabConfigs.first;
  }

  int get _activeTabIndex {
    final index = _tabConfigs.indexWhere((config) => config.tab == _tab);
    return index < 0 ? 0 : index;
  }

  // -----------------------------
  // Filters
  // -----------------------------
  bool _matchesSearch(Map<String, dynamic> d, String q) {
    if (q.isEmpty) return true;
    final needle = q.toLowerCase().trim();

    final studentName = _safeStr(d['studentName']).toLowerCase();
    final studentNo = _safeStr(d['studentNo']).toLowerCase();
    final caseCode = _safeStr(d['caseCode']).toLowerCase();
    final violation = _safeStr(
      d['violationTypeLabel'] ??
          d['violationNameSnapshot'] ??
          d['violationName'],
    ).toLowerCase();
    final category = _categoryLabelFromCaseGlobal(d).toLowerCase();
    final reporter = _safeStr(d['reportedByName']).toLowerCase();

    return studentName.contains(needle) ||
        studentNo.contains(needle) ||
        caseCode.contains(needle) ||
        violation.contains(needle) ||
        category.contains(needle) ||
        reporter.contains(needle);
  }

  bool _matchesTabFor(Map<String, dynamic> d, _CaseTab tab) {
    final key = _statusKey(_safeStr(d['status']));
    if (tab == _CaseTab.review) {
      return key == 'submitted' || key == 'under review';
    }
    if (tab == _CaseTab.needsBooking || tab == _CaseTab.scheduled) {
      if (key != 'action set') return false;
      if (!_meetingRequired(d)) return false;
      final flow = _effectiveMeetingStatusKey(d);
      if (tab == _CaseTab.needsBooking) return flow == 'needs_booking';
      return flow == 'scheduled';
    }
    if (tab == _CaseTab.unresolved) {
      return key == 'unresolved';
    }
    return key == 'resolved';
  }

  bool _matchesTab(Map<String, dynamic> d) => _matchesTabFor(d, _tab);

  bool _matchesConcern(Map<String, dynamic> d) {
    if (_concernFilter == 'All') return true;
    final raw = _safeStr(
      d['concern'] ?? d['concernType'] ?? d['reportedConcernType'],
    ).toLowerCase().trim();
    final want = _concernFilter.toLowerCase();
    return raw == want;
  }

  bool _matchesAction(Map<String, dynamic> d) {
    if (_actionFilter == 'All') return true;
    final key = _actionKey(d);
    return key == _actionFilter.toLowerCase();
  }

  bool _matchesMeeting(Map<String, dynamic> d) {
    if (_meetingFilter == 'All') return true;
    if (_meetingFilter == 'Required') return _meetingRequired(d);
    if (_meetingFilter == 'Not Required' || _meetingFilter == 'No Meeting') {
      return !_meetingRequired(d);
    }

    final flow = _effectiveMeetingStatusKey(d);
    switch (_meetingFilter) {
      case 'Needs Booking':
        return flow == 'needs_booking';
      case 'Scheduled':
        return flow == 'scheduled';
      case 'Completed':
      case 'Done':
        return flow == 'completed';
      case 'Missed Booking':
        return flow == 'booking_missed';
      case 'Missed Meeting':
        return flow == 'meeting_missed';
      case 'Missed':
        return flow == 'booking_missed' || flow == 'meeting_missed';
      default:
        return flow == _meetingFilter.toLowerCase().replaceAll(' ', '_');
    }
  }

  String _effectiveMeetingStatusKey(Map<String, dynamic> d) {
    return _meetingFlowKey(d);
  }

  bool _matchesDate(Map<String, dynamic> d, {String? dateFilterOverride}) {
    final dateFilter = dateFilterOverride ?? _dateFilter;
    if (dateFilter == 'All') return true;
    final dt = _bestDate(d);
    if (dt == null) return false;

    final now = DateTime.now();
    final today = _dayOnly(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = _dayOnly(dt);

    if (dateFilter == 'Today') return day == today;
    if (dateFilter == 'Yesterday') return day == yesterday;

    if (dateFilter == 'This Week') {
      final weekday = today.weekday; // 1..7
      final weekStart = today.subtract(Duration(days: weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 7));
      return !day.isBefore(weekStart) && day.isBefore(weekEnd);
    }

    if (dateFilter == 'This Month') {
      return dt.year == now.year && dt.month == now.month;
    }

    return _dateBucketLabel(day) == dateFilter;
  }

  DateTime _dayOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  String _dateBucketLabel(DateTime day) {
    final now = DateTime.now();
    final today = _dayOnly(now);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    if (day.year == now.year) {
      return DateFormat('MMMM d').format(day);
    }
    return DateFormat('MMMM d, yyyy').format(day);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> raw,
    String q, {
    bool includeDateFilter = true,
    String? dateFilterOverride,
    Set<String>? allowedStudentUids,
  }) {
    final docs = raw.where((doc) {
      final d = doc.data();
      if (allowedStudentUids != null) {
        final studentUid = _safeStr(d['studentUid']);
        if (studentUid.isEmpty || !allowedStudentUids.contains(studentUid)) {
          return false;
        }
      }
      if (!_matchesTab(d)) return false;
      if (!_matchesSearch(d, q)) return false;
      if (_tab == _CaseTab.review && !_matchesConcern(d)) {
        return false;
      }
      if (_tab == _CaseTab.unresolved || _tab == _CaseTab.resolved) {
        if (!_matchesAction(d) || !_matchesMeeting(d)) return false;
      }
      if (includeDateFilter &&
          !_matchesDate(d, dateFilterOverride: dateFilterOverride)) {
        return false;
      }
      return true;
    }).toList();

    docs.sort((a, b) {
      final da = _bestDate(a.data());
      final db = _bestDate(b.data());
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    return docs;
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _concernFilter = 'All';
    _actionFilter = 'All';
    _meetingFilter = 'All';
    _dateFilter = 'All';
  }

  bool _hasActiveFilters() {
    return _searchCtrl.text.trim().isNotEmpty ||
        _concernFilter != 'All' ||
        _actionFilter != 'All' ||
        _meetingFilter != 'All';
  }

  // -----------------------------
  // UI
  // -----------------------------
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool desktopWide = constraints.maxWidth >= 1100;
        final detailsPaneWidth = (constraints.maxWidth * 0.33)
            .clamp(320.0, 420.0)
            .toDouble();
        final aiDesktopInset = desktopWide && _selectedCaseId != null
            ? detailsPaneWidth + 16
            : 0.0;

        return Scaffold(
          backgroundColor: bg,
          floatingActionButton: Padding(
            padding: EdgeInsets.only(right: aiDesktopInset),
            child: FloatingActionButton(
              heroTag: 'osa_violation_ai_fab',
              onPressed: () => showOsaViolationAiAssistantSheet(context),
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              tooltip: 'Open OSA AI',
              child: const Icon(Icons.analytics_rounded),
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          body: ModernTableLayout(
            detailsWidth: detailsPaneWidth,
            detailsIncludeHeader: true,
            header: ModernTableHeader(
              title: 'Violation Reviews',
              subtitle: 'Monitor and review student conduct',
              searchBar: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search cases...',
                  prefixIcon: const Icon(Icons.search, color: primaryColor),
                  filled: true,
                  fillColor: bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              tabs: DefaultTabController(
                length: _tabConfigs.length,
                initialIndex: _activeTabIndex,
                child: Builder(
                  builder: (context) {
                    return ValueListenableBuilder<Map<_CaseTab, int>>(
                      valueListenable: _tabCounts,
                      builder: (context, counts, _) {
                        return TabBar(
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          labelColor: primaryColor,
                          indicatorColor: primaryColor,
                          dividerColor: Colors.transparent,
                          onTap: (index) {
                            final newTab = _tabConfigs[index].tab;
                            if (newTab != _tab) {
                              setState(() {
                                _tab = newTab;
                                _selectedCaseId = null;
                                _concernFilter = 'All';
                                _actionFilter = 'All';
                                _meetingFilter = 'All';
                              });
                            }
                          },
                          tabs: _tabConfigs
                              .map(
                                (config) => Tab(
                                  text:
                                      '${config.label} (${counts[config.tab] ?? 0})',
                                ),
                              )
                              .toList(),
                        );
                      },
                    );
                  },
                ),
              ),
              filters: [
                if (_hasActiveFilters()) ...[
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => setState(() => _clearFilters()),
                    icon: const Icon(Icons.filter_list_off, size: 16),
                    label: const Text('Clear Filters'),
                  ),
                ],
              ],
            ),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _svc.streamAllCases(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_departmentScopeCollegeId != null &&
                    _loadingDepartmentScope) {
                  return const Center(child: CircularProgressIndicator());
                }

                final raw = snap.data!.docs;
                final q = _searchCtrl.text;
                final allowedStudentUids = _departmentScopeCollegeId == null
                    ? null
                    : (_departmentStudentUids ?? <String>{});
                final docs = _filterDocs(
                  raw,
                  q,
                  allowedStudentUids: allowedStudentUids,
                );
                _visibleCaseDocs.value = docs;

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No cases found',
                          style: TextStyle(
                            color: hintColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (constraints.maxWidth >= 900) {
                  return _buildDesktopTable(docs, config: _activeTabConfig);
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final isSelected = _selectedCaseId == doc.id;
                    return _buildCaseCard(
                      doc.id,
                      doc.data(),
                      isSelected,
                      desktopWide,
                      () {
                        if (desktopWide) {
                          setState(() {
                            _selectedCaseId = isSelected ? null : doc.id;
                          });
                        } else {
                          _openDetailsPage(context, doc);
                        }
                      },
                      'All',
                    );
                  },
                );
              },
            ),
            showDetails: _selectedCaseId != null,
            details: _selectedCaseId != null
                ? ValueListenableBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>
                  >(
                    valueListenable: _visibleCaseDocs,
                    builder: (context, docs, _) {
                      QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
                      for (final doc in docs) {
                        if (doc.id == _selectedCaseId) {
                          selectedDoc = doc;
                          break;
                        }
                      }
                      if (selectedDoc == null) {
                        return const SizedBox();
                      }
                      return _DetailsPanel(
                        doc: selectedDoc,
                        bestDate: _bestDate,
                        onClose: () => setState(() => _selectedCaseId = null),
                      );
                    },
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildDesktopTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required _CaseTabConfig config,
  }) {
    final showMeetingColumn = config.showMeetingColumn;
    final showSeverityColumn = config.showSeverityColumn;
    final isNeedsBooking = config.tab == _CaseTab.needsBooking;
    final rowHeight = isNeedsBooking ? 60.0 : 56.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = constraints.maxWidth;
            final tableColumnSpacing = isNeedsBooking ? 28.0 : 20.0;
            final meetingWeight = config.tab == _CaseTab.scheduled ? 2.0 : 1.8;
            final totalWeight =
                1.15 +
                2.35 +
                1.55 +
                2.35 +
                1.20 +
                (showSeverityColumn ? 1.25 : 0.0) +
                (showMeetingColumn ? meetingWeight : 0.0);
            double colWidth(double weight, double minWidth) {
              final value = tableWidth * (weight / totalWeight);
              return value < minWidth ? minWidth : value;
            }

            final codeCellWidth = colWidth(1.15, 100);
            final studentCellWidth = colWidth(2.35, 210);
            final concernCellWidth = colWidth(1.55, 138);
            final violationCellWidth = colWidth(2.35, 220);
            final dateCellWidth = colWidth(1.20, 112);
            final severityCellWidth = showSeverityColumn
                ? colWidth(1.25, 120)
                : 0.0;
            final meetingCellWidth = showMeetingColumn
                ? colWidth(
                    meetingWeight,
                    config.tab == _CaseTab.scheduled ? 172 : 150,
                  )
                : 0.0;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(bg),
                  columnSpacing: tableColumnSpacing,
                  dataRowMinHeight: rowHeight,
                  dataRowMaxHeight: rowHeight,
                  columns: [
                    DataColumn(
                      label: SizedBox(
                        width: codeCellWidth,
                        child: const Text(
                          'CODE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: studentCellWidth,
                        child: const Text(
                          'STUDENT',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: concernCellWidth,
                        child: const Text(
                          'CONCERN',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: violationCellWidth,
                        child: const Text(
                          'VIOLATION',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: dateCellWidth,
                        child: const Text(
                          'DATE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    if (showSeverityColumn)
                      DataColumn(
                        label: SizedBox(
                          width: severityCellWidth,
                          child: const Text(
                            'SEVERITY',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: hintColor,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    if (showMeetingColumn)
                      DataColumn(
                        label: SizedBox(
                          width: meetingCellWidth,
                          child: Text(
                            _meetingColumnHeader(config),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: hintColor,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                  rows: List.generate(docs.length, (i) {
                    final doc = docs[i];
                    final d = doc.data();
                    final isSelected = _selectedCaseId == doc.id;

                    final code = _safeStr(d['caseCode']).isEmpty
                        ? doc.id.substring(0, 8)
                        : _safeStr(d['caseCode']);
                    final student = _safeStr(d['studentName']).isEmpty
                        ? '--'
                        : _safeStr(d['studentName']);
                    final studentNo = _safeStr(d['studentNo']).isEmpty
                        ? '--'
                        : _safeStr(d['studentNo']);
                    final violation = _safeStr(
                      d['violationTypeLabel'] ??
                          d['violationNameSnapshot'] ??
                          d['violationName'],
                    );
                    final date = _bestDate(d);
                    final concern = _safeStr(
                      d['concern'] ??
                          d['concernType'] ??
                          d['reportedConcernType'],
                    );
                    final severity = _safeStr(d['finalSeverity']);

                    return DataRow(
                      selected: isSelected,
                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (isSelected) {
                          return primaryColor.withValues(alpha: 0.08);
                        }
                        return null;
                      }),
                      onSelectChanged: (val) {
                        setState(() {
                          _selectedCaseId = isSelected ? null : doc.id;
                        });
                      },
                      cells: [
                        DataCell(
                          SizedBox(
                            width: codeCellWidth,
                            child: Text(
                              code,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: primaryColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: studentCellWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  student,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: textDark,
                                  ),
                                ),
                                if (studentNo != '--')
                                  Text(
                                    studentNo,
                                    style: const TextStyle(
                                      color: hintColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: concernCellWidth,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _buildConcernPill(concern),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: violationCellWidth,
                            child: Text(
                              violation,
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: dateCellWidth,
                            child: Text(
                              date != null ? _fmtShort(date) : '--',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: hintColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (showSeverityColumn)
                          DataCell(
                            SizedBox(
                              width: severityCellWidth,
                              child: severity.isEmpty
                                  ? const Text(
                                      '--',
                                      style: TextStyle(
                                        color: hintColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : Text(
                                      _titleCase(severity),
                                      style: const TextStyle(
                                        color: textDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        if (showMeetingColumn)
                          DataCell(
                            SizedBox(
                              width: meetingCellWidth,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _buildMeetingCell(d, config: config),
                              ),
                            ),
                          ),
                      ],
                    );
                  }),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildConcernPill(String concern) {
    final label = concern.isEmpty ? 'General' : _titleCase(concern);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: primaryColor,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _meetingColumnHeader(_CaseTabConfig config) {
    if (config.tab == _CaseTab.scheduled) return 'SCHEDULED AT';
    return 'MEETING STATUS';
  }

  Widget _buildMeetingCell(
    Map<String, dynamic> data, {
    required _CaseTabConfig config,
  }) {
    if (config.tab == _CaseTab.scheduled) {
      final scheduledAt = _tsToDate(data['scheduledAt']);
      if (scheduledAt == null) {
        return const Text(
          '--',
          style: TextStyle(color: hintColor, fontWeight: FontWeight.w700),
        );
      }
      return Text(
        _fmtMeetingDateTime(scheduledAt),
        style: const TextStyle(
          color: textDark,
          fontWeight: FontWeight.w700,
          fontSize: 12.2,
        ),
      );
    }
    return _Pill(
      text: _meetingStatusChipText(data),
      tone: _meetingStatusTone(data),
    );
  }

  _Tone _meetingStatusTone(Map<String, dynamic> data) {
    final status = _effectiveMeetingStatusKey(data);
    final isGraceWindow = _isGraceWindowGlobal(data);
    if (status == 'scheduled') {
      return _Tone(
        fill: Colors.blue.withValues(alpha: 0.10),
        border: Colors.blue.withValues(alpha: 0.30),
        text: Colors.blue.shade900,
      );
    }
    if (status == 'completed') {
      return _Tone(
        fill: primaryColor.withValues(alpha: 0.12),
        border: primaryColor.withValues(alpha: 0.35),
        text: primaryColor,
      );
    }
    if (status == 'booking_missed' || status == 'meeting_missed') {
      return _Tone(
        fill: Colors.red.withValues(alpha: 0.10),
        border: Colors.red.withValues(alpha: 0.30),
        text: Colors.red.shade900,
      );
    }
    if (status == 'needs_booking') {
      return _Tone(
        fill: isGraceWindow
            ? Colors.deepOrange.withValues(alpha: 0.10)
            : Colors.orange.withValues(alpha: 0.10),
        border: isGraceWindow
            ? Colors.deepOrange.withValues(alpha: 0.30)
            : Colors.orange.withValues(alpha: 0.30),
        text: isGraceWindow
            ? Colors.deepOrange.shade900
            : Colors.orange.shade900,
      );
    }
    return _Tone(
      fill: Colors.black.withValues(alpha: 0.04),
      border: Colors.black.withValues(alpha: 0.10),
      text: hintColor,
    );
  }

  String _meetingStatusChipText(Map<String, dynamic> data) {
    if (!_meetingRequired(data)) return 'No Meeting';

    final status = _effectiveMeetingStatusKey(data);
    if (status == 'scheduled') return 'Scheduled';
    if (status == 'completed') return 'Completed';
    if (status == 'booking_missed' || status == 'meeting_missed') {
      return 'Missed';
    }
    return _isGraceWindowGlobal(data) ? 'Grace Window' : 'Booking Window';
  }

  Widget _buildCaseCard(
    String id,
    Map<String, dynamic> data,
    bool isSelected,
    bool isDesktop,
    VoidCallback onTap,
    String dateFilter,
  ) {
    final caseCode = (data['caseCode'] ?? 'No Code').toString();
    final studentName = (data['studentName'] ?? 'Unknown').toString();
    final violation =
        (data['typeNameSnapshot'] ??
                data['violationNameSnapshot'] ??
                'Violation')
            .toString();
    final status = (data['status'] ?? 'Submitted').toString();
    final date = _bestDate(data);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : Colors.black.withValues(alpha: 0.05),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
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
                        caseCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    studentName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    violation,
                    style: const TextStyle(color: hintColor, fontSize: 13),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (date != null)
                  Text(
                    _TableRow._dynamicDateTextGlobal(date, dateFilter),
                    style: const TextStyle(fontSize: 12, color: hintColor),
                  ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey;
    final s = status.toLowerCase();
    if (s.contains('submitted')) {
      color = Colors.blue;
    } else if (s.contains('review')) {
      color = Colors.orange;
    } else if (s.contains('action')) {
      color = Colors.purple;
    } else if (s.contains('resolved')) {
      color = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _openDetailsPage(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: _DetailsPanel(
          doc: doc,
          bestDate: _bestDate,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

// ======================================================================
// HEADER WITH KPI STATS
// ======================================================================

// ======================================================================
// TOOLBAR (unchanged, just enhanced search hint)
// ======================================================================

// ======================================================================
// DESKTOP TABLE PANEL (enhanced with case codes + category pills)
// ======================================================================

class _TableRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;
  final DateTime? Function(Map<String, dynamic> d) bestDate;
  final String dateFilter;
  final VoidCallback onTap;

  const _TableRow({
    required this.doc,
    required this.selected,
    required this.bestDate,
    required this.dateFilter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data();

    final studentName = _safeStr(d['studentName']).isEmpty
        ? 'Unknown'
        : _safeStr(d['studentName']);
    final studentNo = _safeStr(d['studentNo']);
    final studentLabel = studentNo.isEmpty
        ? studentName
        : '$studentName ($studentNo)';

    final caseCode = _safeStr(d['caseCode']).isEmpty
        ? '---'
        : _safeStr(d['caseCode']);
    final violation = _safeStr(
      d['violationTypeLabel'] ??
          d['violationNameSnapshot'] ??
          d['violationName'],
    );
    final category = _categoryLabelFromCaseGlobal(d);

    final dt = bestDate(d);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 800;

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? primaryColor.withValues(alpha: 0.10)
                  : Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(
                color: selected
                    ? primaryColor.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              children: [
                if (!narrow)
                  Expanded(
                    flex: 15,
                    child: Text(
                      caseCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Expanded(
                  flex: 25,
                  child: Text(
                    studentLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 20,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _CategoryPill(
                      text: category,
                      concern: _safeStr(
                        d['concern'] ??
                            d['concernType'] ??
                            d['reportedConcernType'],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 25,
                  child: Text(
                    violation.isEmpty ? 'Unspecified violation' : violation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.6,
                    ),
                  ),
                ),
                Expanded(
                  flex: 15,
                  child: Text(
                    _dynamicDateTextGlobal(dt, dateFilter),
                    style: const TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _dynamicDateTextGlobal(DateTime? dt, String _) {
    if (dt == null) return '--';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(dt.year, dt.month, dt.day);

    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    if (day.year == today.year) return DateFormat('MMMM d').format(day);
    return DateFormat('MMMM d, yyyy').format(day);
  }

  static String _fmtShortGlobal(DateTime d) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${months[d.month - 1]} ${d.day}, ${d.year}";
  }
}

// ======================================================================
// MOBILE CARDS PANEL (optimized layout)
// ======================================================================

// ======================================================================
// MOBILE DETAILS PAGE (full-screen instead of modal)
// ======================================================================

class _DetailsPanel extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final DateTime? Function(Map<String, dynamic> d) bestDate;
  final VoidCallback? onClose;

  const _DetailsPanel({
    required this.doc,
    required this.bestDate,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final studentUid = _safeStr(d['studentUid']);

    final studentName = _safeStr(d['studentName']).isEmpty
        ? 'Unknown'
        : _safeStr(d['studentName']);
    final studentNo = _safeStr(d['studentNo']).isEmpty
        ? '--'
        : _safeStr(d['studentNo']);
    final studentProgramFuture = _resolveStudentProgramLabel(d, studentUid);
    final caseCode = _safeStr(d['caseCode']).isEmpty
        ? 'No Code'
        : _safeStr(d['caseCode']);
    final concern = _safeStr(
      d['concern'] ?? d['concernType'] ?? d['reportedConcernType'],
    );
    final violation = _safeStr(
      d['violationTypeLabel'] ??
          d['violationNameSnapshot'] ??
          d['violationName'],
    );
    final category = _categoryLabelFromCaseGlobal(d);

    final statusKey = _statusKey(_safeStr(d['status']));
    final isMonitor =
        statusKey == 'action set' ||
        statusKey == 'unresolved' ||
        statusKey == 'resolved';
    final hideSeverityForNeedsBooking = _isActionSetNeedsBooking(d);
    final meetingRequired = _meetingRequired(d);
    final effectiveMeetingStatus = _effectiveMeetingStatusKeyGlobal(d);
    final canCompleteMeeting =
        meetingRequired &&
        (statusKey == 'action set' || statusKey == 'unresolved') &&
        effectiveMeetingStatus != 'completed';
    final canRescheduleMeeting =
        meetingRequired &&
        (effectiveMeetingStatus == 'booking_missed' ||
            effectiveMeetingStatus == 'meeting_missed');
    final reschedulePrompt = effectiveMeetingStatus == 'booking_missed'
        ? 'Reopen booking window for this missed booking?'
        : 'Reopen booking window for this missed meeting attendance?';

    final dt = bestDate(d);
    final dateText = _formatReportedAtSmartGlobal(dt);

    final reportedBy = _reportedByDisplay(d);
    final reportedType = _safeStr(
      d['reportedTypeNameSnapshot'] ?? d['violationNameSnapshot'],
    );
    final reportedCategory = _safeStr(
      d['reportedCategoryNameSnapshot'] ?? d['categoryNameSnapshot'],
    );
    final wasCorrectedByOsa = d['wasCorrectedByOsa'] == true;
    final correctionReason = _safeStr(
      (d['correction'] as Map<String, dynamic>?)?['latestReason'],
    );
    final narrative = _safeStr(d['narrative'] ?? d['description']).isEmpty
        ? '--'
        : _safeStr(d['narrative'] ?? d['description']);

    final svc = ViolationCaseService();

    return Container(
      color: const Color(0xFFF9FBF9),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Case Details',
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _DetailCard(
                    title: 'Student Information',
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1B5E20,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            border: Border.all(
                              color: const Color(
                                0xFF1B5E20,
                              ).withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF1B5E20),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                studentName,
                                style: const TextStyle(
                                  color: textDark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Student No: $studentNo',
                                style: const TextStyle(
                                  color: hintColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              FutureBuilder<String>(
                                future: studentProgramFuture,
                                initialData: _studentProgramLabelFromCase(d),
                                builder: (context, snapshot) {
                                  final program =
                                      _safeStr(snapshot.data).isEmpty
                                      ? '--'
                                      : _safeStr(snapshot.data);
                                  return Text(
                                    'Program: $program',
                                    style: const TextStyle(
                                      color: hintColor,
                                      fontWeight: FontWeight.w700,
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
                  const SizedBox(height: 12),
                  _DetailCard(
                    title: 'Incident Summary',
                    child: Column(
                      children: [
                        _kv(
                          'Concern',
                          concern.isEmpty ? '--' : _titleCase(concern),
                        ),
                        const SizedBox(height: 8),
                        _kv('Category', category.isEmpty ? '--' : category),
                        const SizedBox(height: 8),
                        _kv(
                          'Violation Type',
                          violation.isEmpty ? '--' : violation,
                        ),
                        const SizedBox(height: 8),
                        _kv('Date Reported', dateText),
                        const SizedBox(height: 8),
                        _kv('Reported By', reportedBy),
                        const SizedBox(height: 8),
                        _kv('Case Code', caseCode),
                      ],
                    ),
                  ),
                  if (wasCorrectedByOsa) ...[
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: 'OSA Correction',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kv(
                            'Original',
                            '${reportedCategory.isEmpty ? '--' : reportedCategory} / ${reportedType.isEmpty ? '--' : reportedType}',
                          ),
                          const SizedBox(height: 8),
                          _kv(
                            'Current',
                            '${category.isEmpty ? '--' : category} / ${violation.isEmpty ? '--' : violation}',
                          ),
                          if (correctionReason.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _kv('Reason', correctionReason),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _DetailCard(
                    title: 'Incident Description',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        narrative,
                        style: const TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DetailCard(
                    title: 'Evidence',
                    child: _EvidencePlaceholders(urls: _evidenceUrls(d)),
                  ),
                  if (_safeStr(d['finalSeverity']).isNotEmpty &&
                      !hideSeverityForNeedsBooking) ...[
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: 'Assessment & Decision',
                      child: Column(
                        children: [
                          _kv(
                            'Severity',
                            _safeStr(d['finalSeverity']).isEmpty
                                ? '--'
                                : _titleCase(_safeStr(d['finalSeverity'])),
                          ),
                          const SizedBox(height: 8),
                          _kv(
                            'Sanction Given',
                            _safeStr(d['sanctionType']).isEmpty
                                ? '--'
                                : _titleCase(_safeStr(d['sanctionType'])),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (meetingRequired) ...[
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: 'Meeting Details',
                      child: _MeetingDetailsInfo(data: d, dense: true),
                    ),
                  ],

                  const SizedBox(height: 12),
                  _DetailCard(
                    title: 'Student Case History',
                    child: _StudentHistorySection(
                      studentUid: studentUid,
                      currentCaseId: doc.id,
                      currentViolationType: violation,
                    ),
                  ),
                  const SizedBox(height: 72),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
              border: Border(
                top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            child: !isMonitor
                ? Row(
                    children: [
                      Expanded(
                        child: _ActionBtn(
                          label: 'Set Action',
                          fill: primaryColor,
                          textColor: Colors.white,
                          borderColor: primaryColor,
                          onTap: () async {
                            final changed = await showDialog<bool>(
                              context: context,
                              builder: (c) => _AssignActionDialog(
                                doc: doc,
                                currentSeverity: _safeStr(
                                  d['finalSeverity'] ?? d['concern'],
                                ),
                                currentAction: _actionKey(d),
                                svc: svc,
                              ),
                            );
                            if (changed == true && onClose != null) {
                              // stream handles refresh
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionBtn(
                          label: 'Correct Report',
                          fill: Colors.white,
                          textColor: primaryColor,
                          borderColor: primaryColor.withValues(alpha: 0.30),
                          onTap: () async {
                            final changed = await showDialog<bool>(
                              context: context,
                              builder: (c) =>
                                  _CorrectViolationDialog(doc: doc, svc: svc),
                            );
                            if (changed == true && onClose != null) {
                              // stream handles refresh
                            }
                          },
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      if (canCompleteMeeting)
                        Expanded(
                          child: _ActionBtn(
                            label: 'Complete Meeting',
                            fill: primaryColor,
                            textColor: Colors.white,
                            borderColor: primaryColor,
                            onTap: () async {
                              final saved = await showDialog<bool>(
                                context: context,
                                builder: (c) => _CompleteMeetingDialog(
                                  caseId: doc.id,
                                  svc: svc,
                                ),
                              );
                              if (saved == true && onClose != null) {
                                // keep open; stream refreshes
                              }
                            },
                          ),
                        ),
                      if (canCompleteMeeting && canRescheduleMeeting)
                        const SizedBox(width: 10),
                      if (canRescheduleMeeting)
                        Expanded(
                          child: _ActionBtn(
                            label: 'Reschedule',
                            fill: Colors.white,
                            textColor: primaryColor,
                            borderColor: primaryColor.withValues(alpha: 0.35),
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Reschedule meeting?'),
                                  content: Text(reschedulePrompt),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Reschedule'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await svc.rescheduleMissedMeeting(
                                  caseId: doc.id,
                                );
                              }
                            },
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            '$k:',
            style: const TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _MeetingDetailsInfo extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool dense;

  const _MeetingDetailsInfo({required this.data, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final scheduledAt = _globalTsToDate(data['scheduledAt']);
    final meetingLocation = _safeStr(data['meetingLocation']);
    final meetingNotes = _safeStr(data['meetingNotes']);
    final facultyNote = _safeStr(data['meetingFacultyNote']);
    final completedAt = _globalTsToDate(data['meetingCompletedAt']);
    final history = _meetingHistoryEntries(data);
    final meetingType = _meetingTypeLabelForDisplay(data);
    final meetingStatus = _meetingStatusChipTextGlobal(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meetingType.isNotEmpty) ...[
          _meetingKv('Meeting Type', meetingType),
          const SizedBox(height: 8),
        ],
        if (meetingStatus.isNotEmpty) ...[
          _meetingKv('Meeting Status', meetingStatus),
          const SizedBox(height: 8),
        ],
        if (scheduledAt != null) ...[
          _meetingInfoCard('Scheduled At', _fmtMeetingDateTime(scheduledAt)),
        ],
        if (completedAt != null) ...[
          const SizedBox(height: 8),
          _meetingKv('Completed At', _fmtMeetingDateTime(completedAt)),
        ],
        if (meetingLocation.isNotEmpty) ...[
          const SizedBox(height: 8),
          _meetingKv('Location', meetingLocation),
        ],
        if (meetingNotes.isNotEmpty) ...[
          const SizedBox(height: 10),
          _meetingTextBlock('Meeting Notes', meetingNotes),
        ],
        if (facultyNote.isNotEmpty) ...[
          const SizedBox(height: 10),
          _meetingTextBlock('Faculty Note', facultyNote),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'Meeting History',
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          ...history.take(5).map((item) {
            final at = _globalTsToDate(item['recordedAt']);
            final status = _safeStr(item['previousMeetingStatus']);
            final reason = _safeStr(item['reason']);
            final prevSchedule = _globalTsToDate(item['previousScheduledAt']);
            final statusText = status.isEmpty
                ? 'Missed meeting'
                : _titleCase(status);
            final scheduleText = prevSchedule == null
                ? ''
                : ' (${_fmtMeetingDateTime(prevSchedule)})';
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$statusText$scheduleText',
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  if (at != null)
                    Text(
                      _fmtMeetingDateTime(at),
                      style: const TextStyle(
                        color: hintColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.3,
                      ),
                    ),
                  if (reason.isNotEmpty)
                    Text(
                      reason,
                      style: const TextStyle(
                        color: hintColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.3,
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _meetingInfoCard(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.event_note_rounded,
            size: dense ? 15 : 16,
            color: primaryColor.withValues(alpha: 0.88),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: hintColor,
                    fontWeight: FontWeight.w900,
                    fontSize: dense ? 11.6 : 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: dense ? 12.1 : 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meetingKv(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: dense ? 96 : 106,
          child: Text(
            '$label:',
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w900,
              fontSize: dense ? 11.6 : 12.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w700,
              fontSize: dense ? 12.1 : 12.8,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  Widget _meetingTextBlock(String title, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: hintColor,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w700,
              fontSize: dense ? 12 : 12.6,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _CorrectViolationDialog extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final ViolationCaseService svc;

  const _CorrectViolationDialog({required this.doc, required this.svc});

  @override
  State<_CorrectViolationDialog> createState() =>
      _CorrectViolationDialogState();
}

class _CorrectViolationDialogState extends State<_CorrectViolationDialog> {
  static const _concernOptions = ['basic', 'serious'];

  late final String _initialConcern;
  late String _concern;
  late final String _initialCategoryId;
  late final String _initialCategoryName;
  late final String _initialTypeId;
  late final String _initialTypeName;
  late final DateTime? _expectedUpdatedAt;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _categories = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _types = const [];
  String? _selectedCategoryId;
  String? _selectedTypeId;
  bool _loadingOptions = false;
  late final TextEditingController _reasonCtrl;
  bool _saving = false;
  bool _prefillCurrentOnNextLoad = true;

  String _normalizeConcernValue(String raw) {
    final value = raw.toLowerCase().trim();
    if (value.contains('serious') || value.contains('major')) {
      return 'serious';
    }
    if (value.contains('basic') ||
        value.contains('minor') ||
        value.contains('moderate')) {
      return 'basic';
    }
    return value;
  }

  String _typeLabel(Map<String, dynamic> data) {
    final label = _safeStr(data['label']);
    if (label.isNotEmpty) return label;
    final legacyName = _safeStr(data['name']);
    if (legacyName.isNotEmpty) return legacyName;
    final snapshotName = _safeStr(data['violationNameSnapshot']);
    if (snapshotName.isNotEmpty) return snapshotName;
    return 'Unnamed violation';
  }

  bool _typeMatchesCategory({
    required Map<String, dynamic> typeData,
    required String categoryId,
    required String categoryName,
  }) {
    final typeCategoryId = _safeStr(typeData['categoryId']);
    if (typeCategoryId.toLowerCase() == categoryId.toLowerCase()) {
      return true;
    }
    if (categoryName.isEmpty) return false;
    final typeCategoryName = _safeStr(
      typeData['categoryName'] ?? typeData['categoryNameSnapshot'],
    );
    return typeCategoryName.toLowerCase() == categoryName.toLowerCase();
  }

  String _readCategoryConcern(Map<String, dynamic> data) {
    const keys = <String>[
      'concern',
      'concernLevel',
      'severity',
      'severityLevel',
      'level',
      'classification',
    ];
    for (final key in keys) {
      final value = _normalizeConcernValue(_safeStr(data[key]));
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  bool _categoryMatchesConcern({
    required Map<String, dynamic> categoryData,
    required String selectedConcern,
  }) {
    final categoryConcern = _readCategoryConcern(categoryData);
    if (categoryConcern.isEmpty) return true;
    return categoryConcern == selectedConcern;
  }

  @override
  void initState() {
    super.initState();
    final data = widget.doc.data();
    final rawConcern = _normalizeConcernValue(_safeStr(data['concern']));
    _initialConcern = _concernOptions.contains(rawConcern)
        ? rawConcern
        : 'basic';
    _concern = _initialConcern;
    _initialCategoryId = _safeStr(data['categoryId']);
    _initialCategoryName = _safeStr(
      data['categoryNameSnapshot'] ?? data['categoryName'],
    );
    _initialTypeId = _safeStr(data['typeId'] ?? data['violationTypeId']);
    _initialTypeName = _safeStr(
      data['typeNameSnapshot'] ?? data['violationNameSnapshot'],
    );
    _expectedUpdatedAt =
        (data['updatedAt'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate();
    _reasonCtrl = TextEditingController();
    _loadCategoriesAndTypes();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategoriesAndTypes() async {
    setState(() => _loadingOptions = true);
    try {
      final strictConcernSnap = await FirebaseFirestore.instance
          .collection('violation_categories')
          .where('isActive', isEqualTo: true)
          .where('concern', isEqualTo: _concern)
          .orderBy('order')
          .get();
      var categories = strictConcernSnap.docs;
      if (categories.isEmpty) {
        final allActiveSnap = await FirebaseFirestore.instance
            .collection('violation_categories')
            .where('isActive', isEqualTo: true)
            .orderBy('order')
            .get();
        final fallback = allActiveSnap.docs.where((doc) {
          return _categoryMatchesConcern(
            categoryData: doc.data(),
            selectedConcern: _concern,
          );
        }).toList();
        categories = fallback.isEmpty ? allActiveSnap.docs : fallback;
      }

      String? categoryId = _selectedCategoryId;
      if (_prefillCurrentOnNextLoad && _concern == _initialConcern) {
        if (_initialCategoryId.isNotEmpty &&
            categories.any((doc) => doc.id == _initialCategoryId)) {
          categoryId = _initialCategoryId;
        } else if (_initialCategoryName.isNotEmpty) {
          for (final doc in categories) {
            if (_safeStr(doc.data()['name']).toLowerCase() ==
                _initialCategoryName.toLowerCase()) {
              categoryId = doc.id;
              break;
            }
          }
        }
      }
      if (categoryId != null &&
          !categories.any((doc) => doc.id == categoryId)) {
        categoryId = null;
      }

      List<QueryDocumentSnapshot<Map<String, dynamic>>> types = const [];
      String? typeId = _selectedTypeId;
      if (categoryId != null) {
        final selectedCategoryId = categoryId;
        final selectedCategoryName = categories
            .where((doc) => doc.id == selectedCategoryId)
            .map((doc) => _safeStr(doc.data()['name']))
            .firstWhere((name) => name.isNotEmpty, orElse: () => '');
        final strictTypesSnap = await FirebaseFirestore.instance
            .collection('violation_types')
            .where('isActive', isEqualTo: true)
            .where('categoryId', isEqualTo: selectedCategoryId)
            .orderBy('label')
            .get();
        types = strictTypesSnap.docs;
        if (types.isEmpty) {
          final allTypesSnap = await FirebaseFirestore.instance
              .collection('violation_types')
              .where('isActive', isEqualTo: true)
              .orderBy('label')
              .get();
          types =
              allTypesSnap.docs.where((doc) {
                return _typeMatchesCategory(
                  typeData: doc.data(),
                  categoryId: selectedCategoryId,
                  categoryName: selectedCategoryName,
                );
              }).toList()..sort((a, b) {
                final al = _typeLabel(a.data()).toLowerCase();
                final bl = _typeLabel(b.data()).toLowerCase();
                return al.compareTo(bl);
              });
        }
        if (_prefillCurrentOnNextLoad && _concern == _initialConcern) {
          if (_initialTypeId.isNotEmpty &&
              types.any((doc) => doc.id == _initialTypeId)) {
            typeId = _initialTypeId;
          } else if (_initialTypeName.isNotEmpty) {
            for (final doc in types) {
              if (_typeLabel(doc.data()).toLowerCase() ==
                  _initialTypeName.toLowerCase()) {
                typeId = doc.id;
                break;
              }
            }
          }
        }
        if (typeId != null && !types.any((doc) => doc.id == typeId)) {
          typeId = null;
        }
      } else {
        typeId = null;
      }

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _selectedCategoryId = categoryId;
        _types = types;
        _selectedTypeId = typeId;
        _prefillCurrentOnNextLoad = false;
      });
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Future<void> _loadTypesForCategory(String categoryId) async {
    setState(() => _loadingOptions = true);
    try {
      final selectedCategoryName = _categories
          .where((doc) => doc.id == categoryId)
          .map((doc) => _safeStr(doc.data()['name']))
          .firstWhere((name) => name.isNotEmpty, orElse: () => '');
      final strictTypesSnap = await FirebaseFirestore.instance
          .collection('violation_types')
          .where('isActive', isEqualTo: true)
          .where('categoryId', isEqualTo: categoryId)
          .orderBy('label')
          .get();
      var types = strictTypesSnap.docs;
      if (types.isEmpty) {
        final allTypesSnap = await FirebaseFirestore.instance
            .collection('violation_types')
            .where('isActive', isEqualTo: true)
            .orderBy('label')
            .get();
        types =
            allTypesSnap.docs.where((doc) {
              return _typeMatchesCategory(
                typeData: doc.data(),
                categoryId: categoryId,
                categoryName: selectedCategoryName,
              );
            }).toList()..sort((a, b) {
              final al = _typeLabel(a.data()).toLowerCase();
              final bl = _typeLabel(b.data()).toLowerCase();
              return al.compareTo(bl);
            });
      }

      String? nextTypeId = _selectedTypeId;
      if (nextTypeId != null && !types.any((doc) => doc.id == nextTypeId)) {
        nextTypeId = null;
      }

      if (!mounted) return;
      setState(() {
        _types = types;
        _selectedTypeId = nextTypeId;
      });
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  String _selectedCategoryName() {
    if (_selectedCategoryId == null) return '';
    for (final doc in _categories) {
      if (doc.id == _selectedCategoryId) return _safeStr(doc.data()['name']);
    }
    return '';
  }

  String _selectedTypeName() {
    if (_selectedTypeId == null) return '';
    for (final doc in _types) {
      if (doc.id == _selectedTypeId) return _typeLabel(doc.data());
    }
    return '';
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? helperText,
    bool enabled = true,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      labelStyle: const TextStyle(
        color: hintColor,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(icon, color: primaryColor.withValues(alpha: 0.85)),
      filled: true,
      fillColor: enabled ? Colors.white : Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: primaryColor, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  bool _hasCorrectionChanges() {
    final currentCategoryId = (_selectedCategoryId ?? '').trim();
    final currentTypeId = (_selectedTypeId ?? '').trim();
    final currentCategoryName = _selectedCategoryName().toLowerCase().trim();
    final currentTypeName = _selectedTypeName().toLowerCase().trim();
    final initialCategoryName = _initialCategoryName.toLowerCase().trim();
    final initialTypeName = _initialTypeName.toLowerCase().trim();
    final categoryChanged = _initialCategoryId.isNotEmpty
        ? currentCategoryId != _initialCategoryId
        : currentCategoryName != initialCategoryName;
    final typeChanged = _initialTypeId.isNotEmpty
        ? currentTypeId != _initialTypeId
        : currentTypeName != initialTypeName;
    final concernChanged = _concern.trim() != _initialConcern;
    return categoryChanged || typeChanged || concernChanged;
  }

  Future<void> _discardChanges() async {
    setState(() {
      _reasonCtrl.clear();
      _concern = _initialConcern;
      _categories = const [];
      _types = const [];
      _selectedCategoryId = null;
      _selectedTypeId = null;
      _prefillCurrentOnNextLoad = true;
    });
    await _loadCategoriesAndTypes();
  }

  Future<bool> _confirmSaveChanges({
    required String fromConcern,
    required String toConcern,
    required String fromCategory,
    required String toCategory,
    required String fromType,
    required String toType,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xxl),
        ),
        title: const Text(
          'Confirm Correction',
          style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Concern: ${_titleCase(fromConcern)} â†’ ${_titleCase(toConcern)}',
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Category: $fromCategory â†’ $toCategory',
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Specific Violation: $fromType â†’ $toType',
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: hintColor, fontWeight: FontWeight.w900),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
            child: const Text(
              'Confirm',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  Future<void> _saveChanges() async {
    setState(() => _saving = true);
    try {
      final categoryId = _selectedCategoryId ?? '';
      final categoryName = _selectedCategoryName();
      final violationId = _selectedTypeId ?? '';
      final violationName = _selectedTypeName();
      final confirmed = await _confirmSaveChanges(
        fromConcern: _initialConcern,
        toConcern: _concern,
        fromCategory: _initialCategoryName.isEmpty ? '-' : _initialCategoryName,
        toCategory: categoryName.isEmpty ? '-' : categoryName,
        fromType: _initialTypeName.isEmpty ? '-' : _initialTypeName,
        toType: violationName.isEmpty ? '-' : violationName,
      );
      if (!mounted) return;
      if (!confirmed) {
        setState(() => _saving = false);
        return;
      }

      await widget.svc.correctReportedViolation(
        caseId: widget.doc.id,
        concern: _concern,
        categoryId: categoryId,
        categoryNameSnapshot: categoryName,
        typeId: violationId,
        typeNameSnapshot: violationName,
        correctionReason: _reasonCtrl.text.trim(),
        expectedUpdatedAt: _expectedUpdatedAt,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final message = e is FirebaseException && e.code == 'aborted'
          ? 'This report was updated by another user. Close and reopen to load latest data.'
          : 'Update failed: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasChanges = _hasCorrectionChanges();
    final canSaveChanges =
        !_saving &&
        !_loadingOptions &&
        (_selectedCategoryId?.isNotEmpty ?? false) &&
        (_selectedTypeId?.isNotEmpty ?? false) &&
        hasChanges &&
        _reasonCtrl.text.trim().isNotEmpty;
    final fieldEnabled = !_saving && !_loadingOptions;

    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Correct Violation Report',
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: hintColor),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'REPORT CORRECTION',
                style: TextStyle(
                  color: hintColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _concern,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w700,
                ),
                decoration: _decor(
                  label: 'Concern Level',
                  icon: Icons.flag_outlined,
                  enabled: fieldEnabled,
                ),
                items: _concernOptions
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_titleCase(value)),
                      ),
                    )
                    .toList(),
                onChanged: !fieldEnabled
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _concern = value;
                          _categories = const [];
                          _types = const [];
                          _selectedCategoryId = null;
                          _selectedTypeId = null;
                          _prefillCurrentOnNextLoad = false;
                        });
                        _loadCategoriesAndTypes();
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategoryId,
                hint: const Text('Select category'),
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w700,
                ),
                decoration: _decor(
                  label: 'Corrected Category',
                  icon: Icons.category_outlined,
                  enabled: fieldEnabled,
                ),
                items: _categories
                    .map(
                      (doc) => DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(_safeStr(doc.data()['name'])),
                      ),
                    )
                    .toList(),
                onChanged: !fieldEnabled
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedCategoryId = value;
                          _selectedTypeId = null;
                          _types = const [];
                        });
                        _loadTypesForCategory(value);
                      },
              ),
              if (!_loadingOptions && _categories.isEmpty) ...[
                const SizedBox(height: 6),
                const Text(
                  'No active categories found for this concern.',
                  style: TextStyle(color: hintColor, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedTypeId,
                hint: const Text('Select specific violation'),
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w700,
                ),
                decoration: _decor(
                  label: 'Corrected Specific Violation',
                  icon: Icons.rule_folder_outlined,
                  enabled: fieldEnabled,
                ),
                items: _types
                    .map(
                      (doc) => DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(_typeLabel(doc.data())),
                      ),
                    )
                    .toList(),
                onChanged: !fieldEnabled
                    ? null
                    : (value) {
                        setState(() => _selectedTypeId = value);
                      },
              ),
              if (!_loadingOptions &&
                  _selectedCategoryId != null &&
                  _types.isEmpty) ...[
                const SizedBox(height: 6),
                const Text(
                  'No active specific violations under this category.',
                  style: TextStyle(color: hintColor, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _reasonCtrl,
                onChanged: (_) => setState(() {}),
                minLines: 2,
                maxLines: 4,
                enabled: fieldEnabled,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w700,
                ),
                decoration: _decor(
                  label: 'Reason for correction',
                  helperText:
                      'Required when saving. Sent to reporter and student notifications.',
                  icon: Icons.edit_note_rounded,
                  enabled: fieldEnabled,
                ),
              ),
              if (!hasChanges)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'No changes yet. Update fields before saving.',
                    style: TextStyle(color: hintColor, fontSize: 12),
                  ),
                ),
              if (_saving || _loadingOptions) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: primaryColor),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _discardChanges,
          child: const Text(
            'Discard Changes',
            style: TextStyle(color: hintColor, fontWeight: FontWeight.w900),
          ),
        ),
        FilledButton(
          onPressed: canSaveChanges ? _saveChanges : null,
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text(
            'Save Changes',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _CompleteMeetingDialog extends StatefulWidget {
  final String caseId;
  final ViolationCaseService svc;

  const _CompleteMeetingDialog({required this.caseId, required this.svc});

  @override
  State<_CompleteMeetingDialog> createState() => _CompleteMeetingDialogState();
}

class _CompleteMeetingDialogState extends State<_CompleteMeetingDialog> {
  final _typesSvc = ViolationTypesService();
  final _notesCtrl = TextEditingController();
  final _facultyNoteCtrl = TextEditingController();
  String? _severity;
  String? _sanctionType;
  bool _saving = false;
  static const List<String> _severities = ['Minor', 'Moderate', 'Major'];
  List<Map<String, String>> _sanctionOptions = const [
    {'code': 'none', 'label': 'None'},
    {'code': 'suspension', 'label': 'Suspension'},
  ];

  Future<void> _loadSanctionTypes() async {
    try {
      final rows = await _typesSvc.fetchActiveSanctionTypes();
      final options = rows
          .map(
            (row) => <String, String>{
              'code': (row['id'] ?? '').toString().trim().toLowerCase(),
              'label': (row['label'] ?? '').toString().trim(),
            },
          )
          .where((row) => (row['code'] ?? '').isNotEmpty)
          .toList(growable: false);
      if (!mounted || options.isEmpty) return;
      setState(() {
        _sanctionOptions = options;
        if (_sanctionType == null ||
            !_sanctionOptions.any((item) => item['code'] == _sanctionType)) {
          _sanctionType = _sanctionOptions.first['code'];
        }
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _sanctionType = _sanctionOptions.first['code'];
    _loadSanctionTypes();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _facultyNoteCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      labelStyle: const TextStyle(
        color: hintColor,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(icon, color: primaryColor.withValues(alpha: 0.85)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: primaryColor, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Complete Meeting',
        style: TextStyle(fontWeight: FontWeight.w900, color: primaryColor),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MEETING RECORD',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: hintColor,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                onChanged: (_) => setState(() {}),
                minLines: 4,
                maxLines: 8,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: textDark,
                ),
                decoration: _decor(
                  label: 'Meeting Notes',
                  icon: Icons.notes_rounded,
                  helperText: 'Required. Used as official meeting record.',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _severity,
                hint: const Text('Select severity'),
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _severity = v),
                decoration: _decor(
                  label: 'Severity Level',
                  icon: Icons.shield_moon_rounded,
                  helperText: 'Required for meeting-required cases.',
                ),
                items: _severities
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _sanctionType,
                hint: const Text('Select sanction'),
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _sanctionType = v),
                decoration: _decor(
                  label: 'Sanction Type',
                  icon: Icons.rule_folder_rounded,
                ),
                items: _sanctionOptions
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item['code'],
                        child: Text(item['label'] ?? ''),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _facultyNoteCtrl,
                onChanged: (_) => setState(() {}),
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: textDark,
                ),
                decoration: _decor(
                  label: 'Faculty Note (sent to reporter)',
                  icon: Icons.campaign_rounded,
                  helperText:
                      'Optional note that the reporting faculty will receive.',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'This completes the meeting and auto-resolves the case.',
                style: TextStyle(
                  color: hintColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(
                    color: primaryColor,
                    backgroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: hintColor),
          ),
        ),
        FilledButton(
          onPressed:
              _saving || _notesCtrl.text.trim().isEmpty || _severity == null
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await widget.svc.completeMeeting(
                      caseId: widget.caseId,
                      meetingNotes: _notesCtrl.text,
                      finalSeverity: _severity!,
                      sanctionType: _sanctionType ?? 'none',
                      facultyNote: _facultyNoteCtrl.text,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Resolve failed: $e')),
                    );
                    setState(() => _saving = false);
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            _saving ? 'Resolving...' : 'Resolve Case',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

// ======================================================================
// STUDENT HISTORY SECTION
// ======================================================================

class _StudentHistorySection extends StatelessWidget {
  final String studentUid;
  final String currentCaseId;
  final String currentViolationType;

  const _StudentHistorySection({
    required this.studentUid,
    required this.currentCaseId,
    required this.currentViolationType,
  });

  @override
  Widget build(BuildContext context) {
    if (studentUid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('violation_cases')
          .where('studentUid', isEqualTo: studentUid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final docs = snapshot.data!.docs
            .where((d) => d.id != currentCaseId)
            .toList();
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No prior history for this student.',
                style: TextStyle(
                  color: hintColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }

        // Sort: Connected cases first, then by date
        docs.sort((a, b) {
          final typeA = _safeStr(
            a.data()['violationTypeLabel'] ??
                a.data()['violationNameSnapshot'] ??
                a.data()['violationName'],
          );
          final typeB = _safeStr(
            b.data()['violationTypeLabel'] ??
                b.data()['violationNameSnapshot'] ??
                b.data()['violationName'],
          );

          final isConnectedA = _isConnected(typeA, currentViolationType);
          final isConnectedB = _isConnected(typeB, currentViolationType);

          if (isConnectedA && !isConnectedB) return -1;
          if (!isConnectedA && isConnectedB) return 1;

          final dateA =
              (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final dateB =
              (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return dateB.compareTo(dateA);
        });

        return Column(
          children: docs.map((doc) {
            final d = doc.data();
            final type = _safeStr(
              d['violationTypeLabel'] ??
                  d['violationNameSnapshot'] ??
                  d['violationName'],
            );
            final date = (d['createdAt'] as Timestamp?)?.toDate();
            final dateStr = date == null
                ? '--'
                : '${date.month}/${date.day}/${date.year}';
            final status = _statusLabel(_safeStr(d['status']));
            final severity = _safeStr(
              d['finalSeverity'] ?? d['concern'],
            ).toUpperCase();

            final isConnected = _isConnected(type, currentViolationType);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isConnected
                    ? primaryColor.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isConnected
                      ? primaryColor.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  if (isConnected)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.link_rounded,
                        color: primaryColor,
                        size: 16,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type,
                          style: TextStyle(
                            color: isConnected ? primaryColor : textDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$dateStr - $status - $severity',
                          style: const TextStyle(
                            color: hintColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  bool _isConnected(String type, String current) {
    final t = type.toLowerCase();
    final c = current.toLowerCase();
    if (t == c) return true;

    // Logic for connected cases: frequent absent and late links to tardiness
    final tardinessKeywords = ['tardy', 'late', 'absent', 'attendance'];
    bool typeIsTardiness = tardinessKeywords.any((k) => t.contains(k));
    bool currentIsTardiness = tardinessKeywords.any((k) => c.contains(k));

    return typeIsTardiness && currentIsTardiness;
  }
}

// ======================================================================
// ASSIGN ACTION DIALOG
// ======================================================================

class _SetActionOption {
  final String code;
  final String label;
  final bool meetingRequired;

  const _SetActionOption({
    required this.code,
    required this.label,
    required this.meetingRequired,
  });
}

class _AssignActionDialog extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String currentSeverity;
  final String currentAction;
  final ViolationCaseService svc;

  const _AssignActionDialog({
    required this.doc,
    required this.currentSeverity,
    required this.currentAction,
    required this.svc,
  });

  @override
  State<_AssignActionDialog> createState() => _AssignActionDialogState();
}

class _AssignActionDialogState extends State<_AssignActionDialog> {
  final _scheduleSvc = OsaMeetingScheduleService();
  final _typesSvc = ViolationTypesService();
  String? _severity;
  String? _action;
  String? _meetingTimeframeKey; // fixed: 3days
  bool _submitting = false;
  bool _checkingTimeframeSlots = false;
  bool _hasSlotsInTimeframe = true;
  String? _timeframeSlotMessage;
  int _timeframeValidationSeq = 0;

  final List<String> _severities = ['Minor', 'Moderate', 'Major'];
  List<_SetActionOption> _reviewActions = const [];

  final List<String> _monitorActions = [
    'Monitoring Progress',
    'Follow-up Session',
    'Home Visitation',
    'Behavioral Contract Update',
    'Counseling Extension',
    'Case Resolution Pending',
  ];

  List<_SetActionOption> _defaultActionOptions() => ViolationSetActionTypes.all
      .map(
        (item) => _SetActionOption(
          code: item.code,
          label: item.label,
          meetingRequired: item.meetingRequired,
        ),
      )
      .toList(growable: false);

  Future<void> _loadActionTypes() async {
    try {
      final rows = await _typesSvc.fetchActiveActionTypes();
      final options = rows
          .map(
            (row) => _SetActionOption(
              code: (row['id'] ?? '').toString().trim().toLowerCase(),
              label: (row['label'] ?? '').toString().trim(),
              meetingRequired: row['meetingRequired'] == true,
            ),
          )
          .where((row) => row.code.isNotEmpty && row.label.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _reviewActions = options.isEmpty ? _defaultActionOptions() : options;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _reviewActions = _defaultActionOptions());
    }
  }

  String? _actionCodeForLabel(String? label) {
    if (label == null || label.trim().isEmpty) return null;
    final match = _reviewActions.where((item) => item.label == label);
    if (match.isEmpty) return null;
    return match.first.code;
  }

  bool _isMeetingRequiredAction(String actionLabel) {
    final fromBackend = ViolationSetActionTypes.resolve(actionLabel);
    if (fromBackend != null) return fromBackend.meetingRequired;

    final configured = _reviewActions.where(
      (item) => item.label == actionLabel,
    );
    if (configured.isNotEmpty) return configured.first.meetingRequired;

    final a = actionLabel.toLowerCase().trim();
    if (a.contains('advisory') || a.contains('reminder')) return false;
    if (a.contains('formal warning') || a.contains('written warning')) {
      return false;
    }
    if (a.contains('guidance') && a.contains('check')) return true;
    if (a.contains('parent') || a.contains('guardian')) return true;
    if (a.contains('osa')) return true;
    if (a.contains('immediate action')) return true;
    return false;
  }

  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59);

  DateTime _meetingDueByForKey(String key) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (key) {
      case 'today':
        return _endOfDay(today);
      case '3days':
        return _endOfDay(today.add(const Duration(days: 3)));
      case 'week':
        return _endOfDay(today.add(const Duration(days: 7)));
      default:
        return _endOfDay(today);
    }
  }

  Future<void> _validateTimeframeSlots() async {
    final status = _safeStr(widget.doc.data()['status']).toLowerCase();
    final isMonitor =
        status == 'action set' ||
        status == 'unresolved' ||
        status == 'resolved';
    final selectedMeetingAction =
        !isMonitor && _action != null && _isMeetingRequiredAction(_action!);

    if (!selectedMeetingAction) {
      if (!mounted) return;
      setState(() {
        _checkingTimeframeSlots = false;
        _hasSlotsInTimeframe = true;
        _timeframeSlotMessage = null;
      });
      return;
    }

    final timeframe =
        (_meetingTimeframeKey == null || _meetingTimeframeKey!.isEmpty)
        ? '3days'
        : _meetingTimeframeKey!;

    final schoolYearId = _safeStr(widget.doc.data()['schoolYearId']);
    final termId = _safeStr(widget.doc.data()['termId']);
    if (schoolYearId.isEmpty || termId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _checkingTimeframeSlots = false;
        _hasSlotsInTimeframe = false;
        _timeframeSlotMessage =
            'This case has no linked school year/term. Cannot validate available meeting slots.';
      });
      return;
    }

    final seq = ++_timeframeValidationSeq;
    if (!mounted) return;
    setState(() {
      _checkingTimeframeSlots = true;
      _timeframeSlotMessage = null;
    });

    try {
      final now = DateTime.now();
      final dueBy = _meetingDueByForKey(timeframe);
      final count = await _scheduleSvc.countOpenSlotsInRange(
        schoolYearId: schoolYearId,
        termId: termId,
        rangeStart: now,
        rangeEnd: dueBy,
      );
      if (!mounted || seq != _timeframeValidationSeq) return;
      setState(() {
        _checkingTimeframeSlots = false;
        _hasSlotsInTimeframe = count > 0;
        _timeframeSlotMessage = count > 0
            ? '$count open slot(s) available for the current booking window.'
            : 'No available slots for the current booking window. Please update meeting schedule.';
      });
    } catch (_) {
      if (!mounted || seq != _timeframeValidationSeq) return;
      setState(() {
        _checkingTimeframeSlots = false;
        _hasSlotsInTimeframe = false;
        _timeframeSlotMessage =
            'Unable to validate available slots right now. Please try again.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _reviewActions = _defaultActionOptions();
    final status = _safeStr(widget.doc.data()['status']).toLowerCase();
    final isMonitor =
        status == 'action set' ||
        status == 'unresolved' ||
        status == 'resolved';
    final actions = isMonitor
        ? _monitorActions
        : _reviewActions.map((item) => item.label).toList(growable: false);

    if (_severities.any(
      (s) => s.toLowerCase() == widget.currentSeverity.toLowerCase(),
    )) {
      _severity = _severities.firstWhere(
        (s) => s.toLowerCase() == widget.currentSeverity.toLowerCase(),
      );
    }
    // Try to match action
    final currentKey = widget.currentAction.toLowerCase();
    for (final a in actions) {
      if (currentKey.contains(a.split('(')[0].trim().toLowerCase())) {
        _action = a;
        break;
      }
    }

    // Fixed meeting booking window for meeting-required actions
    _meetingTimeframeKey = '3days';
    _loadActionTypes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateTimeframeSlots();
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _safeStr(widget.doc.data()['status']).toLowerCase();
    final isMonitor =
        status == 'action set' ||
        status == 'unresolved' ||
        status == 'resolved';
    final actions = isMonitor
        ? _monitorActions
        : _reviewActions.map((item) => item.label).toList(growable: false);
    final selectedMeetingAction =
        !isMonitor && _action != null && _isMeetingRequiredAction(_action!);
    final willResolveImmediately =
        !isMonitor && _action != null && !selectedMeetingAction;
    final showTimeframeSection = _action != null && selectedMeetingAction;
    final showSeveritySection = _action != null && !showTimeframeSection;
    final requiresSeverity = showSeveritySection;
    final title = isMonitor ? 'Update Monitoring' : 'Assign Assessment';
    final subtitle = isMonitor
        ? 'Update the monitoring status or follow-up action.'
        : 'Set the severity and required action for this case.';

    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        title,
        style: const TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: const TextStyle(
                  color: hintColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'ACTION SETTINGS',
                style: const TextStyle(
                  color: hintColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isMonitor
                    ? 'Monitoring Action (Required)'
                    : 'Assign Action (Required)',
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              ...actions.map((a) {
                final selected = _action == a;
                final needsMeeting = !isMonitor && _isMeetingRequiredAction(a);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _action = a;
                      if (!isMonitor && _isMeetingRequiredAction(a)) {
                        _meetingTimeframeKey ??= '3days';
                      }
                    });
                    _validateTimeframeSlots();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? primaryColor.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? primaryColor
                            : Colors.black.withValues(alpha: 0.1),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: selected ? primaryColor : hintColor,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            a,
                            style: TextStyle(
                              color: selected ? textDark : hintColor,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        if (needsMeeting)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                              border: Border.all(
                                color: primaryColor.withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Text(
                              'Meeting',
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),

              if (showTimeframeSection) ...[
                const SizedBox(height: 16),
                const Text(
                  'Meeting booking window (Required)',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Text(
                    'Initial booking window: 3 days (+2-day auto extension)',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_checkingTimeframeSlots)
                  const Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Checking slot availability...',
                          style: TextStyle(
                            color: hintColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  )
                else if (_timeframeSlotMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _hasSlotsInTimeframe
                          ? primaryColor.withValues(alpha: 0.08)
                          : Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _hasSlotsInTimeframe
                            ? primaryColor.withValues(alpha: 0.25)
                            : Colors.red.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      _timeframeSlotMessage!,
                      style: TextStyle(
                        color: _hasSlotsInTimeframe
                            ? primaryColor
                            : Colors.red.shade700,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
              if (showSeveritySection) ...[
                const SizedBox(height: 16),
                const Text(
                  'Severity (Required)',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _severities.map((s) {
                    final selected = _severity == s;
                    return ChoiceChip(
                      label: Text(s),
                      selected: selected,
                      onSelected: (val) =>
                          setState(() => _severity = val ? s : null),
                      selectedColor: primaryColor.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: selected ? primaryColor : hintColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (willResolveImmediately) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.orange.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This action will mark the case as Resolved immediately.',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: hintColor),
          ),
        ),
        FilledButton(
          onPressed: (_action == null || _submitting)
              ? null
              : (requiresSeverity && (_severity == null || _severity!.isEmpty))
              ? null
              : (showTimeframeSection &&
                    (_meetingTimeframeKey == null ||
                        _meetingTimeframeKey!.isEmpty))
              ? null
              : (showTimeframeSection &&
                    (_checkingTimeframeSlots || !_hasSlotsInTimeframe))
              ? null
              : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  willResolveImmediately ? 'Resolve Case' : 'Confirm Action',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final status = _safeStr(widget.doc.data()['status']).toLowerCase();
      final isMonitor =
          status == 'action set' ||
          status == 'unresolved' ||
          status == 'resolved';
      final isMeetingRequired =
          _action != null && _isMeetingRequiredAction(_action!);
      if (isMeetingRequired &&
          (_checkingTimeframeSlots || !_hasSlotsInTimeframe)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No available meeting slots for the initial 3-day booking window.',
              ),
            ),
          );
        }
        setState(() => _submitting = false);
        return;
      }
      final finalSeverity = (!isMonitor && isMeetingRequired)
          ? null
          : _severity;
      final actionCode = _actionCodeForLabel(_action);
      await widget.svc.setGuidanceDecisionV2(
        caseId: widget.doc.id,
        finalSeverity: finalSeverity,
        actionSelected: _action!,
        actionTypeCode: actionCode,
        meetingRequiredOverride: !isMonitor ? isMeetingRequired : null,
        actionReason: null,
        meetingStatus: isMeetingRequired ? 'pending_student_booking' : null,
        meetingWindow: isMeetingRequired
            ? (_meetingTimeframeKey ?? '3days')
            : null,
        meetingDueBy: isMeetingRequired
            ? _meetingDueByForKey(_meetingTimeframeKey ?? '3days')
            : null,
        scheduledAt: null,
        meetingLocation: null,
        officialRemarks: null,
        internalNotes: null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _submitting = false);
      }
    }
  }
}

// ======================================================================
// ENHANCED UI COMPONENTS
// ======================================================================

class _CategoryPill extends StatelessWidget {
  final String text;
  final String concern;

  const _CategoryPill({required this.text, required this.concern});

  @override
  Widget build(BuildContext context) {
    final isSerious = concern.toLowerCase().contains('serious');

    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSerious
            ? primaryColor.withValues(alpha: 0.12)
            : Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSerious
              ? primaryColor.withValues(alpha: 0.25)
              : Colors.blue.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isSerious ? primaryColor : Colors.blue.shade700,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _EvidencePlaceholders extends StatelessWidget {
  final List<String> urls;
  const _EvidencePlaceholders({required this.urls});

  @override
  Widget build(BuildContext context) {
    final count = urls.length;
    if (count <= 0) {
      return const Text(
        'No evidence attached.',
        style: TextStyle(color: hintColor, fontWeight: FontWeight.w700),
      );
    }

    final show = count > 6 ? 6 : count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tap an image to view.',
          style: TextStyle(
            color: hintColor,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Evidence files ($count)',
          style: const TextStyle(color: hintColor, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(show, (i) {
            final url = urls[i];
            final isPdf = _isLikelyPdf(url);
            final imageUrls = urls.where((u) => !_isLikelyPdf(u)).toList();
            final imageInitialIndex = imageUrls.indexOf(url);
            return InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: () async {
                if (isPdf) {
                  await _openEvidenceFile(context, url);
                  return;
                }
                await _openEvidenceViewer(
                  context,
                  imageUrls,
                  initialIndex: imageInitialIndex < 0 ? 0 : imageInitialIndex,
                );
              },
              child: Stack(
                children: [
                  Container(
                    width: 100,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: isPdf
                        ? const Center(
                            child: Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Color(0xFFB71C1C),
                              size: 24,
                            ),
                          )
                        : _ResolvedEvidenceImage(sourceUrl: url),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: const Icon(
                        Icons.open_in_new_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (isPdf)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: const Text(
                          'PDF',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  if (i == show - 1 && count > show)
                    Positioned.fill(
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        child: Text(
                          '+${count - show}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color fill;
  final Color textColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.fill,
    required this.textColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// PILLS & TONES
// ======================================================================

class _Pill extends StatelessWidget {
  final String text;
  final _Tone tone;

  const _Pill({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tone.text,
          fontWeight: FontWeight.w900,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

// ======================================================================
// STATES + HELPERS
// ======================================================================

class _Tone {
  final Color fill;
  final Color border;
  final Color text;

  const _Tone({required this.fill, required this.border, required this.text});
}

String _safeStr(dynamic v) => (v ?? '').toString().trim();

final Map<String, Future<String>> _studentProgramFutureCache =
    <String, Future<String>>{};

String _studentProgramLabelFromCase(Map<String, dynamic> data) {
  final fromCase = _safeStr(
    data['programId'] ??
        data['studentProgramId'] ??
        data['studentProgram'] ??
        data['program'],
  );
  return fromCase.isEmpty ? '--' : fromCase;
}

Future<String> _resolveStudentProgramLabel(
  Map<String, dynamic> data,
  String studentUid,
) {
  final fromCase = _studentProgramLabelFromCase(data);
  if (fromCase != '--') {
    return Future<String>.value(fromCase);
  }

  final uid = _safeStr(studentUid);
  if (uid.isEmpty) {
    return Future<String>.value('--');
  }

  return _studentProgramFutureCache.putIfAbsent(uid, () async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final userData = userDoc.data() ?? const <String, dynamic>{};
    final studentProfile =
        userData['studentProfile'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final fromUser = _safeStr(
      studentProfile['programId'] ??
          studentProfile['program'] ??
          userData['programId'] ??
          userData['program'],
    );
    return fromUser.isEmpty ? '--' : fromUser;
  });
}

String _categoryLabelFromCaseGlobal(Map<String, dynamic> data) {
  final concernValues = <String>{
    _safeStr(data['concern']).toLowerCase(),
    _safeStr(data['concernType']).toLowerCase(),
    _safeStr(data['reportedConcern']).toLowerCase(),
    _safeStr(data['reportedConcernType']).toLowerCase(),
    'basic',
    'serious',
  }..removeWhere((value) => value.isEmpty);

  bool isConcernValue(String value) =>
      concernValues.contains(value.trim().toLowerCase());

  String pick(List<String> keys) {
    for (final key in keys) {
      final value = _safeStr(data[key]);
      if (value.isEmpty) continue;
      if (isConcernValue(value)) continue;
      return value;
    }
    return '';
  }

  final currentCategory = pick(const ['categoryNameSnapshot', 'categoryName']);
  if (currentCategory.isNotEmpty) return currentCategory;

  final reportedCategory = pick(const [
    'reportedCategoryNameSnapshot',
    'reportedCategoryName',
  ]);
  if (reportedCategory.isNotEmpty) return reportedCategory;

  final fallback = _safeStr(
    data['categoryNameSnapshot'] ??
        data['categoryName'] ??
        data['reportedCategoryNameSnapshot'],
  );
  return fallback.isEmpty ? '--' : fallback;
}

String _formatReportedAtSmartGlobal(DateTime? date) {
  if (date == null) return '--';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final startOfWeek = today.subtract(Duration(days: now.weekday - 1));
  final endOfWeek = startOfWeek.add(const Duration(days: 7));
  final time = DateFormat('h:mm a').format(date);

  if (day == today) {
    return 'Today, $time';
  }

  if ((day.isAtSameMomentAs(startOfWeek) || day.isAfter(startOfWeek)) &&
      day.isBefore(endOfWeek)) {
    return '${DateFormat('EEEE').format(date)}, $time';
  }

  return DateFormat('MMM d, yyyy, h:mm a').format(date);
}

String _reporterRoleLabel(String rawRole) {
  final role = _safeStr(rawRole).toLowerCase();
  switch (role) {
    case 'professor':
    case 'teacher':
    case 'faculty':
      return 'Teacher';
    case 'guard':
      return 'Guard';
    case 'dean':
      return 'Dean';
    case 'department_admin':
      return 'Department Admin';
    case 'osa_admin':
      return 'OSA Admin';
    case 'counseling_admin':
      return 'Counseling Admin';
    default:
      return role.isEmpty ? '' : _titleCase(role.replaceAll('_', ' '));
  }
}

String _reportedByDisplay(Map<String, dynamic> data) {
  final name = _safeStr(data['reportedByName']);
  final role = _reporterRoleLabel(_safeStr(data['reportedByRole']));
  if (name.isEmpty && role.isEmpty) return '--';
  if (name.isEmpty) return role;
  if (role.isEmpty) return name;
  return '$name ($role)';
}

String _statusKey(String raw) {
  final n = _safeStr(raw).toLowerCase();
  if (n.contains('under') && n.contains('review')) return 'under review';
  if (n.contains('action')) return 'action set';
  if (n.contains('unresolved')) return 'unresolved';
  if (n.contains('resolved') || n.contains('done')) return 'resolved';
  if (n.contains('submitted')) return 'submitted';
  if (n.contains('rejected')) return 'rejected';
  if (n.contains('dismiss')) return 'dismissed';
  return n;
}

String _statusLabel(String raw) {
  switch (_statusKey(raw)) {
    case 'under review':
      return 'Under Review';
    case 'action set':
      return 'Action Set';
    case 'unresolved':
      return 'Unresolved';
    case 'resolved':
      return 'Resolved';
    case 'submitted':
      return 'Under Review';
    case 'rejected':
      return 'Rejected';
    case 'dismissed':
      return 'Dismissed';
    default:
      return raw.isEmpty ? 'Unknown' : _titleCase(raw);
  }
}

String _actionKey(Map<String, dynamic> d) {
  final raw = _safeStr(d['actionSelected'] ?? d['actionType']).toLowerCase();
  if (raw.contains('osa')) return 'osa endorsement / disciplinary call';
  if (raw.contains('conference') || raw.contains('parent')) {
    return 'parent/guardian conference';
  }
  if (raw.contains('check-in')) return 'OSA check-in (soft meeting)';
  if (raw.contains('formal') || raw.contains('warning')) {
    return 'formal warning';
  }
  if (raw.contains('advisory') || raw.contains('reminder')) {
    return 'advisory / reminder';
  }
  if (raw.contains('immediate')) return 'immediate action required';
  if (raw.contains('monitor')) return 'monitoring';
  if (raw.isEmpty) return '';
  return raw;
}

String _meetingTypeLabelForDisplay(Map<String, dynamic> d) {
  if (!_meetingRequired(d)) return '';

  final explicit = _safeStr(d['actionSelected'] ?? d['actionType']);
  if (explicit.isNotEmpty) return _formatMeetingTypeLabel(explicit);

  final normalized = _actionKey(d);
  if (normalized.isEmpty) return '';
  return _formatMeetingTypeLabel(normalized);
}

String _formatMeetingTypeLabel(String raw) {
  final value = _safeStr(raw);
  if (value.isEmpty) return '';

  final normalized = value.toLowerCase();
  const overrides = <String, String>{
    'osa endorsement / disciplinary call':
        'OSA Endorsement / Disciplinary Call',
    'parent/guardian conference': 'Parent/Guardian Conference',
    'osa check-in (soft meeting)': 'OSA Check-In (Soft Meeting)',
    'immediate action required': 'Immediate Action Required',
    'monitoring': 'Monitoring',
  };

  if (overrides.containsKey(normalized)) {
    return overrides[normalized]!;
  }

  var label = _titleCase(value);
  label = label.replaceAll(RegExp(r'\bOsa\b'), 'OSA');
  label = label.replaceAll(
    RegExp(r'Check-in', caseSensitive: false),
    'Check-In',
  );
  label = label.replaceAll(
    RegExp(r'Parent/guardian', caseSensitive: false),
    'Parent/Guardian',
  );
  return label;
}

bool _meetingRequired(Map<String, dynamic> d) {
  final req = d['meetingRequired'];
  if (req is bool) return req;
  final action = _actionKey(d);
  return action.contains('conference') ||
      action.contains('check-in') ||
      action.contains('osa') ||
      action.contains('immediate');
}

String _meetingFlowKey(Map<String, dynamic> d) {
  if (!_meetingRequired(d)) return 'not_required';

  final meetingStatus = _safeStr(d['meetingStatus']).toLowerCase();
  final bookingStatus = _safeStr(d['bookingStatus']).toLowerCase();
  final scheduledAt = _globalTsToDate(d['scheduledAt']);
  final dueBy =
      _globalTsToDate(d['bookingDeadlineAt']) ??
      _globalTsToDate(d['meetingDueBy']);

  final hasSchedule =
      scheduledAt != null ||
      meetingStatus.contains('scheduled') ||
      bookingStatus.contains('booked');

  if (meetingStatus.contains('completed') ||
      bookingStatus.contains('completed')) {
    return 'completed';
  }

  if (meetingStatus.contains('booking_missed')) return 'booking_missed';

  final explicitMeetingMissed =
      meetingStatus.contains('meeting_missed') ||
      (meetingStatus.contains('missed') && !meetingStatus.contains('booking'));

  if (explicitMeetingMissed) {
    return hasSchedule ? 'meeting_missed' : 'booking_missed';
  }

  if (bookingStatus.contains('missed')) {
    return hasSchedule ? 'meeting_missed' : 'booking_missed';
  }

  if (hasSchedule) return 'scheduled';

  final pendingBooking =
      meetingStatus.isEmpty || meetingStatus.contains('pending');
  if (pendingBooking) {
    if (dueBy != null && DateTime.now().isAfter(dueBy)) {
      return 'booking_missed';
    }
    return 'needs_booking';
  }

  if (dueBy != null && DateTime.now().isAfter(dueBy)) {
    return 'booking_missed';
  }
  return 'needs_booking';
}

bool _isActionSetNeedsBooking(Map<String, dynamic> d) {
  return _statusKey(_safeStr(d['status'])) == 'action set' &&
      _meetingFlowKey(d) == 'needs_booking';
}

String _effectiveMeetingStatusKeyGlobal(Map<String, dynamic> d) {
  return _meetingFlowKey(d);
}

bool _isGraceWindowGlobal(Map<String, dynamic> d) {
  final graceCount = (d['bookingGraceCount'] as num?)?.toInt() ?? 0;
  if (graceCount > 0) return true;
  if (_globalTsToDate(d['bookingGraceExtendedAt']) != null) return true;
  return false;
}

String _meetingStatusChipTextGlobal(Map<String, dynamic> d) {
  if (!_meetingRequired(d)) return 'No Meeting';
  final status = _effectiveMeetingStatusKeyGlobal(d);
  if (status == 'scheduled') return 'Scheduled';
  if (status == 'completed') return 'Completed';
  if (status == 'booking_missed' || status == 'meeting_missed') {
    return 'Missed';
  }
  return _isGraceWindowGlobal(d) ? 'Grace Window' : 'Booking Window';
}

String _fmtMeetingDateTime(DateTime dateTime) {
  return DateFormat('MMM d, yyyy - h:mm a').format(dateTime);
}

List<Map<String, dynamic>> _meetingHistoryEntries(Map<String, dynamic> d) {
  final raw = d['meetingHistory'];
  if (raw is! List) return const [];

  final list = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is Map) {
      list.add(Map<String, dynamic>.from(item));
    }
  }

  list.sort((a, b) {
    final ad = _globalTsToDate(a['recordedAt']);
    final bd = _globalTsToDate(b['recordedAt']);
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
  return list;
}

DateTime? _globalTsToDate(dynamic ts) {
  if (ts == null) return null;
  try {
    return (ts as Timestamp).toDate();
  } catch (_) {
    return null;
  }
}

List<String> _evidenceUrls(Map<String, dynamic> d) {
  final out = <String>[];

  void addCandidate(dynamic v) {
    final url = _extractUrl(v);
    if (url.isNotEmpty && !out.contains(url)) {
      out.add(url);
    }
  }

  final urls = d['evidenceUrls'];
  if (urls is List) {
    for (final item in urls) {
      addCandidate(item);
    }
  }

  final evidences = d['evidences'];
  if (evidences is List) {
    for (final item in evidences) {
      addCandidate(item);
    }
  }

  final evidence = d['evidence'];
  if (evidence != null) {
    addCandidate(evidence);
  }

  return out;
}

String _extractUrl(dynamic item) {
  if (item is String) return item.trim();
  if (item is Map) {
    final keys = [
      'url',
      'downloadUrl',
      'downloadURL',
      'fileUrl',
      'fileURL',
      'imageUrl',
      'imageURL',
    ];
    for (final key in keys) {
      final v = (item[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
  }
  return '';
}

bool _isLikelyPdf(String rawUrl) {
  final value = rawUrl.toLowerCase();
  return value.endsWith('.pdf') ||
      value.contains('.pdf?') ||
      value.contains('mime=application%2fpdf') ||
      value.contains('application/pdf');
}

Future<String?> _resolveEvidenceUrl(String rawUrl) async {
  final value = rawUrl.trim();
  if (value.isEmpty) return null;

  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }

  try {
    if (value.startsWith('gs://')) {
      return await FirebaseStorage.instance.refFromURL(value).getDownloadURL();
    }
    if (!value.contains('://')) {
      return await FirebaseStorage.instance.ref(value).getDownloadURL();
    }
  } catch (_) {}

  return null;
}

Future<void> _openEvidenceFile(BuildContext context, String rawUrl) async {
  final resolved = await _resolveEvidenceUrl(rawUrl);
  if (resolved == null || resolved.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open file URL.')));
    }
    return;
  }

  final uri = Uri.tryParse(resolved);
  if (uri == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid file URL.')));
    }
    return;
  }

  final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open the file.')));
  }
}

Future<void> _openEvidenceViewer(
  BuildContext context,
  List<String> urls, {
  int initialIndex = 0,
}) async {
  if (urls.isEmpty) return;

  final resolved = <String>[];
  for (final raw in urls) {
    if (_isLikelyPdf(raw)) continue;
    final url = await _resolveEvidenceUrl(raw);
    if (url != null && url.isNotEmpty) {
      resolved.add(url);
    }
  }

  if (resolved.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previewable image evidence found.')),
      );
    }
    return;
  }

  if (!context.mounted) return;

  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (_) => _EvidenceViewerDialog(
      urls: resolved,
      initialIndex: initialIndex.clamp(0, resolved.length - 1),
    ),
  );
}

class _EvidenceViewerDialog extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _EvidenceViewerDialog({required this.urls, required this.initialIndex});

  @override
  State<_EvidenceViewerDialog> createState() => _EvidenceViewerDialogState();
}

class _EvidenceViewerDialogState extends State<_EvidenceViewerDialog> {
  late final PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = size.width > 980 ? 940.0 : size.width * 0.96;
    final dialogHeight = size.height > 760 ? 700.0 : size.height * 0.92;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Text(
                    'Evidence ${_current + 1}/${widget.urls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.urls.length,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (_, i) {
                  final url = widget.urls[i];
                  return InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white70,
                              size: 42,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Failed to load image',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Check image metadata/CORS in Firebase Storage.',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
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
            if (widget.urls.length > 1)
              SizedBox(
                height: 74,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.urls.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final active = i == _current;
                    return InkWell(
                      onTap: () {
                        _controller.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 84,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: active ? Colors.white : Colors.white24,
                            width: active ? 2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(
                          widget.urls[i],
                          fit: BoxFit.cover,
                          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white54,
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
      ),
    );
  }
}

class _ResolvedEvidenceImage extends StatelessWidget {
  final String sourceUrl;

  const _ResolvedEvidenceImage({required this.sourceUrl});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _resolveEvidenceUrl(sourceUrl),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primaryColor,
              ),
            ),
          );
        }

        final resolved = snap.data;
        if (resolved == null || resolved.isEmpty) {
          return const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: hintColor,
              size: 22,
            ),
          );
        }

        return Image.network(
          resolved,
          fit: BoxFit.cover,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primaryColor,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: hintColor,
              size: 22,
            ),
          ),
        );
      },
    );
  }
}

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

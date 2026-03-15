import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../shared/widgets/modern_table_layout.dart';

class MySubmittedCasesPage extends StatefulWidget {
  const MySubmittedCasesPage({super.key});

  @override
  State<MySubmittedCasesPage> createState() => _MySubmittedCasesPageState();
}

class _MySubmittedCasesPageState extends State<MySubmittedCasesPage> {
  // Ã¢Å“â€¦ Same theme as TeacherReportScreen
  static const bg = Colors.white;
  static const primaryColor = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  // Tabs
  int _tab = 0; // 0 = Violation, 1 = Counselling
  String? _filterMonthKey;
  String? _filterStatus;
  String? _selectedId;
  final ScrollController _listScrollController = ScrollController();
  String? _violationStreamUid;
  String? _counselingStreamUid;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _violationReportsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _counselingReportsStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _violationCountSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _counselingCountSub;
  final ValueNotifier<int> _violationCount = ValueNotifier<int>(0);
  final ValueNotifier<int> _counselingCount = ValueNotifier<int>(0);
  final Map<String, Future<String>> _studentProgramFutureCache =
      <String, Future<String>>{};

  @override
  void dispose() {
    _violationCountSub?.cancel();
    _counselingCountSub?.cancel();
    _violationCount.dispose();
    _counselingCount.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _ensureViolationReportsStream(String uid) {
    if (_violationStreamUid == uid && _violationReportsStream != null) return;
    _violationStreamUid = uid;
    _violationReportsStream = FirebaseFirestore.instance
        .collection('violation_cases')
        .where('reportedByUid', isEqualTo: uid)
        .snapshots();
    _violationCountSub?.cancel();
    _violationCountSub = _violationReportsStream!.listen((snapshot) {
      _violationCount.value = snapshot.size;
    });
  }

  void _ensureCounselingReportsStream(String uid) {
    if (_counselingStreamUid == uid && _counselingReportsStream != null) return;
    _counselingStreamUid = uid;
    _counselingReportsStream = FirebaseFirestore.instance
        .collection('counseling_cases')
        .where('referredByUid', isEqualTo: uid)
        .snapshots();
    _counselingCountSub?.cancel();
    _counselingCountSub = _counselingReportsStream!.listen((snapshot) {
      _counselingCount.value = snapshot.size;
    });
  }

  // -------------------------
  // Helpers
  // -------------------------
  DateTime? _tsToDate(dynamic ts) {
    try {
      if (ts == null) return null;
      return (ts as Timestamp).toDate();
    } catch (_) {
      return null;
    }
  }

  String _fmtShort(DateTime d) {
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

  String _fmtLong(DateTime d) {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return "${months[d.month - 1]} ${d.day}, ${d.year}";
  }

  String _fmtTsLong(DateTime d) => DateFormat('MMM d, yyyy - h:mm a').format(d);

  String _monthKey(DateTime d) {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return "${months[d.month - 1]} ${d.year}";
  }

  int _monthSortValue(String key) {
    final parts = key.split(" ");
    if (parts.length != 2) return 0;
    final month = parts[0];
    final year = int.tryParse(parts[1]) ?? 0;

    const map = {
      "January": 1,
      "February": 2,
      "March": 3,
      "April": 4,
      "May": 5,
      "June": 6,
      "July": 7,
      "August": 8,
      "September": 9,
      "October": 10,
      "November": 11,
      "December": 12,
    };
    final m = map[month] ?? 0;
    return year * 100 + m;
  }

  String _titleCase(String s) {
    if (s.trim().isEmpty) return s;
    return s
        .split(' ')
        .where((p) => p.trim().isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  String _str(dynamic value) => (value ?? '').toString().trim();

  List<String> _stringList(dynamic value) {
    if (value is Iterable) {
      return value.map((e) => _str(e)).where((e) => e.isNotEmpty).toList();
    }
    return const <String>[];
  }

  Future<String> _resolveStudentProgram({
    required String studentUid,
    required String fallbackProgram,
  }) {
    final fallback = _str(fallbackProgram);
    if (fallback.isNotEmpty && fallback != 'â€”' && fallback != '--') {
      return Future<String>.value(fallback);
    }

    final uid = _str(studentUid);
    if (uid.isEmpty) {
      return Future<String>.value('â€”');
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
      final fromProfile = _str(
        studentProfile['programId'] ??
            studentProfile['program'] ??
            userData['programId'] ??
            userData['program'],
      );
      return fromProfile.isEmpty ? 'â€”' : fromProfile;
    });
  }

  String _prettyConcern(String? concern) {
    final c = (concern ?? '').toLowerCase().trim();
    if (c == 'basic') return 'Basic';
    if (c == 'serious') return 'Serious';
    if (c == 'moderate') return 'Moderate';
    if (c == 'minor') return 'Minor';
    if (c == 'major') return 'Major';
    return c.isEmpty ? '' : _titleCase(c);
  }

  String _normalizeStatus(String s) {
    final x = s.toLowerCase().trim().replaceAll('_', ' ');
    return x.isEmpty ? 'submitted' : x;
  }

  _ReportStatus _mapStatus(String raw) {
    final s = _normalizeStatus(raw);

    if (s.contains('unresolved')) return _ReportStatus.unresolved;
    if (s.contains('resolved') || s.contains('done'))
      return _ReportStatus.resolved;
    if (s.contains('action') && s.contains('set'))
      return _ReportStatus.actionSet;
    if (s.contains('under review') || s.contains('review'))
      return _ReportStatus.underReview;
    if (s.contains('pending') || s.contains('submitted'))
      return _ReportStatus.pending;
    if (s.contains('rejected') || s.contains('dismiss'))
      return _ReportStatus.rejected;

    return _ReportStatus.pending;
  }

  String _displayStatus(String raw) {
    final s = _normalizeStatus(raw);
    if (s.contains('unresolved')) return 'Unresolved';
    if (s.contains('resolved') || s.contains('done')) return 'Resolved';
    if (s.contains('action') && s.contains('set')) {
      return 'Action Set';
    }
    if (s.contains('under review') || s.contains('review'))
      return 'Under Review';
    if (s.contains('submitted') || s.contains('pending')) return 'Under Review';
    if (s.contains('rejected') || s.contains('dismiss')) return 'Rejected';
    return _titleCase(s);
  }

  String _prettyCounselingType(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'academic') return 'Academic';
    if (s == 'personal') return 'Personal';
    return s.isEmpty ? 'General' : _titleCase(s);
  }

  String _buildCounselingReasonSummary(Map<String, dynamic> reasons) {
    final tags = <String>[];
    if (_stringList(reasons['moodsBehaviors']).isNotEmpty ||
        _str(reasons['otherMood']).isNotEmpty) {
      tags.add('Emotional and Behavior');
    }
    if (_stringList(reasons['schoolConcerns']).isNotEmpty ||
        _str(reasons['otherSchool']).isNotEmpty) {
      tags.add('Academic and School');
    }
    if (_stringList(reasons['relationships']).isNotEmpty ||
        _str(reasons['otherRelationship']).isNotEmpty) {
      tags.add('Peer and Relationship');
    }
    if (_stringList(reasons['homeConcerns']).isNotEmpty ||
        _str(reasons['otherHome']).isNotEmpty) {
      tags.add('Family and Home');
    }
    return tags.isEmpty ? 'No checklist selected' : tags.join(', ');
  }

  Future<void> _openFilters(List<_SubmittedReport> all) async {
    final months = all.map((r) => _monthKey(r.submittedAt)).toSet().toList()
      ..sort((a, b) => _monthSortValue(b).compareTo(_monthSortValue(a)));

    // include a few common statuses + discovered ones
    final discovered = all.map((r) => r.statusText).toSet().toList()..sort();
    final statuses = discovered;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black.withOpacity(0.10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _FilterSheet(
                months: months,
                statuses: statuses,
                selectedMonth: _filterMonthKey,
                selectedStatus: _filterStatus,
                onApply: (m, s) {
                  setState(() {
                    _filterMonthKey = m;
                    _filterStatus = s;
                    _tab = 0;
                  });
                  Navigator.pop(context);
                },
                onClear: () {
                  setState(() {
                    _filterMonthKey = null;
                    _filterStatus = null;
                    _tab = 0;
                  });
                  Navigator.pop(context);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Map<String, List<_SubmittedReport>> _groupByMonth(
    List<_SubmittedReport> list,
  ) {
    final map = <String, List<_SubmittedReport>>{};
    for (final r in list) {
      final k = _monthKey(r.submittedAt);
      (map[k] ??= []).add(r);
    }
    return map;
  }

  String _displayReportCode(_SubmittedReport r) {
    if (r.caseCode.trim().isNotEmpty) return r.caseCode;
    if (r.kind == _ReportKind.counseling) {
      final prefix = r.id.length >= 6 ? r.id.substring(0, 6) : r.id;
      return 'CR-${prefix.toUpperCase()}';
    }
    return r.id;
  }

  String _filterSummary() {
    if (_filterMonthKey == null && _filterStatus == null) return "";
    final parts = <String>[];
    if (_filterMonthKey != null) parts.add(_filterMonthKey!);
    if (_filterStatus != null) parts.add(_filterStatus!);
    return parts.join(" - ");
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null)
      return const Scaffold(body: Center(child: Text('Not logged in.')));
    _ensureViolationReportsStream(uid);
    _ensureCounselingReportsStream(uid);
    final activeStream = _tab == 0
        ? _violationReportsStream
        : _counselingReportsStream;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: activeStream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        final docs = snap.data?.docs;
        if (docs == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = docs.map((doc) {
          final d = doc.data();
          if (_tab == 0) {
            final rawStatus = (d['status'] ?? 'Submitted').toString();
            final incidentAt = _tsToDate(d['incidentAt']);
            final createdAt = _tsToDate(d['createdAt']);
            final submittedAt = createdAt ?? incidentAt ?? DateTime.now();
            final caseCode = _str(d['caseCode']);
            final concern = _prettyConcern(
              (d['concern'] ?? d['reportedConcernType']).toString(),
            );
            final category =
                (d['categoryNameSnapshot'] ??
                        d['reportedCategoryNameSnapshot'] ??
                        d['reportedCategoryName'] ??
                        '')
                    .toString()
                    .trim();
            final violation =
                (d['typeNameSnapshot'] ??
                        d['violationNameSnapshot'] ??
                        d['reportedTypeNameSnapshot'] ??
                        'Violation')
                    .toString()
                    .trim();
            final scheduledAt = _tsToDate(d['scheduledAt']);
            final meetingStatus = _str(d['meetingStatus']);
            final meetingRequired = d['meetingRequired'] == true;
            final finalSeverity = _str(d['finalSeverity']);
            final actionType = _str(d['actionType']);
            final reporterName = _str(d['reportedByName']);
            final reporterRole = _toTitleCaseText(_str(d['reportedByRole']));
            final evidenceUrls = _stringList(d['evidenceUrls']);
            final program = _str(
              d['programId'] ??
                  d['studentProgramId'] ??
                  d['studentProgram'] ??
                  d['program'],
            );

            return _SubmittedReport(
              id: doc.id,
              caseCode: caseCode,
              studentUid: _str(d['studentUid']),
              studentName: _str(d['studentName']),
              studentId: _str(d['studentNo']),
              program: program.isEmpty ? '—' : program,
              concern: concern.isEmpty ? '—' : concern,
              category: category.isEmpty ? '—' : category,
              violation: violation.isEmpty ? 'Violation' : violation,
              incidentAt: incidentAt ?? submittedAt,
              submittedAt: submittedAt,
              location: _str(d['location']).isEmpty ? '—' : _str(d['location']),
              status: _mapStatus(rawStatus),
              statusText: _displayStatus(rawStatus),
              description: _str(d['description']).isEmpty
                  ? '—'
                  : _str(d['description']),
              facultyNote: _str(d['meetingFacultyNote']),
              sanctionType: _str(d['sanctionType']),
              finalSeverity: finalSeverity,
              actionType: actionType,
              meetingRequired: meetingRequired,
              meetingStatus: meetingStatus,
              scheduledAt: scheduledAt,
              meetingLocation: _str(d['meetingLocation']),
              reporterName: reporterName,
              reporterRole: reporterRole,
              evidenceUrls: evidenceUrls,
              kind: _ReportKind.violation,
            );
          }

          final rawStatus = (d['status'] ?? 'Submitted').toString();
          final referralDate = _tsToDate(d['referralDate']);
          final createdAt = _tsToDate(d['createdAt']);
          final submittedAt = createdAt ?? referralDate ?? DateTime.now();
          final counselingType = _prettyCounselingType(
            _str(d['counselingType']),
          );
          final reasons =
              (d['reasons'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final reasonSummary = _buildCounselingReasonSummary(reasons);
          final comments = _str(d['comments']);
          final program = _str(
            d['programId'] ??
                d['studentProgramId'] ??
                d['studentProgram'] ??
                d['program'],
          );

          return _SubmittedReport(
            id: doc.id,
            caseCode: _str(d['caseCode']),
            studentUid: _str(d['studentUid']),
            studentName: _str(d['studentName']),
            studentId: _str(d['studentNo']),
            program: program.isEmpty ? '—' : program,
            concern: 'Counselling Referral',
            category: counselingType.isEmpty ? 'General' : counselingType,
            violation: reasonSummary,
            incidentAt: referralDate ?? submittedAt,
            submittedAt: submittedAt,
            location: '—',
            status: _mapStatus(rawStatus),
            statusText: _displayStatus(rawStatus),
            description: comments.isEmpty ? '—' : comments,
            facultyNote: reasonSummary,
            sanctionType: '',
            finalSeverity: '',
            actionType: '',
            meetingRequired: false,
            meetingStatus: _str(d['meetingStatus']),
            scheduledAt: _tsToDate(d['scheduledAt']),
            meetingLocation: _str(d['meetingLocation']),
            reporterName: _str(d['referredBy']),
            reporterRole: _toTitleCaseText(_str(d['referredByRole'])),
            evidenceUrls: const <String>[],
            kind: _ReportKind.counseling,
          );
        }).toList();
        all.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

        // filter logic
        List<_SubmittedReport> list = all;
        if (_filterMonthKey != null) {
          list = list
              .where((r) => _monthKey(r.submittedAt) == _filterMonthKey)
              .toList();
        }
        if (_filterStatus != null) {
          list = list.where((r) => r.statusText == _filterStatus).toList();
        }

        final grouped = _groupByMonth(list);
        final monthsSorted = grouped.keys.toList()
          ..sort((a, b) => _monthSortValue(b).compareTo(_monthSortValue(a)));
        final desktopWide = MediaQuery.sizeOf(context).width >= 1100;

        if (_selectedId != null && !list.any((r) => r.id == _selectedId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedId = null);
          });
        }
        _SubmittedReport? selectedReport;
        if (_selectedId != null) {
          for (final report in list) {
            if (report.id == _selectedId) {
              selectedReport = report;
              break;
            }
          }
        }
        final shouldShowDesktopSplit = desktopWide;
        final shouldShowDetails =
            shouldShowDesktopSplit && selectedReport != null;

        return Scaffold(
          backgroundColor: bg,
          body: ModernTableLayout(
            header: ModernTableHeader(
              title: 'My Reports',
              subtitle: _tab == 0
                  ? 'View and track your submitted violation cases'
                  : 'View and track your submitted counselling referrals',
              searchBar: const SizedBox(),
              tabs: DefaultTabController(
                length: 2,
                initialIndex: _tab,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: primaryColor,
                  indicatorColor: primaryColor,
                  dividerColor: Colors.transparent,
                  onTap: (index) {
                    if (_tab == index) return;
                    setState(() {
                      _tab = index;
                      _selectedId = null;
                      _filterMonthKey = null;
                      _filterStatus = null;
                    });
                  },
                  tabs: [
                    Tab(
                      child: _buildTabLabelWithCount(
                        'Violation',
                        _violationCount,
                      ),
                    ),
                    Tab(
                      child: _buildTabLabelWithCount(
                        'Counselling',
                        _counselingCount,
                      ),
                    ),
                  ],
                ),
              ),
              filters: [
                _buildFilterChip(
                  'Month',
                  _filterMonthKey ?? 'All',
                  _getAvailableMonths(all),
                  (v) {
                    setState(() => _filterMonthKey = v == 'All' ? null : v);
                  },
                ),
                _buildViolationStatusFilterChip(
                  reports: all,
                  current: _filterStatus,
                  onSelected: (next) {
                    setState(() => _filterStatus = next);
                  },
                ),
              ],
            ),
            body: list.isEmpty
                ? const Center(
                    child: Text(
                      'No reports found.',
                      style: TextStyle(
                        color: hintColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : ListView.builder(
                    key: const PageStorageKey('prof_my_reports_list'),
                    controller: _listScrollController,
                    padding: const EdgeInsets.all(24),
                    itemCount: monthsSorted.length,
                    itemBuilder: (context, i) {
                      final month = monthsSorted[i];
                      final monthReports = grouped[month]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              month.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: hintColor,
                                letterSpacing: 1.5,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          ...monthReports.map((r) {
                            final isSelected = _selectedId == r.id;
                            return _buildReportCard(
                              r,
                              isSelected: isSelected,
                              onTap: () {
                                if (desktopWide) {
                                  setState(
                                    () =>
                                        _selectedId = isSelected ? null : r.id,
                                  );
                                  return;
                                }
                                _openDetails(r);
                              },
                            );
                          }),
                        ],
                      );
                    },
                  ),
            showDetails: shouldShowDetails,
            details: shouldShowDetails
                ? _buildDesktopDetailsPanel(selectedReport)
                : null,
            detailsWidth: 480,
          ),
        );
      },
    );
  }

  List<String> _getAvailableMonths(List<_SubmittedReport> reports) {
    final set = reports.map((r) => _monthKey(r.submittedAt)).toSet().toList();
    set.sort((a, b) => _monthSortValue(b).compareTo(_monthSortValue(a)));
    return ['All', ...set];
  }

  Widget _buildTabLabelWithCount(String label, ValueNotifier<int> counter) {
    return ValueListenableBuilder<int>(
      valueListenable: counter,
      builder: (context, value, _) => Text('$label ($value)'),
    );
  }

  Widget _buildViolationStatusFilterChip({
    required List<_SubmittedReport> reports,
    required String? current,
    required ValueChanged<String?> onSelected,
  }) {
    const orderedStatuses = <String>[
      'Under Review',
      'Action Set',
      'Resolved',
      'Unresolved',
      'Rejected',
    ];

    final counts = <String, int>{for (final key in orderedStatuses) key: 0};
    for (final report in reports) {
      final status = report.statusText;
      if (counts.containsKey(status)) {
        counts[status] = (counts[status] ?? 0) + 1;
      }
    }

    final activeCount = current == null
        ? reports.length
        : (counts[current] ?? 0);
    final currentLabel = current ?? 'All';

    return PopupMenuButton<String>(
      onSelected: (value) => onSelected(value == 'All' ? null : value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'All', child: Text('All')),
        ...orderedStatuses.map(
          (status) => PopupMenuItem(value: status, child: Text(status)),
        ),
      ],
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: current == null
              ? Colors.transparent
              : primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: current == null ? Colors.grey[300]! : primaryColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Filter ($activeCount): $currentLabel',
              style: TextStyle(
                color: current == null ? textDark : primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String current,
    List<String> items,
    ValueChanged<String> onSelected,
  ) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => items
          .map((item) => PopupMenuItem(value: item, child: Text(item)))
          .toList(),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: current == 'All'
              ? Colors.transparent
              : primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: current == 'All' ? Colors.grey[300]! : primaryColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: $current',
              style: TextStyle(
                color: current == 'All' ? textDark : primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(
    _SubmittedReport r, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.black.withOpacity(0.05),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
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
                        _displayReportCode(r),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: primaryColor,
                        ),
                      ),
                      const Spacer(),
                      _buildStatusBadge(r.statusText),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    r.studentName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textDark,
                    ),
                  ),
                  Text(
                    r.kind == _ReportKind.counseling
                        ? 'Counselling | ${r.category}'
                        : '${r.concern} | ${r.violation}',
                    style: const TextStyle(color: hintColor, fontSize: 13),
                  ),
                  Text(
                    _fmtShort(r.submittedAt),
                    style: const TextStyle(color: hintColor, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopDetailsPanel(_SubmittedReport report) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                _caseCodeBadge(_displayReportCode(report)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    report.kind == _ReportKind.counseling
                        ? 'Referral Details'
                        : 'Case Details',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                _buildStatusBadge(report.statusText),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildReadOnlyCaseDetailsBody(report),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetails(_SubmittedReport r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: ListView(
            controller: controller,
            children: [
              Row(
                children: [
                  _caseCodeBadge(_displayReportCode(r)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.kind == _ReportKind.counseling
                          ? 'Referral Details'
                          : 'Case Details',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              _buildReadOnlyCaseDetailsBody(r),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyCaseDetailsBody(_SubmittedReport report) {
    if (report.kind == _ReportKind.counseling) {
      return _buildCounselingDetailsBody(report);
    }

    final isUnderReview =
        report.status == _ReportStatus.pending ||
        report.status == _ReportStatus.underReview;
    final isResolved = report.status == _ReportStatus.resolved;

    if (isUnderReview) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadOnlyDetailCard(
            title: 'Student Information',
            child: Column(
              children: [
                _readOnlyKv('Student', report.studentName),
                const SizedBox(height: 8),
                _readOnlyKv('Student No', report.studentId),
                const SizedBox(height: 8),
                _readOnlyProgramKv(report),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ReadOnlyDetailCard(
            title: 'Incident Summary',
            child: Column(
              children: [
                _readOnlyKv('Concern', report.concern),
                const SizedBox(height: 8),
                _readOnlyKv('Category', report.category),
                const SizedBox(height: 8),
                _readOnlyKv('Violation Type', report.violation),
                const SizedBox(height: 8),
                _readOnlyKv('Date Reported', _fmtLong(report.incidentAt)),
                if (report.reporterName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _readOnlyKv(
                    'Reported By',
                    report.reporterRole.isEmpty
                        ? report.reporterName
                        : '${report.reporterName} (${report.reporterRole})',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ReadOnlyDetailCard(
            title: 'Incident Description',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withOpacity(0.08)),
              ),
              child: Text(
                report.description,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ReadOnlyDetailCard(
            title: 'Evidence',
            child: _buildEvidenceSection(report),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReadOnlyDetailCard(
          title: 'Student Information',
          child: Column(
            children: [
              _readOnlyKv('Student', report.studentName),
              const SizedBox(height: 8),
              _readOnlyKv('Student No', report.studentId),
              const SizedBox(height: 8),
              _readOnlyProgramKv(report),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReadOnlyDetailCard(
          title: 'Incident Summary',
          child: Column(
            children: [
              _readOnlyKv('Concern', report.concern),
              const SizedBox(height: 8),
              _readOnlyKv('Category', report.category),
              const SizedBox(height: 8),
              _readOnlyKv('Violation Type', report.violation),
              const SizedBox(height: 8),
              _readOnlyKv('Date Reported', _fmtLong(report.incidentAt)),
              const SizedBox(height: 8),
              _readOnlyKv('Submitted At', _fmtTsLong(report.submittedAt)),
              if (!isResolved) ...[
                const SizedBox(height: 8),
                _readOnlyKv('Status', report.statusText),
              ],
              if (report.reporterName.isNotEmpty) ...[
                const SizedBox(height: 8),
                _readOnlyKv(
                  'Reported By',
                  report.reporterRole.isEmpty
                      ? report.reporterName
                      : '${report.reporterName} (${report.reporterRole})',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReadOnlyDetailCard(
          title: 'Incident Description',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.08)),
            ),
            child: Text(
              report.description,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ReadOnlyDetailCard(
          title: 'Evidence',
          child: _buildEvidenceSection(report),
        ),
        if (report.finalSeverity.isNotEmpty ||
            report.actionType.isNotEmpty ||
            report.sanctionType.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ReadOnlyDetailCard(
            title: 'Assessment & Decision',
            child: Column(
              children: [
                if (report.finalSeverity.isNotEmpty) ...[
                  _readOnlyKv(
                    'Severity',
                    _toTitleCaseText(report.finalSeverity),
                  ),
                  const SizedBox(height: 8),
                ],
                if (report.actionType.isNotEmpty) ...[
                  _readOnlyKv('Action', _toTitleCaseText(report.actionType)),
                  const SizedBox(height: 8),
                ],
                if (report.sanctionType.isNotEmpty)
                  _readOnlyKv(
                    'Sanction Given',
                    _toTitleCaseText(report.sanctionType),
                  ),
              ],
            ),
          ),
        ],
        if (report.meetingRequired) ...[
          const SizedBox(height: 12),
          _ReadOnlyDetailCard(
            title: 'Meeting Details',
            child: Column(
              children: [
                _readOnlyKv(
                  'Meeting Status',
                  report.meetingStatus.isEmpty
                      ? 'Not set'
                      : _toTitleCaseText(report.meetingStatus),
                ),
                if (report.scheduledAt != null) ...[
                  const SizedBox(height: 8),
                  _readOnlyKv('Scheduled At', _fmtTsLong(report.scheduledAt!)),
                ],
              ],
            ),
          ),
        ],
        if (isResolved && report.facultyNote.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _ReadOnlyDetailCard(
            title: 'OSA Note to Reporter',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withOpacity(0.08)),
              ),
              child: Text(
                report.facultyNote,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCounselingDetailsBody(_SubmittedReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReadOnlyDetailCard(
          title: 'Student Information',
          child: Column(
            children: [
              _readOnlyKv('Student', report.studentName),
              const SizedBox(height: 8),
              _readOnlyKv('Student No', report.studentId),
              const SizedBox(height: 8),
              _readOnlyProgramKv(report),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReadOnlyDetailCard(
          title: 'Referral Summary',
          child: Column(
            children: [
              _readOnlyKv('Referral Type', report.category),
              const SizedBox(height: 8),
              _readOnlyKv('Submitted At', _fmtTsLong(report.submittedAt)),
              const SizedBox(height: 8),
              _readOnlyKv('Status', report.statusText),
              if (report.reporterName.isNotEmpty) ...[
                const SizedBox(height: 8),
                _readOnlyKv(
                  'Referred By',
                  report.reporterRole.isEmpty
                      ? report.reporterName
                      : '${report.reporterName} (${report.reporterRole})',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReadOnlyDetailCard(
          title: 'Notes',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.08)),
            ),
            child: Text(
              report.description,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ReadOnlyDetailCard(
          title: 'Concern Checklist',
          child: _readOnlyKv('Selected Areas', report.facultyNote),
        ),
      ],
    );
  }

  Widget _caseCodeBadge(String caseCode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryColor.withOpacity(0.25)),
      ),
      child: Text(
        caseCode,
        style: const TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _readOnlyKv(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '$label:',
            style: const TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w900,
              fontSize: 12.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? 'â€”' : value,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w700,
              fontSize: 12.8,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _readOnlyProgramKv(_SubmittedReport report) {
    return FutureBuilder<String>(
      future: _resolveStudentProgram(
        studentUid: report.studentUid,
        fallbackProgram: report.program,
      ),
      initialData: report.program,
      builder: (context, snapshot) {
        final program = _str(snapshot.data);
        return _readOnlyKv('Program', program.isEmpty ? 'â€”' : program);
      },
    );
  }

  bool _isLikelyPdf(String url) {
    final u = url.toLowerCase();
    return u.contains('.pdf') ||
        u.contains('application/pdf') ||
        u.contains('contenttype=application%2fpdf');
  }

  Widget _buildEvidenceSection(_SubmittedReport report) {
    final urls = report.evidenceUrls;
    if (urls.isEmpty) {
      return const Text(
        'No evidence attached.',
        style: TextStyle(color: hintColor, fontWeight: FontWeight.w700),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: urls.map((url) {
        final isPdf = _isLikelyPdf(url);
        return InkWell(
          onTap: () => _openEvidencePreview(url, isPdf: isPdf),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 110,
            height: 74,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withOpacity(0.08)),
            ),
            clipBehavior: Clip.antiAlias,
            child: isPdf
                ? const Center(
                    child: Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Color(0xFFB71C1C),
                      size: 28,
                    ),
                  )
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_rounded, color: hintColor),
                    ),
                  ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _openEvidencePreview(String url, {required bool isPdf}) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 900,
          height: 620,
          child: Stack(
            children: [
              Positioned.fill(
                child: isPdf
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.picture_as_pdf_rounded,
                                color: Colors.white,
                                size: 56,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'PDF preview is not available in this panel.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                url,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : InteractiveViewer(
                        maxScale: 5,
                        minScale: 0.8,
                        child: Center(
                          child: Image.network(
                            url,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Text(
                              'Failed to load image',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final s = status.toLowerCase().trim();
    final bool isResolved = s.contains('resolved') && !s.contains('unresolved');
    final bool isUnderReview =
        s.contains('review') ||
        s.contains('submitted') ||
        s.contains('pending');
    final bool isUnresolved = s.contains('unresolved');
    final bool isActionSet =
        s.contains('action set') || s.contains('with meeting');
    final bool isRejected = s.contains('rejected') || s.contains('dismiss');

    Color fill = Colors.black.withOpacity(0.04);
    Color border = Colors.black.withOpacity(0.10);
    Color text = hintColor;

    if (isResolved || isActionSet) {
      fill = primaryColor.withOpacity(0.10);
      border = primaryColor.withOpacity(0.30);
      text = primaryColor;
    } else if (isUnresolved || isRejected) {
      fill = Colors.red.withOpacity(0.10);
      border = Colors.red.withOpacity(0.25);
      text = Colors.red.shade900;
    } else if (isUnderReview) {
      fill = Colors.black.withOpacity(0.04);
      border = Colors.black.withOpacity(0.10);
      text = hintColor;
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        status,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.w900,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

class _ReadOnlyDetailCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ReadOnlyDetailCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1F2A1F),
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ===================== TABS ROW =====================
class _TabsRow extends StatelessWidget {
  final double scale;
  final int tab;
  final bool hasFilter;
  final String filterSummary;

  final VoidCallback onAll;
  final VoidCallback onRecent;
  final VoidCallback onOpenFilter;
  final VoidCallback onClearFilter;

  const _TabsRow({
    required this.scale,
    required this.tab,
    required this.hasFilter,
    required this.filterSummary,
    required this.onAll,
    required this.onRecent,
    required this.onOpenFilter,
    required this.onClearFilter,
  });

  static const primaryColor = Color(0xFF2F6C44);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _TabChip(
                scale: scale,
                label: "All",
                icon: Icons.list_alt_rounded,
                selected: tab == 0,
                onTap: onAll,
              ),
            ),
            SizedBox(width: 10 * scale),
            Expanded(
              child: _TabChip(
                scale: scale,
                label: "Recent",
                icon: Icons.schedule_rounded,
                selected: tab == 1,
                onTap: onRecent,
              ),
            ),
            SizedBox(width: 10 * scale),
            SizedBox(
              height: (44 * scale).clamp(44.0, 52.0),
              child: OutlinedButton.icon(
                onPressed: onOpenFilter,
                icon: const Icon(Icons.filter_alt_rounded),
                label: const Text("Filter"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor.withOpacity(0.35)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  textStyle: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: (12.8 * scale).clamp(12.8, 14.2),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (hasFilter) ...[
          SizedBox(height: 10 * scale),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: 12 * scale,
              vertical: 10 * scale,
            ),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16 * scale),
              border: Border.all(color: primaryColor.withOpacity(0.22)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.filter_alt_rounded,
                  color: primaryColor,
                  size: 18,
                ),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: Text(
                    filterSummary,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: (12.6 * scale).clamp(12.6, 14.0),
                      color: const Color(0xFF243024),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onClearFilter,
                  style: TextButton.styleFrom(foregroundColor: primaryColor),
                  child: const Text(
                    "Clear",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  final double scale;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.scale,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  static const primaryColor = Color(0xFF2F6C44);
  static const textDark = Color(0xFF243024);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: (44 * scale).clamp(44.0, 52.0),
        padding: EdgeInsets.symmetric(horizontal: 12 * scale),
        decoration: BoxDecoration(
          color: selected ? primaryColor.withOpacity(0.14) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? primaryColor.withOpacity(0.50)
                : Colors.black.withOpacity(0.12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? primaryColor : textDark),
            SizedBox(width: 8 * scale),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? primaryColor : textDark,
                  fontWeight: FontWeight.w900,
                  fontSize: (12.8 * scale).clamp(12.8, 14.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== MONTH HEADER =====================
class _MonthHeader extends StatelessWidget {
  final double scale;
  final String title;
  final int count;

  const _MonthHeader({
    required this.scale,
    required this.title,
    required this.count,
  });

  static const primaryColor = Color(0xFF2F6C44);
  static const hintColor = Color(0xFF5B665B);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              fontSize: (12.6 * scale).clamp(12.6, 14.2),
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: 10 * scale,
            vertical: 6 * scale,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.75),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.black.withOpacity(0.10)),
          ),
          child: Text(
            "$count",
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w900,
              fontSize: (12.0 * scale).clamp(12.0, 13.6),
            ),
          ),
        ),
      ],
    );
  }
}

// Ã¢Å“â€¦ Wrap layout (no Grid overflow)
class _ReportsWrap extends StatelessWidget {
  final double scale;
  final int crossAxisCount;
  final List<_SubmittedReport> items;

  const _ReportsWrap({
    required this.scale,
    required this.crossAxisCount,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final gap = 12.0 * scale;

    return LayoutBuilder(
      builder: (context, c) {
        final cols = crossAxisCount.clamp(1, 3);
        final itemW = (c.maxWidth - gap * (cols - 1)) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final r in items)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: itemW),
                child: _ReportCard(scale: scale, report: r),
              ),
          ],
        );
      },
    );
  }
}

// ===================== REPORT CARD =====================
class _ReportCard extends StatelessWidget {
  final double scale;
  final _SubmittedReport report;

  const _ReportCard({required this.scale, required this.report});

  static const primaryColor = Color(0xFF2F6C44);
  static const textDark = Color(0xFF243024);
  static const hintColor = Color(0xFF5B665B);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18 * scale),
      onTap: () => _openDetails(context),
      child: Container(
        padding: EdgeInsets.all(12 * scale),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.78),
          borderRadius: BorderRadius.circular(18 * scale),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10 * scale,
              height: 10 * scale,
              margin: EdgeInsets.only(top: 4 * scale),
              decoration: BoxDecoration(
                color: report.status.dotColor,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 10 * scale),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.studentName.isEmpty
                        ? "Ã¢â‚¬â€"
                        : report.studentName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: (13.8 * scale).clamp(13.8, 15.8),
                    ),
                  ),
                  SizedBox(height: 4 * scale),

                  Text(
                    report.violation,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w900,
                      fontSize: (12.8 * scale).clamp(12.8, 14.6),
                    ),
                  ),

                  SizedBox(height: 8 * scale),

                  Wrap(
                    spacing: 10 * scale,
                    runSpacing: 8 * scale,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        "Submitted: ${_fmtShort(report.submittedAt)}",
                        style: TextStyle(
                          color: hintColor,
                          fontWeight: FontWeight.w800,
                          fontSize: (12.0 * scale).clamp(12.0, 13.6),
                        ),
                      ),
                      _StatusPill(
                        scale: scale,
                        status: report.status,
                        label: report.statusText,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.black45),
          ],
        ),
      ),
    );
  }

  void _openDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: EdgeInsets.all(16 * scale),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Report Details",
                        style: TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: (16.0 * scale).clamp(16.0, 18.0),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _detailRow(
                  "Case Code",
                  report.caseCode.isNotEmpty
                      ? report.caseCode
                      : report.kind == _ReportKind.counseling
                      ? 'CR-${(report.id.length >= 6 ? report.id.substring(0, 6) : report.id).toUpperCase()}'
                      : report.id,
                ),
                _detailRow("Student", report.studentName),
                _detailRow("Student No", report.studentId),
                _detailRow("Program", report.program),
                _detailRow("Concern", report.concern),
                _detailRow("Category", report.category),
                _detailRow("Specific Violation", report.violation),
                _detailRow("Location", report.location),
                _detailRow("Incident Date", _fmtLong(report.incidentAt)),
                _detailRow("Submitted At", _fmtTsLong(report.submittedAt)),
                _detailRow("Status", report.statusText),
                if (report.sanctionType.trim().isNotEmpty)
                  _detailRow(
                    "Sanction Type",
                    _toTitleCaseText(report.sanctionType),
                  ),
                const SizedBox(height: 10),
                Text(
                  "Description",
                  style: TextStyle(
                    color: hintColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black.withOpacity(0.10)),
                  ),
                  child: Text(
                    report.description,
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (report.facultyNote.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    "OSA Note to Faculty",
                    style: TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black.withOpacity(0.10)),
                    ),
                    child: Text(
                      report.facultyNote,
                      style: TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      "Close",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: (120 * scale).clamp(120.0, 150.0),
            child: Text(
              label,
              style: TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w900,
                fontSize: (12.4 * scale).clamp(12.4, 14.0),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? "Ã¢â‚¬â€" : value,
              style: TextStyle(
                color: textDark,
                fontWeight: FontWeight.w800,
                fontSize: (12.6 * scale).clamp(12.6, 14.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtShort(DateTime d) {
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

  static String _fmtLong(DateTime d) {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return "${months[d.month - 1]} ${d.day}, ${d.year}";
  }

  static String _fmtTsLong(DateTime d) =>
      DateFormat('MMM d, yyyy - h:mm a').format(d);
}

// ===================== STATUS PILL =====================
class _StatusPill extends StatelessWidget {
  final double scale;
  final _ReportStatus status;
  final String label;

  const _StatusPill({
    required this.scale,
    required this.status,
    required this.label,
  });

  static const textDark = Color(0xFF243024);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 120 * scale),
      padding: EdgeInsets.symmetric(
        horizontal: 10 * scale,
        vertical: 6 * scale,
      ),
      decoration: BoxDecoration(
        color: status.dotColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.dotColor.withOpacity(0.28)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textDark,
          fontWeight: FontWeight.w900,
          fontSize: (11.8 * scale).clamp(11.8, 13.2),
        ),
      ),
    );
  }
}

// ===================== EMPTY STATES =====================
class _EmptyState extends StatelessWidget {
  final double scale;
  const _EmptyState({required this.scale});

  static const hintColor = Color(0xFF5B665B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.description_outlined,
            size: (34 * scale).clamp(34.0, 40.0),
            color: Colors.black45,
          ),
          SizedBox(height: 8 * scale),
          Text(
            "You havenÃ¢â‚¬â„¢t submitted any reports yet.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w900,
              fontSize: (13.0 * scale).clamp(13.0, 15.0),
            ),
          ),
          SizedBox(height: 4 * scale),
          Text(
            "Reports you submit will appear here for tracking and reference.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
              fontSize: (12.2 * scale).clamp(12.2, 14.0),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFilteredState extends StatelessWidget {
  final double scale;
  const _EmptyFilteredState({required this.scale});

  static const hintColor = Color(0xFF5B665B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_off_rounded,
            size: (34 * scale).clamp(34.0, 40.0),
            color: Colors.black45,
          ),
          SizedBox(height: 8 * scale),
          Text(
            "No reports match your filter.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w900,
              fontSize: (13.0 * scale).clamp(13.0, 15.0),
            ),
          ),
          SizedBox(height: 4 * scale),
          Text(
            "Try clearing the filters to see all reports.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
              fontSize: (12.2 * scale).clamp(12.2, 14.0),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== FILTER SHEET =====================
class _FilterSheet extends StatefulWidget {
  final List<String> months;
  final List<String> statuses;
  final String? selectedMonth;
  final String? selectedStatus;

  final void Function(String? month, String? status) onApply;
  final VoidCallback onClear;

  const _FilterSheet({
    required this.months,
    required this.statuses,
    required this.selectedMonth,
    required this.selectedStatus,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const primaryColor = Color(0xFF2F6C44);
  static const textDark = Color(0xFF243024);
  static const hintColor = Color(0xFF5B665B);

  String? _month;
  String? _status;

  @override
  void initState() {
    super.initState();
    _month = widget.selectedMonth;
    _status = widget.selectedStatus;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                "Filter Reports",
                style: TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "By Month",
            style: TextStyle(color: hintColor, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PickChip(
              label: "Any",
              selected: _month == null,
              onTap: () => setState(() => _month = null),
            ),
            for (final m in widget.months)
              _PickChip(
                label: m,
                selected: _month == m,
                onTap: () => setState(() => _month = m),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "By Status",
            style: TextStyle(color: hintColor, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PickChip(
              label: "Any",
              selected: _status == null,
              onTap: () => setState(() => _status = null),
            ),
            for (final s in widget.statuses)
              _PickChip(
                label: s,
                selected: _status == s,
                onTap: () => setState(() => _status = s),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onClear,
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor.withOpacity(0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  "Clear",
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => widget.onApply(_month, _status),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  "Apply",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PickChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const primaryColor = Color(0xFF2F6C44);
  static const textDark = Color(0xFF243024);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? primaryColor.withOpacity(0.14) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? primaryColor.withOpacity(0.50)
                : Colors.black.withOpacity(0.12),
          ),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? primaryColor : textDark,
            fontWeight: FontWeight.w900,
            fontSize: 12.8,
          ),
        ),
      ),
    );
  }
}

String _toTitleCaseText(String value) {
  final s = value.trim();
  if (s.isEmpty) return s;
  return s
      .split(RegExp(r'[\s_-]+'))
      .where((e) => e.isNotEmpty)
      .map((e) => '${e[0].toUpperCase()}${e.substring(1).toLowerCase()}')
      .join(' ');
}

// ===================== MODELS =====================
enum _ReportStatus {
  pending,
  underReview,
  actionSet,
  unresolved,
  resolved,
  rejected,
}

extension _ReportStatusX on _ReportStatus {
  Color get dotColor {
    switch (this) {
      case _ReportStatus.pending:
        return const Color(0xFFE6B800);
      case _ReportStatus.underReview:
        return const Color(0xFF2B7BBB);
      case _ReportStatus.actionSet:
        return const Color(0xFF2E8B57);
      case _ReportStatus.unresolved:
        return const Color(0xFFB23B3B);
      case _ReportStatus.resolved:
        return const Color(0xFF2E8B57);
      case _ReportStatus.rejected:
        return const Color(0xFFB23B3B);
    }
  }
}

enum _ReportKind { violation, counseling }

class _SubmittedReport {
  final String id;
  final String caseCode;
  final String studentUid;
  final String studentName;
  final String studentId;
  final String program;
  final String concern;
  final String category;
  final String violation;
  final DateTime incidentAt;
  final DateTime submittedAt;
  final String location;
  final String description;
  final String facultyNote;
  final String sanctionType;
  final String finalSeverity;
  final String actionType;
  final bool meetingRequired;
  final String meetingStatus;
  final DateTime? scheduledAt;
  final String meetingLocation;
  final String reporterName;
  final String reporterRole;
  final List<String> evidenceUrls;
  final _ReportKind kind;
  final _ReportStatus status;
  final String statusText;

  const _SubmittedReport({
    required this.id,
    required this.caseCode,
    required this.studentUid,
    required this.studentName,
    required this.studentId,
    required this.program,
    required this.concern,
    required this.category,
    required this.violation,
    required this.incidentAt,
    required this.submittedAt,
    required this.location,
    required this.description,
    required this.facultyNote,
    required this.sanctionType,
    required this.finalSeverity,
    required this.actionType,
    required this.meetingRequired,
    required this.meetingStatus,
    required this.scheduledAt,
    required this.meetingLocation,
    required this.reporterName,
    required this.reporterRole,
    required this.evidenceUrls,
    required this.kind,
    required this.status,
    required this.statusText,
  });
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../shared/widgets/modern_table_layout.dart';

class MySubmittedCasesPage extends StatefulWidget {
  final bool showCounselingTab;
  final VoidCallback? onOpenViolationReport;
  final VoidCallback? onOpenCounselingReferral;

  const MySubmittedCasesPage({
    super.key,
    this.showCounselingTab = true,
    this.onOpenViolationReport,
    this.onOpenCounselingReferral,
  });

  @override
  State<MySubmittedCasesPage> createState() => _MySubmittedCasesPageState();
}

class _MySubmittedCasesPageState extends State<MySubmittedCasesPage> {
  // ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Same theme as TeacherReportScreen
  static const bg = Colors.white;
  static const primaryColor = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  // Tabs
  int _tab = 0; // 0 = Violation, 1 = Counselling
  String? _filterMonthKey;
  String? _filterStatus;
  String _statusFilterKey = 'all';
  String? _selectedId;
  String _searchQuery = '';
  bool _isRefreshingTable = false;
  final TextEditingController _searchCtrl = TextEditingController();
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
  final Map<String, Future<String>> _studentPhotoFutureCache =
      <String, Future<String>>{};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastViolationDocs =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastCounselingDocs =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  bool _violationReportsLoaded = false;
  bool _counselingReportsLoaded = false;
  Object? _violationReportsError;
  Object? _counselingReportsError;

  @override
  void dispose() {
    _violationCountSub?.cancel();
    _counselingCountSub?.cancel();
    _violationCount.dispose();
    _counselingCount.dispose();
    _searchCtrl.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _ensureViolationReportsStream(String uid) {
    if (_violationStreamUid == uid && _violationReportsStream != null) return;
    _violationStreamUid = uid;
    _lastViolationDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    _violationReportsLoaded = false;
    _violationReportsError = null;
    _violationCount.value = 0;
    _violationReportsStream = FirebaseFirestore.instance
        .collection('violation_cases')
        .where('reportedByUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots();
    _violationCountSub?.cancel();
    _violationCountSub = _violationReportsStream!.listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _lastViolationDocs = snapshot.docs;
          _violationReportsLoaded = true;
          _violationReportsError = null;
          _violationCount.value = snapshot.size;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _violationReportsLoaded = true;
          _violationReportsError = error;
        });
      },
    );
  }

  void _ensureCounselingReportsStream(String uid) {
    if (_counselingStreamUid == uid && _counselingReportsStream != null) return;
    _counselingStreamUid = uid;
    _lastCounselingDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    _counselingReportsLoaded = false;
    _counselingReportsError = null;
    _counselingCount.value = 0;
    _counselingReportsStream = FirebaseFirestore.instance
        .collection('counseling_cases')
        .where('referralReporterUids', arrayContains: uid)
        .snapshots();
    _counselingCountSub?.cancel();
    _counselingCountSub = _counselingReportsStream!.listen(
      (snapshot) {
        final scopedDocs = snapshot.docs.where((doc) {
          return _isProfessorCounselingReportForUser(doc.data(), uid);
        }).toList(growable: false);
        if (!mounted) return;
        setState(() {
          _lastCounselingDocs = scopedDocs;
          _counselingReportsLoaded = true;
          _counselingReportsError = null;
          _counselingCount.value = scopedDocs.length;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _counselingReportsLoaded = true;
          _counselingReportsError = error;
        });
      },
    );
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

  bool _isProfessorCounselingReportForUser(
    Map<String, dynamic> data,
    String uid,
  ) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return false;

    if (_str(data['studentUid']) == normalizedUid) {
      return true;
    }

    if (_str(data['referredByUid']) == normalizedUid &&
        _str(data['referredByRole']).toLowerCase().trim() == 'professor') {
      return true;
    }

    if (_stringList(data['referralReporterUids']).contains(normalizedUid)) {
      return true;
    }

    final entries = data['referralEntries'];
    if (entries is Iterable) {
      for (final entry in entries.whereType<Map>()) {
        final mapped = entry.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        if (_str(mapped['referredByUid']) == normalizedUid &&
            _str(mapped['referredByRole']).toLowerCase().trim() ==
                'professor') {
          return true;
        }
      }
    }

    return false;
  }

  Future<String> _resolveStudentProgram({
    required String studentUid,
    required String fallbackProgram,
  }) {
    final fallback = _str(fallbackProgram);
    if (fallback.isNotEmpty && fallback != '--') {
      return Future<String>.value(fallback);
    }

    final uid = _str(studentUid);
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
      final fromProfile = _str(
        studentProfile['programId'] ??
            studentProfile['program'] ??
            userData['programId'] ??
            userData['program'],
      );
      return fromProfile.isEmpty ? '--' : fromProfile;
    });
  }

  Future<String> _resolveImageSourceUrl(String source) async {
    final value = _str(source);
    if (value.isEmpty) return '';
    final isHttp = value.startsWith('http://') || value.startsWith('https://');
    if (isHttp) return value;
    try {
      if (value.startsWith('gs://')) {
        return await FirebaseStorage.instance
            .refFromURL(value)
            .getDownloadURL();
      }
      return await FirebaseStorage.instance.ref(value).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  Future<String> _resolveStudentPhotoUrl(String studentUid) {
    final uid = _str(studentUid);
    if (uid.isEmpty) return Future<String>.value('');
    return _studentPhotoFutureCache.putIfAbsent(uid, () async {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data() ?? const <String, dynamic>{};
      final studentProfile =
          userData['studentProfile'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final employeeProfile =
          userData['employeeProfile'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final source = _str(
        userData['photoUrl'] ??
            userData['profilePhotoUrl'] ??
            studentProfile['photoUrl'] ??
            studentProfile['profilePhotoUrl'] ??
            employeeProfile['photoUrl'] ??
            employeeProfile['profilePhotoUrl'],
      );
      return _resolveImageSourceUrl(source);
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

  String _prettyCounselingSource(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'student') return 'Self-referral';
    if (s == 'professor') return 'Professor referral';
    return s.isEmpty ? 'Unknown' : _titleCase(s.replaceAll('_', ' '));
  }

  List<Map<String, dynamic>> _referralEntryList(dynamic value) {
    if (value is! Iterable) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map(
          (entry) => entry.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList(growable: false);
  }

  Map<String, dynamic> _stringKeyedMap(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  DateTime? _latestReferralEntryDate(List<Map<String, dynamic>> entries) {
    DateTime? latest;
    for (final entry in entries) {
      final submittedAt = _tsToDate(entry['submittedAt']);
      if (submittedAt == null) continue;
      if (latest == null || submittedAt.isAfter(latest)) {
        latest = submittedAt;
      }
    }
    return latest;
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

  static const List<String> _statusFilterOrder = <String>[
    'all',
    'under_review',
    'action_set',
    'unresolved',
    'resolved',
    'rejected',
  ];

  static const Map<String, String> _statusFilterLabels = <String, String>{
    'all': 'All',
    'under_review': 'Under Review',
    'action_set': 'Action Set',
    'unresolved': 'Unresolved',
    'resolved': 'Resolved',
    'rejected': 'Rejected',
  };

  Future<void> _refreshCurrentTable() async {
    if (_isRefreshingTable) return;
    setState(() => _isRefreshingTable = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _isRefreshingTable = false);
  }

  void _onSearchInputChanged(String value) {
    final normalized = value.trim().toLowerCase();
    if (_searchQuery == normalized) return;
    setState(() {
      _searchQuery = normalized;
      _selectedId = null;
    });
  }

  void _clearSearchQuery() {
    if (_searchCtrl.text.isEmpty && _searchQuery.isEmpty) return;
    _searchCtrl.clear();
    setState(() {
      _searchQuery = '';
      _selectedId = null;
    });
  }

  bool _matchesSearch(_SubmittedReport report) {
    final controllerQuery = _searchCtrl.text.trim().toLowerCase();
    final needle = controllerQuery.isEmpty ? _searchQuery : controllerQuery;
    if (needle.isEmpty) return true;
    final haystack = <String>[
      _displayReportCode(report),
      report.studentName,
      report.studentId,
      report.program,
      report.concern,
      report.category,
      report.violation,
      report.referralSource,
      report.reporterName,
      report.statusText,
      _fmtShort(report.submittedAt),
    ].join(' ').toLowerCase();
    return haystack.contains(needle);
  }

  String _statusKeyForReport(_SubmittedReport report) {
    switch (report.status) {
      case _ReportStatus.actionSet:
        return 'action_set';
      case _ReportStatus.unresolved:
        return 'unresolved';
      case _ReportStatus.resolved:
        return 'resolved';
      case _ReportStatus.rejected:
        return 'rejected';
      case _ReportStatus.pending:
      case _ReportStatus.underReview:
        return 'under_review';
    }
  }

  bool _matchesStatusFilter(_SubmittedReport report, String statusKey) {
    if (statusKey == 'all') return true;
    return _statusKeyForReport(report) == statusKey;
  }

  Map<String, int> _statusFilterCounts(List<_SubmittedReport> reports) {
    final counts = <String, int>{for (final key in _statusFilterOrder) key: 0};
    for (final report in reports) {
      final key = _statusKeyForReport(report);
      counts[key] = (counts[key] ?? 0) + 1;
      counts['all'] = (counts['all'] ?? 0) + 1;
    }
    return counts;
  }

  Widget _buildStatusFilterBar(Map<String, int> counts) {
    Widget chip(String key) {
      final selected = _statusFilterKey == key;
      final label = _statusFilterLabels[key] ?? key;
      final count = counts[key] ?? 0;
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (_statusFilterKey == key) return;
          setState(() {
            _statusFilterKey = key;
            _selectedId = null;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? primaryColor.withOpacity(0.12) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? primaryColor.withOpacity(0.36)
                  : Colors.black.withOpacity(0.10),
            ),
          ),
          child: Text(
            '$label ($count)',
            style: TextStyle(
              color: selected ? primaryColor : textDark,
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
          children: [
            for (int i = 0; i < _statusFilterOrder.length; i++) ...[
              chip(_statusFilterOrder[i]),
              if (i != _statusFilterOrder.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHandbookStyleSearchBar({
    bool shouldConstrainWidth = true,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final constrainedWidth = width >= 1500
        ? 660.0
        : width >= 1300
        ? 580.0
        : 520.0;
    final height = isDesktop ? 56.0 : 48.0;
    final borderRadius = isDesktop ? 16.0 : 18.0;
    final iconSize = isDesktop ? 24.0 : 22.0;
    final fontSize = isDesktop ? 15.0 : 13.5;

    final searchField = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchCtrl,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.75),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.black12),
            boxShadow: isDesktop
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: hintColor, size: iconSize),
              SizedBox(width: isDesktop ? 12 : 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchInputChanged,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search case, student, violation, date...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
              if (hasText)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: _clearSearchQuery,
                  icon: Icon(
                    Icons.close_rounded,
                    color: hintColor.withOpacity(0.85),
                    size: isDesktop ? 20 : 18,
                  ),
                ),
            ],
          ),
        );
      },
    );

    final refreshButton = Tooltip(
      message: 'Refresh table',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _isRefreshingTable ? null : _refreshCurrentTable,
        child: Container(
          width: height,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.75),
            border: Border.all(color: Colors.black12),
            boxShadow: isDesktop
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: _isRefreshingTable
              ? SizedBox(
                  width: isDesktop ? 18 : 16,
                  height: isDesktop ? 18 : 16,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: hintColor,
                  ),
                )
              : Icon(
                  Icons.refresh_rounded,
                  color: hintColor.withOpacity(0.9),
                  size: isDesktop ? 20 : 18,
                ),
        ),
      ),
    );

    Widget searchWithRefresh() {
      final mobileActions = !isDesktop ? _buildMobileReportActionButtons() : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 8),
              refreshButton,
            ],
          ),
          if (mobileActions != null) ...[
            const SizedBox(height: 10),
            mobileActions,
          ],
        ],
      );
    }

    if (!shouldConstrainWidth || !isDesktop) return searchWithRefresh();
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: constrainedWidth, child: searchWithRefresh()),
    );
  }

  Widget? _buildFullHeaderActions({
    required bool useCompactHeaderActions,
  }) {
    if (useCompactHeaderActions) return null;
    if (widget.onOpenViolationReport == null &&
        widget.onOpenCounselingReferral == null) {
      return null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onOpenViolationReport != null) ...[
          FilledButton.icon(
            onPressed: widget.onOpenViolationReport,
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 1,
            ),
            icon: const Icon(Icons.report_rounded, size: 20),
            label: const Text(
              'Report Violation',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (widget.onOpenCounselingReferral != null)
          OutlinedButton.icon(
            onPressed: widget.onOpenCounselingReferral,
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryColor,
              side: BorderSide(color: primaryColor.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.support_agent_rounded, size: 20),
            label: const Text(
              'Counselling Referral',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
      ],
    );
  }

  Widget? _buildMobileReportActionButtons() {
    if (widget.onOpenViolationReport == null &&
        widget.onOpenCounselingReferral == null) {
      return null;
    }

    if (widget.onOpenViolationReport != null &&
        widget.onOpenCounselingReferral != null) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: widget.onOpenViolationReport,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 1,
              ),
              icon: const Icon(Icons.report_rounded, size: 18),
              label: const Text(
                'Report Violation',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onOpenCounselingReferral,
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: primaryColor.withValues(alpha: 0.35)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.support_agent_rounded, size: 18),
              label: const Text(
                'Counselling Referral',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.onOpenViolationReport != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: widget.onOpenViolationReport,
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 1,
          ),
          icon: const Icon(Icons.report_rounded, size: 18),
          label: const Text(
            'Report Violation',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: widget.onOpenCounselingReferral,
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 1,
        ),
        icon: const Icon(Icons.support_agent_rounded, size: 18),
        label: const Text(
          'Counselling Referral',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not logged in.')));
    }
    if (!widget.showCounselingTab && _tab != 0) {
      _tab = 0;
    }
    _ensureViolationReportsStream(uid);
    if (widget.showCounselingTab) {
      _ensureCounselingReportsStream(uid);
    }
    final showingCounseling = widget.showCounselingTab && _tab == 1;
    final activeError = showingCounseling
        ? _counselingReportsError
        : _violationReportsError;
    final isInitialLoading = showingCounseling
        ? !_counselingReportsLoaded
        : !_violationReportsLoaded;
    final sourceDocs = showingCounseling
        ? _lastCounselingDocs
        : _lastViolationDocs;
    final all = sourceDocs.map<_SubmittedReport?>((doc) {
          final d = doc.data();
          if (!showingCounseling) {
            final rawStatus = (d['status'] ?? 'Submitted').toString();
            final incidentAt = _tsToDate(d['incidentAt']);
            final createdAt = _tsToDate(d['createdAt']);
            if (incidentAt == null || createdAt == null) return null;
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
              program: program.isEmpty ? 'â€”' : program,
              concern: concern.isEmpty ? 'â€”' : concern,
              category: category.isEmpty ? 'â€”' : category,
              violation: violation.isEmpty ? 'Violation' : violation,
              incidentAt: incidentAt,
              submittedAt: createdAt,
              location: _str(d['location']).isEmpty
                  ? 'â€”'
                  : _str(d['location']),
              status: _mapStatus(rawStatus),
              statusText: _displayStatus(rawStatus),
              description: _str(d['description']).isEmpty
                  ? 'â€”'
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
              referralSource: '',
              referralEntries: const <Map<String, dynamic>>[],
              evidenceUrls: evidenceUrls,
              kind: _ReportKind.violation,
            );
          }

          final rawStatus = (d['status'] ?? 'Submitted').toString();
          final referralEntries = _referralEntryList(d['referralEntries']);
          final entrySubmittedAt = _latestReferralEntryDate(referralEntries);
          final referralDate = _tsToDate(d['referralDate']);
          final latestReferralAt = _tsToDate(d['latestReferralAt']);
          final createdAt = _tsToDate(d['createdAt']);
          final updatedAt = _tsToDate(d['updatedAt']);
          final localFallbackDate = DateTime.now();
          final submittedAt =
              createdAt ??
              latestReferralAt ??
              referralDate ??
              entrySubmittedAt ??
              updatedAt ??
              localFallbackDate;
          final incidentAt =
              referralDate ??
              latestReferralAt ??
              entrySubmittedAt ??
              createdAt ??
              updatedAt ??
              submittedAt;
          final counselingType = _prettyCounselingType(
            _str(d['counselingType']),
          );
          final referralSource = _prettyCounselingSource(
            _str(d['referralSource']),
          );
          final reasons = _stringKeyedMap(d['reasons']);
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
            program: program.isEmpty ? 'â€”' : program,
            concern: 'Counselling Referral',
            category: counselingType.isEmpty ? 'General' : counselingType,
            violation: reasonSummary,
            incidentAt: incidentAt,
            submittedAt: submittedAt,
            location: 'â€”',
            status: _mapStatus(rawStatus),
            statusText: _displayStatus(rawStatus),
            description: comments.isEmpty ? 'â€”' : comments,
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
            referralSource: referralSource,
            referralEntries: referralEntries,
            evidenceUrls: const <String>[],
            kind: _ReportKind.counseling,
          );
        }).whereType<_SubmittedReport>().toList();
        all.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

        final roleScoped = all;
        final effectiveSearch = _searchCtrl.text.trim().toLowerCase();
        final searched = effectiveSearch.isEmpty
            ? roleScoped
            : roleScoped.where(_matchesSearch).toList(growable: false);
        final filtered = searched;

        final viewportWidth = MediaQuery.sizeOf(context).width;
        final desktopWide = viewportWidth >= 900;
        final detailsPaneWidth = (viewportWidth * 0.33)
            .clamp(320.0, 420.0)
            .toDouble();

        if (_selectedId != null &&
            !filtered.any((report) => report.id == _selectedId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedId = null);
          });
        }
        _SubmittedReport? selectedReport;
        if (_selectedId != null) {
          for (final report in filtered) {
            if (report.id == _selectedId) {
              selectedReport = report;
              break;
            }
          }
        }
        final shouldShowDetails = desktopWide && selectedReport != null;

        return Scaffold(
          backgroundColor: bg,
          body: ModernTableLayout(
            detailsWidth: detailsPaneWidth,
            header: ModernTableHeader(
              showTitleSection: false,
              showTopControlsWhenTitleHidden: true,
              showSearchBar: true,
              searchBar: _buildHandbookStyleSearchBar(),
              action: _buildFullHeaderActions(
                useCompactHeaderActions: viewportWidth < 900,
              ),
              tabs: DefaultTabController(
                length: widget.showCounselingTab ? 2 : 1,
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
                      _searchCtrl.clear();
                      _searchQuery = '';
                    });
                  },
                  tabs: [
                    Tab(
                      child: _buildTabLabelWithCount(
                        'Violation',
                        _violationCount,
                      ),
                    ),
                    if (widget.showCounselingTab)
                      Tab(
                        child: _buildTabLabelWithCount(
                          'Counselling',
                          _counselingCount,
                        ),
                      ),
                  ],
                ),
              ),
              filters: const [],
            ),
            body: Column(
              children: [
                Expanded(
                  child: activeError != null
                      ? _buildReportsErrorContent(activeError)
                      : isInitialLoading
                      ? _buildReportsLoadingContent(showingCounseling)
                      : _buildReportsContent(
                          reports: filtered,
                          desktopWide: desktopWide,
                          showingCounseling: showingCounseling,
                        ),
                ),
              ],
            ),
            showDetails: shouldShowDetails,
            details: shouldShowDetails
                ? _buildDesktopDetailsPanel(selectedReport)
                : null,
          ),
        );
  }

  Widget _buildReportsErrorContent(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Error: $error',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildReportsLoadingContent(bool showingCounseling) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            showingCounseling
                ? 'Loading counseling referrals...'
                : 'Loading violation reports...',
            style: const TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsContent({
    required List<_SubmittedReport> reports,
    required bool desktopWide,
    required bool showingCounseling,
  }) {
    if (reports.isEmpty) {
      final isCounselingTab = widget.showCounselingTab && _tab == 1;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCounselingTab
                  ? Icons.support_agent_outlined
                  : Icons.inbox_outlined,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              isCounselingTab
                  ? 'No counseling referrals found'
                  : 'No cases found',
              style: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (!desktopWide) {
      return ListView.builder(
        key: const PageStorageKey('prof_my_reports_cards'),
        controller: _listScrollController,
        padding: const EdgeInsets.all(14),
        itemCount: reports.length,
        itemBuilder: (context, index) {
          final report = reports[index];
          final isSelected = _selectedId == report.id;
          final dateText = _fmtShort(report.submittedAt);
          final subtitle = report.kind == _ReportKind.counseling
              ? '${report.referralSource.isEmpty ? 'Counselling' : report.referralSource} | ${report.category}'
              : report.violation;

          return GestureDetector(
            onTap: () {
              setState(() => _selectedId = report.id);
              _openDetails(report);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor.withOpacity(0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? primaryColor
                      : Colors.black.withOpacity(0.05),
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
                            Expanded(
                              child: Text(
                                _displayReportCode(report),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                            Text(
                              dateText,
                              style: const TextStyle(
                                fontSize: 12,
                                color: hintColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          report.studentName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildConcernBadge(report.concern),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                subtitle,
                                style: const TextStyle(
                                  color: hintColor,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          );
        },
      );
    }

    if (showingCounseling) {
      return _buildCounselingReportsTable(reports);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = constraints.maxWidth.toDouble();
              final detailsOpen = _selectedId != null;
              final compactTable = detailsOpen || tableWidth < 1120;
              final tableHorizontalMargin = compactTable ? 8.0 : 12.0;
              final tableColumnSpacing = compactTable ? 12.0 : 18.0;
              final totalWeight = 1.15 + 2.35 + 1.40 + 2.35 + 1.20 + 1.35;
              final usableWidth =
                  (tableWidth -
                          (tableHorizontalMargin * 2) -
                          (tableColumnSpacing * (6 - 1)))
                      .clamp(420.0, double.infinity)
                      .toDouble();

              double colWidth(
                double weight,
                double minWidth, {
                double? compactMinWidth,
              }) {
                final value = usableWidth * (weight / totalWeight);
                final effectiveMin = compactTable
                    ? (compactMinWidth ?? minWidth)
                    : minWidth;
                return value < effectiveMin ? effectiveMin : value;
              }

              final codeCellWidth = colWidth(1.15, 104, compactMinWidth: 86);
              final studentCellWidth = colWidth(
                2.35,
                210,
                compactMinWidth: 170,
              );
              final concernCellWidth = colWidth(1.40, 128, compactMinWidth: 92);
              final violationCellWidth = colWidth(
                2.35,
                220,
                compactMinWidth: 162,
              );
              final dateCellWidth = colWidth(1.20, 116, compactMinWidth: 92);
              final statusCellWidth = colWidth(1.35, 126, compactMinWidth: 110);

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStateProperty.all(bg),
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 64,
                    horizontalMargin: tableHorizontalMargin,
                    columnSpacing: tableColumnSpacing,
                    headingTextStyle: const TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                      fontSize: 12,
                    ),
                    columns: [
                      DataColumn(
                        label: SizedBox(
                          width: codeCellWidth,
                          child: _tableHeaderText('CODE'),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: studentCellWidth,
                          child: _tableHeaderText('STUDENT'),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: concernCellWidth,
                          child: _tableHeaderText('CONCERN'),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: violationCellWidth,
                          child: _tableHeaderText('VIOLATION'),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: dateCellWidth,
                          child: _tableHeaderText('DATE'),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: statusCellWidth,
                          child: _tableHeaderText('STATUS'),
                        ),
                      ),
                    ],
                    rows: [
                      for (int i = 0; i < reports.length; i++)
                        () {
                          final report = reports[i];
                          final isSelected = _selectedId == report.id;
                          final detailsText =
                              report.kind == _ReportKind.counseling
                              ? '${report.referralSource.isEmpty ? 'Counselling' : report.referralSource} | ${report.category}'
                              : report.violation;
                          return DataRow.byIndex(
                            index: i,
                            selected: isSelected,
                            color: WidgetStateProperty.resolveWith<Color?>((
                              states,
                            ) {
                              if (isSelected) {
                                return primaryColor.withValues(alpha: 0.08);
                              }
                              return null;
                            }),
                            onSelectChanged: (_) {
                              setState(() {
                                _selectedId = isSelected ? null : report.id;
                              });
                            },
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: codeCellWidth,
                                  child: Text(
                                    _displayReportCode(report),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: studentCellWidth,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        report.studentName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: textDark,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        report.studentId.isEmpty
                                            ? '--'
                                            : report.studentId,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: hintColor,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
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
                                    child: _buildConcernBadge(report.concern),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: violationCellWidth,
                                  child: Text(
                                    detailsText.isEmpty ? '--' : detailsText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: textDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: dateCellWidth,
                                  child: Text(
                                    _fmtShort(report.submittedAt),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: hintColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: statusCellWidth,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _buildStatusBadge(report.statusText),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCounselingReportsTable(List<_SubmittedReport> reports) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = constraints.maxWidth;
            final detailsOpen = _selectedId != null;
            final compactTable = detailsOpen || tableWidth < 1120;
            final tableHorizontalMargin = compactTable ? 8.0 : 12.0;
            final tableColumnSpacing = compactTable ? 12.0 : 18.0;
            final usableWidth =
                (tableWidth -
                        (tableHorizontalMargin * 2) -
                        (tableColumnSpacing * 4))
                    .clamp(420.0, double.infinity)
                    .toDouble();
            final codeCellWidth = (usableWidth * 0.16).clamp(96.0, 128.0);
            final studentCellWidth = (usableWidth * 0.28).clamp(180.0, 260.0);
            final referralCellWidth = (usableWidth * 0.30).clamp(170.0, 260.0);
            final dateCellWidth = (usableWidth * 0.14).clamp(104.0, 130.0);
            final statusCellWidth = (usableWidth * 0.16).clamp(120.0, 170.0);

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(Colors.white),
                  horizontalMargin: tableHorizontalMargin,
                  columnSpacing: tableColumnSpacing,
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 56,
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
                        width: referralCellWidth,
                        child: const Text(
                          'REFERRAL',
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
                    DataColumn(
                      label: SizedBox(
                        width: statusCellWidth,
                        child: const Text(
                          'STATUS',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                  rows: List.generate(reports.length, (i) {
                    final report = reports[i];
                    final isSelected = _selectedId == report.id;
                    final source = report.referralSource.isEmpty
                        ? 'Counselling'
                        : report.referralSource;
                    final type = report.category.isEmpty
                        ? 'General'
                        : report.category;

                    return DataRow(
                      selected: isSelected,
                      color: WidgetStateProperty.resolveWith<Color?>((_) {
                        if (isSelected) {
                          return primaryColor.withValues(alpha: 0.08);
                        }
                        return null;
                      }),
                      onSelectChanged: (_) {
                        setState(() {
                          _selectedId = isSelected ? null : report.id;
                        });
                      },
                      cells: [
                        DataCell(
                          SizedBox(
                            width: codeCellWidth,
                            child: Text(
                              _displayReportCode(report),
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
                                  report.studentName.isEmpty
                                      ? 'Unknown Student'
                                      : report.studentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: textDark,
                                  ),
                                ),
                                if (report.studentId.isNotEmpty)
                                  Text(
                                    report.studentId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                            width: referralCellWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: textDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  type,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                            width: dateCellWidth,
                            child: Text(
                              _fmtShort(report.submittedAt),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: hintColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: statusCellWidth,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _buildStatusBadge(report.statusText),
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

  Widget _tableHeaderText(String text) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: hintColor,
        fontWeight: FontWeight.w900,
        fontSize: 12,
        letterSpacing: 0.2,
      ),
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
                        ? '${r.referralSource.isEmpty ? 'Counselling' : r.referralSource} | ${r.category}'
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    report.kind == _ReportKind.counseling
                        ? 'Referral Details'
                        : 'Case Details',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _selectedId = null),
                  icon: const Icon(Icons.close_rounded, color: hintColor),
                  tooltip: 'Close details',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
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
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final reservedTop = media.padding.top + kToolbarHeight + 8;
        final modalHeight = (media.size.height - reservedTop)
            .clamp(420.0, media.size.height * 0.92)
            .toDouble();
        return SafeArea(
          top: false,
          child: SizedBox(
            height: modalHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.assignment_outlined,
                            color: primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.kind == _ReportKind.counseling
                                  ? 'Referral Details'
                                  : 'Case Details',
                              style: const TextStyle(
                                color: primaryColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                        child: _buildReadOnlyCaseDetailsBody(r),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReadOnlyCaseDetailsBody(_SubmittedReport report) {
    if (report.kind == _ReportKind.counseling) {
      return _buildCounselingDetailsBody(report);
    }

    final isResolved = report.status == _ReportStatus.resolved;
    final reportedBy = report.reporterName.isEmpty
        ? '--'
        : report.reporterRole.isEmpty
        ? report.reporterName
        : '${report.reporterName} (${report.reporterRole})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReadOnlyStudentInfoCard(report),
        const SizedBox(height: 12),
        _ReadOnlyDetailCard(
          title: 'Incident Summary',
          child: Column(
            children: [
              _readOnlyKv(
                'Concern',
                report.concern.isEmpty
                    ? '--'
                    : _toTitleCaseText(report.concern),
              ),
              const SizedBox(height: 8),
              _readOnlyKv('Category', report.category),
              const SizedBox(height: 8),
              _readOnlyKv('Violation Type', report.violation),
              const SizedBox(height: 8),
              _readOnlyKv('Date Reported', _fmtTsLong(report.submittedAt)),
              const SizedBox(height: 8),
              _readOnlyKv('Date of Incident', _fmtTsLong(report.incidentAt)),
              const SizedBox(height: 8),
              _readOnlyKv('Reported By', reportedBy),
              const SizedBox(height: 8),
              _readOnlyKv('Case Code', _displayReportCode(report)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReadOnlyDetailCard(
          title: 'Incident Description',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Text(
              report.description,
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
        _ReadOnlyDetailCard(
          title: 'Evidence (${report.evidenceUrls.length})',
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Text(
                report.facultyNote,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  fontSize: 14.5,
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
        _buildReadOnlyStudentInfoCard(report),
        const SizedBox(height: 12),
        _ReadOnlyDetailCard(
          title: 'Referral Summary',
          child: Column(
            children: [
              _readOnlyKv('Case Code', _displayReportCode(report)),
              const SizedBox(height: 8),
              _readOnlyKv(
                'Referral Source',
                report.referralSource.isEmpty ? 'Counselling' : report.referralSource,
              ),
              const SizedBox(height: 8),
              _readOnlyKv('Referral Type', report.category),
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
        if (report.referralEntries.isNotEmpty) ...[
          _ReadOnlyDetailCard(
            title: 'Referral History',
            child: Column(
              children: [
                for (int i = 0; i < report.referralEntries.length; i++) ...[
                  _buildReferralHistoryEntry(
                    report.referralEntries[i],
                    isPrimary: i == 0,
                  ),
                  if (i < report.referralEntries.length - 1)
                    const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
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

  Widget _buildReferralHistoryEntry(
    Map<String, dynamic> entry, {
    required bool isPrimary,
  }) {
    final source = _prettyCounselingSource(_str(entry['source']));
    final type = _prettyCounselingType(_str(entry['counselingType']));
    final submittedAt = _tsToDate(entry['submittedAt']);
    final referredBy = _str(entry['referredBy']);
    final referredByRole = _toTitleCaseText(_str(entry['referredByRole']));
    final reasons = _stringKeyedMap(entry['reasons']);
    final comments = _str(entry['comments']);
    final concernSummary = _buildCounselingReasonSummary(reasons);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isPrimary ? 'Primary referral' : 'Referral entry',
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (submittedAt != null)
                Text(
                  _fmtTsLong(submittedAt),
                  style: const TextStyle(
                    color: hintColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _detailRow('Source', source),
          _detailRow('Type', type),
          if (referredBy.isNotEmpty) _detailRow('Referred By', referredBy),
          if (referredByRole.isNotEmpty) _detailRow('Role', referredByRole),
          _detailRow('Concern', concernSummary),
          if (comments.isNotEmpty) _detailRow('Comments', comments),
        ],
      ),
    );
  }

  Widget _readOnlyKv(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label + ':',
            style: const TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '--' : value,
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

  Widget _buildReadOnlyStudentInfoCard(_SubmittedReport report) {
    return _ReadOnlyDetailCard(
      title: 'Student Information',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<String>(
            future: _resolveStudentPhotoUrl(report.studentUid),
            initialData: '',
            builder: (context, snapshot) {
              final photoUrl = _str(snapshot.data);
              return MouseRegion(
                cursor: photoUrl.isEmpty
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: photoUrl.isEmpty
                      ? null
                      : () => _openProfilePhotoViewer(
                          sourceUrl: photoUrl,
                          studentName: report.studentName,
                        ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF1B5E20,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(
                              0xFF1B5E20,
                            ).withValues(alpha: 0.25),
                          ),
                        ),
                        child: photoUrl.isEmpty
                            ? const Icon(
                                Icons.person_rounded,
                                color: Color(0xFF1B5E20),
                                size: 24,
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: Image.network(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                        Icons.person_rounded,
                                        color: Color(0xFF1B5E20),
                                        size: 24,
                                      ),
                                ),
                              ),
                      ),
                      if (photoUrl.isNotEmpty)
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            width: 17,
                            height: 17,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B5E20),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.3,
                              ),
                            ),
                            child: const Icon(
                              Icons.open_in_full_rounded,
                              color: Colors.white,
                              size: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.studentName.isEmpty ? '--' : report.studentName,
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  report.studentId.isEmpty
                      ? 'Student No: --'
                      : 'Student No: ' + report.studentId,
                  style: const TextStyle(
                    color: hintColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                FutureBuilder<String>(
                  future: _resolveStudentProgram(
                    studentUid: report.studentUid,
                    fallbackProgram: report.program,
                  ),
                  initialData: report.program,
                  builder: (context, snapshot) {
                    final program = _str(snapshot.data);
                    return Text(
                      'Program: ' + (program.isEmpty ? '--' : program),
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
    );
  }

  Future<void> _openProfilePhotoViewer({
    required String sourceUrl,
    required String studentName,
  }) async {
    final resolvedUrl = await _resolveImageSourceUrl(sourceUrl);
    if (resolvedUrl.isEmpty || !mounted) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => _ProfilePhotoViewerDialog(
        photoUrl: resolvedUrl,
        studentName: studentName,
      ),
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

    final show = urls.length > 6 ? 6 : urls.length;

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
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(show, (i) {
            final url = urls[i];
            final isPdf = _isLikelyPdf(url);
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openEvidencePreview(url, isPdf: isPdf),
              child: Stack(
                children: [
                  Container(
                    width: 100,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
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
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: primaryColor.withValues(alpha: 0.7),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: hintColor,
                                size: 22,
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
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
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'PDF',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10.5,
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

  Future<void> _openEvidencePreview(String url, {required bool isPdf}) async {
    final resolvedUrl = await _resolveImageSourceUrl(url);
    if (resolvedUrl.isEmpty || !mounted) return;
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
                                resolvedUrl,
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
                            resolvedUrl,
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
    final isResolved = s.contains('resolved') && !s.contains('unresolved');
    final isActionSet =
        s.contains('action set') ||
        s.contains('with meeting') ||
        s.contains('monitoring');
    final isUnderReview =
        s.contains('under review') ||
        s.contains('submitted') ||
        s.contains('pending');

    Color tone = const Color(0xFF455A64);
    if (isResolved) tone = const Color(0xFF2E7D32);
    if (isActionSet) tone = const Color(0xFF0D47A1);
    if (isUnderReview) tone = const Color(0xFFD97706);

    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.24)),
      ),
      child: Text(
        status,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tone,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildConcernBadge(String concern) {
    final normalized = concern.toLowerCase().trim();
    final isSerious = normalized.contains('serious');
    final isBasic = normalized.contains('basic');

    final Color fill = isSerious
        ? Colors.orange.withValues(alpha: 0.10)
        : isBasic
        ? primaryColor.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.04);
    final Color border = isSerious
        ? Colors.orange.withValues(alpha: 0.30)
        : isBasic
        ? primaryColor.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.12);
    final Color text = isSerious
        ? Colors.orange.shade900
        : isBasic
        ? primaryColor
        : hintColor;

    return Container(
      constraints: const BoxConstraints(minWidth: 64, maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        concern.isEmpty ? '--' : concern,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1F2A1F),
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

class _ProfilePhotoViewerDialog extends StatelessWidget {
  final String photoUrl;
  final String studentName;

  const _ProfilePhotoViewerDialog({
    required this.photoUrl,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = size.width > 760 ? 640.0 : size.width * 0.94;
    final dialogHeight = size.height > 620 ? 560.0 : size.height * 0.88;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      studentName.isEmpty ? 'Profile Photo' : studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) =>
                          const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white70,
                                size: 42,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Failed to load profile photo',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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

// ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Wrap layout (no Grid overflow)
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
                        ? "ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â"
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
              value.isEmpty ? "ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â" : value,
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

  @override
  Widget build(BuildContext context) {
    final tone = status.dotColor;
    return Container(
      constraints: BoxConstraints(maxWidth: 120 * scale),
      padding: EdgeInsets.symmetric(
        horizontal: 10 * scale,
        vertical: 6 * scale,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tone,
          fontWeight: FontWeight.w800,
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
            "You havenÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢t submitted any reports yet.",
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
        return const Color(0xFFD97706);
      case _ReportStatus.underReview:
        return const Color(0xFFD97706);
      case _ReportStatus.actionSet:
        return const Color(0xFF0D47A1);
      case _ReportStatus.unresolved:
        return const Color(0xFF455A64);
      case _ReportStatus.resolved:
        return const Color(0xFF2E7D32);
      case _ReportStatus.rejected:
        return const Color(0xFF455A64);
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
  final String referralSource;
  final List<Map<String, dynamic>> referralEntries;
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
    required this.referralSource,
    required this.referralEntries,
    required this.evidenceUrls,
    required this.kind,
    required this.status,
    required this.statusText,
  });
}

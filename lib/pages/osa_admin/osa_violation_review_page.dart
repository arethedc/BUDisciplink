import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:intl/intl.dart';

import '../shared/widgets/modern_table_layout.dart';
import '../shared/widgets/app_layout_tokens.dart';
import '../shared/widgets/app_inline_notice.dart';
import 'meeting_schedule_page.dart';
import '../../services/osa_meeting_schedule_service.dart';
import '../../services/violation_case_service.dart';
import '../../services/violation_types_service.dart';
import '../../services/academic_settings_service.dart';

// Ã¢Å“â€¦ YOUR COLORS (applied everywhere)
const bg = Colors.white;
const primaryColor = Color(0xFF1B5E20);

const textDark = Color(0xFF1F2A1F);
const hintColor = Color(0xFF6D7F62);

enum _InlineNoticeTone { primary, success, danger, warning, neutral }

void _showInlineNotice(
  BuildContext context, {
  required String message,
  _InlineNoticeTone tone = _InlineNoticeTone.primary,
  Duration duration = const Duration(seconds: 4),
}) {
  final bgColor = switch (tone) {
    _InlineNoticeTone.danger => const Color(0xFFC53030),
    _InlineNoticeTone.warning => const Color(0xFFB7791F),
    _InlineNoticeTone.success => const Color(0xFF2F855A),
    _InlineNoticeTone.neutral => const Color(0xFF4A5568),
    _InlineNoticeTone.primary => const Color(0xFF2B6CB0),
  };
  AppScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: bgColor,
      duration: duration,
    ),
  );
}

/// Ã¢Å“â€¦ Enhanced OSA Review Inbox
enum _CaseTab {
  review,
  needsBooking,
  scheduled,
  unresolved,
  resolved,
  cancelled,
}

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

enum _ReviewMoreAction {
  viewCaseLogs,
  correctCase,
  cancelCase,
  completeMeeting,
}

enum _MonitorMoreAction {
  viewCaseLogs,
  correctCase,
  cancelCase,
  completeMeeting,
}

class OsaViolationReviewPage extends StatefulWidget {
  final String? initialSelectedCaseId;
  final bool forceReviewInboxOnOpen;
  final VoidCallback? onOpenReportViolation;
  final VoidCallback? onOpenCounselingReferral;

  const OsaViolationReviewPage({
    super.key,
    this.initialSelectedCaseId,
    this.forceReviewInboxOnOpen = false,
    this.onOpenReportViolation,
    this.onOpenCounselingReferral,
  });

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
    _CaseTabConfig(tab: _CaseTab.cancelled, label: 'Cancelled'),
  ];

  final _svc = ViolationCaseService();
  final _meetingScheduleSvc = OsaMeetingScheduleService();

  // UI state
  _CaseTab _tab = _CaseTab.review;

  String _concernFilter = '';
  String _actionFilter = 'All';
  String _meetingFilter = 'All';
  String _scheduledDateFilter = 'Today';
  final String _dateFilter = 'All';

  String? _selectedCaseId;
  final ValueNotifier<Map<_CaseTab, int>> _tabCounts =
      ValueNotifier<Map<_CaseTab, int>>({
        _CaseTab.review: 0,
        _CaseTab.needsBooking: 0,
        _CaseTab.scheduled: 0,
        _CaseTab.unresolved: 0,
        _CaseTab.resolved: 0,
        _CaseTab.cancelled: 0,
      });

  bool _bookingSweepRunning = false;
  bool _isRefreshingTable = false;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  String? _departmentScopeCollegeId;
  Set<String>? _departmentStudentUids;
  bool _loadingDepartmentScope = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _deptStudentsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tabCountsSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestRawCaseDocs =
      const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  String? _pendingExternalCaseId;

  @override
  void initState() {
    super.initState();
    if (widget.forceReviewInboxOnOpen) {
      _resetToReviewInbox(clearSelectedCase: true);
    }
    _queueExternalCaseSelection(
      widget.initialSelectedCaseId,
      clearFilters: true,
    );
    _runBookingExpirySweep();
    _initDepartmentScope();
    _bindTabCountsStream();
  }

  @override
  void didUpdateWidget(covariant OsaViolationReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final forceReviewInboxChanged =
        oldWidget.forceReviewInboxOnOpen != widget.forceReviewInboxOnOpen;
    if (forceReviewInboxChanged && widget.forceReviewInboxOnOpen) {
      setState(() {
        _resetToReviewInbox(clearSelectedCase: true);
      });
    }
    final nextCaseId = (widget.initialSelectedCaseId ?? '').trim();
    if (oldWidget.initialSelectedCaseId != widget.initialSelectedCaseId &&
        nextCaseId.isNotEmpty) {
      setState(() {
        _queueExternalCaseSelection(
          widget.initialSelectedCaseId,
          clearFilters: true,
        );
      });
    }
  }

  void _queueExternalCaseSelection(
    String? rawCaseId, {
    bool clearFilters = false,
  }) {
    final caseId = (rawCaseId ?? '').trim();
    if (caseId.isEmpty) return;
    _pendingExternalCaseId = caseId;
    _tab = _CaseTab.review;
    if (clearFilters) {
      _resetToReviewInbox(clearSelectedCase: false);
    }
  }

  void _resetToReviewInbox({required bool clearSelectedCase}) {
    _tab = _CaseTab.review;
    if (clearSelectedCase) _selectedCaseId = null;
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    _searchQuery = '';
    _concernFilter = '';
    _actionFilter = 'All';
    _meetingFilter = 'All';
    _scheduledDateFilter = 'Today';
  }

  void _tryApplyPendingExternalSelection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    BuildContext context, {
    required bool mobile,
  }) {
    final pending = _pendingExternalCaseId;
    if (pending == null || pending.isEmpty) return;

    QueryDocumentSnapshot<Map<String, dynamic>>? found;
    for (final doc in docs) {
      final data = doc.data();
      if (doc.id == pending ||
          _safeStr(data['caseId']) == pending ||
          _safeStr(data['caseCode']) == pending) {
        found = doc;
        break;
      }
    }
    if (found == null) return;

    _pendingExternalCaseId = null;
    final nextDoc = found;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selectedCaseId != nextDoc.id) {
        setState(() => _selectedCaseId = nextDoc.id);
      }
      if (mobile) {
        _openDetailsPage(context, nextDoc);
      }
    });
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
      if (mounted) setState(() {});
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
      _CaseTab.cancelled: 0,
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

  void _onSearchInputChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final next = value.trim().toLowerCase();
      if (_searchQuery == next) return;
      setState(() => _searchQuery = next);
    });
  }

  void _clearSearchQuery() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    if (!mounted) return;
    if (_searchQuery.isNotEmpty) {
      setState(() => _searchQuery = '');
    }
  }

  Future<void> _refreshCurrentTable() async {
    if (_isRefreshingTable || !mounted) return;
    setState(() => _isRefreshingTable = true);
    _bindTabCountsStream();
    await _runBookingExpirySweep();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _isRefreshingTable = false);
  }

  bool _matchesSearch(Map<String, dynamic> d) {
    final q = _searchQuery.trim();
    if (q.isEmpty) return true;
    final date =
        _globalTsToDate(d['createdAt']) ?? _globalTsToDate(d['incidentAt']);
    final dateText = date == null
        ? ''
        : '${DateFormat('MMM d, yyyy').format(date)} '
              '${DateFormat('MMMM d, yyyy').format(date)} '
              '${DateFormat('yyyy-MM-dd').format(date)}';
    final fields = [
      _safeStr(d['caseCode']),
      _safeStr(d['studentName']),
      _safeStr(d['studentNo']),
      _safeStr(d['status']),
      _safeStr(d['concern']),
      _safeStr(
        d['violationTypeLabel'] ??
            d['violationNameSnapshot'] ??
            d['violationName'],
      ),
      _safeStr(d['categoryNameSnapshot'] ?? d['categoryName']),
      _safeStr(d['reportedByName']),
      dateText,
    ];
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _tabCountsSub?.cancel();
    _deptStudentsSub?.cancel();
    _tabCounts.dispose();
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
      if (key == 'unresolved') return true;
      if (key == 'action set' && _meetingRequired(d)) {
        final flow = _effectiveMeetingStatusKey(d);
        return flow == 'booking_missed';
      }
      return false;
    }
    if (tab == _CaseTab.resolved) {
      return key == 'resolved';
    }
    return key == 'cancelled';
  }

  bool _matchesTab(Map<String, dynamic> d) => _matchesTabFor(d, _tab);

  String _normalizeConcernKey(String raw) {
    final value = raw.toLowerCase().trim();
    if (value.isEmpty) return '';
    if (value.contains('serious') ||
        value.contains('major') ||
        value.contains('grave')) {
      return 'serious';
    }
    if (value.contains('basic') ||
        value.contains('minor') ||
        value.contains('moderate')) {
      return 'basic';
    }
    return value;
  }

  bool _matchesConcern(Map<String, dynamic> d) {
    if (_concernFilter.isEmpty) return true;
    final raw = _normalizeConcernKey(
      _safeStr(d['concern'] ?? d['concernType'] ?? d['reportedConcernType']),
    );
    final want = _normalizeConcernKey(_concernFilter);
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
    final tomorrow = today.add(const Duration(days: 1));
    final day = _dayOnly(dt);

    if (dateFilter == 'Today') return day == today;
    if (dateFilter == 'Yesterday') return day == yesterday;
    if (dateFilter == 'Tomorrow') return day == tomorrow;

    if (dateFilter == 'This Week') {
      final weekday = today.weekday; // 1..7
      final weekStart = today.subtract(Duration(days: weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 7));
      return !day.isBefore(weekStart) && day.isBefore(weekEnd);
    }

    if (dateFilter == 'Next 7 Days') {
      final end = today.add(const Duration(days: 7));
      return !day.isBefore(today) && day.isBefore(end);
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
    List<QueryDocumentSnapshot<Map<String, dynamic>>> raw, {
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
      if (_tab == _CaseTab.review && !_matchesConcern(d)) {
        return false;
      }
      if (_tab == _CaseTab.unresolved ||
          _tab == _CaseTab.resolved ||
          _tab == _CaseTab.cancelled) {
        if (!_matchesAction(d) || !_matchesMeeting(d)) return false;
      }
      if (includeDateFilter &&
          !_matchesDate(d, dateFilterOverride: dateFilterOverride)) {
        return false;
      }
      if (!_matchesSearch(d)) return false;
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

  Widget _buildReviewConcernFilterBar() {
    final allCount = _reviewInboxCount();
    final basicCount = _reviewConcernCount('basic');
    final seriousCount = _reviewConcernCount('serious');
    const filterRadius = AppRadii.md;

    Widget concernTab({required String value, required String label}) {
      final selected = _concernFilter == value;
      return InkWell(
        borderRadius: BorderRadius.circular(filterRadius),
        onTap: () {
          if (_concernFilter == value) return;
          setState(() {
            _concernFilter = value;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? primaryColor.withValues(alpha: 0.12)
                : Colors.white,
            borderRadius: BorderRadius.circular(filterRadius),
            border: Border.all(
              color: selected
                  ? primaryColor.withValues(alpha: 0.36)
                  : Colors.black.withValues(alpha: 0.10),
            ),
          ),
          child: Text(
            label,
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
          mainAxisSize: MainAxisSize.min,
          children: [
            concernTab(value: '', label: 'All ($allCount)'),
            const SizedBox(width: 8),
            concernTab(value: 'Basic', label: 'Basic ($basicCount)'),
            const SizedBox(width: 8),
            concernTab(value: 'Serious', label: 'Serious ($seriousCount)'),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduledDateFilterBar() {
    const options = <String>[
      'Today',
      'Tomorrow',
      'This Week',
      'Next 7 Days',
      'All',
    ];
    const filterRadius = AppRadii.md;

    Widget dateTab(String label) {
      final selected = _scheduledDateFilter == label;
      return InkWell(
        borderRadius: BorderRadius.circular(filterRadius),
        onTap: () {
          if (_scheduledDateFilter == label) return;
          setState(() => _scheduledDateFilter = label);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? primaryColor.withValues(alpha: 0.12)
                : Colors.white,
            borderRadius: BorderRadius.circular(filterRadius),
            border: Border.all(
              color: selected
                  ? primaryColor.withValues(alpha: 0.36)
                  : Colors.black.withValues(alpha: 0.10),
            ),
          ),
          child: Text(
            label,
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
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              dateTab(options[i]),
              if (i != options.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  int _reviewInboxCount() {
    final allowedStudentUids = _departmentScopeCollegeId == null
        ? null
        : (_departmentStudentUids ?? <String>{});

    var count = 0;
    for (final doc in _latestRawCaseDocs) {
      final data = doc.data();
      if (allowedStudentUids != null) {
        final studentUid = _safeStr(data['studentUid']);
        if (studentUid.isEmpty || !allowedStudentUids.contains(studentUid)) {
          continue;
        }
      }
      if (_matchesTabFor(data, _CaseTab.review)) {
        count += 1;
      }
    }
    return count;
  }

  int _reviewConcernCount(String concernKey) {
    final target = _normalizeConcernKey(concernKey);
    final allowedStudentUids = _departmentScopeCollegeId == null
        ? null
        : (_departmentStudentUids ?? <String>{});

    var count = 0;
    for (final doc in _latestRawCaseDocs) {
      final data = doc.data();
      if (allowedStudentUids != null) {
        final studentUid = _safeStr(data['studentUid']);
        if (studentUid.isEmpty || !allowedStudentUids.contains(studentUid)) {
          continue;
        }
      }
      if (!_matchesTabFor(data, _CaseTab.review)) continue;
      final concern = _normalizeConcernKey(
        _safeStr(
          data['concern'] ?? data['concernType'] ?? data['reportedConcernType'],
        ),
      );
      if (concern == target) count++;
    }
    return count;
  }

  Widget _buildHandbookStyleSearchBar({Widget? compactTrailingAction}) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1000;
    final shouldConstrainWidth = width >= 900;
    final constrainedWidth = width >= 1600
        ? 640.0
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
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.black12),
            boxShadow: isDesktop
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
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
                    color: hintColor.withValues(alpha: 0.85),
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
            color: Colors.white.withValues(alpha: 0.75),
            border: Border.all(color: Colors.black12),
            boxShadow: isDesktop
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
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
                  color: hintColor.withValues(alpha: 0.9),
                  size: isDesktop ? 20 : 18,
                ),
        ),
      ),
    );

    Widget searchWithRefresh() {
      return Row(
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 8),
          refreshButton,
          if (!isDesktop && compactTrailingAction != null) ...[
            const SizedBox(width: 8),
            compactTrailingAction,
          ],
        ],
      );
    }

    if (!shouldConstrainWidth) return searchWithRefresh();
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: constrainedWidth, child: searchWithRefresh()),
    );
  }

  Widget? _buildFullHeaderActions({
    required bool useCompactHeaderActions,
  }) {
    if (useCompactHeaderActions) return null;
    if (widget.onOpenReportViolation == null &&
        widget.onOpenCounselingReferral == null) {
      return null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onOpenReportViolation != null) ...[
          OutlinedButton.icon(
            onPressed: widget.onOpenReportViolation,
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryColor,
              side: BorderSide(color: primaryColor.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.report_rounded, size: 20),
            label: const Text(
              'Report Violation',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (widget.onOpenCounselingReferral != null)
          FilledButton.icon(
            onPressed: widget.onOpenCounselingReferral,
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
            icon: const Icon(Icons.support_agent_rounded, size: 20),
            label: const Text(
              'Counselling Referral',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
      ],
    );
  }

  Widget? _buildCompactHeaderOptionsButton({
    required bool useCompactHeaderActions,
  }) {
    if (!useCompactHeaderActions) return null;
    if (widget.onOpenReportViolation == null &&
        widget.onOpenCounselingReferral == null) {
      return null;
    }

    return Tooltip(
      message: 'More options',
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.75),
          border: Border.all(color: Colors.black12),
        ),
        child: PopupMenuButton<String>(
          tooltip: 'More options',
          padding: EdgeInsets.zero,
          icon: const Icon(
            Icons.more_horiz_rounded,
            color: hintColor,
            size: 20,
          ),
          onSelected: (action) {
            if (action == 'report_violation') {
              widget.onOpenReportViolation?.call();
              return;
            }
            if (action == 'counseling_referral') {
              widget.onOpenCounselingReferral?.call();
            }
          },
          itemBuilder: (context) {
            final items = <PopupMenuEntry<String>>[];
            if (widget.onOpenReportViolation != null) {
              items.add(
                const PopupMenuItem<String>(
                  value: 'report_violation',
                  child: Row(
                    children: [
                      Icon(Icons.report_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Report Violation'),
                    ],
                  ),
                ),
              );
            }
            if (widget.onOpenCounselingReferral != null) {
              items.add(
                const PopupMenuItem<String>(
                  value: 'counseling_referral',
                  child: Row(
                    children: [
                      Icon(Icons.support_agent_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Counselling Referral'),
                    ],
                  ),
                ),
              );
            }
            return items;
          },
        ),
      ),
    );
  }

  // -----------------------------
  // UI
  // -----------------------------
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool desktopWide = constraints.maxWidth >= 1100;
        final bool useCompactHeaderActions = constraints.maxWidth < 760;
        final detailsPaneWidth = (constraints.maxWidth * 0.33)
            .clamp(320.0, 420.0)
            .toDouble();
        final compactHeaderOptions = _buildCompactHeaderOptionsButton(
          useCompactHeaderActions: useCompactHeaderActions,
        );

        return Scaffold(
          backgroundColor: bg,
          body: ModernTableLayout(
            detailsWidth: detailsPaneWidth,
            header: ModernTableHeader(
              showTitleSection: false,
              showTopControlsWhenTitleHidden: true,
              showSearchBar: true,
              searchBar: _buildHandbookStyleSearchBar(
                compactTrailingAction: compactHeaderOptions,
              ),
              action: _buildFullHeaderActions(
                useCompactHeaderActions: useCompactHeaderActions,
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
                                _concernFilter = '';
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
              filters: const [],
            ),
            body: Column(
              children: [
                if (_tab == _CaseTab.review)
                  Container(
                    width: double.infinity,
                    color: bg,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                    child: _buildReviewConcernFilterBar(),
                  ),
                if (_tab == _CaseTab.scheduled)
                  Container(
                    width: double.infinity,
                    color: bg,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                    child: _buildScheduledDateFilterBar(),
                  ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                      final allowedStudentUids =
                          _departmentScopeCollegeId == null
                          ? null
                          : (_departmentStudentUids ?? <String>{});
                      final docs = _filterDocs(
                        raw,
                        dateFilterOverride: _tab == _CaseTab.scheduled
                            ? _scheduledDateFilter
                            : 'All',
                        allowedStudentUids: allowedStudentUids,
                      );
                      _tryApplyPendingExternalSelection(
                        docs,
                        context,
                        mobile: constraints.maxWidth < 900,
                      );

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
                        return _buildDesktopTable(
                          docs,
                          config: _activeTabConfig,
                        );
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
                                setState(() {
                                  _selectedCaseId = doc.id;
                                });
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (!mounted) return;
                                  _openDetailsPage(context, doc);
                                });
                              }
                            },
                            'All',
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            showDetails: _selectedCaseId != null,
            details: _selectedCaseId != null
                ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _svc.streamAllCases(),
                    builder: (context, snap) {
                      if (snap.hasError || !snap.hasData) {
                        return const SizedBox();
                      }
                      final allowedStudentUids =
                          _departmentScopeCollegeId == null
                          ? null
                          : (_departmentStudentUids ?? <String>{});
                      final scopedDocs = snap.data!.docs
                          .where((doc) {
                            if (allowedStudentUids == null) return true;
                            final studentUid = _safeStr(
                              doc.data()['studentUid'],
                            );
                            return studentUid.isNotEmpty &&
                                allowedStudentUids.contains(studentUid);
                          })
                          .toList(growable: false);
                      QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
                      for (final doc in scopedDocs) {
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
                        onOpenCase: (nextDoc) {
                          if (_selectedCaseId == nextDoc.id) return;
                          setState(() => _selectedCaseId = nextDoc.id);
                        },
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
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = constraints.maxWidth;
            final detailsOpen = _selectedCaseId != null;
            final compactTable = detailsOpen || tableWidth < 1120;
            final tableHorizontalMargin = compactTable ? 8.0 : 12.0;
            final tableColumnSpacing = compactTable
                ? 12.0
                : (isNeedsBooking ? 24.0 : 18.0);
            final columnCount =
                5 + (showSeverityColumn ? 1 : 0) + (showMeetingColumn ? 1 : 0);
            final meetingWeight = config.tab == _CaseTab.scheduled ? 2.0 : 1.8;
            final totalWeight =
                1.15 +
                2.35 +
                1.55 +
                2.35 +
                1.20 +
                (showSeverityColumn ? 1.25 : 0.0) +
                (showMeetingColumn ? meetingWeight : 0.0);
            final usableWidth =
                (tableWidth -
                        (tableHorizontalMargin * 2) -
                        (tableColumnSpacing * (columnCount - 1)))
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

            final codeCellWidth = colWidth(1.15, 100, compactMinWidth: 82);
            final studentCellWidth = colWidth(2.35, 210, compactMinWidth: 170);
            final concernCellWidth = colWidth(1.55, 138, compactMinWidth: 100);
            final violationCellWidth = colWidth(
              2.35,
              220,
              compactMinWidth: 160,
            );
            final dateCellWidth = colWidth(1.20, 112, compactMinWidth: 92);
            final severityCellWidth = showSeverityColumn
                ? colWidth(1.25, 120, compactMinWidth: 100)
                : 0.0;
            final meetingCellWidth = showMeetingColumn
                ? colWidth(
                    meetingWeight,
                    config.tab == _CaseTab.scheduled ? 172 : 150,
                    compactMinWidth: config.tab == _CaseTab.scheduled
                        ? 126
                        : 120,
                  )
                : 0.0;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(bg),
                  horizontalMargin: tableHorizontalMargin,
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
    final normalized = concern.trim().toLowerCase();
    final isSerious = normalized.contains('serious');
    final isBasic = normalized.contains('basic');

    final fill = isSerious
        ? Colors.orange.withValues(alpha: 0.10)
        : isBasic
        ? primaryColor.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.04);
    final border = isSerious
        ? Colors.orange.withValues(alpha: 0.30)
        : isBasic
        ? primaryColor.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.12);
    final textColor = isSerious
        ? Colors.orange.shade900
        : isBasic
        ? primaryColor
        : hintColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
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
                      Expanded(
                        child: Text(
                          caseCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: primaryColor,
                          ),
                        ),
                      ),
                      if (date != null)
                        Text(
                          _TableRow._dynamicDateTextGlobal(date, dateFilter),
                          style: const TextStyle(
                            fontSize: 12,
                            color: hintColor,
                          ),
                        ),
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
              children: [const Icon(Icons.chevron_right, color: Colors.grey)],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetailsPage(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _DetailsPanel(
              doc: doc,
              bestDate: _bestDate,
              onClose: () => Navigator.of(context).pop(),
              onOpenCase: (nextDoc) {
                if (nextDoc.id == doc.id) return;
                Navigator.of(context).pop();
                Future<void>.microtask(() {
                  if (!mounted) return;
                  setState(() => _selectedCaseId = nextDoc.id);
                  _openDetailsPage(this.context, nextDoc);
                });
              },
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (_selectedCaseId == doc.id) {
      setState(() => _selectedCaseId = null);
    }
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
                  ? primaryColor.withValues(alpha: 0.05)
                  : Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(
                color: selected
                    ? primaryColor
                    : Colors.black.withValues(alpha: 0.05),
                width: selected ? 2 : 1,
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
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>>? onOpenCase;

  const _DetailsPanel({
    required this.doc,
    required this.bestDate,
    this.onClose,
    this.onOpenCase,
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
    final studentPhotoFuture = _resolveStudentPhotoUrl(studentUid);
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
    final offenseFuture = _resolveOffenseIndicator(
      studentUid: studentUid,
      currentCaseId: doc.id,
      currentCategory: category,
    );

    final statusKey = _statusKey(_safeStr(d['status']));
    final canCorrectCase = _canCorrectCaseStatusKey(statusKey);
    final isCancelled = statusKey == 'cancelled';
    final cancelledFromStatusKey = _statusKey(
      _safeStr(d['cancelledFromStatus']),
    );
    final wasResolvedBeforeCancellation =
        isCancelled &&
        (cancelledFromStatusKey == 'resolved' ||
            _globalTsToDate(d['resolvedAt']) != null);
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
    final canCompleteMeetingFromMenu =
        meetingRequired &&
        effectiveMeetingStatus != 'completed' &&
        statusKey != 'resolved';
    final canCompleteMeetingInReviewMenu =
        canCompleteMeetingFromMenu ||
        statusKey == 'submitted' ||
        statusKey == 'under review';
    final canRescheduleMeeting =
        meetingRequired &&
        (effectiveMeetingStatus == 'booking_missed' ||
            effectiveMeetingStatus == 'meeting_missed');
    final reschedulePrompt = effectiveMeetingStatus == 'booking_missed'
        ? 'Reopen booking window for this missed booking?'
        : 'Reopen booking window for this missed meeting attendance?';

    final dt = bestDate(d);
    final reportedAt =
        _globalTsToDate(d['createdAt']) ??
        _globalTsToDate(d['reportedAt']) ??
        dt;
    final incidentAt =
        _globalTsToDate(d['incidentAt']) ??
        _globalTsToDate(d['incidentDate']) ??
        _globalTsToDate(d['dateOfIncident']);
    final dateReportedText = _formatReportedAtSmartGlobal(reportedAt);
    final dateOfIncidentText = incidentAt == null
        ? '--'
        : _formatReportedAtSmartGlobal(incidentAt);

    final reportedBy = _reportedByDisplay(d);
    final wasCorrectedByOsa = d['wasCorrectedByOsa'] == true;
    final narrative = _safeStr(d['narrative'] ?? d['description']).isEmpty
        ? '--'
        : _safeStr(d['narrative'] ?? d['description']);
    final evidenceUrls = _evidenceUrls(d);
    final evidenceCount = evidenceUrls.length;

    final svc = ViolationCaseService();

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        color: primaryColor,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Case Details',
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: hintColor),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                children: [
                  _DetailCard(
                    title: 'Student Information',
                    child: Row(
                      children: [
                        FutureBuilder<String>(
                          future: studentPhotoFuture,
                          initialData: '',
                          builder: (context, snapshot) {
                            final photoUrl = _safeStr(snapshot.data);
                            return MouseRegion(
                              cursor: photoUrl.isEmpty
                                  ? SystemMouseCursors.basic
                                  : SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: photoUrl.isEmpty
                                    ? null
                                    : () => _openProfilePhotoViewer(
                                        context,
                                        sourceUrl: photoUrl,
                                        studentName: studentName,
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
                                        borderRadius: BorderRadius.circular(
                                          AppRadii.md,
                                        ),
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
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppRadii.md - 1,
                                                  ),
                                              child: Image.network(
                                                photoUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => const Icon(
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
                                            borderRadius: BorderRadius.circular(
                                              AppRadii.pill,
                                            ),
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
                    titleTrailing: isCancelled
                        ? null
                        : FutureBuilder<_OffenseIndicator>(
                            future: offenseFuture,
                            initialData: const _OffenseIndicator(
                              label: '--',
                              subtitle: '',
                              offenseNumber: 0,
                            ),
                            builder: (context, snapshot) {
                              final indicator =
                                  snapshot.data ??
                                  const _OffenseIndicator(
                                    label: '--',
                                    subtitle: '',
                                    offenseNumber: 0,
                                  );
                              final isRepeat = indicator.offenseNumber >= 2;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isRepeat
                                      ? Colors.orange.withValues(alpha: 0.12)
                                      : primaryColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.pill,
                                  ),
                                  border: Border.all(
                                    color: isRepeat
                                        ? Colors.orange.withValues(alpha: 0.35)
                                        : primaryColor.withValues(alpha: 0.28),
                                  ),
                                ),
                                child: Text(
                                  indicator.label,
                                  style: TextStyle(
                                    color: isRepeat
                                        ? Colors.orange.shade800
                                        : primaryColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11.5,
                                  ),
                                ),
                              );
                            },
                          ),
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
                        _kv('Date Reported', dateReportedText),
                        const SizedBox(height: 8),
                        _kv('Date of Incident', dateOfIncidentText),
                        const SizedBox(height: 8),
                        _kv('Reported By', reportedBy),
                        const SizedBox(height: 8),
                        _kv('Case Code', caseCode),
                        if (wasCorrectedByOsa) ...[
                          const SizedBox(height: 8),
                          _kv(
                            'OSA Correction',
                            'Corrected by OSA (see Case Logs).',
                          ),
                        ],
                      ],
                    ),
                  ),
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
                    title: 'Evidence ($evidenceCount)',
                    child: _EvidencePlaceholders(urls: evidenceUrls),
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
                    title: isCancelled
                        ? 'Active Case History'
                        : 'Student Case History',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Offense history is grouped by category and excludes cancelled cases.',
                            style: TextStyle(
                              color: hintColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.8,
                            ),
                          ),
                        ),
                        if (isCancelled)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: primaryColor.withValues(alpha: 0.18),
                              ),
                            ),
                            child: const Text(
                              'This case is cancelled and excluded from offense progression.',
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.4,
                              ),
                            ),
                          ),
                        _StudentHistorySection(
                          studentUid: studentUid,
                          currentCaseId: doc.id,
                          currentViolationType: violation,
                          currentCategory: category,
                          onOpenCase: onOpenCase,
                          showCurrentOffenseSummary: !isCancelled,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 72),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            child: (!isMonitor && !isCancelled)
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
                            if (changed == true) {
                              _showInlineNotice(
                                context,
                                message: 'Action set successfully.',
                                tone: _InlineNoticeTone.success,
                              );
                              onClose?.call();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      PopupMenuButton<_ReviewMoreAction>(
                        tooltip: 'More actions',
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        color: Colors.white,
                        onSelected: (action) async {
                          if (action == _ReviewMoreAction.viewCaseLogs) {
                            showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  _CaseLogsDialog(caseId: doc.id, caseData: d),
                            );
                            return;
                          }
                          if (action == _ReviewMoreAction.correctCase) {
                            if (!canCorrectCase) {
                              _showInlineNotice(
                                context,
                                message:
                                    'Correction is not allowed for this case status.',
                                tone: _InlineNoticeTone.warning,
                              );
                              return;
                            }
                            final changed = await showDialog<bool>(
                              context: context,
                              builder: (c) =>
                                  _CorrectViolationDialog(doc: doc, svc: svc),
                            );
                            if (changed == true) {
                              _showInlineNotice(
                                context,
                                message: 'Case corrected successfully.',
                                tone: _InlineNoticeTone.success,
                              );
                              if (onClose != null) {
                                // stream handles refresh
                              }
                            }
                            return;
                          }
                          if (action == _ReviewMoreAction.completeMeeting) {
                            final saved = await showDialog<bool>(
                              context: context,
                              builder: (c) => _CompleteMeetingDialog(
                                caseId: doc.id,
                                svc: svc,
                              ),
                            );
                            if (saved == true) {
                              _showInlineNotice(
                                context,
                                message: 'Meeting completed.',
                                tone: _InlineNoticeTone.success,
                              );
                              onClose?.call();
                            }
                            return;
                          }
                          final changed = await showDialog<bool>(
                            context: context,
                            builder: (c) => _CancelViolationDialog(
                              doc: doc,
                              svc: svc,
                              asCaseCancellation: true,
                            ),
                          );
                          if (changed == true) {
                            _showInlineNotice(
                              context,
                              message: 'Case cancelled.',
                              tone: _InlineNoticeTone.success,
                            );
                            onClose?.call();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem<_ReviewMoreAction>(
                            value: _ReviewMoreAction.viewCaseLogs,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.history_rounded,
                                color: primaryColor,
                              ),
                              title: Text('Case Logs'),
                            ),
                          ),
                          if (canCorrectCase)
                            const PopupMenuItem<_ReviewMoreAction>(
                              value: _ReviewMoreAction.correctCase,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.edit_note_rounded,
                                  color: primaryColor,
                                ),
                                title: Text('Correct Case'),
                              ),
                            ),
                          const PopupMenuItem<_ReviewMoreAction>(
                            value: _ReviewMoreAction.cancelCase,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.cancel_outlined,
                                color: Colors.redAccent,
                              ),
                              title: Text('Cancel Case'),
                            ),
                          ),
                          if (canCompleteMeetingInReviewMenu)
                            const PopupMenuItem<_ReviewMoreAction>(
                              value: _ReviewMoreAction.completeMeeting,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.task_alt_rounded,
                                  color: primaryColor,
                                ),
                                title: Text('Complete Meeting'),
                              ),
                            ),
                        ],
                        child: Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            border: Border.all(
                              color: primaryColor.withValues(alpha: 0.30),
                            ),
                          ),
                          child: const Icon(
                            Icons.more_vert_rounded,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ],
                  )
                : isCancelled
                ? Row(
                    children: [
                      Expanded(
                        child: _ActionBtn(
                          label: wasResolvedBeforeCancellation
                              ? 'Reopen'
                              : 'Reopen + Set Action',
                          fill: primaryColor,
                          textColor: Colors.white,
                          borderColor: primaryColor,
                          onTap: () async {
                            final changed = await showDialog<bool>(
                              context: context,
                              builder: (c) => wasResolvedBeforeCancellation
                                  ? _ReopenCancelledCaseDialog(
                                      doc: doc,
                                      svc: svc,
                                    )
                                  : _AssignActionDialog(
                                      doc: doc,
                                      currentSeverity: _safeStr(
                                        d['finalSeverity'] ?? d['concern'],
                                      ),
                                      currentAction: _actionKey(d),
                                      svc: svc,
                                    ),
                            );
                            if (changed == true) {
                              _showInlineNotice(
                                context,
                                message: wasResolvedBeforeCancellation
                                    ? 'Case reopened and returned to Resolved.'
                                    : 'Case reopened and action applied.',
                                tone: _InlineNoticeTone.success,
                              );
                              if (onClose != null) {
                                onClose!();
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      PopupMenuButton<_MonitorMoreAction>(
                        tooltip: 'Options',
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        color: Colors.white,
                        onSelected: (action) async {
                          if (action == _MonitorMoreAction.viewCaseLogs) {
                            showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  _CaseLogsDialog(caseId: doc.id, caseData: d),
                            );
                            return;
                          }
                          if (action == _MonitorMoreAction.correctCase) {
                            if (!canCorrectCase) {
                              _showInlineNotice(
                                context,
                                message:
                                    'Correction is not allowed for this case status.',
                                tone: _InlineNoticeTone.warning,
                              );
                              return;
                            }
                            final changed = await showDialog<bool>(
                              context: context,
                              builder: (c) =>
                                  _CorrectViolationDialog(doc: doc, svc: svc),
                            );
                            if (changed == true) {
                              _showInlineNotice(
                                context,
                                message: 'Case corrected successfully.',
                                tone: _InlineNoticeTone.success,
                              );
                              if (onClose != null) {
                                // stream handles refresh
                              }
                            }
                            return;
                          }
                          if (action == _MonitorMoreAction.completeMeeting) {
                            final saved = await showDialog<bool>(
                              context: context,
                              builder: (c) => _CompleteMeetingDialog(
                                caseId: doc.id,
                                svc: svc,
                              ),
                            );
                            if (saved == true) {
                              _showInlineNotice(
                                context,
                                message: 'Meeting completed.',
                                tone: _InlineNoticeTone.success,
                              );
                              onClose?.call();
                            }
                            return;
                          }
                          if (action == _MonitorMoreAction.cancelCase) {
                            final changed = await showDialog<bool>(
                              context: context,
                              builder: (c) => _CancelViolationDialog(
                                doc: doc,
                                svc: svc,
                                asCaseCancellation: true,
                              ),
                            );
                            if (changed == true) {
                              _showInlineNotice(
                                context,
                                message: 'Case cancelled.',
                                tone: _InlineNoticeTone.success,
                              );
                              onClose?.call();
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem<_MonitorMoreAction>(
                            value: _MonitorMoreAction.viewCaseLogs,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.history_rounded,
                                color: primaryColor,
                              ),
                              title: Text('Case Logs'),
                            ),
                          ),
                          if (canCorrectCase)
                            const PopupMenuItem<_MonitorMoreAction>(
                              value: _MonitorMoreAction.correctCase,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.edit_note_rounded,
                                  color: primaryColor,
                                ),
                                title: Text('Correct Case'),
                              ),
                            ),
                          if (canCompleteMeetingFromMenu)
                            const PopupMenuItem<_MonitorMoreAction>(
                              value: _MonitorMoreAction.completeMeeting,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.task_alt_rounded,
                                  color: primaryColor,
                                ),
                                title: Text('Complete Meeting'),
                              ),
                            ),
                          if (statusKey == 'resolved')
                            const PopupMenuItem<_MonitorMoreAction>(
                              value: _MonitorMoreAction.cancelCase,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.cancel_outlined,
                                  color: Colors.redAccent,
                                ),
                                title: Text('Cancel Case'),
                              ),
                            ),
                        ],
                        child: Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            border: Border.all(
                              color: primaryColor.withValues(alpha: 0.30),
                            ),
                          ),
                          child: const Icon(
                            Icons.more_vert_rounded,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      if (statusKey == 'resolved') ...[
                        Expanded(
                          child: _ActionBtn(
                            label: 'Case Logs',
                            fill: Colors.white,
                            textColor: primaryColor,
                            borderColor: primaryColor.withValues(alpha: 0.35),
                            onTap: () {
                              showDialog<void>(
                                context: context,
                                builder: (_) => _CaseLogsDialog(
                                  caseId: doc.id,
                                  caseData: d,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                      ] else ...[
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
                                if (saved == true) {
                                  _showInlineNotice(
                                    context,
                                    message: 'Meeting completed.',
                                    tone: _InlineNoticeTone.success,
                                  );
                                  onClose?.call();
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
                                        onPressed: () =>
                                            Navigator.pop(c, false),
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
                                  if (!context.mounted) return;
                                  _showInlineNotice(
                                    context,
                                    message: 'Meeting rescheduled.',
                                    tone: _InlineNoticeTone.success,
                                  );
                                  onClose?.call();
                                }
                              },
                            ),
                          ),
                        if (canCompleteMeeting || canRescheduleMeeting)
                          const SizedBox(width: 10),
                      ],
                      PopupMenuButton<_MonitorMoreAction>(
                        tooltip: 'Options',
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        color: Colors.white,
                        onSelected: (action) async {
                          if (action == _MonitorMoreAction.viewCaseLogs) {
                            showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  _CaseLogsDialog(caseId: doc.id, caseData: d),
                            );
                            return;
                          }
                          if (action == _MonitorMoreAction.correctCase) {
                            if (!canCorrectCase) {
                              _showInlineNotice(
                                context,
                                message:
                                    'Correction is not allowed for this case status.',
                                tone: _InlineNoticeTone.warning,
                              );
                              return;
                            }
                            final changed = await showDialog<bool>(
                              context: context,
                              builder: (c) =>
                                  _CorrectViolationDialog(doc: doc, svc: svc),
                            );
                            if (changed == true) {
                              _showInlineNotice(
                                context,
                                message: 'Case corrected successfully.',
                                tone: _InlineNoticeTone.success,
                              );
                              if (onClose != null) {
                                // keep open; stream refreshes automatically
                              }
                            }
                            return;
                          }
                          if (action == _MonitorMoreAction.cancelCase) {
                            final changed = await showDialog<bool>(
                              context: context,
                              builder: (c) => _CancelViolationDialog(
                                doc: doc,
                                svc: svc,
                                asCaseCancellation: true,
                              ),
                            );
                            if (changed == true) {
                              _showInlineNotice(
                                context,
                                message: 'Case cancelled.',
                                tone: _InlineNoticeTone.success,
                              );
                              onClose?.call();
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          if (statusKey != 'resolved')
                            const PopupMenuItem<_MonitorMoreAction>(
                              value: _MonitorMoreAction.viewCaseLogs,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.history_rounded,
                                  color: primaryColor,
                                ),
                                title: Text('Case Logs'),
                              ),
                            ),
                          if (canCorrectCase)
                            const PopupMenuItem<_MonitorMoreAction>(
                              value: _MonitorMoreAction.correctCase,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.edit_note_rounded,
                                  color: primaryColor,
                                ),
                                title: Text('Correct Case'),
                              ),
                            ),
                          if (statusKey != 'cancelled')
                            const PopupMenuItem<_MonitorMoreAction>(
                              value: _MonitorMoreAction.cancelCase,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.cancel_outlined,
                                  color: Colors.redAccent,
                                ),
                                title: Text('Cancel Case'),
                              ),
                            ),
                        ],
                        child: Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            border: Border.all(
                              color: primaryColor.withValues(alpha: 0.30),
                            ),
                          ),
                          child: const Icon(
                            Icons.more_vert_rounded,
                            color: primaryColor,
                          ),
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
    final isResolvedCase = _statusKey(_safeStr(data['status'])) == 'resolved';
    final meetingLocation = _safeStr(data['meetingLocation']);
    final meetingNotes = _safeStr(data['meetingNotes']);
    final facultyNote = _safeStr(data['meetingFacultyNote']);
    final completedAt = _globalTsToDate(data['meetingCompletedAt']);
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
          isResolvedCase
              ? _meetingKv('Scheduled At', _fmtMeetingDateTime(scheduledAt))
              : _meetingInfoCard(
                  'Scheduled At',
                  _fmtMeetingDateTime(scheduledAt),
                ),
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

class _CaseLogsDialog extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> caseData;

  const _CaseLogsDialog({required this.caseId, required this.caseData});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Case Logs',
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: hintColor),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: _CaseLogsSection(caseId: caseId, caseData: caseData),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _CaseLogsSection extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> caseData;

  const _CaseLogsSection({required this.caseId, required this.caseData});

  @override
  Widget build(BuildContext context) {
    final logsRef = FirebaseFirestore.instance
        .collection('violation_cases')
        .doc(caseId)
        .collection('activity')
        .orderBy('createdAt', descending: true)
        .limit(40);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: logsRef.snapshots(),
      builder: (context, snapshot) {
        final activityEntries = <_CaseLogEntry>[];
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final entry = _CaseLogEntry.fromActivity(doc.data());
            if (entry != null) {
              activityEntries.add(entry);
            }
          }
          activityEntries.sort((a, b) {
            final ad = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bd = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bd.compareTo(ad);
          });
        }

        final fallbackEntries = _CaseLogEntry.fallbackFromCase(caseData);
        final entries = activityEntries.isNotEmpty
            ? activityEntries
            : fallbackEntries;

        if (snapshot.hasError && entries.isEmpty) {
          return const Text(
            'Could not load case logs.',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          );
        }

        if (!snapshot.hasData && entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.1),
            ),
          );
        }

        if (entries.isEmpty) {
          return const Text(
            'No case logs yet.',
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          );
        }

        return Column(
          children: entries
              .map((entry) {
                final accentColor = entry.toneColor;
                final when = entry.at == null
                    ? '--'
                    : DateFormat('MMM d, yyyy - h:mm a').format(entry.at!);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.title,
                                    style: const TextStyle(
                                      color: textDark,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13.3,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.pill,
                                    ),
                                    border: Border.all(
                                      color: accentColor.withValues(
                                        alpha: 0.28,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    entry.actionLabel,
                                    style: TextStyle(
                                      color: accentColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (entry.description.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                entry.description,
                                style: const TextStyle(
                                  color: textDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.4,
                                  height: 1.34,
                                ),
                              ),
                            ],
                            const SizedBox(height: 7),
                            Text(
                              '$when${entry.actorRole.isEmpty ? '' : ' - ${entry.actorRole}'}',
                              style: const TextStyle(
                                color: hintColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }
}

class _CaseLogEntry {
  final String event;
  final String title;
  final String description;
  final DateTime? at;
  final String actorRole;

  const _CaseLogEntry({
    required this.event,
    required this.title,
    required this.description,
    required this.at,
    required this.actorRole,
  });

  static _CaseLogEntry? fromActivity(Map<String, dynamic> data) {
    final event = _safeStr(data['event']).toLowerCase();
    if (event.isEmpty) return null;
    final rawMeta = data['meta'];
    final meta = rawMeta is Map
        ? Map<String, dynamic>.from(rawMeta)
        : const <String, dynamic>{};
    final title = _safeStr(data['title']).isEmpty
        ? _defaultTitleForEvent(event)
        : _safeStr(data['title']);
    final description = _descriptionForEvent(
      event: event,
      meta: meta,
      fallback: _safeStr(data['description']),
    );
    final actorRole = _safeStr(data['actorRole']).isEmpty
        ? ''
        : _titleCase(_safeStr(data['actorRole']).replaceAll('_', ' '));
    return _CaseLogEntry(
      event: event,
      title: title,
      description: description,
      at: _dateFromAny(data['createdAt'], data['createdAtEpochMs']),
      actorRole: actorRole,
    );
  }

  static List<_CaseLogEntry> fallbackFromCase(Map<String, dynamic> data) {
    final list = <_CaseLogEntry>[];
    final caseCode = _safeStr(data['caseCode']);
    final correction = data['correction'] as Map<String, dynamic>? ?? {};
    final correctionReason = _safeStr(correction['latestReason']);

    final createdAt = _globalTsToDate(data['createdAt']);
    if (createdAt != null) {
      list.add(
        _CaseLogEntry(
          event: 'report_submitted',
          title: 'Violation report submitted',
          description: caseCode.isEmpty
              ? 'Case was submitted for OSA review.'
              : 'Case $caseCode was submitted for OSA review.',
          at: createdAt,
          actorRole: '',
        ),
      );
    }

    final correctedAt = _globalTsToDate(correction['latestAt']);
    if (correctedAt != null) {
      list.add(
        _CaseLogEntry(
          event: 'osa_correction',
          title: 'Violation report corrected',
          description: correctionReason.isEmpty
              ? 'OSA corrected report details.'
              : 'OSA corrected report details. Reason: $correctionReason',
          at: correctedAt,
          actorRole: 'OSA Admin',
        ),
      );
    }

    final assessedAt = _globalTsToDate(data['assessedAt']);
    if (assessedAt != null) {
      final actionSelected = _safeStr(data['actionSelected']);
      final meetingRequired = data['meetingRequired'] == true;
      final meetingStatus = _safeStr(data['meetingStatus']);
      final finalSeverity = _safeStr(data['finalSeverity']);
      final bookingDeadlineAt = _globalTsToDate(data['bookingDeadlineAt']);
      list.add(
        _CaseLogEntry(
          event: 'osa_action_set',
          title: 'OSA action set',
          description: _descriptionForEvent(
            event: 'osa_action_set',
            meta: {
              'actionSelected': actionSelected,
              'meetingRequired': meetingRequired,
              'meetingStatus': meetingStatus,
              'finalSeverity': finalSeverity,
              'bookingDeadlineAt': bookingDeadlineAt?.toIso8601String(),
            },
            fallback: actionSelected.isEmpty
                ? 'OSA applied a case action.'
                : 'OSA set action to ${_titleCase(actionSelected)}.',
          ),
          at: assessedAt,
          actorRole: 'OSA Admin',
        ),
      );
    }

    final bookingBookedAt = _globalTsToDate(data['bookingBookedAt']);
    final scheduledAt = _globalTsToDate(data['scheduledAt']);
    if (bookingBookedAt != null || scheduledAt != null) {
      list.add(
        _CaseLogEntry(
          event: 'appointment_booked',
          title: 'Meeting booked',
          description: _descriptionForEvent(
            event: 'appointment_booked',
            meta: {
              'scheduledAt': (scheduledAt ?? bookingBookedAt)
                  ?.toIso8601String(),
            },
            fallback: 'A meeting slot was booked for this case.',
          ),
          at: bookingBookedAt ?? scheduledAt,
          actorRole: '',
        ),
      );
    }

    final bookingMissedAt = _globalTsToDate(data['bookingMissedAt']);
    if (bookingMissedAt != null) {
      list.add(
        _CaseLogEntry(
          event: 'booking_missed',
          title: 'Booking not completed',
          description: _descriptionForEvent(
            event: 'booking_missed',
            meta: {
              'bookingDeadlineAt': _globalTsToDate(
                data['bookingDeadlineAt'],
              )?.toIso8601String(),
            },
            fallback: 'Booking window was missed.',
          ),
          at: bookingMissedAt,
          actorRole: '',
        ),
      );
    }

    final meetingMissedAt = _globalTsToDate(data['meetingMissedAt']);
    if (meetingMissedAt != null) {
      list.add(
        _CaseLogEntry(
          event: 'meeting_missed',
          title: 'Meeting missed',
          description: _descriptionForEvent(
            event: 'meeting_missed',
            meta: {'scheduledAt': scheduledAt?.toIso8601String()},
            fallback: 'Scheduled meeting was missed.',
          ),
          at: meetingMissedAt,
          actorRole: '',
        ),
      );
    }

    final unresolvedAt = _globalTsToDate(data['unresolvedAt']);
    if (unresolvedAt != null) {
      list.add(
        _CaseLogEntry(
          event: 'case_unresolved',
          title: 'Case set to unresolved',
          description: _descriptionForEvent(
            event: 'case_unresolved',
            meta: {'reason': _safeStr(data['unresolvedReason'])},
            fallback: 'Case was moved to unresolved status.',
          ),
          at: unresolvedAt,
          actorRole: 'OSA Admin',
        ),
      );
    }

    final rescheduledAt = _globalTsToDate(data['meetingRescheduledAt']);
    if (rescheduledAt != null) {
      list.add(
        _CaseLogEntry(
          event: 'meeting_rescheduled',
          title: 'Meeting rebooking opened',
          description: 'OSA reopened the booking window for this case.',
          at: rescheduledAt,
          actorRole: 'OSA Admin',
        ),
      );
    }

    final completedAt = _globalTsToDate(data['meetingCompletedAt']);
    if (completedAt != null) {
      list.add(
        _CaseLogEntry(
          event: 'meeting_completed',
          title: 'Meeting completed',
          description: _descriptionForEvent(
            event: 'meeting_completed',
            meta: {
              'finalSeverity': _safeStr(data['finalSeverity']),
              'sanctionType': _safeStr(data['sanctionType']).isEmpty
                  ? _safeStr(data['sanctionTypeCode'])
                  : _safeStr(data['sanctionType']),
            },
            fallback: 'OSA completed the meeting and resolved the case.',
          ),
          at: completedAt,
          actorRole: 'OSA Admin',
        ),
      );
    }

    final cancelledAt = _globalTsToDate(data['cancelledAt']);
    if (cancelledAt != null) {
      final reason = _safeStr(data['cancellationReason']);
      list.add(
        _CaseLogEntry(
          event: 'case_cancelled',
          title: 'Case cancelled',
          description: reason.isEmpty
              ? 'OSA cancelled this case.'
              : 'OSA cancelled this case. Reason: $reason',
          at: cancelledAt,
          actorRole: 'OSA Admin',
        ),
      );
    }

    final reopenedAt = _globalTsToDate(data['reopenedAt']);
    if (reopenedAt != null) {
      final reason = _safeStr(data['reopenReason']);
      final reopenedToResolved =
          _statusKey(_safeStr(data['status'])) == 'resolved';
      list.add(
        _CaseLogEntry(
          event: 'case_reopened',
          title: 'Case reopened',
          description: reason.isEmpty
              ? (reopenedToResolved
                    ? 'OSA reopened this cancelled case and moved it back to Resolved.'
                    : 'OSA reopened this cancelled case and applied a new action.')
              : 'OSA reopened this cancelled case. Reason: $reason',
          at: reopenedAt,
          actorRole: 'OSA Admin',
        ),
      );
    }

    final resolvedAt = _globalTsToDate(data['resolvedAt']);
    if (resolvedAt != null &&
        _safeStr(data['status']).toLowerCase().contains('resolved')) {
      list.add(
        _CaseLogEntry(
          event: 'case_resolved',
          title: 'Case resolved',
          description: _descriptionForEvent(
            event: 'case_resolved',
            meta: {
              'finalSeverity': _safeStr(data['finalSeverity']),
              'sanctionType': _safeStr(data['sanctionType']).isEmpty
                  ? _safeStr(data['sanctionTypeCode'])
                  : _safeStr(data['sanctionType']),
            },
            fallback: 'This case was marked as resolved.',
          ),
          at: resolvedAt,
          actorRole: 'OSA Admin',
        ),
      );
    }

    list.sort((a, b) {
      final ad = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return list;
  }

  static DateTime? _dateFromAny(dynamic createdAt, dynamic epoch) {
    if (createdAt is Timestamp) return createdAt.toDate();
    if (createdAt is DateTime) return createdAt;
    if (createdAt is String && createdAt.trim().isNotEmpty) {
      return DateTime.tryParse(createdAt.trim())?.toLocal();
    }
    if (epoch is num) {
      return DateTime.fromMillisecondsSinceEpoch(epoch.toInt());
    }
    return null;
  }

  String get actionLabel {
    final key = event.toLowerCase();
    if (key.contains('reopen')) return 'Reopened';
    if (key.contains('cancel')) return 'Cancelled';
    if (key.contains('resolve')) return 'Resolved';
    if (key.contains('unresolved')) return 'Unresolved';
    if (key.contains('correct')) return 'Corrected';
    if (key.contains('action_set')) return 'Action Set';
    if (key.contains('booked')) return 'Booked';
    if (key.contains('booking_missed')) return 'Not Booked';
    if (key.contains('meeting_missed')) return 'Missed';
    if (key.contains('meeting_completed')) return 'Completed';
    if (key.contains('rescheduled')) return 'Rebook';
    if (key.contains('submit')) return 'Submitted';
    return 'Update';
  }

  Color get toneColor {
    final key = event.toLowerCase();
    if (key.contains('reopen')) return Colors.blue.shade700;
    if (key.contains('cancel')) return Colors.red.shade700;
    if (key.contains('unresolved') || key.contains('missed')) {
      return Colors.orange.shade800;
    }
    if (key.contains('resolve')) return primaryColor;
    if (key.contains('correct')) return Colors.blue.shade700;
    if (key.contains('meeting') || key.contains('booked')) {
      return Colors.indigo.shade600;
    }
    if (key.contains('submit')) return Colors.teal.shade700;
    return hintColor;
  }

  static String _defaultTitleForEvent(String event) {
    final key = event.toLowerCase();
    if (key == 'case_reopened') return 'Case reopened';
    if (key == 'osa_action_set') return 'OSA action set';
    if (key == 'appointment_booked') return 'Meeting booked';
    if (key == 'booking_window_extended') return 'Booking window extended';
    if (key == 'booking_missed') return 'Booking not completed';
    if (key == 'meeting_missed') return 'Meeting missed';
    if (key == 'case_unresolved') return 'Case set to unresolved';
    if (key == 'meeting_completed') return 'Meeting completed';
    if (key == 'case_resolved_without_meeting') return 'Case resolved';
    return _titleCase(key.replaceAll('_', ' '));
  }

  static String _descriptionForEvent({
    required String event,
    required Map<String, dynamic> meta,
    required String fallback,
  }) {
    final key = event.toLowerCase();
    final action = _toTitle(
      _safeStr(meta['actionSelected']).isEmpty
          ? _safeStr(meta['actionTypeCode'])
          : _safeStr(meta['actionSelected']),
    );
    final severity = _toTitle(_safeStr(meta['finalSeverity']));
    final sanction = _toTitle(_safeStr(meta['sanctionType']));
    final scheduledAt = _dateFromAny(meta['scheduledAt'], null);
    final bookingDeadlineAt = _dateFromAny(meta['bookingDeadlineAt'], null);
    final reason = _toTitle(_safeStr(meta['reason']));

    if (key == 'osa_action_set') {
      return 'Action: ${action.isEmpty ? 'Not specified' : action}.';
    }
    if (key == 'appointment_booked') {
      return 'Meeting slot booked'
          '${scheduledAt == null ? '' : ' for ${DateFormat('MMM d, yyyy - h:mm a').format(scheduledAt)}'}.';
    }
    if (key == 'booking_window_extended') {
      return 'Booking window was extended.'
          '${bookingDeadlineAt == null ? '' : ' New deadline: ${DateFormat('MMM d, yyyy - h:mm a').format(bookingDeadlineAt)}.'}';
    }
    if (key == 'booking_missed') {
      return 'Student did not book within the allowed window.'
          '${bookingDeadlineAt == null ? '' : ' Deadline was ${DateFormat('MMM d, yyyy - h:mm a').format(bookingDeadlineAt)}.'}';
    }
    if (key == 'meeting_missed') {
      return 'Student missed the scheduled meeting'
          '${scheduledAt == null ? '' : ' at ${DateFormat('MMM d, yyyy - h:mm a').format(scheduledAt)}'}.';
    }
    if (key == 'case_unresolved') {
      return 'Case moved to Unresolved status.'
          '${reason.isEmpty ? '' : ' Reason: $reason.'}';
    }
    if (key == 'meeting_completed') {
      return 'Required meeting completed.'
          '${severity.isEmpty ? '' : ' Severity: $severity.'}'
          '${sanction.isEmpty ? '' : ' Sanction: $sanction.'}';
    }
    if (key == 'case_resolved' || key == 'case_resolved_without_meeting') {
      return 'Case marked as resolved.'
          '${severity.isEmpty ? '' : ' Severity: $severity.'}'
          '${sanction.isEmpty ? '' : ' Sanction: $sanction.'}';
    }
    if (key == 'meeting_rescheduled') {
      return reason.isEmpty
          ? (fallback.isEmpty
                ? 'OSA reopened the booking window after a missed meeting.'
                : fallback)
          : 'OSA reopened booking window. Reason: $reason.';
    }
    if (key == 'case_reopened') {
      final toStatus = _statusKey(_safeStr(meta['toStatus']));
      return reason.isEmpty
          ? (toStatus == 'resolved'
                ? 'OSA reopened this cancelled case and moved it back to Resolved.'
                : 'OSA reopened this cancelled case and applied a new action.')
          : 'OSA reopened this cancelled case. Reason: $reason.';
    }
    return fallback;
  }

  static String _toTitle(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }
}

class _CancelViolationDialog extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final ViolationCaseService svc;
  final bool asCaseCancellation;

  const _CancelViolationDialog({
    required this.doc,
    required this.svc,
    this.asCaseCancellation = false,
  });

  @override
  State<_CancelViolationDialog> createState() => _CancelViolationDialogState();
}

class _CancelViolationDialogState extends State<_CancelViolationDialog> {
  late final TextEditingController _reasonCtrl;
  bool _saving = false;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _reasonCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _showError = true);
      return;
    }

    setState(() {
      _showError = false;
      _saving = true;
    });

    try {
      await widget.svc.cancelReport(caseId: widget.doc.id, reason: reason);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showInlineNotice(
        context,
        message: 'Cancel failed: $e',
        tone: _InlineNoticeTone.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final caseCode = _safeStr(widget.doc.data()['caseCode']);
    final statusKey = _statusKey(_safeStr(widget.doc.data()['status']));
    final resolvedCase = statusKey == 'resolved';
    final titleText = widget.asCaseCancellation
        ? 'Cancel Case'
        : 'Cancel Report';
    final noteText = widget.asCaseCancellation
        ? (resolvedCase
              ? 'This case is already resolved. Cancelling will move it to Cancelled cases.'
              : 'This will move the case to Cancelled cases.')
        : 'This will move the report to Cancelled cases.';
    final hintText = widget.asCaseCancellation
        ? 'Explain why this case is being cancelled'
        : 'Explain why this report is being cancelled';
    final actionText = widget.asCaseCancellation
        ? 'Cancel Case'
        : 'Cancel Report';
    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
      title: Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
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
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titleText,
              style: const TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              caseCode.isEmpty
                  ? widget.asCaseCancellation
                        ? 'Provide a reason for cancelling this case.'
                        : 'Provide a reason for cancelling this report.'
                  : 'Provide a reason for cancelling $caseCode.',
              style: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
              ),
              child: Text(
                noteText,
                style: const TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              enabled: !_saving,
              maxLines: 4,
              onChanged: (_) {
                if (_showError && _reasonCtrl.text.trim().isNotEmpty) {
                  setState(() => _showError = false);
                }
              },
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: hintText,
                alignLabelWithHint: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide: BorderSide(
                    color: _showError
                        ? Colors.redAccent
                        : Colors.black.withValues(alpha: 0.15),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide: BorderSide(
                    color: _showError
                        ? Colors.redAccent
                        : Colors.black.withValues(alpha: 0.15),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide: BorderSide(
                    color: _showError ? Colors.redAccent : primaryColor,
                    width: 1.35,
                  ),
                ),
                errorText: _showError ? 'Reason is required.' : null,
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
              : const Icon(Icons.cancel_outlined),
          label: Text(_saving ? 'Cancelling...' : actionText),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ReopenCancelledCaseDialog extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final ViolationCaseService svc;

  const _ReopenCancelledCaseDialog({required this.doc, required this.svc});

  @override
  State<_ReopenCancelledCaseDialog> createState() =>
      _ReopenCancelledCaseDialogState();
}

class _ReopenCancelledCaseDialogState
    extends State<_ReopenCancelledCaseDialog> {
  late final TextEditingController _reasonCtrl;
  bool _saving = false;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _reasonCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _showError = true);
      return;
    }

    setState(() {
      _showError = false;
      _saving = true;
    });

    try {
      await widget.svc.reopenCancelledCase(
        caseId: widget.doc.id,
        reason: reason,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showInlineNotice(
        context,
        message: 'Reopen failed: $e',
        tone: _InlineNoticeTone.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final caseCode = _safeStr(widget.doc.data()['caseCode']);
    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
      title: Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
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
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reopen Case',
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              caseCode.isEmpty
                  ? 'Provide a reason for reopening this cancelled case.'
                  : 'Provide a reason for reopening $caseCode.',
              style: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
              ),
              child: const Text(
                'This is already a resolved case. Reopening will move it back to Resolved cases.',
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              enabled: !_saving,
              maxLines: 4,
              onChanged: (_) {
                if (_showError && _reasonCtrl.text.trim().isNotEmpty) {
                  setState(() => _showError = false);
                }
              },
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'Explain why this case is being reopened',
                alignLabelWithHint: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide: BorderSide(
                    color: _showError
                        ? Colors.redAccent
                        : Colors.black.withValues(alpha: 0.15),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide: BorderSide(
                    color: _showError
                        ? Colors.redAccent
                        : Colors.black.withValues(alpha: 0.15),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide: BorderSide(
                    color: _showError ? Colors.redAccent : primaryColor,
                    width: 1.35,
                  ),
                ),
                errorText: _showError ? 'Reason is required.' : null,
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(_saving ? 'Reopening...' : 'Reopen Case'),
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
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
  final _typesSvc = ViolationTypesService();

  late final String _statusKeyAtOpen;
  late final bool _statusAllowsCorrection;
  late final String _initialConcern;
  late String _concern;
  late final String _initialCategoryId;
  late final String _initialCategoryName;
  late final String _initialTypeId;
  late final String _initialTypeName;
  late final DateTime? _expectedUpdatedAt;

  List<String> _concernOptions = const [];
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
    _statusKeyAtOpen = _statusKey(_safeStr(data['status']));
    _statusAllowsCorrection = _canCorrectCaseStatusKey(_statusKeyAtOpen);
    final rawConcern = _normalizeConcernValue(_safeStr(data['concern']));
    _initialConcern = rawConcern;
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
    _loadConcernOptionsAndCategories();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConcernOptionsAndCategories() async {
    setState(() => _loadingOptions = true);
    try {
      var options = await _typesSvc.fetchActiveConcernOptions();
      final selected = _concern.trim().toLowerCase();
      if (selected.isNotEmpty &&
          !options.any((item) => item.toLowerCase() == selected)) {
        options = List<String>.from(options)..add(selected);
      }
      if (selected.isEmpty && options.isNotEmpty) {
        _concern = options.first;
      }
      if (!mounted) return;
      setState(() => _concernOptions = options);
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
    await _loadCategoriesAndTypes();
  }

  Future<void> _loadCategoriesAndTypes() async {
    setState(() => _loadingOptions = true);
    try {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> categories = const [];
      final normalizedConcern = _concern.trim().toLowerCase();
      if (normalizedConcern.isNotEmpty) {
        final strictConcernSnap = await FirebaseFirestore.instance
            .collection('violation_categories')
            .where('isActive', isEqualTo: true)
            .where('concern', isEqualTo: normalizedConcern)
            .orderBy('order')
            .get();
        categories = strictConcernSnap.docs;
      }
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
              'Concern: ${_titleCase(fromConcern)} Ã¢â€ â€™ ${_titleCase(toConcern)}',
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Category: $fromCategory Ã¢â€ â€™ $toCategory',
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Specific Violation: $fromType Ã¢â€ â€™ $toType',
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
    if (!_statusAllowsCorrection) {
      _showInlineNotice(
        context,
        message: 'Correction is not allowed for this case status.',
        tone: _InlineNoticeTone.warning,
      );
      return;
    }
    if (!_hasCorrectionChanges()) {
      _showInlineNotice(
        context,
        message: 'No changes detected. Update at least one field.',
        tone: _InlineNoticeTone.neutral,
      );
      return;
    }
    if (_reasonCtrl.text.trim().isEmpty) {
      _showInlineNotice(
        context,
        message: 'Correction reason is required.',
        tone: _InlineNoticeTone.warning,
      );
      return;
    }
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
      _showInlineNotice(
        context,
        message: message,
        tone: _InlineNoticeTone.danger,
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasChanges = _hasCorrectionChanges();
    final canSaveChanges =
        _statusAllowsCorrection &&
        !_saving &&
        !_loadingOptions &&
        (_selectedCategoryId?.isNotEmpty ?? false) &&
        (_selectedTypeId?.isNotEmpty ?? false) &&
        hasChanges &&
        _reasonCtrl.text.trim().isNotEmpty;
    final fieldEnabled =
        _statusAllowsCorrection && !_saving && !_loadingOptions;

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
              if (!_statusAllowsCorrection) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: const Color(0xFFB7791F)),
                  ),
                  child: Text(
                    'Correction is locked for status: ${_titleCase(_statusKeyAtOpen)}.',
                    style: const TextStyle(
                      color: Color(0xFF8C5A12),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.4,
                    ),
                  ),
                ),
              ],
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
                initialValue: _concern.trim().isEmpty ? null : _concern,
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
  bool _loadingConfig = true;
  String? _configError;
  List<String> _severities = const [];
  List<Map<String, String>> _sanctionOptions = const [];

  Future<void> _loadDialogConfig() async {
    setState(() {
      _loadingConfig = true;
      _configError = null;
    });
    try {
      final results = await Future.wait([
        _typesSvc.fetchSeverityLevels(),
        _typesSvc.fetchActiveSanctionTypes(),
      ]);
      final severityOptions = (results[0] as List<String>)
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      final effectiveSeverityOptions = severityOptions.isEmpty
          ? const <String>['Minor', 'Moderate', 'Major']
          : severityOptions;
      final sanctionRows = results[1] as List<Map<String, dynamic>>;
      final sanctionOptions = sanctionRows
          .map(
            (row) => <String, String>{
              'code': (row['id'] ?? '').toString().trim().toLowerCase(),
              'label': (row['label'] ?? '').toString().trim(),
            },
          )
          .where((row) => (row['code'] ?? '').isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _severities = effectiveSeverityOptions;
        _sanctionOptions = sanctionOptions;
        _severity =
            _severity != null &&
                _severities.any(
                  (item) => item.toLowerCase() == _severity!.toLowerCase(),
                )
            ? _severity
            : null;
        _sanctionType =
            _sanctionType != null &&
                _sanctionOptions.any((item) => item['code'] == _sanctionType)
            ? _sanctionType
            : (_sanctionOptions.isEmpty
                  ? null
                  : _sanctionOptions.first['code']);
        if (_sanctionOptions.isEmpty) {
          _configError =
              'Missing violation config. Please seed or add Sanction Types in Violation Settings.';
        }
        _loadingConfig = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingConfig = false;
        _configError =
            'Unable to load violation config. Please check your Firestore data.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDialogConfig();
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
              if (_loadingConfig)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(color: primaryColor),
                )
              else if (_configError != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _configError!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
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
                onChanged: _saving || _loadingConfig
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
                onChanged: _saving || _loadingConfig
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
              _saving ||
                  _loadingConfig ||
                  _configError != null ||
                  _notesCtrl.text.trim().isEmpty ||
                  _severity == null ||
                  _sanctionType == null
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await widget.svc.completeMeeting(
                      caseId: widget.caseId,
                      meetingNotes: _notesCtrl.text,
                      finalSeverity: _severity!,
                      sanctionType: _sanctionType!,
                      facultyNote: _facultyNoteCtrl.text,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    _showInlineNotice(
                      context,
                      message: 'Resolve failed: $e',
                      tone: _InlineNoticeTone.danger,
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

class _StudentHistorySection extends StatefulWidget {
  final String studentUid;
  final String currentCaseId;
  final String currentViolationType;
  final String currentCategory;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>>? onOpenCase;
  final bool showCurrentOffenseSummary;

  const _StudentHistorySection({
    required this.studentUid,
    required this.currentCaseId,
    required this.currentViolationType,
    required this.currentCategory,
    this.onOpenCase,
    this.showCurrentOffenseSummary = true,
  });

  @override
  State<_StudentHistorySection> createState() => _StudentHistorySectionState();
}

class _StudentHistorySectionState extends State<_StudentHistorySection> {
  final Set<String> _expandedCategories = <String>{};
  bool _showAllCategories = false;

  static const int _initialCategoryCount = 3;

  String _normalizeCategoryKey(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == '--' || value == 'uncategorized') {
      return 'uncategorized';
    }
    return value;
  }

  String _displayCategoryLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '--') return 'Uncategorized';
    return value;
  }

  DateTime? _historyDate(Map<String, dynamic> data) {
    return _globalTsToDate(data['createdAt']) ??
        _globalTsToDate(data['incidentAt']) ??
        _globalTsToDate(data['reportedAt']);
  }

  bool _isExcludedFromOffenseHistory(Map<String, dynamic> data) {
    return _statusKey(_safeStr(data['status'])) == 'cancelled';
  }

  String _ordinal(int value) {
    if (value <= 0) return '${value}th';
    final mod100 = value % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${value}th';
    switch (value % 10) {
      case 1:
        return '${value}st';
      case 2:
        return '${value}nd';
      case 3:
        return '${value}rd';
      default:
        return '${value}th';
    }
  }

  bool _isConnected(String type, String current) {
    final t = type.toLowerCase();
    final c = current.toLowerCase();
    if (t == c) return true;

    final tardinessKeywords = ['tardy', 'late', 'absent', 'attendance'];
    final typeIsTardiness = tardinessKeywords.any((k) => t.contains(k));
    final currentIsTardiness = tardinessKeywords.any((k) => c.contains(k));
    return typeIsTardiness && currentIsTardiness;
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required String categoryKey,
    required String categoryLabel,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> priorCases,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>>
    allCasesInCategory,
    required bool isCurrentCategory,
  }) {
    final isExpanded = _expandedCategories.contains(categoryKey);
    final sortedAll = [...allCasesInCategory]
      ..sort((a, b) {
        final da = _historyDate(a.data()) ?? DateTime(2000);
        final db = _historyDate(b.data()) ?? DateTime(2000);
        final byDate = da.compareTo(
          db,
        ); // oldest to latest => first offense to latest
        if (byDate != 0) return byDate;
        return a.id.compareTo(b.id);
      });
    final sorted = [...priorCases]
      ..sort((a, b) {
        final da = _historyDate(a.data()) ?? DateTime(2000);
        final db = _historyDate(b.data()) ?? DateTime(2000);
        final byDate = da.compareTo(
          db,
        ); // oldest to latest => first offense to latest
        if (byDate != 0) return byDate;
        return a.id.compareTo(b.id);
      });

    final totalInCategory = sortedAll.length;
    final currentIndexInCategory = isCurrentCategory
        ? sortedAll.indexWhere((doc) => doc.id == widget.currentCaseId) + 1
        : 0;
    final subtitle = (widget.showCurrentOffenseSummary && isCurrentCategory)
        ? (currentIndexInCategory <= 1
              ? 'Current case appears to be the 1st offense in this category.'
              : 'Current case is the ${_ordinal(currentIndexInCategory)} offense in this category.')
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrentCategory
              ? primaryColor.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove(categoryKey);
                } else {
                  _expandedCategories.add(categoryKey);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                '$categoryLabel ($totalInCategory)',
                                style: TextStyle(
                                  color: isCurrentCategory
                                      ? primaryColor
                                      : textDark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: hintColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: primaryColor,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            if (sorted.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No prior offense records yet for this category.',
                  style: TextStyle(
                    color: hintColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.8,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: sorted
                      .asMap()
                      .entries
                      .map((entry) {
                        final caseDoc = entry.value;
                        final offenseIndex =
                            sortedAll.indexWhere(
                              (doc) => doc.id == caseDoc.id,
                            ) +
                            1;
                        final data = caseDoc.data();
                        final type = _safeStr(
                          data['violationTypeLabel'] ??
                              data['violationNameSnapshot'] ??
                              data['violationName'],
                        );
                        final status = _statusLabel(_safeStr(data['status']));
                        final severity = _safeStr(
                          data['finalSeverity'] ?? data['concern'],
                        );
                        final date = _historyDate(data);
                        final dateText = date == null
                            ? '--'
                            : DateFormat('MMM d, yyyy').format(date);
                        final linked = _isConnected(
                          type,
                          widget.currentViolationType,
                        );
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: () {
                              showDialog<void>(
                                context: context,
                                builder: (_) => _HistoryCaseDetailsDialog(
                                  caseDoc: caseDoc,
                                  offenseLabel:
                                      '${_ordinal(offenseIndex)} Offense',
                                  categoryLabel: categoryLabel,
                                  onOpenCase: widget.onOpenCase,
                                ),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: linked
                                    ? primaryColor.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: linked
                                      ? primaryColor.withValues(alpha: 0.20)
                                      : Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_ordinal(offenseIndex)} Offense',
                                          style: TextStyle(
                                            color: linked
                                                ? primaryColor
                                                : textDark,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          type.isEmpty ? '--' : type,
                                          style: const TextStyle(
                                            color: textDark,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12.2,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$dateText - $status${severity.isEmpty ? '' : ' - ${_titleCase(severity)}'}',
                                          style: const TextStyle(
                                            color: hintColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11.1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.open_in_new_rounded,
                                    color: primaryColor,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.studentUid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('violation_cases')
          .where('studentUid', isEqualTo: widget.studentUid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          );
        }

        final allDocs = snapshot.data!.docs;
        final activeDocs = allDocs
            .where((doc) => !_isExcludedFromOffenseHistory(doc.data()))
            .toList(growable: false);
        final priorDocs = activeDocs
            .where((d) => d.id != widget.currentCaseId)
            .toList(growable: false);

        final groupedByKey =
            <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        final groupedAllByKey =
            <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        final labelsByKey = <String, String>{};
        for (final doc in activeDocs) {
          final rawCategory = _categoryLabelFromCaseGlobal(doc.data());
          final categoryKey = _normalizeCategoryKey(rawCategory);
          groupedAllByKey.putIfAbsent(categoryKey, () => []).add(doc);
        }
        for (final doc in priorDocs) {
          final rawCategory = _categoryLabelFromCaseGlobal(doc.data());
          final categoryKey = _normalizeCategoryKey(rawCategory);
          final categoryLabel = _displayCategoryLabel(rawCategory);
          groupedByKey.putIfAbsent(categoryKey, () => []).add(doc);
          labelsByKey.putIfAbsent(categoryKey, () => categoryLabel);
        }

        final currentCategoryKey = _normalizeCategoryKey(
          widget.currentCategory,
        );
        final currentCategoryLabel = _displayCategoryLabel(
          widget.currentCategory,
        );
        if (!groupedByKey.containsKey(currentCategoryKey)) {
          groupedByKey[currentCategoryKey] =
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        }
        if (!groupedAllByKey.containsKey(currentCategoryKey)) {
          groupedAllByKey[currentCategoryKey] =
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        }
        labelsByKey[currentCategoryKey] = currentCategoryLabel;

        if (priorDocs.isEmpty && groupedByKey.length <= 1) {
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

        final entries = groupedByKey.entries.toList()
          ..sort((a, b) {
            final aIsCurrent = a.key == currentCategoryKey;
            final bIsCurrent = b.key == currentCategoryKey;
            if (aIsCurrent && !bIsCurrent) return -1;
            if (!aIsCurrent && bIsCurrent) return 1;
            final byCount = b.value.length.compareTo(a.value.length);
            if (byCount != 0) return byCount;
            return a.key.toLowerCase().compareTo(b.key.toLowerCase());
          });

        final visibleEntries = _showAllCategories
            ? entries
            : entries.take(_initialCategoryCount).toList(growable: false);

        return Column(
          children: [
            ...visibleEntries.map((entry) {
              return _buildCategoryCard(
                context,
                categoryKey: entry.key,
                categoryLabel: labelsByKey[entry.key] ?? 'Uncategorized',
                priorCases: entry.value,
                allCasesInCategory:
                    groupedAllByKey[entry.key] ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                isCurrentCategory: entry.key == currentCategoryKey,
              );
            }),
            if (entries.length > _initialCategoryCount)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _showAllCategories = !_showAllCategories);
                  },
                  icon: Icon(
                    _showAllCategories
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: primaryColor,
                  ),
                  label: Text(
                    _showAllCategories
                        ? 'Show less categories'
                        : 'See more categories',
                    style: const TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HistoryCaseDetailsDialog extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> caseDoc;
  final String offenseLabel;
  final String categoryLabel;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>>? onOpenCase;

  const _HistoryCaseDetailsDialog({
    required this.caseDoc,
    required this.offenseLabel,
    required this.categoryLabel,
    this.onOpenCase,
  });

  static Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 122,
          child: Text(
            '$k:',
            style: const TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w900,
              fontSize: 12.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w700,
              fontSize: 12.4,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = caseDoc.data();
    final caseCode = _safeStr(d['caseCode']).isEmpty
        ? caseDoc.id
        : _safeStr(d['caseCode']);
    final violation = _safeStr(
      d['violationTypeLabel'] ??
          d['violationNameSnapshot'] ??
          d['violationName'],
    );
    final status = _statusLabel(_safeStr(d['status']));
    final severity = _safeStr(d['finalSeverity'] ?? d['concern']);
    final reportedAt =
        _globalTsToDate(d['createdAt']) ?? _globalTsToDate(d['reportedAt']);
    final incidentAt = _globalTsToDate(d['incidentAt']);
    final reportedBy = _reportedByDisplay(d);
    final narrative = _safeStr(d['narrative'] ?? d['description']);

    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              offenseLabel,
              style: const TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: hintColor),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Case Code', caseCode),
              const SizedBox(height: 8),
              _kv('Category', categoryLabel),
              const SizedBox(height: 8),
              _kv('Violation Type', violation.isEmpty ? '--' : violation),
              const SizedBox(height: 8),
              _kv('Status', status),
              const SizedBox(height: 8),
              _kv('Severity', severity.isEmpty ? '--' : _titleCase(severity)),
              const SizedBox(height: 8),
              _kv(
                'Date Reported',
                reportedAt == null
                    ? '--'
                    : DateFormat('MMM d, yyyy - h:mm a').format(reportedAt),
              ),
              const SizedBox(height: 8),
              _kv(
                'Date of Incident',
                incidentAt == null
                    ? '--'
                    : DateFormat('MMM d, yyyy - h:mm a').format(incidentAt),
              ),
              const SizedBox(height: 8),
              _kv('Reported By', reportedBy),
              if (narrative.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Incident Summary',
                  style: TextStyle(
                    color: hintColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.2,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
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
                      fontWeight: FontWeight.w700,
                      fontSize: 12.4,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        if (onOpenCase != null)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onOpenCase?.call(caseDoc);
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open Case'),
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryColor,
              side: BorderSide(color: primaryColor.withValues(alpha: 0.35)),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (_) => _CaseLogsDialog(caseId: caseDoc.id, caseData: d),
            );
          },
          icon: const Icon(Icons.history_rounded),
          label: const Text('Case Logs'),
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ======================================================================
// ASSIGN ACTION DIALOG
// ======================================================================

class _SetActionOption {
  final String code;
  final String label;
  final bool meetingRequired;
  final int bookingWindowDays;
  final int graceWindowDays;

  const _SetActionOption({
    required this.code,
    required this.label,
    required this.meetingRequired,
    this.bookingWindowDays = 3,
    this.graceWindowDays = 2,
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
  final _academicSvc = AcademicSettingsService();
  String? _severity;
  String? _action;
  String? _meetingTimeframeKey;
  bool _submitting = false;
  bool _checkingTimeframeSlots = false;
  bool _hasSlotsInTimeframe = true;
  bool _hasGeneratedScheduleForTerm = true;
  String? _timeframeSlotMessage;
  int _timeframeValidationSeq = 0;
  final TextEditingController _reopenReasonCtrl = TextEditingController();
  bool _showReopenReasonError = false;
  bool _loadingConfig = true;
  String? _configError;

  List<String> _severities = const [];
  List<_SetActionOption> _reviewActions = const [];
  List<_SetActionOption> _monitorActions = const [];

  Future<void> _loadDialogConfig() async {
    setState(() {
      _loadingConfig = true;
      _configError = null;
    });
    try {
      final results = await Future.wait([
        _typesSvc.fetchActiveActionTypes(),
        _typesSvc.fetchSeverityLevels(),
      ]);
      final actionRows = results[0] as List<Map<String, dynamic>>;
      final severityRows = results[1] as List<String>;
      final reviewActions = actionRows
          .map((row) {
            final code = (row['id'] ?? '').toString().trim().toLowerCase();
            final meetingRequired = row['meetingRequired'] == true;
            final fallbackBooking =
                code == ViolationSetActionTypes.immediateActionRequired
                ? ViolationSetActionTypes.immediateBookingWindowDays
                : ViolationSetActionTypes.defaultBookingWindowDays;
            final fallbackGrace =
                code == ViolationSetActionTypes.immediateActionRequired
                ? 0
                : ViolationSetActionTypes.bookingGraceExtensionDays;
            return _SetActionOption(
              code: code,
              label: (row['label'] ?? '').toString().trim(),
              meetingRequired: meetingRequired,
              bookingWindowDays:
                  ((row['bookingWindowDays'] as num?)?.toInt() ??
                  fallbackBooking),
              graceWindowDays: meetingRequired
                  ? ((row['graceWindowDays'] as num?)?.toInt() ?? fallbackGrace)
                  : 0,
            );
          })
          .where((row) => row.code.isNotEmpty && row.label.isNotEmpty)
          .toList(growable: false);
      final monitorActions = reviewActions;
      final severities = severityRows
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      final effectiveSeverities = severities.isEmpty
          ? const <String>['Minor', 'Moderate', 'Major']
          : severities;
      if (!mounted) return;
      final status = _safeStr(widget.doc.data()['status']).toLowerCase();
      final isMonitor =
          status == 'action set' ||
          status == 'unresolved' ||
          status == 'resolved';
      final actionLabels = isMonitor
          ? monitorActions.map((item) => item.label).toList(growable: false)
          : reviewActions.map((item) => item.label).toList(growable: false);
      String? matchedAction;
      final currentKey = widget.currentAction.toLowerCase();
      for (final label in actionLabels) {
        if (currentKey.contains(label.split('(')[0].trim().toLowerCase())) {
          matchedAction = label;
          break;
        }
      }
      matchedAction ??= actionLabels.isEmpty ? null : actionLabels.first;
      String? matchedSeverity;
      if (effectiveSeverities.any(
        (item) => item.toLowerCase() == widget.currentSeverity.toLowerCase(),
      )) {
        matchedSeverity = effectiveSeverities.firstWhere(
          (item) => item.toLowerCase() == widget.currentSeverity.toLowerCase(),
        );
      }
      setState(() {
        _reviewActions = reviewActions;
        _monitorActions = monitorActions;
        _severities = effectiveSeverities;
        _action = matchedAction;
        _severity = matchedSeverity;
        _meetingTimeframeKey = _defaultMeetingTimeframeKeyForAction(_action);
        if ((!isMonitor && reviewActions.isEmpty) ||
            (isMonitor && monitorActions.isEmpty)) {
          _configError =
              'Missing violation config. Please seed Action Types in Violation Settings.';
        }
        _loadingConfig = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingConfig = false;
        _configError =
            'Unable to load violation config. Please check Firestore.';
      });
    }
    _validateTimeframeSlots();
  }

  _SetActionOption? _actionOptionForLabel(String? label) {
    if (label == null || label.trim().isEmpty) return null;
    for (final item in _reviewActions) {
      if (item.label == label) return item;
    }
    return null;
  }

  String? _actionCodeForLabel(String? label) {
    return _actionOptionForLabel(label)?.code;
  }

  bool _isImmediateActionRequired(String? actionLabel) {
    if (actionLabel == null || actionLabel.trim().isEmpty) return false;
    final configuredCode = _actionOptionForLabel(actionLabel)?.code;
    return configuredCode == ViolationSetActionTypes.immediateActionRequired;
  }

  String _defaultMeetingTimeframeKeyForAction(String? actionLabel) {
    final bookingDays = _initialBookingDaysForAction(actionLabel);
    return '${bookingDays}days';
  }

  int _initialBookingDaysForAction(String? actionLabel) {
    final option = _actionOptionForLabel(actionLabel);
    final configuredDays = option?.bookingWindowDays ?? 0;
    if (configuredDays > 0) return configuredDays;
    return _isImmediateActionRequired(actionLabel)
        ? ViolationSetActionTypes.immediateBookingWindowDays
        : ViolationSetActionTypes.defaultBookingWindowDays;
  }

  int _graceBookingDaysForAction(String? actionLabel) {
    final option = _actionOptionForLabel(actionLabel);
    if (option == null) return _isImmediateActionRequired(actionLabel) ? 0 : 2;
    if (!option.meetingRequired) return 0;
    final configuredDays = option.graceWindowDays;
    return configuredDays < 0 ? 0 : configuredDays;
  }

  String _bookingWindowSummaryForAction(String? actionLabel) {
    final initialDays = _initialBookingDaysForAction(actionLabel);
    final graceDays = _graceBookingDaysForAction(actionLabel);
    if (graceDays == 0) {
      return 'Initial booking window: $initialDays days (no auto extension)';
    }
    return 'Initial booking window: $initialDays days '
        '(+$graceDays-day auto extension)';
  }

  bool _isMeetingRequiredAction(String actionLabel) {
    final configured = _reviewActions.where(
      (item) => item.label == actionLabel,
    );
    if (configured.isNotEmpty) return configured.first.meetingRequired;
    return false;
  }

  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59);

  Future<Map<String, dynamic>?> _resolveMeetingSlotContext() async {
    try {
      final activeSy = await _academicSvc.getActiveSY();
      final activeSchoolYearId = _safeStr(activeSy?['id']);
      final activeTermId = _safeStr(activeSy?['activeTermId']);
      if (activeSchoolYearId.isNotEmpty && activeTermId.isNotEmpty) {
        return <String, dynamic>{
          'schoolYearId': activeSchoolYearId,
          'termId': activeTermId,
          'fromActive': true,
        };
      }
    } catch (_) {}

    final caseSchoolYearId = _safeStr(widget.doc.data()['schoolYearId']);
    final caseTermId = _safeStr(widget.doc.data()['termId']);
    if (caseSchoolYearId.isEmpty || caseTermId.isEmpty) {
      return null;
    }
    return <String, dynamic>{
      'schoolYearId': caseSchoolYearId,
      'termId': caseTermId,
      'fromActive': false,
    };
  }

  DateTime _meetingDueByForKey(String key) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final normalized = key.trim().toLowerCase();
    final dynamicDays = RegExp(r'^(\d+)\s*days?$').firstMatch(normalized);
    if (dynamicDays != null) {
      final parsed = int.tryParse(dynamicDays.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return _endOfDay(today.add(Duration(days: parsed)));
      }
    }
    switch (normalized) {
      case 'today':
        return _endOfDay(today);
      case '2days':
        return _endOfDay(today.add(const Duration(days: 2)));
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
        _hasGeneratedScheduleForTerm = true;
        _timeframeSlotMessage = null;
      });
      return;
    }

    final timeframe =
        (_meetingTimeframeKey == null || _meetingTimeframeKey!.isEmpty)
        ? _defaultMeetingTimeframeKeyForAction(_action)
        : _meetingTimeframeKey!;

    final slotContext = await _resolveMeetingSlotContext();
    if (slotContext == null) {
      if (!mounted) return;
      setState(() {
        _checkingTimeframeSlots = false;
        _hasSlotsInTimeframe = false;
        _hasGeneratedScheduleForTerm = false;
        _timeframeSlotMessage =
            'This case has no linked school year/term. Cannot validate available meeting slots.';
      });
      return;
    }
    final schoolYearId = (slotContext['schoolYearId'] as String?) ?? '';
    final termId = (slotContext['termId'] as String?) ?? '';
    final fromActive = slotContext['fromActive'] == true;

    final seq = ++_timeframeValidationSeq;
    if (!mounted) return;
    setState(() {
      _checkingTimeframeSlots = true;
      _timeframeSlotMessage = null;
    });

    try {
      final hasGeneratedSchedule = await _scheduleSvc.hasSlotsForTerm(
        schoolYearId: schoolYearId,
        termId: termId,
      );
      if (!mounted || seq != _timeframeValidationSeq) return;
      if (!hasGeneratedSchedule) {
        setState(() {
          _checkingTimeframeSlots = false;
          _hasGeneratedScheduleForTerm = false;
          _hasSlotsInTimeframe = false;
          _timeframeSlotMessage =
              'No generated meeting schedule found for this school year/semester. Generate slots in Meeting Schedule first.';
        });
        return;
      }

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
        _hasGeneratedScheduleForTerm = true;
        _hasSlotsInTimeframe = count > 0;
        _timeframeSlotMessage = count > 0
            ? '$count open slot(s) available for the current booking window${fromActive ? ' in the active term' : ''}.'
            : 'No available slots for the current booking window${fromActive ? ' in the active term' : ''}. Please update meeting schedule.';
      });
    } catch (_) {
      if (!mounted || seq != _timeframeValidationSeq) return;
      setState(() {
        _checkingTimeframeSlots = false;
        _hasGeneratedScheduleForTerm = false;
        _hasSlotsInTimeframe = false;
        _timeframeSlotMessage =
            'Unable to validate available slots right now. Please try again.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDialogConfig();
  }

  @override
  void dispose() {
    _reopenReasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 760;
    final dialogWidth = compact ? (viewport.width * 0.95) : 500.0;
    final status = _safeStr(widget.doc.data()['status']).toLowerCase();
    final isCancelled = status == 'cancelled';
    final isMonitor =
        status == 'action set' ||
        status == 'unresolved' ||
        status == 'resolved';
    final actionOptions = isMonitor ? _monitorActions : _reviewActions;
    final actions = actionOptions
        .map((item) => item.label)
        .toList(growable: false);
    final selectedMeetingAction =
        !isMonitor && _action != null && _isMeetingRequiredAction(_action!);
    final willResolveImmediately =
        !isMonitor && _action != null && !selectedMeetingAction;
    final showTimeframeSection = _action != null && selectedMeetingAction;
    final showSeveritySection = _action != null && !showTimeframeSection;
    final requiresSeverity = showSeveritySection;
    final title = isCancelled
        ? 'Reopen + Set Action'
        : (isMonitor ? 'Update Monitoring' : 'Assign Assessment');
    final subtitle = isCancelled
        ? 'Provide a reason for reopening, then assign the next action.'
        : (isMonitor
              ? 'Update the monitoring status or follow-up action.'
              : 'Set the severity and required action for this case.');

    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 24,
        vertical: compact ? 10 : 24,
      ),
      titlePadding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        compact ? 14 : 20,
        compact ? 18 : 24,
        0,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        12,
        compact ? 18 : 24,
        0,
      ),
      actionsPadding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        8,
        compact ? 12 : 16,
        compact ? 12 : 14,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SizedBox(
        width: dialogWidth,
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
              if (_loadingConfig)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(color: primaryColor),
                )
              else if (_configError != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _configError!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (isCancelled) ...[
                const Text(
                  'Reopen reason (Required)',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reopenReasonCtrl,
                  enabled: !_submitting,
                  minLines: 2,
                  maxLines: 3,
                  onChanged: (_) {
                    if (_showReopenReasonError &&
                        _reopenReasonCtrl.text.trim().isNotEmpty) {
                      setState(() => _showReopenReasonError = false);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Why are you reopening this cancelled case?',
                    filled: true,
                    fillColor: Colors.white,
                    errorText: _showReopenReasonError
                        ? 'Reopen reason is required.'
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide(
                        color: _showReopenReasonError
                            ? Colors.redAccent
                            : Colors.black.withValues(alpha: 0.15),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide(
                        color: _showReopenReasonError
                            ? Colors.redAccent
                            : Colors.black.withValues(alpha: 0.15),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide(
                        color: _showReopenReasonError
                            ? Colors.redAccent
                            : primaryColor,
                        width: 1.35,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
              if (actions.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    isMonitor
                        ? 'No active action types configured.'
                        : 'No active action types configured.',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ...actions.map((a) {
                final selected = _action == a;
                final needsMeeting = !isMonitor && _isMeetingRequiredAction(a);
                return GestureDetector(
                  onTap: _loadingConfig
                      ? null
                      : () {
                          setState(() {
                            _action = a;
                            if (!isMonitor && _isMeetingRequiredAction(a)) {
                              _meetingTimeframeKey =
                                  _defaultMeetingTimeframeKeyForAction(a);
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
                  child: Text(
                    _bookingWindowSummaryForAction(_action),
                    style: const TextStyle(
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
          onPressed:
              (_loadingConfig ||
                  _configError != null ||
                  _action == null ||
                  _submitting)
              ? null
              : (requiresSeverity && (_severity == null || _severity!.isEmpty))
              ? null
              : (showTimeframeSection &&
                    (_meetingTimeframeKey == null ||
                        _meetingTimeframeKey!.isEmpty))
              ? null
              : (showTimeframeSection && !_hasGeneratedScheduleForTerm)
              ? null
              : (showTimeframeSection && _checkingTimeframeSlots)
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
                  isCancelled
                      ? 'Reopen + Apply Action'
                      : (willResolveImmediately
                            ? 'Resolve Case'
                            : 'Confirm Action'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final status = _safeStr(widget.doc.data()['status']).toLowerCase();
    final isCancelled = status == 'cancelled';
    final reopenReason = _reopenReasonCtrl.text.trim();
    if (isCancelled && reopenReason.isEmpty) {
      setState(() => _showReopenReasonError = true);
      return;
    }

    setState(() {
      _submitting = true;
      _showReopenReasonError = false;
    });
    try {
      final isMonitor =
          status == 'action set' ||
          status == 'unresolved' ||
          status == 'resolved';
      final isMeetingRequired =
          _action != null && _isMeetingRequiredAction(_action!);
      String? meetingSchoolYearIdForSubmit;
      String? meetingTermIdForSubmit;
      if (isMeetingRequired) {
        final slotContext = await _resolveMeetingSlotContext();
        if (slotContext == null) {
          if (mounted &&
              await _showNoMeetingScheduleDialog(
                message:
                    'Cannot set meeting action because active school year/semester is not configured.',
              )) {
            _openMeetingScheduleFromDialog();
          }
          if (mounted) setState(() => _submitting = false);
          return;
        }
        meetingSchoolYearIdForSubmit = (slotContext['schoolYearId'] as String?)
            ?.trim();
        meetingTermIdForSubmit = (slotContext['termId'] as String?)?.trim();
        if (!_hasGeneratedScheduleForTerm) {
          if (mounted &&
              await _showNoMeetingScheduleDialog(
                message:
                    'No generated meeting schedule found for the selected school year/semester.',
              )) {
            _openMeetingScheduleFromDialog();
          }
          if (mounted) setState(() => _submitting = false);
          return;
        }
      }
      if (isMeetingRequired &&
          (_checkingTimeframeSlots || !_hasSlotsInTimeframe)) {
        final initialDays = _initialBookingDaysForAction(_action);
        if (mounted &&
            await _showNoMeetingScheduleDialog(
              message:
                  'No available meeting slots for the initial '
                  '$initialDays-day booking window.',
            )) {
          _openMeetingScheduleFromDialog();
        }
        if (mounted) setState(() => _submitting = false);
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
        meetingSchoolYearId: meetingSchoolYearIdForSubmit,
        meetingTermId: meetingTermIdForSubmit,
        reopenReason: isCancelled ? reopenReason : null,
        meetingRequiredOverride: !isMonitor ? isMeetingRequired : null,
        actionReason: null,
        meetingStatus: isMeetingRequired ? 'pending_student_booking' : null,
        meetingWindow: isMeetingRequired
            ? (_meetingTimeframeKey ??
                  _defaultMeetingTimeframeKeyForAction(_action))
            : null,
        meetingDueBy: isMeetingRequired
            ? _meetingDueByForKey(
                _meetingTimeframeKey ??
                    _defaultMeetingTimeframeKeyForAction(_action),
              )
            : null,
        scheduledAt: null,
        meetingLocation: null,
        officialRemarks: null,
        internalNotes: null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        _showInlineNotice(
          context,
          message: 'Error: $e',
          tone: _InlineNoticeTone.danger,
        );
        setState(() => _submitting = false);
      }
    }
  }

  Future<bool> _showNoMeetingScheduleDialog({required String message}) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No Meeting Schedule',
                style: TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          '$message\n\nSet up or sync Meeting Schedule first before assigning a meeting-required action.',
          style: const TextStyle(
            color: hintColor,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w900, color: hintColor),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: const Text(
              'Open Meeting Schedule',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    return open == true;
  }

  void _openMeetingScheduleFromDialog() {
    final rootNav = Navigator.of(context, rootNavigator: true);
    rootNav.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rootNav.push(
        MaterialPageRoute<void>(builder: (_) => const MeetingSchedulePage()),
      );
    });
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
    final normalized = concern.trim().toLowerCase();
    final isSerious = normalized.contains('serious');
    final isBasic = normalized.contains('basic');
    final fill = isSerious
        ? Colors.orange.withValues(alpha: 0.12)
        : isBasic
        ? primaryColor.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);
    final border = isSerious
        ? Colors.orange.withValues(alpha: 0.30)
        : isBasic
        ? primaryColor.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.12);
    final textColor = isSerious
        ? Colors.orange.shade900
        : isBasic
        ? primaryColor
        : hintColor;

    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final Widget? titleTrailing;
  final Widget child;

  const _DetailCard({
    required this.title,
    this.titleTrailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (titleTrailing != null) ...[
                const SizedBox(width: 8),
                titleTrailing!,
              ],
            ],
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
final Map<String, Future<String>> _studentPhotoFutureCache =
    <String, Future<String>>{};
final Map<String, Future<_OffenseIndicator>> _offenseIndicatorFutureCache =
    <String, Future<_OffenseIndicator>>{};

class _OffenseIndicator {
  final String label;
  final String subtitle;
  final int offenseNumber;

  const _OffenseIndicator({
    required this.label,
    required this.subtitle,
    required this.offenseNumber,
  });
}

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

Future<String> _resolveStudentPhotoUrl(String studentUid) {
  final uid = _safeStr(studentUid);
  if (uid.isEmpty) {
    return Future<String>.value('');
  }

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

    final source = _safeStr(
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

String _normalizeCategoryKeyGlobal(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty || value == '--' || value == 'uncategorized') {
    return 'uncategorized';
  }
  return value;
}

DateTime? _offenseSortDate(Map<String, dynamic> data) {
  return _globalTsToDate(data['createdAt']) ??
      _globalTsToDate(data['incidentAt']) ??
      _globalTsToDate(data['reportedAt']);
}

String _ordinalGlobal(int value) {
  if (value <= 0) return '${value}th';
  final mod100 = value % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${value}th';
  switch (value % 10) {
    case 1:
      return '${value}st';
    case 2:
      return '${value}nd';
    case 3:
      return '${value}rd';
    default:
      return '${value}th';
  }
}

Future<_OffenseIndicator> _resolveOffenseIndicator({
  required String studentUid,
  required String currentCaseId,
  required String currentCategory,
}) {
  final uid = _safeStr(studentUid);
  if (uid.isEmpty) {
    return Future<_OffenseIndicator>.value(
      const _OffenseIndicator(
        label: '--',
        subtitle: 'Offense indicator unavailable.',
        offenseNumber: 0,
      ),
    );
  }

  final categoryKey = _normalizeCategoryKeyGlobal(currentCategory);
  final cacheKey = '$uid::$currentCaseId::$categoryKey';
  final computation = () async {
    final snap = await FirebaseFirestore.instance
        .collection('violation_cases')
        .where('studentUid', isEqualTo: uid)
        .get();

    final docs = snap.docs
        .where((doc) {
          final docCategory = _normalizeCategoryKeyGlobal(
            _categoryLabelFromCaseGlobal(doc.data()),
          );
          if (docCategory != categoryKey) return false;
          final isCancelled =
              _statusKey(_safeStr(doc.data()['status'])) == 'cancelled';
          return !isCancelled;
        })
        .toList(growable: false);

    if (docs.isEmpty) {
      return const _OffenseIndicator(
        label: '1st Offense',
        subtitle: 'No prior offense records in this category.',
        offenseNumber: 1,
      );
    }

    final sorted = [...docs]
      ..sort((a, b) {
        final da = _offenseSortDate(a.data()) ?? DateTime(2000);
        final db = _offenseSortDate(b.data()) ?? DateTime(2000);
        final byDate = da.compareTo(db); // oldest first
        if (byDate != 0) return byDate;
        return a.id.compareTo(b.id);
      });

    final idx = sorted.indexWhere((doc) => doc.id == currentCaseId);
    final offenseNumber = (idx >= 0 ? idx + 1 : sorted.length + 1);
    final label = '${_ordinalGlobal(offenseNumber)} Offense';
    final subtitle = offenseNumber <= 1
        ? 'This appears to be the first recorded offense in this category.'
        : 'This case is the $label in this category.';

    return _OffenseIndicator(
      label: label,
      subtitle: subtitle,
      offenseNumber: offenseNumber,
    );
  }();

  // Always refresh this key to avoid stale offense rank after case updates.
  _offenseIndicatorFutureCache[cacheKey] = computation;
  return computation;
}

bool _isHttpImageUrl(String value) {
  return value.startsWith('http://') || value.startsWith('https://');
}

Future<String> _resolveImageSourceUrl(String source) async {
  final value = _safeStr(source);
  if (value.isEmpty) return '';
  if (_isHttpImageUrl(value)) return value;
  try {
    if (value.startsWith('gs://')) {
      return await FirebaseStorage.instance.refFromURL(value).getDownloadURL();
    }
    return await FirebaseStorage.instance.ref(value).getDownloadURL();
  } catch (_) {
    return '';
  }
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
  if (n.contains('cancel')) return 'cancelled';
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
    case 'cancelled':
      return 'Cancelled';
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

bool _canCorrectCaseStatusKey(String key) {
  return key == 'submitted' ||
      key == 'under review' ||
      key == 'action set' ||
      key == 'unresolved' ||
      key == 'cancelled' ||
      key == 'resolved';
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
      _showInlineNotice(
        context,
        message: 'Unable to open file URL.',
        tone: _InlineNoticeTone.warning,
      );
    }
    return;
  }

  final uri = Uri.tryParse(resolved);
  if (uri == null) {
    if (context.mounted) {
      _showInlineNotice(
        context,
        message: 'Invalid file URL.',
        tone: _InlineNoticeTone.warning,
      );
    }
    return;
  }

  final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
  if (!ok && context.mounted) {
    _showInlineNotice(
      context,
      message: 'Could not open the file.',
      tone: _InlineNoticeTone.warning,
    );
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
      _showInlineNotice(
        context,
        message: 'No previewable image evidence found.',
        tone: _InlineNoticeTone.neutral,
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

Future<void> _openProfilePhotoViewer(
  BuildContext context, {
  required String sourceUrl,
  required String studentName,
}) async {
  final resolvedUrl = await _resolveImageSourceUrl(sourceUrl);
  if (resolvedUrl.isEmpty) {
    if (context.mounted) {
      _showInlineNotice(
        context,
        message: 'No profile photo available.',
        tone: _InlineNoticeTone.neutral,
      );
    }
    return;
  }
  if (!context.mounted) return;

  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _ProfilePhotoViewerDialog(
      photoUrl: resolvedUrl,
      studentName: studentName,
    ),
  );
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
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
                      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
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

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/counseling_case_workflow_service.dart';
import '../../services/counseling_setup_service.dart';
import '../../services/osa_meeting_schedule_service.dart';
import '../shared/widgets/modern_table_layout.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';

enum _StudentCounselingTab {
  all,
  needsBooking,
  scheduled,
  underReview,
  completed,
  cancelled,
}

class StudentCounselingPage extends StatefulWidget {
  const StudentCounselingPage({super.key});

  @override
  State<StudentCounselingPage> createState() => _StudentCounselingPageState();
}

class _StudentCounselingPageState extends State<StudentCounselingPage> {
  static const bg = Colors.white;
  static const primaryColor = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  final _formKey = GlobalKey<FormState>();
  final _otherMoodCtrl = TextEditingController();
  final _otherSchoolCtrl = TextEditingController();
  final _otherRelationshipCtrl = TextEditingController();
  final _otherHomeCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _workflowService = CounselingCaseWorkflowService();
  final _counselingSetupService = CounselingSetupService();
  final ValueNotifier<Map<_StudentCounselingTab, int>> _tabCounts =
      ValueNotifier<Map<_StudentCounselingTab, int>>({
        _StudentCounselingTab.all: 0,
        _StudentCounselingTab.needsBooking: 0,
        _StudentCounselingTab.scheduled: 0,
        _StudentCounselingTab.underReview: 0,
        _StudentCounselingTab.completed: 0,
        _StudentCounselingTab.cancelled: 0,
      });

  String _studentUid = '';
  String _studentName = '';
  String _studentEmail = '';
  String _studentNo = '';
  String _programId = '';

  String _counselingType = 'academic';
  bool _loading = false;
  bool _loadingProfile = true;
  bool _sweepRunning = false;
  bool _isRefreshingTable = false;
  String? _selectedCaseId;
  _StudentCounselingTab _tab = _StudentCounselingTab.all;
  String _searchQuery = '';
  Timer? _searchDebounce;

  final Set<String> _moodsSelected = <String>{};
  final Set<String> _schoolSelected = <String>{};
  final Set<String> _relationshipSelected = <String>{};
  final Set<String> _homeSelected = <String>{};
  List<String> _moodOptions = List<String>.from(
    CounselingSetupConfig.defaults.moodsBehaviors,
  );
  List<String> _schoolOptions = List<String>.from(
    CounselingSetupConfig.defaults.schoolConcerns,
  );
  List<String> _relationshipOptions = List<String>.from(
    CounselingSetupConfig.defaults.relationships,
  );
  List<String> _homeOptions = List<String>.from(
    CounselingSetupConfig.defaults.homeConcerns,
  );

  @override
  void initState() {
    super.initState();
    _runStudentSafetySweep();
    _loadCounselingSetup();
    _loadStudentProfile();
  }

  Future<void> _loadCounselingSetup() async {
    try {
      final config = await _counselingSetupService.getConfig();
      if (!mounted) return;
      setState(() {
        _moodOptions = List<String>.from(config.moodsBehaviors);
        _schoolOptions = List<String>.from(config.schoolConcerns);
        _relationshipOptions = List<String>.from(config.relationships);
        _homeOptions = List<String>.from(config.homeConcerns);
        _moodsSelected.removeWhere((item) => !_moodOptions.contains(item));
        _schoolSelected.removeWhere((item) => !_schoolOptions.contains(item));
        _relationshipSelected.removeWhere(
          (item) => !_relationshipOptions.contains(item),
        );
        _homeSelected.removeWhere((item) => !_homeOptions.contains(item));
      });
    } catch (_) {
      // Keep defaults if setup cannot be loaded.
    }
  }

  Future<void> _runStudentSafetySweep() async {
    if (_sweepRunning) return;
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    _sweepRunning = true;
    try {
      final count = await _workflowService
          .expireOverdueScheduledMeetingsForStudent(studentUid: uid);
      if (!mounted || count <= 0) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$count overdue counseling appointment(s) were updated to missed.',
          ),
          backgroundColor: primaryColor,
        ),
      );
    } catch (_) {
      // Best-effort safety refresh only.
    } finally {
      _sweepRunning = false;
    }
  }

  Future<void> _loadStudentProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingProfile = false);
      return;
    }

    _studentUid = user.uid;
    _studentEmail = user.email?.trim() ?? '';

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      final studentProfile =
          (data['studentProfile'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      final first = (data['firstName'] ?? '').toString().trim();
      final last = (data['lastName'] ?? '').toString().trim();
      final displayName = (data['displayName'] ?? '').toString().trim();
      final full = ('$first $last').trim();

      if (!mounted) return;
      setState(() {
        _studentName = displayName.isNotEmpty
            ? displayName
            : full.isNotEmpty
            ? full
            : _studentEmail.split('@').first;
        _studentNo = (studentProfile['studentNo'] ?? '').toString().trim();
        _programId = (studentProfile['programId'] ?? '').toString().trim();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _studentName = _studentEmail.split('@').first;
      });
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: hintColor,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(icon, color: primaryColor.withValues(alpha: 0.85)),
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
        borderSide: const BorderSide(color: primaryColor, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  bool _hasAnyReasonSelected() {
    return _moodsSelected.isNotEmpty ||
        _schoolSelected.isNotEmpty ||
        _relationshipSelected.isNotEmpty ||
        _homeSelected.isNotEmpty ||
        _otherMoodCtrl.text.trim().isNotEmpty ||
        _otherSchoolCtrl.text.trim().isNotEmpty ||
        _otherRelationshipCtrl.text.trim().isNotEmpty ||
        _otherHomeCtrl.text.trim().isNotEmpty;
  }

  Future<bool> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_loading || _loadingProfile) return false;
    if (_studentUid.isEmpty) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student account not found. Please login again.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    if (!_hasAnyReasonSelected()) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one concern.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    if (!_formKey.currentState!.validate()) return false;

    setState(() => _loading = true);
    try {
      final caseId = await _workflowService.submitSelfReferral(
        studentUid: _studentUid,
        studentName: _studentName,
        studentNo: _studentNo,
        studentProgramId: _programId,
        counselingType: _counselingType,
        reasons: {
          'moodsBehaviors': _moodsSelected.toList()..sort(),
          'schoolConcerns': _schoolSelected.toList()..sort(),
          'relationships': _relationshipSelected.toList()..sort(),
          'homeConcerns': _homeSelected.toList()..sort(),
          'otherMood': _otherMoodCtrl.text.trim(),
          'otherSchool': _otherSchoolCtrl.text.trim(),
          'otherRelationship': _otherRelationshipCtrl.text.trim(),
          'otherHome': _otherHomeCtrl.text.trim(),
        },
        comments: _commentsCtrl.text.trim(),
      );

      final caseDoc = await FirebaseFirestore.instance
          .collection('counseling_cases')
          .doc(caseId)
          .get();
      final caseData = caseDoc.data() ?? <String, dynamic>{};
      final canBookNow = caseDoc.exists && _canBook(caseData);
      final isScheduledNow = caseDoc.exists && _isScheduled(caseData);
      final isAwaitingCallSlipNow = caseDoc.exists && _isAwaitingCallSlip(caseData);

      if (!mounted) return false;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            canBookNow
                ? 'Self-referral submitted. Please select an appointment slot.'
                : isScheduledNow
                ? 'Your self-referral was added to your active counseling case. You already have a scheduled appointment.'
                : isAwaitingCallSlipNow
                ? 'Your self-referral was added to your active counseling case. Booking will open once counseling is ready.'
                : 'Your self-referral was added to your active counseling case.',
          ),
          backgroundColor: primaryColor,
        ),
      );
      _resetFormAfterSubmit();
      if (canBookNow) {
        await _openBookingDialogForCaseId(caseId);
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submission failed: $error'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _activeTabIndex => _StudentCounselingTab.values.indexOf(_tab);

  String _tabLabel(_StudentCounselingTab tab) {
    switch (tab) {
      case _StudentCounselingTab.all:
        return 'All';
      case _StudentCounselingTab.needsBooking:
        return 'Needs Booking';
      case _StudentCounselingTab.scheduled:
        return 'Scheduled';
      case _StudentCounselingTab.underReview:
        return 'Under Review';
      case _StudentCounselingTab.completed:
        return 'Completed';
      case _StudentCounselingTab.cancelled:
        return 'Cancelled';
    }
  }

  void _onSearchInputChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final next = value.trim();
      if (_searchQuery == next) return;
      setState(() => _searchQuery = next);
    });
  }

  void _clearSearchQuery() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    if (_searchQuery.isNotEmpty) {
      setState(() => _searchQuery = '');
    }
  }

  Future<void> _refreshCurrentTable() async {
    if (_isRefreshingTable) return;
    setState(() => _isRefreshingTable = true);
    try {
      await _runStudentSafetySweep();
      await Future<void>.delayed(const Duration(milliseconds: 420));
    } finally {
      if (mounted) setState(() => _isRefreshingTable = false);
    }
  }

  void _updateTabCounts(List<QueryDocumentSnapshot<Map<String, dynamic>>> raw) {
    final next = <_StudentCounselingTab, int>{
      _StudentCounselingTab.all: 0,
      _StudentCounselingTab.needsBooking: 0,
      _StudentCounselingTab.scheduled: 0,
      _StudentCounselingTab.underReview: 0,
      _StudentCounselingTab.completed: 0,
      _StudentCounselingTab.cancelled: 0,
    };

    for (final doc in raw) {
      final d = doc.data();
      for (final tab in _StudentCounselingTab.values) {
        if (_matchesCounselingTab(d, tab)) {
          next[tab] = (next[tab] ?? 0) + 1;
        }
      }
    }

    final current = _tabCounts.value;
    var changed = false;
    for (final tab in _StudentCounselingTab.values) {
      if ((current[tab] ?? 0) != (next[tab] ?? 0)) {
        changed = true;
        break;
      }
    }
    if (!changed) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tabCounts.value = next;
    });
  }

  bool _isUnderReview(Map<String, dynamic> data) {
    if (_isCompleted(data) || _isCancelled(data)) return false;
    if (_canBook(data) || _isScheduled(data)) return false;
    return true;
  }

  bool _matchesCounselingTab(
    Map<String, dynamic> data,
    _StudentCounselingTab tab,
  ) {
    switch (tab) {
      case _StudentCounselingTab.all:
        return true;
      case _StudentCounselingTab.needsBooking:
        return _canBook(data);
      case _StudentCounselingTab.scheduled:
        return _isScheduled(data);
      case _StudentCounselingTab.underReview:
        return _isUnderReview(data);
      case _StudentCounselingTab.completed:
        return _isCompleted(data);
      case _StudentCounselingTab.cancelled:
        return _isCancelled(data);
    }
  }

  DateTime? _bestCaseDate(Map<String, dynamic> data) {
    return _toDate(data['scheduledAt']) ??
        _toDate(data['createdAt']) ??
        _toDate(data['referralDate']) ??
        _toDate(data['updatedAt']);
  }

  String _fmtShort(DateTime dt) => DateFormat('MMM d, yyyy').format(dt);

  String _safeStr(dynamic value) => (value ?? '').toString().trim();

  Widget _buildHandbookStyleSearchBar({
    bool shouldConstrainWidth = true,
    Widget? compactTrailingAction,
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
                    hintText: 'Search case, type, status, date...',
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

  Widget? _buildCompactHeaderOptionsButton({
    required bool useCompactHeaderActions,
    required VoidCallback onSelfReferral,
  }) {
    if (!useCompactHeaderActions) return null;
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
          enabled: !_loading,
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_horiz_rounded, color: hintColor, size: 20),
          onSelected: (value) {
            if (value == 'self_referral') onSelfReferral();
          },
          itemBuilder: (context) => const [
            PopupMenuItem<String>(
              value: 'self_referral',
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Self Referral'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBookingDialogForCaseId(String caseId) async {
    final caseDoc = await FirebaseFirestore.instance
        .collection('counseling_cases')
        .doc(caseId)
        .get();
    if (!mounted || !caseDoc.exists) return;
    final data = caseDoc.data() ?? <String, dynamic>{};
    await _openBookingDialog(caseId: caseId, data: data);
  }

  Future<void> _openBookingDialog({
    required String caseId,
    required Map<String, dynamic> data,
  }) async {
    final schoolYearId = (data['schoolYearId'] ?? '').toString().trim();
    final termId = (data['termId'] ?? '').toString().trim();
    if (schoolYearId.isEmpty || termId.isEmpty) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Booking context is not ready yet. Please contact counseling admin.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final slotService = OsaMeetingScheduleService(
      templateCollection: 'counseling_schedule_templates',
      slotCollection: 'counseling_meeting_slots',
      caseCollection: 'counseling_cases',
    );
    final bookingLeadHours =
        (data['bookingLeadHours'] as num?)?.toInt() ??
        CounselingCaseWorkflow.bookingLeadTime.inHours;
    final hasSchedule = await slotService.hasSlotsForTerm(
      schoolYearId: schoolYearId,
      termId: termId,
      fromDate: DateTime.now().add(Duration(hours: bookingLeadHours)),
    );
    if (!mounted) return;
    if (!hasSchedule) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No counseling schedule is available yet. You can still submit your referral and counseling will notify you when booking opens.',
          ),
          backgroundColor: primaryColor,
        ),
      );
      return;
    }

    final booked = await showDialog<bool>(
      context: context,
      builder: (_) => _BookCounselingSlotDialog(
        caseId: caseId,
        studentUid: _studentUid,
        schoolYearId: schoolYearId,
        termId: termId,
        bookingDeadlineAt: _toDate(data['bookingDeadlineAt']),
        bookingLeadHours: bookingLeadHours,
        openSlotDays:
            (data['bookingOpenSlotDays'] as num?)?.toInt() ??
            CounselingCaseWorkflow.bookingOpenSlotDays,
      ),
    );

    if (!mounted || booked != true) return;
    AppScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Counseling appointment booked successfully.'),
        backgroundColor: primaryColor,
      ),
    );
  }

  bool _isCompleted(Map<String, dynamic> data) {
    return CounselingCaseState.isCompleted(data);
  }

  bool _isCancelled(Map<String, dynamic> data) {
    return CounselingCaseState.isCancelled(data);
  }

  bool _isMissed(Map<String, dynamic> data) {
    return CounselingCaseState.isMissed(data);
  }

  bool _isScheduled(Map<String, dynamic> data) {
    return CounselingCaseState.isScheduled(data);
  }

  bool _isAwaitingCallSlip(Map<String, dynamic> data) {
    return CounselingCaseState.isAwaitingCallSlip(data);
  }

  bool _canBook(Map<String, dynamic> data) {
    return CounselingCaseState.isBookingRequired(data);
  }

  String _statusText(Map<String, dynamic> data) {
    final shared = CounselingCaseState.statusLabel(data);
    if (shared == 'Missed - Rebook Required') return 'Missed - Rebook';
    return shared;
  }

  Color _statusColor(Map<String, dynamic> data) {
    if (_isCompleted(data)) return Colors.green.shade700;
    if (_isCancelled(data)) return Colors.grey.shade700;
    if (_isScheduled(data)) return Colors.blue.shade700;
    if (_isMissed(data)) return Colors.red.shade700;
    if (_canBook(data)) return primaryColor;
    return hintColor;
  }

  String _titleCase(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    return parts
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
  }

  Widget _buildStatusPill(Map<String, dynamic> data) {
    final color = _statusColor(data);
    final text = _statusText(data);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11.5,
        ),
      ),
    );
  }

  String _prettyType(String value) {
    final type = value.trim().toLowerCase();
    if (type == 'academic') return 'Academic';
    if (type == 'personal') return 'Personal';
    return type.isEmpty ? 'General' : _titleCase(type);
  }

  Widget _buildMyCasesSection(
    double scale, {
    required bool wideLayout,
  }) {
    if (_studentUid.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My Counseling Cases',
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: (14.5 * scale).clamp(14.5, 16.5),
            ),
          ),
          SizedBox(height: 4 * scale),
          Text(
            'Book or rebook your appointment when required.',
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w700,
              fontSize: (12.0 * scale).clamp(12.0, 13.0),
            ),
          ),
          SizedBox(height: 10 * scale),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('counseling_cases')
                .where('studentUid', isEqualTo: _studentUid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    'Error loading counseling cases: ${snapshot.error}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final docs = snapshot.data!.docs.toList()
                ..sort((a, b) {
                  final ad =
                      _toDate(a.data()['createdAt']) ??
                      _toDate(a.data()['referralDate']) ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  final bd =
                      _toDate(b.data()['createdAt']) ??
                      _toDate(b.data()['referralDate']) ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  return bd.compareTo(ad);
                });

              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Text(
                    'No counseling referrals yet.',
                    style: TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              }

              final selectedDoc = (_selectedCaseId == null)
                  ? null
                  : docs
                        .where((doc) => doc.id == _selectedCaseId)
                        .cast<QueryDocumentSnapshot<Map<String, dynamic>>?>()
                        .firstWhere((doc) => doc != null, orElse: () => null);
              if (wideLayout && selectedDoc == null && docs.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _selectedCaseId = docs.first.id;
                  });
                });
              }

              final cards = docs.map((doc) {
                  final data = doc.data();
                  final caseCode = (data['caseCode'] ?? doc.id).toString();
                  final referralType = _prettyType(
                    (data['counselingType'] ?? '').toString(),
                  );
                  final submittedAt =
                      _toDate(data['createdAt']) ??
                      _toDate(data['referralDate']);
                  final scheduledAt = _toDate(data['scheduledAt']);
                  final canBook = _canBook(data);
                  final awaitingCallSlip = _isAwaitingCallSlip(data);
                  final selected = _selectedCaseId == doc.id;
                  final quickSummary = _buildReasonSummary(data);

                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (wideLayout) {
                        setState(() {
                          _selectedCaseId = doc.id;
                        });
                        return;
                      }
                      _openCaseDetailsSheet(
                        caseId: doc.id,
                        data: data,
                        scale: scale,
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected
                            ? primaryColor.withValues(alpha: 0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? primaryColor.withValues(alpha: 0.4)
                              : Colors.black.withValues(alpha: 0.09),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  caseCode,
                                  style: const TextStyle(
                                    color: primaryColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              _buildStatusPill(data),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$referralType Referral',
                            style: const TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            submittedAt == null
                                ? 'Submitted date not available'
                                : 'Submitted ${DateFormat('MMM d, yyyy').format(submittedAt)}',
                            style: const TextStyle(
                              color: hintColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          if (scheduledAt != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Scheduled: ${DateFormat('EEE, MMM d, yyyy h:mm a').format(scheduledAt)}',
                              style: const TextStyle(
                                color: hintColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          if (quickSummary.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              quickSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: hintColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          if (awaitingCallSlip) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.11),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.30),
                                ),
                              ),
                              child: Text(
                                'Counseling will send your call slip before booking opens.',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          if (canBook && !wideLayout) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => _openBookingDialog(
                                  caseId: doc.id,
                                  data: data,
                                ),
                                icon: const Icon(
                                  Icons.event_available_rounded,
                                  size: 18,
                                ),
                                label: const Text('Book / Rebook'),
                                style: TextButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList();

              if (!wideLayout) {
                return Column(children: cards);
              }

              final detailsData = selectedDoc?.data();
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(children: cards),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    flex: 4,
                    child: detailsData == null
                        ? _buildEmptyDetailsPane(scale)
                        : _buildCaseDetailsPane(
                            caseId: selectedDoc!.id,
                            data: detailsData,
                            scale: scale,
                          ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDetailsPane(double scale) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: const Text(
        'Select a counseling case to view details.',
        style: TextStyle(
          color: hintColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCaseDetailsPane({
    required String caseId,
    required Map<String, dynamic> data,
    required double scale,
  }) {
    final caseCode = (data['caseCode'] ?? caseId).toString();
    final submittedAt = _toDate(data['createdAt']) ?? _toDate(data['referralDate']);
    final scheduledAt = _toDate(data['scheduledAt']);
    final canBook = _canBook(data);
    final missed = _isMissed(data);
    final reasonSummary = _buildReasonSummary(data);
    final comments = (data['comments'] ?? '').toString().trim();

    Widget kv(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value.isEmpty ? '--' : value,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Case Details',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: (15 * scale).clamp(15.0, 18.0),
                  ),
                ),
              ),
              _buildStatusPill(data),
            ],
          ),
          SizedBox(height: 10 * scale),
          kv('Case Code', caseCode),
          kv('Referral Type', _prettyType((data['counselingType'] ?? '').toString())),
          kv(
            'Submitted',
            submittedAt == null ? '--' : DateFormat('MMM d, yyyy').format(submittedAt),
          ),
          kv(
            'Scheduled',
            scheduledAt == null
                ? 'Not yet scheduled'
                : DateFormat('EEE, MMM d, yyyy h:mm a').format(scheduledAt),
          ),
          kv('Concern Summary', reasonSummary.isEmpty ? '--' : reasonSummary),
          kv('Notes', comments.isEmpty ? '--' : comments),
          if (canBook) ...[
            SizedBox(height: 8 * scale),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () => _openBookingDialog(caseId: caseId, data: data),
                icon: const Icon(Icons.event_available_rounded, size: 18),
                label: Text(
                  missed ? 'Rebook Appointment' : 'Book Appointment',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _buildReasonSummary(Map<String, dynamic> data) {
    final reasons = (data['reasons'] as Map<String, dynamic>?) ?? const {};
    final items = <String>{};
    for (final key in const [
      'moodsBehaviors',
      'schoolConcerns',
      'relationships',
      'homeConcerns',
    ]) {
      final values = reasons[key];
      if (values is Iterable) {
        for (final item in values) {
          final text = item.toString().trim();
          if (text.isNotEmpty) items.add(text);
        }
      }
    }
    return items.join(', ');
  }

  Future<void> _openCaseDetailsSheet({
    required String caseId,
    required Map<String, dynamic> data,
    required double scale,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _buildCaseDetailsPane(
                caseId: caseId,
                data: data,
                scale: scale,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSelfReferralDialog({
    required bool tablet,
    required bool stackActions,
    required double scale,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !_loading,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: tablet ? 860 : 560,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.9,
            ),
            padding: EdgeInsets.all(14 * scale),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Self Referral Form',
                            style: TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Share your concerns so counseling can assist you.',
                      style: TextStyle(
                        color: hintColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    SizedBox(height: 12 * scale),
                    _buildSectionCard(
                      title: 'Referral Type',
                      subtitle: 'Choose the type of counseling support you need.',
                      scale: scale,
                      child: _buildTypeCard(scale),
                    ),
                    SizedBox(height: 12 * scale),
                    _buildSectionCard(
                      title: 'Notes',
                      subtitle:
                          'Describe your current situation so counseling can assist you better.',
                      scale: scale,
                      child: _buildCommentsSection(scale),
                    ),
                    SizedBox(height: 12 * scale),
                    _buildSectionCard(
                      title: 'Concern Checklist',
                      subtitle:
                          'Optional: select any concern areas that apply to your situation.',
                      scale: scale,
                      child: _buildReasonsGrid(
                        scale,
                        tablet,
                        collapsible: !tablet,
                      ),
                    ),
                    SizedBox(height: 14 * scale),
                    _buildActions(
                      scale,
                      stacked: stackActions,
                      onSubmitSuccess: () {
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                      },
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

  void _resetFormAfterSubmit() {
    setState(() {
      _counselingType = 'academic';
      _moodsSelected.clear();
      _schoolSelected.clear();
      _relationshipSelected.clear();
      _homeSelected.clear();
      _otherMoodCtrl.clear();
      _otherSchoolCtrl.clear();
      _otherRelationshipCtrl.clear();
      _otherHomeCtrl.clear();
      _commentsCtrl.clear();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _tabCounts.dispose();
    _otherMoodCtrl.dispose();
    _otherSchoolCtrl.dispose();
    _otherRelationshipCtrl.dispose();
    _otherHomeCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const hintColor = Color(0xFF6D7F62);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(
        child: Text(
          'Not logged in',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktopWide = constraints.maxWidth >= 900;
        final useCompactHeaderActions = constraints.maxWidth < 760;
        final scale = (constraints.maxWidth / 430).clamp(1.0, 1.18);
        final detailsPaneWidth = (constraints.maxWidth * 0.33)
            .clamp(320.0, 420.0)
            .toDouble();
        void openSelfReferral() => _showSelfReferralDialog(
          tablet: constraints.maxWidth >= 760,
          stackActions: constraints.maxWidth < 640,
          scale: scale,
        );
        final compactOptions = _buildCompactHeaderOptionsButton(
          useCompactHeaderActions: useCompactHeaderActions,
          onSelfReferral: openSelfReferral,
        );

        return Scaffold(
          backgroundColor: bg,
          body: _loadingProfile
              ? const Center(child: CircularProgressIndicator())
              : ModernTableLayout(
                  detailsWidth: detailsPaneWidth,
                  header: ModernTableHeader(
                    showTitleSection: false,
                    showTopControlsWhenTitleHidden: true,
                    showSearchBar: true,
                    searchBar: _buildHandbookStyleSearchBar(
                      compactTrailingAction: compactOptions,
                    ),
                    action: useCompactHeaderActions
                        ? null
                        : FilledButton.icon(
                            onPressed: _loading ? null : openSelfReferral,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text(
                              'Self Referral',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 2,
                            ),
                          ),
                    tabs: DefaultTabController(
                      length: _StudentCounselingTab.values.length,
                      initialIndex: _activeTabIndex,
                      child: ValueListenableBuilder<Map<_StudentCounselingTab, int>>(
                        valueListenable: _tabCounts,
                        builder: (context, counts, _) {
                          return TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            labelColor: primaryColor,
                            indicatorColor: primaryColor,
                            dividerColor: Colors.transparent,
                            onTap: (index) {
                              final nextTab = _StudentCounselingTab.values[index];
                              if (nextTab == _tab) return;
                              setState(() {
                                _tab = nextTab;
                                _selectedCaseId = null;
                              });
                            },
                            tabs: _StudentCounselingTab.values
                                .map(
                                  (tab) => Tab(
                                    text:
                                        '${_tabLabel(tab)} (${counts[tab] ?? 0})',
                                  ),
                                )
                                .toList(growable: false),
                          );
                        },
                      ),
                    ),
                    filters: const [],
                  ),
                  body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('counseling_cases')
                        .where('studentUid', isEqualTo: user.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final raw = snapshot.data!.docs;
                      _updateTabCounts(raw);
                      final query = _searchQuery.trim().toLowerCase();

                      final docs = raw.where((doc) {
                        final data = doc.data();
                        if (!_matchesCounselingTab(data, _tab)) return false;
                        if (query.isEmpty) return true;

                        final caseCode = _safeStr(
                          data['caseCode'] ?? doc.id,
                        ).toLowerCase();
                        final type = _prettyType(
                          _safeStr(data['counselingType']),
                        ).toLowerCase();
                        final status = _statusText(data).toLowerCase();
                        final date = _bestCaseDate(data);
                        final dateText =
                            date == null ? '' : _fmtShort(date).toLowerCase();
                        final reasons = _buildReasonSummary(data).toLowerCase();
                        return caseCode.contains(query) ||
                            type.contains(query) ||
                            status.contains(query) ||
                            dateText.contains(query) ||
                            reasons.contains(query);
                      }).toList()
                        ..sort((a, b) {
                          final da = _bestCaseDate(a.data());
                          final db = _bestCaseDate(b.data());
                          if (da == null && db == null) return 0;
                          if (da == null) return 1;
                          if (db == null) return -1;
                          return db.compareTo(da);
                        });

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

                      if (_selectedCaseId != null &&
                          !docs.any((doc) => doc.id == _selectedCaseId)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() => _selectedCaseId = null);
                        });
                      }

                      if (desktopWide) {
                        return _buildDesktopCounselingTable(docs);
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          final isSelected = _selectedCaseId == doc.id;
                          return _buildCounselingCard(
                            doc.id,
                            doc.data(),
                            isSelected,
                            () => _openCounselingDetails(doc),
                          );
                        },
                      );
                    },
                  ),
                  showDetails: desktopWide && _selectedCaseId != null,
                  details: desktopWide && _selectedCaseId != null
                      ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('counseling_cases')
                              .doc(_selectedCaseId)
                              .snapshots(),
                          builder: (context, snap) {
                            if (!snap.hasData) return const SizedBox();
                            final doc = snap.data!;
                            if (!doc.exists) {
                              return const Center(child: Text('Case not found'));
                            }
                            return _buildDesktopDetailsContainer(
                              caseId: doc.id,
                              data: doc.data() ?? const <String, dynamic>{},
                              scale: scale,
                            );
                          },
                        )
                      : null,
                ),
        );
      },
    );
  }

  Widget _buildDesktopCounselingTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
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
              final detailsOpen = _selectedCaseId != null;
              final compactTable = detailsOpen || tableWidth < 1120;
              final tableHorizontalMargin = compactTable ? 8.0 : 12.0;
              final tableColumnSpacing = compactTable ? 12.0 : 18.0;
              final totalWeight = 1.35 + 1.25 + 1.30 + 1.20 + 1.80;
              final usableWidth =
                  (tableWidth -
                          (tableHorizontalMargin * 2) -
                          (tableColumnSpacing * (5 - 1)))
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

              final codeCellWidth = colWidth(1.35, 112, compactMinWidth: 90);
              final typeCellWidth = colWidth(1.25, 112, compactMinWidth: 92);
              final statusCellWidth = colWidth(1.30, 118, compactMinWidth: 98);
              final dateCellWidth = colWidth(1.20, 112, compactMinWidth: 92);
              final concernCellWidth = colWidth(1.80, 190, compactMinWidth: 140);

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStateProperty.all(Colors.white),
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
                          width: typeCellWidth,
                          child: _tableHeaderText('TYPE'),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: statusCellWidth,
                          child: _tableHeaderText('STATUS'),
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
                          width: concernCellWidth,
                          child: _tableHeaderText('CONCERN'),
                        ),
                      ),
                    ],
                    rows: [
                      for (int i = 0; i < docs.length; i++)
                        () {
                          final doc = docs[i];
                          final data = doc.data();
                          final isSelected = _selectedCaseId == doc.id;
                          final caseCode = _safeStr(
                            data['caseCode'],
                          ).isEmpty
                              ? doc.id
                              : _safeStr(data['caseCode']);
                          final type = _prettyType(_safeStr(data['counselingType']));
                          final status = _statusText(data);
                          final date = _bestCaseDate(data);
                          final concern = _buildReasonSummary(data);

                          return DataRow.byIndex(
                            index: i,
                            selected: isSelected,
                            color: WidgetStateProperty.resolveWith<Color?>((_) {
                              if (isSelected) {
                                return primaryColor.withValues(alpha: 0.10);
                              }
                              return Colors.white;
                            }),
                            onSelectChanged: (_) {
                              setState(() {
                                _selectedCaseId = isSelected ? null : doc.id;
                              });
                            },
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: codeCellWidth,
                                  child: Text(
                                    caseCode,
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
                                  width: typeCellWidth,
                                  child: Text(
                                    type,
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
                                  width: statusCellWidth,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _buildStatusPill(data),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: dateCellWidth,
                                  child: Text(
                                    date == null ? '--' : _fmtShort(date),
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
                                  width: concernCellWidth,
                                  child: Text(
                                    concern.isEmpty ? '--' : concern,
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

  Widget _buildCounselingCard(
    String id,
    Map<String, dynamic> data,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final caseCode = _safeStr(data['caseCode']).isEmpty
        ? id
        : _safeStr(data['caseCode']);
    final date = _bestCaseDate(data);
    final concern = _buildReasonSummary(data);

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
                        caseCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: primaryColor,
                        ),
                      ),
                      const Spacer(),
                      _buildStatusPill(data),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_prettyType(_safeStr(data['counselingType']))} Referral',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textDark,
                    ),
                  ),
                  if (date != null)
                    Text(
                      _fmtShort(date),
                      style: const TextStyle(color: hintColor, fontSize: 13),
                    ),
                  if (concern.isNotEmpty)
                    Text(
                      concern,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: hintColor, fontSize: 12.5),
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

  Widget _buildDesktopDetailsContainer({
    required String caseId,
    required Map<String, dynamic> data,
    required double scale,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: _buildCaseDetailsPane(caseId: caseId, data: data, scale: scale),
    );
  }

  void _openCounselingDetails(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: _buildCaseDetailsPane(
            caseId: doc.id,
            data: doc.data(),
            scale: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
    required double scale,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: (14.2 * scale).clamp(14.0, 16.0),
            ),
          ),
          SizedBox(height: 2 * scale),
          Text(
            subtitle,
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w700,
              fontSize: (12.0 * scale).clamp(12.0, 13.0),
            ),
          ),
          SizedBox(height: 10 * scale),
          child,
        ],
      ),
    );
  }

  Widget _buildTypeCard(double scale) {
    return Container(
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _counselingType,
            decoration: _decor(
              label: 'Referral Type',
              icon: Icons.rule_folder_outlined,
            ),
            items: const [
              DropdownMenuItem(value: 'academic', child: Text('Academic')),
              DropdownMenuItem(value: 'personal', child: Text('Personal')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _counselingType = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReasonsGrid(
    double scale,
    bool wide, {
    required bool collapsible,
  }) {
    final left = Column(
      children: [
        _reasonGroupCard(
          title: 'Moods / Behaviors',
          options: _moodOptions,
          selected: _moodsSelected,
          otherController: _otherMoodCtrl,
          scale: scale,
          collapsible: collapsible,
        ),
        SizedBox(height: 10 * scale),
        _reasonGroupCard(
          title: 'Relationships',
          options: _relationshipOptions,
          selected: _relationshipSelected,
          otherController: _otherRelationshipCtrl,
          scale: scale,
          collapsible: collapsible,
        ),
      ],
    );

    final right = Column(
      children: [
        _reasonGroupCard(
          title: 'School Concerns',
          options: _schoolOptions,
          selected: _schoolSelected,
          otherController: _otherSchoolCtrl,
          scale: scale,
          collapsible: collapsible,
        ),
        SizedBox(height: 10 * scale),
        _reasonGroupCard(
          title: 'Home Concerns',
          options: _homeOptions,
          selected: _homeSelected,
          otherController: _otherHomeCtrl,
          scale: scale,
          collapsible: collapsible,
        ),
      ],
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          SizedBox(width: 10 * scale),
          Expanded(child: right),
        ],
      );
    }

    return Column(
      children: [
        left,
        SizedBox(height: 10 * scale),
        right,
      ],
    );
  }

  Widget _reasonGroupCard({
    required String title,
    required List<String> options,
    required Set<String> selected,
    required TextEditingController otherController,
    required double scale,
    required bool collapsible,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select all that apply.',
          style: TextStyle(
            color: hintColor,
            fontWeight: FontWeight.w700,
            fontSize: (11.8 * scale).clamp(11.5, 13.0),
          ),
        ),
        SizedBox(height: 4 * scale),
        ...options.map((option) {
          final checked = selected.contains(option);
          return CheckboxListTile(
            value: checked,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              option,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            activeColor: primaryColor,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  selected.add(option);
                } else {
                  selected.remove(option);
                }
              });
            },
          );
        }),
        TextFormField(
          controller: otherController,
          decoration: _decor(
            label: 'Other concern in this area (optional)',
            icon: Icons.edit_note_rounded,
            hint: 'Add any additional details for this area',
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: collapsible
          ? Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded:
                    selected.isNotEmpty ||
                    otherController.text.trim().isNotEmpty,
                title: Text(
                  title,
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: (14.0 * scale).clamp(14.0, 16.0),
                  ),
                ),
                children: [content],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: (14.0 * scale).clamp(14.0, 16.0),
                  ),
                ),
                SizedBox(height: 6 * scale),
                content,
              ],
            ),
    );
  }

  Widget _buildCommentsSection(double scale) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _commentsCtrl,
            minLines: 4,
            maxLines: 6,
            decoration: _decor(
              label: 'What is your current situation?',
              icon: Icons.notes_rounded,
              hint:
                  'Share key details. You may include moods/behavior, school, relationship, and home concerns.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
    double scale, {
    required bool stacked,
    VoidCallback? onSubmitSuccess,
  }) {
    final clearButton = OutlinedButton.icon(
      onPressed: _loading ? null : _resetFormAfterSubmit,
      icon: const Icon(Icons.clear_rounded),
      label: const Text('Clear Form'),
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: BorderSide(color: primaryColor.withValues(alpha: 0.45)),
        padding: EdgeInsets.symmetric(vertical: 12 * scale),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final submitButton = ElevatedButton.icon(
      onPressed: _loading
          ? null
          : () async {
              final ok = await _submit();
              if (ok) onSubmitSuccess?.call();
            },
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.send_rounded),
      label: Text(_loading ? 'Submitting...' : 'Submit Referral'),
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 12 * scale),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 46 * scale, child: submitButton),
          SizedBox(height: 10 * scale),
          SizedBox(height: 46 * scale, child: clearButton),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: clearButton),
        SizedBox(width: 10 * scale),
        Expanded(child: submitButton),
      ],
    );
  }
}

class _BookCounselingSlotDialog extends StatefulWidget {
  final String caseId;
  final String studentUid;
  final String schoolYearId;
  final String termId;
  final DateTime? bookingDeadlineAt;
  final int bookingLeadHours;
  final int openSlotDays;

  const _BookCounselingSlotDialog({
    required this.caseId,
    required this.studentUid,
    required this.schoolYearId,
    required this.termId,
    required this.bookingDeadlineAt,
    required this.bookingLeadHours,
    required this.openSlotDays,
  });

  @override
  State<_BookCounselingSlotDialog> createState() =>
      _BookCounselingSlotDialogState();
}

class _BookCounselingSlotDialogState extends State<_BookCounselingSlotDialog> {
  final _slotService = OsaMeetingScheduleService(
    templateCollection: 'counseling_schedule_templates',
    slotCollection: 'counseling_meeting_slots',
    caseCollection: 'counseling_cases',
  );
  final _workflowService = CounselingCaseWorkflowService();
  final _slotScrollCtrl = ScrollController();

  static const _bg = Colors.white;
  static const _primaryColor = Color(0xFF1B5E20);
  static const _hintColor = Color(0xFF6D7F62);
  static const _textDark = Color(0xFF1F2A1F);

  String? _selectedSlotId;
  bool _booking = false;

  @override
  void dispose() {
    _slotScrollCtrl.dispose();
    super.dispose();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _limitByOpenDays(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int dayCount, {
    int minSlots = 12,
    int maxDayCount = 21,
  }) {
    if (docs.isEmpty) return docs;
    final preferredDayCount = dayCount <= 0 ? 7 : dayCount;
    final boundedMaxDays = maxDayCount < preferredDayCount
        ? preferredDayCount
        : maxDayCount;

    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final uniqueDayKeys = <String>{};

    for (final doc in docs) {
      final start = (doc.data()['startAt'] as Timestamp?)?.toDate();
      if (start == null) continue;
      final dayKey = DateFormat('yyyy-MM-dd').format(start);
      final isNewDay = !uniqueDayKeys.contains(dayKey);
      if (isNewDay &&
          uniqueDayKeys.length >= preferredDayCount &&
          out.length >= minSlots) {
        break;
      }
      if (isNewDay && uniqueDayKeys.length >= boundedMaxDays) {
        break;
      }
      uniqueDayKeys.add(dayKey);
      out.add(doc);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final effectiveOpenSlotDays = widget.openSlotDays <= 0
        ? CounselingCaseWorkflow.bookingOpenSlotDays
        : widget.openSlotDays;
    final bookingClosed =
        widget.bookingDeadlineAt != null &&
        now.isAfter(widget.bookingDeadlineAt!);
    final earliestAllowedStart = now.add(
      Duration(hours: widget.bookingLeadHours),
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth < 760 ? screenWidth - 32 : 640.0;
    final dialogHeight = screenWidth < 760 ? 520.0 : 600.0;

    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Counseling Slot',
            style: TextStyle(
              color: _primaryColor,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Choose one available schedule for your counseling appointment.',
            style: TextStyle(
              color: _hintColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: bookingClosed
            ? Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Booking window has ended. Please contact counseling support.',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                stream: _slotService.streamOpenSlots(
                  schoolYearId: widget.schoolYearId,
                  termId: widget.termId,
                  fromDate: earliestAllowedStart,
                  limit: 500,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Text(
                        'Error loading slots: ${snapshot.error}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: _primaryColor),
                    );
                  }

                  final sorted =
                      snapshot.data!.where((slotDoc) {
                        final data = slotDoc.data();
                        final start = (data['startAt'] as Timestamp?)?.toDate();
                        if (start == null) return false;
                        if (start.isBefore(now)) return false;
                        if (start.isBefore(earliestAllowedStart)) return false;
                        return true;
                      }).toList()..sort((a, b) {
                        final aStart =
                            (a.data()['startAt'] as Timestamp?)?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        final bStart =
                            (b.data()['startAt'] as Timestamp?)?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        return aStart.compareTo(bStart);
                      });

                  final docs = _limitByOpenDays(
                    sorted,
                    effectiveOpenSlotDays,
                    minSlots: 12,
                    maxDayCount: 21,
                  );
                  if (docs.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'No open slots available right now.\nPlease try again later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _hintColor,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                      ),
                    );
                  }

                  QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
                  for (final doc in docs) {
                    if (doc.id == _selectedSlotId) {
                      selectedDoc = doc;
                      break;
                    }
                  }

                  if (_selectedSlotId != null && selectedDoc == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => _selectedSlotId = null);
                    });
                  }
                  final dayGroups = _groupSlotsByDay(docs);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _primaryColor.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Text(
                          'Showing the next $effectiveOpenSlotDays available day${effectiveOpenSlotDays == 1 ? '' : 's'} with open slots '
                          '(minimum ${widget.bookingLeadHours}-hour lead time).',
                          style: const TextStyle(
                            color: _primaryColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            '${docs.length} available slot${docs.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: _hintColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          if (docs.length > 5)
                            const Row(
                              children: [
                                Icon(
                                  Icons.swipe_vertical_rounded,
                                  size: 14,
                                  color: _hintColor,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Scroll for more',
                                  style: TextStyle(
                                    color: _hintColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.09),
                            ),
                          ),
                          child: Scrollbar(
                            controller: _slotScrollCtrl,
                            thumbVisibility: docs.length > 5,
                            child: CustomScrollView(
                              controller: _slotScrollCtrl,
                              slivers: [
                                for (final group in dayGroups)
                                  SliverMainAxisGroup(
                                    slivers: [
                                      SliverPersistentHeader(
                                        pinned: true,
                                        delegate:
                                            _CounselingStickyDayHeaderDelegate(
                                              height: 34,
                                              child: KeyedSubtree(
                                                key: ValueKey(
                                                  DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(group.day),
                                                ),
                                                child: Container(
                                                  color: Colors.white,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8,
                                                        bottom: 6,
                                                      ),
                                                  child: Text(
                                                    _formatSlotDayHeader(
                                                      group.day,
                                                    ),
                                                    style: const TextStyle(
                                                      color: _hintColor,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 12,
                                                      letterSpacing: 0.6,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                      ),
                                      SliverList(
                                        delegate: SliverChildBuilderDelegate((
                                          _,
                                          index,
                                        ) {
                                          final doc = group.slots[index];
                                          final start = _slotStart(doc);
                                          final end = _slotEnd(doc);
                                          if (start == null || end == null) {
                                            return const SizedBox.shrink();
                                          }
                                          return _buildSlotCard(
                                            doc: doc,
                                            start: start,
                                            end: end,
                                            selectedSlotId: _selectedSlotId,
                                            onSelect: _booking
                                                ? null
                                                : (slotId) => setState(
                                                    () => _selectedSlotId =
                                                        slotId,
                                                  ),
                                          );
                                        }, childCount: group.slots.length),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (selectedDoc != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _primaryColor.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            'Selected: ${_slotLabel(_slotStart(selectedDoc), _slotEnd(selectedDoc))}',
                            style: const TextStyle(
                              color: _primaryColor,
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _booking ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: _hintColor),
          ),
        ),
        FilledButton(
          onPressed: bookingClosed || _booking || _selectedSlotId == null
              ? null
              : () async {
                  setState(() => _booking = true);
                  try {
                    await _workflowService.bookSlotForCase(
                      slotId: _selectedSlotId!,
                      caseId: widget.caseId,
                      studentUid: widget.studentUid,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop(true);
                  } catch (e) {
                    if (!context.mounted) return;
                    setState(() => _booking = false);
                    AppScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Booking failed: $e')),
                    );
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: _primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            _booking ? 'Booking...' : 'Book Slot',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  List<_CounselingDaySlotGroup> _groupSlotsByDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final groups = <_CounselingDaySlotGroup>[];
    DateTime? currentDay;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> currentSlots = [];

    for (final doc in docs) {
      final start = _slotStart(doc);
      if (start == null) continue;
      final dayKey = DateTime(start.year, start.month, start.day);
      if (currentDay == null || !_isSameDate(currentDay, dayKey)) {
        if (currentDay != null && currentSlots.isNotEmpty) {
          groups.add(
            _CounselingDaySlotGroup(day: currentDay, slots: currentSlots),
          );
        }
        currentDay = dayKey;
        currentSlots = [doc];
      } else {
        currentSlots.add(doc);
      }
    }

    if (currentDay != null && currentSlots.isNotEmpty) {
      groups.add(_CounselingDaySlotGroup(day: currentDay, slots: currentSlots));
    }
    return groups;
  }

  Widget _buildSlotCard({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required DateTime start,
    required DateTime end,
    required String? selectedSlotId,
    required void Function(String slotId)? onSelect,
  }) {
    final selected = selectedSlotId == doc.id;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onSelect == null ? null : () => onSelect(doc.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? _primaryColor.withValues(alpha: 0.10)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? _primaryColor
                : Colors.black.withValues(alpha: 0.10),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? _primaryColor : _hintColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _slotTimeRange(start, end),
                    style: TextStyle(
                      color: _textDark,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _slotMeta(start, end),
                    style: const TextStyle(
                      color: _hintColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _slotStart(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      (doc.data()['startAt'] as Timestamp?)?.toDate();

  DateTime? _slotEnd(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      (doc.data()['endAt'] as Timestamp?)?.toDate();

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatSlotDayHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    if (_isSameDate(date, today)) {
      return 'TODAY - ${DateFormat('MMMM d, yyyy').format(date)}';
    }
    if (_isSameDate(date, tomorrow)) {
      return 'TOMORROW - ${DateFormat('MMMM d, yyyy').format(date)}';
    }
    return DateFormat('EEEE - MMMM d, yyyy').format(date).toUpperCase();
  }

  String _slotTimeRange(DateTime start, DateTime end) {
    final s = DateFormat('h:mm a').format(start);
    final e = DateFormat('h:mm a').format(end);
    return '$s - $e';
  }

  String _slotMeta(DateTime start, DateTime end) {
    final minutes = end.difference(start).inMinutes.clamp(0, 600);
    final duration = minutes % 60 == 0
        ? '${minutes ~/ 60} hour'
        : '$minutes mins';
    return '${DateFormat('EEE, MMM d').format(start)} - $duration session';
  }

  String _slotLabel(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '--';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final slotDay = DateTime(start.year, start.month, start.day);
    final dayLabel = _isSameDate(slotDay, today)
        ? 'Today'
        : DateFormat('EEE, MMM d, yyyy').format(start);
    return '$dayLabel - ${_slotTimeRange(start, end)}';
  }
}

class _CounselingDaySlotGroup {
  final DateTime day;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> slots;

  const _CounselingDaySlotGroup({required this.day, required this.slots});
}

class _CounselingStickyDayHeaderDelegate
    extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _CounselingStickyDayHeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _CounselingStickyDayHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

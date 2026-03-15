import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../shared/widgets/modern_table_layout.dart';
import '../../services/osa_meeting_schedule_service.dart';

enum _StudentCasesTab { review, needsBooking, meeting, history }

class StudentViolationsPage extends StatefulWidget {
  const StudentViolationsPage({super.key});

  @override
  State<StudentViolationsPage> createState() => _StudentViolationsPageState();
}

class _StudentViolationsPageState extends State<StudentViolationsPage> {
  final _searchCtrl = TextEditingController();
  final _meetingScheduleSvc = OsaMeetingScheduleService();
  _StudentCasesTab _tab = _StudentCasesTab.review;
  String? _selectedId;
  Timer? _bookingSweepTimer;
  bool _bookingSweepRunning = false;

  @override
  void initState() {
    super.initState();
    _runBookingExpirySweep();
    _bookingSweepTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _runBookingExpirySweep(),
    );
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

  @override
  void dispose() {
    _bookingSweepTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF6FAF6);
    const primaryColor = Color(0xFF1B5E20);
    const hintColor = Color(0xFF6D7F62);
    const textDark = Color(0xFF1F2A1F);

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
        final desktopWide = constraints.maxWidth >= 1100;

        return Scaffold(
          backgroundColor: bg,
          body: ModernTableLayout(
            header: ModernTableHeader(
              title: 'My Violations',
              subtitle: 'View your recorded violations and tracking status',
              tabs: DefaultTabController(
                length: 4,
                initialIndex: _tab == _StudentCasesTab.review
                    ? 0
                    : _tab == _StudentCasesTab.needsBooking
                    ? 1
                    : _tab == _StudentCasesTab.meeting
                    ? 2
                    : 3,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: primaryColor,
                  indicatorColor: primaryColor,
                  dividerColor: Colors.transparent,
                  onTap: (index) {
                    final newTab = index == 0
                        ? _StudentCasesTab.review
                        : index == 1
                        ? _StudentCasesTab.needsBooking
                        : index == 2
                        ? _StudentCasesTab.meeting
                        : _StudentCasesTab.history;
                    if (newTab == _tab) return;
                    setState(() {
                      _tab = newTab;
                      _selectedId = null;
                    });
                  },
                  tabs: const [
                    Tab(text: 'Under Review'),
                    Tab(text: 'Needs Booking'),
                    Tab(text: 'My Schedule'),
                    Tab(text: 'History'),
                  ],
                ),
              ),
              searchBar: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search violations...',
                  prefixIcon: const Icon(Icons.search, color: primaryColor),
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
              stream: FirebaseFirestore.instance
                  .collection('violation_cases')
                  .where('studentUid', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final raw = snap.data!.docs;
                final q = _searchCtrl.text.toLowerCase().trim();

                List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = raw
                    .where((doc) {
                      final d = doc.data();
                      if (!_isVisibleToStudent(d)) return false;
                      if (!_matchesStudentTab(d, _tab)) return false;
                      if (q.isEmpty) return true;
                      final caseCode = _safeStr(d['caseCode']).toLowerCase();
                      final violation = _safeStr(
                        d['violationTypeLabel'] ??
                            d['typeNameSnapshot'] ??
                            d['violationNameSnapshot'] ??
                            d['violationName'],
                      ).toLowerCase();
                      final status = _safeStr(d['status']).toLowerCase();
                      final severity = _safeStr(
                        d['finalSeverity'],
                      ).toLowerCase();
                      return caseCode.contains(q) ||
                          violation.contains(q) ||
                          status.contains(q) ||
                          severity.contains(q);
                    })
                    .toList();

                docs.sort((a, b) {
                  final da = _bestDate(a.data());
                  final db = _bestDate(b.data());
                  if (da == null && db == null) return 0;
                  if (da == null) return 1;
                  if (db == null) return -1;
                  return db.compareTo(da);
                });

                if (docs.isEmpty) {
                  return _withReviewNotice(
                    child: Center(
                      child: Text(
                        _tab == _StudentCasesTab.review
                            ? 'No cases under review.'
                            : _tab == _StudentCasesTab.needsBooking
                            ? 'No cases that need booking.'
                            : _tab == _StudentCasesTab.meeting
                            ? 'No scheduled meeting cases.'
                            : 'No case history.',
                        style: const TextStyle(
                          color: hintColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }

                return _withReviewNotice(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final isSelected = _selectedId == doc.id;
                      return _buildViolationCard(
                        doc.id,
                        doc.data(),
                        isSelected,
                        desktopWide,
                        () {
                          if (desktopWide) {
                            setState(
                              () => _selectedId = isSelected ? null : doc.id,
                            );
                          } else {
                            _openDetails(doc);
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
            showDetails: _selectedId != null,
            details: _selectedId != null
                ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('violation_cases')
                        .doc(_selectedId)
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const SizedBox();
                      final doc = snap.data!;
                      if (!doc.exists) {
                        return const Center(child: Text('Case not found'));
                      }

                      return _DesktopDetailsPanel(
                        doc: doc,
                        primaryColor: primaryColor,
                        hintColor: hintColor,
                      );
                    },
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _withReviewNotice({required Widget child}) {
    if (_tab != _StudentCasesTab.review) return child;
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: _ReviewNoticeBox(),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildViolationCard(
    String id,
    Map<String, dynamic> data,
    bool isSelected,
    bool isDesktop,
    VoidCallback onTap,
  ) {
    const primaryColor = Color(0xFF1B5E20);
    const hintColor = Color(0xFF6D7F62);
    const textDark = Color(0xFF1F2A1F);

    final caseCode = (data['caseCode'] ?? 'No Code').toString();
    final violation =
        (data['violationTypeLabel'] ?? data['typeNameSnapshot'] ?? 'Violation')
            .toString();
    final status = _statusLabel(_safeStr(data['status']));
    final date = _bestDate(data);

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
                      _buildStatusBadge(status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    violation,
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
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    return _studentStatusPill(status);
  }

  void _openDetails(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
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
        child: _StudentCaseDetailsSheet(doc: doc),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onSearchChanged;
  final Color primaryColor;
  final Color hintColor;
  final int total;
  final int shown;

  const _Header({
    required this.searchCtrl,
    required this.filter,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.primaryColor,
    required this.hintColor,
    required this.total,
    required this.shown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.warning_rounded, color: primaryColor),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'My Violations',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$shown / $total',
                  style: TextStyle(
                    color: hintColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;

              final search = TextField(
                controller: searchCtrl,
                onChanged: (_) => onSearchChanged(),
                decoration: InputDecoration(
                  hintText: 'Search (case code, violation, status, severity)',
                  hintStyle: TextStyle(
                    color: hintColor,
                    fontWeight: FontWeight.w700,
                  ),
                  prefixIcon: Icon(Icons.search_rounded, color: hintColor),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.black.withOpacity(0.10),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.black.withOpacity(0.10),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: primaryColor, width: 1.4),
                  ),
                ),
              );

              final filterDd = _FilterDropdown(
                value: filter,
                onChanged: onFilterChanged,
                primaryColor: primaryColor,
                hintColor: hintColor,
                fullWidth: narrow,
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [search, const SizedBox(height: 10), filterDd],
                );
              }

              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  filterDd,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final Color primaryColor;
  final Color hintColor;
  final bool fullWidth;

  const _FilterDropdown({
    required this.value,
    required this.onChanged,
    required this.primaryColor,
    required this.hintColor,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: fullWidth ? 0 : 170),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: const [
          DropdownMenuItem(value: 'All', child: Text('All')),
          DropdownMenuItem(
            value: 'Meeting Required',
            child: Text('Meeting Required'),
          ),
          DropdownMenuItem(value: 'Pending', child: Text('Pending')),
          DropdownMenuItem(value: 'Resolved', child: Text('Resolved')),
        ],
        onChanged: (v) => onChanged(v ?? 'All'),
        isExpanded: true,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Color primaryColor;
  final Color hintColor;
  final VoidCallback onOpen;

  const _CaseCard({
    required this.doc,
    required this.primaryColor,
    required this.hintColor,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data() ?? <String, dynamic>{};
    final code = _safeStr(d['caseCode']).isEmpty
        ? doc.id
        : _safeStr(d['caseCode']);
    final violation = _safeStr(
      d['violationTypeLabel'] ??
          d['typeNameSnapshot'] ??
          d['violationNameSnapshot'] ??
          d['violationName'],
    );
    final status = _statusLabel(_safeStr(d['status']));
    final severity = _safeStr(d['finalSeverity']);
    final meetingRequired = _meetingRequired(d);
    final due = _tsToDate(d['meetingDueBy']);
    final meetingWindowRaw = _safeStr(d['meetingWindow']);
    final meetingBadgeText = _meetingWindowCompactBadgeText(
      meetingWindowRaw,
      due,
    );

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    code,
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _Pill(
                  text: status,
                  tone: _statusTone(
                    _safeStr(d['status']),
                    primaryColor,
                    hintColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              violation.isEmpty ? '--' : violation,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (severity.isNotEmpty)
                  _Pill(
                    text: severity.toUpperCase(),
                    tone: _severityTone(severity, primaryColor),
                  ),
                if (meetingRequired)
                  _Pill(
                    text: meetingBadgeText,
                    tone: _Tone(
                      fill: primaryColor.withOpacity(0.10),
                      border: primaryColor.withOpacity(0.25),
                      text: primaryColor,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool active;
  final Color primaryColor;
  final Color hintColor;
  final VoidCallback onTap;

  const _DesktopRow({
    required this.doc,
    required this.active,
    required this.primaryColor,
    required this.hintColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data() ?? <String, dynamic>{};
    final code = _safeStr(d['caseCode']).isEmpty
        ? doc.id
        : _safeStr(d['caseCode']);
    final violation = _safeStr(
      d['violationTypeLabel'] ??
          d['typeNameSnapshot'] ??
          d['violationNameSnapshot'] ??
          d['violationName'],
    );
    final status = _statusLabel(_safeStr(d['status']));
    final meetingRequired = _meetingRequired(d);
    final due = _tsToDate(d['meetingDueBy']);
    final meetingWindowRaw = _safeStr(d['meetingWindow']);
    final meetingBadgeText = _meetingWindowCompactBadgeText(
      meetingWindowRaw,
      due,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: active ? primaryColor.withOpacity(0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? primaryColor.withOpacity(0.22)
                : Colors.black.withOpacity(0.06),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code,
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    violation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (meetingRequired)
              _Pill(
                text: meetingBadgeText,
                tone: _Tone(
                  fill: primaryColor.withOpacity(0.10),
                  border: primaryColor.withOpacity(0.22),
                  text: primaryColor,
                ),
              ),
            const SizedBox(width: 8),
            _Pill(
              text: status,
              tone: _statusTone(_safeStr(d['status']), primaryColor, hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopDetailsPanel extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final Color primaryColor;
  final Color hintColor;

  const _DesktopDetailsPanel({
    required this.doc,
    required this.primaryColor,
    required this.hintColor,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data() ?? <String, dynamic>{};
    const textDark = Color(0xFF1F2A1F);
    final code = _safeStr(d['caseCode']).isEmpty
        ? doc.id
        : _safeStr(d['caseCode']);
    final violation = _safeStr(
      d['violationTypeLabel'] ??
          d['typeNameSnapshot'] ??
          d['violationNameSnapshot'] ??
          d['violationName'],
    );
    final dateReported = _bestDate(d);
    final dateReportedText = _formatReportedAtSmart(dateReported);
    final reporterDisplay = _reportedByDisplay(d);
    final concern = _safeStr(d['concern'] ?? d['reportedConcernType']);
    final category = _categoryLabelFromCase(d);
    final desc = _safeStr(d['description'] ?? d['narrative']);
    final statusRaw = _safeStr(d['status']);
    final statusKey = _statusKey(statusRaw);
    final status = _statusLabel(statusRaw);
    final isResolvedCase = _statusKey(statusRaw) == 'resolved';
    final isUnderReviewCase =
        statusKey == 'under review' || statusKey == 'submitted';
    final severity = _safeStr(d['finalSeverity']);
    final sanctionType = _safeStr(d['sanctionType']);
    final sanctionLabel = sanctionType.isEmpty
        ? '--'
        : sanctionType.toLowerCase() == 'none'
        ? 'None'
        : _titleCase(sanctionType);
    final meetingRequired = _meetingRequired(d);
    final meetingTypeText = _meetingTypeLabelForDetails(d);
    final meetingStatusText = _meetingStatusTextForDetails(
      d,
      isResolvedCase: isResolvedCase,
    );
    final scheduledAt = _tsToDate(d['scheduledAt']);
    final scheduledMeetingText = _scheduledMeetingText(scheduledAt);
    final showScheduledAtCard = meetingRequired && scheduledAt != null;
    final due = _tsToDate(d['meetingDueBy']);
    final bookingDeadline = _tsToDate(d['bookingDeadlineAt']);
    final officialRemarks = _safeStr(d['officialRemarks']);
    final meetingStatusRaw = _safeStr(d['meetingStatus']).toLowerCase();
    final pendingBooking =
        meetingStatusRaw.isEmpty ||
        meetingStatusRaw == 'pending' ||
        meetingStatusRaw == 'pending_student_booking';
    final bookingDeadlinePassed = _isPast(bookingDeadline);
    final duePassed = _isPast(due);
    final schoolYearId = _safeStr(d['schoolYearId']);
    final termId = _safeStr(d['termId']);
    final canBookMeetingSlot =
        meetingRequired &&
        !isResolvedCase &&
        pendingBooking &&
        !bookingDeadlinePassed &&
        !duePassed &&
        schoolYearId.isNotEmpty &&
        termId.isNotEmpty &&
        _safeStr(d['studentUid']).isNotEmpty;

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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primaryColor.withOpacity(0.25)),
                  ),
                  child: Text(
                    code,
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Case Details',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                _studentStatusPill(status),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _StudentDetailCard(
                    title: 'Incident Summary',
                    child: Column(
                      children: [
                        _studentKv(
                          'Concern',
                          concern.isEmpty ? '--' : _titleCase(concern),
                        ),
                        const SizedBox(height: 8),
                        _studentKv(
                          'Category',
                          category.isEmpty ? '--' : category,
                        ),
                        const SizedBox(height: 8),
                        _studentKv(
                          'Violation Type',
                          violation.isEmpty ? '--' : violation,
                        ),
                        const SizedBox(height: 8),
                        _studentKv('Date Reported', dateReportedText),
                        const SizedBox(height: 8),
                        _studentKv('Reported By', reporterDisplay),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StudentDetailCard(
                    title: 'Incident Description',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.08),
                        ),
                      ),
                      child: Text(
                        desc.isEmpty ? '--' : desc,
                        style: const TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                  if (officialRemarks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _StudentDetailCard(
                      title: 'OSA Remarks',
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.08),
                          ),
                        ),
                        child: Text(
                          officialRemarks,
                          style: TextStyle(
                            color: hintColor,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (isResolvedCase) ...[
                    const SizedBox(height: 12),
                    _StudentDetailCard(
                      title: 'Assessment & Decision',
                      child: Column(
                        children: [
                          _studentKv(
                            'Severity',
                            severity.isEmpty ? '--' : severity.toUpperCase(),
                          ),
                          const SizedBox(height: 8),
                          _studentKv('Sanction Given', sanctionLabel),
                        ],
                      ),
                    ),
                  ],
                  if (!isUnderReviewCase) ...[
                    const SizedBox(height: 12),
                    _StudentDetailCard(
                      title: isResolvedCase
                          ? 'Meeting History'
                          : 'Meeting Status',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _studentKv('Meeting Type', meetingTypeText),
                          const SizedBox(height: 8),
                          _studentKv('Meeting Status', meetingStatusText),
                          if (showScheduledAtCard) ...[
                            const SizedBox(height: 8),
                            _meetingInfoCard(
                              label: 'Scheduled At',
                              value: scheduledMeetingText,
                            ),
                          ],
                          if (canBookMeetingSlot) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  await OsaMeetingScheduleService()
                                      .expireOverduePendingBookings();
                                  if (!context.mounted) return;
                                  await showDialog<bool>(
                                    context: context,
                                    builder: (_) => _BookMeetingSlotDialog(
                                      caseId: doc.id,
                                      studentUid: _safeStr(d['studentUid']),
                                      schoolYearId: schoolYearId,
                                      termId: termId,
                                      meetingDueBy: due,
                                      bookingDeadlineAt: bookingDeadline,
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.event_available_rounded,
                                  size: 18,
                                ),
                                label: const Text(
                                  'BOOK MEETING SLOT',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ] else if (!isResolvedCase &&
                              meetingRequired &&
                              pendingBooking &&
                              (bookingDeadlinePassed || duePassed)) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.28),
                                ),
                              ),
                              child: Text(
                                bookingDeadlinePassed
                                    ? 'Booking window has ended. Please wait for OSA follow-up.'
                                    : 'Meeting due window has passed. Please wait for OSA follow-up.',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            isResolvedCase
                                ? 'Case is resolved. Meeting information is shown for history.'
                                : 'If a meeting is required, please book and attend based on OSA instructions.',
                            style: TextStyle(
                              color: hintColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
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
        ],
      ),
    );
  }
}

class _StudentCaseDetailsSheet extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _StudentCaseDetailsSheet({required this.doc});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF6FAF6);
    const primaryColor = Color(0xFF1B5E20);
    const hintColor = Color(0xFF6D7F62);
    const textDark = Color(0xFF1F2A1F);

    final d = doc.data();
    final code = _safeStr(d['caseCode']).isEmpty
        ? doc.id
        : _safeStr(d['caseCode']);
    final violation = _safeStr(
      d['violationTypeLabel'] ??
          d['typeNameSnapshot'] ??
          d['violationNameSnapshot'] ??
          d['violationName'],
    );
    final dateReported = _bestDate(d);
    final dateReportedText = _formatReportedAtSmart(dateReported);
    final reporterDisplay = _reportedByDisplay(d);
    final concern = _safeStr(d['concern'] ?? d['reportedConcernType']);
    final category = _categoryLabelFromCase(d);
    final statusRaw = _safeStr(d['status']);
    final statusKey = _statusKey(statusRaw);
    final status = _statusLabel(statusRaw);
    final isResolvedCase = _statusKey(statusRaw) == 'resolved';
    final isUnderReviewCase =
        statusKey == 'under review' || statusKey == 'submitted';
    final severity = _safeStr(d['finalSeverity']);
    final sanctionType = _safeStr(d['sanctionType']);
    final sanctionLabel = sanctionType.isEmpty
        ? '--'
        : sanctionType.toLowerCase() == 'none'
        ? 'None'
        : _titleCase(sanctionType);
    final meetingRequired = _meetingRequired(d);
    final meetingTypeText = _meetingTypeLabelForDetails(d);
    final meetingStatusText = _meetingStatusTextForDetails(
      d,
      isResolvedCase: isResolvedCase,
    );
    final scheduledAt = _tsToDate(d['scheduledAt']);
    final scheduledMeetingText = _scheduledMeetingText(scheduledAt);
    final showScheduledAtCard = meetingRequired && scheduledAt != null;
    final due = _tsToDate(d['meetingDueBy']);
    final bookingDeadline = _tsToDate(d['bookingDeadlineAt']);
    final desc = _safeStr(d['description'] ?? d['narrative']);
    final officialRemarks = _safeStr(d['officialRemarks']);
    final meetingStatusRaw = _safeStr(d['meetingStatus']).toLowerCase();
    final pendingBooking =
        meetingStatusRaw.isEmpty ||
        meetingStatusRaw == 'pending' ||
        meetingStatusRaw == 'pending_student_booking';
    final bookingDeadlinePassed = _isPast(bookingDeadline);
    final duePassed = _isPast(due);
    final schoolYearId = _safeStr(d['schoolYearId']);
    final termId = _safeStr(d['termId']);
    final canBookMeetingSlot =
        meetingRequired &&
        !isResolvedCase &&
        pendingBooking &&
        !bookingDeadlinePassed &&
        !duePassed &&
        schoolYearId.isNotEmpty &&
        termId.isNotEmpty &&
        _safeStr(d['studentUid']).isNotEmpty;

    return ColoredBox(
      color: bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primaryColor.withOpacity(0.25)),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Case Details',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                Flexible(child: _studentStatusPill(status)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _StudentDetailCard(
                    title: 'Case Details',
                    child: Column(
                      children: [
                        _studentKv(
                          'Concern',
                          concern.isEmpty ? '--' : _titleCase(concern),
                        ),
                        const SizedBox(height: 8),
                        _studentKv(
                          'Category',
                          category.isEmpty ? '--' : category,
                        ),
                        const SizedBox(height: 8),
                        _studentKv(
                          'Violation Type',
                          violation.isEmpty ? '--' : violation,
                        ),
                        const SizedBox(height: 8),
                        _studentKv('Date Reported', dateReportedText),
                        const SizedBox(height: 8),
                        _studentKv('Reported By', reporterDisplay),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StudentDetailCard(
                    title: 'Incident Description',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.08),
                        ),
                      ),
                      child: Text(
                        desc.isEmpty ? '--' : desc,
                        style: const TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                  if (officialRemarks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _StudentDetailCard(
                      title: 'OSA Remarks',
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.08),
                          ),
                        ),
                        child: Text(
                          officialRemarks,
                          style: TextStyle(
                            color: hintColor,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (isResolvedCase) ...[
                    const SizedBox(height: 12),
                    _StudentDetailCard(
                      title: 'Assessment & Decision',
                      child: Column(
                        children: [
                          _studentKv(
                            'Severity',
                            severity.isEmpty ? '--' : severity.toUpperCase(),
                          ),
                          const SizedBox(height: 8),
                          _studentKv('Sanction Given', sanctionLabel),
                        ],
                      ),
                    ),
                  ],
                  if (!isUnderReviewCase) ...[
                    const SizedBox(height: 12),
                    _StudentDetailCard(
                      title: isResolvedCase
                          ? 'Meeting History'
                          : 'Meeting Status',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _studentKv('Meeting Type', meetingTypeText),
                          const SizedBox(height: 8),
                          _studentKv('Meeting Status', meetingStatusText),
                          if (showScheduledAtCard) ...[
                            const SizedBox(height: 8),
                            _meetingInfoCard(
                              label: 'Scheduled At',
                              value: scheduledMeetingText,
                            ),
                          ],
                          if (canBookMeetingSlot) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  await OsaMeetingScheduleService()
                                      .expireOverduePendingBookings();
                                  if (!context.mounted) return;
                                  await showDialog<bool>(
                                    context: context,
                                    builder: (_) => _BookMeetingSlotDialog(
                                      caseId: doc.id,
                                      studentUid: _safeStr(d['studentUid']),
                                      schoolYearId: schoolYearId,
                                      termId: termId,
                                      meetingDueBy: due,
                                      bookingDeadlineAt: bookingDeadline,
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.event_available_rounded,
                                  size: 18,
                                ),
                                label: const Text(
                                  'BOOK MEETING SLOT',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ] else if (!isResolvedCase &&
                              meetingRequired &&
                              pendingBooking &&
                              (bookingDeadlinePassed || duePassed)) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.28),
                                ),
                              ),
                              child: Text(
                                bookingDeadlinePassed
                                    ? 'Booking window has ended. Please wait for OSA follow-up.'
                                    : 'Meeting due window has passed. Please wait for OSA follow-up.',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            isResolvedCase
                                ? 'Case is resolved. Meeting information is shown for history.'
                                : 'If a meeting is required, please book and attend based on OSA instructions.',
                            style: TextStyle(
                              color: hintColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentDetailCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _StudentDetailCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
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

class _ReviewNoticeBox extends StatelessWidget {
  const _ReviewNoticeBox();

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1B5E20);
    const hintColor = Color(0xFF6D7F62);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2E3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: primaryColor.withOpacity(0.9),
            size: 18,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Your case is under review. Please wait for OSA action updates or meeting instructions.',
              style: TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _studentKv(String label, String value) {
  const hintColor = Color(0xFF6D7F62);
  const textDark = Color(0xFF1F2A1F);

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
            fontSize: 12,
          ),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            color: textDark,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            height: 1.3,
          ),
        ),
      ),
    ],
  );
}

Widget _meetingInfoCard({required String label, required String value}) {
  const primaryColor = Color(0xFF1B5E20);
  const hintColor = Color(0xFF6D7F62);
  const textDark = Color(0xFF1F2A1F);

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
          size: 16,
          color: primaryColor.withValues(alpha: 0.88),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: hintColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
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

class _BookMeetingSlotDialog extends StatefulWidget {
  final String caseId;
  final String studentUid;
  final String schoolYearId;
  final String termId;
  final DateTime? meetingDueBy;
  final DateTime? bookingDeadlineAt;

  const _BookMeetingSlotDialog({
    required this.caseId,
    required this.studentUid,
    required this.schoolYearId,
    required this.termId,
    required this.meetingDueBy,
    required this.bookingDeadlineAt,
  });

  @override
  State<_BookMeetingSlotDialog> createState() => _BookMeetingSlotDialogState();
}

class _BookMeetingSlotDialogState extends State<_BookMeetingSlotDialog> {
  final _svc = OsaMeetingScheduleService();
  final _slotScrollCtrl = ScrollController();
  static const _bg = Color(0xFFF6FAF6);
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final earliestAllowedStart = now.add(
      OsaMeetingScheduleService.bookingLeadTime,
    );
    final bookingClosed =
        widget.bookingDeadlineAt != null &&
        now.isAfter(widget.bookingDeadlineAt!);
    final dueWindowClosed =
        widget.meetingDueBy != null && now.isAfter(widget.meetingDueBy!);
    final defaultUpperBound = now.add(const Duration(days: 14));
    final upperBound =
        (widget.meetingDueBy != null &&
            widget.meetingDueBy!.isBefore(defaultUpperBound))
        ? widget.meetingDueBy!
        : defaultUpperBound;
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
            'Select Meeting Slot',
            style: TextStyle(
              color: _primaryColor,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Choose one available schedule for your OSA meeting.',
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
        child: (bookingClosed || dueWindowClosed)
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
                        bookingClosed
                            ? 'Booking window already ended. Please wait for OSA follow-up.'
                            : 'Meeting due window already passed. Please wait for OSA follow-up.',
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
                stream: _svc.streamOpenSlots(
                  schoolYearId: widget.schoolYearId,
                  termId: widget.termId,
                  limit: 120,
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
                    return const SizedBox(
                      child: Center(
                        child: CircularProgressIndicator(color: _primaryColor),
                      ),
                    );
                  }

                  final docs =
                      snapshot.data!.where((slotDoc) {
                        final data = slotDoc.data();
                        final start = (data['startAt'] as Timestamp?)?.toDate();
                        if (start == null) return false;
                        if (start.isBefore(now)) return false;
                        if (start.isBefore(earliestAllowedStart)) return false;
                        if (start.isAfter(upperBound)) return false;
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
                      child: Center(
                        child: Text(
                          widget.meetingDueBy == null
                              ? 'No available meeting slots right now.\nTry again later (2-hour advance booking required).'
                              : 'No slots available before ${_fmtDeadline(widget.meetingDueBy!)}\nwith at least 2 hours advance booking.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
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
                          widget.meetingDueBy == null
                              ? 'Available slots shown: next 14 days (minimum 2-hour lead time).'
                              : 'Book until ${_fmtDeadline(widget.meetingDueBy!)} (minimum 2-hour lead time).',
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
                                for (final group in dayGroups) ...[
                                  SliverPersistentHeader(
                                    pinned: true,
                                    delegate: _StickyDayHeaderDelegate(
                                      height: 34,
                                      child: Container(
                                        color: Colors.white,
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.only(
                                          top: 8,
                                          bottom: 6,
                                        ),
                                        child: Text(
                                          _formatSlotDayHeader(group.day),
                                          style: const TextStyle(
                                            color: _hintColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                            letterSpacing: 0.6,
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
                                                () => _selectedSlotId = slotId,
                                              ),
                                      );
                                    }, childCount: group.slots.length),
                                  ),
                                ],
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
          onPressed:
              bookingClosed ||
                  dueWindowClosed ||
                  _booking ||
                  _selectedSlotId == null
              ? null
              : () async {
                  setState(() => _booking = true);
                  try {
                    await _svc.bookSlotForCase(
                      slotId: _selectedSlotId!,
                      caseId: widget.caseId,
                      studentUid: widget.studentUid,
                    );
                    if (!mounted) return;
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context, true);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Meeting slot booked successfully.'),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    setState(() => _booking = false);
                    ScaffoldMessenger.of(context).showSnackBar(
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

  List<_DaySlotGroup> _groupSlotsByDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final groups = <_DaySlotGroup>[];
    DateTime? currentDay;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> currentSlots = [];

    for (final doc in docs) {
      final start = _slotStart(doc);
      if (start == null) continue;
      final dayKey = DateTime(start.year, start.month, start.day);
      if (currentDay == null || !_isSameDate(currentDay, dayKey)) {
        if (currentDay != null && currentSlots.isNotEmpty) {
          groups.add(_DaySlotGroup(day: currentDay, slots: currentSlots));
        }
        currentDay = dayKey;
        currentSlots = [doc];
      } else {
        currentSlots.add(doc);
      }
    }

    if (currentDay != null && currentSlots.isNotEmpty) {
      groups.add(_DaySlotGroup(day: currentDay, slots: currentSlots));
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

class _DaySlotGroup {
  final DateTime day;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> slots;

  const _DaySlotGroup({required this.day, required this.slots});
}

class _StickyDayHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _StickyDayHeaderDelegate({required this.height, required this.child});

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
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickyDayHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'No violations found for the selected filters.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState(this.error);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

Widget _studentStatusPill(String status) {
  const primaryColor = Color(0xFF1B5E20);
  const hintColor = Color(0xFF6D7F62);
  return _Pill(
    text: status,
    tone: _statusTone(status, primaryColor, hintColor),
  );
}

class _Pill extends StatelessWidget {
  final String text;
  final _Tone tone;
  const _Pill({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(999),
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

class _Tone {
  final Color fill;
  final Color border;
  final Color text;
  const _Tone({required this.fill, required this.border, required this.text});
}

bool _matchesStudentTab(Map<String, dynamic> d, _StudentCasesTab tab) {
  final statusKey = _statusKey(_safeStr(d['status']));
  final meetingRequired = _meetingRequired(d);
  final meetingFlow = _studentMeetingFlowKey(d);

  switch (tab) {
    case _StudentCasesTab.review:
      return statusKey == 'submitted' || statusKey == 'under review';
    case _StudentCasesTab.needsBooking:
      return meetingRequired &&
          statusKey != 'resolved' &&
          statusKey != 'unresolved' &&
          meetingFlow == 'needs_booking';
    case _StudentCasesTab.meeting:
      return statusKey != 'resolved' &&
          statusKey != 'unresolved' &&
          meetingRequired &&
          (meetingFlow == 'scheduled' || meetingFlow == 'completed');
    case _StudentCasesTab.history:
      return statusKey == 'resolved' || statusKey == 'unresolved';
  }
}

bool _isVisibleToStudent(Map<String, dynamic> d) {
  final statusKey = _statusKey(_safeStr(d['status']));
  return statusKey == 'submitted' ||
      statusKey == 'under review' ||
      statusKey == 'action set' ||
      statusKey == 'unresolved' ||
      statusKey == 'resolved';
}

bool _meetingRequired(Map<String, dynamic> d) {
  final req = d['meetingRequired'];
  if (req is bool) return req;
  final action = _safeStr(d['actionSelected'] ?? d['actionType']).toLowerCase();
  return action.contains('guidance') ||
      action.contains('check') ||
      action.contains('parent') ||
      action.contains('guardian') ||
      action.contains('osa') ||
      action.contains('immediate');
}

String _studentMeetingFlowKey(Map<String, dynamic> d) {
  if (!_meetingRequired(d)) return 'no_meeting';

  final meetingStatus = _safeStr(d['meetingStatus']).toLowerCase();
  final bookingStatus = _safeStr(d['bookingStatus']).toLowerCase();
  final hasSchedule = _tsToDate(d['scheduledAt']) != null;

  if (meetingStatus.contains('completed') ||
      bookingStatus.contains('completed')) {
    return 'completed';
  }
  if (meetingStatus.contains('scheduled') ||
      meetingStatus.contains('booked') ||
      bookingStatus.contains('booked') ||
      hasSchedule) {
    return 'scheduled';
  }
  if (meetingStatus.contains('booking_missed') ||
      meetingStatus.contains('meeting_missed') ||
      (meetingStatus.contains('missed') &&
          !meetingStatus.contains('dismiss')) ||
      bookingStatus.contains('missed')) {
    return 'missed';
  }
  return 'needs_booking';
}

String _meetingStatusLabel(Map<String, dynamic> d) {
  final raw = _safeStr(d['meetingStatus']).toLowerCase();
  if (raw.contains('pending_student_booking')) {
    return 'Meeting: Awaiting Booking';
  }
  if (raw.contains('booking_missed')) return 'Meeting: Missed';
  if (raw.contains('scheduled') || raw.contains('booked')) {
    return 'Meeting: Scheduled';
  }
  if (raw.contains('completed')) return 'Meeting: Completed';
  if (raw.contains('missed')) return 'Meeting: Missed';
  if (raw.contains('pending')) return 'Meeting: Pending';
  return _meetingRequired(d) ? 'Meeting: Required' : 'No meeting';
}

String _meetingTypeLabelForDetails(Map<String, dynamic> d) {
  final rawAction = _safeStr(d['actionSelected'] ?? d['actionType']);
  if (rawAction.isNotEmpty) {
    return _titleCase(rawAction.replaceAll('-', ' '));
  }
  return _meetingRequired(d) ? 'Meeting Required' : 'No Meeting Required';
}

String _meetingStatusTextForDetails(
  Map<String, dynamic> d, {
  required bool isResolvedCase,
}) {
  final source = isResolvedCase
      ? _meetingHistoryText(d)
      : _meetingStatusLabel(d);
  final trimmed = source.trim();
  if (trimmed.toLowerCase().startsWith('meeting:')) {
    return trimmed.substring('meeting:'.length).trim();
  }
  return trimmed;
}

String _meetingHistoryText(Map<String, dynamic> d) {
  if (!_meetingRequired(d)) return 'No Meeting Required';
  final raw = _safeStr(d['meetingStatus']).toLowerCase();
  if (raw.contains('completed')) return 'Meeting Completed';
  if (raw.contains('booking_missed') || raw.contains('missed')) {
    return 'Meeting Missed';
  }
  if (raw.contains('scheduled') || raw.contains('booked')) {
    return 'Meeting Scheduled';
  }
  if (raw.contains('pending_student_booking') || raw.contains('pending')) {
    return 'Meeting Required (Not Booked)';
  }
  return 'Meeting Required';
}

String _meetingWindowLabel(String raw) {
  final k = raw.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  if (k.isEmpty) return '';
  switch (k) {
    case 'today':
    case 'withinaday':
    case 'within1day':
      return 'Same Day';
    case '3days':
    case 'threedays':
    case 'within3days':
      return '3 Days';
    case 'week':
    case '1week':
    case 'withinweek':
    case 'within7days':
      return '1 Week';
    default:
      return _titleCase(raw);
  }
}

String _meetingWindowCompactBadgeText(String raw, DateTime? due) {
  if (due != null) {
    final when = _fmtShort(due);
    return _isPast(due) ? 'MISSED $when' : 'BOOK BY $when';
  }
  final window = _meetingWindowLabel(raw);
  return window.isEmpty ? 'MEETING REQUIRED' : window.toUpperCase();
}

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

bool _isPast(DateTime? date) {
  if (date == null) return false;
  return DateTime.now().isAfter(date);
}

String _fmtDeadline(DateTime date) {
  return DateFormat('MMM d, h:mm a').format(date);
}

String _formatReportedAtSmart(DateTime? date) {
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

String _formatMeetingScheduleSmart(DateTime date) {
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

String _scheduledMeetingText(DateTime? scheduledAt) {
  if (scheduledAt == null) return 'Not yet scheduled';
  return _formatMeetingScheduleSmart(scheduledAt);
}

String _safeStr(dynamic v) => (v ?? '').toString().trim();

String _categoryLabelFromCase(Map<String, dynamic> data) {
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

_Tone _statusTone(String raw, Color primaryColor, Color hintColor) {
  final k = _statusKey(raw);
  switch (k) {
    case 'resolved':
      return _Tone(
        fill: primaryColor.withOpacity(0.14),
        border: primaryColor.withOpacity(0.35),
        text: primaryColor,
      );
    case 'action set':
      return _Tone(
        fill: primaryColor.withOpacity(0.10),
        border: primaryColor.withOpacity(0.25),
        text: primaryColor,
      );
    case 'unresolved':
      return _Tone(
        fill: Colors.red.withOpacity(0.10),
        border: Colors.red.withOpacity(0.25),
        text: Colors.red.shade900,
      );
    case 'under review':
      return _Tone(
        fill: Colors.black.withOpacity(0.04),
        border: Colors.black.withOpacity(0.10),
        text: hintColor,
      );
    default:
      return _Tone(
        fill: Colors.black.withOpacity(0.04),
        border: Colors.black.withOpacity(0.10),
        text: hintColor,
      );
  }
}

_Tone _severityTone(String raw, Color primaryColor) {
  final s = raw.toLowerCase();
  if (s.contains('major')) {
    return _Tone(
      fill: Colors.red.withOpacity(0.10),
      border: Colors.red.withOpacity(0.30),
      text: Colors.red.shade900,
    );
  }
  if (s.contains('moderate')) {
    return _Tone(
      fill: Colors.orange.withOpacity(0.10),
      border: Colors.orange.withOpacity(0.30),
      text: Colors.orange.shade900,
    );
  }
  if (s.contains('minor')) {
    return _Tone(
      fill: primaryColor.withOpacity(0.10),
      border: primaryColor.withOpacity(0.30),
      text: primaryColor,
    );
  }
  return _Tone(
    fill: Colors.blue.withOpacity(0.10),
    border: Colors.blue.withOpacity(0.30),
    text: Colors.blue.shade900,
  );
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

String _titleCase(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  final parts = t.replaceAll('_', ' ').split(RegExp(r'\\s+'));
  return parts
      .map(
        (p) =>
            p.isEmpty ? p : p[0].toUpperCase() + p.substring(1).toLowerCase(),
      )
      .join(' ');
}

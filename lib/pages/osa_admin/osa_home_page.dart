import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/violation_case_service.dart';
import 'package:apps/services/app_firestore.dart';

class OsaHomePage extends StatefulWidget {
  final VoidCallback? onOpenAcademicSettings;
  final VoidCallback? onOpenViolationReview;
  final VoidCallback? onOpenMeetingSchedule;
  final ValueChanged<String>? onOpenCase;

  const OsaHomePage({
    super.key,
    this.onOpenAcademicSettings,
    this.onOpenViolationReview,
    this.onOpenMeetingSchedule,
    this.onOpenCase,
  });

  static const primary = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hint = Color(0xFF6D7F62);

  @override
  State<OsaHomePage> createState() => _OsaHomePageState();
}

class _OsaHomePageState extends State<OsaHomePage> {
  static const primary = OsaHomePage.primary;
  static const textDark = OsaHomePage.textDark;
  static const hint = OsaHomePage.hint;

  String? _tappedCaseId;
  int _tapStamp = 0;

  void _openCaseWithFlash(String caseId, VoidCallback onOpen) {
    final tapStamp = ++_tapStamp;
    if (mounted) setState(() => _tappedCaseId = caseId);
    onOpen();
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted || tapStamp != _tapStamp) return;
      if (_tappedCaseId == caseId) {
        setState(() => _tappedCaseId = null);
      }
    });
  }

  DateTime? _toDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  String _safe(dynamic v) => (v ?? '').toString().trim();

  String _studentName(Map<String, dynamic> userData) {
    final display = _safe(userData['displayName']);
    if (display.isNotEmpty && display != '--') return display;

    final first = _safe(userData['firstName']);
    final middle = _safe(userData['middleName']);
    final last = _safe(userData['lastName']);
    final full = [first, middle, last].where((e) => e.isNotEmpty).join(' ');
    if (full.isNotEmpty) return full;

    final email = _safe(userData['email']);
    if (email.contains('@')) return email.split('@').first;
    return 'Student';
  }

  String _fmtCardDate(DateTime? date) {
    if (date == null) return '--';
    final local = date.toLocal();
    const m = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final now = DateTime.now();
    if (local.year == now.year) return '${m[local.month - 1]} ${local.day}';
    return '${m[local.month - 1]} ${local.day}, ${local.year}';
  }

  String _statusKey(Map<String, dynamic> data) {
    return _safe(data['status']).toLowerCase().trim();
  }

  bool _meetingRequired(Map<String, dynamic> data) {
    final req = data['meetingRequired'];
    if (req is bool) return req;

    final action = _safe(data['actionType']).toLowerCase();
    if (action.contains('monitoring')) return false;
    return true;
  }

  String _meetingFlowKey(Map<String, dynamic> data) {
    if (!_meetingRequired(data)) return 'not_required';

    final meetingStatus = _safe(data['meetingStatus']).toLowerCase();
    final bookingStatus = _safe(data['bookingStatus']).toLowerCase();
    final scheduledAt = _toDate(data['scheduledAt']);
    final bookingDeadlineAt = _toDate(data['bookingDeadlineAt']);

    final hasSchedule =
        scheduledAt != null ||
        meetingStatus.contains('scheduled') ||
        bookingStatus.contains('booked');

    if (meetingStatus.contains('completed') ||
        bookingStatus.contains('completed')) {
      return 'completed';
    }

    if (meetingStatus.contains('booking_missed') ||
        bookingStatus.contains('missed')) {
      return hasSchedule ? 'meeting_missed' : 'booking_missed';
    }

    if (meetingStatus.contains('meeting_missed')) return 'meeting_missed';
    if (hasSchedule) return 'scheduled';

    final pendingLike =
        meetingStatus.isEmpty ||
        meetingStatus.contains('pending') ||
        meetingStatus.contains('needs_booking');

    if (pendingLike) {
      final now = DateTime.now();
      if (bookingDeadlineAt != null && now.isAfter(bookingDeadlineAt)) {
        return 'booking_missed';
      }
      return 'needs_booking';
    }

    return 'needs_booking';
  }

  int _countByStatus(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Set<String> statuses,
  ) {
    return docs.where((doc) {
      final status = _safe(doc.data()['status']).toLowerCase();
      return statuses.contains(status);
    }).length;
  }

  String _normalizedStudentVerification(Map<String, dynamic> data) {
    final field = _safe(data['studentVerificationStatus']).toLowerCase();
    if (field.isNotEmpty) return field;

    final legacy = _safe(data['status']).toLowerCase();
    if (legacy.isNotEmpty) return legacy;

    return 'verified';
  }

  bool _isApprovedStudent(Map<String, dynamic> data) {
    return _normalizedStudentVerification(data) == 'verified';
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AppFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'student')
          .snapshots(),
      builder: (context, studentsSnap) {
        if (!studentsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final studentDocs = studentsSnap.data!.docs;
        final approvedStudents = studentDocs
            .where((d) => _isApprovedStudent(d.data()))
            .toList();
        final approvedStudentUids = approvedStudents.map((d) => d.id).toSet();
        final studentNameByUid = <String, String>{
          for (final d in approvedStudents) d.id: _studentName(d.data()),
        };
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ViolationCaseService().streamAllCases(limit: 1000),
          builder: (context, casesSnap) {
            if (!casesSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allCases = casesSnap.data!.docs.where((doc) {
              final studentUid = _safe(doc.data()['studentUid']);
              return studentUid.isNotEmpty &&
                  approvedStudentUids.contains(studentUid);
            }).toList();

            final newReportedCases =
                allCases.where((doc) {
                  final key = _statusKey(doc.data());
                  return key == 'submitted' || key == 'under review';
                }).toList()..sort((a, b) {
                  final ad =
                      _toDate(a.data()['createdAt']) ??
                      _toDate(a.data()['updatedAt']);
                  final bd =
                      _toDate(b.data()['createdAt']) ??
                      _toDate(b.data()['updatedAt']);
                  if (ad == null && bd == null) return 0;
                  if (ad == null) return 1;
                  if (bd == null) return -1;
                  return bd.compareTo(ad);
                });

            final scheduledAppointments =
                allCases.where((doc) {
                  final key = _statusKey(doc.data());
                  if (key != 'action set') return false;
                  return _meetingFlowKey(doc.data()) == 'scheduled';
                }).toList()..sort((a, b) {
                  final ad =
                      _toDate(a.data()['scheduledAt']) ??
                      _toDate(a.data()['updatedAt']) ??
                      _toDate(a.data()['createdAt']);
                  final bd =
                      _toDate(b.data()['scheduledAt']) ??
                      _toDate(b.data()['updatedAt']) ??
                      _toDate(b.data()['createdAt']);
                  if (ad == null && bd == null) return 0;
                  if (ad == null) return 1;
                  if (bd == null) return -1;
                  return ad.compareTo(bd);
                });

            final needsBookingCount = allCases.where((doc) {
              final key = _statusKey(doc.data());
              if (key != 'action set') return false;
              return _meetingFlowKey(doc.data()) == 'needs_booking';
            }).length;

            final unresolvedCount = _countByStatus(allCases, {'unresolved'});
            final resolvedCount = _countByStatus(allCases, {'resolved'});
            Widget buildPanel({
              required String title,
              required int count,
              required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
              required String emptyText,
              required DateTime? Function(Map<String, dynamic>) cardDate,
              VoidCallback? onSeeAll,
            }) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$title ($count)',
                            style: const TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: onSeeAll,
                          child: const Text('See all'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (docs.isEmpty)
                      Container(
                        height: 160,
                        alignment: Alignment.center,
                        child: Text(
                          emptyText,
                          style: const TextStyle(
                            color: hint,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      ...docs.take(5).map((doc) {
                        final d = doc.data();
                        final studentUid = _safe(d['studentUid']);
                        final studentName =
                            studentNameByUid[studentUid] ?? 'Student';
                        final caseId = _safe(d['caseId']).isEmpty
                            ? doc.id
                            : _safe(d['caseId']);
                        final violationCode = _safe(d['caseCode']).isEmpty
                            ? caseId
                            : _safe(d['caseCode']);
                        final violationLabel = _safe(
                          d['violationTypeLabel'] ??
                              d['violationNameSnapshot'] ??
                              d['violationName'] ??
                              d['typeNameSnapshot'],
                        );
                        final displayDate = _fmtCardDate(cardDate(d));
                        final isTapped = _tappedCaseId == caseId;
                        void openCaseDetails() {
                          if (widget.onOpenCase != null) {
                            widget.onOpenCase!(caseId);
                            return;
                          }
                          widget.onOpenViolationReview?.call();
                        }

                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () =>
                              _openCaseWithFlash(caseId, openCaseDetails),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                            decoration: BoxDecoration(
                              color: isTapped
                                  ? primary.withValues(alpha: 0.04)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isTapped
                                    ? primary.withValues(alpha: 0.5)
                                    : Colors.black.withValues(alpha: 0.09),
                                width: isTapped ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              violationCode,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: primary,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 11.2,
                                                letterSpacing: 0.15,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            displayDate,
                                            style: const TextStyle(
                                              color: hint,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        studentName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: textDark,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13.3,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        violationLabel.isEmpty
                                            ? 'Violation'
                                            : violationLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: hint,
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
                      }),
                  ],
                ),
              );
            }

            final newReportedPanel = buildPanel(
              title: 'New Reported',
              count: newReportedCases.length,
              docs: newReportedCases,
              emptyText: 'No newly reported cases.',
              cardDate: (d) =>
                  _toDate(d['createdAt']) ?? _toDate(d['updatedAt']),
              onSeeAll: widget.onOpenViolationReview,
            );

            final scheduledPanel = buildPanel(
              title: 'Scheduled Appointments',
              count: scheduledAppointments.length,
              docs: scheduledAppointments,
              emptyText: 'No scheduled appointments.',
              cardDate: (d) =>
                  _toDate(d['scheduledAt']) ??
                  _toDate(d['updatedAt']) ??
                  _toDate(d['createdAt']),
              onSeeAll:
                  widget.onOpenMeetingSchedule ?? widget.onOpenViolationReview,
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OSA Overview',
                          style: TextStyle(
                            color: primary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Scope: University-wide',
                          style: TextStyle(
                            color: hint,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _kpiCard(
                        'Students',
                        approvedStudentUids.length,
                        Icons.groups_rounded,
                      ),
                      _kpiCard(
                        'New Reported',
                        newReportedCases.length,
                        Icons.inbox_rounded,
                      ),
                      _kpiCard(
                        'Needs Booking',
                        needsBookingCount,
                        Icons.event_available_rounded,
                      ),
                      _kpiCard(
                        'Scheduled',
                        scheduledAppointments.length,
                        Icons.calendar_month_rounded,
                      ),
                      _kpiCard(
                        'Resolved',
                        resolvedCount,
                        Icons.check_circle_rounded,
                      ),
                      _kpiCard(
                        'Unresolved',
                        unresolvedCount,
                        Icons.report_problem_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, c) {
                      if (c.maxWidth >= 1100) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: newReportedPanel),
                            const SizedBox(width: 12),
                            Expanded(child: scheduledPanel),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          newReportedPanel,
                          const SizedBox(height: 12),
                          scheduledPanel,
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _kpiCard(String label, int value, IconData icon) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: hint,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

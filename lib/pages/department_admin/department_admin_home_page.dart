import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DepartmentAdminHomePage extends StatelessWidget {
  final VoidCallback? onOpenUserManagement;
  final VoidCallback? onOpenViolationReview;
  final ValueChanged<String>? onOpenPendingApprovalProfile;
  final ValueChanged<String>? onOpenViolationAlertCase;

  const DepartmentAdminHomePage({
    super.key,
    this.onOpenUserManagement,
    this.onOpenViolationReview,
    this.onOpenPendingApprovalProfile,
    this.onOpenViolationAlertCase,
  });

  static const bg = Colors.white;
  static const primary = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hint = Color(0xFF6D7F62);

  DateTime? _toDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  String _fmtWhen(DateTime? date) {
    if (date == null) return '--';
    final local = date.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hh = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final mm = local.minute.toString().padLeft(2, '0');
    final ap = local.hour >= 12 ? 'PM' : 'AM';
    if (sameDay) return '$hh:$mm $ap';
    return '${m[local.month - 1]} ${local.day}, $hh:$mm $ap';
  }

  String _safe(dynamic v) => (v ?? '').toString().trim();

  String _studentName(Map<String, dynamic> userData) {
    final display = _safe(userData['displayName']);
    if (display.isNotEmpty && display != '--') return display;
    final first = _safe(userData['firstName']);
    final last = _safe(userData['lastName']);
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    final email = _safe(userData['email']);
    if (email.contains('@')) return email.split('@').first;
    return 'Student';
  }

  String _statusLabel(String raw) {
    final s = raw.toLowerCase().trim();
    if (s == 'action set') return 'Monitoring';
    if (s == 'under review') return 'Under Review';
    if (s == 'submitted') return 'Submitted';
    if (s == 'resolved') return 'Resolved';
    return s.isEmpty ? 'Unknown' : s;
  }

  Color _statusColor(String raw) {
    final s = raw.toLowerCase().trim();
    if (s == 'action set') return const Color(0xFF0D47A1);
    if (s == 'submitted' || s == 'under review') return const Color(0xFFF57C00);
    if (s == 'resolved') return const Color(0xFF2E7D32);
    return Colors.grey.shade700;
  }

  int _countByStatus(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Set<String> statuses,
  ) {
    return docs.where((doc) {
      final status = (doc.data()['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return statuses.contains(status);
    }).length;
  }

  String _normalizedStudentVerification(Map<String, dynamic> data) {
    final field = (data['studentVerificationStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (field.isNotEmpty) return field;

    final legacy = (data['status'] ?? '').toString().trim().toLowerCase();
    if (legacy.isNotEmpty) return legacy;
    return 'verified';
  }

  bool _isApprovedStudent(Map<String, dynamic> data) {
    final verification = _normalizedStudentVerification(data);
    return verification == 'verified';
  }

  bool _isPendingStudentApproval(Map<String, dynamic> data) {
    final verification = _normalizedStudentVerification(data);
    return verification == 'pending_approval' ||
        verification == 'pending_verification';
  }

  Map<String, dynamic> _payloadAsMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  bool _isUnreadNotification(Map<String, dynamic> data) {
    return _toDate(data['readAt']) == null;
  }

  bool _isPendingApprovalNotification(Map<String, dynamic> data) {
    final payload = _payloadAsMap(data['payload']);
    final type = _safe(payload['type']).toLowerCase();
    return type == 'student_profile_pending_approval';
  }

  String _pendingApprovalStudentUid(Map<String, dynamic> data) {
    final payload = _payloadAsMap(data['payload']);
    return _safe(payload['studentUid']);
  }

  String _notificationCaseId(Map<String, dynamic> data) {
    final payload = _payloadAsMap(data['payload']);
    final payloadCaseId = _safe(payload['caseId']);
    if (payloadCaseId.isNotEmpty) return payloadCaseId;
    return _safe(data['caseId']);
  }

  bool _looksLikeViolationNotification(Map<String, dynamic> data) {
    final payload = _payloadAsMap(data['payload']);
    final caseId = _safe(payload['caseId']).isNotEmpty
        ? _safe(payload['caseId'])
        : _safe(data['caseId']);
    final caseCode = _safe(payload['caseCode']);
    final event = _safe(payload['event']).toLowerCase();
    final title = _safe(data['title']).toLowerCase();
    final body = _safe(data['body']).toLowerCase();
    return caseId.isNotEmpty ||
        caseCode.isNotEmpty ||
        event.contains('report') ||
        title.contains('violation') ||
        body.contains('violation') ||
        title.contains('case update');
  }

  Future<void> _markPendingApprovalNotificationsRead({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications,
    required String studentUid,
  }) async {
    final uid = studentUid.trim();
    if (uid.isEmpty) return;
    for (final doc in notifications) {
      final data = doc.data();
      if (!_isUnreadNotification(data)) continue;
      if (!_isPendingApprovalNotification(data)) continue;
      if (_pendingApprovalStudentUid(data) != uid) continue;
      try {
        await doc.reference.update({'readAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    }
  }

  Future<void> _markViolationNotificationsRead({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications,
    required String caseId,
  }) async {
    final normalizedCaseId = caseId.trim();
    if (normalizedCaseId.isEmpty) return;
    for (final doc in notifications) {
      final data = doc.data();
      if (!_isUnreadNotification(data)) continue;
      if (!_looksLikeViolationNotification(data)) continue;
      if (_notificationCaseId(data) != normalizedCaseId) continue;
      try {
        await doc.reference.update({'readAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final userData = userSnap.data!.data() ?? <String, dynamic>{};
        final dept = (userData['employeeProfile']?['department'] ?? '')
            .toString()
            .trim();
        if (dept.isEmpty) {
          return const Center(
            child: Text(
              'No department is assigned to your account.',
              style: TextStyle(color: hint, fontWeight: FontWeight.w700),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'student')
              .snapshots(),
          builder: (context, studentsSnap) {
            if (!studentsSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final deptStudents = studentsSnap.data!.docs.where((d) {
              final college = (d.data()['studentProfile']?['collegeId'] ?? '')
                  .toString()
                  .trim();
              return college == dept;
            }).toList();

            final approvedStudentUids = deptStudents
                .where((d) => _isApprovedStudent(d.data()))
                .map((d) => d.id)
                .toSet();
            final approvedStudentNamesByUid = <String, String>{
              for (final d in deptStudents.where(
                (row) => _isApprovedStudent(row.data()),
              ))
                d.id: _studentName(d.data()),
            };

            final pendingApprovalCount = deptStudents
                .where((d) => _isPendingStudentApproval(d.data()))
                .length;
            final pendingApprovalStudents =
                deptStudents
                    .where((d) => _isPendingStudentApproval(d.data()))
                    .toList()
                  ..sort((a, b) {
                    final ad =
                        _toDate(a.data()['updatedAt']) ??
                        _toDate(a.data()['createdAt']);
                    final bd =
                        _toDate(b.data()['updatedAt']) ??
                        _toDate(b.data()['createdAt']);
                    if (ad == null && bd == null) return 0;
                    if (ad == null) return 1;
                    if (bd == null) return -1;
                    return bd.compareTo(ad);
                  });

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('violation_cases')
                  .snapshots(),
              builder: (context, casesSnap) {
                if (!casesSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final cases = casesSnap.data!.docs.where((doc) {
                  final uid = (doc.data()['studentUid'] ?? '')
                      .toString()
                      .trim();
                  return uid.isNotEmpty && approvedStudentUids.contains(uid);
                }).toList();

                final review = _countByStatus(cases, {
                  'submitted',
                  'under review',
                });
                final monitoring = _countByStatus(cases, {'action set'});
                final resolved = _countByStatus(cases, {'resolved'});
                final alertCases =
                    cases.where((doc) {
                      final status = _safe(doc.data()['status']).toLowerCase();
                      return status == 'submitted' ||
                          status == 'under review' ||
                          status == 'action set';
                    }).toList()..sort((a, b) {
                      final ad =
                          _toDate(a.data()['updatedAt']) ??
                          _toDate(a.data()['createdAt']);
                      final bd =
                          _toDate(b.data()['updatedAt']) ??
                          _toDate(b.data()['createdAt']);
                      if (ad == null && bd == null) return 0;
                      if (ad == null) return 1;
                      if (bd == null) return -1;
                      return bd.compareTo(ad);
                    });

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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Department Overview',
                              style: TextStyle(
                                color: primary,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Scope: $dept',
                              style: const TextStyle(
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
                            'Pending Approval',
                            pendingApprovalCount,
                            Icons.verified_user_outlined,
                          ),
                          _kpiCard('For Review', review, Icons.inbox_rounded),
                          _kpiCard(
                            'Monitoring',
                            monitoring,
                            Icons.monitor_heart_rounded,
                          ),
                          _kpiCard(
                            'Resolved',
                            resolved,
                            Icons.check_circle_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(authUser.uid)
                            .collection('notifications')
                            .snapshots(),
                        builder: (context, notificationsSnap) {
                          if (!notificationsSnap.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final notificationDocs = notificationsSnap.data!.docs;
                          final pendingStudentUids = pendingApprovalStudents
                              .map((d) => d.id)
                              .toSet();
                          final activeCaseIds = alertCases.map((d) {
                            final caseId = _safe(d.data()['caseId']);
                            return caseId.isEmpty ? d.id : caseId;
                          }).toSet();
                          final unreadPendingStudentUids = <String>{};
                          final unreadViolationCaseIds = <String>{};
                          for (final n in notificationDocs) {
                            final data = n.data();
                            if (!_isUnreadNotification(data)) continue;
                            if (_isPendingApprovalNotification(data)) {
                              final studentUid = _pendingApprovalStudentUid(
                                data,
                              );
                              if (studentUid.isNotEmpty &&
                                  pendingStudentUids.contains(studentUid)) {
                                unreadPendingStudentUids.add(studentUid);
                              }
                              continue;
                            }
                            if (_looksLikeViolationNotification(data)) {
                              final caseId = _notificationCaseId(data);
                              if (caseId.isNotEmpty &&
                                  activeCaseIds.contains(caseId)) {
                                unreadViolationCaseIds.add(caseId);
                              }
                            }
                          }
                          final pendingUnreadCount =
                              unreadPendingStudentUids.length;
                          final violationUnreadCount =
                              unreadViolationCaseIds.length;
                          return LayoutBuilder(
                            builder: (context, panelConstraints) {
                              final desktopSplit =
                                  panelConstraints.maxWidth >= 1100;
                              final pendingApprovalPanel = Container(
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
                                            'Pending Approval ($pendingUnreadCount)',
                                            style: const TextStyle(
                                              color: primary,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: onOpenUserManagement,
                                          child: const Text('See all'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (pendingApprovalStudents.isEmpty)
                                      Container(
                                        height: 160,
                                        alignment: Alignment.center,
                                        child: const Text(
                                          'No students pending approval.',
                                          style: TextStyle(
                                            color: hint,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      )
                                    else
                                      ...pendingApprovalStudents.take(5).map((
                                        doc,
                                      ) {
                                        final data = doc.data();
                                        final uid = doc.id;
                                        final studentName = _studentName(data);
                                        final studentNo = _safe(
                                          data['studentProfile']?['studentNo'],
                                        );
                                        final photoUrl = _safe(
                                          data['photoUrl'],
                                        );
                                        final when = _fmtWhen(
                                          _toDate(data['updatedAt']) ??
                                              _toDate(data['createdAt']),
                                        );
                                        return Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          padding: const EdgeInsets.fromLTRB(
                                            10,
                                            9,
                                            10,
                                            9,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.black.withValues(
                                                alpha: 0.12,
                                              ),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Container(
                                                    width: 44,
                                                    height: 58,
                                                    decoration: BoxDecoration(
                                                      color: primary.withValues(
                                                        alpha: 0.12,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      image: photoUrl.isEmpty
                                                          ? null
                                                          : DecorationImage(
                                                              image:
                                                                  NetworkImage(
                                                                    photoUrl,
                                                                  ),
                                                              fit: BoxFit.cover,
                                                            ),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: photoUrl.isEmpty
                                                        ? Text(
                                                            studentName
                                                                    .trim()
                                                                    .isEmpty
                                                                ? '?'
                                                                : studentName
                                                                      .trim()[0]
                                                                      .toUpperCase(),
                                                            style:
                                                                const TextStyle(
                                                                  color:
                                                                      primary,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                  fontSize: 14,
                                                                ),
                                                          )
                                                        : null,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          studentName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                color: textDark,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                fontSize: 13.5,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 3,
                                                        ),
                                                        Text(
                                                          studentNo.isEmpty
                                                              ? 'Student No: --'
                                                              : 'Student No: $studentNo',
                                                          style:
                                                              const TextStyle(
                                                                color: hint,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          'Queued: $when',
                                                          style:
                                                              const TextStyle(
                                                                color: hint,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize: 11.5,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  SizedBox(
                                                    height: 36,
                                                    child: OutlinedButton(
                                                      onPressed: () async {
                                                        await _markPendingApprovalNotificationsRead(
                                                          notifications:
                                                              notificationDocs,
                                                          studentUid: uid,
                                                        );
                                                        if (onOpenPendingApprovalProfile !=
                                                            null) {
                                                          onOpenPendingApprovalProfile!(
                                                            uid,
                                                          );
                                                          return;
                                                        }
                                                        onOpenUserManagement
                                                            ?.call();
                                                      },
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor:
                                                            primary,
                                                        side: BorderSide(
                                                          color: primary
                                                              .withValues(
                                                                alpha: 0.35,
                                                              ),
                                                        ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                            ),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        'View',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                  ],
                                ),
                              );

                              final alertsPanel = Container(
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
                                            'Violation Alerts ($violationUnreadCount)',
                                            style: const TextStyle(
                                              color: primary,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: onOpenViolationReview,
                                          child: const Text('See all'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (alertCases.isEmpty)
                                      Container(
                                        height: 160,
                                        alignment: Alignment.center,
                                        child: const Text(
                                          'No active violation alerts.',
                                          style: TextStyle(
                                            color: hint,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      )
                                    else
                                      ...alertCases.take(5).map((doc) {
                                        final d = doc.data();
                                        final studentUid = _safe(
                                          d['studentUid'],
                                        );
                                        final studentName =
                                            approvedStudentNamesByUid[studentUid] ??
                                            'Student';
                                        final caseId =
                                            _safe(d['caseId']).isEmpty
                                            ? doc.id
                                            : _safe(d['caseId']);
                                        final statusRaw = _safe(d['status']);
                                        final when = _fmtWhen(
                                          _toDate(d['updatedAt']) ??
                                              _toDate(d['createdAt']),
                                        );
                                        return Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          padding: const EdgeInsets.fromLTRB(
                                            10,
                                            9,
                                            10,
                                            9,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FBF8),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.black.withValues(
                                                alpha: 0.08,
                                              ),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      caseId,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: textDark,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: _statusColor(
                                                        statusRaw,
                                                      ).withValues(alpha: 0.14),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      _statusLabel(statusRaw),
                                                      style: TextStyle(
                                                        color: _statusColor(
                                                          statusRaw,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                studentName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: hint,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      when,
                                                      style: const TextStyle(
                                                        color: hint,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 11.5,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  SizedBox(
                                                    height: 32,
                                                    child: OutlinedButton(
                                                      onPressed: () async {
                                                        await _markViolationNotificationsRead(
                                                          notifications:
                                                              notificationDocs,
                                                          caseId: caseId,
                                                        );
                                                        if (onOpenViolationAlertCase !=
                                                            null) {
                                                          onOpenViolationAlertCase!(
                                                            caseId,
                                                          );
                                                          return;
                                                        }
                                                        onOpenViolationReview
                                                            ?.call();
                                                      },
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor:
                                                            primary,
                                                        side: BorderSide(
                                                          color: primary
                                                              .withValues(
                                                                alpha: 0.35,
                                                              ),
                                                        ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                            ),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        'View',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                  ],
                                ),
                              );

                              if (desktopSplit) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: pendingApprovalPanel),
                                    const SizedBox(width: 12),
                                    Expanded(child: alertsPanel),
                                  ],
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  pendingApprovalPanel,
                                  const SizedBox(height: 12),
                                  alertsPanel,
                                ],
                              );
                            },
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

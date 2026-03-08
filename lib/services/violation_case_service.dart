import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'academic_settings_service.dart';

class ViolationCaseWorkflow {
  static const statusSubmitted = 'Submitted';
  static const statusUnderReview = 'Under Review';
  static const statusActionSet = 'Action Set';
  static const statusResolved = 'Resolved';
  static const statusUnresolved = 'Unresolved';

  static const stepReview = 'review';
  static const stepMonitoring = 'monitoring';
  static const stepResolved = 'resolved';

  static const actionNoMeeting = 'no_meeting';
  static const actionMeetingRequired = 'meeting_required';
}

class ViolationSetActionType {
  final String code;
  final String label;
  final bool meetingRequired;

  const ViolationSetActionType({
    required this.code,
    required this.label,
    required this.meetingRequired,
  });
}

class ViolationSetActionTypes {
  static const advisoryReminder = 'advisory_reminder';
  static const formalWarning = 'formal_warning';
  static const osaCheckIn = 'osa_check_in';
  static const parentGuardianConference = 'parent_guardian_conference';
  static const osaEndorsement = 'osa_endorsement_disciplinary_call';
  static const immediateActionRequired = 'immediate_action_required';

  static const List<ViolationSetActionType> all = [
    ViolationSetActionType(
      code: advisoryReminder,
      label: 'Advisory / Reminder',
      meetingRequired: false,
    ),
    ViolationSetActionType(
      code: formalWarning,
      label: 'Formal Warning',
      meetingRequired: false,
    ),
    ViolationSetActionType(
      code: osaCheckIn,
      label: 'OSA Check-in (soft meeting)',
      meetingRequired: true,
    ),
    ViolationSetActionType(
      code: parentGuardianConference,
      label: 'Parent/Guardian Conference',
      meetingRequired: true,
    ),
    ViolationSetActionType(
      code: osaEndorsement,
      label: 'OSA Endorsement / Disciplinary Call',
      meetingRequired: true,
    ),
    ViolationSetActionType(
      code: immediateActionRequired,
      label: 'Immediate Action Required',
      meetingRequired: true,
    ),
  ];

  static ViolationSetActionType? resolve(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return null;

    for (final item in all) {
      if (item.code == value) return item;
      if (item.label.toLowerCase() == value) return item;
      if (item.label.toLowerCase().contains(value)) return item;
      if (value.contains(item.label.toLowerCase())) return item;
    }

    // Legacy compatibility
    if (value == ViolationCaseWorkflow.actionMeetingRequired) {
      return all.firstWhere((item) => item.code == immediateActionRequired);
    }
    if (value == ViolationCaseWorkflow.actionNoMeeting) {
      return all.firstWhere((item) => item.code == advisoryReminder);
    }
    if (value.contains('advisory') || value.contains('reminder')) {
      return all.firstWhere((item) => item.code == advisoryReminder);
    }
    if (value.contains('formal warning') || value.contains('written warning')) {
      return all.firstWhere((item) => item.code == formalWarning);
    }
    if (value.contains('guidance') && value.contains('check')) {
      return all.firstWhere((item) => item.code == osaCheckIn);
    }
    if (value.contains('parent') || value.contains('guardian')) {
      return all.firstWhere((item) => item.code == parentGuardianConference);
    }
    if (value.contains('osa') && value.contains('endorsement')) {
      return all.firstWhere((item) => item.code == osaEndorsement);
    }
    if (value.contains('immediate action')) {
      return all.firstWhere((item) => item.code == immediateActionRequired);
    }
    return null;
  }
}

class ViolationSanctionType {
  final String code;
  final String label;

  const ViolationSanctionType({required this.code, required this.label});
}

class ViolationSanctionTypes {
  static const none = 'none';
  static const suspension = 'suspension';

  static const List<ViolationSanctionType> all = [
    ViolationSanctionType(code: none, label: 'None'),
    ViolationSanctionType(code: suspension, label: 'Suspension'),
  ];

  static String? normalizeCode(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return none;
    for (final item in all) {
      if (item.code == value) return item.code;
      if (item.label.toLowerCase() == value) return item.code;
    }
    return null;
  }
}

class ViolationCaseService {
  final _db = FirebaseFirestore.instance;
  final _academicSvc = AcademicSettingsService();

  CollectionReference<Map<String, dynamic>> get _cases =>
      _db.collection('violation_cases');

  Future<String> submitCase({
    required String studentUid,
    required String studentNo,
    required String studentName,
    String? gradeSection,
    required DateTime incidentAt,
    required String concern,
    required String categoryId,
    required String categoryNameSnapshot,
    required String typeId,
    required String typeNameSnapshot,
    required String description,
    List<String> evidenceUrls = const [],
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    final caseCode = await _academicSvc.generateCaseCode();

    final reporterDoc = await _db.collection('users').doc(user.uid).get();
    final reporterData = reporterDoc.data() ?? {};
    final reportedByRole = (reporterData['role'] ?? '').toString();
    final displayName = (reporterData['displayName'] ?? '').toString().trim();
    final first = (reporterData['firstName'] ?? '').toString().trim();
    final last = (reporterData['lastName'] ?? '').toString().trim();
    final fallbackName = ('$first $last').trim();
    final reportedByName = displayName.isNotEmpty ? displayName : fallbackName;

    final activeSY = await _academicSvc.getActiveSY();
    final syId = activeSY?['id']?.toString();
    final activeTermId = activeSY?['activeTermId']?.toString();

    final ref = _cases.doc();
    final now = FieldValue.serverTimestamp();
    final normalizedConcern = concern.trim();
    final normalizedCategoryId = categoryId.trim();
    final normalizedCategoryName = categoryNameSnapshot.trim();
    final normalizedTypeId = typeId.trim();
    final normalizedTypeName = typeNameSnapshot.trim();
    final normalizedDescription = description.trim();

    final studentData =
        (await _db.collection('users').doc(studentUid.trim()).get()).data() ??
        {};
    final studentProfile =
        studentData['studentProfile'] as Map<String, dynamic>? ?? {};
    final studentCollegeId = (studentProfile['collegeId'] ?? '')
        .toString()
        .trim();

    await ref.set({
      'caseId': ref.id,
      'caseCode': caseCode,
      'status': ViolationCaseWorkflow.statusUnderReview,
      'workflowStep': ViolationCaseWorkflow.stepReview,
      'workflowAction': null,
      'createdAt': now,
      'updatedAt': now,
      'schoolYearId': syId,
      'termId': activeTermId,
      'reportedByUid': user.uid,
      'reportedByRole': reportedByRole.isEmpty ? null : reportedByRole,
      'reportedByName': reportedByName.isEmpty ? null : reportedByName,
      'studentUid': studentUid.trim(),
      'studentNo': (studentProfile['studentNo'] ?? studentNo).toString().trim(),
      'studentName': studentName.trim(),
      'studentCollegeId': studentCollegeId.isEmpty ? null : studentCollegeId,
      'gradeSection': (gradeSection == null || gradeSection.trim().isEmpty)
          ? null
          : gradeSection.trim(),
      'incidentAt': Timestamp.fromDate(incidentAt),
      'concern': normalizedConcern,
      'categoryId': normalizedCategoryId,
      'categoryNameSnapshot': normalizedCategoryName,
      'typeId': normalizedTypeId,
      'typeNameSnapshot': normalizedTypeName,
      'reportedConcern': normalizedConcern,
      'reportedCategoryId': normalizedCategoryId,
      'reportedCategoryNameSnapshot': normalizedCategoryName,
      'reportedTypeId': normalizedTypeId,
      'reportedTypeNameSnapshot': normalizedTypeName,
      'violationTypeId': normalizedTypeId,
      'violationNameSnapshot': normalizedTypeName,
      'reportedConcernType': normalizedConcern,
      'description': normalizedDescription,
      'reportedDescription': normalizedDescription,
      'evidenceUrls': evidenceUrls,
      'wasCorrectedByOsa': false,
      'correction': {
        'wasCorrected': false,
        'count': 0,
        'latestByUid': null,
        'latestAt': null,
        'latestReason': null,
      },
      'finalSeverity': null,
      'actionType': null,
      'actionTypeCode': null,
      'actionNotes': null,
      'actionSelected': null,
      'actionReason': null,
      'sanctionType': null,
      'sanctionTypeCode': null,
      'meetingRequired': false,
      'meetingStatus': null,
      'meetingWindow': null,
      'meetingDueBy': null,
      'scheduledAt': null,
      'meetingLocation': null,
      'officialRemarks': null,
      'internalNotes': null,
      'resolvedAt': null,
      'resolvedByUid': null,
    });

    if (_shouldNotifyOnProfessorSubmission(reportedByRole)) {
      final payload = <String, dynamic>{
        'event': 'report_submitted',
        'caseId': ref.id,
        'caseCode': caseCode,
        'status': ViolationCaseWorkflow.statusUnderReview,
        'workflowStep': ViolationCaseWorkflow.stepReview,
        'studentUid': studentUid.trim(),
        'studentName': studentName.trim(),
        'studentCollegeId': studentCollegeId.isEmpty ? null : studentCollegeId,
      };

      await _notifyStudent(
        caseId: ref.id,
        studentUid: studentUid.trim(),
        title: 'Violation Report Submitted',
        body:
            'A professor submitted a violation report for your account. It is now under OSA review.',
        payload: payload,
      );

      final deanUids = await _findDepartmentDeanUids(
        departmentCode: studentCollegeId,
      );
      for (final deanUid in deanUids) {
        if (deanUid == user.uid) continue;
        await _notifyUser(
          caseId: ref.id,
          uid: deanUid,
          title: 'New Department Violation Report',
          body:
              'A new violation report for $studentName ($caseCode) was submitted and is under OSA review.',
          payload: payload,
        );
      }
    }

    return ref.id;
  }

  Future<void> markUnderReview(String caseId) async {
    final caseDoc = await _cases.doc(caseId).get();
    final caseData = caseDoc.data() ?? {};
    final studentUid = (caseData['studentUid'] ?? '').toString().trim();

    await _cases.doc(caseId).update({
      'status': ViolationCaseWorkflow.statusUnderReview,
      'workflowStep': ViolationCaseWorkflow.stepReview,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid,
      title: 'Case Under Review',
      body: 'Your violation report is now under OSA review.',
      payload: const {'status': ViolationCaseWorkflow.statusUnderReview},
    );
  }

  Future<void> correctReportedViolation({
    required String caseId,
    required String concern,
    required String categoryId,
    required String categoryNameSnapshot,
    required String typeId,
    required String typeNameSnapshot,
    String? correctionReason,
    DateTime? expectedUpdatedAt,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    final caseRef = _cases.doc(caseId);
    final caseDoc = await caseRef.get();
    if (!caseDoc.exists) throw Exception('Case not found');
    final data = caseDoc.data() ?? {};

    final previous = <String, dynamic>{
      'concern': (data['concern'] ?? '').toString().trim(),
      'categoryId': (data['categoryId'] ?? '').toString().trim(),
      'categoryNameSnapshot': (data['categoryNameSnapshot'] ?? '')
          .toString()
          .trim(),
      'typeId': (data['typeId'] ?? '').toString().trim(),
      'typeNameSnapshot': (data['typeNameSnapshot'] ?? '').toString().trim(),
    };

    final normalizedConcern = concern.trim();
    final normalizedCategoryId = categoryId.trim();
    final normalizedCategoryName = categoryNameSnapshot.trim();
    final normalizedTypeId = typeId.trim();
    final normalizedTypeName = typeNameSnapshot.trim();
    final normalizedReason = (correctionReason ?? '').trim();

    await _db.runTransaction((tx) async {
      final txCaseDoc = await tx.get(caseRef);
      if (!txCaseDoc.exists) throw Exception('Case not found');
      final txData = txCaseDoc.data() ?? {};
      if (expectedUpdatedAt != null) {
        final currentUpdatedAt = (txData['updatedAt'] as Timestamp?)?.toDate();
        final sameUpdatedAt =
            currentUpdatedAt != null &&
            currentUpdatedAt.millisecondsSinceEpoch ==
                expectedUpdatedAt.millisecondsSinceEpoch;
        if (!sameUpdatedAt) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'aborted',
            message: 'Case was updated by another user.',
          );
        }
      }

      tx.update(caseRef, {
        'concern': normalizedConcern,
        'categoryId': normalizedCategoryId,
        'categoryNameSnapshot': normalizedCategoryName,
        'typeId': normalizedTypeId,
        'typeNameSnapshot': normalizedTypeName,
        'violationTypeId': normalizedTypeId,
        'violationNameSnapshot': normalizedTypeName,
        'reportedConcernType': normalizedConcern,
        'wasCorrectedByOsa': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'correction.wasCorrected': true,
        'correction.latestByUid': user.uid,
        'correction.latestAt': FieldValue.serverTimestamp(),
        'correction.latestReason': normalizedReason.isEmpty
            ? null
            : normalizedReason,
        'correction.count': FieldValue.increment(1),
      });

      final historyRef = caseRef.collection('correction_history').doc();
      tx.set(historyRef, {
        'caseId': caseId,
        'from': previous,
        'to': {
          'concern': normalizedConcern,
          'categoryId': normalizedCategoryId,
          'categoryNameSnapshot': normalizedCategoryName,
          'typeId': normalizedTypeId,
          'typeNameSnapshot': normalizedTypeName,
        },
        'reason': normalizedReason.isEmpty ? null : normalizedReason,
        'correctedByUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    final reporterUid = (data['reportedByUid'] ?? '').toString().trim();
    final studentUid = (data['studentUid'] ?? '').toString().trim();
    final caseCode = (data['caseCode'] ?? caseId).toString();

    final payload = {
      'event': 'osa_correction',
      'caseId': caseId,
      'caseCode': caseCode,
      'fromType': previous['typeNameSnapshot'],
      'toType': normalizedTypeName,
      'reason': normalizedReason.isEmpty ? null : normalizedReason,
    };

    await _notifyUser(
      caseId: caseId,
      uid: reporterUid,
      title: 'Report corrected by OSA',
      body:
          'OSA corrected $caseCode from ${previous['typeNameSnapshot']} to $normalizedTypeName.',
      payload: payload,
    );

    await _notifyUser(
      caseId: caseId,
      uid: studentUid,
      title: 'Case details updated',
      body: 'OSA updated the violation details for case $caseCode.',
      payload: payload,
    );
  }

  Future<void> setGuidanceAssessment({
    required String caseId,
    required String finalSeverity,
    required String actionType,
    String? actionNotes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    await _cases.doc(caseId).update({
      'finalSeverity': finalSeverity,
      'actionType': actionType,
      'actionNotes': (actionNotes == null || actionNotes.trim().isEmpty)
          ? null
          : actionNotes.trim(),
      'status': ViolationCaseWorkflow.statusActionSet,
      'workflowStep': ViolationCaseWorkflow.stepMonitoring,
      'updatedAt': FieldValue.serverTimestamp(),
      'assessedAt': FieldValue.serverTimestamp(),
      'assessedByUid': user.uid,
    });
  }

  Future<void> applyGuidanceDecision({
    required String caseId,
    required String finalSeverity,
    required String actionType,
    String? actionNotes,
  }) async {
    await setGuidanceDecisionV2(
      caseId: caseId,
      finalSeverity: finalSeverity,
      actionSelected: actionType,
      actionReason: actionNotes,
      meetingStatus: null,
      meetingWindow: null,
      meetingDueBy: null,
      scheduledAt: null,
      meetingLocation: null,
      officialRemarks: null,
      internalNotes: null,
    );
  }

  Future<void> setReviewAction({
    required String caseId,
    required String finalSeverity,
    required bool meetingRequired,
    String? actionReason,
    String? meetingWindow,
    DateTime? meetingDueBy,
    String? officialRemarks,
  }) async {
    await setGuidanceDecisionV2(
      caseId: caseId,
      finalSeverity: finalSeverity,
      actionSelected: meetingRequired
          ? ViolationCaseWorkflow.actionMeetingRequired
          : ViolationCaseWorkflow.actionNoMeeting,
      actionReason: actionReason,
      meetingStatus: meetingRequired ? 'pending' : null,
      meetingWindow: meetingRequired ? meetingWindow : null,
      meetingDueBy: meetingRequired ? meetingDueBy : null,
      scheduledAt: null,
      meetingLocation: null,
      officialRemarks: officialRemarks,
      internalNotes: null,
    );
  }

  Future<void> setGuidanceDecisionV2({
    required String caseId,
    String? finalSeverity,
    required String actionSelected,
    String? actionTypeCode,
    bool? meetingRequiredOverride,
    String? actionReason,
    String? meetingStatus,
    String? meetingWindow,
    DateTime? meetingDueBy,
    DateTime? scheduledAt,
    String? meetingLocation,
    String? officialRemarks,
    String? internalNotes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    final normalizedSeverity = (finalSeverity ?? '').toLowerCase().trim();
    final resolvedActionType = ViolationSetActionTypes.resolve(actionSelected);
    final normalizedAction = (resolvedActionType?.label ?? actionSelected)
        .toLowerCase()
        .trim();
    final normalizedActionCode =
        (actionTypeCode == null || actionTypeCode.trim().isEmpty)
        ? resolvedActionType?.code
        : actionTypeCode.trim().toLowerCase();
    final needsMeeting =
        meetingRequiredOverride ??
        resolvedActionType?.meetingRequired ??
        _meetingRequiredForAction(normalizedAction);
    final normalizedMeetingStatus = needsMeeting
        ? _normalizeMeetingStatusForRequired(meetingStatus)
        : null;
    final bookingDeadlineAt = needsMeeting
        ? _computeBookingDeadline(meetingDueBy: meetingDueBy)
        : null;
    final normalizedMeetingDueBy = needsMeeting
        ? (() {
            if (meetingDueBy == null) return bookingDeadlineAt;
            if (bookingDeadlineAt == null) return meetingDueBy;
            if (meetingDueBy.isBefore(bookingDeadlineAt)) {
              return bookingDeadlineAt;
            }
            return meetingDueBy;
          })()
        : null;
    final now = FieldValue.serverTimestamp();

    final update = <String, dynamic>{
      'finalSeverity': normalizedSeverity.isEmpty ? null : normalizedSeverity,
      'actionSelected': normalizedAction,
      'actionTypeCode': normalizedActionCode,
      'actionReason': (actionReason == null || actionReason.trim().isEmpty)
          ? null
          : actionReason.trim(),
      'meetingRequired': needsMeeting,
      'meetingStatus': needsMeeting ? normalizedMeetingStatus : null,
      'meetingWindow': needsMeeting
          ? (meetingWindow == null || meetingWindow.trim().isEmpty)
                ? null
                : meetingWindow.toLowerCase().trim()
          : null,
      'meetingDueBy': needsMeeting && normalizedMeetingDueBy != null
          ? Timestamp.fromDate(normalizedMeetingDueBy)
          : null,
      'bookingDeadlineAt': needsMeeting && bookingDeadlineAt != null
          ? Timestamp.fromDate(bookingDeadlineAt)
          : null,
      'bookingStatus': needsMeeting
          ? _bookingStatusForMeetingStatus(normalizedMeetingStatus)
          : null,
      'bookingGraceCount': needsMeeting ? 0 : null,
      'bookingGraceExtendedAt': null,
      'scheduledAt': needsMeeting && scheduledAt != null
          ? Timestamp.fromDate(scheduledAt)
          : null,
      'meetingLocation': needsMeeting
          ? (meetingLocation == null || meetingLocation.trim().isEmpty)
                ? null
                : meetingLocation.trim()
          : null,
      'unresolvedAt': null,
      'unresolvedByUid': null,
      'unresolvedReason': null,
      'officialRemarks':
          (officialRemarks == null || officialRemarks.trim().isEmpty)
          ? null
          : officialRemarks.trim(),
      'internalNotes': (internalNotes == null || internalNotes.trim().isEmpty)
          ? null
          : internalNotes.trim(),
      'actionType': normalizedAction,
      'actionNotes': (actionReason == null || actionReason.trim().isEmpty)
          ? null
          : actionReason.trim(),
      'assessedAt': now,
      'assessedByUid': user.uid,
      'updatedAt': now,
    };

    if (normalizedAction == 'warning' || !needsMeeting) {
      update.addAll({
        'status': ViolationCaseWorkflow.statusResolved,
        'workflowStep': ViolationCaseWorkflow.stepResolved,
        'workflowAction': ViolationCaseWorkflow.actionNoMeeting,
        'resolvedAt': now,
        'resolvedByUid': user.uid,
      });
    } else {
      update.addAll({
        'status': ViolationCaseWorkflow.statusActionSet,
        'workflowStep': ViolationCaseWorkflow.stepMonitoring,
        'workflowAction': ViolationCaseWorkflow.actionMeetingRequired,
      });
    }

    final caseDoc = await _cases.doc(caseId).get();
    final caseData = caseDoc.data() ?? {};
    final studentUid = (caseData['studentUid'] ?? '').toString().trim();

    await _cases.doc(caseId).update(update);

    await _enqueueGuidanceNotification(
      caseId: caseId,
      studentUid: studentUid.isEmpty ? null : studentUid,
      payload: {
        'status': update['status'],
        'workflowStep': update['workflowStep'],
        'workflowAction': update['workflowAction'],
        'finalSeverity': normalizedSeverity.isEmpty ? null : normalizedSeverity,
        'actionSelected': normalizedAction,
        'actionTypeCode': normalizedActionCode,
        'officialRemarks': update['officialRemarks'],
        'meetingRequired': needsMeeting,
        'meetingStatus': update['meetingStatus'],
        'meetingWindow': update['meetingWindow'],
        'meetingDueBy': update['meetingDueBy'],
        'bookingDeadlineAt': update['bookingDeadlineAt'],
        'bookingStatus': update['bookingStatus'],
        'scheduledAt': update['scheduledAt'],
        'meetingLocation': update['meetingLocation'],
      },
    );
  }

  String _normalizeMeetingStatusForRequired(String? raw) {
    final normalized = (raw ?? '').toLowerCase().trim();
    if (normalized.isEmpty || normalized == 'pending') {
      return 'pending_student_booking';
    }
    return normalized;
  }

  String _bookingStatusForMeetingStatus(String? meetingStatus) {
    final normalized = (meetingStatus ?? '').toLowerCase().trim();
    if (normalized.contains('scheduled')) return 'booked';
    if (normalized.contains('completed')) return 'completed';
    if (normalized.contains('missed')) return 'missed';
    return 'pending';
  }

  DateTime _computeBookingDeadline({required DateTime? meetingDueBy}) {
    final now = DateTime.now();
    final minimumBookingWindow = now.add(const Duration(days: 3));
    if (meetingDueBy == null) return minimumBookingWindow;
    if (meetingDueBy.isBefore(minimumBookingWindow)) {
      return minimumBookingWindow;
    }
    return meetingDueBy;
  }

  DateTime _meetingDueByFromWindow(String? meetingWindow) {
    final now = DateTime.now();
    final key = (meetingWindow ?? '').toLowerCase().trim();

    DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59);

    switch (key) {
      case 'today':
        return endOfDay(now);
      case '3days':
        return endOfDay(now.add(const Duration(days: 3)));
      case 'week':
        return endOfDay(now.add(const Duration(days: 7)));
      default:
        return endOfDay(now.add(const Duration(days: 1)));
    }
  }

  bool _meetingRequiredForAction(String normalizedAction) {
    final action = normalizedAction.toLowerCase().trim();
    final resolved = ViolationSetActionTypes.resolve(action);
    if (resolved != null) return resolved.meetingRequired;

    if (action == ViolationCaseWorkflow.actionMeetingRequired) return true;
    if (action == ViolationCaseWorkflow.actionNoMeeting) return false;
    if (action.contains('advisory') || action.contains('reminder')) {
      return false;
    }
    if (action.contains('formal warning') ||
        action.contains('written warning')) {
      return false;
    }
    if (action.contains('guidance') && action.contains('check')) return true;
    if (action.contains('parent') || action.contains('guardian')) return true;
    if (action.contains('osa')) return true;
    if (action.contains('immediate action')) return true;
    if (action.contains('monitoring')) return true;
    if (action.contains('follow-up')) return true;
    if (action.contains('home visitation')) return true;
    if (action.contains('behavioral contract')) return true;
    if (action.contains('counseling extension')) return true;
    if (action.contains('resolution pending')) return true;
    if (action == 'meeting' || action == 'osa_call') return true;

    return false;
  }

  Future<void> _notifyUser({
    required String caseId,
    required String? uid,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    if (uid == null || uid.trim().isEmpty) return;

    final normalizedUid = uid.trim();
    final now = FieldValue.serverTimestamp();
    final dataPayload = payload ?? const <String, dynamic>{};

    await _cases.doc(caseId).collection('notification_queue').add({
      'toType': 'uid',
      'toUid': normalizedUid,
      'title': title,
      'body': body,
      'payload': dataPayload,
      'createdAt': now,
      'readAt': null,
    });

    await _db
        .collection('users')
        .doc(normalizedUid)
        .collection('notifications')
        .add({
          'caseId': caseId,
          'title': title,
          'body': body,
          'payload': dataPayload,
          'createdAt': now,
          'readAt': null,
        });
  }

  Future<void> _notifyStudent({
    required String caseId,
    required String? studentUid,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) {
    return _notifyUser(
      caseId: caseId,
      uid: studentUid,
      title: title,
      body: body,
      payload: payload,
    );
  }

  bool _shouldNotifyOnProfessorSubmission(String rawRole) {
    final role = rawRole.toLowerCase().trim();
    return role == 'professor' ||
        role == 'faculty' ||
        role == 'teacher' ||
        role == 'classroom_teacher';
  }

  Future<List<String>> _findDepartmentDeanUids({
    required String departmentCode,
  }) async {
    final code = departmentCode.trim();
    if (code.isEmpty) return const <String>[];

    final results = await Future.wait([
      _db
          .collection('users')
          .where('role', isEqualTo: 'department_admin')
          .get(),
      _db.collection('users').where('role', isEqualTo: 'dean').get(),
    ]);

    final recipients = <String>{};
    for (final snap in results) {
      for (final doc in snap.docs) {
        final data = doc.data();
        final uid = (data['uid'] ?? doc.id).toString().trim();
        if (uid.isEmpty) continue;

        final accountStatus = (data['accountStatus'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (accountStatus == 'inactive') continue;

        final department = (data['employeeProfile']?['department'] ?? '')
            .toString()
            .trim();
        if (department != code) continue;

        recipients.add(uid);
      }
    }

    return recipients.toList(growable: false);
  }

  Future<void> _enqueueGuidanceNotification({
    required String caseId,
    required String? studentUid,
    required Map<String, dynamic> payload,
  }) async {
    final now = FieldValue.serverTimestamp();
    final queue = _cases.doc(caseId).collection('notification_queue');

    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid,
      title: 'OSA Decision Updated',
      body: 'Your violation case has an updated OSA decision.',
      payload: payload,
    );

    await queue.add({
      'toType': 'role',
      'toRole': 'dean',
      'title': 'Violation Case Update',
      'body': 'A violation case under your department has been updated.',
      'payload': payload,
      'createdAt': now,
      'readAt': null,
    });
  }

  Future<void> markResolved({
    required String caseId,
    String? resolutionNotes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');
    final caseDoc = await _cases.doc(caseId).get();
    final caseData = caseDoc.data() ?? {};
    final studentUid = (caseData['studentUid'] ?? '').toString().trim();

    await _cases.doc(caseId).update({
      'status': ViolationCaseWorkflow.statusResolved,
      'workflowStep': ViolationCaseWorkflow.stepResolved,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedByUid': user.uid,
      'resolutionNotes':
          (resolutionNotes == null || resolutionNotes.trim().isEmpty)
          ? null
          : resolutionNotes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid,
      title: 'Case Resolved',
      body: 'Your violation case has been marked as resolved.',
      payload: const {'status': ViolationCaseWorkflow.statusResolved},
    );
  }

  Future<void> completeMeeting({
    required String caseId,
    required String meetingNotes,
    required String finalSeverity,
    String sanctionType = 'none',
    String? facultyNote,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');
    final caseDoc = await _cases.doc(caseId).get();
    final caseData = caseDoc.data() ?? {};
    final studentUid = (caseData['studentUid'] ?? '').toString().trim();
    final reporterUid = (caseData['reportedByUid'] ?? '').toString().trim();
    final normalizedSanctionTypeRaw = sanctionType.trim().toLowerCase();
    final normalizedSanctionType = normalizedSanctionTypeRaw.isEmpty
        ? ViolationSanctionTypes.none
        : normalizedSanctionTypeRaw;
    final normalizedFacultyNote = (facultyNote ?? '').trim();
    final severityRaw = finalSeverity.trim().toLowerCase();
    if (severityRaw.isEmpty ||
        !(severityRaw == 'minor' ||
            severityRaw == 'moderate' ||
            severityRaw == 'major')) {
      throw Exception('Please select a valid severity level.');
    }
    final normalizedSeverity =
        severityRaw[0].toUpperCase() + severityRaw.substring(1);

    await _cases.doc(caseId).update({
      'status': ViolationCaseWorkflow.statusResolved,
      'workflowStep': ViolationCaseWorkflow.stepResolved,
      'workflowAction': ViolationCaseWorkflow.actionMeetingRequired,
      'finalSeverity': normalizedSeverity,
      'meetingStatus': 'completed',
      'bookingStatus': 'completed',
      'meetingCompletedAt': FieldValue.serverTimestamp(),
      'meetingNotes': meetingNotes.trim().isEmpty ? null : meetingNotes.trim(),
      'sanctionType': normalizedSanctionType,
      'sanctionTypeCode': normalizedSanctionType,
      'sanctionGiven': null,
      'meetingFacultyNote': normalizedFacultyNote.isEmpty
          ? null
          : normalizedFacultyNote,
      'meetingInternalNote': null,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedByUid': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'meetingCompletedByUid': user.uid,
    });

    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid,
      title: 'Meeting Completed',
      body: 'OSA has completed your meeting and resolved the case.',
      payload: {
        'status': ViolationCaseWorkflow.statusResolved,
        'workflowStep': ViolationCaseWorkflow.stepResolved,
        'meetingStatus': 'completed',
        'finalSeverity': normalizedSeverity,
        'sanctionType': normalizedSanctionType,
        'sanctionTypeCode': normalizedSanctionType,
      },
    );

    await _notifyUser(
      caseId: caseId,
      uid: reporterUid,
      title: 'Case Meeting Outcome',
      body: normalizedFacultyNote.isEmpty
          ? 'OSA completed the meeting and resolved this case.'
          : normalizedFacultyNote,
      payload: {
        'status': ViolationCaseWorkflow.statusResolved,
        'meetingStatus': 'completed',
        'finalSeverity': normalizedSeverity,
        'sanctionType': normalizedSanctionType,
        'sanctionTypeCode': normalizedSanctionType,
        'facultyNote': normalizedFacultyNote.isEmpty
            ? null
            : normalizedFacultyNote,
      },
    );
  }

  Future<void> rescheduleMissedMeeting({
    required String caseId,
    String? reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    final caseRef = _cases.doc(caseId);
    final caseDoc = await caseRef.get();
    if (!caseDoc.exists) throw Exception('Case not found');

    final caseData = caseDoc.data() ?? {};
    final studentUid = (caseData['studentUid'] ?? '').toString().trim();
    final meetingRequired = caseData['meetingRequired'] == true;
    if (!meetingRequired) {
      throw Exception('Meeting is not required for this case.');
    }

    final previousMeetingStatus = (caseData['meetingStatus'] ?? '')
        .toString()
        .trim();
    final previousBookingStatus = (caseData['bookingStatus'] ?? '')
        .toString()
        .trim();
    final wasMissed =
        previousMeetingStatus.toLowerCase().contains('missed') ||
        previousBookingStatus.toLowerCase().contains('missed');
    if (!wasMissed) {
      throw Exception('Only missed meetings can be rescheduled.');
    }

    final meetingWindow = (caseData['meetingWindow'] ?? '').toString().trim();
    final nextDueBy = _meetingDueByFromWindow(meetingWindow);
    final nextBookingDeadline = _computeBookingDeadline(
      meetingDueBy: nextDueBy,
    );

    final historyEntry = <String, dynamic>{
      'event': 'rescheduled_after_missed',
      'recordedAt': Timestamp.now(),
      'recordedByUid': user.uid,
      'previousMeetingStatus': previousMeetingStatus,
      'previousBookingStatus': previousBookingStatus,
      'previousScheduledAt': caseData['scheduledAt'],
      'previousBookingSlotId': caseData['bookingSlotId'],
      'previousMeetingDueBy': caseData['meetingDueBy'],
      'previousBookingDeadlineAt': caseData['bookingDeadlineAt'],
      'reason': (reason ?? '').trim().isEmpty
          ? 'Rescheduled by OSA'
          : reason!.trim(),
    };

    await caseRef.update({
      'status': ViolationCaseWorkflow.statusActionSet,
      'workflowStep': ViolationCaseWorkflow.stepMonitoring,
      'workflowAction': ViolationCaseWorkflow.actionMeetingRequired,
      'meetingRequired': true,
      'meetingStatus': 'pending_student_booking',
      'bookingStatus': 'pending',
      'bookingGraceCount': 0,
      'bookingGraceExtendedAt': null,
      'meetingDueBy': Timestamp.fromDate(nextDueBy),
      'bookingDeadlineAt': Timestamp.fromDate(nextBookingDeadline),
      'scheduledAt': null,
      'bookingSlotId': null,
      'bookingBookedAt': null,
      'unresolvedAt': null,
      'unresolvedByUid': null,
      'unresolvedReason': null,
      'meetingRescheduledAt': FieldValue.serverTimestamp(),
      'meetingRescheduledByUid': user.uid,
      'meetingHistory': FieldValue.arrayUnion([historyEntry]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid,
      title: 'Meeting Rescheduled',
      body: 'OSA reopened your meeting booking window. Please book again.',
      payload: {
        'meetingStatus': 'pending_student_booking',
        'rescheduled': true,
      },
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamAllCases() {
    return _cases.orderBy('createdAt', descending: true).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamSubmittedOnly() {
    return _cases
        .where('status', isEqualTo: ViolationCaseWorkflow.statusUnderReview)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}

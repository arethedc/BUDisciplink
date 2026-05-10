import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'academic_settings_service.dart';
import 'violation_types_service.dart';

class ViolationCaseWorkflow {
  static const statusSubmitted = 'Submitted';
  static const statusUnderReview = 'Under Review';
  static const statusActionSet = 'Action Set';
  static const statusResolved = 'Resolved';
  static const statusUnresolved = 'Unresolved';
  static const statusCancelled = 'Cancelled';

  static const stepReview = 'review';
  static const stepMonitoring = 'monitoring';
  static const stepResolved = 'resolved';
  static const stepCancelled = 'cancelled';

  static const actionNoMeeting = 'no_meeting';
  static const actionMeetingRequired = 'meeting_required';
}

class ViolationSetActionType {
  final String code;
  final String label;
  final bool meetingRequired;
  final int bookingWindowDays;
  final int graceWindowDays;

  const ViolationSetActionType({
    required this.code,
    required this.label,
    required this.meetingRequired,
    this.bookingWindowDays = 3,
    this.graceWindowDays = 2,
  });
}

class ViolationSetActionTypes {
  static const advisoryReminder = 'advisory_reminder';
  static const formalWarning = 'formal_warning';
  static const osaCheckIn = 'osa_check_in';
  static const parentGuardianConference = 'parent_guardian_conference';
  static const osaEndorsement = 'osa_endorsement_disciplinary_call';
  static const immediateActionRequired = 'immediate_action_required';
  static const int defaultBookingWindowDays = 3;
  static const int immediateBookingWindowDays = 2;
  static const int bookingGraceExtensionDays = 2;

  static ViolationSetActionType? resolve(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == advisoryReminder) {
      return const ViolationSetActionType(
        code: advisoryReminder,
        label: 'Advisory / Reminder',
        meetingRequired: false,
      );
    }
    if (value == 'advisory / reminder') {
      return const ViolationSetActionType(
        code: advisoryReminder,
        label: 'Advisory / Reminder',
        meetingRequired: false,
      );
    }
    if (value == formalWarning) {
      return const ViolationSetActionType(
        code: formalWarning,
        label: 'Formal Warning',
        meetingRequired: false,
      );
    }
    if (value == 'formal warning') {
      return const ViolationSetActionType(
        code: formalWarning,
        label: 'Formal Warning',
        meetingRequired: false,
      );
    }
    if (value == osaCheckIn) {
      return const ViolationSetActionType(
        code: osaCheckIn,
        label: 'OSA Check-in (soft meeting)',
        meetingRequired: true,
      );
    }
    if (value == 'osa check-in (soft meeting)') {
      return const ViolationSetActionType(
        code: osaCheckIn,
        label: 'OSA Check-in (soft meeting)',
        meetingRequired: true,
      );
    }
    if (value == parentGuardianConference) {
      return const ViolationSetActionType(
        code: parentGuardianConference,
        label: 'Parent/Guardian Conference',
        meetingRequired: true,
      );
    }
    if (value == 'parent/guardian conference') {
      return const ViolationSetActionType(
        code: parentGuardianConference,
        label: 'Parent/Guardian Conference',
        meetingRequired: true,
      );
    }
    if (value == osaEndorsement) {
      return const ViolationSetActionType(
        code: osaEndorsement,
        label: 'OSA Endorsement / Disciplinary Call',
        meetingRequired: true,
      );
    }
    if (value == 'osa endorsement / disciplinary call') {
      return const ViolationSetActionType(
        code: osaEndorsement,
        label: 'OSA Endorsement / Disciplinary Call',
        meetingRequired: true,
      );
    }
    if (value == immediateActionRequired) {
      return const ViolationSetActionType(
        code: immediateActionRequired,
        label: 'Immediate Action Required',
        meetingRequired: true,
        bookingWindowDays: immediateBookingWindowDays,
        graceWindowDays: 0,
      );
    }
    if (value == 'immediate action required') {
      return const ViolationSetActionType(
        code: immediateActionRequired,
        label: 'Immediate Action Required',
        meetingRequired: true,
        bookingWindowDays: immediateBookingWindowDays,
        graceWindowDays: 0,
      );
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
  static const int defaultCaseStreamLimit = 600;

  final _db = FirebaseFirestore.instance;
  final _academicSvc = AcademicSettingsService();
  final _typesSvc = ViolationTypesService();

  CollectionReference<Map<String, dynamic>> get _cases =>
      _db.collection('violation_cases');

  Future<ViolationSetActionType?> _resolveConfiguredActionType({
    String? actionTypeCode,
    String? actionSelected,
  }) async {
    final rows = await _typesSvc.fetchActiveActionTypes();
    final normalizedCode = (actionTypeCode ?? '').trim().toLowerCase();
    final normalizedLabel = (actionSelected ?? '').trim().toLowerCase();
    for (final row in rows) {
      final code = (row['id'] ?? '').toString().trim().toLowerCase();
      final label = (row['label'] ?? '').toString().trim();
      final labelLower = label.toLowerCase();
      if (code.isEmpty || label.isEmpty) continue;
      if (normalizedCode.isNotEmpty && normalizedCode == code) {
        final meetingRequired = row['meetingRequired'] == true;
        return ViolationSetActionType(
          code: code,
          label: label,
          meetingRequired: meetingRequired,
          bookingWindowDays: _normalizeBookingWindowDays(
            row['bookingWindowDays'],
            fallback: _fallbackBookingWindowDays(code),
          ),
          graceWindowDays: _normalizeGraceWindowDays(
            row['graceWindowDays'],
            fallback: _fallbackGraceWindowDays(code),
            meetingRequired: meetingRequired,
          ),
        );
      }
      if (normalizedLabel.isNotEmpty && normalizedLabel == labelLower) {
        final meetingRequired = row['meetingRequired'] == true;
        return ViolationSetActionType(
          code: code,
          label: label,
          meetingRequired: meetingRequired,
          bookingWindowDays: _normalizeBookingWindowDays(
            row['bookingWindowDays'],
            fallback: _fallbackBookingWindowDays(code),
          ),
          graceWindowDays: _normalizeGraceWindowDays(
            row['graceWindowDays'],
            fallback: _fallbackGraceWindowDays(code),
            meetingRequired: meetingRequired,
          ),
        );
      }
    }
    return null;
  }

  int _fallbackBookingWindowDays(String? actionTypeCode) {
    final normalizedCode = (actionTypeCode ?? '').trim().toLowerCase();
    if (normalizedCode == ViolationSetActionTypes.immediateActionRequired) {
      return ViolationSetActionTypes.immediateBookingWindowDays;
    }
    return ViolationSetActionTypes.defaultBookingWindowDays;
  }

  int _fallbackGraceWindowDays(String? actionTypeCode) {
    final normalizedCode = (actionTypeCode ?? '').trim().toLowerCase();
    if (normalizedCode == ViolationSetActionTypes.immediateActionRequired) {
      return 0;
    }
    return ViolationSetActionTypes.bookingGraceExtensionDays;
  }

  int _normalizeBookingWindowDays(dynamic raw, {required int fallback}) {
    final parsed = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    if (parsed == null || parsed < 1) return fallback;
    return parsed;
  }

  int _normalizeGraceWindowDays(
    dynamic raw, {
    required int fallback,
    required bool meetingRequired,
  }) {
    if (!meetingRequired) return 0;
    final parsed = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    if (parsed == null || parsed < 0) return fallback;
    return parsed;
  }

  DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _resolveTermSlot(String termDocId, Map<String, dynamic> data) {
    final id = termDocId.toLowerCase().trim();
    if (id == 'term1' || id == '1' || id.contains('1st')) return 'term1';
    if (id == 'term2' || id == '2' || id.contains('2nd')) return 'term2';
    if (id == 'term3' || id == '3' || id.contains('3rd')) return 'term3';

    final order = data['order'];
    if (order == 1 || order == '1') return 'term1';
    if (order == 2 || order == '2') return 'term2';
    if (order == 3 || order == '3') return 'term3';

    final name = (data['name'] ?? '').toString().toLowerCase();
    if (name.contains('1st') || name.contains('first')) return 'term1';
    if (name.contains('2nd') || name.contains('second')) return 'term2';
    if (name.contains('3rd') ||
        name.contains('third') ||
        name.contains('short')) {
      return 'term3';
    }
    return '';
  }

  Future<String?> _resolveTermIdForIncidentDate({
    required String schoolYearId,
    required DateTime incidentAt,
    String? fallbackTermId,
  }) async {
    final normalizedFallback = (fallbackTermId ?? '').trim();
    final termsSnap = await _db
        .collection('academic_years')
        .doc(schoolYearId)
        .collection('terms')
        .get();

    final incidentDay = _dayOnly(incidentAt);
    final ranges = <_IncidentTermRange>[];
    for (final doc in termsSnap.docs) {
      final data = doc.data();
      final termId = _resolveTermSlot(doc.id, data);
      if (termId.isEmpty) continue;
      final startTs = data['startAt'] as Timestamp?;
      final endTs = data['endAt'] as Timestamp?;
      if (startTs == null || endTs == null) continue;
      final start = _dayOnly(startTs.toDate());
      final end = _dayOnly(endTs.toDate());
      if (end.isBefore(start)) continue;
      ranges.add(_IncidentTermRange(termId: termId, start: start, end: end));
    }

    for (final range in ranges) {
      final inRange =
          (incidentDay.isAtSameMomentAs(range.start) ||
              incidentDay.isAfter(range.start)) &&
          (incidentDay.isAtSameMomentAs(range.end) ||
              incidentDay.isBefore(range.end));
      if (inRange) return range.termId;
    }

    // If incident date is outside all term ranges, use the last active term.
    if (normalizedFallback.isNotEmpty) return normalizedFallback;

    if (ranges.isEmpty) return null;
    ranges.sort((a, b) => a.end.compareTo(b.end));
    return ranges.last.termId;
  }

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
    final syId = activeSY?['id']?.toString().trim();
    var activeTermId = activeSY?['activeTermId']?.toString().trim();
    if (syId != null && syId.isNotEmpty) {
      try {
        activeTermId = await _academicSvc.syncActiveTermByDate(syId);
      } catch (_) {
        // Keep existing fallback if sync fails.
      }
    }
    final incidentTermId =
        (syId == null || syId.isEmpty)
        ? activeTermId
        : await _resolveTermIdForIncidentDate(
            schoolYearId: syId,
            incidentAt: incidentAt,
            fallbackTermId: activeTermId,
          );

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
    final normalizedStudentNo = (studentProfile['studentNo'] ?? studentNo)
        .toString()
        .trim();
    final studentCollegeId = (studentProfile['collegeId'] ?? '')
        .toString()
        .trim();
    final studentProgramId =
        (studentProfile['programId'] ?? studentData['programId'] ?? '')
            .toString()
            .trim();

    await ref.set({
      'caseCode': caseCode,
      'status': ViolationCaseWorkflow.statusUnderReview,
      'workflowStep': ViolationCaseWorkflow.stepReview,
      'workflowAction': null,
      'createdAt': now,
      'updatedAt': now,
      'schoolYearId': syId,
      'termId': incidentTermId,
      'reportedByUid': user.uid,
      'reportedByRole': reportedByRole.isEmpty ? null : reportedByRole,
      'reportedByName': reportedByName.isEmpty ? null : reportedByName,
      'studentUid': studentUid.trim(),
      'studentNo': normalizedStudentNo,
      'studentName': studentName.trim(),
      'studentCollegeId': studentCollegeId.isEmpty ? null : studentCollegeId,
      'studentProgramId': studentProgramId.isEmpty ? null : studentProgramId,
      'gradeSection': (gradeSection == null || gradeSection.trim().isEmpty)
          ? null
          : gradeSection.trim(),
      'incidentAt': Timestamp.fromDate(incidentAt),
      'concern': normalizedConcern,
      'categoryId': normalizedCategoryId,
      'categoryNameSnapshot': normalizedCategoryName,
      'typeId': normalizedTypeId,
      'typeNameSnapshot': normalizedTypeName,
      'description': normalizedDescription,
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

    if (_shouldNotifyOnStaffSubmission(reportedByRole)) {
      final studentIdLabel = normalizedStudentNo.isEmpty
          ? caseCode
          : normalizedStudentNo;
      final studentLabel = '$studentName ($studentIdLabel)';

      final payload = <String, dynamic>{
        'type': 'violation_report_submitted',
        'event': 'report_submitted',
        'module': 'violation',
        'caseId': ref.id,
        'caseCode': caseCode,
        'status': ViolationCaseWorkflow.statusUnderReview,
        'workflowStep': ViolationCaseWorkflow.stepReview,
        'studentUid': studentUid.trim(),
        'studentName': studentName.trim(),
        'studentCollegeId': studentCollegeId.isEmpty ? null : studentCollegeId,
        'reportedByName': reportedByName.isEmpty ? null : reportedByName,
        'reportedByRole': reportedByRole.isEmpty ? null : reportedByRole,
      };

      await _notifyCaseStakeholders(
        caseId: ref.id,
        caseData: {
          'studentUid': studentUid.trim(),
          'reportedByUid': user.uid,
          'studentCollegeId': studentCollegeId,
        },
        title: 'Violation Report Submitted',
        studentBody:
            'A new violation report for $studentLabel is under OSA review.',
        reporterBody:
            'Your violation report for $studentLabel was submitted for OSA review.',
        departmentBody: 'A new violation report for $studentLabel.',
        payload: payload,
        actorUid: user.uid,
      );

      final osaUids = await _findOsaAdminUids();
      for (final osaUid in osaUids) {
        if (osaUid == user.uid) continue;
        await _notifyUser(
          caseId: ref.id,
          uid: osaUid,
          title: 'New Violation Report',
          body: 'A new violation report for $studentLabel.',
          payload: payload,
        );
      }
    }

    await _appendCaseActivity(
      caseId: ref.id,
      event: 'report_submitted',
      title: 'Violation report submitted',
      description:
          'A new violation report was submitted and queued for OSA review.',
      actorUid: user.uid,
      actorRole: reportedByRole.isEmpty ? 'user' : reportedByRole,
      meta: {
        'caseCode': caseCode,
        'status': ViolationCaseWorkflow.statusUnderReview,
        'studentUid': studentUid.trim(),
      },
    );

    return ref.id;
  }

  Future<void> markUnderReview(String caseId) async {
    final caseDoc = await _cases.doc(caseId).get();
    final caseData = caseDoc.data() ?? {};
    final caseCode = _safe(caseData['caseCode']).isNotEmpty
        ? _safe(caseData['caseCode'])
        : caseId;

    await _cases.doc(caseId).update({
      'status': ViolationCaseWorkflow.statusUnderReview,
      'workflowStep': ViolationCaseWorkflow.stepReview,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _notifyCaseStakeholders(
      caseId: caseId,
      caseData: caseData,
      title: 'Case Under Review',
      studentBody: 'Your violation case $caseCode is now under OSA review.',
      reporterBody: 'Violation case $caseCode is now under OSA review by OSA.',
      departmentBody:
          'Violation case $caseCode is now under OSA review by OSA.',
      payload: const {
        'status': ViolationCaseWorkflow.statusUnderReview,
        'workflowStep': ViolationCaseWorkflow.stepReview,
      },
      actorUid: FirebaseAuth.instance.currentUser?.uid,
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

    final caseCode = (data['caseCode'] ?? caseId).toString();

    final payload = {
      'event': 'osa_correction',
      'caseId': caseId,
      'caseCode': caseCode,
      'fromType': previous['typeNameSnapshot'],
      'toType': normalizedTypeName,
      'reason': normalizedReason.isEmpty ? null : normalizedReason,
    };

    await _notifyCaseStakeholders(
      caseId: caseId,
      caseData: data,
      title: 'Report corrected by OSA',
      studentBody: 'OSA updated the violation details for case $caseCode.',
      reporterBody:
          'OSA corrected $caseCode from ${previous['typeNameSnapshot']} to $normalizedTypeName.',
      departmentBody:
          'OSA corrected details for $caseCode from ${previous['typeNameSnapshot']} to $normalizedTypeName.',
      payload: payload,
      actorUid: user.uid,
    );

    await _appendCaseActivity(
      caseId: caseId,
      event: 'osa_correction',
      title: 'Violation report corrected',
      description:
          'OSA corrected the reported violation details from ${previous['typeNameSnapshot']} to $normalizedTypeName.',
      actorUid: user.uid,
      actorRole: 'osa_admin',
      meta: payload,
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
    String? meetingSchoolYearId,
    String? meetingTermId,
    String? reopenReason,
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
    final resolvedActionType = await _resolveConfiguredActionType(
      actionTypeCode: actionTypeCode,
      actionSelected: actionSelected,
    );
    if (resolvedActionType == null && meetingRequiredOverride == null) {
      throw Exception(
        'Selected action type is not configured. Please update Violation Settings.',
      );
    }
    final normalizedAction = (resolvedActionType?.label ?? actionSelected)
        .toLowerCase()
        .trim();
    final normalizedActionCode =
        (actionTypeCode == null || actionTypeCode.trim().isEmpty)
        ? resolvedActionType?.code
        : actionTypeCode.trim().toLowerCase();
    final needsMeeting =
        meetingRequiredOverride ?? resolvedActionType?.meetingRequired ?? false;
    final bookingWindowDays = needsMeeting
        ? _normalizeBookingWindowDays(
            resolvedActionType?.bookingWindowDays,
            fallback: _fallbackBookingWindowDays(normalizedActionCode),
          )
        : 0;
    final graceWindowDays = needsMeeting
        ? _normalizeGraceWindowDays(
            resolvedActionType?.graceWindowDays,
            fallback: _fallbackGraceWindowDays(normalizedActionCode),
            meetingRequired: true,
          )
        : 0;
    final normalizedMeetingStatus = needsMeeting
        ? _normalizeMeetingStatusForRequired(meetingStatus)
        : null;
    final bookingDeadlineAt = needsMeeting
        ? _computeBookingDeadline(
            meetingDueBy: meetingDueBy,
            bookingWindowDays: bookingWindowDays,
          )
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
    String? resolvedMeetingSchoolYearId;
    String? resolvedMeetingTermId;
    if (needsMeeting) {
      final providedSchoolYearId = (meetingSchoolYearId ?? '').trim();
      final providedTermId = (meetingTermId ?? '').trim();
      if (providedSchoolYearId.isNotEmpty && providedTermId.isNotEmpty) {
        resolvedMeetingSchoolYearId = providedSchoolYearId;
        resolvedMeetingTermId = providedTermId;
      } else {
        final activeSY = await _academicSvc.getActiveSY();
        final activeSchoolYearId = (activeSY?['id'] ?? '').toString().trim();
        final activeTermId = (activeSY?['activeTermId'] ?? '')
            .toString()
            .trim();
        if (activeSchoolYearId.isNotEmpty && activeTermId.isNotEmpty) {
          resolvedMeetingSchoolYearId = activeSchoolYearId;
          resolvedMeetingTermId = activeTermId;
        }
      }
    }
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
          ? ((meetingWindow == null || meetingWindow.trim().isEmpty)
                ? '${bookingWindowDays}days'
                : meetingWindow.toLowerCase().trim())
          : null,
      'bookingWindowDays': needsMeeting ? bookingWindowDays : null,
      'bookingGraceDays': needsMeeting ? graceWindowDays : null,
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
    if (needsMeeting &&
        resolvedMeetingSchoolYearId != null &&
        resolvedMeetingTermId != null) {
      update['schoolYearId'] = resolvedMeetingSchoolYearId;
      update['termId'] = resolvedMeetingTermId;
    }

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
    final caseCode = _safe(caseData['caseCode']).isEmpty
        ? caseId
        : _safe(caseData['caseCode']);
    final previousStatus = _safe(caseData['status']).toLowerCase();
    final wasCancelled =
        previousStatus == ViolationCaseWorkflow.statusCancelled.toLowerCase();
    final normalizedReopenReason = (reopenReason ?? '').trim();
    if (wasCancelled) {
      update.addAll({
        'reopenedAt': now,
        'reopenedByUid': user.uid,
        'reopenReason': normalizedReopenReason.isEmpty
            ? null
            : normalizedReopenReason,
      });
    }

    await _cases.doc(caseId).update(update);

    final updatedStatus = (update['status'] ?? '').toString();
    final resolvedActionLabel = resolvedActionType?.label.isNotEmpty == true
        ? resolvedActionType!.label
        : _toTitle(actionSelected);
    final resolvedSeverity = normalizedSeverity.isEmpty
        ? _safe(caseData['finalSeverity'])
        : normalizedSeverity;
    final resolvedSeverityLabel = _toTitle(resolvedSeverity);
    final notificationPayload = <String, dynamic>{
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
      'bookingWindowDays': update['bookingWindowDays'],
      'bookingGraceDays': update['bookingGraceDays'],
      'meetingDueBy': update['meetingDueBy'],
      'bookingDeadlineAt': update['bookingDeadlineAt'],
      'bookingStatus': update['bookingStatus'],
      'scheduledAt': update['scheduledAt'],
      'meetingLocation': update['meetingLocation'],
      'reopenedFromCancelled': wasCancelled,
      'reopenReason': normalizedReopenReason.isEmpty
          ? null
          : normalizedReopenReason,
    };
    final actionLabelForMessage = resolvedActionLabel.isEmpty
        ? 'OSA action'
        : resolvedActionLabel;
    final studentMessage = updatedStatus == ViolationCaseWorkflow.statusResolved
        ? 'OSA resolved case $caseCode. ${actionLabelForMessage == 'OSA action' ? '' : 'Action: $actionLabelForMessage.'}'
              .trim()
        : (needsMeeting
              ? 'OSA set action for case $caseCode. Please book your required meeting.'
              : 'OSA set action for case $caseCode.');
    final stakeholderMessage =
        updatedStatus == ViolationCaseWorkflow.statusResolved
        ? 'OSA resolved case $caseCode.'
        : (needsMeeting
              ? 'OSA set action for case $caseCode and opened meeting booking.'
              : 'OSA set action for case $caseCode.');
    await _notifyCaseStakeholders(
      caseId: caseId,
      caseData: caseData,
      title: updatedStatus == ViolationCaseWorkflow.statusResolved
          ? 'Case Resolved'
          : 'OSA Action Set',
      studentBody: studentMessage,
      reporterBody: stakeholderMessage,
      departmentBody: stakeholderMessage,
      payload: notificationPayload,
      actorUid: user.uid,
    );
    final activityEvent = updatedStatus == ViolationCaseWorkflow.statusResolved
        ? 'case_resolved_without_meeting'
        : 'osa_action_set';
    final activityTitle = updatedStatus == ViolationCaseWorkflow.statusResolved
        ? 'Case resolved'
        : 'OSA action set';
    final activityDescription =
        updatedStatus == ViolationCaseWorkflow.statusResolved
        ? 'OSA resolved the case after assessment.'
              '${resolvedActionLabel.isEmpty ? '' : ' Action: $resolvedActionLabel.'}'
              '${resolvedSeverityLabel.isEmpty ? '' : ' Severity: $resolvedSeverityLabel.'}'
        : 'OSA set action to $resolvedActionLabel.';
    if (wasCancelled) {
      await _appendCaseActivity(
        caseId: caseId,
        event: 'case_reopened',
        title: 'Case reopened',
        description: normalizedReopenReason.isEmpty
            ? 'OSA reopened this cancelled case and applied a new action.'
            : 'OSA reopened this cancelled case. Reason: $normalizedReopenReason',
        actorUid: user.uid,
        actorRole: 'osa_admin',
        meta: {
          'fromStatus': ViolationCaseWorkflow.statusCancelled,
          'toStatus': updatedStatus,
          'reason': normalizedReopenReason.isEmpty
              ? null
              : normalizedReopenReason,
        },
      );
    }
    await _appendCaseActivity(
      caseId: caseId,
      event: activityEvent,
      title: activityTitle,
      description: activityDescription,
      actorUid: user.uid,
      actorRole: 'osa_admin',
      meta: {
        'status': updatedStatus,
        'actionSelected': normalizedAction,
        'actionTypeCode': normalizedActionCode,
        'meetingRequired': needsMeeting,
        'meetingStatus': normalizedMeetingStatus,
        'bookingWindowDays': needsMeeting ? bookingWindowDays : null,
        'bookingGraceDays': needsMeeting ? graceWindowDays : null,
        'finalSeverity': resolvedSeverityLabel.isEmpty
            ? null
            : resolvedSeverityLabel,
        'bookingDeadlineAt': bookingDeadlineAt?.toIso8601String(),
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

  int _initialBookingWindowDays({
    required String? actionTypeCode,
    required String? actionSelected,
  }) {
    final normalizedCode = (actionTypeCode ?? '').trim().toLowerCase();
    if (normalizedCode == ViolationSetActionTypes.immediateActionRequired) {
      return ViolationSetActionTypes.immediateBookingWindowDays;
    }
    final normalizedLabel = (actionSelected ?? '').trim().toLowerCase();
    if (normalizedLabel == ViolationSetActionTypes.immediateActionRequired ||
        normalizedLabel == 'immediate action required') {
      return ViolationSetActionTypes.immediateBookingWindowDays;
    }
    return ViolationSetActionTypes.defaultBookingWindowDays;
  }

  DateTime _computeBookingDeadline({
    required DateTime? meetingDueBy,
    required int bookingWindowDays,
  }) {
    final now = DateTime.now();
    final minimumBookingWindow = now.add(Duration(days: bookingWindowDays));
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

    final dynamicDays = RegExp(r'^(\d+)\s*days?$').firstMatch(key);
    if (dynamicDays != null) {
      final parsed = int.tryParse(dynamicDays.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return endOfDay(now.add(Duration(days: parsed)));
      }
    }

    switch (key) {
      case 'today':
        return endOfDay(now);
      case '2days':
        return endOfDay(now.add(const Duration(days: 2)));
      case '3days':
        return endOfDay(now.add(const Duration(days: 3)));
      case 'week':
        return endOfDay(now.add(const Duration(days: 7)));
      default:
        return endOfDay(now.add(const Duration(days: 1)));
    }
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

  bool _shouldNotifyOnStaffSubmission(String rawRole) {
    final role = rawRole.toLowerCase().trim();
    return role == 'professor' ||
        role == 'guard' ||
        role == 'department_admin' ||
        role == 'osa_admin' ||
        role == 'counseling_admin' ||
        role == 'super_admin';
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

  Future<List<String>> _findOsaAdminUids() async {
    final snap = await _db
        .collection('users')
        .where('role', isEqualTo: 'osa_admin')
        .get();

    final recipients = <String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final uid = (data['uid'] ?? doc.id).toString().trim();
      if (uid.isEmpty) continue;

      final accountStatus = (data['accountStatus'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (accountStatus == 'inactive') continue;

      recipients.add(uid);
    }
    return recipients.toList(growable: false);
  }

  Future<String> _resolveStudentDepartmentCode(
    Map<String, dynamic> caseData,
  ) async {
    final direct = _safe(caseData['studentCollegeId']);
    if (direct.isNotEmpty) return direct;

    final studentUid = _safe(caseData['studentUid']);
    if (studentUid.isEmpty) return '';

    try {
      final studentDoc = await _db.collection('users').doc(studentUid).get();
      final student = studentDoc.data() ?? const <String, dynamic>{};
      return _safe(student['studentProfile']?['collegeId']);
    } catch (_) {
      return '';
    }
  }

  Future<void> _notifyCaseStakeholders({
    required String caseId,
    required Map<String, dynamic> caseData,
    required String title,
    required String studentBody,
    String? reporterBody,
    String? departmentBody,
    Map<String, dynamic>? payload,
    String? actorUid,
    bool notifyStudent = true,
    bool notifyReporter = true,
    bool notifyDepartment = true,
  }) async {
    final normalizedActorUid = actorUid?.trim() ?? '';
    final studentUid = _safe(caseData['studentUid']);
    final reporterUid = _safe(caseData['reportedByUid']);
    final dataPayload = payload ?? const <String, dynamic>{};
    final sent = <String>{};

    Future<void> notifyUid(String uid, String body) async {
      final normalizedUid = uid.trim();
      if (normalizedUid.isEmpty) return;
      if (normalizedActorUid.isNotEmpty &&
          normalizedUid == normalizedActorUid) {
        return;
      }
      if (!sent.add(normalizedUid)) return;
      await _notifyUser(
        caseId: caseId,
        uid: normalizedUid,
        title: title,
        body: body,
        payload: dataPayload,
      );
    }

    if (notifyStudent && studentUid.isNotEmpty) {
      await notifyUid(studentUid, studentBody);
    }

    if (notifyReporter && reporterUid.isNotEmpty) {
      await notifyUid(reporterUid, reporterBody ?? studentBody);
    }

    if (notifyDepartment) {
      final departmentCode = await _resolveStudentDepartmentCode(caseData);
      if (departmentCode.isNotEmpty) {
        final departmentUids = await _findDepartmentDeanUids(
          departmentCode: departmentCode,
        );
        final message = departmentBody ?? reporterBody ?? studentBody;
        for (final uid in departmentUids) {
          await notifyUid(uid, message);
        }
      }
    }
  }

  String _safe(dynamic value) => (value ?? '').toString().trim();

  String _toTitle(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    return text
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

  Future<void> _appendCaseActivity({
    required String caseId,
    required String event,
    required String title,
    required String description,
    String? actorUid,
    String actorRole = 'system',
    Map<String, dynamic>? meta,
  }) async {
    final safeCaseId = caseId.trim();
    final safeEvent = event.trim();
    if (safeCaseId.isEmpty || safeEvent.isEmpty) return;

    await _cases.doc(safeCaseId).collection('activity').add({
      'event': safeEvent,
      'title': title.trim(),
      'description': description.trim(),
      'actorUid': (actorUid ?? '').trim().isEmpty
          ? (FirebaseAuth.instance.currentUser?.uid ?? '')
          : actorUid!.trim(),
      'actorRole': actorRole.trim().isEmpty ? 'system' : actorRole.trim(),
      'meta': meta ?? const <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtEpochMs': DateTime.now().millisecondsSinceEpoch,
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
    final caseCode = _safe(caseData['caseCode']).isEmpty
        ? caseId
        : _safe(caseData['caseCode']);
    final severityLabel = _toTitle(_safe(caseData['finalSeverity']));
    final sanctionLabel = _toTitle(
      _safe(caseData['sanctionTypeCode']).isEmpty
          ? _safe(caseData['sanctionType'])
          : _safe(caseData['sanctionTypeCode']),
    );

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

    await _notifyCaseStakeholders(
      caseId: caseId,
      caseData: caseData,
      title: 'Case Resolved',
      studentBody: 'Your violation case $caseCode has been marked as resolved.',
      reporterBody: 'Violation case $caseCode has been marked as resolved.',
      departmentBody: 'Violation case $caseCode has been marked as resolved.',
      payload: const {
        'status': ViolationCaseWorkflow.statusResolved,
        'workflowStep': ViolationCaseWorkflow.stepResolved,
      },
      actorUid: user.uid,
    );

    await _appendCaseActivity(
      caseId: caseId,
      event: 'case_resolved',
      title: 'Case resolved',
      description: (resolutionNotes ?? '').trim().isEmpty
          ? 'OSA marked this case as resolved.'
                '${severityLabel.isEmpty ? '' : ' Severity: $severityLabel.'}'
                '${sanctionLabel.isEmpty ? '' : ' Sanction: $sanctionLabel.'}'
          : 'OSA marked this case as resolved. Notes: ${resolutionNotes!.trim()}'
                '${severityLabel.isEmpty ? '' : ' Severity: $severityLabel.'}'
                '${sanctionLabel.isEmpty ? '' : ' Sanction: $sanctionLabel.'}',
      actorUid: user.uid,
      actorRole: 'osa_admin',
      meta: {
        'status': ViolationCaseWorkflow.statusResolved,
        'resolutionNotes': (resolutionNotes ?? '').trim().isEmpty
            ? null
            : resolutionNotes!.trim(),
        'finalSeverity': severityLabel.isEmpty ? null : severityLabel,
        'sanctionType': sanctionLabel.isEmpty ? null : sanctionLabel,
      },
    );
  }

  Future<void> completeMeeting({
    required String caseId,
    required String meetingNotes,
    required String finalSeverity,
    required String sanctionType,
    String? facultyNote,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');
    final caseDoc = await _cases.doc(caseId).get();
    final caseData = caseDoc.data() ?? {};
    final caseCode = _safe(caseData['caseCode']).isEmpty
        ? caseId
        : _safe(caseData['caseCode']);
    final normalizedSanctionTypeRaw = sanctionType.trim().toLowerCase();
    final normalizedSanctionType = normalizedSanctionTypeRaw.isEmpty
        ? ViolationSanctionTypes.none
        : normalizedSanctionTypeRaw;
    final sanctionLabel = _toTitle(normalizedSanctionType);
    final normalizedFacultyNote = (facultyNote ?? '').trim();
    final severityRaw = finalSeverity.trim().toLowerCase();
    final configuredSeverities = await _typesSvc.fetchSeverityLevels();
    if (configuredSeverities.isEmpty) {
      throw Exception(
        'System severity levels are unavailable right now. Please try again.',
      );
    }
    final matchedSeverity = configuredSeverities.firstWhere(
      (item) => item.toLowerCase() == severityRaw,
      orElse: () => '',
    );
    if (severityRaw.isEmpty || matchedSeverity.isEmpty) {
      throw Exception('Please select a valid severity level.');
    }
    final normalizedSeverity = matchedSeverity;

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

    await _notifyCaseStakeholders(
      caseId: caseId,
      caseData: caseData,
      title: 'Case Meeting Outcome',
      studentBody:
          'OSA has completed your meeting and resolved case $caseCode.',
      reporterBody: normalizedFacultyNote.isEmpty
          ? 'OSA completed the meeting and resolved case $caseCode.'
          : normalizedFacultyNote,
      departmentBody: 'OSA completed the meeting and resolved case $caseCode.',
      payload: {
        'status': ViolationCaseWorkflow.statusResolved,
        'workflowStep': ViolationCaseWorkflow.stepResolved,
        'meetingStatus': 'completed',
        'finalSeverity': normalizedSeverity,
        'sanctionType': normalizedSanctionType,
        'sanctionTypeCode': normalizedSanctionType,
        'facultyNote': normalizedFacultyNote.isEmpty
            ? null
            : normalizedFacultyNote,
      },
      actorUid: user.uid,
    );

    await _appendCaseActivity(
      caseId: caseId,
      event: 'meeting_completed',
      title: 'Meeting completed',
      description:
          'OSA completed the required meeting and resolved this case.'
          ' Severity: $normalizedSeverity.'
          ' Sanction: $sanctionLabel.',
      actorUid: user.uid,
      actorRole: 'osa_admin',
      meta: {
        'status': ViolationCaseWorkflow.statusResolved,
        'meetingStatus': 'completed',
        'finalSeverity': normalizedSeverity,
        'sanctionType': sanctionLabel,
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
    final caseCode = _safe(caseData['caseCode']).isNotEmpty
        ? _safe(caseData['caseCode'])
        : caseId;
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
    final actionTypeCode = (caseData['actionTypeCode'] ?? '').toString().trim();
    final actionSelected =
        (caseData['actionSelected'] ?? caseData['actionType'])
            .toString()
            .trim();
    final configuredBookingWindowDays = _normalizeBookingWindowDays(
      caseData['bookingWindowDays'],
      fallback: _initialBookingWindowDays(
        actionTypeCode: actionTypeCode,
        actionSelected: actionSelected,
      ),
    );
    final nextDueBy = _meetingDueByFromWindow(
      meetingWindow.isEmpty
          ? '${configuredBookingWindowDays}days'
          : meetingWindow,
    );
    final nextBookingDeadline = _computeBookingDeadline(
      meetingDueBy: nextDueBy,
      bookingWindowDays: configuredBookingWindowDays,
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
      'meetingWindow': '${configuredBookingWindowDays}days',
      'bookingWindowDays': configuredBookingWindowDays,
      'bookingGraceDays': _normalizeGraceWindowDays(
        caseData['bookingGraceDays'],
        fallback: _fallbackGraceWindowDays(actionTypeCode),
        meetingRequired: true,
      ),
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

    await _notifyCaseStakeholders(
      caseId: caseId,
      caseData: caseData,
      title: 'Meeting Rescheduled',
      studentBody:
          'OSA reopened meeting booking for case $caseCode. Please book again.',
      reporterBody:
          'OSA reopened meeting booking for case $caseCode after a missed schedule.',
      departmentBody:
          'Meeting booking was reopened for case $caseCode after a missed schedule.',
      payload: {
        'status': ViolationCaseWorkflow.statusActionSet,
        'meetingStatus': 'pending_student_booking',
        'rescheduled': true,
      },
      actorUid: user.uid,
    );

    await _appendCaseActivity(
      caseId: caseId,
      event: 'meeting_rescheduled',
      title: 'Meeting rebooking opened',
      description:
          'OSA reopened the booking window after a missed schedule so the student can book again.',
      actorUid: user.uid,
      actorRole: 'osa_admin',
      meta: {
        'status': ViolationCaseWorkflow.statusActionSet,
        'meetingStatus': 'pending_student_booking',
        'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
      },
    );
  }

  Future<void> cancelReport({
    required String caseId,
    required String reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw Exception('Please provide a reason for cancellation.');
    }

    final caseRef = _cases.doc(caseId);
    final caseDoc = await caseRef.get();
    if (!caseDoc.exists) throw Exception('Case not found');

    final caseData = caseDoc.data() ?? {};
    final caseCode = _safe(caseData['caseCode']).isEmpty
        ? caseId
        : _safe(caseData['caseCode']);
    final meetingRequired = caseData['meetingRequired'] == true;
    final previousStatus = (caseData['status'] ?? '').toString().trim();
    final previousWorkflowStep = (caseData['workflowStep'] ?? '')
        .toString()
        .trim();

    await caseRef.update({
      'status': ViolationCaseWorkflow.statusCancelled,
      'workflowStep': ViolationCaseWorkflow.stepCancelled,
      'workflowAction': null,
      'meetingStatus': meetingRequired ? 'cancelled' : null,
      'bookingStatus': meetingRequired ? 'cancelled' : null,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledByUid': user.uid,
      'cancellationReason': normalizedReason,
      'cancelledFromStatus': previousStatus.isEmpty ? null : previousStatus,
      'cancelledFromWorkflowStep': previousWorkflowStep.isEmpty
          ? null
          : previousWorkflowStep,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final payload = <String, dynamic>{
      'event': 'case_cancelled',
      'caseId': caseId,
      'caseCode': caseCode,
      'status': ViolationCaseWorkflow.statusCancelled,
      'reason': normalizedReason,
    };

    await _notifyCaseStakeholders(
      caseId: caseId,
      caseData: caseData,
      title: 'Violation Report Cancelled',
      studentBody: 'OSA cancelled violation case $caseCode.',
      reporterBody: 'OSA cancelled report $caseCode. Reason: $normalizedReason',
      departmentBody: 'OSA cancelled case $caseCode. Reason: $normalizedReason',
      payload: payload,
      actorUid: user.uid,
    );

    await _appendCaseActivity(
      caseId: caseId,
      event: 'case_cancelled',
      title: 'Case cancelled',
      description: 'OSA cancelled this case. Reason: $normalizedReason',
      actorUid: user.uid,
      actorRole: 'osa_admin',
      meta: payload,
    );
  }

  Future<void> reopenCancelledCase({
    required String caseId,
    required String reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw Exception('Please provide a reason for reopening.');
    }

    final caseRef = _cases.doc(caseId);
    final caseDoc = await caseRef.get();
    if (!caseDoc.exists) throw Exception('Case not found');

    final caseData = caseDoc.data() ?? {};
    final currentStatus = _safe(caseData['status']).toLowerCase();
    if (currentStatus != ViolationCaseWorkflow.statusCancelled.toLowerCase()) {
      throw Exception('Only cancelled cases can be reopened from this action.');
    }

    final cancelledFromStatus = _safe(
      caseData['cancelledFromStatus'],
    ).toLowerCase();
    final wasResolvedBeforeCancellation =
        cancelledFromStatus ==
            ViolationCaseWorkflow.statusResolved.toLowerCase() ||
        caseData['resolvedAt'] != null;
    if (!wasResolvedBeforeCancellation) {
      throw Exception(
        'This case was not cancelled from Resolved. Use Reopen + Set Action.',
      );
    }

    final caseCode = _safe(caseData['caseCode']).isEmpty
        ? caseId
        : _safe(caseData['caseCode']);
    final meetingRequired = caseData['meetingRequired'] == true;
    final hasCompletedMeeting = caseData['meetingCompletedAt'] != null;

    await caseRef.update({
      'status': ViolationCaseWorkflow.statusResolved,
      'workflowStep': ViolationCaseWorkflow.stepResolved,
      'workflowAction': meetingRequired
          ? ViolationCaseWorkflow.actionMeetingRequired
          : ViolationCaseWorkflow.actionNoMeeting,
      'meetingStatus': meetingRequired
          ? (hasCompletedMeeting ? 'completed' : null)
          : null,
      'bookingStatus': meetingRequired
          ? (hasCompletedMeeting ? 'completed' : null)
          : null,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedByUid': user.uid,
      'reopenedAt': FieldValue.serverTimestamp(),
      'reopenedByUid': user.uid,
      'reopenReason': normalizedReason,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final payload = <String, dynamic>{
      'event': 'case_reopened',
      'caseId': caseId,
      'caseCode': caseCode,
      'fromStatus': ViolationCaseWorkflow.statusCancelled,
      'toStatus': ViolationCaseWorkflow.statusResolved,
      'status': ViolationCaseWorkflow.statusResolved,
      'reason': normalizedReason,
    };

    await _notifyCaseStakeholders(
      caseId: caseId,
      caseData: caseData,
      title: 'Violation Case Reopened',
      studentBody: 'OSA reopened case $caseCode and moved it back to Resolved.',
      reporterBody:
          'OSA reopened cancelled case $caseCode and returned it to Resolved. Reason: $normalizedReason',
      departmentBody:
          'OSA reopened cancelled case $caseCode and returned it to Resolved. Reason: $normalizedReason',
      payload: payload,
      actorUid: user.uid,
    );

    await _appendCaseActivity(
      caseId: caseId,
      event: 'case_reopened',
      title: 'Case reopened',
      description:
          'OSA reopened this cancelled case and moved it back to Resolved. Reason: $normalizedReason',
      actorUid: user.uid,
      actorRole: 'osa_admin',
      meta: payload,
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamAllCases({
    int limit = defaultCaseStreamLimit,
  }) {
    return _cases
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamDepartmentCases({
    required String studentCollegeId,
    int limit = defaultCaseStreamLimit,
  }) {
    final department = studentCollegeId.trim();
    if (department.isEmpty) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return _cases
        .where('studentCollegeId', isEqualTo: department)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamResolvedCases({
    int limit = defaultCaseStreamLimit,
  }) {
    return _cases
        .where('status', isEqualTo: ViolationCaseWorkflow.statusResolved)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamSubmittedOnly() {
    return _cases
        .where('status', isEqualTo: ViolationCaseWorkflow.statusUnderReview)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}

class _IncidentTermRange {
  final String termId;
  final DateTime start;
  final DateTime end;

  const _IncidentTermRange({
    required this.termId,
    required this.start,
    required this.end,
  });
}

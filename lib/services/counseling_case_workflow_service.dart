import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'academic_settings_service.dart';

class CounselingCaseWorkflow {
  static const referralSourceStudent = 'student';
  static const referralSourceProfessor = 'professor';

  static const workflowSubmitted = 'submitted';
  static const workflowBookingRequired = 'booking_required';
  static const workflowBooked = 'booked';
  static const workflowMissed = 'missed';
  static const workflowCompleted = 'completed';
  static const workflowCancelled = 'cancelled';

  static const meetingAwaitingCallSlip = 'awaiting_call_slip';
  static const meetingPendingStudentBooking = 'pending_student_booking';
  static const meetingScheduled = 'scheduled';
  static const meetingMissed = 'meeting_missed';
  static const meetingCompleted = 'completed';
  static const meetingCancelled = 'cancelled';

  static const bookingNotOpen = 'not_open';
  static const bookingPending = 'pending';
  static const bookingBooked = 'booked';
  static const bookingMissed = 'missed';
  static const bookingCompleted = 'completed';
  static const bookingCancelled = 'cancelled';

  static const callSlipNotRequired = 'not_required';
  static const callSlipPending = 'pending';
  static const callSlipSent = 'sent';

  static const Duration bookingLeadTime = Duration(days: 1);
  static const int bookingOpenSlotDays = 7;
}

class CounselingCaseState {
  static String _safe(dynamic value) => (value ?? '').toString().trim();

  static bool isCompleted(Map<String, dynamic> data) {
    final status = _safe(data['status']).toLowerCase();
    final workflow = _safe(data['workflowStatus']).toLowerCase();
    final meeting = _safe(data['meetingStatus']).toLowerCase();
    final booking = _safe(data['bookingStatus']).toLowerCase();
    return status.contains('completed') ||
        status.contains('resolved') ||
        workflow == CounselingCaseWorkflow.workflowCompleted ||
        meeting == CounselingCaseWorkflow.meetingCompleted ||
        booking == CounselingCaseWorkflow.bookingCompleted;
  }

  static bool isCancelled(Map<String, dynamic> data) {
    final status = _safe(data['status']).toLowerCase();
    final workflow = _safe(data['workflowStatus']).toLowerCase();
    final meeting = _safe(data['meetingStatus']).toLowerCase();
    final booking = _safe(data['bookingStatus']).toLowerCase();
    return status.contains('cancel') ||
        workflow == CounselingCaseWorkflow.workflowCancelled ||
        meeting == CounselingCaseWorkflow.meetingCancelled ||
        booking == CounselingCaseWorkflow.bookingCancelled;
  }

  static bool isMissed(Map<String, dynamic> data) {
    final workflow = _safe(data['workflowStatus']).toLowerCase();
    final meeting = _safe(data['meetingStatus']).toLowerCase();
    final booking = _safe(data['bookingStatus']).toLowerCase();
    return workflow == CounselingCaseWorkflow.workflowMissed ||
        meeting == CounselingCaseWorkflow.meetingMissed ||
        booking == CounselingCaseWorkflow.bookingMissed ||
        meeting.contains('missed');
  }

  static bool isScheduled(Map<String, dynamic> data) {
    final workflow = _safe(data['workflowStatus']).toLowerCase();
    final meeting = _safe(data['meetingStatus']).toLowerCase();
    final booking = _safe(data['bookingStatus']).toLowerCase();
    return workflow == CounselingCaseWorkflow.workflowBooked ||
        meeting == CounselingCaseWorkflow.meetingScheduled ||
        booking == CounselingCaseWorkflow.bookingBooked;
  }

  static bool isAwaitingCallSlip(Map<String, dynamic> data) {
    final source = _safe(data['referralSource']).toLowerCase();
    final callSlip = _safe(data['callSlipStatus']).toLowerCase();
    final workflow = _safe(data['workflowStatus']).toLowerCase();
    final meeting = _safe(data['meetingStatus']).toLowerCase();
    return source == CounselingCaseWorkflow.referralSourceProfessor &&
        callSlip != CounselingCaseWorkflow.callSlipSent &&
        (meeting == CounselingCaseWorkflow.meetingAwaitingCallSlip ||
            workflow == CounselingCaseWorkflow.workflowSubmitted ||
            meeting == 'pending_assessment');
  }

  static bool isBookingRequired(Map<String, dynamic> data) {
    if (isCompleted(data) || isCancelled(data) || isScheduled(data)) {
      return false;
    }
    if (isAwaitingCallSlip(data)) return false;

    final workflow = _safe(data['workflowStatus']).toLowerCase();
    final meeting = _safe(data['meetingStatus']).toLowerCase();
    final booking = _safe(data['bookingStatus']).toLowerCase();
    return workflow == CounselingCaseWorkflow.workflowBookingRequired ||
        meeting == CounselingCaseWorkflow.meetingPendingStudentBooking ||
        booking == CounselingCaseWorkflow.bookingPending ||
        isMissed(data);
  }

  static bool isClosed(Map<String, dynamic> data) {
    return isCompleted(data) || isCancelled(data);
  }

  static String statusLabel(Map<String, dynamic> data) {
    if (isAwaitingCallSlip(data)) return 'Awaiting Call Slip';
    if (isCompleted(data)) return 'Completed';
    if (isCancelled(data)) return 'Cancelled';
    if (isScheduled(data)) return 'Scheduled';
    if (isMissed(data)) return 'Missed - Rebook Required';
    if (isBookingRequired(data)) return 'Booking Required';

    final workflow = _safe(data['workflowStatus']);
    if (workflow.isNotEmpty) return _titleCase(workflow.replaceAll('_', ' '));
    final status = _safe(data['status']);
    if (status.isNotEmpty) return _titleCase(status.replaceAll('_', ' '));
    return 'Submitted';
  }

  static String _titleCase(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class CounselingCaseWorkflowService {
  CounselingCaseWorkflowService({
    FirebaseFirestore? db,
    AcademicSettingsService? academicSettingsService,
  }) : _db = db ?? FirebaseFirestore.instance,
       _academicSettings =
           academicSettingsService ??
           AcademicSettingsService(db: db ?? FirebaseFirestore.instance);

  final FirebaseFirestore _db;
  final AcademicSettingsService _academicSettings;

  CollectionReference<Map<String, dynamic>> get _cases =>
      _db.collection('counseling_cases');
  CollectionReference<Map<String, dynamic>> get _slots =>
      _db.collection('counseling_meeting_slots');

  Future<String> submitSelfReferral({
    required String studentUid,
    required String studentName,
    required String studentNo,
    required String studentProgramId,
    required String counselingType,
    required Map<String, dynamic> reasons,
    required String comments,
  }) async {
    final caseCode = await _academicSettings.generateCounselingCaseCode();
    final context = await _loadAcademicContext();
    final now = DateTime.now();
    final bookingWindowStart = now.add(CounselingCaseWorkflow.bookingLeadTime);

    final doc = await _cases.add({
      'caseCode': caseCode,
      'status': CounselingCaseWorkflow.workflowSubmitted,
      'workflowStatus': CounselingCaseWorkflow.workflowBookingRequired,
      'referralSource': CounselingCaseWorkflow.referralSourceStudent,
      'counselingType': counselingType.trim().toLowerCase(),
      'meetingRequired': true,
      'meetingStatus': CounselingCaseWorkflow.meetingPendingStudentBooking,
      'bookingStatus': CounselingCaseWorkflow.bookingPending,
      'callSlipStatus': CounselingCaseWorkflow.callSlipNotRequired,
      'bookingLeadHours': CounselingCaseWorkflow.bookingLeadTime.inHours,
      'bookingWindowDays': null,
      'bookingOpenSlotDays': CounselingCaseWorkflow.bookingOpenSlotDays,
      'bookingRequiredAt': Timestamp.fromDate(now),
      'bookingWindowStartAt': Timestamp.fromDate(bookingWindowStart),
      'bookingWindowEndAt': null,
      'bookingDeadlineAt': null,
      'bookingSlotId': null,
      'currentAppointmentId': null,
      'scheduledAt': null,
      'missedCount': 0,
      'schoolYearId': context.schoolYearId,
      'termId': context.termId,
      'studentUid': studentUid.trim(),
      'studentName': studentName.trim(),
      'studentNo': studentNo.trim(),
      'studentProgramId': studentProgramId.trim(),
      'referredByUid': studentUid.trim(),
      'referredByRole': 'student',
      'classroomTeacher': '',
      'referredBy': studentName.trim(),
      'referralDate': Timestamp.fromDate(now),
      'reasons': reasons,
      'comments': comments.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _appendCaseActivity(
      caseId: doc.id,
      event: 'case_submitted',
      title: 'Self-referral submitted',
      description: 'Student submitted a counseling self-referral.',
      actorUid: studentUid.trim(),
      actorRole: 'student',
      meta: {
        'workflowStatus': CounselingCaseWorkflow.workflowBookingRequired,
        'meetingStatus': CounselingCaseWorkflow.meetingPendingStudentBooking,
      },
    );
    return doc.id;
  }

  Future<String> submitProfessorReferral({
    required String studentUid,
    required String studentName,
    required String studentNo,
    required String studentProgramId,
    required String professorUid,
    required String professorName,
    required String counselingType,
    required Map<String, dynamic> reasons,
    required String comments,
  }) async {
    final caseCode = await _academicSettings.generateCounselingCaseCode();
    final context = await _loadAcademicContext();
    final now = DateTime.now();
    final referredBy = professorName.trim().isEmpty
        ? 'Professor'
        : professorName.trim();

    final doc = await _cases.add({
      'caseCode': caseCode,
      'status': CounselingCaseWorkflow.workflowSubmitted,
      'workflowStatus': CounselingCaseWorkflow.workflowSubmitted,
      'referralSource': CounselingCaseWorkflow.referralSourceProfessor,
      'counselingType': counselingType.trim().toLowerCase(),
      'meetingRequired': true,
      'meetingStatus': CounselingCaseWorkflow.meetingAwaitingCallSlip,
      'bookingStatus': CounselingCaseWorkflow.bookingNotOpen,
      'callSlipStatus': CounselingCaseWorkflow.callSlipPending,
      'bookingLeadHours': CounselingCaseWorkflow.bookingLeadTime.inHours,
      'bookingWindowDays': null,
      'bookingOpenSlotDays': CounselingCaseWorkflow.bookingOpenSlotDays,
      'bookingRequiredAt': null,
      'bookingWindowStartAt': null,
      'bookingWindowEndAt': null,
      'bookingDeadlineAt': null,
      'bookingSlotId': null,
      'currentAppointmentId': null,
      'scheduledAt': null,
      'missedCount': 0,
      'schoolYearId': context.schoolYearId,
      'termId': context.termId,
      'studentUid': studentUid.trim(),
      'studentName': studentName.trim(),
      'studentNo': studentNo.trim(),
      'studentProgramId': studentProgramId.trim(),
      'referredByUid': professorUid.trim(),
      'referredByRole': 'professor',
      'classroomTeacher': referredBy,
      'referredBy': referredBy,
      'referralDate': Timestamp.fromDate(now),
      'reasons': reasons,
      'comments': comments.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _appendCaseActivity(
      caseId: doc.id,
      event: 'case_submitted',
      title: 'Professor referral submitted',
      description: '$referredBy submitted a counseling referral.',
      actorUid: professorUid.trim(),
      actorRole: 'professor',
      meta: {
        'workflowStatus': CounselingCaseWorkflow.workflowSubmitted,
        'meetingStatus': CounselingCaseWorkflow.meetingAwaitingCallSlip,
      },
    );
    return doc.id;
  }

  Future<void> sendCallSlip({required String caseId}) async {
    final now = DateTime.now();
    final bookingWindowStart = now.add(CounselingCaseWorkflow.bookingLeadTime);
    final actorUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    var studentUid = '';
    var caseCode = caseId;

    await _db.runTransaction((tx) async {
      final ref = _cases.doc(caseId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Counseling case not found.');
      final data = snap.data() ?? <String, dynamic>{};

      final source = _safe(data['referralSource']).toLowerCase();
      if (source != CounselingCaseWorkflow.referralSourceProfessor) {
        throw Exception('Call slip is only available for professor referrals.');
      }

      final meetingStatus = _safe(data['meetingStatus']).toLowerCase();
      final workflowStatus = _safe(data['workflowStatus']).toLowerCase();
      final callSlipStatus = _safe(data['callSlipStatus']).toLowerCase();
      if (callSlipStatus == CounselingCaseWorkflow.callSlipSent) {
        throw Exception('Call slip has already been sent.');
      }

      final canSend =
          meetingStatus == CounselingCaseWorkflow.meetingAwaitingCallSlip ||
          workflowStatus == CounselingCaseWorkflow.workflowSubmitted;
      if (!canSend) {
        throw Exception('This case is not waiting for a call slip.');
      }

      studentUid = _safe(data['studentUid']);
      caseCode = _safe(data['caseCode']).isEmpty
          ? caseId
          : _safe(data['caseCode']);

      tx.update(ref, {
        'workflowStatus': CounselingCaseWorkflow.workflowBookingRequired,
        'meetingStatus': CounselingCaseWorkflow.meetingPendingStudentBooking,
        'bookingStatus': CounselingCaseWorkflow.bookingPending,
        'callSlipStatus': CounselingCaseWorkflow.callSlipSent,
        'callSlipSentByUid': actorUid,
        'callSlipSentAt': FieldValue.serverTimestamp(),
        'bookingRequiredAt': Timestamp.fromDate(now),
        'bookingWindowStartAt': Timestamp.fromDate(bookingWindowStart),
        'bookingWindowEndAt': null,
        'bookingDeadlineAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (studentUid.isEmpty) return;
    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid,
      title: 'Counseling Call Slip',
      body:
          'A counseling call slip was sent for case $caseCode. Please book your appointment.',
      payload: const {
        'module': 'counseling',
        'workflowStatus': CounselingCaseWorkflow.workflowBookingRequired,
        'meetingStatus': CounselingCaseWorkflow.meetingPendingStudentBooking,
      },
    );
    await _appendCaseActivity(
      caseId: caseId,
      event: 'call_slip_sent',
      title: 'Call slip sent',
      description: 'Counseling opened booking for this professor referral.',
      actorRole: 'counseling_admin',
      meta: {
        'workflowStatus': CounselingCaseWorkflow.workflowBookingRequired,
        'meetingStatus': CounselingCaseWorkflow.meetingPendingStudentBooking,
      },
    );
  }

  Future<void> markAppointmentBooked({
    required String caseId,
    required String slotId,
    required DateTime scheduledAt,
  }) async {
    await _db.runTransaction((tx) async {
      final ref = _cases.doc(caseId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Counseling case not found.');
      final data = snap.data() ?? <String, dynamic>{};

      final workflowStatus = _safe(data['workflowStatus']).toLowerCase();
      final meetingStatus = _safe(data['meetingStatus']).toLowerCase();
      final canBook =
          workflowStatus == CounselingCaseWorkflow.workflowBookingRequired ||
          meetingStatus == CounselingCaseWorkflow.meetingPendingStudentBooking;
      if (!canBook) {
        throw Exception('Booking is not open for this counseling case.');
      }

      tx.update(ref, {
        'workflowStatus': CounselingCaseWorkflow.workflowBooked,
        'meetingStatus': CounselingCaseWorkflow.meetingScheduled,
        'bookingStatus': CounselingCaseWorkflow.bookingBooked,
        'currentAppointmentId': slotId.trim(),
        'bookingSlotId': slotId.trim(),
        'scheduledAt': Timestamp.fromDate(scheduledAt),
        'bookingBookedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await _appendCaseActivity(
      caseId: caseId,
      event: 'appointment_booked',
      title: 'Appointment booked',
      description: 'A counseling appointment was booked.',
      actorRole: 'student',
      meta: {
        'slotId': slotId.trim(),
        'scheduledAt': scheduledAt.toIso8601String(),
        'workflowStatus': CounselingCaseWorkflow.workflowBooked,
        'meetingStatus': CounselingCaseWorkflow.meetingScheduled,
      },
    );
  }

  Future<void> bookSlotForCase({
    required String slotId,
    required String caseId,
    required String studentUid,
  }) async {
    final slotRef = _slots.doc(slotId.trim());
    final caseRef = _cases.doc(caseId.trim());
    final actorUid = FirebaseAuth.instance.currentUser?.uid;
    var caseCode = caseId.trim();
    DateTime? bookedStartAt;

    await _db.runTransaction((tx) async {
      final slotSnap = await tx.get(slotRef);
      if (!slotSnap.exists) throw Exception('Slot not found.');
      final slotData = slotSnap.data() ?? <String, dynamic>{};
      final slotStatus = _safe(slotData['status']).toLowerCase();
      if (slotStatus != 'open') {
        throw Exception('Selected slot is no longer available.');
      }

      final caseSnap = await tx.get(caseRef);
      if (!caseSnap.exists) throw Exception('Counseling case not found.');
      final caseData = caseSnap.data() ?? <String, dynamic>{};
      caseCode = _safe(caseData['caseCode']).isEmpty
          ? caseId.trim()
          : _safe(caseData['caseCode']);

      final caseStudentUid = _safe(caseData['studentUid']);
      if (caseStudentUid.isNotEmpty && caseStudentUid != studentUid.trim()) {
        throw Exception('This case does not belong to the current student.');
      }

      final callSlipStatus = _safe(caseData['callSlipStatus']).toLowerCase();
      final source = _safe(caseData['referralSource']).toLowerCase();
      if (source == CounselingCaseWorkflow.referralSourceProfessor &&
          callSlipStatus != CounselingCaseWorkflow.callSlipSent) {
        throw Exception(
          'Booking is not available yet. Please wait for counseling call slip.',
        );
      }

      final workflowStatus = _safe(caseData['workflowStatus']).toLowerCase();
      final meetingStatus = _safe(caseData['meetingStatus']).toLowerCase();
      final bookingStatus = _safe(caseData['bookingStatus']).toLowerCase();
      final canBook =
          workflowStatus == CounselingCaseWorkflow.workflowBookingRequired ||
          workflowStatus == CounselingCaseWorkflow.workflowMissed ||
          meetingStatus ==
              CounselingCaseWorkflow.meetingPendingStudentBooking ||
          meetingStatus == CounselingCaseWorkflow.meetingMissed ||
          bookingStatus == CounselingCaseWorkflow.bookingMissed;
      if (!canBook) {
        throw Exception('Booking is not open for this counseling case.');
      }

      final startAt = (slotData['startAt'] as Timestamp?)?.toDate();
      final endAt = (slotData['endAt'] as Timestamp?)?.toDate();
      if (startAt == null || endAt == null) {
        throw Exception('Selected slot has invalid schedule.');
      }

      final now = DateTime.now();
      if (startAt.isBefore(now)) {
        throw Exception('Selected slot is already in the past.');
      }

      final leadHours =
          (caseData['bookingLeadHours'] as num?)?.toInt() ??
          CounselingCaseWorkflow.bookingLeadTime.inHours;
      final earliest = now.add(Duration(hours: leadHours));
      if (startAt.isBefore(earliest)) {
        throw Exception(
          'Selected slot is too soon. Please book at least $leadHours hours ahead.',
        );
      }

      final bookingDeadlineAt = (caseData['bookingDeadlineAt'] as Timestamp?)
          ?.toDate();
      if (bookingDeadlineAt != null && now.isAfter(bookingDeadlineAt)) {
        throw Exception(
          'Booking window has ended. Please contact counseling support.',
        );
      }

      final termId = _safe(caseData['termId']);
      final schoolYearId = _safe(caseData['schoolYearId']);
      final slotTermId = _safe(slotData['termId']);
      final slotSchoolYearId = _safe(slotData['schoolYearId']);
      if (termId.isNotEmpty && slotTermId.isNotEmpty && termId != slotTermId) {
        throw Exception('Selected slot does not match case term.');
      }
      if (schoolYearId.isNotEmpty &&
          slotSchoolYearId.isNotEmpty &&
          schoolYearId != slotSchoolYearId) {
        throw Exception('Selected slot does not match case school year.');
      }

      tx.update(slotRef, {
        'status': 'booked',
        'caseId': caseId.trim(),
        'studentUid': studentUid.trim(),
        'bookedByUid': actorUid,
        'bookedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.update(caseRef, {
        'workflowStatus': CounselingCaseWorkflow.workflowBooked,
        'meetingStatus': CounselingCaseWorkflow.meetingScheduled,
        'bookingStatus': CounselingCaseWorkflow.bookingBooked,
        'currentAppointmentId': slotId.trim(),
        'bookingSlotId': slotId.trim(),
        'scheduledAt': Timestamp.fromDate(startAt),
        'bookingBookedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      bookedStartAt = startAt;
    });

    await _appendCaseActivity(
      caseId: caseId.trim(),
      event: 'appointment_booked',
      title: 'Appointment booked',
      description:
          'Student booked a counseling appointment${bookedStartAt == null ? '' : ' for ${bookedStartAt!.toIso8601String()}'}',
      actorUid: actorUid,
      actorRole: 'student',
      meta: {
        'slotId': slotId.trim(),
        'caseCode': caseCode,
        'scheduledAt': bookedStartAt?.toIso8601String(),
        'workflowStatus': CounselingCaseWorkflow.workflowBooked,
        'meetingStatus': CounselingCaseWorkflow.meetingScheduled,
      },
    );
  }

  Future<void> markAppointmentMissed({required String caseId}) async {
    var studentUid = '';
    var caseCode = caseId;
    await _db.runTransaction((tx) async {
      final ref = _cases.doc(caseId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Counseling case not found.');
      final data = snap.data() ?? <String, dynamic>{};

      final workflowStatus = _safe(data['workflowStatus']).toLowerCase();
      final meetingStatus = _safe(data['meetingStatus']).toLowerCase();
      final canMarkMissed =
          workflowStatus == CounselingCaseWorkflow.workflowBooked ||
          meetingStatus == CounselingCaseWorkflow.meetingScheduled;
      if (!canMarkMissed) {
        throw Exception('Only booked appointments can be marked missed.');
      }

      studentUid = _safe(data['studentUid']);
      caseCode = _safe(data['caseCode']).isEmpty
          ? caseId
          : _safe(data['caseCode']);
      final missedCount = (data['missedCount'] as num?)?.toInt() ?? 0;
      final slotId = _safe(data['bookingSlotId']);
      if (slotId.isNotEmpty) {
        tx.set(_slots.doc(slotId), {
          'status': 'missed',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      tx.update(ref, {
        'workflowStatus': CounselingCaseWorkflow.workflowMissed,
        'meetingStatus': CounselingCaseWorkflow.meetingMissed,
        'bookingStatus': CounselingCaseWorkflow.bookingMissed,
        'missedCount': missedCount + 1,
        'bookingMissedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (studentUid.isEmpty) return;
    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid,
      title: 'Counseling Appointment Missed',
      body:
          'Your counseling appointment for case $caseCode was marked missed. You may book again when booking is available.',
      payload: const {
        'module': 'counseling',
        'workflowStatus': CounselingCaseWorkflow.workflowMissed,
        'meetingStatus': CounselingCaseWorkflow.meetingMissed,
      },
    );
    await _appendCaseActivity(
      caseId: caseId,
      event: 'appointment_missed',
      title: 'Appointment marked missed',
      description: 'Counseling staff marked the appointment as missed.',
      actorRole: 'counseling_admin',
      meta: {
        'workflowStatus': CounselingCaseWorkflow.workflowMissed,
        'meetingStatus': CounselingCaseWorkflow.meetingMissed,
      },
    );
  }

  Future<void> reopenBookingAfterMissed({required String caseId}) async {
    final now = DateTime.now();
    final bookingWindowStart = now.add(CounselingCaseWorkflow.bookingLeadTime);
    var studentUid = '';
    var caseCode = caseId;
    await _db.runTransaction((tx) async {
      final ref = _cases.doc(caseId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Counseling case not found.');
      final data = snap.data() ?? <String, dynamic>{};

      final workflowStatus = _safe(data['workflowStatus']).toLowerCase();
      final meetingStatus = _safe(data['meetingStatus']).toLowerCase();
      final missed =
          workflowStatus == CounselingCaseWorkflow.workflowMissed ||
          meetingStatus == CounselingCaseWorkflow.meetingMissed ||
          _safe(data['bookingStatus']).toLowerCase() ==
              CounselingCaseWorkflow.bookingMissed;
      if (!missed) {
        throw Exception('Only missed appointments can be reopened.');
      }

      studentUid = _safe(data['studentUid']);
      caseCode = _safe(data['caseCode']).isEmpty
          ? caseId
          : _safe(data['caseCode']);
      tx.update(ref, {
        'workflowStatus': CounselingCaseWorkflow.workflowBookingRequired,
        'meetingStatus': CounselingCaseWorkflow.meetingPendingStudentBooking,
        'bookingStatus': CounselingCaseWorkflow.bookingPending,
        'bookingRequiredAt': Timestamp.fromDate(now),
        'bookingWindowStartAt': Timestamp.fromDate(bookingWindowStart),
        'bookingWindowEndAt': null,
        'bookingDeadlineAt': null,
        'currentAppointmentId': null,
        'bookingSlotId': null,
        'scheduledAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (studentUid.isEmpty) return;
    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid,
      title: 'Counseling Booking Reopened',
      body:
          'Booking was reopened for counseling case $caseCode. Please select a new appointment slot.',
      payload: const {
        'module': 'counseling',
        'workflowStatus': CounselingCaseWorkflow.workflowBookingRequired,
        'meetingStatus': CounselingCaseWorkflow.meetingPendingStudentBooking,
      },
    );
    await _appendCaseActivity(
      caseId: caseId,
      event: 'booking_reopened',
      title: 'Booking reopened',
      description:
          'Counseling staff reopened booking after a missed appointment.',
      actorRole: 'counseling_admin',
      meta: {
        'workflowStatus': CounselingCaseWorkflow.workflowBookingRequired,
        'meetingStatus': CounselingCaseWorkflow.meetingPendingStudentBooking,
      },
    );
  }

  Future<void> markAppointmentCompleted({required String caseId}) async {
    var studentUid = '';
    var caseCode = caseId;
    await _db.runTransaction((tx) async {
      final ref = _cases.doc(caseId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Counseling case not found.');
      final data = snap.data() ?? <String, dynamic>{};
      final workflowStatus = _safe(data['workflowStatus']).toLowerCase();
      final meetingStatus = _safe(data['meetingStatus']).toLowerCase();
      final canComplete =
          workflowStatus == CounselingCaseWorkflow.workflowBooked ||
          meetingStatus == CounselingCaseWorkflow.meetingScheduled;
      if (!canComplete) {
        throw Exception('Only booked appointments can be completed.');
      }

      studentUid = _safe(data['studentUid']);
      caseCode = _safe(data['caseCode']).isEmpty
          ? caseId
          : _safe(data['caseCode']);
      final slotId = _safe(data['bookingSlotId']);
      if (slotId.isNotEmpty) {
        tx.set(_slots.doc(slotId), {
          'status': 'completed',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      tx.update(ref, {
        'status': CounselingCaseWorkflow.workflowCompleted,
        'workflowStatus': CounselingCaseWorkflow.workflowCompleted,
        'meetingStatus': CounselingCaseWorkflow.meetingCompleted,
        'bookingStatus': CounselingCaseWorkflow.bookingCompleted,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (studentUid.isEmpty) return;
    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid,
      title: 'Counseling Appointment Completed',
      body:
          'Your counseling appointment for case $caseCode was marked completed.',
      payload: const {
        'module': 'counseling',
        'workflowStatus': CounselingCaseWorkflow.workflowCompleted,
        'meetingStatus': CounselingCaseWorkflow.meetingCompleted,
      },
    );
    await _appendCaseActivity(
      caseId: caseId,
      event: 'appointment_completed',
      title: 'Appointment completed',
      description: 'Counseling staff marked the appointment as completed.',
      actorRole: 'counseling_admin',
      meta: {
        'workflowStatus': CounselingCaseWorkflow.workflowCompleted,
        'meetingStatus': CounselingCaseWorkflow.meetingCompleted,
      },
    );
  }

  Future<void> cancelCase({required String caseId}) async {
    final snap = await _cases.doc(caseId).get();
    final data = snap.data() ?? <String, dynamic>{};
    final studentUid = _safe(data['studentUid']);
    final caseCode = _safe(data['caseCode']).isEmpty
        ? caseId
        : _safe(data['caseCode']);

    await _cases.doc(caseId).update({
      'status': CounselingCaseWorkflow.workflowCancelled,
      'workflowStatus': CounselingCaseWorkflow.workflowCancelled,
      'meetingStatus': CounselingCaseWorkflow.meetingCancelled,
      'bookingStatus': CounselingCaseWorkflow.bookingCancelled,
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (studentUid.isEmpty) return;
    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid,
      title: 'Counseling Case Cancelled',
      body: 'Counseling case $caseCode was cancelled by counseling staff.',
      payload: const {
        'module': 'counseling',
        'workflowStatus': CounselingCaseWorkflow.workflowCancelled,
        'meetingStatus': CounselingCaseWorkflow.meetingCancelled,
      },
    );
    await _appendCaseActivity(
      caseId: caseId,
      event: 'case_cancelled',
      title: 'Case cancelled',
      description: 'Counseling staff cancelled the case.',
      actorRole: 'counseling_admin',
      meta: {
        'workflowStatus': CounselingCaseWorkflow.workflowCancelled,
        'meetingStatus': CounselingCaseWorkflow.meetingCancelled,
      },
    );
  }

  Future<int> expireOverdueScheduledMeetings({
    int limit = 300,
    Duration gracePeriod = const Duration(hours: 1),
  }) async {
    final snap = await _cases.limit(limit).get();
    return _expireOverdueScheduledDocs(snap.docs, gracePeriod: gracePeriod);
  }

  Future<int> expireOverdueScheduledMeetingsForStudent({
    required String studentUid,
    int limit = 80,
    Duration gracePeriod = const Duration(hours: 1),
  }) async {
    final uid = studentUid.trim();
    if (uid.isEmpty) return 0;
    final snap = await _cases
        .where('studentUid', isEqualTo: uid)
        .limit(limit)
        .get();
    return _expireOverdueScheduledDocs(snap.docs, gracePeriod: gracePeriod);
  }

  Future<int> _expireOverdueScheduledDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required Duration gracePeriod,
  }) async {
    final now = DateTime.now();
    final overdue = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in docs) {
      final data = doc.data();
      final workflow = _safe(data['workflowStatus']).toLowerCase();
      final meeting = _safe(data['meetingStatus']).toLowerCase();
      final booking = _safe(data['bookingStatus']).toLowerCase();
      final scheduledAt = (data['scheduledAt'] as Timestamp?)?.toDate();

      final scheduled =
          workflow == CounselingCaseWorkflow.workflowBooked ||
          meeting == CounselingCaseWorkflow.meetingScheduled ||
          booking == CounselingCaseWorkflow.bookingBooked;
      if (!scheduled || scheduledAt == null) continue;

      final closed =
          workflow == CounselingCaseWorkflow.workflowCompleted ||
          workflow == CounselingCaseWorkflow.workflowCancelled ||
          meeting == CounselingCaseWorkflow.meetingCompleted ||
          meeting == CounselingCaseWorkflow.meetingCancelled ||
          booking == CounselingCaseWorkflow.bookingCompleted ||
          booking == CounselingCaseWorkflow.bookingCancelled;
      if (closed) continue;

      final alreadyMissed =
          workflow == CounselingCaseWorkflow.workflowMissed ||
          meeting == CounselingCaseWorkflow.meetingMissed ||
          booking == CounselingCaseWorkflow.bookingMissed ||
          meeting.contains('missed');
      if (alreadyMissed) continue;

      if (now.isAfter(scheduledAt.add(gracePeriod))) {
        overdue.add(doc);
      }
    }

    if (overdue.isEmpty) return 0;

    final caseBatch = _db.batch();
    final slotBatch = _db.batch();
    var hasSlotUpdate = false;

    for (final doc in overdue) {
      final data = doc.data();
      final slotId = _safe(data['bookingSlotId']);
      caseBatch.update(doc.reference, {
        'workflowStatus': CounselingCaseWorkflow.workflowMissed,
        'meetingStatus': CounselingCaseWorkflow.meetingMissed,
        'bookingStatus': CounselingCaseWorkflow.bookingMissed,
        'missedCount': FieldValue.increment(1),
        'meetingMissedAt': FieldValue.serverTimestamp(),
        'bookingMissedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (slotId.isNotEmpty) {
        hasSlotUpdate = true;
        slotBatch.set(_slots.doc(slotId), {
          'status': 'missed',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    await caseBatch.commit();
    if (hasSlotUpdate) {
      await slotBatch.commit();
    }

    for (final doc in overdue) {
      final data = doc.data();
      final studentUid = _safe(data['studentUid']);
      if (studentUid.isEmpty) continue;
      final caseCode = _safe(data['caseCode']).isEmpty
          ? doc.id
          : _safe(data['caseCode']);
      await _notifyStudent(
        caseId: doc.id,
        studentUid: studentUid,
        title: 'Counseling Appointment Missed',
        body:
            'You did not attend the scheduled counseling appointment for case $caseCode. You may rebook your appointment.',
        payload: const {
          'module': 'counseling',
          'workflowStatus': CounselingCaseWorkflow.workflowMissed,
          'meetingStatus': CounselingCaseWorkflow.meetingMissed,
        },
      );
      await _appendCaseActivity(
        caseId: doc.id,
        event: 'appointment_auto_missed',
        title: 'Appointment auto-marked missed',
        description:
            'System detected an overdue scheduled counseling appointment and marked it missed.',
        actorRole: 'system',
        meta: {
          'caseCode': caseCode,
          'workflowStatus': CounselingCaseWorkflow.workflowMissed,
          'meetingStatus': CounselingCaseWorkflow.meetingMissed,
        },
      );
    }

    return overdue.length;
  }

  Future<_AcademicContext> _loadAcademicContext() async {
    final active = await _academicSettings.getActiveSY();
    if (active == null) {
      throw Exception('No active school year. Please set one first.');
    }

    final schoolYearId = _safe(active['id']);
    final termId = _safe(active['activeTermId']).isEmpty
        ? 'term1'
        : _safe(active['activeTermId']);
    return _AcademicContext(schoolYearId: schoolYearId, termId: termId);
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
      'actorUid': _safe(actorUid).isEmpty
          ? (FirebaseAuth.instance.currentUser?.uid ?? '')
          : _safe(actorUid),
      'actorRole': actorRole.trim().isEmpty ? 'system' : actorRole.trim(),
      'meta': meta ?? const <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtEpochMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _notifyStudent({
    required String caseId,
    required String studentUid,
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    final now = FieldValue.serverTimestamp();
    await _cases.doc(caseId).collection('notification_queue').add({
      'toType': 'uid',
      'toUid': studentUid,
      'title': title,
      'body': body,
      'payload': payload,
      'createdAt': now,
      'readAt': null,
    });

    await _db
        .collection('users')
        .doc(studentUid)
        .collection('notifications')
        .add({
          'caseId': caseId,
          'title': title,
          'body': body,
          'payload': payload,
          'createdAt': now,
          'readAt': null,
        });
  }
}

class _AcademicContext {
  const _AcademicContext({required this.schoolYearId, required this.termId});

  final String schoolYearId;
  final String termId;
}

String _safe(dynamic value) => (value ?? '').toString().trim();

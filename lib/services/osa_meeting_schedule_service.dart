import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'violation_case_service.dart';

class OsaMeetingSlotStatus {
  static const open = 'open';
  static const booked = 'booked';
  static const completed = 'completed';
  static const missed = 'missed';
  static const cancelled = 'cancelled';
}

class OsaMeetingScheduleService {
  static const Duration bookingLeadTime = Duration(hours: 2);

  OsaMeetingScheduleService({
    String templateCollection = 'osa_schedule_templates',
    String slotCollection = 'osa_meeting_slots',
    String caseCollection = 'violation_cases',
  }) : _templateCollection = templateCollection,
       _slotCollection = slotCollection,
       _caseCollection = caseCollection;

  final _db = FirebaseFirestore.instance;
  final String _templateCollection;
  final String _slotCollection;
  final String _caseCollection;

  CollectionReference<Map<String, dynamic>> get _templates =>
      _db.collection(_templateCollection);
  CollectionReference<Map<String, dynamic>> get _slots =>
      _db.collection(_slotCollection);
  CollectionReference<Map<String, dynamic>> get _cases =>
      _db.collection(_caseCollection);

  String _templateDocId(String schoolYearId, String termId) =>
      '$schoolYearId::$termId';

  bool _isMissingIndex(Object error) =>
      error is FirebaseException && error.code == 'failed-precondition';

  Future<void> saveTermScheduleTemplate({
    required String schoolYearId,
    required String termId,
    required Map<String, List<Map<String, String>>> weeklyWindows,
    Map<String, List<Map<String, String>>> recurringBlockedWindows = const {},
    List<String> blockedDates = const [],
    int slotMinutes = 60,
    String timezone = 'Asia/Manila',
  }) async {
    final now = FieldValue.serverTimestamp();
    final docId = _templateDocId(schoolYearId.trim(), termId.trim());

    await _templates.doc(docId).set({
      'schoolYearId': schoolYearId.trim(),
      'termId': termId.trim(),
      'slotMinutes': slotMinutes,
      'timezone': timezone,
      'weeklyWindows': weeklyWindows,
      'recurringBlockedWindows': recurringBlockedWindows,
      'blockedDates': blockedDates.map((v) => v.trim()).toList(),
      'updatedAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getTermScheduleTemplate({
    required String schoolYearId,
    required String termId,
  }) async {
    final doc = await _templates
        .doc(_templateDocId(schoolYearId.trim(), termId.trim()))
        .get();
    return doc.data();
  }

  Future<int> generateSlotsFromTemplate({
    required String schoolYearId,
    required String termId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    bool replaceOpenSlots = false,
    DateTime? replaceOpenFrom,
    bool failIfExisting = false,
    DateTime? existingFrom,
  }) async {
    if (rangeEnd.isBefore(rangeStart)) {
      throw Exception('rangeEnd must be after rangeStart');
    }

    final normalizedSchoolYearId = schoolYearId.trim();
    final normalizedTermId = termId.trim();

    if (failIfExisting) {
      final hasExisting = await hasSlotsForTerm(
        schoolYearId: normalizedSchoolYearId,
        termId: normalizedTermId,
        fromDate: existingFrom ?? rangeStart,
      );
      if (hasExisting) {
        throw Exception(
          'Slots already exist for this term. Reset open slots before generating a new schedule.',
        );
      }
    }

    final template = await getTermScheduleTemplate(
      schoolYearId: normalizedSchoolYearId,
      termId: normalizedTermId,
    );
    if (template == null) {
      throw Exception('Schedule template not found for $schoolYearId $termId');
    }

    final weeklyWindows =
        (template['weeklyWindows'] as Map<String, dynamic>? ?? {}).map((
          key,
          value,
        ) {
          final list = (value as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((window) => Map<String, String>.from(window))
              .toList();
          return MapEntry(key.toLowerCase().trim(), list);
        });
    final recurringBlockedWindows =
        (template['recurringBlockedWindows'] as Map<String, dynamic>? ?? {})
            .map((key, value) {
              final list = (value as List<dynamic>? ?? [])
                  .whereType<Map>()
                  .map((window) => Map<String, String>.from(window))
                  .toList();
              return MapEntry(key.toLowerCase().trim(), list);
            });
    final blockedDates = (template['blockedDates'] as List<dynamic>? ?? [])
        .map((v) => v.toString().trim())
        .toSet();
    final slotMinutes = (template['slotMinutes'] as num?)?.toInt() ?? 60;

    if (replaceOpenSlots) {
      await _deleteOpenSlotsForTerm(
        schoolYearId: normalizedSchoolYearId,
        termId: normalizedTermId,
        fromDate: replaceOpenFrom ?? rangeStart,
      );
    }

    final normalizedStart = DateTime(
      rangeStart.year,
      rangeStart.month,
      rangeStart.day,
    );
    final normalizedEnd = DateTime(
      rangeEnd.year,
      rangeEnd.month,
      rangeEnd.day,
      23,
      59,
      59,
    );

    var batch = _db.batch();
    var opCount = 0;
    var generated = 0;
    var current = normalizedStart;

    while (!current.isAfter(normalizedEnd)) {
      final dateKey = _dateKey(current);
      if (!blockedDates.contains(dateKey)) {
        final weekdayKey = _weekdayKey(current);
        final windows = weeklyWindows[weekdayKey] ?? const [];
        final dayBlockedWindows =
            recurringBlockedWindows[weekdayKey] ?? const [];

        for (final window in windows) {
          final start = _parseTimeOnDate(current, window['start']);
          final end = _parseTimeOnDate(current, window['end']);
          if (start == null || end == null || !end.isAfter(start)) {
            continue;
          }

          var slotStart = start;
          while (slotStart.add(Duration(minutes: slotMinutes)).isBefore(end) ||
              slotStart
                  .add(Duration(minutes: slotMinutes))
                  .isAtSameMomentAs(end)) {
            final slotEnd = slotStart.add(Duration(minutes: slotMinutes));
            final blocked = _isBlockedByRecurringWindow(
              day: current,
              slotStart: slotStart,
              slotEnd: slotEnd,
              blockedWindows: dayBlockedWindows,
            );
            if (blocked) {
              slotStart = slotEnd;
              continue;
            }

            final slotId = _slotDocId(
              schoolYearId: normalizedSchoolYearId,
              termId: normalizedTermId,
              slotStart: slotStart,
            );
            final slotRef = _slots.doc(slotId);

            batch.set(slotRef, {
              'slotId': slotId,
              'schoolYearId': normalizedSchoolYearId,
              'termId': normalizedTermId,
              'dateKey': dateKey,
              'weekday': weekdayKey,
              'startAt': Timestamp.fromDate(slotStart),
              'endAt': Timestamp.fromDate(slotEnd),
              'durationMinutes': slotMinutes,
              'status': OsaMeetingSlotStatus.open,
              'caseId': null,
              'studentUid': null,
              'bookedByUid': null,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: false));

            generated++;
            opCount++;
            if (opCount == 400) {
              await batch.commit();
              batch = _db.batch();
              opCount = 0;
            }

            slotStart = slotEnd;
          }
        }
      }

      current = current.add(const Duration(days: 1));
    }

    if (opCount > 0) {
      await batch.commit();
    }

    return generated;
  }

  bool _isBlockedByRecurringWindow({
    required DateTime day,
    required DateTime slotStart,
    required DateTime slotEnd,
    required List<Map<String, String>> blockedWindows,
  }) {
    for (final window in blockedWindows) {
      final blockedStart = _parseTimeOnDate(day, window['start']);
      final blockedEnd = _parseTimeOnDate(day, window['end']);
      if (blockedStart == null || blockedEnd == null) continue;
      if (!blockedEnd.isAfter(blockedStart)) continue;
      final overlaps =
          slotStart.isBefore(blockedEnd) && blockedStart.isBefore(slotEnd);
      if (overlaps) return true;
    }
    return false;
  }

  Future<bool> hasSlotsForTerm({
    required String schoolYearId,
    required String termId,
    DateTime? fromDate,
  }) async {
    final normalizedSchoolYearId = schoolYearId.trim();
    final normalizedTermId = termId.trim();
    final normalizedFrom = fromDate == null
        ? null
        : DateTime(fromDate.year, fromDate.month, fromDate.day);

    try {
      var query = _slots
          .where('schoolYearId', isEqualTo: normalizedSchoolYearId)
          .where('termId', isEqualTo: normalizedTermId);

      if (normalizedFrom != null) {
        query = query.where(
          'startAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(normalizedFrom),
        );
      }

      final snap = await query.limit(1).get();
      return snap.docs.isNotEmpty;
    } catch (e) {
      if (!_isMissingIndex(e)) rethrow;

      final scanned = await _scanSlotsForTerm(
        schoolYearId: normalizedSchoolYearId,
        termId: normalizedTermId,
      );
      for (final doc in scanned) {
        final startAt = (doc.data()['startAt'] as Timestamp?)?.toDate();
        if (startAt == null) continue;
        if (normalizedFrom == null || !startAt.isBefore(normalizedFrom)) {
          return true;
        }
      }
      return false;
    }
  }

  Future<void> _deleteOpenSlotsForTerm({
    required String schoolYearId,
    required String termId,
    DateTime? fromDate,
  }) async {
    final normalizedSchoolYearId = schoolYearId.trim();
    final normalizedTermId = termId.trim();
    final normalizedFrom = fromDate == null
        ? null
        : DateTime(fromDate.year, fromDate.month, fromDate.day);

    List<QueryDocumentSnapshot<Map<String, dynamic>>> docsToDelete;
    try {
      Query<Map<String, dynamic>> query = _slots
          .where('schoolYearId', isEqualTo: normalizedSchoolYearId)
          .where('termId', isEqualTo: normalizedTermId)
          .where('status', isEqualTo: OsaMeetingSlotStatus.open);

      if (normalizedFrom != null) {
        query = query.where(
          'startAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(normalizedFrom),
        );
      }
      final existing = await query.get();
      docsToDelete = existing.docs;
    } catch (e) {
      if (!_isMissingIndex(e)) rethrow;
      final scanned = await _scanSlotsForTerm(
        schoolYearId: normalizedSchoolYearId,
        termId: normalizedTermId,
      );
      docsToDelete = scanned.where((doc) {
        final data = doc.data();
        if ((data['status'] ?? '') != OsaMeetingSlotStatus.open) return false;
        if (normalizedFrom == null) return true;
        final startAt = (data['startAt'] as Timestamp?)?.toDate();
        if (startAt == null) return false;
        return !startAt.isBefore(normalizedFrom);
      }).toList();
    }

    var deleteBatch = _db.batch();
    var deleteCount = 0;
    for (final doc in docsToDelete) {
      deleteBatch.delete(doc.reference);
      deleteCount++;
      if (deleteCount == 400) {
        await deleteBatch.commit();
        deleteBatch = _db.batch();
        deleteCount = 0;
      }
    }
    if (deleteCount > 0) {
      await deleteBatch.commit();
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _scanSlotsForTerm({
    required String schoolYearId,
    required String termId,
  }) async {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    Query<Map<String, dynamic>> query = _slots
        .orderBy(FieldPath.documentId)
        .limit(500);

    while (true) {
      final snap = await query.get();
      if (snap.docs.isEmpty) break;

      for (final doc in snap.docs) {
        final data = doc.data();
        if ((data['schoolYearId'] ?? '').toString() != schoolYearId) continue;
        if ((data['termId'] ?? '').toString() != termId) continue;
        out.add(doc);
      }

      if (snap.docs.length < 500) break;
      query = query.startAfterDocument(snap.docs.last);
    }

    return out;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamOpenSlots({
    required String schoolYearId,
    required String termId,
    int limit = 200,
  }) {
    return _slots
        .where('schoolYearId', isEqualTo: schoolYearId.trim())
        .where('termId', isEqualTo: termId.trim())
        .where('status', isEqualTo: OsaMeetingSlotStatus.open)
        .orderBy('startAt')
        .limit(limit)
        .snapshots();
  }

  Future<int> countOpenSlotsInRange({
    required String schoolYearId,
    required String termId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int hardCap = 2000,
  }) async {
    if (rangeEnd.isBefore(rangeStart)) return 0;

    final normalizedSchoolYearId = schoolYearId.trim();
    final normalizedTermId = termId.trim();
    final from = Timestamp.fromDate(rangeStart);
    final to = Timestamp.fromDate(rangeEnd);

    try {
      final snap = await _slots
          .where('schoolYearId', isEqualTo: normalizedSchoolYearId)
          .where('termId', isEqualTo: normalizedTermId)
          .where('status', isEqualTo: OsaMeetingSlotStatus.open)
          .where('startAt', isGreaterThanOrEqualTo: from)
          .where('startAt', isLessThanOrEqualTo: to)
          .limit(hardCap)
          .get();
      return snap.docs.length;
    } catch (e) {
      if (!_isMissingIndex(e)) rethrow;

      final scanned = await _scanSlotsForTerm(
        schoolYearId: normalizedSchoolYearId,
        termId: normalizedTermId,
      );
      var count = 0;
      for (final doc in scanned) {
        final data = doc.data();
        if ((data['status'] ?? '') != OsaMeetingSlotStatus.open) continue;
        final startAt = (data['startAt'] as Timestamp?)?.toDate();
        if (startAt == null) continue;
        if (startAt.isBefore(rangeStart)) continue;
        if (startAt.isAfter(rangeEnd)) continue;
        count++;
        if (count >= hardCap) break;
      }
      return count;
    }
  }

  Future<void> bookSlotForCase({
    required String slotId,
    required String caseId,
    required String studentUid,
  }) async {
    final slotRef = _slots.doc(slotId);
    final caseRef = _cases.doc(caseId);
    final user = FirebaseAuth.instance.currentUser;
    final actorUid = user?.uid;

    await _db.runTransaction((tx) async {
      final slotSnap = await tx.get(slotRef);
      if (!slotSnap.exists) throw Exception('Slot not found');
      final slotData = slotSnap.data() ?? {};
      if ((slotData['status'] ?? '') != OsaMeetingSlotStatus.open) {
        throw Exception('Slot is no longer available');
      }

      final caseSnap = await tx.get(caseRef);
      if (!caseSnap.exists) throw Exception('Case not found');
      final caseData = caseSnap.data() ?? {};
      final caseStudentUid = (caseData['studentUid'] ?? '').toString().trim();
      if (caseStudentUid.isNotEmpty && caseStudentUid != studentUid.trim()) {
        throw Exception('This case does not belong to the current student.');
      }
      final meetingRequired = caseData['meetingRequired'] == true;
      if (!meetingRequired) {
        throw Exception('Meeting booking is not required for this case.');
      }
      final meetingStatus = (caseData['meetingStatus'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final canBookFromStatus =
          meetingStatus.isEmpty ||
          meetingStatus == 'pending' ||
          meetingStatus == 'pending_student_booking';
      if (!canBookFromStatus) {
        throw Exception('Meeting booking is not open for this case.');
      }

      final startAt = (slotData['startAt'] as Timestamp?)?.toDate();
      final endAt = (slotData['endAt'] as Timestamp?)?.toDate();
      if (startAt == null || endAt == null) {
        throw Exception('Slot has invalid time');
      }
      final nowLocal = DateTime.now();
      if (startAt.isBefore(nowLocal)) {
        throw Exception('Selected slot is already in the past.');
      }
      final earliestAllowedStart = nowLocal.add(bookingLeadTime);
      if (startAt.isBefore(earliestAllowedStart)) {
        throw Exception(
          'Selected slot is too soon. Please book at least ${bookingLeadTime.inHours} hours in advance.',
        );
      }

      final bookingDeadlineAt = (caseData['bookingDeadlineAt'] as Timestamp?)
          ?.toDate();
      if (bookingDeadlineAt != null && nowLocal.isAfter(bookingDeadlineAt)) {
        throw Exception('Booking window has ended for this case.');
      }

      final meetingDueBy = (caseData['meetingDueBy'] as Timestamp?)?.toDate();
      if (meetingDueBy != null && startAt.isAfter(meetingDueBy)) {
        throw Exception(
          'Selected slot is beyond the allowed meeting due date.',
        );
      }

      final maxBookableAt = nowLocal.add(const Duration(days: 14));
      if (startAt.isAfter(maxBookableAt)) {
        throw Exception(
          'Selected slot is too far ahead. Choose within 14 days.',
        );
      }

      tx.update(slotRef, {
        'status': OsaMeetingSlotStatus.booked,
        'caseId': caseId,
        'studentUid': studentUid.trim(),
        'bookedByUid': actorUid,
        'bookedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.update(caseRef, {
        'status': ViolationCaseWorkflow.statusActionSet,
        'workflowStep': ViolationCaseWorkflow.stepMonitoring,
        'workflowAction': ViolationCaseWorkflow.actionMeetingRequired,
        'meetingRequired': true,
        'meetingStatus': 'scheduled',
        'scheduledAt': Timestamp.fromDate(startAt),
        'bookingStatus': 'booked',
        'bookingSlotId': slotId,
        'bookingBookedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid.trim(),
      title: 'Meeting Scheduled',
      body: 'Your OSA meeting slot has been booked.',
      payload: {'meetingStatus': 'scheduled', 'slotId': slotId},
    );
  }

  Future<int> expireOverduePendingBookings({int limit = 300}) async {
    final now = DateTime.now();
    final snap = await _cases
        .where('status', isEqualTo: ViolationCaseWorkflow.statusActionSet)
        .limit(limit)
        .get();

    final overdue = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final graceExtensions = <Map<String, dynamic>>[];
    final scheduledMissed = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['meetingRequired'] != true) continue;

      final status = (data['meetingStatus'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final bookingStatus = (data['bookingStatus'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final pendingBooking =
          status.isEmpty ||
          status == 'pending' ||
          status == 'pending_student_booking';
      final scheduledAt = (data['scheduledAt'] as Timestamp?)?.toDate();
      final booked = status.contains('scheduled') || bookingStatus == 'booked';
      final completed =
          status.contains('completed') || bookingStatus == 'completed';
      final missedAlready = status.contains('missed');

      if (scheduledAt != null &&
          booked &&
          !completed &&
          !missedAlready &&
          now.isAfter(scheduledAt.add(const Duration(hours: 1)))) {
        scheduledMissed.add(doc);
        continue;
      }

      if (!pendingBooking) continue;
      if (scheduledAt != null) continue;

      final bookingDeadlineAt = (data['bookingDeadlineAt'] as Timestamp?)
          ?.toDate();
      final meetingDueBy = (data['meetingDueBy'] as Timestamp?)?.toDate();
      final deadline = bookingDeadlineAt ?? meetingDueBy;
      if (deadline == null || now.isBefore(deadline)) continue;

      final graceCount = (data['bookingGraceCount'] as num?)?.toInt() ?? 0;
      if (graceCount < 1) {
        final nextBookingDeadline = now.add(const Duration(days: 2));
        final nextMeetingDueBy =
            (meetingDueBy == null || meetingDueBy.isBefore(nextBookingDeadline))
            ? nextBookingDeadline
            : meetingDueBy;
        graceExtensions.add({
          'doc': doc,
          'nextBookingDeadline': nextBookingDeadline,
          'nextMeetingDueBy': nextMeetingDueBy,
          'nextGraceCount': graceCount + 1,
        });
      } else {
        overdue.add(doc);
      }
    }

    if (graceExtensions.isNotEmpty) {
      final batch = _db.batch();
      for (final entry in graceExtensions) {
        final doc = entry['doc'] as QueryDocumentSnapshot<Map<String, dynamic>>;
        final nextBookingDeadline = entry['nextBookingDeadline'] as DateTime;
        final nextMeetingDueBy = entry['nextMeetingDueBy'] as DateTime;
        final nextGraceCount = entry['nextGraceCount'] as int;
        batch.update(doc.reference, {
          'meetingStatus': 'pending_student_booking',
          'bookingStatus': 'pending',
          'bookingGraceCount': nextGraceCount,
          'bookingGraceExtendedAt': FieldValue.serverTimestamp(),
          'bookingDeadlineAt': Timestamp.fromDate(nextBookingDeadline),
          'meetingDueBy': Timestamp.fromDate(nextMeetingDueBy),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    if (overdue.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in overdue) {
        batch.update(doc.reference, {
          'meetingStatus': 'booking_missed',
          'bookingStatus': 'missed',
          'bookingMissedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    if (scheduledMissed.isNotEmpty) {
      final caseBatch = _db.batch();
      final slotBatch = _db.batch();
      var hasSlotUpdates = false;
      for (final doc in scheduledMissed) {
        final data = doc.data();
        final slotId = (data['bookingSlotId'] ?? '').toString().trim();

        caseBatch.update(doc.reference, {
          'status': ViolationCaseWorkflow.statusUnresolved,
          'workflowStep': ViolationCaseWorkflow.stepMonitoring,
          'workflowAction': ViolationCaseWorkflow.actionMeetingRequired,
          'meetingStatus': 'meeting_missed',
          'bookingStatus': 'missed',
          'meetingMissedAt': FieldValue.serverTimestamp(),
          'unresolvedAt': FieldValue.serverTimestamp(),
          'unresolvedReason': 'meeting_absence',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (slotId.isNotEmpty) {
          hasSlotUpdates = true;
          slotBatch.set(_slots.doc(slotId), {
            'status': OsaMeetingSlotStatus.missed,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
      await caseBatch.commit();
      if (hasSlotUpdates) {
        await slotBatch.commit();
      }
    }

    for (final entry in graceExtensions) {
      final doc = entry['doc'] as QueryDocumentSnapshot<Map<String, dynamic>>;
      final data = doc.data();
      final studentUid = (data['studentUid'] ?? '').toString().trim();
      final caseCode = (data['caseCode'] ?? doc.id).toString();
      await _notifyStudent(
        caseId: doc.id,
        studentUid: studentUid,
        title: 'Booking Window Extended',
        body:
            'You still have 2 more days to book your OSA meeting slot for case $caseCode.',
        payload: const {'meetingStatus': 'pending_student_booking'},
      );
    }

    for (final doc in overdue) {
      final data = doc.data();
      final studentUid = (data['studentUid'] ?? '').toString().trim();
      final caseCode = (data['caseCode'] ?? doc.id).toString();
      await _notifyStudent(
        caseId: doc.id,
        studentUid: studentUid,
        title: 'Booking Window Missed',
        body:
            'You did not book an OSA meeting slot within the allowed 5-day window for case $caseCode. Please wait for OSA follow-up.',
        payload: const {'meetingStatus': 'booking_missed'},
      );
    }

    for (final doc in scheduledMissed) {
      final data = doc.data();
      final studentUid = (data['studentUid'] ?? '').toString().trim();
      final caseCode = (data['caseCode'] ?? doc.id).toString();
      await _notifyStudent(
        caseId: doc.id,
        studentUid: studentUid,
        title: 'Meeting Missed',
        body:
            'You did not attend the scheduled OSA meeting for case $caseCode. The case is now marked unresolved.',
        payload: const {
          'status': ViolationCaseWorkflow.statusUnresolved,
          'meetingStatus': 'meeting_missed',
        },
      );
    }

    return graceExtensions.length + overdue.length + scheduledMissed.length;
  }

  Future<void> markMeetingMissed({
    required String slotId,
    required String caseId,
    required String studentUid,
  }) async {
    final actorUid = FirebaseAuth.instance.currentUser?.uid;

    await _slots.doc(slotId).set({
      'status': OsaMeetingSlotStatus.missed,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _cases.doc(caseId).set({
      'status': ViolationCaseWorkflow.statusUnresolved,
      'workflowStep': ViolationCaseWorkflow.stepMonitoring,
      'workflowAction': ViolationCaseWorkflow.actionMeetingRequired,
      'meetingStatus': 'meeting_missed',
      'bookingStatus': 'missed',
      'meetingMissedAt': FieldValue.serverTimestamp(),
      'unresolvedAt': FieldValue.serverTimestamp(),
      'unresolvedByUid': actorUid,
      'unresolvedReason': 'meeting_absence',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _notifyStudent(
      caseId: caseId,
      studentUid: studentUid.trim(),
      title: 'Meeting Missed',
      body:
          'Your OSA meeting was marked missed. The case is now unresolved until OSA takes follow-up action.',
      payload: {
        'status': ViolationCaseWorkflow.statusUnresolved,
        'meetingStatus': 'meeting_missed',
        'slotId': slotId,
      },
    );
  }

  Future<void> closeOpenSlot({required String slotId}) async {
    final slotRef = _slots.doc(slotId);
    final actorUid = FirebaseAuth.instance.currentUser?.uid;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(slotRef);
      if (!snap.exists) {
        throw Exception('Slot not found.');
      }
      final data = snap.data() ?? {};
      if ((data['status'] ?? '') != OsaMeetingSlotStatus.open) {
        throw Exception('Only open slots can be closed.');
      }

      tx.update(slotRef, {
        'status': OsaMeetingSlotStatus.cancelled,
        'closedByUid': actorUid,
        'closedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> releaseBookedSlot({
    required String slotId,
    required String caseId,
  }) async {
    final slotRef = _slots.doc(slotId);
    final caseRef = _cases.doc(caseId);

    await _db.runTransaction((tx) async {
      final slotSnap = await tx.get(slotRef);
      if (!slotSnap.exists) throw Exception('Slot not found');

      tx.update(slotRef, {
        'status': OsaMeetingSlotStatus.open,
        'caseId': null,
        'studentUid': null,
        'bookedByUid': null,
        'bookedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.update(caseRef, {
        'meetingStatus': 'pending_student_booking',
        'bookingStatus': 'pending',
        'scheduledAt': null,
        'bookingSlotId': null,
        'bookingBookedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  String _slotDocId({
    required String schoolYearId,
    required String termId,
    required DateTime slotStart,
  }) {
    return '${schoolYearId}_${termId}_${slotStart.toUtc().millisecondsSinceEpoch}';
  }

  DateTime? _parseTimeOnDate(DateTime day, String? hhmm) {
    if (hhmm == null || hhmm.trim().isEmpty) return null;
    final parts = hhmm.trim().split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  String _weekdayKey(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'mon';
      case DateTime.tuesday:
        return 'tue';
      case DateTime.wednesday:
        return 'wed';
      case DateTime.thursday:
        return 'thu';
      case DateTime.friday:
        return 'fri';
      case DateTime.saturday:
        return 'sat';
      case DateTime.sunday:
      default:
        return 'sun';
    }
  }

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
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

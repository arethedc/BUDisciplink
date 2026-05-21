import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_firestore.dart';
import 'osa_meeting_schedule_service.dart';

class OsaSetupStatus {
  final String activeSchoolYearId;
  final String activeTermId;
  final bool hasViolationCategories;
  final bool hasViolationTypes;
  final bool hasSanctionTypes;
  final bool hasActionTypes;
  final bool hasActiveSchoolYear;
  final bool hasActiveTerm;
  final bool hasMeetingScheduleTemplate;
  final bool hasMeetingScheduleSlots;

  const OsaSetupStatus({
    required this.activeSchoolYearId,
    required this.activeTermId,
    required this.hasViolationCategories,
    required this.hasViolationTypes,
    required this.hasSanctionTypes,
    required this.hasActionTypes,
    required this.hasActiveSchoolYear,
    required this.hasActiveTerm,
    required this.hasMeetingScheduleTemplate,
    required this.hasMeetingScheduleSlots,
  });

  bool get hasViolationSetup =>
      hasViolationCategories &&
      hasViolationTypes &&
      hasSanctionTypes &&
      hasActionTypes;

  bool get hasMeetingScheduleSetup =>
      !hasActiveSchoolYear ||
      (hasActiveTerm &&
          (hasMeetingScheduleTemplate || hasMeetingScheduleSlots));

  bool get isComplete => hasViolationSetup && hasMeetingScheduleSetup;
}

class OsaSetupStatusService {
  OsaSetupStatusService({
    FirebaseFirestore? db,
    OsaMeetingScheduleService? meetingScheduleService,
  }) : _db = db ?? AppFirestore.instance,
       _meetingScheduleService =
           meetingScheduleService ?? OsaMeetingScheduleService();

  final FirebaseFirestore _db;
  final OsaMeetingScheduleService _meetingScheduleService;

  Future<OsaSetupStatus> load() async {
    final results = await Future.wait<Object?>([
      _db
          .collection('violation_categories')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get(),
      _db
          .collection('violation_types')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get(),
      _db
          .collection('sanction_types')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get(),
      _db
          .collection('action_types')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get(),
      _db
          .collection('academic_years')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get(),
    ]);

    final categoriesSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final typesSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final sanctionsSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final actionsSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final activeYearSnap = results[4] as QuerySnapshot<Map<String, dynamic>>;

    final hasActiveSchoolYear = activeYearSnap.docs.isNotEmpty;
    final activeYearDoc = hasActiveSchoolYear
        ? activeYearSnap.docs.first
        : null;
    final activeTermId = hasActiveSchoolYear
        ? (activeYearDoc?.data()['activeTermId'] ?? '').toString().trim()
        : '';

    var hasMeetingScheduleTemplate = false;
    var hasMeetingScheduleSlots = false;
    if (hasActiveSchoolYear && activeTermId.isNotEmpty) {
      final template = await _meetingScheduleService.getTermScheduleTemplate(
        schoolYearId: activeYearDoc!.id,
        termId: activeTermId,
      );
      hasMeetingScheduleTemplate = template != null;
      hasMeetingScheduleSlots = await _meetingScheduleService.hasSlotsForTerm(
        schoolYearId: activeYearDoc.id,
        termId: activeTermId,
      );
    }

    return OsaSetupStatus(
      activeSchoolYearId: hasActiveSchoolYear ? activeYearDoc!.id : '',
      activeTermId: activeTermId,
      hasViolationCategories: categoriesSnap.docs.isNotEmpty,
      hasViolationTypes: typesSnap.docs.isNotEmpty,
      hasSanctionTypes: sanctionsSnap.docs.isNotEmpty,
      hasActionTypes: actionsSnap.docs.isNotEmpty,
      hasActiveSchoolYear: hasActiveSchoolYear,
      hasActiveTerm: activeTermId.isNotEmpty,
      hasMeetingScheduleTemplate: hasMeetingScheduleTemplate,
      hasMeetingScheduleSlots: hasMeetingScheduleSlots,
    );
  }
}

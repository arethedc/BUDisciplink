import 'academic_settings_service.dart';
import 'counseling_setup_service.dart';
import 'osa_meeting_schedule_service.dart';

class CounselingSetupStatus {
  final bool hasCounselingGroups;
  final bool hasCounselingItems;
  final bool hasCounselingSetup;
  final String activeSchoolYearId;
  final String activeTermId;
  final bool hasActiveSchoolYear;
  final bool hasActiveTerm;
  final bool hasMeetingScheduleTemplate;
  final bool hasMeetingScheduleSlots;

  const CounselingSetupStatus({
    required this.hasCounselingGroups,
    required this.hasCounselingItems,
    required this.hasCounselingSetup,
    required this.activeSchoolYearId,
    required this.activeTermId,
    required this.hasActiveSchoolYear,
    required this.hasActiveTerm,
    required this.hasMeetingScheduleTemplate,
    required this.hasMeetingScheduleSlots,
  });

  bool get hasMeetingScheduleSetup =>
      !hasActiveSchoolYear ||
      (hasActiveTerm &&
          (hasMeetingScheduleTemplate || hasMeetingScheduleSlots));

  bool get isComplete => hasCounselingSetup && hasMeetingScheduleSetup;
}

class CounselingSetupStatusService {
  CounselingSetupStatusService({
    CounselingSetupService? counselingSetupService,
    AcademicSettingsService? academicSettingsService,
    OsaMeetingScheduleService? meetingScheduleService,
  }) : _counselingSetupService =
           counselingSetupService ?? CounselingSetupService(),
       _academicSettingsService =
           academicSettingsService ?? AcademicSettingsService(),
       _meetingScheduleService =
           meetingScheduleService ??
           OsaMeetingScheduleService(
             templateCollection: 'counseling_schedule_templates',
             slotCollection: 'counseling_meeting_slots',
             caseCollection: 'counseling_cases',
           );

  final CounselingSetupService _counselingSetupService;
  final AcademicSettingsService _academicSettingsService;
  final OsaMeetingScheduleService _meetingScheduleService;

  Future<CounselingSetupStatus> load() async {
    final config = await _counselingSetupService.getConfig();
    final activeSy = await _academicSettingsService.getActiveSY();
    final hasActiveSchoolYear = activeSy != null;
    final activeSchoolYearId = hasActiveSchoolYear
        ? (activeSy['id'] ?? '').toString().trim()
        : '';
    final activeTermId = hasActiveSchoolYear
        ? (activeSy['activeTermId'] ?? '').toString().trim()
        : '';

    var hasMeetingScheduleTemplate = false;
    var hasMeetingScheduleSlots = false;
    if (hasActiveSchoolYear && activeTermId.isNotEmpty) {
      final template = await _meetingScheduleService.getTermScheduleTemplate(
        schoolYearId: activeSchoolYearId,
        termId: activeTermId,
      );
      hasMeetingScheduleTemplate = template != null;
      hasMeetingScheduleSlots = await _meetingScheduleService.hasSlotsForTerm(
        schoolYearId: activeSchoolYearId,
        termId: activeTermId,
      );
    }

    return CounselingSetupStatus(
      hasCounselingGroups: config.hasAnyActiveGroups,
      hasCounselingItems: config.hasAnyActiveItems,
      hasCounselingSetup: config.hasMinimumCounselingSetup,
      activeSchoolYearId: activeSchoolYearId,
      activeTermId: activeTermId,
      hasActiveSchoolYear: hasActiveSchoolYear,
      hasActiveTerm: activeTermId.isNotEmpty,
      hasMeetingScheduleTemplate: hasMeetingScheduleTemplate,
      hasMeetingScheduleSlots: hasMeetingScheduleSlots,
    );
  }
}

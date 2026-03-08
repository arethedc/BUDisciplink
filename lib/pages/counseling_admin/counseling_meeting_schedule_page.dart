import 'package:apps/pages/osa_admin/meeting_schedule_page.dart';
import 'package:apps/services/osa_meeting_schedule_service.dart';
import 'package:flutter/material.dart';

class CounselingMeetingSchedulePage extends StatelessWidget {
  const CounselingMeetingSchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MeetingSchedulePage(
      title: 'Counseling Meeting Schedule',
      service: OsaMeetingScheduleService(
        templateCollection: 'counseling_schedule_templates',
        slotCollection: 'counseling_meeting_slots',
        caseCollection: 'counseling_cases',
      ),
    );
  }
}

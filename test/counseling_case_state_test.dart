import 'package:apps/services/counseling_case_workflow_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CounselingCaseState', () {
    test('detects awaiting call slip for professor referral', () {
      final data = <String, dynamic>{
        'referralSource': 'professor',
        'callSlipStatus': 'pending',
        'workflowStatus': 'submitted',
        'meetingStatus': 'awaiting_call_slip',
      };

      expect(CounselingCaseState.isAwaitingCallSlip(data), isTrue);
      expect(CounselingCaseState.statusLabel(data), 'Awaiting Call Slip');
    });

    test('detects booking required', () {
      final data = <String, dynamic>{
        'workflowStatus': 'booking_required',
        'meetingStatus': 'pending_student_booking',
        'bookingStatus': 'pending',
      };

      expect(CounselingCaseState.isBookingRequired(data), isTrue);
      expect(CounselingCaseState.statusLabel(data), 'Booking Required');
    });

    test('detects scheduled status', () {
      final data = <String, dynamic>{
        'workflowStatus': 'booked',
        'meetingStatus': 'scheduled',
        'bookingStatus': 'booked',
      };

      expect(CounselingCaseState.isScheduled(data), isTrue);
      expect(CounselingCaseState.statusLabel(data), 'Scheduled');
    });

    test('detects missed status', () {
      final data = <String, dynamic>{
        'workflowStatus': 'missed',
        'meetingStatus': 'meeting_missed',
        'bookingStatus': 'missed',
      };

      expect(CounselingCaseState.isMissed(data), isTrue);
      expect(CounselingCaseState.statusLabel(data), 'Missed - Rebook Required');
    });

    test('detects completed and closed', () {
      final data = <String, dynamic>{
        'status': 'completed',
        'workflowStatus': 'completed',
        'meetingStatus': 'completed',
        'bookingStatus': 'completed',
      };

      expect(CounselingCaseState.isCompleted(data), isTrue);
      expect(CounselingCaseState.isClosed(data), isTrue);
      expect(CounselingCaseState.statusLabel(data), 'Completed');
    });
  });
}

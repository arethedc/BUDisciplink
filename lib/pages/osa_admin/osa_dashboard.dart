import 'package:apps/pages/shared/handbook/hb_handbook_page.dart';
import 'package:apps/pages/shared/notifications/app_notifications_ui.dart';
import 'package:apps/pages/shared/profile/unified_profile_page.dart';
import 'package:apps/pages/shared/widgets/app_theme_tokens.dart';
import 'package:apps/pages/shared/widgets/app_branding.dart';
import 'package:apps/pages/shared/widgets/logout_confirm_dialog.dart';
import 'package:apps/pages/shared/widgets/responsive_layout_tokens.dart';
import 'package:apps/pages/shared/widgets/role_shell_scaffold.dart';
import 'package:apps/pages/shared/widgets/unsaved_changes_guard.dart';
import 'package:apps/services/app_router.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apps/pages/osa_admin/osa_home_page.dart';

// Settings sub-pages (adjust paths to your project)
import 'handbook_workflow_page.dart';
import 'handbook_docs_editor_page.dart';
import 'meeting_schedule_page.dart';
import '../professor/professor_counseling_page.dart';
import '../professor/MySubmittedReportPage.dart';
import '../professor/violation_report_page.dart';
import 'violation_analytics_page.dart';
import 'violation_records_page.dart';
import 'violation_types_page.dart';
import 'osa_violation_review_page.dart';
import 'package:apps/services/app_firestore.dart';
import 'package:apps/services/osa_setup_status_service.dart';

class OsaDashboard extends StatefulWidget {
  final String section;
  final String? initialSelectedCaseCode;
  final String? initialSelectedReviewCaseCode;
  final bool reviewInboxOnOpen;
  final String? recordsPreset;
  final String? tabDeepLink;
  final String? handbookSectionId;
  final String? handbookHighlightText;

  const OsaDashboard({
    super.key,
    this.section = 'dashboard',
    this.initialSelectedCaseCode,
    this.initialSelectedReviewCaseCode,
    this.reviewInboxOnOpen = false,
    this.recordsPreset,
    this.tabDeepLink,
    this.handbookSectionId,
    this.handbookHighlightText,
  });

  static const _sectionToIndex = <String, int>{
    'dashboard': 0,
    'handbook': 1,
    'records': 2,
    'setup': 3,
    'meeting-schedule': 4,
    'handbook-workflow': 5,
    'profile': 6,
    'analytics': 7,
    'review': 8,
    'handbook-editor': 9,
    'report': 10,
    'counseling': 11,
    'my-reports': 12,
    'notifications': 13,
  };

  static const _indexToSection = <int, String>{
    0: 'dashboard',
    1: 'handbook',
    2: 'records',
    3: 'setup',
    4: 'meeting-schedule',
    5: 'handbook-workflow',
    6: 'profile',
    7: 'analytics',
    8: 'review',
    9: 'handbook-editor',
    10: 'report',
    11: 'counseling',
    12: 'my-reports',
    13: 'notifications',
  };

  static int indexForSection(String section) => _sectionToIndex[section] ?? 0;

  static String sectionForIndex(int index) =>
      _indexToSection[index] ?? 'dashboard';

  static String pathForSection(String section, {Map<String, String>? query}) {
    final base = AppRoutes.withSection(AppRoutes.osaAdmin, section);
    if (query == null || query.isEmpty) return base;
    return Uri(path: base, queryParameters: query).toString();
  }

  @override
  State<OsaDashboard> createState() => _OsaDashboardState();
}

class _OsaDashboardState extends State<OsaDashboard> {
  static final Map<String, String> _sessionTabBySection = <String, String>{};
  late int _currentIndex;
  int _previousIndexBeforeNotifications = 0;
  bool _showDesktopNotifications = false;
  bool _osaSetupChecked = false;
  bool _meetingScheduleModalShown = false;
  ViolationRecordsFilterPreset? _recordsPreset;
  int _recordsPresetVersion = 0;
  final int _violationReviewReloadToken = 0;
  int _handbookEditorReloadToken = 0;
  String? _preselectedViolationCaseCode;
  String? _preselectedReviewCaseCode;
  bool _forceReviewInboxOnOpen = false;
  static const int _myReportsIndex = 12;
  static const int _notificationsIndex = 13;
  final _violationUnsaved = UnsavedChangesController();
  final _counselingUnsaved = UnsavedChangesController();
  final _handbookEditorUnsaved = UnsavedChangesController();

  // Settings section open/close
  bool _settingsOpen = false;

  // ================== THEME (match reference dashboard) ==================
  static const bg = AppColors.background;
  static const primary = AppColors.primary;
  static const hint = AppColors.hint;
  static const textDark = AppColors.textDark;
  static const surface = AppColors.surface;

  @override
  void initState() {
    super.initState();
    _currentIndex = OsaDashboard.indexForSection(widget.section);
    _preselectedViolationCaseCode =
        (widget.initialSelectedCaseCode ?? '').trim().isEmpty
        ? null
        : widget.initialSelectedCaseCode!.trim();
    _preselectedReviewCaseCode =
        (widget.initialSelectedReviewCaseCode ?? '').trim().isEmpty
        ? null
        : widget.initialSelectedReviewCaseCode!.trim();
    _forceReviewInboxOnOpen = widget.reviewInboxOnOpen;
    _recordsPreset = _presetFromQuery(widget.recordsPreset);
    if (_recordsPreset != null) {
      _recordsPresetVersion++;
    }
    final incomingTab = (widget.tabDeepLink ?? '').trim();
    final incomingSection = widget.section.trim();
    if (incomingTab.isNotEmpty &&
        (incomingSection == 'setup' ||
            incomingSection == 'review' ||
            incomingSection == 'my-reports')) {
      _sessionTabBySection[incomingSection] = incomingTab;
    }
    _settingsOpen = _currentIndex >= 3 && _currentIndex <= 5;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSectionTabQuery();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowOsaSetupModal();
    });
  }

  @override
  void didUpdateWidget(covariant OsaDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = OsaDashboard.indexForSection(widget.section);
    final nextCaseCode = (widget.initialSelectedCaseCode ?? '').trim();
    final nextReviewCaseCode = (widget.initialSelectedReviewCaseCode ?? '')
        .trim();
    final nextPreset = _presetFromQuery(widget.recordsPreset);
    final presetChanged = widget.recordsPreset != oldWidget.recordsPreset;
    if (_currentIndex != nextIndex ||
        (_preselectedViolationCaseCode ?? '') != nextCaseCode ||
        (_preselectedReviewCaseCode ?? '') != nextReviewCaseCode ||
        _forceReviewInboxOnOpen != widget.reviewInboxOnOpen ||
        presetChanged) {
      setState(() {
        _currentIndex = nextIndex;
        _settingsOpen = _currentIndex >= 3 && _currentIndex <= 5;
        _preselectedViolationCaseCode = nextCaseCode.isEmpty
            ? null
            : nextCaseCode;
        _preselectedReviewCaseCode = nextReviewCaseCode.isEmpty
            ? null
            : nextReviewCaseCode;
        _forceReviewInboxOnOpen = widget.reviewInboxOnOpen;
        if (presetChanged) {
          _recordsPreset = nextPreset;
          _recordsPresetVersion++;
        }
      });
    }
    final incomingTab = (widget.tabDeepLink ?? '').trim();
    final incomingSection = widget.section.trim();
    if (incomingTab.isNotEmpty &&
        (incomingSection == 'setup' ||
            incomingSection == 'review' ||
            incomingSection == 'my-reports')) {
      _sessionTabBySection[incomingSection] = incomingTab;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSectionTabQuery();
    });
  }

  ViolationRecordsFilterPreset? _presetFromQuery(String? rawPreset) {
    final preset = (rawPreset ?? '').trim().toLowerCase();
    switch (preset) {
      case 'under_review':
        return const ViolationRecordsFilterPreset(outcome: 'Under Review');
      case 'action_set':
        return const ViolationRecordsFilterPreset(outcome: 'Action Set');
      case 'resolved':
        return const ViolationRecordsFilterPreset(outcome: 'Resolved');
      case 'unresolved':
        return const ViolationRecordsFilterPreset(outcome: 'Unresolved');
      default:
        return null;
    }
  }

  String? _presetQueryFromPreset(ViolationRecordsFilterPreset? preset) {
    final raw = (preset?.outcome ?? '').trim().toLowerCase();
    switch (raw) {
      case 'under review':
      case 'under_review':
        return 'under_review';
      case 'action set':
      case 'action_set':
        return 'action_set';
      case 'resolved':
        return 'resolved';
      case 'unresolved':
        return 'unresolved';
      default:
        return null;
    }
  }

  Future<OsaSetupStatus?> _loadOsaSetupStatus() async {
    try {
      return await OsaSetupStatusService().load();
    } catch (error) {
      debugPrint('Failed to load OSA setup status: $error');
      return null;
    }
  }

  String _meetingScheduleReminderKey(String userId) {
    return 'osa_meeting_schedule_seen_term_$userId';
  }

  Future<String?> _loadLastSeenMeetingScheduleKey(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_meetingScheduleReminderKey(userId));
  }

  Future<void> _markMeetingScheduleSeen({
    required String userId,
    required OsaSetupStatus status,
  }) async {
    final schoolYearId = status.activeSchoolYearId.trim();
    final termId = status.activeTermId.trim();
    if (schoolYearId.isEmpty || termId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _meetingScheduleReminderKey(userId),
      '$schoolYearId::$termId',
    );
  }

  Future<void> _maybeShowOsaSetupModal() async {
    if (_osaSetupChecked || !mounted || _currentIndex != 0) return;
    _osaSetupChecked = true;

    final status = await _loadOsaSetupStatus();
    if (!mounted || status == null || _currentIndex != 0) return;

    if (!status.hasViolationSetup) {
      await _showViolationSetupModal(status);
    }

    if (!mounted || _currentIndex != 0) return;
    await _maybeShowMeetingScheduleModalIfNeeded(status: status);
  }

  Future<void> _maybeShowMeetingScheduleModalIfNeeded({
    OsaSetupStatus? status,
  }) async {
    if (_meetingScheduleModalShown || !mounted || _currentIndex != 0) return;
    final resolvedStatus = status ?? await _loadOsaSetupStatus();
    if (!mounted || resolvedStatus == null || _currentIndex != 0) return;
    if (!resolvedStatus.hasActiveSchoolYear ||
        resolvedStatus.activeTermId.trim().isEmpty) {
      return;
    }
    if (resolvedStatus.hasMeetingScheduleSetup) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final currentKey =
        '${resolvedStatus.activeSchoolYearId}::${resolvedStatus.activeTermId}';
    final lastSeenKey = await _loadLastSeenMeetingScheduleKey(user.uid);
    if (lastSeenKey == currentKey) return;

    _meetingScheduleModalShown = true;
    await _showMeetingScheduleModal(resolvedStatus);
    await _markMeetingScheduleSeen(userId: user.uid, status: resolvedStatus);
  }

  Future<void> _showViolationSetupModal(OsaSetupStatus status) async {
    await _showSetupDialog(
      title: 'Violation setup required',
      subtitle:
          'Complete the setup below so reviews and outcomes stay consistent.',
      icon: Icons.checklist_rtl_rounded,
      sections: [
        _buildSetupSection(
          title: 'Violation setup',
          subtitle:
              'These items keep reviews, resolutions, and outcomes consistent.',
          children: [
            _buildSetupChecklistRow(
              label: 'Violation categories',
              ready: status.hasViolationCategories,
              missingHint: 'Create at least one active violation category.',
            ),
            const SizedBox(height: 8),
            _buildSetupChecklistRow(
              label: 'Specific violation types',
              ready: status.hasViolationTypes,
              missingHint:
                  'Add active specific violation types under the categories.',
            ),
            const SizedBox(height: 8),
            _buildSetupChecklistRow(
              label: 'Sanction types',
              ready: status.hasSanctionTypes,
              missingHint: 'Add active sanction types for case outcomes.',
            ),
            const SizedBox(height: 8),
            _buildSetupChecklistRow(
              label: 'Action types',
              ready: status.hasActionTypes,
              missingHint: 'Add active action types for case handling.',
            ),
          ],
        ),
      ],
      primaryLabel: 'Open Violation Setup',
      primaryIcon: Icons.open_in_new_rounded,
      onPrimaryPressed: () => _go(3),
    );
  }

  Future<void> _showMeetingScheduleModal(OsaSetupStatus status) async {
    await _showSetupDialog(
      title: 'Meeting schedule required',
      subtitle:
          'The active semester changed. Confirm the schedule template before students reserve slots.',
      icon: Icons.calendar_month_rounded,
      sections: [
        _buildSetupSection(
          title: 'Meeting schedule',
          subtitle:
              'Use the current semester to keep booking slots aligned with the active term.',
          children: [
            _buildSetupChecklistRow(
              label: 'Active semester',
              ready: status.hasActiveTerm,
              missingHint:
                  'Set an active semester before generating meeting slots.',
            ),
            const SizedBox(height: 8),
            _buildSetupChecklistRow(
              label: 'Meeting schedule template',
              ready: status.hasMeetingScheduleTemplate,
              missingHint:
                  'Create the meeting schedule template for the active term.',
            ),
          ],
        ),
      ],
      primaryLabel: 'Open Meeting Schedule',
      primaryIcon: Icons.open_in_new_rounded,
      onPrimaryPressed: () => _go(4),
    );
  }

  Future<void> _showSetupDialog({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> sections,
    required String primaryLabel,
    required IconData primaryIcon,
    required VoidCallback onPrimaryPressed,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: primary.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Icon(icon, color: primary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: primary,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: hint,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ...sections,
                  const SizedBox(height: 18),
                  _buildSetupDialogActions(
                    dialogContext: dialogContext,
                    primaryLabel: primaryLabel,
                    primaryIcon: primaryIcon,
                    onPrimaryPressed: () {
                      Navigator.of(dialogContext).pop();
                      onPrimaryPressed();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSetupDialogActions({
    required BuildContext dialogContext,
    required String primaryLabel,
    required IconData primaryIcon,
    required VoidCallback onPrimaryPressed,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 640;
        final primaryButton = FilledButton.icon(
          onPressed: onPrimaryPressed,
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          icon: Icon(primaryIcon, size: 18),
          label: Text(
            primaryLabel,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text(
                      'Later',
                      style: TextStyle(
                        color: hint,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: primaryButton),
            ],
          );
        }

        return Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Later',
                style: TextStyle(color: hint, fontWeight: FontWeight.w900),
              ),
            ),
            const Spacer(),
            primaryButton,
          ],
        );
      },
    );
  }

  Widget _buildSetupSection({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: hint,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSetupChecklistRow({
    required String label,
    required bool ready,
    required String missingHint,
  }) {
    final color = ready ? const Color(0xFF2F855A) : const Color(0xFFC53030);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: ready
                ? const Color(0xFF2F855A).withValues(alpha: 0.10)
                : const Color(0xFFC53030).withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Icon(
            ready ? Icons.check_rounded : Icons.close_rounded,
            size: 14,
            color: color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ready ? 'Ready' : missingHint,
                style: TextStyle(
                  color: ready ? const Color(0xFF2F855A) : hint,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.2,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================== PAGES ==================
  // Keep as a getter so hot reload reflects changes (initState doesn't rerun).
  List<Widget> get _pages => [
    OsaHomePage(
      onOpenAcademicSettings: () => _goSettings(3),
      onOpenViolationReview: () =>
          _openViolationReviewAsync(toReviewInbox: true),
      onOpenMeetingSchedule: () => _goSettings(4),
      onOpenCase: (caseCode) {
        _openViolationReviewAsync(preselectCaseCode: caseCode);
      },
    ),
    HbHandbookPage(
      useSidebarDesktop: false,
      hideTopHeader: true,
      initialSectionId: widget.handbookSectionId,
      initialHighlightText: widget.handbookHighlightText,
      openSelectedOnMobile: true,
    ),
    ViolationRecordsPage(
      key: ValueKey('violation-records-$_recordsPresetVersion'),
      initialFilterPreset: _recordsPreset,
      initialSelectedCaseCode: _preselectedViolationCaseCode,
    ),

    ViolationTypesPage(
      initialTab: _effectiveTabForSection('setup'),
      onTabChanged: (tabKey) => _syncSectionTab('setup', tabKey),
    ),
    const MeetingSchedulePage(),
    HandbookWorkflowPage(
      onOpenEditorForVersion: (_) {
        setState(() => _handbookEditorReloadToken++);
        context.go(OsaDashboard.pathForSection('handbook-editor'));
      },
    ),
    const UnifiedProfilePage(),
    ViolationAnalyticsPage(
      onOpenRecords: (preset) {
        final presetKey = _presetQueryFromPreset(preset);
        context.go(
          OsaDashboard.pathForSection(
            'records',
            query: presetKey == null
                ? null
                : <String, String>{'preset': presetKey},
          ),
        );
      },
    ),
    OsaViolationReviewPage(
      key: ValueKey('osa-review-$_violationReviewReloadToken'),
      initialSelectedCaseCode: _preselectedReviewCaseCode,
      initialTab: _effectiveTabForSection('review'),
      forceReviewInboxOnOpen: _forceReviewInboxOnOpen,
      onOpenReportViolation: _openViolationReportModal,
      onOpenCounselingReferral: _openCounselingReferralModal,
      onTabChanged: (tabKey) => _syncSectionTab('review', tabKey),
    ),
    HandbookDocsEditorPage(
      key: ValueKey('hb-editor-$_handbookEditorReloadToken'),
      unsavedChangesController: _handbookEditorUnsaved,
      onBack: () {
        setState(() {
          _currentIndex = 5;
          _settingsOpen = true;
        });
      },
    ),
    ViolationReportPage(unsavedChangesController: _violationUnsaved),
    ProfessorCounselingPage(unsavedChangesController: _counselingUnsaved),
    MySubmittedCasesPage(
      onOpenViolationReport: () => _go(10),
      onOpenCounselingReferral: () => _go(11),
      initialTab: _effectiveTabForSection('my-reports'),
      onTabChanged: (tabKey) => _syncSectionTab('my-reports', tabKey),
    ),
    AppNotificationsContent(
      onBack: () {
        final backIndex =
            _previousIndexBeforeNotifications == _notificationsIndex
            ? 0
            : _previousIndexBeforeNotifications;
        _go(backIndex);
      },
      onViewNotification: _handleNotificationView,
    ),
  ];

  String? _effectiveTabForSection(String section) {
    if (widget.section == section) {
      final explicit = (widget.tabDeepLink ?? '').trim();
      if (explicit.isNotEmpty) return explicit;
    }
    final remembered = (_sessionTabBySection[section] ?? '').trim();
    return remembered.isEmpty ? null : remembered;
  }

  String _pageTitle() {
    switch (_currentIndex) {
      case 0:
        return "Dashboard";
      case 1:
        return "Student Handbook";
      case 2:
        return "Violation Records";
      case 3:
        return "Violation Setup";

      // Ã¢Å“â€¦ Settings pages
      case 4:
        return "Meeting Schedule";
      case 5:
        return "Manage Handbook";
      case 6:
        return "Profile";
      case 7:
        return "Violation Analytics";
      case 8:
        return "Violation Review";
      case 9:
        return "Manage Handbook";
      case 10:
        return "Report Violation";
      case 11:
        return "Counselling Referral";
      case _myReportsIndex:
        return "My Reports";
      case _notificationsIndex:
        return "Notifications";

      default:
        return "OSA Portal";
    }
  }

  UnsavedChangesController? _controllerForIndex(int index) {
    switch (index) {
      case 10:
        return _violationUnsaved;
      case 11:
        return _counselingUnsaved;
      case 9:
        return _handbookEditorUnsaved;
      default:
        return null;
    }
  }

  Future<bool> _confirmLeaveCurrentPage() async {
    final controller = _controllerForIndex(_currentIndex);
    if (controller == null || !controller.isDirty) return true;
    if (controller.canSave) {
      final choice = await showUnsavedChangesChoiceDialog(
        context,
        title: 'You have unsaved changes',
        message: 'Do you want to save before leaving this page?',
        stayLabel: 'Continue editing',
        discardLabel: 'Discard and leave',
        saveLabel: 'Save and leave',
      );
      if (choice == UnsavedChangesChoice.stay) return false;
      if (choice == UnsavedChangesChoice.discard) {
        controller.discardChanges();
        return true;
      }
      final saved = await controller.saveChanges();
      if (saved) {
        controller.clear();
      }
      return saved;
    }
    final leave = await showUnsavedChangesDialog(
      context,
      title: 'Leave current form?',
      message:
          'You have unsaved changes on this form. If you continue, your draft will be discarded.',
    );
    if (leave) {
      controller.discardChanges();
    }
    return leave;
  }

  Future<void> _logout() async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    final confirmed = await showLogoutConfirmDialog(context);
    if (!mounted || !confirmed) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    context.go('/welcome');
  }

  void _go(int i) {
    _goAsync(i);
  }

  Future<void> _goAsync(int i) async {
    if (i == _currentIndex) return;
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    if (i != _notificationsIndex) {
      _previousIndexBeforeNotifications = i;
    }
    final section = OsaDashboard.sectionForIndex(i);
    final tab = _defaultTabForSection(section);
    final target = OsaDashboard.pathForSection(
      section,
      query: tab == null ? null : <String, String>{'tab': tab},
    );
    if (GoRouterState.of(context).uri.toString() == target) return;
    context.go(target);
    if (i == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_osaSetupChecked) {
          _maybeShowOsaSetupModal();
        } else {
          _maybeShowMeetingScheduleModalIfNeeded();
        }
      });
    }
  }

  Future<void> _openFormModal({
    required String title,
    required Widget child,
    String? subtitle,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final isFlatHeaderModal =
            title == 'Report Violation' || title == 'Counselling Referral';
        final size = MediaQuery.of(dialogContext).size;
        final isDesktop = size.width >= 900;
        final maxWidth = isDesktop ? 1180.0 : size.width - 20;
        final maxHeight = size.height * 0.92;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 12,
          ),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox(
            width: maxWidth,
            height: maxHeight,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
                  decoration: BoxDecoration(
                    color: isFlatHeaderModal ? Colors.white : surface,
                    border: isFlatHeaderModal
                        ? null
                        : Border(
                            bottom: BorderSide(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: textDark,
                                fontSize: 16,
                              ),
                            ),
                            if ((subtitle ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!.trim(),
                                style: TextStyle(
                                  color: hint.withValues(alpha: 0.95),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.06),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openViolationReportModal() async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    await _openFormModal(
      title: 'Report Violation',
      subtitle: 'Search a student, complete incident details, and submit.',
      child: ViolationReportPage(
        onOpenMyReportsInShell: () {
          Navigator.of(context, rootNavigator: true).pop();
          _go(_myReportsIndex);
        },
      ),
    );
  }

  Future<void> _openCounselingReferralModal() async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    await _openFormModal(
      title: 'Counselling Referral',
      child: ProfessorCounselingPage(
        unsavedChangesController: _counselingUnsaved,
      ),
    );
  }

  Future<void> _openViolationReviewAsync({
    String? preselectCaseCode,
    bool toReviewInbox = false,
  }) async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    final caseCode = (preselectCaseCode ?? '').trim();
    final target = OsaDashboard.pathForSection(
      'review',
      query: <String, String>{
        if (caseCode.isNotEmpty) 'reviewCaseCode': caseCode,
        if (toReviewInbox || caseCode.isNotEmpty) 'reviewInbox': '1',
      },
    );
    context.go(target);
  }

  String? _defaultTabForSection(String section) {
    final remembered = (_sessionTabBySection[section] ?? '').trim();
    if (remembered.isNotEmpty) return remembered;
    switch (section) {
      case 'setup':
        return 'violations';
      case 'review':
        return 'review';
      case 'my-reports':
        return 'violation';
      default:
        return null;
    }
  }

  void _ensureSectionTabQuery() {
    if (!mounted) return;
    final section = OsaDashboard.sectionForIndex(_currentIndex);
    final defaultTab = _defaultTabForSection(section);
    if (defaultTab == null) return;
    final currentUri = GoRouterState.of(context).uri;
    final currentTab = (currentUri.queryParameters['tab'] ?? '').trim();
    if (currentTab.isNotEmpty) return;
    final target = OsaDashboard.pathForSection(
      section,
      query: <String, String>{'tab': defaultTab},
    );
    if (target == currentUri.toString()) return;
    context.replace(target);
  }

  void _syncSectionTab(String section, String tabKey) {
    final currentSection = OsaDashboard.sectionForIndex(_currentIndex);
    if (currentSection != section) return;
    _sessionTabBySection[section] = tabKey;
    final currentUri = GoRouterState.of(context).uri;
    final currentTab = (currentUri.queryParameters['tab'] ?? '').trim();
    if (currentTab == tabKey) return;
    final target = OsaDashboard.pathForSection(
      section,
      query: <String, String>{'tab': tabKey},
    );
    if (target == currentUri.toString()) return;
    context.go(target);
  }

  void _goSettings(int pageIndex) {
    _goSettingsAsync(pageIndex);
  }

  Future<void> _goSettingsAsync(int pageIndex) async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    final section = OsaDashboard.sectionForIndex(pageIndex);
    final tab = _defaultTabForSection(section);
    context.go(
      OsaDashboard.pathForSection(
        section,
        query: tab == null ? null : <String, String>{'tab': tab},
      ),
    );
  }

  Future<void> _handleNotificationView(AppNotificationViewIntent intent) async {
    switch (intent.target) {
      case AppNotificationViewTarget.pendingApproval:
        _go(0);
        break;
      case AppNotificationViewTarget.violationAlert:
        final caseRef = (intent.caseCode ?? '').trim();
        await _openViolationReviewAsync(preselectCaseCode: caseRef);
        break;
    }
  }

  void _toggleDesktopNotifications() {
    setState(() => _showDesktopNotifications = !_showDesktopNotifications);
  }

  void _closeDesktopNotifications() {
    if (_showDesktopNotifications) {
      setState(() => _showDesktopNotifications = false);
    }
  }

  Future<void> _openNotificationsPage() async {
    final canLeave = await _confirmLeaveCurrentPage();
    if (!mounted || !canLeave) return;
    if (_currentIndex != _notificationsIndex) {
      _previousIndexBeforeNotifications = _currentIndex;
    }
    _showDesktopNotifications = false;
    _go(_notificationsIndex);
  }

  String _displayName(Map<String, dynamic> data, User user) {
    final dn = (data['displayName'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final full = ('$first $last').trim();
    if (full.isNotEmpty) return full;
    final email = (data['email'] ?? user.email ?? '').toString().trim();
    if (email.contains('@')) return email.split('@').first;
    return 'OSA Admin';
  }

  String _email(Map<String, dynamic> data, User user) {
    final e = (data['email'] ?? user.email ?? '').toString().trim();
    return e.isEmpty ? '--' : e;
  }

  String _profilePhotoUrl(Map<String, dynamic> data) {
    final direct = (data['photoUrl'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final profilePhoto = (data['profilePhotoUrl'] ?? '').toString().trim();
    if (profilePhoto.isNotEmpty) return profilePhoto;
    final studentProfile = data['studentProfile'] as Map<String, dynamic>?;
    final nestedStudentPhoto = (studentProfile?['photoUrl'] ?? '')
        .toString()
        .trim();
    if (nestedStudentPhoto.isNotEmpty) return nestedStudentPhoto;
    final employeeProfile = data['employeeProfile'] as Map<String, dynamic>?;
    final nestedEmployeePhoto = (employeeProfile?['photoUrl'] ?? '')
        .toString()
        .trim();
    if (nestedEmployeePhoto.isNotEmpty) return nestedEmployeePhoto;
    return '';
  }

  String _title(Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString().toLowerCase().trim();
    switch (role) {
      case 'osa_admin':
        return 'OSA Administrator';
      default:
        return 'OSA Portal';
    }
  }

  @override
  void dispose() {
    _violationUnsaved.dispose();
    _counselingUnsaved.dispose();
    _handbookEditorUnsaved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Not logged in',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: AppFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final accountName = _displayName(data, user);
        final accountEmail = _email(data, user);
        final accountTitle = _title(data);
        final profilePhotoUrl = _profilePhotoUrl(data);

        return LayoutBuilder(
          builder: (context, constraints) {
            final shell = ResponsiveLayoutTokens.resolveShellLayout(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              allowCompactDesktopDrawer: true,
            );

            final menuPanel = _MenuPanel(
              currentIndex: _currentIndex,
              primary: primary,
              hint: hint,
              textDark: textDark,
              surface: surface,
              onSelect: _go,
              onProfile: () => _go(6),
              settingsOpen: _settingsOpen,
              onToggleSettings: () =>
                  setState(() => _settingsOpen = !_settingsOpen),
              onSelectSettingsItem: (pageIndex) => _goSettings(pageIndex),
              onLogout: _logout,
              accountTitle: accountTitle,
              accountEmail: accountEmail,
              accountName: accountName,
              profilePhotoUrl: profilePhotoUrl,
            );

            return RoleShellScaffold(
              backgroundColor: bg,
              title: _pageTitle(),
              usesDrawerSidebar: shell.usesDrawerSidebar,
              showPermanentSidebar: shell.showPermanentSidebar,
              drawer: Drawer(
                child: _MenuPanel(
                  currentIndex: _currentIndex,
                  primary: primary,
                  hint: hint,
                  textDark: textDark,
                  surface: surface,
                  onSelect: (i) {
                    Navigator.of(context).maybePop();
                    _go(i);
                  },
                  onProfile: () {
                    Navigator.of(context).maybePop();
                    _go(6);
                  },
                  settingsOpen: _settingsOpen,
                  onToggleSettings: () =>
                      setState(() => _settingsOpen = !_settingsOpen),
                  onSelectSettingsItem: (pageIndex) {
                    Navigator.of(context).maybePop();
                    _goSettings(pageIndex);
                  },
                  onLogout: () {
                    Navigator.of(context).maybePop();
                    _logout();
                  },
                  accountTitle: accountTitle,
                  accountEmail: accountEmail,
                  accountName: accountName,
                  profilePhotoUrl: profilePhotoUrl,
                ),
              ),
              sidebar: menuPanel,
              content: IndexedStack(index: _currentIndex, children: _pages),
              onNotificationsTap: () {
                if (shell.isDesktop) {
                  _toggleDesktopNotifications();
                } else {
                  if (_currentIndex == _notificationsIndex) {
                    final backIndex =
                        _previousIndexBeforeNotifications == _notificationsIndex
                        ? 0
                        : _previousIndexBeforeNotifications;
                    _go(backIndex);
                  } else {
                    _openNotificationsPage();
                  }
                }
              },
              notificationsUid: user.uid,
              suppressIncomingNotificationToasts:
                  _showDesktopNotifications ||
                  _currentIndex == _notificationsIndex,
              hideNotificationsBadge:
                  _showDesktopNotifications ||
                  _currentIndex == _notificationsIndex,
              enableNotificationSound: false,
              showDesktopOverlay: shell.isDesktop && _showDesktopNotifications,
              onDismissDesktopOverlay: _closeDesktopNotifications,
              desktopOverlay: DesktopNotificationsPanel(
                uid: user.uid,
                onClose: _closeDesktopNotifications,
                onSeeAll: _openNotificationsPage,
                onViewNotification: (intent) async {
                  _closeDesktopNotifications();
                  await _handleNotificationView(intent);
                },
              ),
              showBackButton:
                  shell.usesDrawerSidebar &&
                  _currentIndex == _notificationsIndex,
              onBackPressed: () {
                final backIndex =
                    _previousIndexBeforeNotifications == _notificationsIndex
                    ? 0
                    : _previousIndexBeforeNotifications;
                _go(backIndex);
              },
            );
          },
        );
      },
    );
  }
}

// ================= SIDEBAR =================

class _MenuPanel extends StatelessWidget {
  final int currentIndex;

  final Color primary;
  final Color hint;
  final Color textDark;
  final Color surface;

  final ValueChanged<int> onSelect;
  final VoidCallback onProfile;

  final bool settingsOpen;
  final VoidCallback onToggleSettings;
  final ValueChanged<int> onSelectSettingsItem;

  final VoidCallback onLogout;

  final String accountTitle;
  final String accountEmail;
  final String accountName;
  final String profilePhotoUrl;

  const _MenuPanel({
    required this.currentIndex,
    required this.primary,
    required this.hint,
    required this.textDark,
    required this.surface,
    required this.onSelect,
    required this.onProfile,
    required this.settingsOpen,
    required this.onToggleSettings,
    required this.onSelectSettingsItem,
    required this.onLogout,
    required this.accountTitle,
    required this.accountEmail,
    required this.accountName,
    required this.profilePhotoUrl,
  });

  bool _isHttpPhotoUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  Future<String> _resolvePhotoUrl(String source) async {
    final value = source.trim();
    if (value.isEmpty) return '';
    if (_isHttpPhotoUrl(value)) {
      if (value.contains('firebasestorage.googleapis.com') ||
          value.contains('firebasestorage.app')) {
        try {
          return await FirebaseStorage.instance
              .refFromURL(value)
              .getDownloadURL();
        } catch (_) {
          return value;
        }
      }
      return value;
    }
    try {
      if (value.startsWith('gs://')) {
        return await FirebaseStorage.instance
            .refFromURL(value)
            .getDownloadURL();
      }
      return await FirebaseStorage.instance.ref(value).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  Widget _buildProfileAvatar() {
    final source = profilePhotoUrl.trim();
    const fallback = Icon(
      Icons.person_outline_rounded,
      size: 24,
      color: Colors.white,
    );
    final fallbackAvatar = const CircleAvatar(
      backgroundColor: Colors.white24,
      child: fallback,
    );

    Widget photoAvatar(String url) {
      return ClipOval(
        child: Image.network(
          url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          errorBuilder: (_, _, _) => fallbackAvatar,
        ),
      );
    }

    if (source.isEmpty) return fallbackAvatar;
    if (_isHttpPhotoUrl(source)) {
      return FutureBuilder<String>(
        future: _resolvePhotoUrl(source),
        builder: (context, snapshot) {
          final resolved = (snapshot.data ?? source).trim();
          return resolved.isEmpty ? fallbackAvatar : photoAvatar(resolved);
        },
      );
    }
    return FutureBuilder<String>(
      future: _resolvePhotoUrl(source),
      builder: (context, snapshot) {
        final resolved = (snapshot.data ?? '').trim();
        return resolved.isEmpty ? fallbackAvatar : photoAvatar(resolved);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBranding.logo(width: 28, height: 28),
                  const SizedBox(width: 8),
                  Text(
                    'BUDiscipLink',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onProfile,
                child: Ink(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: primary.withValues(
                      alpha: currentIndex == 6 ? 0.86 : 0.80,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _buildProfileAvatar(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              accountName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              accountEmail,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.90),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              accountTitle,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.92),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 10, bottom: 16),
              child: Column(
                children: [
                  _MenuItem(
                    icon: Icons.dashboard_rounded,
                    label: 'Dashboard',
                    active: currentIndex == 0,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(0),
                  ),
                  _MenuItem(
                    icon: Icons.menu_book_rounded,
                    label: 'Handbook',
                    active: currentIndex == 1,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(1),
                  ),
                  _MenuItem(
                    icon: Icons.rule_rounded,
                    label: 'Violation Review',
                    active: currentIndex == 8,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(8),
                  ),
                  _MenuItem(
                    icon: Icons.assignment_rounded,
                    label: 'Violation Records',
                    active: currentIndex == 2,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(2),
                  ),
                  _MenuItem(
                    icon: Icons.analytics_rounded,
                    label: 'Violation Analytics',
                    active: currentIndex == 7,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(7),
                  ),
                  _MenuItem(
                    icon: Icons.article_outlined,
                    label: 'My Reports',
                    active: currentIndex == 12,
                    primary: primary,
                    textDark: textDark,
                    onTap: () => onSelect(12),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: primary.withValues(alpha: 0.15), height: 18),
                  InkWell(
                    onTap: onToggleSettings,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: settingsOpen
                            ? primary.withValues(alpha: 0.08)
                            : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.settings_outlined,
                            color: textDark.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Settings',
                              style: TextStyle(
                                color: textDark.withValues(alpha: 0.92),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Icon(
                            settingsOpen
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: hint,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (settingsOpen) ...[
                    const SizedBox(height: 4),
                    _SubItem(
                      label: 'Violation Setup',
                      icon: Icons.fact_check_rounded,
                      active: currentIndex == 3,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(3),
                    ),
                    _SubItem(
                      label: 'Meeting Schedule',
                      icon: Icons.calendar_month_rounded,
                      active: currentIndex == 4,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(4),
                    ),
                    _SubItem(
                      label: 'Manage Handbook',
                      icon: Icons.published_with_changes_rounded,
                      active: currentIndex == 5 || currentIndex == 9,
                      primary: primary,
                      textDark: textDark,
                      hint: hint,
                      onTap: () => onSelectSettingsItem(5),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: primary.withValues(alpha: 0.15)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: InkWell(
              onTap: onLogout,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.logout_rounded, color: Colors.red),
                    SizedBox(width: 12),
                    Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color primary;
  final Color textDark;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.primary,
    required this.textDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? primary : textDark.withValues(alpha: 0.85);
    final textColor = active ? primary : textDark.withValues(alpha: 0.92);

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? primary.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color primary;
  final Color textDark;
  final Color hint;
  final VoidCallback onTap;

  const _SubItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.primary,
    required this.textDark,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? primary : textDark.withValues(alpha: 0.80);
    final textColor = active ? primary : textDark.withValues(alpha: 0.88);

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(22, 2, 10, 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? primary.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

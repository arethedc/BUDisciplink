import 'package:apps/pages/shared/widgets/modern_table_layout.dart';
import 'package:apps/pages/shared/widgets/app_layout_tokens.dart';
import 'package:apps/services/counseling_case_workflow_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';
import 'package:apps/pages/professor/professor_counseling_page.dart';

class CounselingAppointmentsPage extends StatefulWidget {
  const CounselingAppointmentsPage({super.key});

  @override
  State<CounselingAppointmentsPage> createState() =>
      _CounselingAppointmentsPageState();
}

enum _CounselingActionKind {
  sendCallSlip,
  completeMeeting,
  cancelCase,
}

class _CounselingMenuAction {
  final String label;
  final IconData icon;
  final bool danger;
  final VoidCallback onTap;

  const _CounselingMenuAction({
    required this.label,
    required this.icon,
    required this.danger,
    required this.onTap,
  });
}

class _CounselingAppointmentsPageState
    extends State<CounselingAppointmentsPage> {
  static const primary = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hint = Color(0xFF6D7F62);
  static const List<_CounselingReviewTabConfig> _tabs = [
    _CounselingReviewTabConfig(
      tab: _CounselingReviewTab.all,
      label: 'All',
    ),
    _CounselingReviewTabConfig(
      tab: _CounselingReviewTab.awaitingCallSlip,
      label: 'Awaiting Call Slip',
    ),
    _CounselingReviewTabConfig(
      tab: _CounselingReviewTab.bookingRequired,
      label: 'Booking Required',
    ),
    _CounselingReviewTabConfig(
      tab: _CounselingReviewTab.scheduled,
      label: 'Scheduled',
    ),
    _CounselingReviewTabConfig(
      tab: _CounselingReviewTab.missed,
      label: 'Missed',
    ),
    _CounselingReviewTabConfig(
      tab: _CounselingReviewTab.completed,
      label: 'Completed',
    ),
    _CounselingReviewTabConfig(
      tab: _CounselingReviewTab.cancelled,
      label: 'Cancelled',
    ),
  ];

  final TextEditingController _searchCtrl = TextEditingController();
  final CounselingCaseWorkflowService _workflowService =
      CounselingCaseWorkflowService();
  final Map<String, Future<String>> _studentPhotoFutureCache =
      <String, Future<String>>{};

  _CounselingReviewTab _tab = _CounselingReviewTab.all;
  String _selectedId = '';
  String? _actionCaseId;
  bool _sweepRunning = false;

  @override
  void initState() {
    super.initState();
    _runExpirySweep();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _runExpirySweep({bool showResult = false}) async {
    if (_sweepRunning) return;
    _sweepRunning = true;
    try {
      final count = await _workflowService.expireOverdueScheduledMeetings();
      if (!mounted) return;
      if (count > 0) {
        AppScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$count overdue scheduled counseling appointment(s) were marked missed.',
            ),
            backgroundColor: primary,
          ),
        );
      } else if (showResult) {
        AppScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No overdue scheduled counseling appointments found.',
            ),
            backgroundColor: primary,
          ),
        );
      }
    } catch (error) {
      if (mounted && showResult) {
        AppScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sweep failed: $error'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      _sweepRunning = false;
    }
  }

  Future<void> _refreshCurrentTable() async {
    if (_sweepRunning) return;
    await _runExpirySweep(showResult: false);
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildRefreshButton() {
    return Tooltip(
      message: 'Refresh table',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _sweepRunning ? null : _refreshCurrentTable,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.75),
            border: Border.all(color: Colors.black12),
          ),
          child: _sweepRunning
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primary,
                  ),
                )
              : const Icon(Icons.refresh_rounded, color: hint, size: 20),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1000;
    final shouldConstrainWidth = width >= 900;
    final constrainedWidth = width >= 1600
        ? 640.0
        : width >= 1300
            ? 580.0
            : 520.0;
    final height = isDesktop ? 56.0 : 48.0;
    final borderRadius = isDesktop ? 16.0 : 18.0;
    final iconSize = isDesktop ? 24.0 : 22.0;
    final fontSize = isDesktop ? 15.0 : 13.5;

    final searchField = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchCtrl,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;

        return Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.black12),
            boxShadow: isDesktop
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: hint, size: iconSize),
              SizedBox(width: isDesktop ? 12 : 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search student, status, source, or type...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(
                      color: hint,
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
              if (hasText)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {});
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    color: hint.withValues(alpha: 0.85),
                    size: isDesktop ? 20 : 18,
                  ),
                ),
            ],
          ),
        );
      },
    );

    Widget searchWithRefresh() {
      return Row(
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 8),
          _buildRefreshButton(),
        ],
      );
    }

    if (!shouldConstrainWidth) return searchWithRefresh();
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: constrainedWidth, child: searchWithRefresh()),
    );
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _safe(dynamic value) => (value ?? '').toString().trim();

  bool _matchesTab(Map<String, dynamic> data) {
    switch (_tab) {
      case _CounselingReviewTab.all:
        return true;
      case _CounselingReviewTab.awaitingCallSlip:
        return _isAwaitingCallSlip(data);
      case _CounselingReviewTab.bookingRequired:
        return _isBookingRequired(data);
      case _CounselingReviewTab.scheduled:
        return _isScheduled(data);
      case _CounselingReviewTab.missed:
        return _isMissed(data);
      case _CounselingReviewTab.completed:
        return _isCompleted(data);
      case _CounselingReviewTab.cancelled:
        return _isCancelled(data);
    }
  }

  int _tabCount(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, _CounselingReviewTab tab) {
    return docs.where((doc) {
      final data = doc.data();
      switch (tab) {
        case _CounselingReviewTab.all:
          return true;
        case _CounselingReviewTab.awaitingCallSlip:
          return _isAwaitingCallSlip(data);
        case _CounselingReviewTab.bookingRequired:
          return _isBookingRequired(data);
        case _CounselingReviewTab.scheduled:
          return _isScheduled(data);
        case _CounselingReviewTab.missed:
          return _isMissed(data);
        case _CounselingReviewTab.completed:
          return _isCompleted(data);
        case _CounselingReviewTab.cancelled:
          return _isCancelled(data);
      }
    }).length;
  }

  String _fmtDate(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('MMM d, yyyy').format(value);
  }

  String _fmtDateTime(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('MMM d, yyyy - h:mm a').format(value);
  }

  bool _isCompleted(Map<String, dynamic> data) {
    return CounselingCaseState.isCompleted(data);
  }

  bool _isCancelled(Map<String, dynamic> data) {
    return CounselingCaseState.isCancelled(data);
  }

  bool _isMissed(Map<String, dynamic> data) {
    return CounselingCaseState.isMissed(data);
  }

  bool _isScheduled(Map<String, dynamic> data) {
    return CounselingCaseState.isScheduled(data);
  }

  bool _isAwaitingCallSlip(Map<String, dynamic> data) {
    return CounselingCaseState.isAwaitingCallSlip(data);
  }

  bool _isBookingRequired(Map<String, dynamic> data) {
    return CounselingCaseState.isBookingRequired(data);
  }

  bool _isClosedCase(Map<String, dynamic> data) {
    return CounselingCaseState.isClosed(data);
  }

  String _titleCase(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _prettySource(String source) {
    final s = source.toLowerCase().trim();
    if (s == 'student') return 'Self-referral';
    if (s == 'professor') return 'Professor referral';
    return s.isEmpty ? 'Unknown' : _titleCase(s);
  }

  String _prettyType(String type) {
    final t = type.toLowerCase().trim();
    if (t == 'academic') return 'Academic';
    if (t == 'personal') return 'Personal';
    return t.isEmpty ? '-' : _titleCase(t);
  }

  String _statusText(Map<String, dynamic> data) {
    return CounselingCaseState.statusLabel(data);
  }

  Color _statusColor(Map<String, dynamic> data) {
    if (_isCompleted(data)) return Colors.green.shade700;
    if (_isCancelled(data)) return Colors.grey.shade700;
    if (_isMissed(data)) return Colors.red.shade700;
    if (_isScheduled(data)) return Colors.blue.shade700;
    if (_isBookingRequired(data)) return primary;
    if (_isAwaitingCallSlip(data)) return Colors.orange.shade700;
    return Colors.grey.shade700;
  }

  Widget _buildStatusPill(Map<String, dynamic> data) {
    final color = _statusColor(data);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _statusText(data),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
        ),
      ),
    );
  }

  List<String> _reasonList(Map<String, dynamic> reasons, String key) {
    final raw = reasons[key];
    if (raw is List) {
      return raw
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> _referralEntryList(dynamic raw) {
    if (raw is Iterable) {
      return raw
          .whereType<Map>()
          .map(
            (item) => item.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  String _concernGroupLabel(String key) {
    switch (key.trim()) {
      case 'moodsBehaviors':
        return 'Moods / Behaviors';
      case 'schoolConcerns':
        return 'School Concerns';
      case 'relationships':
        return 'Relationships';
      case 'homeConcerns':
        return 'Home Concerns';
      default:
        return _titleCase(key.replaceAll('_', ' '));
    }
  }

  Widget _buildConcernList(Map<String, dynamic> reasons) {
    final items = <Widget>[];
    for (final entry in reasons.entries) {
      final label = _concernGroupLabel(entry.key.toString());
      final raw = entry.value;
      final values = <String>[];
      if (raw is List) {
        values.addAll(
          raw.map((value) => _safe(value)).where((value) => value.isNotEmpty),
        );
      } else {
        final single = _safe(raw);
        if (single.isNotEmpty) values.add(single);
      }

      if (values.isEmpty) continue;

      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final value in values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '- $value',
                        style: const TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return const Text(
        '-',
        style: TextStyle(
          color: textDark,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items,
    );
  }

  Widget _buildConcernSection(Map<String, dynamic> reasons) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              'Concern',
              style: const TextStyle(
                color: hint,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: _buildConcernList(reasons),
            ),
          ),
        ],
      ),
    );
  }

  bool _canSendCallSlipAction(Map<String, dynamic> data) {
    final source = _safe(data['referralSource']).toLowerCase();
    return source == CounselingCaseWorkflow.referralSourceProfessor &&
        _isAwaitingCallSlip(data) &&
        !_isCompleted(data) &&
        !_isCancelled(data);
  }

  bool _canCompleteMeetingAction(Map<String, dynamic> data) {
    return (_isScheduled(data) ||
            _isBookingRequired(data) ||
            _safe(data['workflowStatus']).toLowerCase() ==
                CounselingCaseWorkflow.workflowBooked) &&
        !_isCompleted(data) &&
        !_isCancelled(data);
  }

  bool _canCancelCaseAction(Map<String, dynamic> data) {
    return !_isCompleted(data) && !_isCancelled(data);
  }

  _CounselingActionKind? _primaryActionFor(Map<String, dynamic> data) {
    if (_canSendCallSlipAction(data)) return _CounselingActionKind.sendCallSlip;
    if (_canCompleteMeetingAction(data)) {
      return _CounselingActionKind.completeMeeting;
    }
    if (_canCancelCaseAction(data)) return _CounselingActionKind.cancelCase;
    return null;
  }

  String _actionLabel(_CounselingActionKind action) {
    switch (action) {
      case _CounselingActionKind.sendCallSlip:
        return 'Send Call Slip';
      case _CounselingActionKind.completeMeeting:
        return 'Complete Meeting';
      case _CounselingActionKind.cancelCase:
        return 'Cancel Case';
    }
  }

  bool _actionIsDanger(_CounselingActionKind action) {
    return action == _CounselingActionKind.cancelCase;
  }

  bool _actionIsPrimary(_CounselingActionKind action) {
    return action == _CounselingActionKind.sendCallSlip ||
        action == _CounselingActionKind.completeMeeting;
  }

  IconData _actionIcon(_CounselingActionKind action) {
    switch (action) {
      case _CounselingActionKind.sendCallSlip:
        return Icons.mark_email_unread_outlined;
      case _CounselingActionKind.completeMeeting:
        return Icons.check_circle_outline_rounded;
      case _CounselingActionKind.cancelCase:
        return Icons.cancel_outlined;
    }
  }

  bool _isActionBusy(String caseId) => _actionCaseId == caseId;

  String _friendlyError(Object error) {
    final raw = error.toString().trim();
    if (raw.startsWith('Exception:')) {
      return raw.substring('Exception:'.length).trim();
    }
    return raw;
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          contentPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _runCaseAction({
    required String caseId,
    required String title,
    required String message,
    required String successMessage,
    required Future<void> Function() action,
    String confirmLabel = 'Confirm',
  }) async {
    if (_actionCaseId != null) return;

    final confirmed = await _confirmAction(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    );
    if (!confirmed || !mounted) return;

    setState(() => _actionCaseId = caseId);
    try {
      await action();
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage), backgroundColor: primary),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(error)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionCaseId = null);
    }
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback? onPressed,
    bool primaryButton = false,
    bool dangerButton = false,
    bool loading = false,
  }) {
    final foreground = dangerButton
        ? Colors.red.shade700
        : primaryButton
            ? Colors.white
            : primary;
    final background = dangerButton
        ? Colors.white
        : primaryButton
            ? primary
            : Colors.white;
    final borderColor = dangerButton
        ? Colors.red.withValues(alpha: 0.35)
        : primaryButton
            ? primary
            : primary.withValues(alpha: 0.35);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              : Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCaseActions(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final caseId = doc.id;
    final busy = _isActionBusy(caseId);
    final isAwaitingCallSlip = _isAwaitingCallSlip(data);

    final canSendCallSlip = _canSendCallSlipAction(data);
    final canCompleteMeeting = _canCompleteMeetingAction(data);
    final canCancelCase = _canCancelCaseAction(data);
    final primaryAction = _primaryActionFor(data);
    final menuItems = <_CounselingMenuAction>[
      if (canCancelCase && primaryAction != _CounselingActionKind.cancelCase)
        _CounselingMenuAction(
          label: 'Cancel Case',
          icon: Icons.cancel_outlined,
          danger: true,
          onTap: () => _runCaseAction(
            caseId: caseId,
            title: 'Cancel counseling case?',
            message:
                'This will cancel the case and write a case log for the action.',
            successMessage: 'Counseling case cancelled.',
            confirmLabel: 'Cancel Case',
            action: () => _workflowService.cancelCase(caseId: caseId),
          ),
        ),
      _CounselingMenuAction(
        label: 'Case Logs',
        icon: Icons.receipt_long_rounded,
        danger: false,
        onTap: () => _openCaseLogsDialog(doc),
      ),
    ];

    if (!canSendCallSlip && !canCompleteMeeting && !canCancelCase) {
      return const Text(
        'No admin actions available for the current case status.',
        style: TextStyle(
          color: hint,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
          height: 1.35,
        ),
      );
    }

    if (primaryAction == null) {
      return const SizedBox.shrink();
    }

    VoidCallback primaryOnTap() {
      switch (primaryAction) {
        case _CounselingActionKind.sendCallSlip:
          return () => _runCaseAction(
                caseId: caseId,
                title: 'Send counseling call slip?',
                message:
                    'The student will be notified and can start booking an appointment.',
                successMessage:
                    'Call slip sent. Student can now book an appointment.',
                confirmLabel: 'Send Slip',
                action: () => _workflowService.sendCallSlip(caseId: caseId),
              );
        case _CounselingActionKind.completeMeeting:
          return () => _runCaseAction(
                caseId: caseId,
                title: 'Mark meeting completed?',
                message:
                    'This will close the case as completed and notify the student.',
                successMessage: 'Meeting marked as completed.',
                confirmLabel: 'Complete',
                action: () =>
                    _workflowService.markAppointmentCompleted(caseId: caseId),
              );
        case _CounselingActionKind.cancelCase:
          return () => _runCaseAction(
                caseId: caseId,
                title: 'Cancel counseling case?',
                message:
                    'This will cancel the case and write a case log for the action.',
                successMessage: 'Counseling case cancelled.',
                confirmLabel: 'Cancel Case',
                action: () => _workflowService.cancelCase(caseId: caseId),
              );
      }
    }

    if (isAwaitingCallSlip || menuItems.isNotEmpty) {
      final useFilledPrimary = isAwaitingCallSlip;
      return Row(
        children: [
          Expanded(
            child: _buildActionButton(
              label: _actionLabel(primaryAction),
              primaryButton: useFilledPrimary &&
                  _actionIsPrimary(primaryAction),
              dangerButton: _actionIsDanger(primaryAction),
              loading: busy,
              onPressed: busy ? null : primaryOnTap(),
            ),
          ),
          const SizedBox(width: 10),
          PopupMenuButton<_CounselingMenuAction>(
            tooltip: 'More actions',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            color: Colors.white,
            enabled: !busy && menuItems.isNotEmpty,
            onSelected: (action) => action.onTap(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: primary.withValues(alpha: 0.25),
                ),
              ),
              child: const Icon(
                Icons.more_vert_rounded,
                color: primary,
              ),
            ),
            itemBuilder: (context) => [
              for (final action in menuItems)
                PopupMenuItem<_CounselingMenuAction>(
                  value: action,
                  child: Row(
                    children: [
                      Icon(
                        action.icon,
                        size: 18,
                        color: action.danger ? Colors.red.shade700 : primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        action.label,
                        style: TextStyle(
                          color: action.danger ? Colors.red.shade700 : textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    }

    return _buildActionButton(
      label: _actionLabel(primaryAction),
      primaryButton: _actionIsPrimary(primaryAction),
      dangerButton: _actionIsDanger(primaryAction),
      loading: busy,
      onPressed: busy ? null : primaryOnTap(),
    );
  }

  Future<void> _openCaseLogsDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CounselingCaseLogsDialog(caseDoc: doc),
    );
  }

  Future<void> _openCounselingReferralModal() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final media = MediaQuery.of(dialogContext);
        final width = media.size.width > 1000
            ? 980.0
            : media.size.width > 760
                ? media.size.width * 0.96
                : media.size.width * 0.98;
        final height = media.size.height > 640
            ? media.size.height * 0.92
            : media.size.height * 0.96;

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: SizedBox(
            width: width.clamp(320.0, 980.0),
            height: height.clamp(520.0, media.size.height * 0.98),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Counselling Referral',
                          style: TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded, color: hint),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const Expanded(
                  child: ProfessorCounselingPage(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCounselingReferralButton() {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    return FilledButton.icon(
      onPressed: _openCounselingReferralModal,
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      icon: const Icon(Icons.support_agent_rounded, size: 18),
      label: Text(
        wide ? 'Counselling Referral' : 'Referral',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _detailCard({
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(12),
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
              fontSize: 13.5,
            ),
          ),
          if (child is! SizedBox) ...[
            const SizedBox(height: 8),
            child,
          ] else ...[
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailPane(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final studentUid = _safe(data['studentUid']);
    final referralEntries = _referralEntryList(data['referralEntries']);
    final scheduledAt = _toDate(data['scheduledAt']);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        color: primary,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Case Details',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                children: [
                  _detailCard(
                    title: 'Student Information',
                    child: Row(
                      children: [
                        FutureBuilder<String>(
                          future: _resolveStudentPhotoUrl(studentUid),
                          initialData: '',
                          builder: (context, snapshot) {
                            final photoUrl = _safe(snapshot.data);
                            return MouseRegion(
                              cursor: photoUrl.isEmpty
                                  ? SystemMouseCursors.basic
                                  : SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: photoUrl.isEmpty
                                    ? null
                                    : () => _openProfilePhotoViewer(
                                        context: context,
                                        sourceUrl: photoUrl,
                                        studentName: _safe(data['studentName']),
                                      ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: primary.withValues(
                                            alpha: 0.22,
                                          ),
                                        ),
                                      ),
                                      child: photoUrl.isEmpty
                                          ? const Icon(
                                              Icons.person_rounded,
                                              color: primary,
                                              size: 24,
                                            )
                                          : ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                              child: Image.network(
                                                photoUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (context, error, stackTrace) =>
                                                        const Icon(
                                                          Icons.person_rounded,
                                                          color: primary,
                                                          size: 24,
                                                        ),
                                              ),
                                            ),
                                    ),
                                    if (photoUrl.isNotEmpty)
                                      Positioned(
                                        right: -4,
                                        bottom: -4,
                                        child: Container(
                                          width: 17,
                                          height: 17,
                                          decoration: BoxDecoration(
                                            color: primary,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1.3,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.open_in_full_rounded,
                                            color: Colors.white,
                                            size: 10,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _safe(data['studentName']).isEmpty
                                    ? 'Unknown Student'
                                    : _safe(data['studentName']),
                                style: const TextStyle(
                                  color: textDark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Student No: ${_safe(data['studentNo']).isEmpty ? '-' : _safe(data['studentNo'])}',
                                style: const TextStyle(
                                  color: hint,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Program: ${_safe(data['studentProgramId']).isEmpty ? '-' : _safe(data['studentProgramId'])}',
                                style: const TextStyle(
                                  color: hint,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detailCard(
                    title: 'Case Information',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('Status', _statusText(data)),
                        _kv(
                          'Case Code',
                          _safe(data['caseCode']).isEmpty
                              ? doc.id
                              : _safe(data['caseCode']),
                        ),
                        _kv(
                          'Meeting',
                          _safe(data['meetingStatus']).isEmpty
                              ? '-'
                              : _titleCase(
                                  _safe(data['meetingStatus']).replaceAll(
                                    '_',
                                    ' ',
                                  ),
                                ),
                        ),
                        if (_safe(data['callSlipStatus']).isNotEmpty)
                          _kv(
                            'Call Slip',
                            _titleCase(
                              _safe(data['callSlipStatus']).replaceAll(
                                '_',
                                ' ',
                              ),
                            ),
                          ),
                        if (!_isBookingRequired(data))
                        _kv('Scheduled At', _fmtDateTime(scheduledAt)),
                      ],
                    ),
                  ),
                  _buildReferralHistoryCard(referralEntries),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            child: _buildCaseActions(doc),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralEntryCard(
    Map<String, dynamic> entry, {
    bool isPrimary = false,
  }) {
    final source = _prettySource(_safe(entry['source']));
    final isSelfReferral =
        _safe(entry['source']).toLowerCase() ==
        CounselingCaseWorkflow.referralSourceStudent;
    final type = _prettyType(_safe(entry['counselingType']));
    final referredBy = _safe(entry['referredBy']).isEmpty
        ? '-'
        : _safe(entry['referredBy']);
    final submittedAt = _toDate(entry['submittedAt']);
    final comments = _safe(entry['comments']);
    final reasons = entry['reasons'] is Map<String, dynamic>
        ? entry['reasons'] as Map<String, dynamic>
        : <String, dynamic>{};

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  source,
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (isPrimary)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Primary',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _kv('Type', type),
          if (!isSelfReferral) _kv('Submitted By', referredBy),
          _kv('Submitted At', _fmtDateTime(submittedAt)),
          _buildConcernSection(reasons),
          if (comments.isNotEmpty) _kv('Comments', comments),
        ],
      ),
    );
  }

  Widget _buildReferralHistoryCard(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return _detailCard(
      title: 'Referral History',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < entries.length; i++)
            _buildReferralEntryCard(entries[i], isPrimary: i == 0),
        ],
      ),
    );
  }

  Future<String> _resolveStudentPhotoUrl(String studentUid) {
    final uid = studentUid.trim();
    if (uid.isEmpty) return Future<String>.value('');

    return _studentPhotoFutureCache.putIfAbsent(uid, () async {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data() ?? const <String, dynamic>{};
      final studentProfile =
          userData['studentProfile'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final employeeProfile =
          userData['employeeProfile'] as Map<String, dynamic>? ??
          const <String, dynamic>{};

      final source = _safe(
        userData['photoUrl'] ??
            userData['profilePhotoUrl'] ??
            studentProfile['photoUrl'] ??
            studentProfile['profilePhotoUrl'] ??
            employeeProfile['photoUrl'] ??
            employeeProfile['profilePhotoUrl'],
      );
      return _resolveImageSourceUrl(source);
    });
  }

  Future<String> _resolveImageSourceUrl(String source) async {
    final value = source.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    try {
      if (value.startsWith('gs://')) {
        return await FirebaseStorage.instance.refFromURL(value).getDownloadURL();
      }
      return await FirebaseStorage.instance.ref(value).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  Future<void> _openProfilePhotoViewer({
    required BuildContext context,
    required String sourceUrl,
    required String studentName,
  }) async {
    final resolvedUrl = await _resolveImageSourceUrl(sourceUrl);
    if (resolvedUrl.isEmpty) {
      if (context.mounted) {
        AppScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No profile photo available.'),
            backgroundColor: primary,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => _ProfilePhotoViewerDialog(
        photoUrl: resolvedUrl,
        studentName: studentName,
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              key,
              style: const TextStyle(
                color: hint,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMobileDetails(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _buildDetailPane(doc),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('counseling_cases')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snap.data!.docs;
        final query = _searchCtrl.text.trim().toLowerCase();
        final docs = allDocs.where((doc) {
          final data = doc.data();
          final student = _safe(data['studentName']).toLowerCase();
          final studentNo = _safe(data['studentNo']).toLowerCase();
          final program = _safe(data['studentProgramId']).toLowerCase();
          final statusLabel = _statusText(data).toLowerCase();
          final source = _safe(data['referralSource']).toLowerCase();
          final type = _safe(data['counselingType']).toLowerCase();
          if (!_matchesTab(data)) return false;

          if (query.isNotEmpty &&
              !student.contains(query) &&
              !studentNo.contains(query) &&
              !program.contains(query) &&
              !statusLabel.contains(query) &&
              !source.contains(query) &&
              !type.contains(query)) {
            return false;
          }
          return true;
        }).toList();

        final selectedDoc = _selectedId.isEmpty
            ? null
            : docs
                  .where((doc) => doc.id == _selectedId)
                  .cast<QueryDocumentSnapshot<Map<String, dynamic>>?>()
                  .firstWhere((doc) => doc != null, orElse: () => null);

        if (selectedDoc == null && _selectedId.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedId = '');
          });
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 1100;
            final initialTabIndex = _tabs.indexWhere((item) => item.tab == _tab);
            final tabBar = DefaultTabController(
              length: _tabs.length,
              initialIndex: initialTabIndex < 0 ? 0 : initialTabIndex,
              child: Builder(
                builder: (context) {
                  return TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: primary,
                    indicatorColor: primary,
                    dividerColor: Colors.transparent,
                    onTap: (index) {
                      final nextTab = _tabs[index].tab;
                      if (nextTab == _tab) return;
                      setState(() {
                        _tab = nextTab;
                        _selectedId = '';
                      });
                    },
                    tabs: [
                      for (final tab in _tabs)
                        Tab(
                          text:
                              '${tab.label} (${_tabCount(allDocs, tab.tab)})',
                        ),
                    ],
                  );
                },
              ),
            );

            return ModernTableLayout(
              header: ModernTableHeader(
              showTitleSection: false,
              showTopControlsWhenTitleHidden: true,
              showSearchBar: true,
              searchBar: _buildSearchBar(),
              action: _buildCounselingReferralButton(),
              tabs: tabBar,
              filters: const [],
            ),
              body: docs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.support_agent_outlined,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No referral found',
                            style: TextStyle(
                              color: hint,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : isDesktop
                      ? _buildDesktopTable(docs)
                      : ListView.builder(
                          padding: const EdgeInsets.all(14),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data();
                            final selected = _selectedId == doc.id;
                            return _buildCaseCard(
                              doc,
                              data,
                              selected,
                              () {
                                _openMobileDetails(doc);
                              },
                            );
                          },
                        ),
              showDetails: isDesktop && selectedDoc != null,
              details: selectedDoc == null
                  ? null
                  : _buildDetailPane(selectedDoc),
              detailsWidth: (constraints.maxWidth * 0.33).clamp(320.0, 420.0),
            );
          },
        );
      },
    );
  }

  Widget _buildDesktopTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = constraints.maxWidth;
            final detailsOpen = _selectedId.isNotEmpty;
            final compactTable = detailsOpen || tableWidth < 1120;
            final tableHorizontalMargin = compactTable ? 8.0 : 12.0;
            final tableColumnSpacing = compactTable ? 12.0 : 18.0;
            final usableWidth =
                (tableWidth -
                        (tableHorizontalMargin * 2) -
                        (tableColumnSpacing * 4))
                    .clamp(420.0, double.infinity)
                    .toDouble();
            final codeCellWidth = (usableWidth * 0.16).clamp(96.0, 128.0);
            final studentCellWidth = (usableWidth * 0.28).clamp(180.0, 260.0);
            final referralCellWidth = (usableWidth * 0.30).clamp(170.0, 260.0);
            final dateCellWidth = (usableWidth * 0.14).clamp(104.0, 130.0);
            final statusCellWidth = (usableWidth * 0.16).clamp(120.0, 170.0);

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(Colors.white),
                  horizontalMargin: tableHorizontalMargin,
                  columnSpacing: tableColumnSpacing,
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 56,
                  columns: [
                    DataColumn(
                      label: SizedBox(
                        width: codeCellWidth,
                        child: const Text(
                          'CODE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hint,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: studentCellWidth,
                        child: const Text(
                          'STUDENT',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hint,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: referralCellWidth,
                        child: const Text(
                          'REFERRAL',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hint,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: dateCellWidth,
                        child: const Text(
                          'DATE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hint,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: statusCellWidth,
                        child: const Text(
                          'STATUS',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hint,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                  rows: List.generate(docs.length, (i) {
                    final doc = docs[i];
                    final data = doc.data();
                    final isSelected = _selectedId == doc.id;
                    final caseCode = _safe(data['caseCode']).isEmpty
                        ? doc.id.substring(0, 8)
                        : _safe(data['caseCode']);
                    final studentName = _safe(data['studentName']).isEmpty
                        ? 'Unknown Student'
                        : _safe(data['studentName']);
                    final studentNo = _safe(data['studentNo']);
                    final source = _prettySource(_safe(data['referralSource']));
                    final type = _prettyType(_safe(data['counselingType']));
                    final date = _toDate(data['createdAt']);

                    return DataRow(
                      selected: isSelected,
                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (isSelected) {
                          return primary.withValues(alpha: 0.08);
                        }
                        return null;
                      }),
                      onSelectChanged: (value) {
                        setState(() {
                          _selectedId = isSelected ? '' : doc.id;
                        });
                      },
                      cells: [
                        DataCell(
                          SizedBox(
                            width: codeCellWidth,
                            child: Text(
                              caseCode,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: primary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: studentCellWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  studentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: textDark,
                                  ),
                                ),
                                if (studentNo.isNotEmpty)
                                  Text(
                                    studentNo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: hint,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: referralCellWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: textDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  type,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: hint,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: dateCellWidth,
                            child: Text(
                              _fmtDate(date),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: hint,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: statusCellWidth,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _buildStatusPill(data),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCaseCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> data,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final caseCode = _safe(data['caseCode']).isEmpty
        ? doc.id.substring(0, 8)
        : _safe(data['caseCode']);
    final studentName = _safe(data['studentName']).isEmpty
        ? 'Unknown Student'
        : _safe(data['studentName']);
    final studentNo = _safe(data['studentNo']);
    final source = _prettySource(_safe(data['referralSource']));
    final type = _prettyType(_safe(data['counselingType']));
    final createdAt = _fmtDate(_toDate(data['createdAt']));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? primary.withValues(alpha: 0.40)
                : Colors.black.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          caseCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: primary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        createdAt,
                        style: const TextStyle(
                          color: hint,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    studentName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: textDark,
                    ),
                  ),
                  if (studentNo.isNotEmpty)
                    Text(
                      studentNo,
                      style: const TextStyle(
                        color: hint,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        source,
                        style: const TextStyle(
                          color: hint,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '|',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        type,
                        style: const TextStyle(
                          color: hint,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '|',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      _buildStatusPill(data),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}

class _ProfilePhotoViewerDialog extends StatelessWidget {
  final String photoUrl;
  final String studentName;

  const _ProfilePhotoViewerDialog({
    required this.photoUrl,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = size.width > 760 ? 640.0 : size.width * 0.94;
    final dialogHeight = size.height > 620 ? 560.0 : size.height * 0.88;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      studentName.isEmpty ? 'Profile Photo' : studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) =>
                          const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white70,
                                size: 42,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Failed to load profile photo',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounselingCaseLogsDialog extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> caseDoc;

  const _CounselingCaseLogsDialog({required this.caseDoc});

  static const Color _textDark = Color(0xFF1F2A1F);
  static const Color _hint = Color(0xFF6D7F62);

  String _safe(dynamic value) => (value ?? '').toString().trim();

  String _fmtTs(dynamic value) {
    if (value is Timestamp) {
      return DateFormat('MMM d, yyyy • h:mm a').format(value.toDate());
    }
    if (value is DateTime) {
      return DateFormat('MMM d, yyyy • h:mm a').format(value);
    }
    return '--';
  }

  @override
  Widget build(BuildContext context) {
    final logsRef = caseDoc.reference
        .collection('activity')
        .orderBy('createdAtEpochMs', descending: true);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
              child: Row(
                children: [
                  const Expanded(
                  child: Text(
                      'Case Logs',
                      style: TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: _hint),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: logsRef.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        'Could not load case logs.',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 42,
                            color: _hint,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No case logs yet.',
                            style: TextStyle(
                              color: _hint,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final title = _safe(data['title']).isEmpty
                          ? 'Log Entry'
                          : _safe(data['title']);
                      final description = _safe(data['description']);
                      final actorRole = _safe(data['actorRole']).isEmpty
                          ? 'system'
                          : _safe(data['actorRole']);
                      final createdAt = _fmtTs(data['createdAt']);

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FBF7),
                          borderRadius: BorderRadius.circular(12),
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
                                    title,
                                    style: const TextStyle(
                                      color: _textDark,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                Text(
                                  actorRole,
                                  style: const TextStyle(
                                    color: _hint,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              description.isEmpty ? '--' : description,
                              style: const TextStyle(
                                color: _textDark,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              createdAt,
                              style: const TextStyle(
                                color: _hint,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CounselingReviewTab {
  all,
  awaitingCallSlip,
  bookingRequired,
  scheduled,
  missed,
  completed,
  cancelled,
}

class _CounselingReviewTabConfig {
  final _CounselingReviewTab tab;
  final String label;

  const _CounselingReviewTabConfig({
    required this.tab,
    required this.label,
  });
}

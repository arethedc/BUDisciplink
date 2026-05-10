import 'package:apps/pages/shared/widgets/modern_table_layout.dart';
import 'package:apps/services/counseling_case_workflow_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';

class CounselingAppointmentsPage extends StatefulWidget {
  const CounselingAppointmentsPage({super.key});

  @override
  State<CounselingAppointmentsPage> createState() =>
      _CounselingAppointmentsPageState();
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

  bool _canSendCallSlip(Map<String, dynamic> data) => _isAwaitingCallSlip(data);

  bool _canMarkScheduledOutcome(Map<String, dynamic> data) {
    return _isScheduled(data) && !_isCompleted(data) && !_isCancelled(data);
  }

  bool _canReopenBooking(Map<String, dynamic> data) {
    return _isMissed(data) && !_isCompleted(data) && !_isCancelled(data);
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

  Widget _detailCard({required String title, required Widget child}) {
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
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool primaryButton = false,
    bool dangerButton = false,
    bool loading = false,
  }) {
    final foreground = dangerButton ? Colors.red.shade700 : primary;

    if (primaryButton) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: dangerButton ? Colors.red.shade700 : primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        icon: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(icon, size: 18),
        label: Text(
          loading ? 'Processing...' : label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        side: BorderSide(color: foreground.withValues(alpha: 0.60)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(foreground),
              ),
            )
          : Icon(icon, size: 18),
      label: Text(
        loading ? 'Processing...' : label,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildCaseActions(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final caseId = doc.id;
    final busy = _isActionBusy(caseId);

    final canSendCallSlip = _canSendCallSlip(data);
    final canMarkOutcome = _canMarkScheduledOutcome(data);
    final canReopen = _canReopenBooking(data);

    if (!canSendCallSlip && !canMarkOutcome && !canReopen) {
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

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canSendCallSlip)
          _buildActionButton(
            icon: Icons.mark_email_unread_outlined,
            label: 'Send Call Slip',
            primaryButton: true,
            loading: busy,
            onPressed: busy
                ? null
                : () => _runCaseAction(
                    caseId: caseId,
                    title: 'Send counseling call slip?',
                    message:
                        'The student will be notified and can start booking an appointment.',
                    successMessage:
                        'Call slip sent. Student can now book an appointment.',
                    confirmLabel: 'Send Slip',
                    action: () => _workflowService.sendCallSlip(caseId: caseId),
                  ),
          ),
        if (canMarkOutcome)
          _buildActionButton(
            icon: Icons.check_circle_outline_rounded,
            label: 'Mark Completed',
            primaryButton: true,
            loading: busy,
            onPressed: busy
                ? null
                : () => _runCaseAction(
                    caseId: caseId,
                    title: 'Mark appointment completed?',
                    message:
                        'This will close the case as completed and move it to Closed.',
                    successMessage: 'Appointment marked as completed.',
                    confirmLabel: 'Mark Completed',
                    action: () => _workflowService.markAppointmentCompleted(
                      caseId: caseId,
                    ),
                  ),
          ),
        if (canMarkOutcome)
          _buildActionButton(
            icon: Icons.event_busy_rounded,
            label: 'Mark Missed',
            dangerButton: true,
            loading: busy,
            onPressed: busy
                ? null
                : () => _runCaseAction(
                    caseId: caseId,
                    title: 'Mark appointment as missed?',
                    message:
                        'The case will move to missed status and can be reopened for rebooking.',
                    successMessage: 'Appointment marked as missed.',
                    confirmLabel: 'Mark Missed',
                    action: () =>
                        _workflowService.markAppointmentMissed(caseId: caseId),
                  ),
          ),
        if (canReopen)
          _buildActionButton(
            icon: Icons.restart_alt_rounded,
            label: 'Reopen Booking',
            loading: busy,
            onPressed: busy
                ? null
                : () => _runCaseAction(
                    caseId: caseId,
                    title: 'Reopen booking for student?',
                    message:
                        'The student will be allowed to book a new counseling appointment.',
                    successMessage: 'Booking reopened for this case.',
                    confirmLabel: 'Reopen',
                    action: () => _workflowService.reopenBookingAfterMissed(
                      caseId: caseId,
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _reasonsSection(Map<String, dynamic> reasons) {
    Widget listBlock(String label, List<String> values) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: hint,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            if (values.isEmpty)
              const Text(
                '-',
                style: TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              )
            else
              ...values.map(
                (value) => Text(
                  '- $value',
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final mood = _reasonList(reasons, 'moodsBehaviors');
    final school = _reasonList(reasons, 'schoolConcerns');
    final relationships = _reasonList(reasons, 'relationships');
    final home = _reasonList(reasons, 'homeConcerns');

    final otherMood = _safe(reasons['otherMood']);
    final otherSchool = _safe(reasons['otherSchool']);
    final otherRelationship = _safe(reasons['otherRelationship']);
    final otherHome = _safe(reasons['otherHome']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        listBlock(
          'Moods / Behaviors',
          otherMood.isEmpty ? mood : [...mood, 'Other: $otherMood'],
        ),
        listBlock(
          'School Concerns',
          otherSchool.isEmpty ? school : [...school, 'Other: $otherSchool'],
        ),
        listBlock(
          'Relationships',
          otherRelationship.isEmpty
              ? relationships
              : [...relationships, 'Other: $otherRelationship'],
        ),
        listBlock(
          'Home Concerns',
          otherHome.isEmpty ? home : [...home, 'Other: $otherHome'],
        ),
      ],
    );
  }

  DateTime? _activityDate(Map<String, dynamic> data) {
    final createdAt = _toDate(data['createdAt']);
    if (createdAt != null) return createdAt;
    final epoch = (data['createdAtEpochMs'] as num?)?.toInt();
    if (epoch == null || epoch <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(epoch);
  }

  Widget _buildActivityTimeline(String caseId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('counseling_cases')
          .doc(caseId)
          .collection('activity')
          .orderBy('createdAtEpochMs', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Could not load activity timeline.',
            style: TextStyle(
              color: hint,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Text(
            'No activity logs yet.',
            style: TextStyle(
              color: hint,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          );
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data();
            final title = _safe(data['title']).isEmpty
                ? _safe(data['event'])
                : _safe(data['title']);
            final description = _safe(data['description']);
            final actorRole = _safe(data['actorRole']);
            final when = _activityDate(data);
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? 'Activity' : title,
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.8,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        color: hint,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.2,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${actorRole.isEmpty ? 'system' : actorRole} | ${_fmtDateTime(when)}',
                    style: const TextStyle(
                      color: hint,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDetailPane(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final source = _safe(data['referralSource']).toLowerCase();
    final isSelfReferral =
        source == CounselingCaseWorkflow.referralSourceStudent;
    final referralDate = _toDate(data['referralDate']);
    final createdAt = _toDate(data['createdAt']);
    final updatedAt = _toDate(data['updatedAt']);
    final scheduledAt = _toDate(data['scheduledAt']);
    final reasons =
        (data['reasons'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final comments = _safe(data['comments']);

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
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: primary.withValues(alpha: 0.22),
                            ),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: primary,
                            size: 24,
                          ),
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
                    title: 'Referral Information',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv(
                          'Source',
                          _prettySource(_safe(data['referralSource'])),
                        ),
                        _kv(
                          'Referral Type',
                          _prettyType(_safe(data['counselingType'])),
                        ),
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
                        if (!isSelfReferral)
                          _kv(
                            'Call Slip',
                            _safe(data['callSlipStatus']).isEmpty
                                ? '-'
                                : _titleCase(
                                    _safe(data['callSlipStatus']).replaceAll(
                                      '_',
                                      ' ',
                                    ),
                                  ),
                          ),
                        _kv('Scheduled At', _fmtDateTime(scheduledAt)),
                        if (!isSelfReferral)
                          _kv(
                            'Referred By',
                            _safe(data['referredBy']).isEmpty
                                ? '-'
                                : _safe(data['referredBy']),
                          ),
                        _kv('Referral Date', _fmtDate(referralDate)),
                        _kv('Created At', _fmtDateTime(createdAt)),
                        _kv('Updated At', _fmtDateTime(updatedAt)),
                      ],
                    ),
                  ),
                  _detailCard(title: 'Actions', child: _buildCaseActions(doc)),
                  _detailCard(
                    title: 'Concerns',
                    child: _reasonsSection(reasons),
                  ),
                  _detailCard(
                    title: 'Comments',
                    child: Text(
                      comments.isEmpty ? '-' : comments,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                  _detailCard(
                    title: 'Activity Timeline',
                    child: _buildActivityTimeline(doc.id),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
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
      backgroundColor: Colors.transparent,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
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
              action: null,
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
              detailsWidth: (constraints.maxWidth * 0.40).clamp(390.0, 520.0),
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

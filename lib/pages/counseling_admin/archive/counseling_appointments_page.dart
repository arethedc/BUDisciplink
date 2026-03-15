import 'package:apps/pages/shared/widgets/modern_table_layout.dart';
import 'package:apps/services/counseling_case_workflow_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  final TextEditingController _searchCtrl = TextEditingController();
  final CounselingCaseWorkflowService _workflowService =
      CounselingCaseWorkflowService();

  int _tab = 0; // 0 queue, 1 closed
  String _sourceFilter = 'all';
  String _typeFilter = 'all';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$count overdue scheduled counseling appointment(s) were marked missed.',
            ),
            backgroundColor: primary,
          ),
        );
      } else if (showResult) {
        ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
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

  Widget _buildSweepActionButton() {
    return OutlinedButton.icon(
      onPressed: _sweepRunning ? null : () => _runExpirySweep(showResult: true),
      icon: _sweepRunning
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 18),
      label: Text(
        _sweepRunning ? 'Running...' : 'Run Sweep',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary.withValues(alpha: 0.50)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _safe(dynamic value) => (value ?? '').toString().trim();

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage), backgroundColor: primary),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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

  Widget _buildFilterChip({
    required String label,
    required String current,
    required List<Map<String, String>> options,
    required ValueChanged<String> onSelected,
  }) {
    final currentLabel =
        options.firstWhere(
          (option) => option['value'] == current,
          orElse: () => options.first,
        )['label'] ??
        current;
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => options
          .map(
            (option) => PopupMenuItem<String>(
              value: option['value']!,
              child: Text(option['label']!),
            ),
          )
          .toList(),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: current == 'all'
              ? Colors.transparent
              : primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: current == 'all' ? Colors.grey.shade300 : primary,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: $currentLabel',
              style: TextStyle(
                color: current == 'all' ? textDark : primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
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
    final referralDate = _toDate(data['referralDate']);
    final createdAt = _toDate(data['createdAt']);
    final updatedAt = _toDate(data['updatedAt']);
    final scheduledAt = _toDate(data['scheduledAt']);
    final reasons =
        (data['reasons'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final comments = _safe(data['comments']);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: ListView(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F6F1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primary.withValues(alpha: 0.20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.badge_rounded, color: primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _safe(data['studentName']).isEmpty
                        ? 'Unknown Student'
                        : _safe(data['studentName']),
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _detailCard(
            title: 'Case Information',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(
                  'Case Code',
                  _safe(data['caseCode']).isEmpty
                      ? doc.id
                      : _safe(data['caseCode']),
                ),
                _kv('Source', _prettySource(_safe(data['referralSource']))),
                _kv('Type', _prettyType(_safe(data['counselingType']))),
                _kv('Status', _statusText(data)),
                _kv(
                  'Meeting',
                  _safe(data['meetingStatus']).isEmpty
                      ? '-'
                      : _titleCase(
                          _safe(data['meetingStatus']).replaceAll('_', ' '),
                        ),
                ),
                _kv(
                  'Call Slip',
                  _safe(data['callSlipStatus']).isEmpty
                      ? '-'
                      : _titleCase(
                          _safe(data['callSlipStatus']).replaceAll('_', ' '),
                        ),
                ),
                _kv('Scheduled At', _fmtDateTime(scheduledAt)),
                _kv(
                  'Student No',
                  _safe(data['studentNo']).isEmpty
                      ? '-'
                      : _safe(data['studentNo']),
                ),
                _kv(
                  'Program',
                  _safe(data['studentProgramId']).isEmpty
                      ? '-'
                      : _safe(data['studentProgramId']),
                ),
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
            title: 'Activity Timeline',
            child: _buildActivityTimeline(doc.id),
          ),
          _detailCard(title: 'Concerns', child: _reasonsSection(reasons)),
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

        final query = _searchCtrl.text.trim().toLowerCase();
        final docs = snap.data!.docs.where((doc) {
          final data = doc.data();
          final source = _safe(data['referralSource']).toLowerCase();
          final type = _safe(data['counselingType']).toLowerCase();
          final student = _safe(data['studentName']).toLowerCase();
          final studentNo = _safe(data['studentNo']).toLowerCase();
          final program = _safe(data['studentProgramId']).toLowerCase();
          final statusLabel = _statusText(data).toLowerCase();

          final closed = _isClosedCase(data);
          if (_tab == 0 && closed) return false;
          if (_tab == 1 && !closed) return false;

          if (_sourceFilter != 'all' && source != _sourceFilter) return false;
          if (_typeFilter != 'all' && type != _typeFilter) return false;

          if (query.isNotEmpty &&
              !student.contains(query) &&
              !studentNo.contains(query) &&
              !program.contains(query) &&
              !statusLabel.contains(query)) {
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
            return ModernTableLayout(
              header: ModernTableHeader(
                title: 'Counseling Queue',
                subtitle:
                    'Review referrals from students and professors and manage booking flow.',
                action: _buildSweepActionButton(),
                searchBar: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search student, status, or program',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
                tabs: Row(
                  children: [
                    _TopTab(
                      label: 'Queue',
                      selected: _tab == 0,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    const SizedBox(width: 8),
                    _TopTab(
                      label: 'Closed',
                      selected: _tab == 1,
                      onTap: () => setState(() => _tab = 1),
                    ),
                  ],
                ),
                filters: [
                  _buildFilterChip(
                    label: 'Source',
                    current: _sourceFilter,
                    options: const [
                      {'value': 'all', 'label': 'All'},
                      {'value': 'student', 'label': 'Self-referral'},
                      {'value': 'professor', 'label': 'Professor referral'},
                    ],
                    onSelected: (value) =>
                        setState(() => _sourceFilter = value),
                  ),
                  _buildFilterChip(
                    label: 'Type',
                    current: _typeFilter,
                    options: const [
                      {'value': 'all', 'label': 'All'},
                      {'value': 'academic', 'label': 'Academic'},
                      {'value': 'personal', 'label': 'Personal'},
                    ],
                    onSelected: (value) => setState(() => _typeFilter = value),
                  ),
                ],
              ),
              body: docs.isEmpty
                  ? const Center(
                      child: Text(
                        'No referrals found.',
                        style: TextStyle(
                          color: hint,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: docs.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final selected = _selectedId == doc.id;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            if (isDesktop) {
                              setState(() {
                                _selectedId = selected ? '' : doc.id;
                              });
                            } else {
                              _openMobileDetails(doc);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                            decoration: BoxDecoration(
                              color: selected
                                  ? primary.withValues(alpha: 0.07)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? primary.withValues(alpha: 0.45)
                                    : Colors.black.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _safe(data['studentName']).isEmpty
                                            ? 'Unknown Student'
                                            : _safe(data['studentName']),
                                        style: const TextStyle(
                                          color: textDark,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          Text(
                                            _prettySource(
                                              _safe(data['referralSource']),
                                            ),
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
                                            _prettyType(
                                              _safe(data['counselingType']),
                                            ),
                                            style: const TextStyle(
                                              color: hint,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            '| ${_fmtDate(_toDate(data['createdAt']))}',
                                            style: const TextStyle(
                                              color: hint,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _buildStatusPill(data),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.black45,
                                ),
                              ],
                            ),
                          ),
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
}

class _TopTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TopTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFF1B5E20).withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF1B5E20)
                  : const Color(0xFF6D7F62),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

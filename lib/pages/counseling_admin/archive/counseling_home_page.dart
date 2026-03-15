import 'package:apps/services/counseling_case_workflow_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CounselingHomePage extends StatelessWidget {
  const CounselingHomePage({super.key});

  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hint = Color(0xFF6D7F62);

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _safe(dynamic value) => (value ?? '').toString().trim();

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

  bool _isClosed(Map<String, dynamic> data) {
    return CounselingCaseState.isClosed(data);
  }

  String _titleCase(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    return parts
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
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

  String _sourceText(Map<String, dynamic> data) {
    final source = _safe(data['referralSource']).toLowerCase();
    if (source == CounselingCaseWorkflow.referralSourceStudent) {
      return 'Self-referral';
    }
    if (source == CounselingCaseWorkflow.referralSourceProfessor) {
      return 'Professor referral';
    }
    return source.isEmpty ? 'Unknown' : _titleCase(source);
  }

  String _fmtDateTime(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('MMM d, yyyy - h:mm a').format(value);
  }

  Widget _kpiCard({
    required String label,
    required int value,
    required IconData icon,
    required double width,
    Color? iconColor,
  }) {
    final tone = iconColor ?? primary;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: tone, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: hint,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(Map<String, dynamic> data) {
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('counseling_cases')
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text('Error loading dashboard: ${snap.error}'),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          final now = DateTime.now();
          final activeQueueCount = docs
              .where((d) => !_isClosed(d.data()))
              .length;
          final awaitingCallSlipCount = docs
              .where((d) => _isAwaitingCallSlip(d.data()))
              .length;
          final bookingRequiredCount = docs
              .where((d) => _isBookingRequired(d.data()))
              .length;
          final missedCount = docs.where((d) => _isMissed(d.data())).length;
          final completedCount = docs
              .where((d) => _isCompleted(d.data()))
              .length;
          final upcomingCount = docs.where((d) {
            final data = d.data();
            if (!_isScheduled(data)) return false;
            final scheduledAt = _toDate(data['scheduledAt']);
            return scheduledAt != null && scheduledAt.isAfter(now);
          }).length;

          final recentDocs = docs.take(10).toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final cardsPerRow = width >= 1400
                  ? 4
                  : width >= 1024
                  ? 3
                  : width >= 720
                  ? 2
                  : 1;
              final cardWidth = ((width - 48) / cardsPerRow) - 10;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Counseling Overview',
                            style: TextStyle(
                              color: primary,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Live referral queue, booking progress, and appointment outcomes.',
                            style: TextStyle(
                              color: hint,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _kpiCard(
                          label: 'Active Queue',
                          value: activeQueueCount,
                          icon: Icons.inbox_rounded,
                          width: cardWidth,
                        ),
                        _kpiCard(
                          label: 'Awaiting Call Slip',
                          value: awaitingCallSlipCount,
                          icon: Icons.mark_email_unread_outlined,
                          width: cardWidth,
                          iconColor: Colors.orange.shade700,
                        ),
                        _kpiCard(
                          label: 'Booking Required',
                          value: bookingRequiredCount,
                          icon: Icons.event_note_rounded,
                          width: cardWidth,
                          iconColor: primary,
                        ),
                        _kpiCard(
                          label: 'Upcoming Sessions',
                          value: upcomingCount,
                          icon: Icons.schedule_rounded,
                          width: cardWidth,
                          iconColor: Colors.blue.shade700,
                        ),
                        _kpiCard(
                          label: 'Missed',
                          value: missedCount,
                          icon: Icons.event_busy_rounded,
                          width: cardWidth,
                          iconColor: Colors.red.shade700,
                        ),
                        _kpiCard(
                          label: 'Completed',
                          value: completedCount,
                          icon: Icons.task_alt_rounded,
                          width: cardWidth,
                          iconColor: Colors.green.shade700,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recent Referrals',
                            style: TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Latest submitted counseling cases and current workflow status.',
                            style: TextStyle(
                              color: hint,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (recentDocs.isEmpty)
                            const Text(
                              'No counseling referrals yet.',
                              style: TextStyle(
                                color: hint,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: recentDocs.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final doc = recentDocs[index];
                                final data = doc.data();
                                final studentName =
                                    _safe(data['studentName']).isEmpty
                                    ? 'Unknown Student'
                                    : _safe(data['studentName']);
                                final caseCode = _safe(data['caseCode']).isEmpty
                                    ? doc.id
                                    : _safe(data['caseCode']);
                                final createdAt = _toDate(data['createdAt']);

                                return Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7FBF7),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.black.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              studentName,
                                              style: const TextStyle(
                                                color: textDark,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '$caseCode | ${_sourceText(data)}',
                                              style: const TextStyle(
                                                color: hint,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _fmtDateTime(createdAt),
                                              style: const TextStyle(
                                                color: hint,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _statusPill(data),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

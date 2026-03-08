import 'package:apps/pages/shared/widgets/modern_table_layout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CounselingAppointmentsPage extends StatefulWidget {
  const CounselingAppointmentsPage({super.key});

  @override
  State<CounselingAppointmentsPage> createState() =>
      _CounselingAppointmentsPageState();
}

class _CounselingAppointmentsPageState extends State<CounselingAppointmentsPage> {
  static const primary = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hint = Color(0xFF6D7F62);

  final TextEditingController _searchCtrl = TextEditingController();

  int _tab = 0; // 0 queue, 1 closed
  String _sourceFilter = 'all';
  String _typeFilter = 'all';
  String _selectedId = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  String _fmtDate(DateTime? value) {
    if (value == null) return '—';
    return DateFormat('MMM d, yyyy').format(value);
  }

  String _fmtDateTime(DateTime? value) {
    if (value == null) return '—';
    return DateFormat('MMM d, yyyy • h:mm a').format(value);
  }

  bool _isClosedStatus(String status) {
    final s = status.toLowerCase();
    return s.contains('closed') ||
        s.contains('completed') ||
        s.contains('resolved');
  }

  String _prettySource(String source) {
    final s = source.toLowerCase().trim();
    if (s == 'student') return 'Self-referral';
    if (s == 'professor') return 'Professor referral';
    return s.isEmpty ? 'Unknown' : s;
  }

  String _prettyType(String type) {
    final t = type.toLowerCase().trim();
    if (t == 'academic') return 'Academic';
    if (t == 'personal') return 'Personal';
    return t.isEmpty ? '—' : t;
  }

  String _prettyStatus(String status) {
    final s = status.toLowerCase().trim().replaceAll('_', ' ');
    if (s.isEmpty) return 'Submitted';
    return s
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('closed') || s.contains('completed') || s.contains('resolved')) {
      return Colors.green;
    }
    if (s.contains('meeting') || s.contains('scheduled')) {
      return Colors.blue;
    }
    if (s.contains('missed')) return Colors.red;
    if (s.contains('assessment') || s.contains('review')) return Colors.orange;
    return Colors.grey.shade700;
  }

  List<String> _reasonList(Map<String, dynamic> reasons, String key) {
    final raw = reasons[key];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    return const [];
  }

  Widget _buildFilterChip({
    required String label,
    required String current,
    required List<Map<String, String>> options,
    required ValueChanged<String> onSelected,
  }) {
    final currentLabel = options
            .firstWhere(
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
          color: current == 'all' ? Colors.transparent : primary.withValues(alpha: 0.10),
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

  Widget _buildStatusPill(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _prettyStatus(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
        ),
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
          const SizedBox(height: 8),
          child,
        ],
      ),
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
                '—',
                style: TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              )
            else
              ...values.map(
                (value) => Text(
                  '• $value',
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

    final otherMood = (reasons['otherMood'] ?? '').toString().trim();
    final otherSchool = (reasons['otherSchool'] ?? '').toString().trim();
    final otherRelationship = (reasons['otherRelationship'] ?? '').toString().trim();
    final otherHome = (reasons['otherHome'] ?? '').toString().trim();

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

  Widget _buildDetailPane(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final referralDate = _toDate(data['referralDate']);
    final createdAt = _toDate(data['createdAt']);
    final updatedAt = _toDate(data['updatedAt']);
    final reasons = (data['reasons'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final comments = (data['comments'] ?? '').toString().trim();

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
                    (data['studentName'] ?? 'Unknown Student').toString(),
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
                _kv('Source', _prettySource((data['referralSource'] ?? '').toString())),
                _kv('Type', _prettyType((data['counselingType'] ?? '').toString())),
                _kv('Status', _prettyStatus((data['status'] ?? '').toString())),
                _kv('Student No', (data['studentNo'] ?? '—').toString()),
                _kv('Program', (data['studentProgramId'] ?? '—').toString()),
                _kv('Referred By', (data['referredBy'] ?? '—').toString()),
                _kv('Referral Date', _fmtDate(referralDate)),
                _kv('Created At', _fmtDateTime(createdAt)),
                _kv('Updated At', _fmtDateTime(updatedAt)),
              ],
            ),
          ),
          _detailCard(
            title: 'Concerns',
            child: _reasonsSection(reasons),
          ),
          _detailCard(
            title: 'Comments',
            child: Text(
              comments.isEmpty ? '—' : comments,
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
            width: 100,
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

  Future<void> _openMobileDetails(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
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
          final status = (data['status'] ?? '').toString().trim();
          final source = (data['referralSource'] ?? '').toString().trim().toLowerCase();
          final type = (data['counselingType'] ?? '').toString().trim().toLowerCase();
          final student = (data['studentName'] ?? '').toString().toLowerCase();
          final studentNo = (data['studentNo'] ?? '').toString().toLowerCase();
          final program = (data['studentProgramId'] ?? '').toString().toLowerCase();

          final closed = _isClosedStatus(status);
          if (_tab == 0 && closed) return false;
          if (_tab == 1 && !closed) return false;

          if (_sourceFilter != 'all' && source != _sourceFilter) return false;
          if (_typeFilter != 'all' && type != _typeFilter) return false;

          if (query.isNotEmpty &&
              !student.contains(query) &&
              !studentNo.contains(query) &&
              !program.contains(query) &&
              !status.toLowerCase().contains(query)) {
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
                    'Review referrals from students and professors before scheduling.',
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
                    onSelected: (value) => setState(() => _sourceFilter = value),
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
                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final status = (data['status'] ?? '').toString();
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (data['studentName'] ?? 'Unknown Student')
                                            .toString(),
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
                                              (data['referralSource'] ?? '')
                                                  .toString(),
                                            ),
                                            style: const TextStyle(
                                              color: hint,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            '•',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            _prettyType(
                                              (data['counselingType'] ?? '')
                                                  .toString(),
                                            ),
                                            style: const TextStyle(
                                              color: hint,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            '• ${_fmtDate(_toDate(data['createdAt']))}',
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
                                _buildStatusPill(status),
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
              details: selectedDoc == null ? null : _buildDetailPane(selectedDoc),
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
              color: selected ? const Color(0xFF1B5E20) : const Color(0xFF6D7F62),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

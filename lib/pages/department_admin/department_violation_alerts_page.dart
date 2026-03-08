import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../shared/widgets/modern_table_layout.dart';

class DepartmentViolationAlertsPage extends StatefulWidget {
  const DepartmentViolationAlertsPage({super.key});

  @override
  State<DepartmentViolationAlertsPage> createState() =>
      _DepartmentViolationAlertsPageState();
}

class _DepartmentViolationAlertsPageState
    extends State<DepartmentViolationAlertsPage> {
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);
  static const surface = Color(0xFFFFFFFF);

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _scopeFilter = 'new';
  String? _selectedCaseId;
  bool _savingSeen = false;
  bool _savingNote = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  DateTime? _toDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  String _safeStr(dynamic value) => (value ?? '').toString().trim();

  String _fullNameFromUser(Map<String, dynamic> userData) {
    final dn = _safeStr(userData['displayName']);
    if (dn.isNotEmpty) return dn;
    final first = _safeStr(userData['firstName']);
    final last = _safeStr(userData['lastName']);
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    final email = _safeStr(userData['email']);
    if (email.contains('@')) return email.split('@').first;
    return 'Department Admin';
  }

  String _studentName(Map<String, dynamic> userData) {
    final display = _safeStr(userData['displayName']);
    if (display.isNotEmpty) return display;
    final first = _safeStr(userData['firstName']);
    final last = _safeStr(userData['lastName']);
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    return _safeStr(userData['email']);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '--';
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  bool _isSeenBy(Map<String, dynamic> data, String uid) {
    final raw = data['deptSeenByUids'];
    if (raw is! List) return false;
    return raw.any((e) => e.toString().trim() == uid);
  }

  Color _statusColor(String statusRaw) {
    final status = statusRaw.toLowerCase().trim();
    if (status == 'resolved') return const Color(0xFF2E7D32);
    if (status == 'action set') return const Color(0xFF0D47A1);
    if (status == 'submitted' || status == 'under review') {
      return const Color(0xFFD97706);
    }
    return const Color(0xFF455A64);
  }

  String _statusLabel(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return 'Submitted';
    if (s == 'action set') return 'Monitoring';
    if (s == 'under review') return 'Under Review';
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  int _scopeIndex() {
    switch (_scopeFilter) {
      case 'new':
        return 0;
      case 'week':
        return 1;
      default:
        return 2;
    }
  }

  String _scopeFromIndex(int index) {
    if (index == 0) return 'new';
    if (index == 1) return 'week';
    return 'all';
  }

  bool _hasActiveFilter() {
    return _scopeFilter != 'new' || _searchCtrl.text.trim().isNotEmpty;
  }

  void _clearFilters() {
    setState(() {
      _scopeFilter = 'new';
      _searchCtrl.clear();
      _selectedCaseId = null;
    });
  }

  Widget _scopeTabs() {
    return DefaultTabController(
      key: ValueKey(_scopeFilter),
      length: 3,
      initialIndex: _scopeIndex(),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: primary,
        indicatorColor: primary,
        dividerColor: Colors.transparent,
        onTap: (index) {
          final next = _scopeFromIndex(index);
          if (next == _scopeFilter) return;
          setState(() {
            _scopeFilter = next;
            _selectedCaseId = null;
          });
        },
        tabs: const [
          Tab(text: 'New / Unseen'),
          Tab(text: 'This Week'),
          Tab(text: 'All Alerts'),
        ],
      ),
    );
  }

  Widget _statChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterCases({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required Map<String, String> studentNameByUid,
    required String uid,
  }) {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final needle = _searchCtrl.text.trim().toLowerCase();

    final filtered = docs.where((doc) {
      final d = doc.data();
      final seen = _isSeenBy(d, uid);
      final createdAt = _toDate(d['createdAt']) ?? _toDate(d['incidentAt']);

      if (_scopeFilter == 'new' && seen) return false;
      if (_scopeFilter == 'week') {
        if (createdAt == null || createdAt.isBefore(weekStart)) return false;
      }

      if (needle.isNotEmpty) {
        final caseCode = _safeStr(d['caseCode']).toLowerCase();
        final violation = _safeStr(
          d['violationTypeLabel'] ??
              d['violationNameSnapshot'] ??
              d['violationName'],
        ).toLowerCase();
        final status = _safeStr(d['status']).toLowerCase();
        final studentUid = _safeStr(d['studentUid']);
        final student = _safeStr(studentNameByUid[studentUid]).toLowerCase();

        if (!caseCode.contains(needle) &&
            !violation.contains(needle) &&
            !status.contains(needle) &&
            !student.contains(needle)) {
          return false;
        }
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final ad = _toDate(a.data()['createdAt']) ?? DateTime(2000);
      final bd = _toDate(b.data()['createdAt']) ?? DateTime(2000);
      return bd.compareTo(ad);
    });
    return filtered;
  }

  Future<void> _markSeen({
    required DocumentReference<Map<String, dynamic>> ref,
    required String uid,
  }) async {
    if (_savingSeen) return;
    setState(() => _savingSeen = true);
    try {
      await ref.set({
        'deptSeenByUids': FieldValue.arrayUnion([uid]),
        'deptSeenAt': {uid: FieldValue.serverTimestamp()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as seen.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark seen: $error')));
    } finally {
      if (mounted) setState(() => _savingSeen = false);
    }
  }

  Future<void> _saveDepartmentNote({
    required DocumentReference<Map<String, dynamic>> ref,
    required String uid,
    required String authorName,
    required String department,
  }) async {
    final note = _noteCtrl.text.trim();
    if (note.isEmpty || _savingNote) return;

    setState(() => _savingNote = true);
    try {
      await ref.set({
        'departmentNotes': FieldValue.arrayUnion([
          {
            'uid': uid,
            'name': authorName,
            'department': department,
            'note': note,
            'createdAt': FieldValue.serverTimestamp(),
          },
        ]),
        'deptSeenByUids': FieldValue.arrayUnion([uid]),
        'deptSeenAt': {uid: FieldValue.serverTimestamp()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _noteCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Department note saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save note: $error')));
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: hint,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.isEmpty ? '--' : value,
          style: const TextStyle(
            color: textDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _detailCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _tableHeaderText(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        color: hint,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildNotesList(Map<String, dynamic> caseData) {
    final raw = caseData['departmentNotes'];
    if (raw is! List || raw.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Text(
          'No department notes yet.',
          style: TextStyle(
            color: hint,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    final entries = raw.whereType<Map>().map((e) {
      final map = Map<String, dynamic>.from(e);
      final created = _toDate(map['createdAt']);
      return {'data': map, 'createdAt': created};
    }).toList();

    entries.sort((a, b) {
      final ad = a['createdAt'] as DateTime? ?? DateTime(2000);
      final bd = b['createdAt'] as DateTime? ?? DateTime(2000);
      return bd.compareTo(ad);
    });

    return Column(
      children: entries.take(5).map((entry) {
        final note = entry['data'] as Map<String, dynamic>;
        final author = _safeStr(note['name']).isEmpty
            ? 'Department Admin'
            : _safeStr(note['name']);
        final text = _safeStr(note['note']);
        final created = _formatDate(entry['createdAt'] as DateTime?);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
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
                      author,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    created,
                    style: TextStyle(
                      color: hint,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                text.isEmpty ? '--' : text,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDetailPane({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String studentName,
    required String currentUid,
    required String adminName,
    required String department,
    required bool isSheet,
    VoidCallback? onClose,
  }) {
    final d = doc.data();
    final seen = _isSeenBy(d, currentUid);
    final caseCode = _safeStr(d['caseCode']).isEmpty ? doc.id : _safeStr(d['caseCode']);
    final violation = _safeStr(
      d['violationTypeLabel'] ?? d['violationNameSnapshot'] ?? d['violationName'],
    );
    final category = _safeStr(d['categoryNameSnapshot']);
    final statusRaw = _safeStr(d['status']);
    final severity = _safeStr(
      d['finalSeverity'] ?? d['assessedSeverity'] ?? d['severityLevel'],
    );
    final reportedBy = _safeStr(d['reportedByName']);
    final createdAt = _toDate(d['createdAt']) ?? _toDate(d['incidentAt']);
    final correctionReason = _safeStr(
      (d['correction'] as Map<String, dynamic>?)?['latestReason'],
    );
    final evidenceCount = d['evidenceUrls'] is List ? (d['evidenceUrls'] as List).length : 0;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Case $caseCode',
                style: const TextStyle(
                  fontSize: 18,
                  color: textDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              seen ? 'Seen' : 'New',
              seen ? const Color(0xFF2E7D32) : const Color(0xFFD97706),
            ),
            _chip(_statusLabel(statusRaw), _statusColor(statusRaw)),
          ],
        ),
        const SizedBox(height: 14),
        _detailCard(
          title: 'Case Summary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Student', studentName),
              const SizedBox(height: 10),
              _kv('Violation', violation),
              const SizedBox(height: 10),
              _kv('Category', category),
              const SizedBox(height: 10),
              _kv('Severity', severity.isEmpty ? '--' : severity),
              const SizedBox(height: 10),
              _kv('Reported by', reportedBy),
              const SizedBox(height: 10),
              _kv('Submitted at', _formatDate(createdAt)),
              const SizedBox(height: 10),
              _kv('Evidence files', '$evidenceCount'),
              if (correctionReason.isNotEmpty) ...[
                const SizedBox(height: 10),
                _kv('OSA correction note', correctionReason),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _detailCard(
          title: 'Department Action',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: seen || _savingSeen
                          ? null
                          : () => _markSeen(ref: doc.reference, uid: currentUid),
                      icon: _savingSeen
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.visibility_rounded, size: 18),
                      label: Text(seen ? 'Already Seen' : 'Mark as Seen'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: BorderSide(color: primary.withValues(alpha: 0.35)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                minLines: 3,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Add a note for department records...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _savingNote
                      ? null
                      : () => _saveDepartmentNote(
                            ref: doc.reference,
                            uid: currentUid,
                            authorName: adminName,
                            department: department,
                          ),
                  icon: _savingNote
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save Department Note'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _detailCard(
          title: 'Recent Notes',
          child: _buildNotesList(d),
        ),
      ],
    );

    if (isSheet) {
      return Container(
        color: bg,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(child: body),
      );
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMobileDetails({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String studentName,
    required String currentUid,
    required String adminName,
    required String department,
  }) {
    _noteCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.60,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: _buildDetailPane(
                doc: doc,
                studentName: studentName,
                currentUid: currentUid,
                adminName: adminName,
                department: department,
                isSheet: true,
                onClose: () => Navigator.of(context).pop(),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, adminSnap) {
        if (!adminSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final adminData = adminSnap.data!.data() ?? <String, dynamic>{};
        final department = _safeStr(adminData['employeeProfile']?['department']);
        final adminName = _fullNameFromUser(adminData);

        if (department.isEmpty) {
          return Center(
            child: Text(
              'No department is assigned to your account.',
              style: TextStyle(
                color: hint,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'student')
              .snapshots(),
          builder: (context, studentsSnap) {
            if (!studentsSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final studentsByUid = <String, String>{};
            for (final doc in studentsSnap.data!.docs) {
              final d = doc.data();
              final collegeId = _safeStr(d['studentProfile']?['collegeId']);
              if (collegeId == department) {
                studentsByUid[doc.id] = _studentName(d);
              }
            }

            if (studentsByUid.isEmpty) {
              return Center(
                child: Text(
                  'No students found for department $department.',
                  style: TextStyle(
                    color: hint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('violation_cases')
                  .snapshots(),
              builder: (context, caseSnap) {
                if (!caseSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allCases = caseSnap.data!.docs.where((doc) {
                  final studentUid = _safeStr(doc.data()['studentUid']);
                  return studentsByUid.containsKey(studentUid);
                }).toList();

                final filtered = _filterCases(
                  docs: allCases,
                  studentNameByUid: studentsByUid,
                  uid: currentUser.uid,
                );

                QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
                if (_selectedCaseId != null) {
                  for (final doc in filtered) {
                    if (doc.id == _selectedCaseId) {
                      selectedDoc = doc;
                      break;
                    }
                  }
                }
                if (_selectedCaseId != null && selectedDoc == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _selectedCaseId = null);
                  });
                }

                final newCount = filtered
                    .where((doc) => !_isSeenBy(doc.data(), currentUser.uid))
                    .length;
                final width = MediaQuery.sizeOf(context).width;
                final useDesktopTable = width >= 900;
                final showSideDetails = width >= 1100;

                return Container(
                  color: bg,
                  child: ModernTableLayout(
                    detailsWidth: (width * 0.42).clamp(420.0, 560.0).toDouble(),
                    header: ModernTableHeader(
                      title: 'Violation Alerts',
                      subtitle: 'Read-only notifications for $department',
                      searchBar: TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search cases...',
                          prefixIcon: const Icon(Icons.search, color: primary),
                          filled: true,
                          fillColor: bg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      tabs: _scopeTabs(),
                      filters: [
                        _statChip(
                          label: 'Total',
                          value: '${filtered.length}',
                          color: const Color(0xFF455A64),
                        ),
                        const SizedBox(width: 8),
                        _statChip(
                          label: 'New',
                          value: '$newCount',
                          color: const Color(0xFFD97706),
                        ),
                        if (_hasActiveFilter()) ...[
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.filter_list_off, size: 16),
                            label: const Text('Clear Filters'),
                          ),
                        ],
                      ],
                    ),
                    body: _buildContent(
                      filtered: filtered,
                      studentsByUid: studentsByUid,
                      currentUid: currentUser.uid,
                      adminName: adminName,
                      department: department,
                      useDesktopTable: useDesktopTable,
                      showSideDetails: showSideDetails,
                    ),
                    showDetails: showSideDetails && selectedDoc != null,
                    details: selectedDoc == null
                        ? null
                        : _buildDetailPane(
                            doc: selectedDoc,
                            studentName:
                                studentsByUid[_safeStr(selectedDoc.data()['studentUid'])] ??
                                    '--',
                            currentUid: currentUser.uid,
                            adminName: adminName,
                            department: department,
                            isSheet: false,
                            onClose: () {
                              setState(() {
                                _selectedCaseId = null;
                                _noteCtrl.clear();
                              });
                            },
                          ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildContent({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered,
    required Map<String, String> studentsByUid,
    required String currentUid,
    required String adminName,
    required String department,
    required bool useDesktopTable,
    required bool showSideDetails,
  }) {
    if (filtered.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Center(
          child: Text(
            'No alerts found for this filter.',
            style: TextStyle(
              color: hint,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    if (!useDesktopTable) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = filtered[index];
            final d = doc.data();
            final studentUid = _safeStr(d['studentUid']);
            final studentName = studentsByUid[studentUid] ?? '--';
            final caseCode = _safeStr(d['caseCode']).isEmpty
                ? doc.id
                : _safeStr(d['caseCode']);
            final violation = _safeStr(
              d['violationTypeLabel'] ??
                  d['violationNameSnapshot'] ??
                  d['violationName'],
            );
            final statusRaw = _safeStr(d['status']);
            final seen = _isSeenBy(d, currentUid);
            final createdAt = _toDate(d['createdAt']) ?? _toDate(d['incidentAt']);

            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openMobileDetails(
                doc: doc,
                studentName: studentName,
                currentUid: currentUid,
                adminName: adminName,
                department: department,
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            caseCode,
                            style: const TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _chip(
                          seen ? 'Seen' : 'New',
                          seen
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFD97706),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      studentName,
                      style: TextStyle(
                        color: hint,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      violation.isEmpty ? '--' : violation,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _chip(_statusLabel(statusRaw), _statusColor(statusRaw)),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(createdAt),
                          style: TextStyle(
                            color: hint,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: const WidgetStatePropertyAll(bg),
                    columnSpacing: 24,
                    columns: [
                      DataColumn(label: _tableHeaderText('CASE NO')),
                      DataColumn(label: _tableHeaderText('STUDENT')),
                      DataColumn(label: _tableHeaderText('VIOLATION')),
                      DataColumn(label: _tableHeaderText('STATUS')),
                      DataColumn(label: _tableHeaderText('DATE')),
                      DataColumn(label: _tableHeaderText('SEEN')),
                    ],
                    rows: filtered.map((doc) {
                      final d = doc.data();
                      final selected = _selectedCaseId == doc.id;
                      final studentUid = _safeStr(d['studentUid']);
                      final studentName = studentsByUid[studentUid] ?? '--';
                      final caseCode = _safeStr(d['caseCode']).isEmpty
                          ? doc.id
                          : _safeStr(d['caseCode']);
                      final violation = _safeStr(
                        d['violationTypeLabel'] ??
                            d['violationNameSnapshot'] ??
                            d['violationName'],
                      );
                      final statusRaw = _safeStr(d['status']);
                      final seen = _isSeenBy(d, currentUid);
                      final createdAt =
                          _toDate(d['createdAt']) ?? _toDate(d['incidentAt']);

                      return DataRow(
                        selected: selected,
                        color: WidgetStateProperty.resolveWith((states) {
                          if (selected) return primary.withValues(alpha: 0.08);
                          return null;
                        }),
                        onSelectChanged: (_) {
                          if (showSideDetails) {
                            setState(() {
                              if (_selectedCaseId == doc.id) {
                                _selectedCaseId = null;
                              } else {
                                _selectedCaseId = doc.id;
                              }
                              _noteCtrl.clear();
                            });
                            return;
                          }

                          _openMobileDetails(
                            doc: doc,
                            studentName: studentName,
                            currentUid: currentUid,
                            adminName: adminName,
                            department: department,
                          );
                        },
                        cells: [
                          DataCell(Text(caseCode)),
                          DataCell(
                            Text(studentName, overflow: TextOverflow.ellipsis),
                          ),
                          DataCell(
                            SizedBox(
                              width: 230,
                              child: Text(
                                violation.isEmpty ? '--' : violation,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            _chip(_statusLabel(statusRaw), _statusColor(statusRaw)),
                          ),
                          DataCell(Text(_formatDate(createdAt))),
                          DataCell(
                            _chip(
                              seen ? 'Seen' : 'New',
                              seen
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFD97706),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

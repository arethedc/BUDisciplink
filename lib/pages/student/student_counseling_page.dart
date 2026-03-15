import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/counseling_case_workflow_service.dart';
import '../../services/osa_meeting_schedule_service.dart';

class StudentCounselingPage extends StatefulWidget {
  const StudentCounselingPage({super.key});

  @override
  State<StudentCounselingPage> createState() => _StudentCounselingPageState();
}

class _StudentCounselingPageState extends State<StudentCounselingPage> {
  static const bg = Color(0xFFF6FAF6);
  static const primaryColor = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  final _formKey = GlobalKey<FormState>();
  final _otherMoodCtrl = TextEditingController();
  final _otherSchoolCtrl = TextEditingController();
  final _otherRelationshipCtrl = TextEditingController();
  final _otherHomeCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();
  final _workflowService = CounselingCaseWorkflowService();

  String _studentUid = '';
  String _studentName = '';
  String _studentEmail = '';
  String _studentNo = '';
  String _programId = '';

  String _counselingType = 'academic';
  bool _loading = false;
  bool _loadingProfile = true;
  bool _sweepRunning = false;

  final Set<String> _moodsSelected = <String>{};
  final Set<String> _schoolSelected = <String>{};
  final Set<String> _relationshipSelected = <String>{};
  final Set<String> _homeSelected = <String>{};

  static const List<String> _moodOptions = <String>[
    'anxious/worried',
    'depressed/unhappy',
    'eating disorder',
    'body image concerns',
    'hyperactive/inattentive',
    'shy/withdrawn',
    'low self-esteem',
    'aggressive behaviors',
    'stealing',
  ];

  static const List<String> _schoolOptions = <String>[
    'homework not turned in',
    'not complete',
    'low test/assignment grades',
    'poor classroom performance',
    'sleeping in class/always tired',
    'sudden change in grades',
    'frequently tardy or absent',
    'new student',
  ];

  static const List<String> _relationshipOptions = <String>[
    'bullying',
    'difficulty making friends',
    'poor social skills',
    'problems with friends',
    'boy/girl friend issues',
  ];

  static const List<String> _homeOptions = <String>[
    'fighting with family members',
    'illness/death in the family',
    'parents divorced/separated',
    'suspected abuse',
    'suspected substance abuse',
    'parent request',
  ];

  @override
  void initState() {
    super.initState();
    _runStudentSafetySweep();
    _loadStudentProfile();
  }

  Future<void> _runStudentSafetySweep() async {
    if (_sweepRunning) return;
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    _sweepRunning = true;
    try {
      final count = await _workflowService
          .expireOverdueScheduledMeetingsForStudent(studentUid: uid);
      if (!mounted || count <= 0) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$count overdue counseling appointment(s) were updated to missed.',
          ),
          backgroundColor: primaryColor,
        ),
      );
    } catch (_) {
      // Best-effort safety refresh only.
    } finally {
      _sweepRunning = false;
    }
  }

  Future<void> _loadStudentProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingProfile = false);
      return;
    }

    _studentUid = user.uid;
    _studentEmail = user.email?.trim() ?? '';

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      final studentProfile =
          (data['studentProfile'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      final first = (data['firstName'] ?? '').toString().trim();
      final last = (data['lastName'] ?? '').toString().trim();
      final displayName = (data['displayName'] ?? '').toString().trim();
      final full = ('$first $last').trim();

      if (!mounted) return;
      setState(() {
        _studentName = displayName.isNotEmpty
            ? displayName
            : full.isNotEmpty
            ? full
            : _studentEmail.split('@').first;
        _studentNo = (studentProfile['studentNo'] ?? '').toString().trim();
        _programId = (studentProfile['programId'] ?? '').toString().trim();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _studentName = _studentEmail.split('@').first;
      });
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: hintColor,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(icon, color: primaryColor.withValues(alpha: 0.85)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  bool _hasAnyReasonSelected() {
    return _moodsSelected.isNotEmpty ||
        _schoolSelected.isNotEmpty ||
        _relationshipSelected.isNotEmpty ||
        _homeSelected.isNotEmpty ||
        _otherMoodCtrl.text.trim().isNotEmpty ||
        _otherSchoolCtrl.text.trim().isNotEmpty ||
        _otherRelationshipCtrl.text.trim().isNotEmpty ||
        _otherHomeCtrl.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_loading || _loadingProfile) return;
    if (_studentUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student account not found. Please login again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_hasAnyReasonSelected()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one concern.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final caseId = await _workflowService.submitSelfReferral(
        studentUid: _studentUid,
        studentName: _studentName,
        studentNo: _studentNo,
        studentProgramId: _programId,
        counselingType: _counselingType,
        reasons: {
          'moodsBehaviors': _moodsSelected.toList()..sort(),
          'schoolConcerns': _schoolSelected.toList()..sort(),
          'relationships': _relationshipSelected.toList()..sort(),
          'homeConcerns': _homeSelected.toList()..sort(),
          'otherMood': _otherMoodCtrl.text.trim(),
          'otherSchool': _otherSchoolCtrl.text.trim(),
          'otherRelationship': _otherRelationshipCtrl.text.trim(),
          'otherHome': _otherHomeCtrl.text.trim(),
        },
        comments: _commentsCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Self-referral submitted. Please select an appointment slot.',
          ),
          backgroundColor: primaryColor,
        ),
      );
      _resetFormAfterSubmit();
      await _openBookingDialogForCaseId(caseId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submission failed: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openBookingDialogForCaseId(String caseId) async {
    final caseDoc = await FirebaseFirestore.instance
        .collection('counseling_cases')
        .doc(caseId)
        .get();
    if (!mounted || !caseDoc.exists) return;
    final data = caseDoc.data() ?? <String, dynamic>{};
    await _openBookingDialog(caseId: caseId, data: data);
  }

  Future<void> _openBookingDialog({
    required String caseId,
    required Map<String, dynamic> data,
  }) async {
    final schoolYearId = (data['schoolYearId'] ?? '').toString().trim();
    final termId = (data['termId'] ?? '').toString().trim();
    if (schoolYearId.isEmpty || termId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Booking context is not ready yet. Please contact counseling admin.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final booked = await showDialog<bool>(
      context: context,
      builder: (_) => _BookCounselingSlotDialog(
        caseId: caseId,
        studentUid: _studentUid,
        schoolYearId: schoolYearId,
        termId: termId,
        bookingDeadlineAt: _toDate(data['bookingDeadlineAt']),
        bookingLeadHours:
            (data['bookingLeadHours'] as num?)?.toInt() ??
            CounselingCaseWorkflow.bookingLeadTime.inHours,
        openSlotDays:
            (data['bookingOpenSlotDays'] as num?)?.toInt() ??
            CounselingCaseWorkflow.bookingOpenSlotDays,
      ),
    );

    if (!mounted || booked != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Counseling appointment booked successfully.'),
        backgroundColor: primaryColor,
      ),
    );
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

  bool _canBook(Map<String, dynamic> data) {
    return CounselingCaseState.isBookingRequired(data);
  }

  String _statusText(Map<String, dynamic> data) {
    final shared = CounselingCaseState.statusLabel(data);
    if (shared == 'Missed - Rebook Required') return 'Missed - Rebook';
    return shared;
  }

  Color _statusColor(Map<String, dynamic> data) {
    if (_isCompleted(data)) return Colors.green.shade700;
    if (_isCancelled(data)) return Colors.grey.shade700;
    if (_isScheduled(data)) return Colors.blue.shade700;
    if (_isMissed(data)) return Colors.red.shade700;
    if (_canBook(data)) return primaryColor;
    return hintColor;
  }

  String _titleCase(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    return parts
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
  }

  Widget _buildStatusPill(Map<String, dynamic> data) {
    final color = _statusColor(data);
    final text = _statusText(data);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11.5,
        ),
      ),
    );
  }

  String _prettyType(String value) {
    final type = value.trim().toLowerCase();
    if (type == 'academic') return 'Academic';
    if (type == 'personal') return 'Personal';
    return type.isEmpty ? 'General' : _titleCase(type);
  }

  Widget _buildMyCasesSection(double scale) {
    if (_studentUid.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My Counseling Cases',
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: (14.5 * scale).clamp(14.5, 16.5),
            ),
          ),
          SizedBox(height: 4 * scale),
          Text(
            'Book or rebook your appointment when required.',
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w700,
              fontSize: (12.0 * scale).clamp(12.0, 13.0),
            ),
          ),
          SizedBox(height: 10 * scale),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('counseling_cases')
                .where('studentUid', isEqualTo: _studentUid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    'Error loading counseling cases: ${snapshot.error}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final docs = snapshot.data!.docs.toList()
                ..sort((a, b) {
                  final ad =
                      _toDate(a.data()['createdAt']) ??
                      _toDate(a.data()['referralDate']) ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  final bd =
                      _toDate(b.data()['createdAt']) ??
                      _toDate(b.data()['referralDate']) ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  return bd.compareTo(ad);
                });

              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Text(
                    'No counseling referrals yet.',
                    style: TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data();
                  final caseCode = (data['caseCode'] ?? doc.id).toString();
                  final referralType = _prettyType(
                    (data['counselingType'] ?? '').toString(),
                  );
                  final submittedAt =
                      _toDate(data['createdAt']) ??
                      _toDate(data['referralDate']);
                  final scheduledAt = _toDate(data['scheduledAt']);
                  final canBook = _canBook(data);
                  final awaitingCallSlip = _isAwaitingCallSlip(data);
                  final missed = _isMissed(data);

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.09),
                      ),
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
                                  color: primaryColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            _buildStatusPill(data),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$referralType Referral',
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          submittedAt == null
                              ? 'Submitted date not available'
                              : 'Submitted ${DateFormat('MMM d, yyyy').format(submittedAt)}',
                          style: const TextStyle(
                            color: hintColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        if (scheduledAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Scheduled: ${DateFormat('EEE, MMM d, yyyy h:mm a').format(scheduledAt)}',
                            style: const TextStyle(
                              color: hintColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                        if (awaitingCallSlip) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.11),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.30),
                              ),
                            ),
                            child: Text(
                              'Counseling will send your call slip before booking opens.',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                        if (canBook) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: () => _openBookingDialog(
                                caseId: doc.id,
                                data: data,
                              ),
                              icon: const Icon(
                                Icons.event_available_rounded,
                                size: 18,
                              ),
                              label: Text(
                                missed
                                    ? 'Rebook Appointment'
                                    : 'Book Appointment',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _resetFormAfterSubmit() {
    setState(() {
      _counselingType = 'academic';
      _moodsSelected.clear();
      _schoolSelected.clear();
      _relationshipSelected.clear();
      _homeSelected.clear();
      _otherMoodCtrl.clear();
      _otherSchoolCtrl.clear();
      _otherRelationshipCtrl.clear();
      _otherHomeCtrl.clear();
      _commentsCtrl.clear();
    });
  }

  @override
  void dispose() {
    _otherMoodCtrl.dispose();
    _otherSchoolCtrl.dispose();
    _otherRelationshipCtrl.dispose();
    _otherHomeCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final scale = (width / 430).clamp(1.0, 1.18);
        final pad = (16.0 * scale).clamp(16.0, 24.0);
        final bool wide = width >= 980;

        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: _loadingProfile
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      pad,
                      14 * scale,
                      pad,
                      20 * scale,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: wide ? 1160 : 920,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(14 * scale),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(26 * scale),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.05),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(14 * scale),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22 * scale),
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Center(
                                    child: Text(
                                      'Student Self-Referral Form',
                                      style: TextStyle(
                                        color: textDark,
                                        fontWeight: FontWeight.w900,
                                        fontSize: (18 * scale).clamp(
                                          18.0,
                                          22.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 6 * scale),
                                  Center(
                                    child: Text(
                                      'Share your concerns so counseling can assist you.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: hintColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: (12.5 * scale).clamp(
                                          12.5,
                                          14.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 14 * scale),
                                  _buildTopInfoSection(scale),
                                  SizedBox(height: 12 * scale),
                                  _buildReasonsGrid(scale, wide),
                                  SizedBox(height: 12 * scale),
                                  _buildCommentsSection(scale),
                                  SizedBox(height: 14 * scale),
                                  _buildActions(scale),
                                  SizedBox(height: 16 * scale),
                                  _buildMyCasesSection(scale),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildTopInfoSection(double scale) {
    final now = DateFormat('MMM d, yyyy').format(DateTime.now());
    return Container(
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Referral Information',
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: (14.5 * scale).clamp(14.5, 16.5),
            ),
          ),
          SizedBox(height: 10 * scale),
          Wrap(
            spacing: 10 * scale,
            runSpacing: 10 * scale,
            children: [
              SizedBox(
                width: 300,
                child: TextFormField(
                  initialValue: _studentName,
                  readOnly: true,
                  decoration: _decor(
                    label: 'Student Name',
                    icon: Icons.person_outline_rounded,
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextFormField(
                  initialValue: now,
                  readOnly: true,
                  decoration: _decor(
                    label: 'Date',
                    icon: Icons.calendar_today_rounded,
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextFormField(
                  initialValue: _studentNo.isEmpty ? 'Not set' : _studentNo,
                  readOnly: true,
                  decoration: _decor(
                    label: 'Student No',
                    icon: Icons.badge_outlined,
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _counselingType,
                  decoration: _decor(
                    label: 'Type',
                    icon: Icons.rule_folder_outlined,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'academic',
                      child: Text('Academic'),
                    ),
                    DropdownMenuItem(
                      value: 'personal',
                      child: Text('Personal'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _counselingType = value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReasonsGrid(double scale, bool wide) {
    final left = Column(
      children: [
        _reasonGroupCard(
          title: 'Moods / Behaviors',
          options: _moodOptions,
          selected: _moodsSelected,
          otherController: _otherMoodCtrl,
          scale: scale,
        ),
        SizedBox(height: 10 * scale),
        _reasonGroupCard(
          title: 'Relationships',
          options: _relationshipOptions,
          selected: _relationshipSelected,
          otherController: _otherRelationshipCtrl,
          scale: scale,
        ),
      ],
    );

    final right = Column(
      children: [
        _reasonGroupCard(
          title: 'School Concerns',
          options: _schoolOptions,
          selected: _schoolSelected,
          otherController: _otherSchoolCtrl,
          scale: scale,
        ),
        SizedBox(height: 10 * scale),
        _reasonGroupCard(
          title: 'Home Concerns',
          options: _homeOptions,
          selected: _homeSelected,
          otherController: _otherHomeCtrl,
          scale: scale,
        ),
      ],
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          SizedBox(width: 10 * scale),
          Expanded(child: right),
        ],
      );
    }

    return Column(
      children: [
        left,
        SizedBox(height: 10 * scale),
        right,
      ],
    );
  }

  Widget _reasonGroupCard({
    required String title,
    required List<String> options,
    required Set<String> selected,
    required TextEditingController otherController,
    required double scale,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: (14.0 * scale).clamp(14.0, 16.0),
            ),
          ),
          SizedBox(height: 6 * scale),
          ...options.map((option) {
            final checked = selected.contains(option);
            return CheckboxListTile(
              value: checked,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                option,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              activeColor: primaryColor,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    selected.add(option);
                  } else {
                    selected.remove(option);
                  }
                });
              },
            );
          }),
          TextFormField(
            controller: otherController,
            decoration: _decor(
              label: 'Other',
              icon: Icons.edit_note_rounded,
              hint: 'Specify if not listed',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection(double scale) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comments',
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: (14.0 * scale).clamp(14.0, 16.0),
            ),
          ),
          SizedBox(height: 8 * scale),
          TextFormField(
            controller: _commentsCtrl,
            minLines: 4,
            maxLines: 6,
            decoration: _decor(
              label: 'Describe your concern',
              icon: Icons.notes_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(double scale) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _resetFormAfterSubmit,
            icon: const Icon(Icons.clear_rounded),
            label: const Text('Clear Form'),
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryColor,
              side: BorderSide(color: primaryColor.withValues(alpha: 0.45)),
              padding: EdgeInsets.symmetric(vertical: 12 * scale),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        SizedBox(width: 10 * scale),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_loading ? 'Submitting...' : 'Submit Referral'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12 * scale),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookCounselingSlotDialog extends StatefulWidget {
  final String caseId;
  final String studentUid;
  final String schoolYearId;
  final String termId;
  final DateTime? bookingDeadlineAt;
  final int bookingLeadHours;
  final int openSlotDays;

  const _BookCounselingSlotDialog({
    required this.caseId,
    required this.studentUid,
    required this.schoolYearId,
    required this.termId,
    required this.bookingDeadlineAt,
    required this.bookingLeadHours,
    required this.openSlotDays,
  });

  @override
  State<_BookCounselingSlotDialog> createState() =>
      _BookCounselingSlotDialogState();
}

class _BookCounselingSlotDialogState extends State<_BookCounselingSlotDialog> {
  final _slotService = OsaMeetingScheduleService(
    templateCollection: 'counseling_schedule_templates',
    slotCollection: 'counseling_meeting_slots',
    caseCollection: 'counseling_cases',
  );
  final _workflowService = CounselingCaseWorkflowService();
  final _slotScrollCtrl = ScrollController();

  static const _bg = Color(0xFFF6FAF6);
  static const _primaryColor = Color(0xFF1B5E20);
  static const _hintColor = Color(0xFF6D7F62);
  static const _textDark = Color(0xFF1F2A1F);

  String? _selectedSlotId;
  bool _booking = false;

  @override
  void dispose() {
    _slotScrollCtrl.dispose();
    super.dispose();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _limitByOpenDays(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int dayCount,
  ) {
    if (dayCount <= 0 || docs.isEmpty) return docs;

    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final uniqueDayKeys = <String>{};

    for (final doc in docs) {
      final start = (doc.data()['startAt'] as Timestamp?)?.toDate();
      if (start == null) continue;
      final dayKey = DateFormat('yyyy-MM-dd').format(start);
      if (!uniqueDayKeys.contains(dayKey) && uniqueDayKeys.length >= dayCount) {
        break;
      }
      uniqueDayKeys.add(dayKey);
      out.add(doc);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final bookingClosed =
        widget.bookingDeadlineAt != null &&
        now.isAfter(widget.bookingDeadlineAt!);
    final earliestAllowedStart = now.add(
      Duration(hours: widget.bookingLeadHours),
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth < 760 ? screenWidth - 32 : 640.0;
    final dialogHeight = screenWidth < 760 ? 520.0 : 600.0;

    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Counseling Slot',
            style: TextStyle(
              color: _primaryColor,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Choose one available schedule for your counseling appointment.',
            style: TextStyle(
              color: _hintColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: bookingClosed
            ? Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Booking window has ended. Please contact counseling support.',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                stream: _slotService.streamOpenSlots(
                  schoolYearId: widget.schoolYearId,
                  termId: widget.termId,
                  limit: 500,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Text(
                        'Error loading slots: ${snapshot.error}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: _primaryColor),
                    );
                  }

                  final sorted =
                      snapshot.data!.where((slotDoc) {
                        final data = slotDoc.data();
                        final start = (data['startAt'] as Timestamp?)?.toDate();
                        if (start == null) return false;
                        if (start.isBefore(now)) return false;
                        if (start.isBefore(earliestAllowedStart)) return false;
                        return true;
                      }).toList()..sort((a, b) {
                        final aStart =
                            (a.data()['startAt'] as Timestamp?)?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        final bStart =
                            (b.data()['startAt'] as Timestamp?)?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        return aStart.compareTo(bStart);
                      });

                  final docs = _limitByOpenDays(sorted, widget.openSlotDays);
                  if (docs.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'No open slots available right now.\nPlease try again later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _hintColor,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                      ),
                    );
                  }

                  QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
                  for (final doc in docs) {
                    if (doc.id == _selectedSlotId) {
                      selectedDoc = doc;
                      break;
                    }
                  }

                  if (_selectedSlotId != null && selectedDoc == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => _selectedSlotId = null);
                    });
                  }
                  final dayGroups = _groupSlotsByDay(docs);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _primaryColor.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Text(
                          'Showing ${widget.openSlotDays} days worth of open slots '
                          '(minimum ${widget.bookingLeadHours}-hour lead time).',
                          style: const TextStyle(
                            color: _primaryColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            '${docs.length} available slot${docs.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: _hintColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          if (docs.length > 5)
                            const Row(
                              children: [
                                Icon(
                                  Icons.swipe_vertical_rounded,
                                  size: 14,
                                  color: _hintColor,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Scroll for more',
                                  style: TextStyle(
                                    color: _hintColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.09),
                            ),
                          ),
                          child: Scrollbar(
                            controller: _slotScrollCtrl,
                            thumbVisibility: docs.length > 5,
                            child: CustomScrollView(
                              controller: _slotScrollCtrl,
                              slivers: [
                                for (final group in dayGroups) ...[
                                  SliverPersistentHeader(
                                    pinned: true,
                                    delegate:
                                        _CounselingStickyDayHeaderDelegate(
                                          height: 34,
                                          child: Container(
                                            color: Colors.white,
                                            alignment: Alignment.centerLeft,
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                              bottom: 6,
                                            ),
                                            child: Text(
                                              _formatSlotDayHeader(group.day),
                                              style: const TextStyle(
                                                color: _hintColor,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 12,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ),
                                        ),
                                  ),
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate((
                                      _,
                                      index,
                                    ) {
                                      final doc = group.slots[index];
                                      final start = _slotStart(doc);
                                      final end = _slotEnd(doc);
                                      if (start == null || end == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return _buildSlotCard(
                                        doc: doc,
                                        start: start,
                                        end: end,
                                        selectedSlotId: _selectedSlotId,
                                        onSelect: _booking
                                            ? null
                                            : (slotId) => setState(
                                                () => _selectedSlotId = slotId,
                                              ),
                                      );
                                    }, childCount: group.slots.length),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (selectedDoc != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _primaryColor.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            'Selected: ${_slotLabel(_slotStart(selectedDoc), _slotEnd(selectedDoc))}',
                            style: const TextStyle(
                              color: _primaryColor,
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _booking ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900, color: _hintColor),
          ),
        ),
        FilledButton(
          onPressed: bookingClosed || _booking || _selectedSlotId == null
              ? null
              : () async {
                  setState(() => _booking = true);
                  try {
                    await _workflowService.bookSlotForCase(
                      slotId: _selectedSlotId!,
                      caseId: widget.caseId,
                      studentUid: widget.studentUid,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop(true);
                  } catch (e) {
                    if (!context.mounted) return;
                    setState(() => _booking = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Booking failed: $e')),
                    );
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: _primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            _booking ? 'Booking...' : 'Book Slot',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  List<_CounselingDaySlotGroup> _groupSlotsByDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final groups = <_CounselingDaySlotGroup>[];
    DateTime? currentDay;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> currentSlots = [];

    for (final doc in docs) {
      final start = _slotStart(doc);
      if (start == null) continue;
      final dayKey = DateTime(start.year, start.month, start.day);
      if (currentDay == null || !_isSameDate(currentDay, dayKey)) {
        if (currentDay != null && currentSlots.isNotEmpty) {
          groups.add(
            _CounselingDaySlotGroup(day: currentDay, slots: currentSlots),
          );
        }
        currentDay = dayKey;
        currentSlots = [doc];
      } else {
        currentSlots.add(doc);
      }
    }

    if (currentDay != null && currentSlots.isNotEmpty) {
      groups.add(_CounselingDaySlotGroup(day: currentDay, slots: currentSlots));
    }
    return groups;
  }

  Widget _buildSlotCard({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required DateTime start,
    required DateTime end,
    required String? selectedSlotId,
    required void Function(String slotId)? onSelect,
  }) {
    final selected = selectedSlotId == doc.id;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onSelect == null ? null : () => onSelect(doc.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? _primaryColor.withValues(alpha: 0.10)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? _primaryColor
                : Colors.black.withValues(alpha: 0.10),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? _primaryColor : _hintColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _slotTimeRange(start, end),
                    style: TextStyle(
                      color: _textDark,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _slotMeta(start, end),
                    style: const TextStyle(
                      color: _hintColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _slotStart(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      (doc.data()['startAt'] as Timestamp?)?.toDate();

  DateTime? _slotEnd(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      (doc.data()['endAt'] as Timestamp?)?.toDate();

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatSlotDayHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    if (_isSameDate(date, today)) {
      return 'TODAY - ${DateFormat('MMMM d, yyyy').format(date)}';
    }
    if (_isSameDate(date, tomorrow)) {
      return 'TOMORROW - ${DateFormat('MMMM d, yyyy').format(date)}';
    }
    return DateFormat('EEEE - MMMM d, yyyy').format(date).toUpperCase();
  }

  String _slotTimeRange(DateTime start, DateTime end) {
    final s = DateFormat('h:mm a').format(start);
    final e = DateFormat('h:mm a').format(end);
    return '$s - $e';
  }

  String _slotMeta(DateTime start, DateTime end) {
    final minutes = end.difference(start).inMinutes.clamp(0, 600);
    final duration = minutes % 60 == 0
        ? '${minutes ~/ 60} hour'
        : '$minutes mins';
    return '${DateFormat('EEE, MMM d').format(start)} - $duration session';
  }

  String _slotLabel(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '--';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final slotDay = DateTime(start.year, start.month, start.day);
    final dayLabel = _isSameDate(slotDay, today)
        ? 'Today'
        : DateFormat('EEE, MMM d, yyyy').format(start);
    return '$dayLabel - ${_slotTimeRange(start, end)}';
  }
}

class _CounselingDaySlotGroup {
  final DateTime day;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> slots;

  const _CounselingDaySlotGroup({required this.day, required this.slots});
}

class _CounselingStickyDayHeaderDelegate
    extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _CounselingStickyDayHeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _CounselingStickyDayHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

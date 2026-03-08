import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  String _studentUid = '';
  String _studentName = '';
  String _studentEmail = '';
  String _studentNo = '';
  String _programId = '';

  String _counselingType = 'academic';
  bool _loading = false;
  bool _loadingProfile = true;

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
    _loadStudentProfile();
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
      await FirebaseFirestore.instance.collection('counseling_cases').add({
        'referralSource': 'student',
        'counselingType': _counselingType,
        'status': 'submitted',
        'meetingStatus': 'pending_assessment',
        'studentUid': _studentUid,
        'studentName': _studentName,
        'studentNo': _studentNo,
        'studentProgramId': _programId,
        'referredByUid': _studentUid,
        'referredByRole': 'student',
        'classroomTeacher': '',
        'referredBy': _studentName,
        'referralDate': Timestamp.fromDate(DateTime.now()),
        'reasons': {
          'moodsBehaviors': _moodsSelected.toList()..sort(),
          'schoolConcerns': _schoolSelected.toList()..sort(),
          'relationships': _relationshipSelected.toList()..sort(),
          'homeConcerns': _homeSelected.toList()..sort(),
          'otherMood': _otherMoodCtrl.text.trim(),
          'otherSchool': _otherSchoolCtrl.text.trim(),
          'otherRelationship': _otherRelationshipCtrl.text.trim(),
          'otherHome': _otherHomeCtrl.text.trim(),
        },
        'comments': _commentsCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Self-referral submitted successfully.'),
          backgroundColor: primaryColor,
        ),
      );
      _resetFormAfterSubmit();
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
                    padding:
                        EdgeInsets.fromLTRB(pad, 14 * scale, pad, 20 * scale),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: wide ? 1160 : 920),
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
                                        fontSize:
                                            (18 * scale).clamp(18.0, 22.0),
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
                                        fontSize:
                                            (12.5 * scale).clamp(12.5, 14.0),
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
                    DropdownMenuItem(value: 'academic', child: Text('Academic')),
                    DropdownMenuItem(value: 'personal', child: Text('Personal')),
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

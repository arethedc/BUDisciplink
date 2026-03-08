import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ProfessorCounselingPage extends StatefulWidget {
  const ProfessorCounselingPage({super.key});

  @override
  State<ProfessorCounselingPage> createState() => _ProfessorCounselingPageState();
}

class _ProfessorCounselingPageState extends State<ProfessorCounselingPage> {
  static const bg = Color(0xFFF6FAF6);
  static const primaryColor = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  final _formKey = GlobalKey<FormState>();

  final _studentSearchCtrl = TextEditingController();
  final _referredByCtrl = TextEditingController();
  final _otherMoodCtrl = TextEditingController();
  final _otherSchoolCtrl = TextEditingController();
  final _otherRelationshipCtrl = TextEditingController();
  final _otherHomeCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();

  String _teacherName = '';
  String _teacherUid = '';
  String _teacherEmail = '';
  String _counselingType = 'academic';

  String? _studentUid;
  String? _studentName;
  String? _studentNo;
  String? _studentProgram;

  bool _loading = false;
  bool _loadingStudents = true;
  final List<Map<String, String>> _students = <Map<String, String>>[];

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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait(<Future<void>>[
      _loadTeacher(),
      _loadStudents(),
    ]);
  }

  Future<void> _loadTeacher() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _teacherUid = user.uid;
    _teacherEmail = user.email?.trim() ?? '';

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data() ?? <String, dynamic>{};

      final first = (data['firstName'] ?? '').toString().trim();
      final last = (data['lastName'] ?? '').toString().trim();
      final displayName = (data['displayName'] ?? '').toString().trim();
      final full = ('$first $last').trim();

      setState(() {
        _teacherName = displayName.isNotEmpty
            ? displayName
            : full.isNotEmpty
                ? full
                : _teacherEmail.split('@').first;
      });
    } catch (_) {
      setState(() {
        _teacherName = _teacherEmail.split('@').first;
      });
    }
  }

  Future<void> _loadStudents() async {
    setState(() => _loadingStudents = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'student')
          .limit(700)
          .get();

      final items = <Map<String, String>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final studentProfile =
            (data['studentProfile'] as Map<String, dynamic>?) ??
                <String, dynamic>{};
        final first = (data['firstName'] ?? '').toString().trim();
        final last = (data['lastName'] ?? '').toString().trim();
        final displayName = (data['displayName'] ?? '').toString().trim();
        final full = ('$first $last').trim();
        final name = displayName.isNotEmpty
            ? displayName
            : full.isNotEmpty
                ? full
                : 'Unnamed Student';
        final studentNo = (studentProfile['studentNo'] ?? '').toString().trim();
        final program = (studentProfile['programId'] ?? '').toString().trim();

        items.add(<String, String>{
          'uid': doc.id,
          'name': name,
          'studentNo': studentNo,
          'programId': program,
        });
      }

      items.sort(
        (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
              (b['name'] ?? '').toLowerCase(),
            ),
      );

      if (!mounted) return;
      setState(() {
        _students
          ..clear()
          ..addAll(items);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load students. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  List<Map<String, String>> _filterStudents(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <Map<String, String>>[];
    return _students.where((student) {
      final name = (student['name'] ?? '').toLowerCase();
      final studentNo = (student['studentNo'] ?? '').toLowerCase();
      final programId = (student['programId'] ?? '').toLowerCase();
      return name.contains(q) || studentNo.contains(q) || programId.contains(q);
    }).take(7).toList();
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
    if (_loading) return;
    if (_studentUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a student.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_hasAnyReasonSelected()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one referral reason.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.collection('counseling_cases').add({
        'referralSource': 'professor',
        'counselingType': _counselingType,
        'status': 'submitted',
        'meetingStatus': 'pending_assessment',
        'studentUid': _studentUid,
        'studentName': _studentName ?? '',
        'studentNo': _studentNo ?? '',
        'studentProgramId': _studentProgram ?? '',
        'referredByUid': _teacherUid,
        'referredByRole': 'professor',
        'classroomTeacher': _teacherName,
        'referredBy': _referredByCtrl.text.trim(),
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
          content: Text('Counseling referral submitted successfully.'),
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
      _studentUid = null;
      _studentName = null;
      _studentNo = null;
      _studentProgram = null;
      _moodsSelected.clear();
      _schoolSelected.clear();
      _relationshipSelected.clear();
      _homeSelected.clear();
      _studentSearchCtrl.clear();
      _referredByCtrl.clear();
      _otherMoodCtrl.clear();
      _otherSchoolCtrl.clear();
      _otherRelationshipCtrl.clear();
      _otherHomeCtrl.clear();
      _commentsCtrl.clear();
    });
  }

  void _selectStudent(Map<String, String> student) {
    setState(() {
      _studentUid = student['uid'];
      _studentName = student['name'];
      _studentNo = student['studentNo'];
      _studentProgram = student['programId'];
      _studentSearchCtrl.text =
          '${student['name'] ?? ''} (${student['studentNo'] ?? 'No ID'})';
    });
  }

  void _clearSelectedStudent() {
    setState(() {
      _studentUid = null;
      _studentName = null;
      _studentNo = null;
      _studentProgram = null;
      _studentSearchCtrl.clear();
    });
  }

  @override
  void dispose() {
    _studentSearchCtrl.dispose();
    _referredByCtrl.dispose();
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
        final bool showSuggestions =
            _studentSearchCtrl.text.trim().isNotEmpty && _studentUid == null;
        final suggestions = showSuggestions
            ? _filterStudents(_studentSearchCtrl.text)
            : <Map<String, String>>[];

        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(pad, 14 * scale, pad, 20 * scale),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 1160 : 920),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(14 * scale),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(26 * scale),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
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
                                'Counseling Referral Form',
                                style: TextStyle(
                                  color: textDark,
                                  fontWeight: FontWeight.w900,
                                  fontSize: (18 * scale).clamp(18.0, 22.0),
                                ),
                              ),
                            ),
                            SizedBox(height: 6 * scale),
                            Center(
                              child: Text(
                                'Submit referral concerns for student counseling.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: hintColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: (12.5 * scale).clamp(12.5, 14.0),
                                ),
                              ),
                            ),
                            SizedBox(height: 14 * scale),
                            _buildTopInfoSection(scale),
                            SizedBox(height: 12 * scale),
                            _buildStudentSelector(scale, suggestions),
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
                  initialValue: _teacherName.isEmpty ? _teacherEmail : _teacherName,
                  readOnly: true,
                  decoration: _decor(
                    label: 'Classroom Teacher',
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
                width: 300,
                child: TextFormField(
                  controller: _referredByCtrl,
                  decoration: _decor(
                    label: 'Referred by (if different)',
                    icon: Icons.forward_to_inbox_outlined,
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

  Widget _buildStudentSelector(
    double scale,
    List<Map<String, String>> suggestions,
  ) {
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
            'Student',
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: (14.5 * scale).clamp(14.5, 16.5),
            ),
          ),
          SizedBox(height: 10 * scale),
          TextFormField(
            controller: _studentSearchCtrl,
            enabled: !_loadingStudents,
            onChanged: (_) => setState(() {}),
            decoration: _decor(
              label: _loadingStudents
                  ? 'Loading students...'
                  : 'Search by student name, number, or program',
              icon: Icons.search_rounded,
            ),
          ),
          if (_studentUid != null) ...[
            SizedBox(height: 10 * scale),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10 * scale),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryColor.withValues(alpha: 0.24)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: primaryColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_studentName ?? ''} • ${_studentNo ?? 'No ID'}'
                      '${(_studentProgram ?? '').isNotEmpty ? ' • ${_studentProgram!}' : ''}',
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearSelectedStudent,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ],
          if (_studentUid == null && suggestions.isNotEmpty) ...[
            SizedBox(height: 10 * scale),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
              ),
              child: Column(
                children: suggestions.map((student) {
                  final name = student['name'] ?? '';
                  final studentNo = student['studentNo'] ?? 'No ID';
                  final programId = student['programId'] ?? '';
                  return ListTile(
                    dense: true,
                    onTap: () => _selectStudent(student),
                    leading: const Icon(Icons.person_rounded, color: primaryColor),
                    title: Text(
                      name,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      '$studentNo${programId.isNotEmpty ? ' • $programId' : ''}',
                      style: const TextStyle(
                        color: hintColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
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
              label: 'Add notes for counseling admin',
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/counseling_case_workflow_service.dart';
import '../shared/widgets/unsaved_changes_guard.dart';

class ProfessorCounselingPage extends StatefulWidget {
  final UnsavedChangesController? unsavedChangesController;

  const ProfessorCounselingPage({super.key, this.unsavedChangesController});

  @override
  State<ProfessorCounselingPage> createState() =>
      _ProfessorCounselingPageState();
}

class _ProfessorCounselingPageState extends State<ProfessorCounselingPage> {
  static const bg = Color(0xFFF6FAF6);
  static const primaryColor = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  final _formKey = GlobalKey<FormState>();
  final _studentSearchFieldKey = GlobalKey();
  final _notesFieldKey = GlobalKey();

  final _studentSearchCtrl = TextEditingController();
  final _otherMoodCtrl = TextEditingController();
  final _otherSchoolCtrl = TextEditingController();
  final _otherRelationshipCtrl = TextEditingController();
  final _otherHomeCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();
  final _studentSearchFocus = FocusNode();
  final _notesFocus = FocusNode();
  final _workflowService = CounselingCaseWorkflowService();

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
  bool _studentSelectionError = false;
  bool _notesError = false;
  final List<Map<String, String>> _students = <Map<String, String>>[];

  final Set<String> _moodsSelected = <String>{};
  final Set<String> _schoolSelected = <String>{};
  final Set<String> _relationshipSelected = <String>{};
  final Set<String> _homeSelected = <String>{};

  static const List<String> _moodOptions = <String>[
    'Anxious or worried',
    'Depressed or unhappy',
    'Eating disorder concerns',
    'Body image concerns',
    'Hyperactive or inattentive',
    'Shy or withdrawn',
    'Low self-esteem',
    'Aggressive behavior',
    'Stealing',
  ];

  static const List<String> _schoolOptions = <String>[
    'Homework not submitted',
    'Incomplete classwork',
    'Low test or assignment grades',
    'Poor classroom performance',
    'Sleeping in class or always tired',
    'Sudden change in grades',
    'Frequently tardy or absent',
    'New student',
  ];

  static const List<String> _relationshipOptions = <String>[
    'Bullying',
    'Difficulty making friends',
    'Poor social skills',
    'Problems with friends',
    'Boyfriend or girlfriend issues',
  ];

  static const List<String> _homeOptions = <String>[
    'Fighting with family members',
    'Illness or death in the family',
    'Parents divorced or separated',
    'Suspected abuse',
    'Suspected substance abuse',
    'Parent request',
  ];

  @override
  void initState() {
    super.initState();
    _studentSearchCtrl.addListener(_syncUnsavedState);
    _otherMoodCtrl.addListener(_syncUnsavedState);
    _otherSchoolCtrl.addListener(_syncUnsavedState);
    _otherRelationshipCtrl.addListener(_syncUnsavedState);
    _otherHomeCtrl.addListener(_syncUnsavedState);
    _commentsCtrl.addListener(_syncUnsavedState);
    _attachUnsavedController(widget.unsavedChangesController);
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ProfessorCounselingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unsavedChangesController != widget.unsavedChangesController) {
      _detachUnsavedController(oldWidget.unsavedChangesController);
      _attachUnsavedController(widget.unsavedChangesController);
    }
  }

  Future<void> _bootstrap() async {
    await Future.wait(<Future<void>>[_loadTeacher(), _loadStudents()]);
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
    return _students
        .where((student) {
          final name = (student['name'] ?? '').toLowerCase();
          final studentNo = (student['studentNo'] ?? '').toLowerCase();
          final programId = (student['programId'] ?? '').toLowerCase();
          return name.contains(q) ||
              studentNo.contains(q) ||
              programId.contains(q);
        })
        .take(7)
        .toList();
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? hint,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Future<void> _scrollToField(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.18,
    );
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_loading) return;
    if (_studentUid == null) {
      setState(() => _studentSelectionError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a student first.'),
          backgroundColor: Colors.red,
        ),
      );
      await _scrollToField(_studentSearchFieldKey);
      _studentSearchFocus.requestFocus();
      return;
    }
    if (_commentsCtrl.text.trim().isEmpty) {
      setState(() => _notesError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add notes about the student situation.'),
          backgroundColor: Colors.red,
        ),
      );
      await _scrollToField(_notesFieldKey);
      _notesFocus.requestFocus();
      return;
    }
    final confirmed = await _showSubmitConfirmation();
    if (!confirmed || !mounted) return;

    setState(() => _loading = true);
    try {
      final referredByName = _teacherName.isNotEmpty
          ? _teacherName
          : (_teacherEmail.isNotEmpty ? _teacherEmail : 'Professor');
      await _workflowService.submitProfessorReferral(
        studentUid: _studentUid ?? '',
        studentName: _studentName ?? '',
        studentNo: _studentNo ?? '',
        studentProgramId: _studentProgram ?? '',
        professorUid: _teacherUid,
        professorName: referredByName,
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

  List<String> _selectedConcernGroups() {
    final groups = <String>[];
    if (_moodsSelected.isNotEmpty || _otherMoodCtrl.text.trim().isNotEmpty) {
      groups.add('Emotional and Behavior');
    }
    if (_schoolSelected.isNotEmpty || _otherSchoolCtrl.text.trim().isNotEmpty) {
      groups.add('Academic and School');
    }
    if (_relationshipSelected.isNotEmpty ||
        _otherRelationshipCtrl.text.trim().isNotEmpty) {
      groups.add('Peer and Relationship');
    }
    if (_homeSelected.isNotEmpty || _otherHomeCtrl.text.trim().isNotEmpty) {
      groups.add('Family and Home');
    }
    return groups;
  }

  Future<bool> _showSubmitConfirmation() async {
    final concerns = _selectedConcernGroups();
    final notes = _commentsCtrl.text.trim();
    final notesPreview = notes.length > 220
        ? '${notes.substring(0, 220)}...'
        : notes;
    final referralType = _counselingType == 'personal'
        ? 'Personal'
        : 'Academic';
    final studentLabel =
        '${_studentName ?? 'Unknown'} | ${_studentNo ?? 'No ID'}'
        '${(_studentProgram ?? '').isNotEmpty ? ' | ${_studentProgram!}' : ''}';

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        Widget row(String label, String value) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 128,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        Widget concernChip(String text) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          );
        }

        return AlertDialog(
          backgroundColor: bg,
          surfaceTintColor: bg,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Confirm Referral Submission',
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Please review the details before sending to counseling.',
                    style: TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      children: [
                        row('Student', studentLabel),
                        Divider(
                          color: Colors.black.withValues(alpha: 0.08),
                          height: 12,
                        ),
                        row('Referral Type', referralType),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Concern Checklist',
                    style: TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (concerns.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: const Text(
                        'No checklist items selected. This is optional.',
                        style: TextStyle(
                          color: hintColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: concerns.map(concernChip).toList(),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Notes',
                    style: TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      notesPreview,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Back to Edit',
                style: TextStyle(color: hintColor, fontWeight: FontWeight.w900),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Confirm Submit',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
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
      _studentSelectionError = false;
      _notesError = false;
      _otherMoodCtrl.clear();
      _otherSchoolCtrl.clear();
      _otherRelationshipCtrl.clear();
      _otherHomeCtrl.clear();
      _commentsCtrl.clear();
    });
    _syncUnsavedState();
  }

  void _selectStudent(Map<String, String> student) {
    setState(() {
      _studentUid = student['uid'];
      _studentName = student['name'];
      _studentNo = student['studentNo'];
      _studentProgram = student['programId'];
      _studentSearchCtrl.clear();
      _studentSelectionError = false;
    });
    _syncUnsavedState();
  }

  void _clearSelectedStudent() {
    setState(() {
      _studentUid = null;
      _studentName = null;
      _studentNo = null;
      _studentProgram = null;
      _studentSearchCtrl.clear();
      _studentSelectionError = false;
    });
    _syncUnsavedState();
  }

  bool get _hasDraftChanges =>
      _studentUid != null ||
      _studentSearchCtrl.text.trim().isNotEmpty ||
      _counselingType != 'academic' ||
      _commentsCtrl.text.trim().isNotEmpty ||
      _moodsSelected.isNotEmpty ||
      _schoolSelected.isNotEmpty ||
      _relationshipSelected.isNotEmpty ||
      _homeSelected.isNotEmpty ||
      _otherMoodCtrl.text.trim().isNotEmpty ||
      _otherSchoolCtrl.text.trim().isNotEmpty ||
      _otherRelationshipCtrl.text.trim().isNotEmpty ||
      _otherHomeCtrl.text.trim().isNotEmpty;

  void _syncUnsavedState() {
    widget.unsavedChangesController?.setDirty(_hasDraftChanges);
  }

  void _discardDraftFromGuard() {
    if (_loading) return;
    _resetFormAfterSubmit();
  }

  void _attachUnsavedController(UnsavedChangesController? controller) {
    if (controller == null) return;
    controller.setDiscardHandler(_discardDraftFromGuard);
    controller.setDirty(_hasDraftChanges);
  }

  void _detachUnsavedController(UnsavedChangesController? controller) {
    if (controller == null) return;
    controller.setDiscardHandler(null);
    controller.clear();
  }

  Future<bool> _confirmLeaveIfUnsaved() async {
    if (!_hasDraftChanges) return true;
    final leave = await showUnsavedChangesDialog(
      context,
      title: 'Leave counseling referral form?',
      message:
          'You have an unfinished referral. Leaving now will clear your current draft.',
    );
    if (leave) {
      _discardDraftFromGuard();
    }
    return leave;
  }

  @override
  void dispose() {
    _detachUnsavedController(widget.unsavedChangesController);
    _studentSearchCtrl.removeListener(_syncUnsavedState);
    _otherMoodCtrl.removeListener(_syncUnsavedState);
    _otherSchoolCtrl.removeListener(_syncUnsavedState);
    _otherRelationshipCtrl.removeListener(_syncUnsavedState);
    _otherHomeCtrl.removeListener(_syncUnsavedState);
    _commentsCtrl.removeListener(_syncUnsavedState);
    _studentSearchCtrl.dispose();
    _otherMoodCtrl.dispose();
    _otherSchoolCtrl.dispose();
    _otherRelationshipCtrl.dispose();
    _otherHomeCtrl.dispose();
    _commentsCtrl.dispose();
    _studentSearchFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final scale = (width / 430).clamp(1.0, 1.16);
        final pad = (16.0 * scale).clamp(16.0, 24.0);
        final bool desktop = width >= 1100;
        final bool tablet = width >= 760;
        final bool stackActions = width < 640;
        final bool showSuggestions = _studentSearchCtrl.text.trim().isNotEmpty;
        final suggestions = showSuggestions
            ? _filterStudents(_studentSearchCtrl.text)
            : <Map<String, String>>[];

        return PopScope(
          canPop: !_hasDraftChanges,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final canLeave = await _confirmLeaveIfUnsaved();
            if (canLeave && context.mounted) {
              Navigator.of(context).maybePop();
            }
          },
          child: Scaffold(
            backgroundColor: bg,
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, 14 * scale, pad, 20 * scale),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: desktop ? 1160 : 920),
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
                                  'Do you have concerns about a student? We are here to help.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: hintColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: (12.5 * scale).clamp(12.5, 14.0),
                                  ),
                                ),
                              ),
                              SizedBox(height: 14 * scale),
                              _buildSectionCard(
                                title: 'Student Selection & Referral Type',
                                subtitle:
                                    'Please select the student who needs support and choose the referral type.',
                                scale: scale,
                                child: _buildStudentTypeSplit(
                                  scale,
                                  suggestions,
                                  split: desktop,
                                ),
                              ),
                              SizedBox(height: 12 * scale),
                              _buildSectionCard(
                                title: 'Notes',
                                subtitle:
                                    'Tell us the student\'s current situation so we can respond well.',
                                scale: scale,
                                child: _buildCommentsSection(scale),
                              ),
                              SizedBox(height: 12 * scale),
                              _buildSectionCard(
                                title: 'Concern Checklist',
                                subtitle:
                                    'Optional: select any areas of concern to help counseling prepare support.',
                                scale: scale,
                                child: _buildReasonsGrid(
                                  scale,
                                  tablet,
                                  collapsible: !tablet,
                                ),
                              ),
                              SizedBox(height: 14 * scale),
                              _buildActions(scale, stacked: stackActions),
                            ],
                          ),
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

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
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
              fontSize: (14.2 * scale).clamp(14.0, 16.0),
            ),
          ),
          SizedBox(height: 2 * scale),
          Text(
            subtitle,
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w700,
              fontSize: (12.0 * scale).clamp(12.0, 13.0),
            ),
          ),
          SizedBox(height: 10 * scale),
          child,
        ],
      ),
    );
  }

  Widget _buildStudentTypeSplit(
    double scale,
    List<Map<String, String>> suggestions, {
    required bool split,
  }) {
    if (split) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: _buildStudentSelector(scale, suggestions)),
          SizedBox(width: 10 * scale),
          Expanded(flex: 3, child: _buildTopInfoSection(scale)),
        ],
      );
    }

    return Column(
      children: [
        _buildStudentSelector(scale, suggestions),
        SizedBox(height: 10 * scale),
        _buildTopInfoSection(scale),
      ],
    );
  }

  Widget _buildTopInfoSection(double scale) {
    return Container(
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _counselingType,
                decoration: _decor(
                  label: 'Referral Type',
                  icon: Icons.rule_folder_outlined,
                ),
                items: const [
                  DropdownMenuItem(value: 'academic', child: Text('Academic')),
                  DropdownMenuItem(value: 'personal', child: Text('Personal')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _counselingType = value);
                  _syncUnsavedState();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStudentSelector(
    double scale,
    List<Map<String, String>> suggestions,
  ) {
    return Container(
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: _studentSearchFieldKey,
            controller: _studentSearchCtrl,
            focusNode: _studentSearchFocus,
            enabled: !_loadingStudents,
            onChanged: (_) {
              setState(() => _studentSelectionError = false);
              _syncUnsavedState();
            },
            decoration: _decor(
              label: _loadingStudents
                  ? 'Loading students...'
                  : 'Search student by name, number, or program',
              icon: Icons.search_rounded,
              errorText: _studentSelectionError
                  ? 'Please select a student.'
                  : null,
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
                      '${_studentName ?? ''} | ${_studentNo ?? 'No ID'}'
                      '${(_studentProgram ?? '').isNotEmpty ? ' | ${_studentProgram!}' : ''}',
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
          if (suggestions.isNotEmpty) ...[
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
                    leading: const Icon(
                      Icons.person_rounded,
                      color: primaryColor,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      '$studentNo${programId.isNotEmpty ? ' | $programId' : ''}',
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

  Widget _buildReasonsGrid(
    double scale,
    bool wide, {
    required bool collapsible,
  }) {
    final left = Column(
      children: [
        _reasonGroupCard(
          title: 'Emotional and Behavior Concerns',
          options: _moodOptions,
          selected: _moodsSelected,
          otherController: _otherMoodCtrl,
          scale: scale,
          collapsible: collapsible,
        ),
        SizedBox(height: 10 * scale),
        _reasonGroupCard(
          title: 'Peer and Relationship Concerns',
          options: _relationshipOptions,
          selected: _relationshipSelected,
          otherController: _otherRelationshipCtrl,
          scale: scale,
          collapsible: collapsible,
        ),
      ],
    );

    final right = Column(
      children: [
        _reasonGroupCard(
          title: 'Academic and School Concerns',
          options: _schoolOptions,
          selected: _schoolSelected,
          otherController: _otherSchoolCtrl,
          scale: scale,
          collapsible: collapsible,
        ),
        SizedBox(height: 10 * scale),
        _reasonGroupCard(
          title: 'Family and Home Concerns',
          options: _homeOptions,
          selected: _homeSelected,
          otherController: _otherHomeCtrl,
          scale: scale,
          collapsible: collapsible,
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
    required bool collapsible,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select all that apply.',
          style: TextStyle(
            color: hintColor,
            fontWeight: FontWeight.w700,
            fontSize: (11.8 * scale).clamp(11.5, 13.0),
          ),
        ),
        SizedBox(height: 4 * scale),
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
              _syncUnsavedState();
            },
          );
        }),
        TextFormField(
          controller: otherController,
          decoration: _decor(
            label: 'Other concern in this area (optional)',
            icon: Icons.edit_note_rounded,
            hint: 'Add any additional details for this area',
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: collapsible
          ? Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded:
                    selected.isNotEmpty ||
                    otherController.text.trim().isNotEmpty,
                title: Text(
                  title,
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: (14.0 * scale).clamp(14.0, 16.0),
                  ),
                ),
                children: [content],
              ),
            )
          : Column(
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
                content,
              ],
            ),
    );
  }

  Widget _buildCommentsSection(double scale) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: _notesFieldKey,
            controller: _commentsCtrl,
            focusNode: _notesFocus,
            minLines: 4,
            maxLines: 6,
            onChanged: (value) {
              if (_notesError && value.trim().isNotEmpty) {
                setState(() => _notesError = false);
              }
              _syncUnsavedState();
            },
            decoration: _decor(
              label: 'What is the student\'s current situation?',
              icon: Icons.notes_rounded,
              hint:
                  'Share key details. You may include moods/behavior, school, relationship, and home concerns.',
              errorText: _notesError
                  ? 'Please add notes so counseling can assist the student.'
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(double scale, {required bool stacked}) {
    final clearButton = OutlinedButton.icon(
      onPressed: _loading ? null : _resetFormAfterSubmit,
      icon: const Icon(Icons.clear_rounded),
      label: const Text('Clear Form'),
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: BorderSide(color: primaryColor.withValues(alpha: 0.45)),
        padding: EdgeInsets.symmetric(vertical: 12 * scale),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final submitButton = ElevatedButton.icon(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 46 * scale, child: submitButton),
          SizedBox(height: 10 * scale),
          SizedBox(height: 46 * scale, child: clearButton),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: clearButton),
        SizedBox(width: 10 * scale),
        Expanded(child: submitButton),
      ],
    );
  }
}

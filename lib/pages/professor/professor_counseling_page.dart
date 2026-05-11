import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../services/counseling_case_workflow_service.dart';
import '../../services/counseling_setup_service.dart';
import '../../services/student_directory_policy.dart';
import '../shared/widgets/unsaved_changes_guard.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';

class ProfessorCounselingPage extends StatefulWidget {
  final UnsavedChangesController? unsavedChangesController;

  const ProfessorCounselingPage({super.key, this.unsavedChangesController});

  @override
  State<ProfessorCounselingPage> createState() =>
      _ProfessorCounselingPageState();
}

class _ProfessorCounselingPageState extends State<ProfessorCounselingPage> {
  static const bg = Colors.white;
  static const primaryColor = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  final _formKey = GlobalKey<FormState>();
  final _studentSearchFieldKey = GlobalKey();
  final _studentSearchOverlayAnchorKey = GlobalKey();
  final _studentSearchLayerLink = LayerLink();
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
  final _counselingSetupService = CounselingSetupService();
  OverlayEntry? _studentSearchOverlay;

  String _teacherName = '';
  String _teacherUid = '';
  String _teacherEmail = '';
  String _counselingType = 'academic';

  String? _studentUid;
  String? _studentName;
  String? _studentNo;
  String? _studentProgram;
  String? _studentPhotoUrl;

  bool _loading = false;
  bool _loadingStudents = true;
  bool _studentSelectionError = false;
  bool _notesError = false;
  final List<Map<String, String>> _students = <Map<String, String>>[];

  final Set<String> _moodsSelected = <String>{};
  final Set<String> _schoolSelected = <String>{};
  final Set<String> _relationshipSelected = <String>{};
  final Set<String> _homeSelected = <String>{};
  final Map<String, Future<String>> _resolvedPhotoUrlCache = {};
  List<String> _moodOptions = List<String>.from(
    CounselingSetupConfig.defaults.moodsBehaviors,
  );
  List<String> _schoolOptions = List<String>.from(
    CounselingSetupConfig.defaults.schoolConcerns,
  );
  List<String> _relationshipOptions = List<String>.from(
    CounselingSetupConfig.defaults.relationships,
  );
  List<String> _homeOptions = List<String>.from(
    CounselingSetupConfig.defaults.homeConcerns,
  );

  @override
  void initState() {
    super.initState();
    _studentSearchCtrl.addListener(_syncUnsavedState);
    _studentSearchCtrl.addListener(_handleStudentSearchChanged);
    _studentSearchFocus.addListener(_handleStudentSearchFocusChanged);
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
    await Future.wait(<Future<void>>[
      _loadTeacher(),
      _loadStudents(),
      _loadCounselingSetup(),
    ]);
  }

  Future<void> _loadCounselingSetup() async {
    try {
      final config = await _counselingSetupService.getConfig();
      if (!mounted) return;
      setState(() {
        _moodOptions = List<String>.from(config.moodsBehaviors);
        _schoolOptions = List<String>.from(config.schoolConcerns);
        _relationshipOptions = List<String>.from(config.relationships);
        _homeOptions = List<String>.from(config.homeConcerns);
        _moodsSelected.removeWhere((item) => !_moodOptions.contains(item));
        _schoolSelected.removeWhere((item) => !_schoolOptions.contains(item));
        _relationshipSelected.removeWhere(
          (item) => !_relationshipOptions.contains(item),
        );
        _homeSelected.removeWhere((item) => !_homeOptions.contains(item));
      });
    } catch (_) {
      // Keep defaults if setup cannot be loaded.
    }
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
        if (!StudentDirectoryPolicy.isSearchableStudent(data)) continue;
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
        final photoUrl = (data['photoUrl'] ?? studentProfile['photoUrl'] ?? '')
            .toString()
            .trim();

        items.add(<String, String>{
          'uid': doc.id,
          'name': name,
          'studentNo': studentNo,
          'programId': program,
          'photoUrl': photoUrl,
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
      AppScaffoldMessenger.of(context).showSnackBar(
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

  List<Map<String, String>> _activeStudentSuggestions() {
    if (_loadingStudents) {
      return const <Map<String, String>>[];
    }
    final query = _studentSearchCtrl.text.trim();
    if (query.isEmpty) return const <Map<String, String>>[];
    return _filterStudents(query);
  }

  void _handleStudentSearchChanged() {
    _updateStudentSearchOverlay();
  }

  void _handleStudentSearchFocusChanged() {
    _updateStudentSearchOverlay();
  }

  void _removeStudentSearchOverlay() {
    _studentSearchOverlay?.remove();
    _studentSearchOverlay = null;
  }

  void _updateStudentSearchOverlay() {
    if (!mounted) return;
    final suggestions = _activeStudentSuggestions();
    if (suggestions.isEmpty) {
      _removeStudentSearchOverlay();
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    if (_studentSearchOverlay == null) {
      _studentSearchOverlay = _buildStudentSearchOverlay();
      overlay.insert(_studentSearchOverlay!);
    } else {
      _studentSearchOverlay!.markNeedsBuild();
    }
  }

  OverlayEntry _buildStudentSearchOverlay() {
    return OverlayEntry(
      builder: (overlayContext) {
        final renderBox =
            _studentSearchOverlayAnchorKey.currentContext?.findRenderObject()
                as RenderBox?;
        if (renderBox == null || !renderBox.attached) {
          return const SizedBox.shrink();
        }
        final suggestions = _activeStudentSuggestions();
        if (suggestions.isEmpty) return const SizedBox.shrink();
        final fieldSize = renderBox.size;

        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    _studentSearchFocus.unfocus();
                    _removeStudentSearchOverlay();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
              CompositedTransformFollower(
                link: _studentSearchLayerLink,
                showWhenUnlinked: false,
                offset: Offset(0, fieldSize.height + 6),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: fieldSize.width,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 290),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.06),
                        ),
                        itemBuilder: (context, index) {
                          final student = suggestions[index];
                          final name = student['name'] ?? '';
                          final studentNo = student['studentNo'] ?? 'No ID';
                          final programId = student['programId'] ?? '';
                          final photoUrl = student['photoUrl'];
                          return ListTile(
                            dense: true,
                            onTap: () {
                              _selectStudent(student);
                              _removeStudentSearchOverlay();
                            },
                            leading: _studentAvatar(
                              name: name,
                              photoUrl: photoUrl,
                              size: 34,
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
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'S';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Widget _studentAvatar({
    required String name,
    required String? photoUrl,
    required double size,
  }) {
    final safeName = name.trim().isEmpty ? 'Student' : name.trim();
    final safeUrl = (photoUrl ?? '').trim();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: primaryColor.withValues(alpha: 0.24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: safeUrl.isEmpty
          ? Center(
              child: Text(
                _initials(safeName),
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.36,
                ),
              ),
            )
          : Image.network(
              safeUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  _initials(safeName),
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.36,
                  ),
                ),
              ),
            ),
    );
  }

  bool _isHttpPhotoUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  Future<String> _resolvePhotoUrl(String source) async {
    final value = source.trim();
    if (value.isEmpty) return '';
    if (_isHttpPhotoUrl(value)) return value;
    try {
      if (value.startsWith('gs://')) {
        return await FirebaseStorage.instance
            .refFromURL(value)
            .getDownloadURL();
      }
      return await FirebaseStorage.instance.ref(value).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  Future<void> _openStudentProfilePhotoViewer({
    required String name,
    required String? photoUrl,
  }) async {
    final source = (photoUrl ?? '').trim();
    if (source.isEmpty) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No profile photo available.')),
      );
      return;
    }

    final resolved = _isHttpPhotoUrl(source)
        ? source
        : await _resolvedPhotoUrlCache.putIfAbsent(
            source,
            () => _resolvePhotoUrl(source),
          );
    if (resolved.trim().isEmpty) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No profile photo available.')),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox(
            width: 640,
            height: 560,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name.trim().isEmpty ? 'Student Profile' : name.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
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
                          resolved,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
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
      },
    );
  }

  Widget _studentAvatarWithPreview({
    required String name,
    required String? photoUrl,
    required double size,
  }) {
    final source = (photoUrl ?? '').trim();
    final hasPhoto = source.isNotEmpty;
    final avatar = _studentAvatar(name: name, photoUrl: photoUrl, size: size);
    if (!hasPhoto) return avatar;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () =>
            _openStudentProfilePhotoViewer(name: name, photoUrl: source),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: (size * 0.30).clamp(14.0, 18.0),
                height: (size * 0.30).clamp(14.0, 18.0),
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Icon(
                  Icons.open_in_full_rounded,
                  color: Colors.white,
                  size: (size * 0.15).clamp(8.0, 11.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      AppScaffoldMessenger.of(context).showSnackBar(
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
      AppScaffoldMessenger.of(context).showSnackBar(
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
      final reporterUid = _teacherUid.trim().isNotEmpty
          ? _teacherUid.trim()
          : (FirebaseAuth.instance.currentUser?.uid.trim() ?? '');
      if (reporterUid.isEmpty) {
        throw Exception('Reporter account not found. Please login again.');
      }
      final caseId = await _workflowService.submitProfessorReferral(
        studentUid: _studentUid ?? '',
        studentName: _studentName ?? '',
        studentNo: _studentNo ?? '',
        studentProgramId: _studentProgram ?? '',
        professorUid: reporterUid,
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

      try {
        await FirebaseFirestore.instance
            .collection('counseling_cases')
            .doc(caseId)
            .set({
              'referredByUid': reporterUid,
              'referralReporterUids': FieldValue.arrayUnion([reporterUid]),
            }, SetOptions(merge: true));
      } catch (_) {
        // The workflow service already writes these fields; this is just a
        // best-effort repair for older linked cases.
      }

      final caseDoc = await FirebaseFirestore.instance
          .collection('counseling_cases')
          .doc(caseId)
          .get();
      final caseData = caseDoc.data() ?? <String, dynamic>{};
      final isScheduled = CounselingCaseState.isScheduled(caseData);
      final isAwaitingCallSlip = CounselingCaseState.isAwaitingCallSlip(
        caseData,
      );
      final isBookingRequired = CounselingCaseState.isBookingRequired(caseData);

      final message = isScheduled
          ? "Referral added to the student's active counseling case. The student already has a scheduled appointment."
          : isBookingRequired
          ? "Referral linked to the student's active counseling case. Booking is already open for the student."
          : isAwaitingCallSlip
          ? 'Counseling referral submitted. Counseling admin will send a call slip to open booking.'
          : 'Counseling referral submitted successfully.';

      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: primaryColor,
        ),
      );
      _resetFormAfterSubmit();
    } catch (error) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
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
      _studentPhotoUrl = null;
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
    _removeStudentSearchOverlay();
    _syncUnsavedState();
  }

  void _selectStudent(Map<String, String> student) {
    setState(() {
      _studentUid = student['uid'];
      _studentName = student['name'];
      _studentNo = student['studentNo'];
      _studentProgram = student['programId'];
      _studentPhotoUrl = student['photoUrl'];
      _studentSearchCtrl.clear();
      _studentSelectionError = false;
    });
    _removeStudentSearchOverlay();
    FocusScope.of(context).unfocus();
    _syncUnsavedState();
  }

  void _clearSelectedStudent() {
    setState(() {
      _studentUid = null;
      _studentName = null;
      _studentNo = null;
      _studentProgram = null;
      _studentPhotoUrl = null;
      _studentSearchCtrl.clear();
      _studentSelectionError = false;
    });
    _removeStudentSearchOverlay();
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
    _studentSearchCtrl.removeListener(_handleStudentSearchChanged);
    _studentSearchFocus.removeListener(_handleStudentSearchFocusChanged);
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
    _removeStudentSearchOverlay();
    _studentSearchFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final compactModal = width < 760;
        final scale = (width / 430).clamp(0.90, 1.16);
        final pad = compactModal
            ? (10.0 * scale).clamp(8.0, 14.0)
            : (16.0 * scale).clamp(16.0, 24.0);
        final bool desktop = width >= 1100;
        final bool tablet = width >= 760;
        final bool stackActions = width < 640;

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
            backgroundColor: Colors.white,
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  pad,
                  compactModal ? 8 * scale : 14 * scale,
                  pad,
                  compactModal ? 12 * scale : 20 * scale,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: desktop ? 1160 : 920),
                    child: SizedBox(
                      width: double.infinity,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionCard(
                              title: 'Student Selection',
                              subtitle:
                                  'Please select the student who needs support.',
                              scale: scale,
                              child: _buildStudentSelector(scale),
                            ),
                            SizedBox(height: 12 * scale),
                            _buildSectionCard(
                              title: 'Student Information & Referral Type',
                              subtitle:
                                  'Review selected student details and confirm the referral type.',
                              scale: scale,
                              child: _buildStudentInfoTypeSplit(
                                scale,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
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

  Widget _buildStudentInfoTypeSplit(double scale, {required bool split}) {
    if (split) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: _buildStudentInfoCard(scale)),
          SizedBox(width: 10 * scale),
          Expanded(flex: 3, child: _buildTopInfoSection(scale)),
        ],
      );
    }

    return Column(
      children: [
        _buildStudentInfoCard(scale),
        SizedBox(height: 10 * scale),
        _buildTopInfoSection(scale),
      ],
    );
  }

  Widget _buildTopInfoSection(double scale) {
    return DropdownButtonFormField<String>(
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
    );
  }

  Widget _buildStudentSelector(double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompositedTransformTarget(
          link: _studentSearchLayerLink,
          child: Container(
            key: _studentSearchOverlayAnchorKey,
            child: TextFormField(
              key: _studentSearchFieldKey,
              controller: _studentSearchCtrl,
              focusNode: _studentSearchFocus,
              enabled: !_loadingStudents,
              onChanged: (_) {
                setState(() => _studentSelectionError = false);
                _syncUnsavedState();
                _updateStudentSearchOverlay();
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
          ),
        ),
      ],
    );
  }

  Widget _buildStudentInfoCard(double scale) {
    final hasStudent = _studentUid != null;
    if (!hasStudent) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(12 * scale),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.info_outline_rounded,
                color: primaryColor,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Select a student to view their profile details.',
                style: TextStyle(color: hintColor, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: primaryColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          _studentAvatarWithPreview(
            name: _studentName ?? 'Student',
            photoUrl: _studentPhotoUrl,
            size: (52 * scale).clamp(46.0, 58.0),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (_studentName ?? '').trim().isEmpty
                      ? 'Selected Student'
                      : (_studentName ?? '').trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: (14.2 * scale).clamp(14.2, 16.0),
                  ),
                ),
                SizedBox(height: 2 * scale),
                Text(
                  [
                    if ((_studentNo ?? '').trim().isNotEmpty)
                      (_studentNo ?? '').trim(),
                    if ((_studentProgram ?? '').trim().isNotEmpty)
                      (_studentProgram ?? '').trim(),
                  ].join(' | '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hintColor,
                    fontWeight: FontWeight.w700,
                    fontSize: (12.4 * scale).clamp(12.4, 13.8),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8 * scale),
          TextButton(
            onPressed: _clearSelectedStudent,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            ),
            child: const Text('Clear'),
          ),
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
    return TextFormField(
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

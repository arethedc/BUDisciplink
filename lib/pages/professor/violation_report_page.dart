import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../services/student_directory_policy.dart';
import '../../services/academic_settings_service.dart';
import '../../services/violation_case_service.dart';
import '../osa_admin/institution_setup_page.dart';
import '../shared/widgets/unsaved_changes_guard.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';

class ViolationReportPage extends StatefulWidget {
  final VoidCallback? onOpenMyReportsInShell;
  final UnsavedChangesController? unsavedChangesController;

  const ViolationReportPage({
    super.key,
    this.onOpenMyReportsInShell,
    this.unsavedChangesController,
  });

  @override
  State<ViolationReportPage> createState() => _ViolationReportPageState();
}

class _ViolationReportPageState extends State<ViolationReportPage> {
  final _formKey = GlobalKey<FormState>();
  final _svc = ViolationCaseService();
  final _academicSvc = AcademicSettingsService();

  // =========================
  // THEME (Bicol University Green)
  // =========================
  static const bg = Colors.white;
  static const primaryColor = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  // Student search + locked student fields
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _searchFieldAnchorKey = GlobalKey();
  final _searchLayerLink = LayerLink();
  final _studentNoCtrl = TextEditingController();
  final _studentNameCtrl = TextEditingController();
  final _programCtrl = TextEditingController();

  // Narrative
  final _descriptionCtrl = TextEditingController();

  // Selected student
  String? _studentUid;
  String? _selectedStudentPhotoUrl;
  String _selectedStudentCollegeId = '';

  // Concern + Category + Type (3-level structure)
  String? _concern; // basic | serious
  String? _categoryId;
  String? _categoryName;
  String? _typeId;
  String? _typeName;
  DateTime _incidentAt = DateTime.now();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _categoryCache = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _typeCache = [];
  final Map<String, int> _categoryReportCounts = {};
  final Map<String, int> _typeReportCounts = {};
  String _categoryCountSignature = '';
  String _typeCountSignature = '';
  bool _loadingCategoryCounts = false;
  bool _loadingTypeCounts = false;

  // Evidence (multiple)
  final List<PlatformFile> _pickedFiles = [];
  final ImagePicker _imagePicker = ImagePicker();

  bool _submitting = false;
  bool _incidentModified = false;
  bool _checkingAcademicContext = true;
  bool _hasActiveSchoolYear = false;
  String? _activeSchoolYearLabel;
  String? _academicContextError;
  String _viewerRole = '';

  // Student cache
  bool _loadingStudents = false;
  String? _studentLoadError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _studentCache = [];
  OverlayEntry? _studentSearchOverlay;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_syncUnsavedState);
    _searchCtrl.addListener(_handleSearchInputChanged);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    _descriptionCtrl.addListener(_syncUnsavedState);
    _attachUnsavedController(widget.unsavedChangesController);
    _loadAcademicContext();
  }

  @override
  void didUpdateWidget(covariant ViolationReportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unsavedChangesController != widget.unsavedChangesController) {
      _detachUnsavedController(oldWidget.unsavedChangesController);
      _attachUnsavedController(widget.unsavedChangesController);
    }
  }

  @override
  void dispose() {
    _detachUnsavedController(widget.unsavedChangesController);
    _searchCtrl.removeListener(_syncUnsavedState);
    _searchCtrl.removeListener(_handleSearchInputChanged);
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _descriptionCtrl.removeListener(_syncUnsavedState);
    _removeStudentSearchOverlay();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _studentNoCtrl.dispose();
    _studentNameCtrl.dispose();
    _programCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  // =========================
  // ACADEMIC CONTEXT GATE
  // =========================
  Future<void> _loadAcademicContext() async {
    if (!mounted) return;
    setState(() {
      _checkingAcademicContext = true;
      _academicContextError = null;
    });
    _removeStudentSearchOverlay();

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final activeSy = await _academicSvc.getActiveSY();
      var role = '';
      if (currentUser != null) {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        role = (userSnap.data()?['role'] ?? '').toString().trim().toLowerCase();
      }
      if (!mounted) return;

      final hasActive = activeSy != null;
      final label = hasActive
          ? ((activeSy['label'] ?? activeSy['id'] ?? '').toString().trim())
          : null;

      setState(() {
        _hasActiveSchoolYear = hasActive;
        _activeSchoolYearLabel = (label == null || label.isEmpty)
            ? null
            : label;
        _viewerRole = role;
      });
      if (!hasActive) {
        _removeStudentSearchOverlay();
      }

      if (hasActive) {
        await _preloadStudents();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasActiveSchoolYear = false;
        _activeSchoolYearLabel = null;
        _academicContextError = e.toString();
        _viewerRole = '';
      });
    } finally {
      if (mounted) {
        setState(() => _checkingAcademicContext = false);
      }
    }
  }

  bool get _canOpenSchoolYearSetup {
    return _viewerRole == 'super_admin' ||
        _viewerRole == 'osa_admin' ||
        _viewerRole == 'department_admin';
  }

  Future<void> _openSchoolYearSetup() async {
    if (!_canOpenSchoolYearSetup || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InstitutionSetupPage()),
    );
    if (!mounted) return;
    await _loadAcademicContext();
  }

  Widget _buildNoActiveSchoolYearGate({required double scale}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reporting is unavailable',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: (16.0 * scale).clamp(16.0, 18.0),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12 * scale),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF5D9A3)),
            ),
            child: Text(
              'No active school year is configured. Report Violation is locked until an admin sets an active school year and semester dates.',
              style: TextStyle(
                color: const Color(0xFF8A5C12),
                fontWeight: FontWeight.w800,
                fontSize: (12.8 * scale).clamp(12.8, 14.0),
              ),
            ),
          ),
          if ((_activeSchoolYearLabel ?? '').isNotEmpty) ...[
            SizedBox(height: 8 * scale),
            Text(
              'Current active school year: $_activeSchoolYearLabel',
              style: TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w700,
                fontSize: (12.5 * scale).clamp(12.5, 14.0),
              ),
            ),
          ],
          if ((_academicContextError ?? '').isNotEmpty) ...[
            SizedBox(height: 8 * scale),
            Text(
              'Check failed: $_academicContextError',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w700,
                fontSize: (12.2 * scale).clamp(12.2, 13.5),
              ),
            ),
          ],
          if (!_canOpenSchoolYearSetup) ...[
            SizedBox(height: 8 * scale),
            Text(
              'Please contact an administrator to activate a school year.',
              style: TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w700,
                fontSize: (12.4 * scale).clamp(12.4, 13.8),
              ),
            ),
          ],
          SizedBox(height: 12 * scale),
          Row(
            children: [
              if (_canOpenSchoolYearSetup) ...[
                FilledButton.icon(
                  onPressed: _checkingAcademicContext ? null : _openSchoolYearSetup,
                  icon: const Icon(Icons.settings_rounded),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  label: const Text(
                    'Open School Year & Semesters',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              OutlinedButton.icon(
                onPressed: _checkingAcademicContext ? null : _loadAcademicContext,
                icon: const Icon(Icons.refresh_rounded),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor.withValues(alpha: 0.40)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: const Text(
                  'Refresh',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================
  // INPUT DECORATION (keep TextFormField)
  // =========================
  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? helperText,
    bool isDropdown = false,
  }) {
    final baseBorderColor = primaryColor.withValues(alpha: 0.20);
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      labelStyle: const TextStyle(
        color: hintColor,
        fontWeight: FontWeight.w700,
      ),
      helperStyle: const TextStyle(
        color: hintColor,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: Icon(icon, color: primaryColor.withValues(alpha: 0.85)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: baseBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: baseBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 1.6),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: isDropdown ? 12 : 14,
        vertical: 13,
      ),
    );
  }

  // =========================
  // PRELOAD STUDENTS
  // =========================
  Future<void> _preloadStudents() async {
    if (_loadingStudents) return;

    setState(() {
      _loadingStudents = true;
      _studentLoadError = null;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'student')
          .limit(700)
          .get();

      if (!mounted) return;

      final students = snap.docs
          .where((d) => StudentDirectoryPolicy.isSearchableStudent(d.data()))
          .cast<QueryDocumentSnapshot<Map<String, dynamic>>>()
          .toList();

      setState(() => _studentCache = students);
    } catch (e) {
      if (!mounted) return;
      setState(() => _studentLoadError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingStudents = false);
      }
    }
  }

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  String _safeString(dynamic value) => (value ?? '').toString().trim();

  Map<String, dynamic> _studentProfileOf(Map<String, dynamic> data) {
    final raw = data['studentProfile'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  String _studentDisplayName(Map<String, dynamic> data) {
    final explicit = _safeString(data['displayName']);
    if (explicit.isNotEmpty) return explicit;
    final first = _safeString(data['firstName']);
    final last = _safeString(data['lastName']);
    return '$first $last'.trim();
  }

  String _studentNoOf(Map<String, dynamic> data) {
    final profile = _studentProfileOf(data);
    if (_safeString(profile['studentNo']).isNotEmpty) {
      return _safeString(profile['studentNo']);
    }
    return _safeString(data['studentNo']);
  }

  String _programIdOf(Map<String, dynamic> data) {
    final profile = _studentProfileOf(data);
    if (_safeString(profile['programId']).isNotEmpty) {
      return _safeString(profile['programId']);
    }
    if (_safeString(profile['program']).isNotEmpty) {
      return _safeString(profile['program']);
    }
    if (_safeString(data['programId']).isNotEmpty) {
      return _safeString(data['programId']);
    }
    return _safeString(data['program']);
  }

  String _collegeIdOf(Map<String, dynamic> data) {
    final profile = _studentProfileOf(data);
    return _safeString(profile['collegeId']);
  }

  String _photoUrlOf(Map<String, dynamic> data) {
    final topLevel = _safeString(data['photoUrl']);
    if (topLevel.isNotEmpty) return topLevel;
    final profilePhoto = _safeString(data['profilePhotoUrl']);
    if (profilePhoto.isNotEmpty) return profilePhoto;
    final profile = _studentProfileOf(data);
    final profileUrl = _safeString(profile['photoUrl']);
    if (profileUrl.isNotEmpty) return profileUrl;
    final nestedProfileUrl = _safeString(profile['profilePhotoUrl']);
    if (nestedProfileUrl.isNotEmpty) return nestedProfileUrl;
    final employeeProfile = data['employeeProfile'] as Map<String, dynamic>?;
    final employeePhoto = _safeString(employeeProfile?['photoUrl']);
    if (employeePhoto.isNotEmpty) return employeePhoto;
    return _safeString(employeeProfile?['profilePhotoUrl']);
  }

  final Map<String, Future<String>> _resolvedPhotoUrlCache = {};

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

  Widget _avatarInitial(String name, double size) {
    return Center(
      child: Text(
        _initials(name),
        style: TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.34,
        ),
      ),
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
    required String photoUrl,
    required double size,
  }) {
    final source = photoUrl.trim();
    Widget buildImage(String url) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _avatarInitial(name, size),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: source.isEmpty
          ? _avatarInitial(name, size)
          : _isHttpPhotoUrl(source)
          ? buildImage(source)
          : FutureBuilder<String>(
              future: _resolvedPhotoUrlCache.putIfAbsent(
                source,
                () => _resolvePhotoUrl(source),
              ),
              builder: (context, snapshot) {
                final resolved = (snapshot.data ?? '').trim();
                if (resolved.isEmpty) return _avatarInitial(name, size);
                return buildImage(resolved);
              },
            ),
    );
  }

  Future<void> _openStudentProfilePhotoViewer({
    required String name,
    required String photoUrl,
  }) async {
    final source = photoUrl.trim();
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
    required String photoUrl,
    required double size,
  }) {
    final source = photoUrl.trim();
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

  void _handleSearchInputChanged() {
    _updateStudentSearchOverlay();
  }

  void _handleSearchFocusChanged() {
    _updateStudentSearchOverlay();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _activeSearchSuggestions() {
    if (!_hasActiveSchoolYear ||
        _loadingStudents ||
        _studentLoadError != null) {
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
    return _filterStudentsLocal(query);
  }

  void _removeStudentSearchOverlay() {
    _studentSearchOverlay?.remove();
    _studentSearchOverlay = null;
  }

  void _updateStudentSearchOverlay() {
    if (!mounted) return;
    final suggestions = _activeSearchSuggestions();
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
            _searchFieldAnchorKey.currentContext?.findRenderObject()
                as RenderBox?;
        if (renderBox == null || !renderBox.attached) {
          return const SizedBox.shrink();
        }

        final suggestions = _activeSearchSuggestions();
        if (suggestions.isEmpty) return const SizedBox.shrink();
        final fieldSize = renderBox.size;

        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    _searchFocusNode.unfocus();
                    _removeStudentSearchOverlay();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
              CompositedTransformFollower(
                link: _searchLayerLink,
                showWhenUnlinked: false,
                offset: Offset(0, fieldSize.height + 6),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: fieldSize.width,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 300),
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
                      child: suggestions.isEmpty
                          ? const SizedBox.shrink()
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: suggestions.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                              itemBuilder: (context, index) {
                                final doc = suggestions[index];
                                final d = doc.data();
                                final name = _studentDisplayName(d);
                                final no = _studentNoOf(d);
                                final programId = _programIdOf(d);
                                final collegeId = _collegeIdOf(d);
                                final photoUrl = _photoUrlOf(d);
                                final primaryMeta = <String>[
                                  if (no.isNotEmpty) no,
                                  if (programId.isNotEmpty) programId,
                                ].join(' | ');
                                final secondaryMeta = <String>[
                                  if (collegeId.isNotEmpty) collegeId,
                                ].join(' | ');

                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  leading: _studentAvatar(
                                    name: name.isEmpty ? 'Student' : name,
                                    photoUrl: photoUrl,
                                    size: 40,
                                  ),
                                  title: Text(
                                    name.isEmpty ? 'Unnamed student' : name,
                                    style: const TextStyle(
                                      color: textDark,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (primaryMeta.isNotEmpty)
                                        Text(
                                          primaryMeta,
                                          style: const TextStyle(
                                            color: hintColor,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      if (secondaryMeta.isNotEmpty)
                                        Text(
                                          secondaryMeta,
                                          style: TextStyle(
                                            color: hintColor.withValues(
                                              alpha: 0.9,
                                            ),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                  onTap: () {
                                    _selectStudent(doc);
                                    _removeStudentSearchOverlay();
                                  },
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

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterStudentsLocal(
    String q,
  ) {
    final query = _norm(q);
    if (query.isEmpty) return [];

    final tokens = query.split(' ').where((t) => t.trim().isNotEmpty).toList();

    final results = _studentCache.where((doc) {
      final data = doc.data();

      final name = _norm(_studentDisplayName(data));
      final studentNo = _norm(_studentNoOf(data));
      final programId = _norm(_programIdOf(data));

      if (name.contains(query) ||
          studentNo.contains(query) ||
          programId.contains(query)) {
        return true;
      }

      if (tokens.isNotEmpty) return tokens.every((t) => name.contains(t));
      return false;
    }).toList();

    return results.take(8).toList();
  }

  void _selectStudent(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final studentNo = _studentNoOf(data);
    final studentName = _studentDisplayName(data);
    final programId = _programIdOf(data);

    setState(() {
      _studentUid = doc.id;
      _selectedStudentPhotoUrl = _photoUrlOf(data);
      _selectedStudentCollegeId = _collegeIdOf(data);

      _studentNoCtrl.text = studentNo;
      _studentNameCtrl.text = studentName;
      _programCtrl.text = programId;
      _searchCtrl.clear();
    });
    _syncUnsavedState();

    _removeStudentSearchOverlay();
    FocusScope.of(context).unfocus();
  }

  void _clearSelectedStudent() {
    setState(() {
      _studentUid = null;
      _selectedStudentPhotoUrl = null;
      _selectedStudentCollegeId = '';
      _studentNoCtrl.clear();
      _studentNameCtrl.clear();
      _programCtrl.clear();
      _searchCtrl.clear();
    });
    _syncUnsavedState();
    _removeStudentSearchOverlay();
  }

  // =========================
  // CATEGORIES STREAM
  // =========================
  Stream<QuerySnapshot<Map<String, dynamic>>> _categoriesStream() {
    return FirebaseFirestore.instance
        .collection('violation_categories')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  Future<void> _ensureCategoryCounts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> categories,
  ) async {
    if (categories.isEmpty) return;
    final ids = categories.map((d) => d.id).toList()..sort();
    final signature = ids.join('|');
    if (_loadingCategoryCounts || signature == _categoryCountSignature) return;
    _loadingCategoryCounts = true;
    _categoryCountSignature = signature;

    try {
      final entries = await Future.wait(
        categories.map((doc) async {
          final agg = await FirebaseFirestore.instance
              .collection('violation_cases')
              .where('categoryId', isEqualTo: doc.id)
              .count()
              .get();
          return MapEntry(doc.id, agg.count ?? 0);
        }),
      );
      if (!mounted) return;
      setState(() {
        _categoryReportCounts
          ..clear()
          ..addEntries(entries);
      });
    } catch (_) {
      // keep graceful fallback to alphabetical when counts are unavailable
    } finally {
      _loadingCategoryCounts = false;
    }
  }

  // =========================
  // TYPES STREAM
  // =========================
  Stream<QuerySnapshot<Map<String, dynamic>>> _typesStream() {
    if (_categoryId == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('violation_types')
        .where('isActive', isEqualTo: true)
        .where('categoryId', isEqualTo: _categoryId)
        .snapshots();
  }

  Future<void> _ensureTypeCounts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> types,
  ) async {
    if (types.isEmpty) return;
    final ids = types.map((d) => d.id).toList()..sort();
    final signature = '${_categoryId ?? ''}:${ids.join('|')}';
    if (_loadingTypeCounts || signature == _typeCountSignature) return;
    _loadingTypeCounts = true;
    _typeCountSignature = signature;

    try {
      final entries = await Future.wait(
        types.map((doc) async {
          final agg = await FirebaseFirestore.instance
              .collection('violation_cases')
              .where('typeId', isEqualTo: doc.id)
              .count()
              .get();
          return MapEntry(doc.id, agg.count ?? 0);
        }),
      );
      if (!mounted) return;
      setState(() {
        _typeReportCounts
          ..clear()
          ..addEntries(entries);
      });
    } catch (_) {
      // keep graceful fallback to alphabetical when counts are unavailable
    } finally {
      _loadingTypeCounts = false;
    }
  }

  // =========================
  // EVIDENCE (multiple)
  // =========================
  bool get _supportsCameraCapture {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  String _fileExtFromName(String name) {
    final clean = name.trim().toLowerCase();
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return '';
    return clean.substring(dot + 1);
  }

  bool _isAllowedEvidenceExt(String ext) {
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'pdf';
  }

  bool _isImageEvidenceExt(String ext) {
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png';
  }

  bool _isPdfEvidenceExt(String ext) => ext == 'pdf';

  bool _isAllowedEvidenceFile(PlatformFile file) {
    final ext = _fileExtFromName(file.name);
    return _isAllowedEvidenceExt(ext);
  }

  void _appendEvidenceFile(PlatformFile file) {
    if (!_isAllowedEvidenceFile(file)) return;
    final exists = _pickedFiles.any(
      (x) =>
          x.name == file.name &&
          x.size == file.size &&
          (x.path ?? '') == (file.path ?? ''),
    );
    if (!exists) {
      _pickedFiles.add(file);
    }
  }

  Widget _buildEvidenceThumb(PlatformFile file, {required double size}) {
    final ext = _fileExtFromName(file.name);
    final radius = BorderRadius.circular(10);
    final box = BoxDecoration(
      color: primaryColor.withValues(alpha: 0.10),
      borderRadius: radius,
      border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
    );

    Widget child;
    if (_isPdfEvidenceExt(ext)) {
      child = const Icon(Icons.picture_as_pdf_rounded, color: Colors.red);
    } else if (_isImageEvidenceExt(ext)) {
      if (file.bytes != null) {
        child = ClipRRect(
          borderRadius: radius,
          child: Image.memory(file.bytes!, fit: BoxFit.cover),
        );
      } else if ((file.path ?? '').isNotEmpty) {
        child = ClipRRect(
          borderRadius: radius,
          child: Image.file(File(file.path!), fit: BoxFit.cover),
        );
      } else {
        child = const Icon(Icons.image_rounded, color: primaryColor, size: 18);
      }
    } else {
      child = const Icon(Icons.insert_drive_file_rounded, color: hintColor);
    }

    return InkWell(
      borderRadius: radius,
      onTap: () => _openEvidencePreview(file),
      child: Container(
        width: size,
        height: size,
        decoration: box,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  Future<void> _openEvidencePreview(PlatformFile file) async {
    final ext = _fileExtFromName(file.name);
    final isImage = _isImageEvidenceExt(ext);
    final isPdf = _isPdfEvidenceExt(ext);
    if (!isImage && !isPdf) return;

    Widget content;
    if (isImage) {
      if (file.bytes != null) {
        content = InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.memory(file.bytes!, fit: BoxFit.contain),
        );
      } else if ((file.path ?? '').isNotEmpty) {
        content = InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.file(File(file.path!), fit: BoxFit.contain),
        );
      } else {
        content = const Center(
          child: Text('Image preview is unavailable for this file.'),
        );
      }
    } else {
      if (file.bytes != null) {
        content = SfPdfViewer.memory(file.bytes!);
      } else if ((file.path ?? '').isNotEmpty) {
        content = SfPdfViewer.file(File(file.path!));
      } else {
        content = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.red,
                size: 72,
              ),
              const SizedBox(height: 12),
              Text(
                file.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'PDF preview is unavailable for this file.',
                style: TextStyle(color: hintColor, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 760,
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 620),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEvidencePicker() async {
    final action = await showModalBottomSheet<_EvidencePickAction>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_supportsCameraCapture)
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt_rounded,
                    color: primaryColor,
                  ),
                  title: const Text(
                    'Take Photo',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Use device camera'),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_EvidencePickAction.capturePhoto),
                ),
              ListTile(
                leading: const Icon(
                  Icons.upload_file_rounded,
                  color: primaryColor,
                ),
                title: const Text(
                  'Upload Files',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('JPG / PNG / PDF'),
                onTap: () =>
                    Navigator.of(context).pop(_EvidencePickAction.uploadFiles),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == _EvidencePickAction.capturePhoto) {
      await _capturePhotoEvidence();
      return;
    }
    await _pickEvidenceMultiple();
  }

  Future<void> _pickEvidenceMultiple() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: kIsWeb, // helps web
    );

    if (res == null || res.files.isEmpty) return;

    final rejected = <String>[];
    setState(() {
      for (final f in res.files) {
        if (!_isAllowedEvidenceFile(f)) {
          rejected.add(f.name);
          continue;
        }
        _appendEvidenceFile(f);
      }
    });
    _syncUnsavedState();

    if (rejected.isNotEmpty && mounted) {
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only photo files (JPG/PNG) and PDF are allowed. Skipped: ${rejected.length}',
          ),
        ),
      );
    }
  }

  Future<void> _capturePhotoEvidence() async {
    if (!_supportsCameraCapture) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera capture is not available on this device.'),
        ),
      );
      return;
    }

    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (photo == null) return;

      final bytes = kIsWeb ? await photo.readAsBytes() : null;
      final size = bytes?.length ?? await photo.length();
      final captured = PlatformFile(
        name: photo.name.isEmpty
            ? 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg'
            : photo.name,
        size: size,
        path: kIsWeb ? null : photo.path,
        bytes: bytes,
      );

      if (!mounted) return;
      setState(() => _appendEvidenceFile(captured));
      _syncUnsavedState();
    } catch (e) {
      if (!mounted) return;
      AppScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Camera capture failed: $e')));
    }
  }

  void _removeEvidenceAt(int i) {
    setState(() => _pickedFiles.removeAt(i));
    _syncUnsavedState();
  }

  void _clearEvidence() {
    setState(() => _pickedFiles.clear());
    _syncUnsavedState();
  }

  Future<List<String>> _uploadEvidenceMultiple() async {
    if (_pickedFiles.isEmpty) return [];

    final urls = <String>[];

    for (final f in _pickedFiles) {
      if (!_isAllowedEvidenceFile(f)) continue;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${f.name}';
      final metadata = SettableMetadata(
        contentType: _contentTypeForName(f.name),
        contentDisposition: _contentDispositionForName(f.name),
      );
      final ref = FirebaseStorage.instance
          .ref()
          .child('violation_case_evidence')
          .child(fileName);

      // Web: bytes, Mobile/Desktop: path
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) continue;
        await ref.putData(bytes, metadata);
      } else {
        final path = f.path;
        if (path == null) continue;
        await ref.putFile(File(path), metadata);
      }

      final url = await ref.getDownloadURL();
      urls.add(url);
    }

    return urls;
  }

  String _contentTypeForName(String name) {
    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  String _contentDispositionForName(String name) {
    final ext = name.toLowerCase().split('.').last;
    final safeName = name.replaceAll('"', '');
    if (ext == 'pdf') {
      return 'attachment; filename="$safeName"';
    }
    return 'inline; filename="$safeName"';
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _incidentDateText(DateTime value) =>
      DateFormat('MMM d, yyyy').format(value);

  String _incidentTimeText(DateTime value) =>
      DateFormat('h:mm a').format(value);

  Future<DateTime?> _showModernDatePicker({
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required String helpText,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
      cancelText: 'Cancel',
      confirmText: 'Apply',
      builder: (context, child) {
        final base = Theme.of(context);
        final colorScheme = base.colorScheme.copyWith(
          primary: primaryColor,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: textDark,
        );
        final pickerTheme = base.datePickerTheme.copyWith(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
          headerBackgroundColor: primaryColor,
          headerForegroundColor: Colors.white,
          cancelButtonStyle: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
          confirmButtonStyle: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );
        return Theme(
          data: base.copyWith(
            colorScheme: colorScheme,
            datePickerTheme: pickerTheme,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  Future<TimeOfDay?> _showModernTimePicker({
    required TimeOfDay initialTime,
    required String helpText,
  }) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: helpText,
      cancelText: 'Cancel',
      confirmText: 'Apply',
      builder: (context, child) {
        final base = Theme.of(context);
        final dayPeriodColor = WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return bg;
        });
        final dayPeriodTextColor = WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return textDark;
        });
        final colorScheme = base.colorScheme.copyWith(
          primary: primaryColor,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: textDark,
        );
        final pickerTheme = base.timePickerTheme.copyWith(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
          hourMinuteShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: primaryColor.withValues(alpha: 0.20)),
          ),
          hourMinuteColor: bg,
          hourMinuteTextColor: textDark,
          dayPeriodColor: dayPeriodColor,
          dayPeriodTextColor: dayPeriodTextColor,
          dayPeriodShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: primaryColor.withValues(alpha: 0.14)),
          ),
          dialBackgroundColor: bg,
          dialHandColor: primaryColor,
          dialTextColor: textDark,
          entryModeIconColor: primaryColor,
          helpTextStyle: const TextStyle(
            color: textDark,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
          cancelButtonStyle: TextButton.styleFrom(
            foregroundColor: primaryColor,
            backgroundColor: Colors.white,
            side: BorderSide(color: primaryColor.withValues(alpha: 0.30)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
          confirmButtonStyle: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );
        return Theme(
          data: base.copyWith(
            colorScheme: colorScheme,
            timePickerTheme: pickerTheme,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  String _displayLabel(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return '-';
    return cleaned
        .replaceAll('_', ' ')
        .split(' ')
        .where((p) => p.trim().isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
  }

  Widget _summaryRow({
    required String label,
    required String value,
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value.trim(),
              maxLines: multiline ? null : 1,
              overflow: multiline
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmSubmitWithSummary() async {
    final studentName = _studentNameCtrl.text.trim();
    final studentNo = _studentNoCtrl.text.trim();
    final program = _programCtrl.text.trim();
    final concern = _displayLabel(_concern ?? '');
    final category = (_categoryName ?? '').trim();
    final type = (_typeName ?? '').trim();
    final incidentDateText = _incidentDateText(_incidentAt);
    final incidentTimeText = _incidentTimeText(_incidentAt);
    final notes = _descriptionCtrl.text.trim();

    var imageCount = 0;
    var pdfCount = 0;
    for (final file in _pickedFiles) {
      final ext = _fileExtFromName(file.name);
      if (_isImageEvidenceExt(ext)) imageCount++;
      if (_isPdfEvidenceExt(ext)) pdfCount++;
    }

    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.fact_check_outlined,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Verify Violation Report',
                          style: TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Please review this summary before submitting.',
                    style: TextStyle(
                      color: hintColor.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7FBF7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: primaryColor.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _studentAvatarWithPreview(
                                  name: studentName.isEmpty
                                      ? 'Student'
                                      : studentName,
                                  photoUrl: _selectedStudentPhotoUrl ?? '',
                                  size: 44,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        studentName.isEmpty
                                            ? 'Selected Student'
                                            : studentName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: textDark,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${studentNo.isEmpty ? 'No ID' : studentNo}'
                                        '${program.isEmpty ? '' : ' | $program'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: hintColor.withValues(
                                            alpha: 0.9,
                                          ),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Violation Summary',
                                  style: TextStyle(
                                    color: textDark,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _summaryRow(label: 'Concern', value: concern),
                                _summaryRow(
                                  label: 'Category',
                                  value: category.isEmpty ? '-' : category,
                                ),
                                _summaryRow(
                                  label: 'Violation Type',
                                  value: type.isEmpty ? '-' : type,
                                ),
                                _summaryRow(
                                  label: 'Incident Date',
                                  value: incidentDateText,
                                ),
                                _summaryRow(
                                  label: 'Incident Time',
                                  value: incidentTimeText,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Incident Notes',
                                  style: TextStyle(
                                    color: textDark,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  notes.isEmpty ? '-' : notes,
                                  style: const TextStyle(
                                    color: textDark,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Evidence Summary',
                                  style: TextStyle(
                                    color: textDark,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _summaryRow(
                                  label: 'Attachments',
                                  value: '${_pickedFiles.length} file(s)',
                                ),
                                _summaryRow(
                                  label: 'Photos',
                                  value: '$imageCount',
                                ),
                                _summaryRow(label: 'PDF', value: '$pdfCount'),
                                if (_pickedFiles.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  ..._pickedFiles
                                      .take(4)
                                      .map(
                                        (f) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 4,
                                          ),
                                          child: Text(
                                            '• ${f.name}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: hintColor,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12.2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  if (_pickedFiles.length > 4)
                                    Text(
                                      '+${_pickedFiles.length - 4} more file(s)',
                                      style: const TextStyle(
                                        color: hintColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.2,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: hintColor,
                            side: BorderSide(
                              color: Colors.black.withValues(alpha: 0.2),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.send_rounded),
                          label: const Text(
                            'Submit Report',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return submitted == true;
  }

  void _setIncidentDateTime(DateTime selected) {
    final now = DateTime.now();
    if (selected.isAfter(now)) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Future incident date/time is not allowed.'),
        ),
      );
      return;
    }

    setState(() {
      _incidentAt = selected;
      _incidentModified = true;
    });
    _syncUnsavedState();
  }

  Future<void> _pickIncidentDate() async {
    final now = DateTime.now();
    final current = _incidentAt.isAfter(now) ? now : _incidentAt;

    final pickedDate = await _showModernDatePicker(
      initialDate: _dateOnly(current),
      firstDate: DateTime(now.year - 10),
      lastDate: _dateOnly(now),
      helpText: 'Select incident date',
    );
    if (pickedDate == null || !mounted) return;

    final selected = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      current.hour,
      current.minute,
    );
    _setIncidentDateTime(selected);
  }

  Future<void> _pickIncidentTime() async {
    final now = DateTime.now();
    final current = _incidentAt.isAfter(now) ? now : _incidentAt;

    final pickedTime = await _showModernTimePicker(
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: 'Select incident time',
    );
    if (pickedTime == null || !mounted) return;

    final selected = DateTime(
      current.year,
      current.month,
      current.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    _setIncidentDateTime(selected);
  }

  void _useCurrentIncidentDateTime() {
    _setIncidentDateTime(DateTime.now());
  }

  // =========================
  // CLEAR / SUBMIT
  // =========================
  void _clearAll() {
    _formKey.currentState?.reset();

    setState(() {
      _studentUid = null;
      _selectedStudentPhotoUrl = null;
      _selectedStudentCollegeId = '';
      _searchCtrl.clear();
      _studentNoCtrl.clear();
      _studentNameCtrl.clear();
      _programCtrl.clear();

      _descriptionCtrl.clear();

      _concern = null;
      _categoryId = null;
      _categoryName = null;
      _typeId = null;
      _typeName = null;
      _categoryCache = [];
      _typeCache = [];
      _incidentAt = DateTime.now();
      _incidentModified = false;

      _pickedFiles.clear();
    });

    FocusManager.instance.primaryFocus?.unfocus();
    _removeStudentSearchOverlay();
    _syncUnsavedState();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_hasActiveSchoolYear) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reporting is unavailable. No active school year is configured.',
          ),
        ),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_studentUid == null) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a student first.')),
      );
      return;
    }

    if (_categoryId == null || _categoryName == null) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a violation category.')),
      );
      return;
    }

    if (_concern == null) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected category has no mapped concern type.'),
        ),
      );
      return;
    }

    if (_typeId == null || _typeName == null) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a specific violation type.')),
      );
      return;
    }

    final confirmed = await _confirmSubmitWithSummary();
    if (!mounted || !confirmed) return;

    setState(() => _submitting = true);

    try {
      final evidenceUrls = await _uploadEvidenceMultiple();

      await _svc.submitCase(
        studentUid: _studentUid!,
        studentNo: _studentNoCtrl.text.trim(),
        studentName: _studentNameCtrl.text.trim(),
        gradeSection: null,
        incidentAt: _incidentAt,
        concern: _concern!,
        categoryId: _categoryId!,
        categoryNameSnapshot: _categoryName!,
        typeId: _typeId!,
        typeNameSnapshot: _typeName!,
        description: _descriptionCtrl.text.trim(),
        evidenceUrls: evidenceUrls,
      );

      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Violation case submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _clearAll();
    } catch (e) {
      if (!mounted) return;
      AppScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  bool get _hasDraftChanges =>
      _studentUid != null ||
      _searchCtrl.text.trim().isNotEmpty ||
      _descriptionCtrl.text.trim().isNotEmpty ||
      _categoryId != null ||
      _typeId != null ||
      _concern != null ||
      _incidentModified ||
      _pickedFiles.isNotEmpty;

  void _syncUnsavedState() {
    widget.unsavedChangesController?.setDirty(_hasDraftChanges);
  }

  void _discardDraftFromGuard() {
    if (_submitting) return;
    _clearAll();
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
      title: 'Leave violation report form?',
      message:
          'You have an unfinished violation report. Leaving now will clear your current draft.',
    );
    if (leave) {
      _discardDraftFromGuard();
    }
    return leave;
  }

  // =========================
  // UI HELPERS
  // =========================
  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
    required double scale,
    bool compact = false,
  }) {
    final sectionPadding = compact ? (10 * scale) : (12 * scale);
    final radius = compact ? 12.0 : 16.0;
    final gapAfterSubtitle = compact ? (8 * scale) : (10 * scale);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(sectionPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
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
          SizedBox(height: 1.5 * scale),
          Text(
            subtitle,
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w700,
              fontSize: (12.0 * scale).clamp(12.0, 13.0),
            ),
          ),
          SizedBox(height: gapAfterSubtitle),
          child,
        ],
      ),
    );
  }

  Widget _buildStudentInfoAndViolationSplit(
    double scale, {
    required bool split,
  }) {
    if (split) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _studentInfoCard(scale: scale, forceFillHeight: false),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: _violationDetailsCard(scale: scale, forceFillHeight: false),
          ),
        ],
      );
    }

    return Column(
      children: [
        _studentInfoCard(scale: scale, forceFillHeight: false),
        SizedBox(height: 10 * scale),
        _violationDetailsCard(scale: scale, forceFillHeight: false),
      ],
    );
  }

  Widget _buildActions(double scale, {required bool stacked}) {
    final clearButton = OutlinedButton.icon(
      onPressed: _submitting ? null : _clearAll,
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
      onPressed: _submitting ? null : _submit,
      icon: _submitting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.send_rounded),
      label: Text(_submitting ? 'Submitting...' : 'Submit Report'),
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

  // =========================
  // BUILD (new 3-card layout)
  // =========================
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;

        final compactModal = w < 760;
        final scale = (w / 430).clamp(0.90, 1.15);
        final pad = compactModal
            ? (10.0 * scale).clamp(8.0, 14.0)
            : (16.0 * scale).clamp(14.0, 22.0);
        final twoColumnDetails = w >= 980;

        final bool desktop = w >= 1100;
        final bool stackActions = w < 820;

        final maxCanvas = compactModal
            ? double.infinity
            : (desktop ? 1160.0 : 920.0);

        return WillPopScope(
          onWillPop: _confirmLeaveIfUnsaved,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  pad,
                  compactModal ? 8 * scale : 12 * scale,
                  pad,
                  compactModal ? 10 * scale : 14 * scale,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxCanvas),
                    child: Column(
                      children: [
                        if (_checkingAcademicContext)
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(24 * scale),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: primaryColor,
                              ),
                            ),
                          )
                        else if (!_hasActiveSchoolYear)
                          _buildNoActiveSchoolYearGate(scale: scale)
                        else
                        SizedBox(
                          width: double.infinity,
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionCard(
                                  title: 'Student Selection',
                                  subtitle:
                                      'Search and select the student for this report.',
                                  scale: scale,
                                  compact: compactModal,
                                  child: _searchSection(scale: scale),
                                ),
                                SizedBox(
                                  height: compactModal ? 8 * scale : 12 * scale,
                                ),
                                if (twoColumnDetails)
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: _buildSectionCard(
                                          title: 'Student Information',
                                          subtitle:
                                              'Review auto-filled student information for the selected student.',
                                          scale: scale,
                                          compact: compactModal,
                                          child: _studentInfoCard(
                                            scale: scale,
                                            forceFillHeight: false,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12 * scale),
                                      Expanded(
                                        child: _buildSectionCard(
                                          title: 'Violation Details',
                                          subtitle:
                                              'Complete the violation category, type, and incident date/time.',
                                          scale: scale,
                                          compact: compactModal,
                                          child: _violationDetailsCard(
                                            scale: scale,
                                            forceFillHeight: false,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else ...[
                                  _buildSectionCard(
                                    title: 'Student Information',
                                    subtitle:
                                        'Review auto-filled student information for the selected student.',
                                    scale: scale,
                                    compact: compactModal,
                                    child: _studentInfoCard(
                                      scale: scale,
                                      forceFillHeight: false,
                                    ),
                                  ),
                                  SizedBox(
                                    height: compactModal
                                        ? 8 * scale
                                        : 12 * scale,
                                  ),
                                  _buildSectionCard(
                                    title: 'Violation Details',
                                    subtitle:
                                        'Complete the violation category, type, and incident date/time.',
                                    scale: scale,
                                    compact: compactModal,
                                    child: _violationDetailsCard(
                                      scale: scale,
                                      forceFillHeight: false,
                                    ),
                                  ),
                                ],
                                SizedBox(
                                  height: compactModal ? 8 * scale : 12 * scale,
                                ),
                                _buildSectionCard(
                                  title: 'Incident Notes',
                                  subtitle: 'Provide incident details for review.',
                                  scale: scale,
                                  compact: compactModal,
                                  child: _notesCard(scale: scale),
                                ),
                                SizedBox(
                                  height: compactModal ? 8 * scale : 12 * scale,
                                ),
                                _buildSectionCard(
                                  title: 'Evidence',
                                  subtitle:
                                      'Attach photo, image, or PDF files related to the reported incident.',
                                  scale: scale,
                                  compact: compactModal,
                                  child: _narrativeEvidenceCard(scale: scale),
                                ),
                                SizedBox(
                                  height: compactModal ? 10 * scale : 14 * scale,
                                ),
                                _buildActions(scale, stacked: stackActions),
                              ],
                            ),
                          ),
                        ),
                      ],
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

  // =========================
  // SEARCH SECTION (outside cards)
  // =========================
  Widget _searchSection({required double scale}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompositedTransformTarget(
          link: _searchLayerLink,
          child: Container(
            key: _searchFieldAnchorKey,
            child: TextFormField(
              controller: _searchCtrl,
              focusNode: _searchFocusNode,
              style: TextStyle(
                color: textDark,
                fontWeight: FontWeight.w800,
                fontSize: (13.5 * scale).clamp(13.5, 15.0),
              ),
              decoration: _decor(
                label: _loadingStudents
                    ? 'Loading students...'
                    : "Search student by name, number, or program",
                icon: Icons.search_rounded,
              ),
              enabled: !_loadingStudents,
              onChanged: (_) {
                setState(() {});
                _updateStudentSearchOverlay();
              },
            ),
          ),
        ),
        if (_loadingStudents)
          Padding(
            padding: EdgeInsets.only(top: 10 * scale),
            child: const LinearProgressIndicator(),
          ),
        if (_studentLoadError != null) ...[
          SizedBox(height: 10 * scale),
          Text(
            "Failed to load students: $_studentLoadError",
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w800,
              fontSize: (12.8 * scale).clamp(12.8, 14.0),
            ),
          ),
        ],
      ],
    );
  }

  // =========================
  // CARD 1: Student Info (locked fields)
  // =========================
  Widget _studentInfoCard({
    required double scale,
    required bool forceFillHeight,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Container(
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
                    style: TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 10 * scale),
          if (_studentUid != null) ...[
            Container(
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
                    name: _studentNameCtrl.text.trim().isEmpty
                        ? 'Student'
                        : _studentNameCtrl.text.trim(),
                    photoUrl: _selectedStudentPhotoUrl ?? '',
                    size: (54 * scale).clamp(48.0, 62.0),
                  ),
                  SizedBox(width: 10 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _studentNameCtrl.text.trim().isEmpty
                              ? 'Selected student'
                              : _studentNameCtrl.text.trim(),
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
                            if (_studentNoCtrl.text.trim().isNotEmpty)
                              _studentNoCtrl.text.trim(),
                            if (_programCtrl.text.trim().isNotEmpty)
                              _programCtrl.text.trim(),
                          ].join(' | '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hintColor,
                            fontWeight: FontWeight.w700,
                            fontSize: (12.4 * scale).clamp(12.4, 13.8),
                          ),
                        ),
                        if (_selectedStudentCollegeId.trim().isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 2 * scale),
                            child: Text(
                              [
                                if (_selectedStudentCollegeId.trim().isNotEmpty)
                                  _selectedStudentCollegeId.trim(),
                              ].join(' | '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: hintColor.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
                                fontSize: (12.0 * scale).clamp(12.0, 13.2),
                              ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10 * scale),
          ],

          TextFormField(
            controller: _studentNoCtrl,
            readOnly: true,
            showCursor: false,
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w800,
              fontSize: (13.5 * scale).clamp(13.5, 15.0),
            ),
            decoration: _decor(
              label: "Student Number",
              icon: Icons.confirmation_number_outlined,
            ),
          ),
          SizedBox(height: 10 * scale),

          TextFormField(
            controller: _studentNameCtrl,
            readOnly: true,
            showCursor: false,
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w800,
              fontSize: (13.5 * scale).clamp(13.5, 15.0),
            ),
            decoration: _decor(
              label: "Student Name",
              icon: Icons.person_outline_rounded,
            ),
          ),
          SizedBox(height: 10 * scale),

          TextFormField(
            controller: _programCtrl,
            readOnly: true,
            showCursor: false,
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w800,
              fontSize: (13.5 * scale).clamp(13.5, 15.0),
            ),
            decoration: _decor(
              label: "Program / Course",
              icon: Icons.school_outlined,
            ),
          ),

        if (forceFillHeight) const Spacer(),
      ],
    );
  }

  // =========================
  // CARD 2: Violation Details (3-level structure)
  // =========================
  Widget _violationDetailsCard({
    required double scale,
    required bool forceFillHeight,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // Step 1: Category (concern auto-derived from selected category)
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _categoriesStream(),
            builder: (context, snap) {
              if (snap.hasData) {
                _categoryCache = snap.data!.docs.toList()
                  ..sort((a, b) {
                    final aCount = _categoryReportCounts[a.id] ?? 0;
                    final bCount = _categoryReportCounts[b.id] ?? 0;
                    final countCmp = bCount.compareTo(aCount);
                    if (countCmp != 0) return countCmp;
                    final aName = (a.data()['name'] ?? '')
                        .toString()
                        .toLowerCase();
                    final bName = (b.data()['name'] ?? '')
                        .toString()
                        .toLowerCase();
                    return aName.compareTo(bName);
                  });
                _ensureCategoryCounts(_categoryCache);
              }

              final docs = _categoryCache;

              if (snap.hasError) {
                return Padding(
                  padding: EdgeInsets.only(top: 8 * scale),
                  child: Text(
                    "Category error: ${snap.error}",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                      fontSize: (12.8 * scale).clamp(12.8, 14.0),
                    ),
                  ),
                );
              }

              if (snap.connectionState == ConnectionState.waiting &&
                  docs.isEmpty) {
                return Padding(
                  padding: EdgeInsets.only(top: 8 * scale),
                  child: const LinearProgressIndicator(),
                );
              }

              if (docs.isEmpty) {
                return Padding(
                  padding: EdgeInsets.only(top: 8 * scale),
                  child: Text(
                    "No categories found. Please seed default data first.",
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w700,
                      fontSize: (12.8 * scale).clamp(12.8, 14.0),
                    ),
                  ),
                );
              }

              return DropdownButtonFormField<String>(
                key: ValueKey(_categoryId),
                initialValue: _categoryId,
                decoration: _decor(
                  label: "Violation Category",
                  icon: Icons.category_rounded,
                  isDropdown: true,
                ),
                items: docs.map((d) {
                  final name = (d.data()['name'] ?? '').toString();
                  return DropdownMenuItem(
                    value: d.id,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (id) {
                  if (id == null) return;
                  final picked = docs.firstWhere((d) => d.id == id);
                  final data = picked.data();
                  final pickedName = (data['name'] ?? '').toString();
                  final mappedConcern = (data['concern'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();
                  setState(() {
                    _categoryId = id;
                    _categoryName = pickedName;
                    _concern = mappedConcern.isEmpty ? null : mappedConcern;
                    _typeId = null;
                    _typeName = null;
                    _typeCache = [];
                  });
                  _syncUnsavedState();
                },
                validator: (v) => v == null ? "Required" : null,
              );
            },
          ),
          SizedBox(height: 10 * scale),

          // Step 2: Specific Type
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _typesStream(),
            builder: (context, snap) {
              if (snap.hasData) {
                _typeCache = snap.data!.docs.toList()
                  ..sort((a, b) {
                    final aCount = _typeReportCounts[a.id] ?? 0;
                    final bCount = _typeReportCounts[b.id] ?? 0;
                    final countCmp = bCount.compareTo(aCount);
                    if (countCmp != 0) return countCmp;
                    final aLabel = (a.data()['label'] ?? '')
                        .toString()
                        .toLowerCase();
                    final bLabel = (b.data()['label'] ?? '')
                        .toString()
                        .toLowerCase();
                    return aLabel.compareTo(bLabel);
                  });
                _ensureTypeCounts(_typeCache);
              }

              final docs = _typeCache;

              if (snap.hasError) {
                return Padding(
                  padding: EdgeInsets.only(top: 8 * scale),
                  child: Text(
                    "Type error: ${snap.error}",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                      fontSize: (12.8 * scale).clamp(12.8, 14.0),
                    ),
                  ),
                );
              }

              if (snap.connectionState == ConnectionState.waiting &&
                  _categoryId != null &&
                  docs.isEmpty) {
                return Padding(
                  padding: EdgeInsets.only(top: 8 * scale),
                  child: const LinearProgressIndicator(),
                );
              }

              if (_categoryId != null && docs.isEmpty) {
                return Padding(
                  padding: EdgeInsets.only(top: 8 * scale),
                  child: Text(
                    "No specific types found for this category.",
                    style: TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w700,
                      fontSize: (12.8 * scale).clamp(12.8, 14.0),
                    ),
                  ),
                );
              }

              return DropdownButtonFormField<String>(
                key: ValueKey(_typeId),
                initialValue: _typeId,
                decoration: _decor(
                  label: _categoryId == null
                      ? "Specific Type (select category first)"
                      : "Specific Violation",
                  icon: Icons.warning_amber_rounded,
                  isDropdown: true,
                ),
                items: docs.map((d) {
                  final label = (d.data()['label'] ?? '').toString();
                  return DropdownMenuItem(
                    value: d.id,
                    child: Text(label, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (_categoryId == null)
                    ? null
                    : (id) {
                        if (id == null) return;
                        final picked = docs.firstWhere((d) => d.id == id);
                        final pickedLabel = (picked.data()['label'] ?? '')
                            .toString();
                        setState(() {
                          _typeId = id;
                          _typeName = pickedLabel;
                        });
                        _syncUnsavedState();
                      },
                validator: (v) => v == null ? "Required" : null,
              );
            },
          ),

          SizedBox(height: 10 * scale),

          LayoutBuilder(
            builder: (context, constraints) {
              final dateField = InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickIncidentDate,
                child: InputDecorator(
                  decoration: _decor(
                    label: "Incident Date",
                    icon: Icons.event_rounded,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _incidentDateText(_incidentAt),
                          style: TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: (13.5 * scale).clamp(13.5, 15.0),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.edit_calendar_rounded,
                        color: primaryColor.withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ),
              );
              final timeField = InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickIncidentTime,
                child: InputDecorator(
                  decoration: _decor(
                    label: "Incident Time",
                    icon: Icons.access_time_rounded,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _incidentTimeText(_incidentAt),
                          style: TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: (13.5 * scale).clamp(13.5, 15.0),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.schedule_rounded,
                        color: primaryColor.withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ),
              );

              return Column(
                children: [
                  dateField,
                  SizedBox(height: 10 * scale),
                  timeField,
                ],
              );
            },
          ),
          SizedBox(height: 8 * scale),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _useCurrentIncidentDateTime,
              icon: const Icon(Icons.update_rounded, size: 16),
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              label: const Text(
                'Use current date/time',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),

        if (forceFillHeight) const Spacer(),
      ],
    );
  }

  // =========================
  // NOTES
  // =========================
  Widget _notesCard({required double scale}) {
    return TextFormField(
      controller: _descriptionCtrl,
      minLines: 4,
      maxLines: 6,
      style: TextStyle(
        color: textDark,
        fontWeight: FontWeight.w700,
        fontSize: (13.5 * scale).clamp(13.5, 15.0),
      ),
      decoration: _decor(
        label: "What happened in this incident?",
        icon: Icons.notes_rounded,
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
    );
  }

  // =========================
  // EVIDENCE
  // =========================
  Widget _narrativeEvidenceCard({required double scale}) {
    final hasFiles = _pickedFiles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasFiles)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _clearEvidence,
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              label: const Text(
                "Clear",
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        InkWell(
          borderRadius: BorderRadius.circular(18 * scale),
          onTap: _openEvidencePicker,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(14 * scale),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                Container(
                  width: (46 * scale).clamp(46.0, 58.0),
                  height: (46 * scale).clamp(46.0, 58.0),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16 * scale),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: const Icon(
                    Icons.upload_file_rounded,
                    color: primaryColor,
                  ),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasFiles ? "Attachments added" : "Upload evidence",
                        style: TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: (14.0 * scale).clamp(14.0, 16.0),
                        ),
                      ),
                      SizedBox(height: 4 * scale),
                      Text(
                        hasFiles
                            ? "${_pickedFiles.length} file(s) selected"
                            : "Tap to take photo or choose JPG / PNG / PDF",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                          fontSize: (12.5 * scale).clamp(12.5, 14.0),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.black54),
              ],
            ),
          ),
        ),
        if (hasFiles) ...[
          SizedBox(height: 12 * scale),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12 * scale),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16 * scale),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: List.generate(_pickedFiles.length, (i) {
                final f = _pickedFiles[i];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: i == _pickedFiles.length - 1 ? 0 : 10 * scale,
                  ),
                  child: Row(
                    children: [
                      _buildEvidenceThumb(f, size: 36),
                      SizedBox(width: 10 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w900,
                                fontSize: (13.0 * scale).clamp(13.0, 14.5),
                              ),
                            ),
                            SizedBox(height: 2 * scale),
                            Text(
                              "${(f.size / 1024).toStringAsFixed(1)} KB",
                              style: TextStyle(
                                color: hintColor,
                                fontWeight: FontWeight.w700,
                                fontSize: (12.0 * scale).clamp(12.0, 13.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _removeEvidenceAt(i),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.18),
                            ),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.red,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }
}

enum _EvidencePickAction { capturePhoto, uploadFiles }

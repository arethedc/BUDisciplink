import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../services/violation_case_service.dart';
import '../shared/widgets/unsaved_changes_guard.dart';
import 'MySubmittedReportPage.dart';

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

  // =========================
  // THEME (Bicol University Green)
  // =========================
  static const bg = Color(0xFFF6FAF6);
  static const primaryColor = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  // Student search + locked student fields
  final _searchCtrl = TextEditingController();
  final _studentNoCtrl = TextEditingController();
  final _studentNameCtrl = TextEditingController();
  final _programCtrl = TextEditingController();

  // Narrative
  final _descriptionCtrl = TextEditingController();

  // Selected student
  String? _studentUid;
  String? _selectedStudentPhotoUrl;
  String _selectedStudentCollegeId = '';
  String _selectedStudentYearLevel = '';

  // Concern + Category + Type (3-level structure)
  String? _concern; // basic | serious
  String? _categoryId;
  String? _categoryName;
  String? _typeId;
  String? _typeName;
  DateTime _incidentAt = DateTime.now();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _categoryCache = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _typeCache = [];

  // Evidence (multiple)
  final List<PlatformFile> _pickedFiles = [];
  final ImagePicker _imagePicker = ImagePicker();

  bool _submitting = false;
  bool _incidentModified = false;

  // Student cache
  bool _loadingStudents = false;
  String? _studentLoadError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _studentCache = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_syncUnsavedState);
    _descriptionCtrl.addListener(_syncUnsavedState);
    _attachUnsavedController(widget.unsavedChangesController);
    _preloadStudents();
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
    _descriptionCtrl.removeListener(_syncUnsavedState);
    _searchCtrl.dispose();
    _studentNoCtrl.dispose();
    _studentNameCtrl.dispose();
    _programCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  // =========================
  // INPUT DECORATION (keep TextFormField)
  // =========================
  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? helperText,
  }) {
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          .limit(500)
          .get();

      if (!mounted) return;

      final students = snap.docs
          .where((d) => (d.data()['role'] ?? '').toString() == 'student')
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

  String _yearLevelOf(Map<String, dynamic> data) {
    final profile = _studentProfileOf(data);
    if (_safeString(profile['yearLevel']).isNotEmpty) {
      return _safeString(profile['yearLevel']);
    }
    return _safeString(data['yearLevel']);
  }

  String _photoUrlOf(Map<String, dynamic> data) =>
      _safeString(data['photoUrl']);

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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl.isEmpty
          ? Center(
              child: Text(
                _initials(name),
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.34,
                ),
              ),
            )
          : Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  _initials(name),
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.34,
                  ),
                ),
              ),
            ),
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
      _selectedStudentYearLevel = _yearLevelOf(data);

      _studentNoCtrl.text = studentNo;
      _studentNameCtrl.text = studentName;
      _programCtrl.text = programId;
      _searchCtrl.clear();
    });
    _syncUnsavedState();

    FocusScope.of(context).unfocus();
  }

  void _clearSelectedStudent() {
    setState(() {
      _studentUid = null;
      _selectedStudentPhotoUrl = null;
      _selectedStudentCollegeId = '';
      _selectedStudentYearLevel = '';
      _studentNoCtrl.clear();
      _studentNameCtrl.clear();
      _programCtrl.clear();
      _searchCtrl.clear();
    });
    _syncUnsavedState();
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
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(
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

  Future<void> _pickIncidentDateTime() async {
    final now = DateTime.now();
    final current = _incidentAt.isAfter(now) ? now : _incidentAt;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _dateOnly(current),
      firstDate: DateTime(now.year - 10),
      lastDate: _dateOnly(now),
      helpText: 'Select incident date',
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: 'Select incident time',
    );
    if (pickedTime == null || !mounted) return;

    final selected = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (selected.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
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

  // =========================
  // CLEAR / SUBMIT
  // =========================
  void _clearAll() {
    _formKey.currentState?.reset();

    setState(() {
      _studentUid = null;
      _selectedStudentPhotoUrl = null;
      _selectedStudentCollegeId = '';
      _selectedStudentYearLevel = '';
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
    _syncUnsavedState();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_studentUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a student first.')),
      );
      return;
    }

    if (_categoryId == null || _categoryName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a violation category.')),
      );
      return;
    }

    if (_concern == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected category has no mapped concern type.'),
        ),
      );
      return;
    }

    if (_typeId == null || _typeName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a specific violation type.')),
      );
      return;
    }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Violation case submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _clearAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
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

  Future<void> _openMyReports() async {
    if (_hasDraftChanges) {
      final leave = await showUnsavedChangesDialog(
        context,
        title: 'Open My Reports?',
        message:
            'You have an unfinished violation report. Leaving now will clear your current draft.',
      );
      if (!leave || !mounted) return;
      _discardDraftFromGuard();
    }
    if (widget.onOpenMyReportsInShell != null) {
      widget.onOpenMyReportsInShell!();
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MySubmittedCasesPage()));
  }

  // =========================
  // UI HELPERS
  // =========================
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

  Widget _buildStudentInfoAndViolationSplit(
    double scale, {
    required bool split,
    required String nowText,
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
            child: _violationDetailsCard(
              scale: scale,
              nowText: nowText,
              forceFillHeight: false,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _studentInfoCard(scale: scale, forceFillHeight: false),
        SizedBox(height: 10 * scale),
        _violationDetailsCard(
          scale: scale,
          nowText: nowText,
          forceFillHeight: false,
        ),
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

        final scale = (w / 430).clamp(1.0, 1.20);
        final pad = (16.0 * scale).clamp(16.0, 24.0);

        final bool desktop = w >= 1100;
        final bool split = w >= 980;
        final bool stackActions = w < 640;

        final nowText = DateFormat('MMM d, yyyy - h:mm a').format(_incidentAt);

        final showSuggestions = _searchCtrl.text.trim().isNotEmpty;

        final suggestions = showSuggestions
            ? _filterStudentsLocal(_searchCtrl.text)
            : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        final maxCanvas = desktop ? 1160.0 : 920.0;

        return WillPopScope(
          onWillPop: _confirmLeaveIfUnsaved,
          child: Scaffold(
            backgroundColor: bg,
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, 14 * scale, pad, 16 * scale),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxCanvas),
                    child: Column(
                      children: [
                        // OUTER SOFT CONTAINER
                        Container(
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
                                      "Violation Report",
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
                                      "Search student first, then complete the report.",
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
                                  SizedBox(height: 10 * scale),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      onPressed: _openMyReports,
                                      icon: const Icon(Icons.article_outlined),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primaryColor,
                                        side: BorderSide(
                                          color: primaryColor.withValues(
                                            alpha: 0.45,
                                          ),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12 * scale,
                                          ),
                                        ),
                                      ),
                                      label: Text(
                                        "My Reports",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: (13.5 * scale).clamp(
                                            13.5,
                                            15.0,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 16 * scale),
                                  _buildSectionCard(
                                    title: 'Student Selection',
                                    subtitle:
                                        'Search and select the student for this report.',
                                    scale: scale,
                                    child: _searchSection(
                                      scale: scale,
                                      suggestions: suggestions,
                                    ),
                                  ),
                                  SizedBox(height: 12 * scale),
                                  _buildSectionCard(
                                    title:
                                        'Student Information & Violation Details',
                                    subtitle:
                                        'Review auto-filled student data and complete violation details.',
                                    scale: scale,
                                    child: _buildStudentInfoAndViolationSplit(
                                      scale,
                                      split: split,
                                      nowText: nowText,
                                    ),
                                  ),
                                  SizedBox(height: 12 * scale),
                                  _buildSectionCard(
                                    title: 'Incident Notes',
                                    subtitle:
                                        'Provide incident details for review.',
                                    scale: scale,
                                    child: _notesCard(scale: scale),
                                  ),
                                  SizedBox(height: 12 * scale),
                                  _buildSectionCard(
                                    title: 'Evidence',
                                    subtitle:
                                        'Attach photo, image, or PDF files related to the reported incident.',
                                    scale: scale,
                                    child: _narrativeEvidenceCard(scale: scale),
                                  ),
                                  SizedBox(height: 14 * scale),
                                  _buildActions(scale, stacked: stackActions),
                                ],
                              ),
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
  Widget _searchSection({
    required double scale,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> suggestions,
  }) {
    final showSuggestions = _searchCtrl.text.trim().isNotEmpty;

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
            controller: _searchCtrl,
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
            onChanged: (_) => setState(() {}),
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
                      '${_studentNameCtrl.text.trim().isEmpty ? 'Selected student' : _studentNameCtrl.text.trim()} | '
                      '${_studentNoCtrl.text.trim().isEmpty ? 'No ID' : _studentNoCtrl.text.trim()}'
                      '${_programCtrl.text.trim().isNotEmpty ? ' | ${_programCtrl.text.trim()}' : ''}',
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

          if (!_loadingStudents &&
              _studentLoadError == null &&
              showSuggestions) ...[
            SizedBox(height: 10 * scale),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
              ),
              child: suggestions.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(12 * scale),
                      child: Text(
                        "No matching students found.",
                        style: TextStyle(
                          color: hintColor,
                          fontWeight: FontWeight.w700,
                          fontSize: (12.8 * scale).clamp(12.8, 14.0),
                        ),
                      ),
                    )
                  : Column(
                      children: suggestions.map((doc) {
                        final d = doc.data();
                        final name = _studentDisplayName(d);
                        final no = _studentNoOf(d);
                        final programId = _programIdOf(d);
                        final collegeId = _collegeIdOf(d);
                        final yearLevel = _yearLevelOf(d);
                        final photoUrl = _photoUrlOf(d);
                        final primaryMeta = <String>[
                          if (no.isNotEmpty) no,
                          if (programId.isNotEmpty) programId,
                        ].join(' | ');
                        final secondaryMeta = <String>[
                          if (collegeId.isNotEmpty) collegeId,
                          if (yearLevel.isNotEmpty) yearLevel,
                        ].join(' | ');

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12 * scale,
                            vertical: 4 * scale,
                          ),
                          leading: _studentAvatar(
                            name: name.isEmpty ? 'Student' : name,
                            photoUrl: photoUrl,
                            size: 40,
                          ),
                          title: Text(
                            name.isEmpty ? 'Unnamed student' : name,
                            style: TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (primaryMeta.isNotEmpty)
                                Text(
                                  primaryMeta,
                                  style: TextStyle(
                                    color: hintColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              if (secondaryMeta.isNotEmpty)
                                Text(
                                  secondaryMeta,
                                  style: TextStyle(
                                    color: hintColor.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () {
                            _selectStudent(doc);
                            setState(() {});
                          },
                        );
                      }).toList(),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================
  // CARD 1: Student Info (locked fields)
  // =========================
  Widget _studentInfoCard({
    required double scale,
    required bool forceFillHeight,
  }) {
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
                  _studentAvatar(
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
                        if (_selectedStudentCollegeId.trim().isNotEmpty ||
                            _selectedStudentYearLevel.trim().isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 2 * scale),
                            child: Text(
                              [
                                if (_selectedStudentCollegeId.trim().isNotEmpty)
                                  _selectedStudentCollegeId.trim(),
                                if (_selectedStudentYearLevel.trim().isNotEmpty)
                                  _selectedStudentYearLevel.trim(),
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
      ),
    );
  }

  // =========================
  // CARD 2: Violation Details (3-level structure)
  // =========================
  Widget _violationDetailsCard({
    required double scale,
    required String nowText,
    required bool forceFillHeight,
  }) {
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
          // Step 1: Category (concern auto-derived from selected category)
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _categoriesStream(),
            builder: (context, snap) {
              if (snap.hasData) {
                _categoryCache = snap.data!.docs.toList();
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
                  helperText: "e.g., Dress Code, ID Compliance",
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
                _typeCache = snap.data!.docs.toList();
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
                  helperText: "Choose the exact violation",
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

          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pickIncidentDateTime,
            child: InputDecorator(
              decoration: _decor(
                label: "Incident Date & Time",
                icon: Icons.calendar_today_outlined,
                helperText:
                    "Default is current time. You can set a past date/time only.",
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      nowText,
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
          ),

          if (forceFillHeight) const Spacer(),

          SizedBox(height: 10 * scale),
          Text(
            "Tip: Select category first, then choose the specific violation.",
            style: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w700,
              fontSize: (12.5 * scale).clamp(12.5, 14.0),
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // NOTES
  // =========================
  Widget _notesCard({required double scale}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: TextFormField(
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
      ),
    );
  }

  // =========================
  // EVIDENCE
  // =========================
  Widget _narrativeEvidenceCard({required double scale}) {
    final hasFiles = _pickedFiles.isNotEmpty;

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
          if (hasFiles)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _clearEvidence,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                label: const Text(
                  "Clear",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                  ),
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
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
          ),

          if (hasFiles) ...[
            SizedBox(height: 12 * scale),

            // Attached list (remove per file)
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
      ),
    );
  }
}

enum _EvidencePickAction { capturePhoto, uploadFiles }

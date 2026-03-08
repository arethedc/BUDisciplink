import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/violation_case_service.dart';
import 'MySubmittedReportPage.dart';

class ViolationReportPage extends StatefulWidget {
  const ViolationReportPage({super.key});

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
  static const accentColor = Color(0xFF43A047);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);
  static const cardShadow = Color(0x0A000000);

  // Student search + locked student fields
  final _searchCtrl = TextEditingController();
  final _studentNoCtrl = TextEditingController();
  final _studentNameCtrl = TextEditingController();
  final _programCtrl = TextEditingController();

  // Narrative
  final _descriptionCtrl = TextEditingController();

  // Selected student
  String? _studentUid;

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

  // Student cache
  bool _loadingStudents = false;
  String? _studentLoadError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _studentCache = [];

  @override
  void initState() {
    super.initState();
    _preloadStudents();
  }

  @override
  void dispose() {
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
      prefixIcon: Icon(icon, color: primaryColor.withOpacity(0.85)),
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
      final snap =
          await FirebaseFirestore.instance.collection('users').limit(500).get();

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

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterStudentsLocal(
    String q,
  ) {
    final query = _norm(q);
    if (query.isEmpty) return [];

    final tokens = query.split(' ').where((t) => t.trim().isNotEmpty).toList();

    final results = _studentCache.where((doc) {
      final data = doc.data();

      final studentProfile = data['studentProfile'] as Map<String, dynamic>? ?? {};
      final name = _norm((data['displayName'] ?? '').toString());
      final studentNo = _norm((studentProfile['studentNo'] ?? data['studentNo'] ?? '').toString());
      final programId = _norm((studentProfile['programId'] ?? data['programId'] ?? '').toString());

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

    final studentProfile = data['studentProfile'] as Map<String, dynamic>? ?? {};

    setState(() {
      _studentUid = doc.id;

      _studentNoCtrl.text = (studentProfile['studentNo'] ?? data['studentNo'] ?? '').toString();
      _studentNameCtrl.text = (data['displayName'] ?? '').toString();
      _programCtrl.text = (studentProfile['programId'] ?? data['programId'] ?? '').toString();

      final no = _studentNoCtrl.text.trim();
      final name = _studentNameCtrl.text.trim();
      _searchCtrl.text = no.isEmpty ? name : '$no - $name';
    });

    FocusScope.of(context).unfocus();
  }

  // ✅ If user edits search after selecting → auto-clear selection so they can pick new student
  void _clearSelectedStudentButKeepSearch() {
    setState(() {
      _studentUid = null;
      _studentNoCtrl.clear();
      _studentNameCtrl.clear();
      _programCtrl.clear();
    });
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

  void _appendEvidenceFile(PlatformFile file) {
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
                  leading: const Icon(Icons.camera_alt_rounded, color: primaryColor),
                  title: const Text(
                    'Take Photo',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Use device camera'),
                  onTap: () => Navigator.of(context).pop(_EvidencePickAction.capturePhoto),
                ),
              ListTile(
                leading: const Icon(Icons.upload_file_rounded, color: primaryColor),
                title: const Text(
                  'Upload Files',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('JPG / PNG / PDF'),
                onTap: () => Navigator.of(context).pop(_EvidencePickAction.uploadFiles),
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

    setState(() {
      for (final f in res.files) {
        _appendEvidenceFile(f);
      }
    });
  }

  Future<void> _capturePhotoEvidence() async {
    if (!_supportsCameraCapture) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera capture is not available on this device.')),
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera capture failed: $e')),
      );
    }
  }

  void _removeEvidenceAt(int i) {
    setState(() => _pickedFiles.removeAt(i));
  }

  void _clearEvidence() {
    setState(() => _pickedFiles.clear());
  }

  Future<List<String>> _uploadEvidenceMultiple() async {
    if (_pickedFiles.isEmpty) return [];

    final urls = <String>[];

    for (final f in _pickedFiles) {
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

    setState(() => _incidentAt = selected);
  }

  // =========================
  // CLEAR / SUBMIT
  // =========================
  void _clearAll() {
    _formKey.currentState?.reset();

    setState(() {
      _studentUid = null;
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

      _pickedFiles.clear();
    });

    FocusManager.instance.primaryFocus?.unfocus();
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
          content: Text('✅ Violation case submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _clearAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _openMyReports() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MySubmittedCasesPage()),
    );
  }

  // =========================
  // UI HELPERS
  // =========================
  Widget _sectionTitle(String text, double scale) {
    return Row(
      children: [
        Container(
          width: 10 * scale,
          height: 10 * scale,
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4 * scale),
          ),
        ),
        SizedBox(width: 10 * scale),
        Text(
          text,
          style: TextStyle(
            color: textDark,
            fontWeight: FontWeight.w900,
            fontSize: (15.5 * scale).clamp(15.5, 18.0),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text, double scale) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * scale),
      child: Text(
        text,
        style: TextStyle(
          color: textDark,
          fontWeight: FontWeight.w900,
          fontSize: (13.5 * scale).clamp(13.5, 15.5),
        ),
      ),
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

        // breakpoints
        final bool wide = w >= 980; // desktop wide
        final bool tablet = w >= 640 && w < 980;

        final nowText = DateFormat('MMM d, yyyy • h:mm a').format(_incidentAt);

        final showSuggestions =
            _searchCtrl.text.trim().isNotEmpty && _studentUid == null;

        final suggestions = showSuggestions
            ? _filterStudentsLocal(_searchCtrl.text)
            : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        final maxCanvas = wide ? 1100.0 : 900.0;

        return Scaffold(
        backgroundColor: bg,
        body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(pad, 14 * scale, pad, 16 * scale),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxCanvas),
                  child: Column(
                    children: [
                      // ✅ OUTER SOFT CONTAINER
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(14 * scale),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(26 * scale),
                          border: Border.all(color: Colors.black.withOpacity(0.05)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
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
                                      fontSize: (18 * scale).clamp(18.0, 22.0),
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
                                      fontSize: (12.5 * scale).clamp(12.5, 14.0),
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
                                        color: primaryColor.withOpacity(0.45),
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

                                // ✅ STEP 1: SEARCH OUTSIDE CARDS (inside outer container)
                                _searchSection(
                                  scale: scale,
                                  suggestions: suggestions,
                                ),

                                SizedBox(height: 14 * scale),

                                // ✅ STEP 2: CARDS
                                if (wide) ...[
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: _studentInfoCard(scale: scale, forceFillHeight: true)),
                                        SizedBox(width: 14 * scale),
                                        Expanded(child: _violationDetailsCard(scale: scale, nowText: nowText, forceFillHeight: true)),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 14 * scale),

                                  // ✅ Card 3 full-width on desktop
                                  _narrativeEvidenceCard(scale: scale),
                                ] else ...[
                                  _studentInfoCard(scale: scale, forceFillHeight: false),
                                  SizedBox(height: 12 * scale),
                                  _violationDetailsCard(scale: scale, nowText: nowText, forceFillHeight: false),
                                  SizedBox(height: 12 * scale),

                                  // ✅ stacked on tablet/phone
                                  _narrativeEvidenceCard(scale: scale),
                                ],

                                SizedBox(height: 14 * scale),

                                // ✅ ACTIONS
                                if (wide || tablet) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: (52 * scale).clamp(52.0, 58.0),
                                          child: OutlinedButton.icon(
                                            onPressed: _submitting ? null : _clearAll,
                                            icon: const Icon(Icons.clear_all_rounded),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: primaryColor,
                                              side: BorderSide(color: primaryColor.withOpacity(0.45)),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(16 * scale),
                                              ),
                                            ),
                                            label: Text(
                                              "Clear Form",
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: (15.0 * scale).clamp(15.0, 17.0),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12 * scale),
                                      Expanded(
                                        child: SizedBox(
                                          height: (52 * scale).clamp(52.0, 58.0),
                                          child: ElevatedButton(
                                            onPressed: _submitting ? null : _submit,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: primaryColor,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(16 * scale),
                                              ),
                                            ),
                                            child: Text(
                                              _submitting ? "Submitting..." : "Submit Report",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: (15.5 * scale).clamp(15.5, 17.0),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  SizedBox(
                                    width: double.infinity,
                                    height: (52 * scale).clamp(52.0, 58.0),
                                    child: ElevatedButton(
                                      onPressed: _submitting ? null : _submit,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16 * scale),
                                        ),
                                      ),
                                      child: Text(
                                        _submitting ? "Submitting..." : "Submit Report",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: (15.5 * scale).clamp(15.5, 17.0),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 10 * scale),
                                  SizedBox(
                                    width: double.infinity,
                                    height: (48 * scale).clamp(48.0, 54.0),
                                    child: OutlinedButton.icon(
                                      onPressed: _submitting ? null : _clearAll,
                                      icon: const Icon(Icons.clear_all_rounded),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primaryColor,
                                        side: BorderSide(color: primaryColor.withOpacity(0.45)),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16 * scale),
                                        ),
                                      ),
                                      label: Text(
                                        "Clear Form",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: (14.5 * scale).clamp(14.5, 16.0),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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
    final showSuggestions =
        _searchCtrl.text.trim().isNotEmpty && _studentUid == null;

    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle("Search Student", scale),
          SizedBox(height: 10 * scale),

          TextFormField(
            controller: _searchCtrl,
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w800,
              fontSize: (13.5 * scale).clamp(13.5, 15.0),
            ),
            decoration: _decor(
              label: "Search (Name / Student No. / Program)",
              icon: Icons.search_rounded,
              helperText: _studentUid == null
                  ? "Pick a result to lock the student fields below"
                  : "Edit search to change selected student",
            ),
            onChanged: (_) {
              if (_studentUid != null) _clearSelectedStudentButKeepSearch();
              setState(() {});
            },
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

          if (!_loadingStudents &&
              _studentLoadError == null &&
              showSuggestions) ...[
            SizedBox(height: 10 * scale),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.75),
                borderRadius: BorderRadius.circular(16 * scale),
                border: Border.all(color: Colors.black.withOpacity(0.08)),
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
                        final name = (d['displayName'] ?? '').toString();
                        final no = (d['studentNo'] ?? '').toString();
                        final programId = (d['programId'] ?? '').toString();

                        return ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12 * scale),
                              border: Border.all(color: Colors.black.withOpacity(0.06)),
                            ),
                            child: const Icon(Icons.person_rounded, color: primaryColor, size: 18),
                          ),
                          title: Text(
                            no.isEmpty ? name : "$no — $name",
                            style: TextStyle(color: textDark, fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            programId.isEmpty ? "—" : programId,
                            style: TextStyle(color: hintColor, fontWeight: FontWeight.w700),
                          ),
                          onTap: () => _selectStudent(doc),
                        );
                      }).toList(),
                    ),
            ),
          ],

          SizedBox(height: 10 * scale),

          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
              decoration: BoxDecoration(
                color: (_studentUid != null)
                    ? primaryColor.withOpacity(0.12)
                    : Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: (_studentUid != null)
                      ? primaryColor.withOpacity(0.35)
                      : Colors.black.withOpacity(0.10),
                ),
              ),
              child: Text(
                _studentUid != null ? "Student selected" : "No student selected",
                style: TextStyle(
                  color: _studentUid != null ? primaryColor : hintColor,
                  fontWeight: FontWeight.w900,
                  fontSize: (12.5 * scale).clamp(12.5, 14.0),
                ),
              ),
            ),
          ),
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
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle("Student Info", scale),
          SizedBox(height: 10 * scale),

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

          SizedBox(height: 10 * scale),
          Text(
            "Note: These fields auto-fill after selecting a student.",
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
  // CARD 2: Violation Details (3-level structure)
  // =========================
  Widget _violationDetailsCard({
    required double scale,
    required String nowText,
    required bool forceFillHeight,
  }) {
    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle("Violation Details", scale),
          SizedBox(height: 10 * scale),

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
                  final mappedConcern =
                      (data['concern'] ?? '').toString().trim().toLowerCase();
                  setState(() {
                    _categoryId = id;
                    _categoryName = pickedName;
                    _concern = mappedConcern.isEmpty ? null : mappedConcern;
                    _typeId = null;
                    _typeName = null;
                    _typeCache = [];
                  });
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
                        final pickedLabel = (picked.data()['label'] ?? '').toString();
                        setState(() {
                          _typeId = id;
                          _typeName = pickedLabel;
                        });
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
                    color: primaryColor.withOpacity(0.9),
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
  // CARD 3: Description + Evidence (full width on desktop)
  // =========================
  Widget _narrativeEvidenceCard({required double scale}) {
    final hasFiles = _pickedFiles.isNotEmpty;

    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle("Narrative & Evidence", scale),
          SizedBox(height: 10 * scale),

          TextFormField(
            controller: _descriptionCtrl,
            maxLines: 5,
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w700,
              fontSize: (13.5 * scale).clamp(13.5, 15.0),
            ),
            decoration: _decor(
              label: "Description",
              icon: Icons.description_outlined,
              helperText: "Briefly explain what happened",
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
          ),

          SizedBox(height: 14 * scale),

          Row(
            children: [
              Expanded(child: _fieldLabel("Proof / Evidence (Multiple)", scale)),
              if (hasFiles)
                TextButton.icon(
                  onPressed: _clearEvidence,
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  label: const Text(
                    "Clear",
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),

          InkWell(
            borderRadius: BorderRadius.circular(18 * scale),
            onTap: _openEvidencePicker,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(14 * scale),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.75),
                borderRadius: BorderRadius.circular(18 * scale),
                border: Border.all(color: Colors.black.withOpacity(0.10)),
              ),
              child: Row(
                children: [
                  Container(
                    width: (46 * scale).clamp(46.0, 58.0),
                    height: (46 * scale).clamp(46.0, 58.0),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16 * scale),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: const Icon(Icons.upload_file_rounded, color: primaryColor),
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

            // Attached list (remove per file)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12 * scale),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.75),
                borderRadius: BorderRadius.circular(16 * scale),
                border: Border.all(color: Colors.black.withOpacity(0.08)),
              ),
              child: Column(
                children: List.generate(_pickedFiles.length, (i) {
                  final f = _pickedFiles[i];
                  final ext = (f.extension ?? '').toLowerCase();
                  final isPdf = ext == 'pdf';
                  final icon = isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded;

                  return Padding(
                    padding: EdgeInsets.only(bottom: i == _pickedFiles.length - 1 ? 0 : 10 * scale),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12 * scale),
                            border: Border.all(color: Colors.black.withOpacity(0.06)),
                          ),
                          child: Icon(icon, color: primaryColor, size: 18),
                        ),
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
                              color: Colors.red.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.red.withOpacity(0.18)),
                            ),
                            child: const Icon(Icons.close_rounded, color: Colors.red, size: 18),
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

enum _EvidencePickAction {
  capturePhoto,
  uploadFiles,
}

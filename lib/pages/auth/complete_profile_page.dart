import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/role_router.dart';
import '../shared/widgets/logout_confirm_dialog.dart';
import '../shared/widgets/unsaved_changes_guard.dart';

class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _studentNoController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  String? selectedCollege;
  String? selectedProgram;
  int? selectedYear;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> colleges = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> programs = [];

  bool _saving = false;
  bool _initialLoading = true;
  bool _uploadingPhoto = false;
  bool _showAllRejectionHistory = false;

  String? _lastRejectionReason;
  String? _photoUrl;
  XFile? _pickedPhoto;
  Uint8List? _pickedPhotoBytes;

  String? _firstNameError;
  String? _middleNameError;
  String? _lastNameError;
  String? _studentNoError;
  String? _collegeError;
  String? _programError;
  String? _yearError;
  String? _photoError;

  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  bool _isFormattingStudentNo = false;
  final ImagePicker _imagePicker = ImagePicker();

  bool _snapshotReady = false;
  String _initialFirstName = '';
  String _initialMiddleName = '';
  String _initialLastName = '';
  String _initialStudentNo = '';
  String _initialCollege = '';
  String _initialProgram = '';
  int? _initialYear;
  String _initialPhotoUrl = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _studentNoController.addListener(_formatStudentNo);
  }

  @override
  void dispose() {
    _studentNoController.removeListener(_formatStudentNo);
    _studentNoController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await _loadColleges();
      await _loadExistingProfile();
      if (!_snapshotReady) {
        _captureInitialSnapshot();
      }
    } finally {
      if (mounted) {
        setState(() => _initialLoading = false);
      }
    }
  }

  Future<void> _loadColleges() async {
    final snap = await FirebaseFirestore.instance
        .collection('colleges')
        .where('active', isEqualTo: true)
        .get();
    if (!mounted) return;
    setState(() => colleges = snap.docs);
  }

  Future<void> _loadPrograms(String collegeId) async {
    final snap = await FirebaseFirestore.instance
        .collection('programs')
        .where('collegeId', isEqualTo: collegeId)
        .where('active', isEqualTo: true)
        .get();
    if (!mounted) return;
    setState(() => programs = snap.docs);
  }

  int? _parseYear(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  Future<void> _loadExistingProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!doc.exists) return;

    final data = doc.data() ?? <String, dynamic>{};
    final studentProfileRaw = data['studentProfile'];
    final studentProfile = studentProfileRaw is Map
        ? Map<String, dynamic>.from(studentProfileRaw)
        : <String, dynamic>{};

    final collegeId = (studentProfile['collegeId'] ?? '').toString().trim();
    final programId = (studentProfile['programId'] ?? '').toString().trim();

    if (collegeId.isNotEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('programs')
          .where('collegeId', isEqualTo: collegeId)
          .where('active', isEqualTo: true)
          .get();
      programs = snap.docs;
    }

    final verification = (data['studentVerificationStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final reviewReason = (data['reviewReason'] ?? '').toString().trim();

    if (verification == 'pending_approval' || verification == 'verified') {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          RoleRouter.route(context);
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _firstNameController.text = (data['firstName'] ?? '').toString().trim();
      _middleNameController.text = (data['middleName'] ?? '').toString().trim();
      _lastNameController.text = (data['lastName'] ?? '').toString().trim();
      _studentNoController.text =
          (studentProfile['studentNo'] ?? data['studentNo'] ?? '')
              .toString()
              .trim();

      selectedCollege = collegeId.isEmpty ? null : collegeId;
      selectedProgram = programs.any((p) => p.id == programId)
          ? programId
          : null;
      selectedYear = _parseYear(
        studentProfile['yearLevel'] ?? data['yearLevel'],
      );

      _photoUrl = (data['photoUrl'] ?? '').toString().trim();
      _lastRejectionReason =
          verification == 'rejected' && reviewReason.isNotEmpty
          ? reviewReason
          : null;
      _captureInitialSnapshot();
    });
  }

  void _captureInitialSnapshot() {
    _initialFirstName = _firstNameController.text.trim();
    _initialMiddleName = _middleNameController.text.trim();
    _initialLastName = _lastNameController.text.trim();
    _initialStudentNo = _studentNoController.text.trim();
    _initialCollege = (selectedCollege ?? '').trim();
    _initialProgram = (selectedProgram ?? '').trim();
    _initialYear = selectedYear;
    _initialPhotoUrl = (_photoUrl ?? '').trim();
    _snapshotReady = true;
  }

  bool get _hasUnsavedChanges {
    if (!_snapshotReady || _initialLoading || _saving || _uploadingPhoto) {
      return false;
    }

    return _firstNameController.text.trim() != _initialFirstName ||
        _middleNameController.text.trim() != _initialMiddleName ||
        _lastNameController.text.trim() != _initialLastName ||
        _studentNoController.text.trim() != _initialStudentNo ||
        (selectedCollege ?? '').trim() != _initialCollege ||
        (selectedProgram ?? '').trim() != _initialProgram ||
        selectedYear != _initialYear ||
        (_photoUrl ?? '').trim() != _initialPhotoUrl ||
        _pickedPhoto != null;
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasUnsavedChanges) return true;
    return showUnsavedChangesDialog(
      context,
      title: 'Leave profile setup?',
      message:
          'You have unsaved profile changes. Leaving now will discard your current edits.',
    );
  }

  String _digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');

  String _formatDigitsToStudentNo(String digits) {
    final d = digits.length > 7 ? digits.substring(0, 7) : digits;
    if (d.length <= 3) return d;
    return '${d.substring(0, 3)}-${d.substring(3)}';
  }

  void _formatStudentNo() {
    if (_isFormattingStudentNo) return;
    final raw = _studentNoController.text;
    final digits = _digitsOnly(raw);
    final formatted = _formatDigitsToStudentNo(digits);
    if (raw == formatted) return;

    _isFormattingStudentNo = true;
    _studentNoController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _isFormattingStudentNo = false;
  }

  bool _isStudentNoValid(String value) {
    return RegExp(r'^\d{3}-\d{4}$').hasMatch(value);
  }

  String _toTitleCase(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return trimmed;
    final lower = trimmed.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  String _toUpper(String s) => s.trim().toUpperCase();

  void _clearErrors() {
    _firstNameError = null;
    _middleNameError = null;
    _lastNameError = null;
    _studentNoError = null;
    _collegeError = null;
    _programError = null;
    _yearError = null;
    _photoError = null;
  }

  bool _validateFields() {
    _clearErrors();

    final studentNo = _studentNoController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    var ok = true;

    if (firstName.isEmpty) {
      _firstNameError = 'First name is required';
      ok = false;
    }
    if (lastName.isEmpty) {
      _lastNameError = 'Last name is required';
      ok = false;
    }
    if (studentNo.isEmpty) {
      _studentNoError = 'Student number is required';
      ok = false;
    } else if (!_isStudentNoValid(studentNo)) {
      _studentNoError = 'Invalid format. Use 123-1234';
      ok = false;
    }
    if (selectedCollege == null || selectedCollege!.isEmpty) {
      _collegeError = 'Please select a college';
      ok = false;
    }
    if (selectedProgram == null || selectedProgram!.isEmpty) {
      _programError = 'Please select a program';
      ok = false;
    }
    if (selectedYear == null) {
      _yearError = 'Please select a year level';
      ok = false;
    }

    final hasExistingPhoto = (_photoUrl ?? '').trim().isNotEmpty;
    final hasPickedPhoto = _pickedPhoto != null;
    if (!hasExistingPhoto && !hasPickedPhoto) {
      _photoError = 'Profile photo is required';
      ok = false;
    }

    setState(() {});
    return ok;
  }

  Future<void> _pickProfilePhoto() async {
    if (_uploadingPhoto || _saving) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedPhoto = picked;
        _pickedPhotoBytes = bytes;
        _photoError = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return 'jpg';
    return filename.substring(dot + 1).toLowerCase();
  }

  String _contentTypeForExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  Future<String> _uploadProfilePhoto(String uid, XFile photo) async {
    final ext = _extensionOf(photo.name.isEmpty ? photo.path : photo.name);
    final path =
        'users/$uid/profile/profile_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance.ref(path);
    final metadata = SettableMetadata(contentType: _contentTypeForExt(ext));
    if (kIsWeb) {
      final bytes = await photo.readAsBytes();
      await ref.putData(bytes, metadata);
    } else {
      await ref.putFile(File(photo.path), metadata);
    }
    return ref.getDownloadURL();
  }

  Future<void> _notifyPendingApprovalReviewers({
    required String studentUid,
    required String studentName,
    required String studentNo,
    required String collegeId,
    required String programId,
    required int? yearLevel,
  }) async {
    final departmentCode = collegeId.trim();
    if (departmentCode.isEmpty) return;

    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db
            .collection('users')
            .where('role', isEqualTo: 'department_admin')
            .get(),
        db.collection('users').where('role', isEqualTo: 'dean').get(),
      ]);

      final recipients = <String>{};
      for (final snap in results) {
        for (final doc in snap.docs) {
          final data = doc.data();
          final uid = (data['uid'] ?? doc.id).toString().trim();
          if (uid.isEmpty || uid == studentUid) continue;

          final accountStatus = (data['accountStatus'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (accountStatus == 'inactive') continue;

          final reviewerDepartment =
              (data['employeeProfile']?['department'] ?? '').toString().trim();
          if (reviewerDepartment != departmentCode) continue;

          recipients.add(uid);
        }
      }

      for (final recipientUid in recipients) {
        await db
            .collection('users')
            .doc(recipientUid)
            .collection('notifications')
            .add({
              'title': 'Pending Approval',
              'body':
                  '$studentName submitted a student profile for department approval.',
              'payload': {
                'type': 'student_profile_pending_approval',
                'studentUid': studentUid,
                'studentName': studentName,
                'studentNo': studentNo,
                'collegeId': departmentCode,
                'programId': programId,
                'yearLevel': yearLevel,
              },
              'createdAt': FieldValue.serverTimestamp(),
              'readAt': null,
            });
      }
    } catch (e) {
      debugPrint('Failed to notify pending-approval reviewers: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (_saving || _uploadingPhoto) return;

    final valid = _validateFields();
    if (!valid) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      String? nextPhotoUrl = _photoUrl;
      if (_pickedPhoto != null) {
        setState(() => _uploadingPhoto = true);
        nextPhotoUrl = await _uploadProfilePhoto(uid, _pickedPhoto!);
        if (mounted) {
          setState(() {
            _photoUrl = nextPhotoUrl;
            _pickedPhoto = null;
            _pickedPhotoBytes = null;
          });
        }
      }

      final firstName = _toTitleCase(_firstNameController.text);
      final middleName = _toTitleCase(_middleNameController.text);
      final lastName = _toTitleCase(_lastNameController.text);

      final displayName = middleName.isEmpty
          ? '${_toUpper(lastName)}, $firstName'
          : '${_toUpper(lastName)}, $firstName $middleName';

      final studentNo = _studentNoController.text.trim();
      final currentCollege = (selectedCollege ?? '').trim();
      final currentProgram = (selectedProgram ?? '').trim();
      final fullName = '$firstName $lastName'.trim();

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'studentProfile': {
          'studentNo': studentNo,
          'collegeId': selectedCollege,
          'programId': selectedProgram,
          'yearLevel': selectedYear,
        },
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'displayName': displayName,
        if ((nextPhotoUrl ?? '').trim().isNotEmpty) 'photoUrl': nextPhotoUrl,
        'accountStatus': 'active',
        'studentVerificationStatus': 'pending_approval',
        'status': 'pending_approval',
        'reviewReason': FieldValue.delete(),
        'reviewDecision': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _notifyPendingApprovalReviewers(
        studentUid: uid,
        studentName: fullName.isEmpty ? displayName : fullName,
        studentNo: studentNo,
        collegeId: currentCollege,
        programId: currentProgram,
        yearLevel: selectedYear,
      );

      if (!mounted) return;
      await RoleRouter.route(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    final canLeave = await _confirmDiscardIfNeeded();
    if (!context.mounted || !canLeave) return;
    final confirmed = await showLogoutConfirmDialog(context);
    if (!context.mounted || !confirmed) return;
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (r) => false);
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? helperText,
    String? errorText,
    bool isRequired = false,
    bool optional = false,
  }) {
    final labelBaseStyle = const TextStyle(
      color: hint,
      fontWeight: FontWeight.w700,
    );
    return InputDecoration(
      label: Text.rich(
        TextSpan(
          text: label,
          style: labelBaseStyle,
          children: [
            if (isRequired)
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w900,
                ),
              ),
            if (optional)
              const TextSpan(
                text: ' (optional)',
                style: TextStyle(color: hint, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
      helperText: helperText,
      errorText: errorText,
      helperStyle: TextStyle(
        color: hint.withValues(alpha: 0.9),
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(icon, color: primary.withValues(alpha: 0.85)),
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
        borderSide: const BorderSide(color: primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  DateTime? _logDate(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) return createdAt.toDate();

    final epoch = data['createdAtEpochMs'];
    if (epoch is int) {
      return DateTime.fromMillisecondsSinceEpoch(epoch);
    }
    if (epoch is num) {
      return DateTime.fromMillisecondsSinceEpoch(epoch.toInt());
    }
    return null;
  }

  String _formatLogDate(DateTime? date) {
    if (date == null) return '--';
    final local = date.toLocal();
    const monthNames = [
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
    final month = monthNames[local.month - 1];
    final day = local.day.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour24 = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12Raw = hour24 % 12;
    final hour12 = (hour12Raw == 0 ? 12 : hour12Raw).toString();
    return '$month $day, $year  $hour12:$minute $suffix';
  }

  bool _isRejectedLog(Map<String, dynamic> data) {
    final action = (data['action'] ?? '').toString().trim().toLowerCase();
    final title = (data['title'] ?? '').toString().trim().toLowerCase();
    final payloadRaw = data['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : const <String, dynamic>{};
    final decision = (payload['decision'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return action == 'rejected' ||
        action.contains('reject') ||
        title.contains('reject') ||
        decision == 'rejected';
  }

  String _extractRejectReason(Map<String, dynamic> data) {
    final directReason = (data['reason'] ?? '').toString().trim();
    if (directReason.isNotEmpty) return directReason;

    final payloadRaw = data['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : const <String, dynamic>{};
    final payloadReason = (payload['reason'] ?? '').toString().trim();
    if (payloadReason.isNotEmpty) return payloadReason;

    final details = (data['details'] ?? '').toString().trim();
    if (details.isEmpty) return 'No reason provided.';

    const marker = 'Reason:';
    final markerIndex = details.toLowerCase().indexOf(marker.toLowerCase());
    if (markerIndex >= 0) {
      final parsed = details.substring(markerIndex + marker.length).trim();
      if (parsed.isNotEmpty) return parsed;
    }
    return details;
  }

  String _formatActor(String name, String role) {
    final safeName = name.trim().isEmpty ? 'Reviewer' : name.trim();
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedRole.isEmpty) return safeName;

    String prettyRole;
    switch (normalizedRole) {
      case 'department_admin':
        prettyRole = 'Department Admin';
        break;
      case 'osa_admin':
        prettyRole = 'OSA Admin';
        break;
      default:
        prettyRole = normalizedRole
            .split('_')
            .where((p) => p.trim().isNotEmpty)
            .map((p) => p[0].toUpperCase() + p.substring(1))
            .join(' ');
        break;
    }
    return '$safeName ($prettyRole)';
  }

  Widget _buildRevisionAuditCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('profile_logs')
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final rejected =
            docs.map((doc) => doc.data()).where(_isRejectedLog).toList()
              ..sort((a, b) {
                final ad = _logDate(a);
                final bd = _logDate(b);
                if (ad == null && bd == null) return 0;
                if (ad == null) return 1;
                if (bd == null) return -1;
                return bd.compareTo(ad);
              });

        final latestReasonFallback = (_lastRejectionReason ?? '').trim();
        if (latestReasonFallback.isNotEmpty) {
          final exists = rejected.any(
            (row) =>
                _extractRejectReason(row).trim().toLowerCase() ==
                latestReasonFallback.toLowerCase(),
          );
          if (!exists) {
            rejected.insert(0, <String, dynamic>{
              'reason': latestReasonFallback,
              'actorName': '',
              'actorRole': '',
              '_syntheticLatest': true,
            });
          }
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            rejected.isEmpty) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4F4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF9A9A)),
            ),
            child: Row(
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Loading revision details...',
                    style: TextStyle(
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

        if (rejected.isEmpty) return const SizedBox.shrink();

        final collapsedCount = 3;
        final showAll = _showAllRejectionHistory;
        final visible = showAll
            ? rejected
            : rejected.take(collapsedCount).toList();
        final canExpand = rejected.length > collapsedCount;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4F4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEF9A9A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profile Revision Required',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your previous details are loaded below. Update the needed fields and resubmit. Your updated profile will be reviewed by the Dean for approval.',
                          style: TextStyle(
                            color: textDark.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...List.generate(visible.length, (index) {
                final row = visible[index];
                final isLatest = index == 0;
                final reason = _extractRejectReason(row);
                final when = _formatLogDate(_logDate(row));
                final actor = _formatActor(
                  (row['actorName'] ?? '').toString(),
                  (row['actorRole'] ?? '').toString(),
                );
                final synthetic = row['_syntheticLatest'] == true;
                final meta = synthetic
                    ? 'Latest review'
                    : (when == '--' ? actor : '$when - $actor');

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              reason,
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          if (isLatest)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(
                                'Latest',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        style: TextStyle(
                          color: textDark.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (canExpand)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _showAllRejectionHistory = !_showAllRejectionHistory;
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      showAll ? 'See less' : 'See more',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
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

  ImageProvider<Object>? _profileImageProvider() {
    if (_pickedPhotoBytes != null) return MemoryImage(_pickedPhotoBytes!);
    final url = (_photoUrl ?? '').trim();
    if (url.isNotEmpty) return NetworkImage(url);
    return null;
  }

  Widget _buildProfilePhotoCard() {
    final imageProvider = _profileImageProvider();
    final hasError = (_photoError ?? '').isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? Colors.red.shade400
              : primary.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFFE8F3E8),
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? const Icon(Icons.person_rounded, color: primary, size: 28)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profile Photo *',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Required. JPG or PNG recommended.',
                  style: TextStyle(
                    color: hint.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if (hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _photoError!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: (_saving || _uploadingPhoto)
                  ? null
                  : _pickProfilePhoto,
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: Text(
                (_photoUrl ?? '').trim().isEmpty && _pickedPhoto == null
                    ? 'Upload'
                    : 'Change',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                side: BorderSide(color: primary.withValues(alpha: 0.45)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldColumn() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 700;

        Widget first = TextField(
          controller: _firstNameController,
          onChanged: (_) => setState(() => _firstNameError = null),
          decoration: _decor(
            label: 'First Name',
            isRequired: true,
            icon: Icons.person_outline_rounded,
            errorText: _firstNameError,
          ),
        );
        Widget middle = TextField(
          controller: _middleNameController,
          onChanged: (_) => setState(() => _middleNameError = null),
          decoration: _decor(
            label: 'Middle Name',
            optional: true,
            icon: Icons.person_outline_rounded,
            errorText: _middleNameError,
          ),
        );
        Widget last = TextField(
          controller: _lastNameController,
          onChanged: (_) => setState(() => _lastNameError = null),
          decoration: _decor(
            label: 'Last Name',
            isRequired: true,
            icon: Icons.person_outline_rounded,
            errorText: _lastNameError,
          ),
        );
        Widget studentNo = TextField(
          controller: _studentNoController,
          onChanged: (_) => setState(() => _studentNoError = null),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: _decor(
            label: 'Student Number',
            isRequired: true,
            icon: Icons.badge_outlined,
            helperText: 'Format: 123-1234',
            errorText: _studentNoError,
          ),
        );
        Widget college = DropdownButtonFormField<String>(
          initialValue: selectedCollege,
          isExpanded: true,
          decoration: _decor(
            label: 'College',
            isRequired: true,
            icon: Icons.account_balance_outlined,
            errorText: _collegeError,
          ),
          items: colleges
              .map(
                (c) => DropdownMenuItem<String>(
                  value: c.id,
                  child: Text(
                    (c.data()['name'] ?? '').toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              selectedCollege = value;
              selectedProgram = null;
              programs.clear();
              _collegeError = null;
              _programError = null;
            });
            _loadPrograms(value);
          },
        );
        Widget program = DropdownButtonFormField<String>(
          key: ValueKey(selectedCollege),
          initialValue: selectedProgram,
          isExpanded: true,
          decoration: _decor(
            label: 'Program',
            isRequired: true,
            icon: Icons.school_outlined,
            errorText: _programError,
          ),
          items: programs
              .map(
                (p) => DropdownMenuItem<String>(
                  value: p.id,
                  child: Text(
                    (p.data()['name'] ?? '').toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() {
            selectedProgram = value;
            _programError = null;
          }),
        );
        Widget year = DropdownButtonFormField<int>(
          initialValue: selectedYear,
          isExpanded: true,
          decoration: _decor(
            label: 'Year Level',
            isRequired: true,
            icon: Icons.calendar_today_outlined,
            errorText: _yearError,
          ),
          items: [1, 2, 3, 4]
              .map(
                (y) => DropdownMenuItem<int>(value: y, child: Text('Year $y')),
              )
              .toList(),
          onChanged: (value) => setState(() {
            selectedYear = value;
            _yearError = null;
          }),
        );

        if (!twoColumns) {
          return Column(
            children: [
              first,
              const SizedBox(height: 12),
              middle,
              const SizedBox(height: 12),
              last,
              const SizedBox(height: 16),
              studentNo,
              const SizedBox(height: 16),
              college,
              const SizedBox(height: 16),
              program,
              const SizedBox(height: 16),
              year,
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: first),
                const SizedBox(width: 12),
                Expanded(child: middle),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: last),
                const SizedBox(width: 12),
                Expanded(child: studentNo),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: college),
                const SizedBox(width: 12),
                Expanded(child: program),
              ],
            ),
            const SizedBox(height: 12),
            year,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final contentMaxWidth = w >= 1200
        ? 960.0
        : w >= 900
        ? 840.0
        : double.infinity;

    return WillPopScope(
      onWillPop: _confirmDiscardIfNeeded,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: Container(
                margin: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: primary.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: _initialLoading
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.6),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'COMPLETE YOUR PROFILE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Please fill in the required details to continue',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: hint,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildRevisionAuditCard(),
                            _buildProfilePhotoCard(),
                            const SizedBox(height: 16),
                            _buildFieldColumn(),
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                onPressed: (_saving || _uploadingPhoto)
                                    ? null
                                    : _saveProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primary,
                                  foregroundColor: Colors.white,
                                ),
                                child: (_saving || _uploadingPhoto)
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Save Profile',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F2E3),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: primary.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    color: primary.withValues(alpha: 0.9),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'This profile will be reviewed by your Dean for approval. Please provide complete and accurate information before submitting.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: () => _logout(context),
                                icon: const Icon(
                                  Icons.logout_rounded,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Log out',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primary,
                                  side: const BorderSide(
                                    color: primary,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
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
      ),
    );
  }
}

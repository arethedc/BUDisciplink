import 'dart:math';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../shared/widgets/modern_table_layout.dart';

class UserManagementPage extends StatefulWidget {
  final bool studentsOnlyScope;
  final String? headerTitle;
  final String? headerSubtitle;

  const UserManagementPage({
    super.key,
    this.studentsOnlyScope = false,
    this.headerTitle,
    this.headerSubtitle,
  });

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _allUsersStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _studentUsersStream;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';

  Map<String, dynamic>? _currentUserData;
  bool _loadingAdminData = true;
  String? _selectedUserId;
  bool _detailEditing = false;
  String _pendingStudentFilter = 'pending_approval';

  final _detailFirstNameCtrl = TextEditingController();
  final _detailMiddleNameCtrl = TextEditingController();
  final _detailLastNameCtrl = TextEditingController();
  final _detailEmailCtrl = TextEditingController();
  final _detailStudentNoCtrl = TextEditingController();
  final _detailCollegeCtrl = TextEditingController();
  final _detailProgramCtrl = TextEditingController();
  final _detailYearLevelCtrl = TextEditingController();
  final _detailEmployeeNoCtrl = TextEditingController();
  final _detailDepartmentCtrl = TextEditingController();
  String _detailRole = '';
  String _detailAccountStatus = 'active';
  String _detailStudentVerificationStatus = 'verified';
  Timer? _detailStudentNoDebounce;
  bool _detailStudentNoChecking = false;
  String? _detailStudentNoAvailabilityError;
  Timer? _detailEmployeeNoDebounce;
  bool _detailEmployeeNoChecking = false;
  String? _detailEmployeeNoAvailabilityError;
  String _detailOriginalStudentNo = '';
  String _detailOriginalEmployeeNo = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _filterCacheSourceDocs;
  String _filterCacheType = '';
  String _filterCacheQuery = '';
  String _filterCachePendingFilter = '';
  String _filterCacheAdminRole = '';
  String _filterCacheAdminDept = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterCacheResult =
      const [];

  // Design Theme
  static const primaryColor = Color(0xFF1B5E20);
  static const accentColor = Color(0xFF43A047);
  static const backgroundColor = Color(0xFFF6FAF6);
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _allUsersStream = FirebaseFirestore.instance
        .collection('users')
        .snapshots();
    _studentUsersStream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'student')
        .snapshots();
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (mounted) {
          setState(() {
            _currentUserData = doc.data();
            _loadingAdminData = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadingAdminData = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _detailStudentNoDebounce?.cancel();
    _detailEmployeeNoDebounce?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    _detailFirstNameCtrl.dispose();
    _detailMiddleNameCtrl.dispose();
    _detailLastNameCtrl.dispose();
    _detailEmailCtrl.dispose();
    _detailStudentNoCtrl.dispose();
    _detailCollegeCtrl.dispose();
    _detailProgramCtrl.dispose();
    _detailYearLevelCtrl.dispose();
    _detailEmployeeNoCtrl.dispose();
    _detailDepartmentCtrl.dispose();
    super.dispose();
  }

  String _activeUserListType() {
    switch (_tabController.index) {
      case 1:
        return 'active_staff';
      case 2:
        return 'inactive_staff';
      default:
        return 'staff';
    }
  }

  String _studentsOnlyListType() {
    switch (_tabController.index) {
      case 1:
        return 'active_students';
      case 2:
        return 'pending';
      default:
        return 'students';
    }
  }

  Widget _buildPendingStudentFilterBar() {
    Widget chip({required String value, required String label}) {
      final selected = _pendingStudentFilter == value;
      return FilterChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) {
          setState(() => _pendingStudentFilter = value);
        },
        selectedColor: primaryColor.withValues(alpha: 0.15),
        checkmarkColor: primaryColor,
        side: BorderSide(
          color: selected
              ? primaryColor.withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: 0.10),
        ),
        labelStyle: TextStyle(
          color: selected ? primaryColor : textDark,
          fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
        ),
      );
    }

    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip(
            value: 'pending_email_verification',
            label: 'Pending Email Verification',
          ),
          chip(value: 'pending_profile', label: 'Pending Profile'),
          chip(value: 'pending_approval', label: 'Pending Approval'),
        ],
      ),
    );
  }

  bool get _isDepartmentAdminScope {
    if (widget.studentsOnlyScope) return true;
    final role = (_currentUserData?['role'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return role == 'department_admin' || role == 'dean';
  }

  String _displayName(Map<String, dynamic> data) {
    final studentProfile =
        data['studentProfile'] as Map<String, dynamic>? ?? {};
    final employeeProfile =
        data['employeeProfile'] as Map<String, dynamic>? ?? {};

    final dn = (data['displayName'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final full = ('$first $last').trim();
    if (full.isNotEmpty) return full;
    final email = (data['email'] ?? '').toString().trim();
    if (email.contains('@')) return email.split('@').first;
    return '--';
  }

  String _displayId(Map<String, dynamic> data) {
    final studentProfile =
        data['studentProfile'] as Map<String, dynamic>? ?? {};
    final employeeProfile =
        data['employeeProfile'] as Map<String, dynamic>? ?? {};
    final role = (data['role'] ?? '').toString().trim().toLowerCase();

    if (role == 'student') {
      return (studentProfile['studentNo'] ?? data['studentNo'] ?? 'No ID')
          .toString();
    }
    return (employeeProfile['employeeNo'] ?? data['employeeNo'] ?? 'No ID')
        .toString();
  }

  String _formatRole(String role) {
    switch (role) {
      case 'osa_admin':
        return 'OSA Admin';
      case 'counseling_admin':
        return 'Counseling Admin';
      case 'super_admin':
        return 'Super Admin';
      case 'professor':
        return 'Professor';
      case 'guard':
        return 'Guard';
      case 'student':
        return 'Student';
      case 'department_admin':
        return 'Department Admin (Dean)';
      default:
        return role.isEmpty ? '--' : role;
    }
  }

  bool _isStudentRole(String role) => role.trim().toLowerCase() == 'student';

  String _normalizeAccountStatus(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'inactive') return 'inactive';
    return 'active';
  }

  String _normalizeStudentVerification(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'pending_verification') {
      return 'pending_approval';
    }
    if (value == 'pending_email_verification' ||
        value == 'pending_profile' ||
        value == 'pending_approval' ||
        value == 'verified') {
      return value;
    }
    return 'verified';
  }

  String _readStudentVerification(
    Map<String, dynamic> data, {
    String role = 'student',
  }) {
    if (!_isStudentRole(role)) return '';
    final field = (data['studentVerificationStatus'] ?? '').toString().trim();
    if (field.isNotEmpty) return _normalizeStudentVerification(field);

    final legacy = (data['status'] ?? '').toString().trim().toLowerCase();
    if (legacy == 'pending_profile' ||
        legacy == 'pending_email_verification' ||
        legacy == 'pending_approval' ||
        legacy == 'pending_verification' ||
        legacy == 'verified') {
      return _normalizeStudentVerification(legacy);
    }
    if (legacy == 'active') return 'verified';
    return 'pending_profile';
  }

  String _readAccountStatus(Map<String, dynamic> data, {required String role}) {
    final field = (data['accountStatus'] ?? '').toString().trim();
    if (field.isNotEmpty) return _normalizeAccountStatus(field);

    final legacy = (data['status'] ?? '').toString().trim().toLowerCase();
    if (legacy == 'inactive') return 'inactive';
    return 'active';
  }

  String _legacyStatusValue({
    required String role,
    required String accountStatus,
    String? studentVerificationStatus,
  }) {
    if (!_isStudentRole(role)) return accountStatus;
    if (accountStatus == 'inactive') return 'inactive';
    return _normalizeStudentVerification(
      studentVerificationStatus ?? 'verified',
    );
  }

  bool _roleNeedsDepartmentFor(String role) {
    final key = role.trim().toLowerCase();
    return key != 'student' &&
        key != 'osa_admin' &&
        key != 'counseling_admin' &&
        key != 'super_admin';
  }

  void _clearDetailSelection() {
    setState(() {
      _selectedUserId = null;
      _detailEditing = false;
      _detailRole = '';
      _detailAccountStatus = 'active';
      _detailStudentVerificationStatus = 'verified';
      _detailStudentNoChecking = false;
      _detailStudentNoAvailabilityError = null;
      _detailEmployeeNoChecking = false;
      _detailEmployeeNoAvailabilityError = null;
      _detailOriginalStudentNo = '';
      _detailOriginalEmployeeNo = '';
      _detailFirstNameCtrl.clear();
      _detailMiddleNameCtrl.clear();
      _detailLastNameCtrl.clear();
      _detailEmailCtrl.clear();
      _detailStudentNoCtrl.clear();
      _detailCollegeCtrl.clear();
      _detailProgramCtrl.clear();
      _detailYearLevelCtrl.clear();
      _detailEmployeeNoCtrl.clear();
      _detailDepartmentCtrl.clear();
    });
  }

  void _loadDetailFromData(
    String uid,
    Map<String, dynamic> data, {
    bool resetEditing = true,
  }) {
    final studentProfile =
        (data['studentProfile'] as Map<String, dynamic>?) ?? {};
    final employeeProfile =
        (data['employeeProfile'] as Map<String, dynamic>?) ?? {};
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    final accountStatus = _readAccountStatus(data, role: role);
    final studentVerification = _readStudentVerification(data, role: role);

    setState(() {
      _selectedUserId = uid;
      if (resetEditing) _detailEditing = false;
      _detailRole = role;
      _detailAccountStatus = accountStatus;
      _detailStudentVerificationStatus = studentVerification;
      _detailStudentNoChecking = false;
      _detailStudentNoAvailabilityError = null;
      _detailEmployeeNoChecking = false;
      _detailEmployeeNoAvailabilityError = null;

      _detailFirstNameCtrl.text = (data['firstName'] ?? '').toString().trim();
      _detailMiddleNameCtrl.text = (data['middleName'] ?? '').toString().trim();
      _detailLastNameCtrl.text = (data['lastName'] ?? '').toString().trim();
      _detailEmailCtrl.text = (data['email'] ?? '').toString().trim();
      _detailStudentNoCtrl.text =
          (studentProfile['studentNo'] ?? data['studentNo'] ?? '')
              .toString()
              .trim();
      _detailCollegeCtrl.text = (studentProfile['collegeId'] ?? '')
          .toString()
          .trim();
      _detailProgramCtrl.text = (studentProfile['programId'] ?? '')
          .toString()
          .trim();
      _detailYearLevelCtrl.text = (studentProfile['yearLevel'] ?? '')
          .toString()
          .trim();
      _detailEmployeeNoCtrl.text =
          (employeeProfile['employeeNo'] ?? data['employeeNo'] ?? '')
              .toString()
              .trim();
      _detailOriginalStudentNo = _detailStudentNoCtrl.text.trim();
      _detailOriginalEmployeeNo = _detailEmployeeNoCtrl.text.trim();
      _detailDepartmentCtrl.text = (employeeProfile['department'] ?? '')
          .toString()
          .trim();
    });
  }

  Future<bool> _existsByFieldForOtherUser({
    required String field,
    required String value,
    required String currentUid,
  }) async {
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where(field, isEqualTo: value)
        .limit(3)
        .get();
    return query.docs.any((doc) => doc.id != currentUid);
  }

  Future<bool> _isDetailStudentNoAvailable(String studentNo) async {
    final uid = _selectedUserId;
    if (uid == null) return true;
    if (studentNo == _detailOriginalStudentNo) return true;
    final hasDuplicateNested = await _existsByFieldForOtherUser(
      field: 'studentProfile.studentNo',
      value: studentNo,
      currentUid: uid,
    );
    if (hasDuplicateNested) return false;
    final hasDuplicateLegacy = await _existsByFieldForOtherUser(
      field: 'studentNo',
      value: studentNo,
      currentUid: uid,
    );
    return !hasDuplicateLegacy;
  }

  Future<bool> _isDetailEmployeeNoAvailable(String employeeNo) async {
    final uid = _selectedUserId;
    if (uid == null) return true;
    if (employeeNo == _detailOriginalEmployeeNo) return true;
    final hasDuplicateNested = await _existsByFieldForOtherUser(
      field: 'employeeProfile.employeeNo',
      value: employeeNo,
      currentUid: uid,
    );
    if (hasDuplicateNested) return false;
    final hasDuplicateLegacy = await _existsByFieldForOtherUser(
      field: 'employeeNo',
      value: employeeNo,
      currentUid: uid,
    );
    return !hasDuplicateLegacy;
  }

  void _scheduleDetailStudentNoAvailabilityCheck(String raw) {
    _detailStudentNoDebounce?.cancel();
    final studentNo = raw.trim();
    const pattern = r'^\d{3}-\d{4}$';

    if (!_detailEditing || !_isStudentRole(_detailRole)) {
      if (_detailStudentNoChecking ||
          _detailStudentNoAvailabilityError != null) {
        setState(() {
          _detailStudentNoChecking = false;
          _detailStudentNoAvailabilityError = null;
        });
      }
      return;
    }

    if (studentNo.isEmpty || !RegExp(pattern).hasMatch(studentNo)) {
      setState(() {
        _detailStudentNoChecking = false;
        _detailStudentNoAvailabilityError = null;
      });
      return;
    }

    if (studentNo == _detailOriginalStudentNo) {
      setState(() {
        _detailStudentNoChecking = false;
        _detailStudentNoAvailabilityError = null;
      });
      return;
    }

    setState(() {
      _detailStudentNoChecking = true;
      _detailStudentNoAvailabilityError = null;
    });

    _detailStudentNoDebounce = Timer(
      const Duration(milliseconds: 450),
      () async {
        bool available = true;
        try {
          available = await _isDetailStudentNoAvailable(studentNo);
        } catch (_) {
          available = true;
        }
        if (!mounted) return;
        if (!_detailEditing || !_isStudentRole(_detailRole)) return;
        if (_detailStudentNoCtrl.text.trim() != studentNo) return;
        setState(() {
          _detailStudentNoChecking = false;
          _detailStudentNoAvailabilityError = available
              ? null
              : 'Student Number already exists';
        });
      },
    );
  }

  void _scheduleDetailEmployeeNoAvailabilityCheck(String raw) {
    _detailEmployeeNoDebounce?.cancel();
    final employeeNo = raw.trim();
    const pattern = r'^\d{4}-\d{3}$';

    if (!_detailEditing || _isStudentRole(_detailRole)) {
      if (_detailEmployeeNoChecking ||
          _detailEmployeeNoAvailabilityError != null) {
        setState(() {
          _detailEmployeeNoChecking = false;
          _detailEmployeeNoAvailabilityError = null;
        });
      }
      return;
    }

    if (employeeNo.isEmpty || !RegExp(pattern).hasMatch(employeeNo)) {
      setState(() {
        _detailEmployeeNoChecking = false;
        _detailEmployeeNoAvailabilityError = null;
      });
      return;
    }

    if (employeeNo == _detailOriginalEmployeeNo) {
      setState(() {
        _detailEmployeeNoChecking = false;
        _detailEmployeeNoAvailabilityError = null;
      });
      return;
    }

    setState(() {
      _detailEmployeeNoChecking = true;
      _detailEmployeeNoAvailabilityError = null;
    });

    _detailEmployeeNoDebounce = Timer(
      const Duration(milliseconds: 450),
      () async {
        bool available = true;
        try {
          available = await _isDetailEmployeeNoAvailable(employeeNo);
        } catch (_) {
          available = true;
        }
        if (!mounted) return;
        if (!_detailEditing || _isStudentRole(_detailRole)) return;
        if (_detailEmployeeNoCtrl.text.trim() != employeeNo) return;
        setState(() {
          _detailEmployeeNoChecking = false;
          _detailEmployeeNoAvailabilityError = available
              ? null
              : 'Employee ID already exists';
        });
      },
    );
  }

  bool get _detailSaveLocked {
    if (!_detailEditing) return false;
    if (_detailStudentNoChecking || _detailEmployeeNoChecking) return true;
    if (_detailStudentNoAvailabilityError != null ||
        _detailEmployeeNoAvailabilityError != null) {
      return true;
    }

    if (_isStudentRole(_detailRole)) {
      final studentNo = _detailStudentNoCtrl.text.trim();
      if (studentNo.isNotEmpty &&
          !RegExp(r'^\d{3}-\d{4}$').hasMatch(studentNo)) {
        return true;
      }
      return false;
    }

    final employeeNo = _detailEmployeeNoCtrl.text.trim();
    if (employeeNo.isNotEmpty &&
        !RegExp(r'^\d{4}-\d{3}$').hasMatch(employeeNo)) {
      return true;
    }
    return false;
  }

  Future<void> _saveSelectedUserDetails() async {
    final uid = _selectedUserId;
    if (uid == null) return;
    if (_detailSaveLocked) return;

    final role = _detailRole;
    final firstName = _detailFirstNameCtrl.text.trim();
    final middleName = _detailMiddleNameCtrl.text.trim();
    final lastName = _detailLastNameCtrl.text.trim();

    if (firstName.isEmpty || lastName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('First name and last name are required.')),
      );
      return;
    }

    if (_isStudentRole(role)) {
      final studentNo = _detailStudentNoCtrl.text.trim();
      if (studentNo.isNotEmpty &&
          !RegExp(r'^\d{3}-\d{4}$').hasMatch(studentNo)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student Number must be ###-####.')),
        );
        return;
      }
      if (studentNo.isNotEmpty) {
        final available = await _isDetailStudentNoAvailable(studentNo);
        if (!available) {
          if (!mounted) return;
          setState(() {
            _detailStudentNoAvailabilityError = 'Student Number already exists';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Student Number already exists.')),
          );
          return;
        }
      }
    } else {
      final employeeNo = _detailEmployeeNoCtrl.text.trim();
      if (employeeNo.isNotEmpty &&
          !RegExp(r'^\d{4}-\d{3}$').hasMatch(employeeNo)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee ID must be ####-###.')),
        );
        return;
      }
      if (employeeNo.isNotEmpty) {
        final available = await _isDetailEmployeeNoAvailable(employeeNo);
        if (!available) {
          if (!mounted) return;
          setState(() {
            _detailEmployeeNoAvailabilityError = 'Employee ID already exists';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Employee ID already exists.')),
          );
          return;
        }
      }
    }

    final accountStatus = _normalizeAccountStatus(_detailAccountStatus);
    final verificationStatus = _isStudentRole(role)
        ? _normalizeStudentVerification(_detailStudentVerificationStatus)
        : null;
    final legacyStatus = _legacyStatusValue(
      role: role,
      accountStatus: accountStatus,
      studentVerificationStatus: verificationStatus,
    );

    final update = <String, dynamic>{
      'firstName': firstName,
      'middleName': middleName.isEmpty ? null : middleName,
      'lastName': lastName,
      'displayName': '$firstName $lastName'.trim(),
      'accountStatus': accountStatus,
      'status': legacyStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (_isStudentRole(role)) {
      update['studentVerificationStatus'] = verificationStatus;
      update['studentProfile'] = {
        'studentNo': _detailStudentNoCtrl.text.trim().isEmpty
            ? null
            : _detailStudentNoCtrl.text.trim(),
        'collegeId': _detailCollegeCtrl.text.trim().isEmpty
            ? null
            : _detailCollegeCtrl.text.trim(),
        'programId': _detailProgramCtrl.text.trim().isEmpty
            ? null
            : _detailProgramCtrl.text.trim(),
        'yearLevel': int.tryParse(_detailYearLevelCtrl.text.trim()),
      };
    } else {
      update['studentVerificationStatus'] = FieldValue.delete();
      update['employeeProfile'] = {
        'employeeNo': _detailEmployeeNoCtrl.text.trim().isEmpty
            ? null
            : _detailEmployeeNoCtrl.text.trim(),
        'department': _roleNeedsDepartmentFor(role)
            ? (_detailDepartmentCtrl.text.trim().isEmpty
                  ? null
                  : _detailDepartmentCtrl.text.trim())
            : null,
      };
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(update);
      if (!mounted) return;
      setState(() => _detailEditing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User profile updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  InputDecoration _detailDecor(
    String label, {
    bool enabled = true,
    IconData? icon,
    String? helperText,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      errorText: errorText,
      labelStyle: const TextStyle(
        color: hintColor,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: primaryColor.withOpacity(0.82), size: 20),
      filled: true,
      fillColor: enabled ? Colors.white : const Color(0xFFF1F4F1),
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

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  DateTime? _docSortDate(Map<String, dynamic> data) {
    return _asDate(data['updatedAt']) ?? _asDate(data['createdAt']);
  }

  void _onSearchInputChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final next = value.trim().toLowerCase();
      if (_searchQuery == next) return;
      setState(() => _searchQuery = next);
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredUsersMemoized({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> rawDocs,
    required String type,
    required String query,
    required String adminRole,
    required String adminDept,
  }) {
    final cacheHit =
        identical(_filterCacheSourceDocs, rawDocs) &&
        _filterCacheType == type &&
        _filterCacheQuery == query &&
        _filterCachePendingFilter == _pendingStudentFilter &&
        _filterCacheAdminRole == adminRole &&
        _filterCacheAdminDept == adminDept;
    if (cacheHit) {
      return _filterCacheResult;
    }

    final filtered =
        rawDocs.where((doc) {
          final data = doc.data();
          final role = (data['role'] ?? '').toString().trim().toLowerCase();
          final accountStatus = _readAccountStatus(data, role: role);
          final studentVerification = _readStudentVerification(
            data,
            role: role,
          );
          final userDept = (data['employeeProfile']?['department'] ?? '')
              .toString();
          final studentCollege = (data['studentProfile']?['collegeId'] ?? '')
              .toString();

          if (adminRole == 'department_admin' || adminRole == 'dean') {
            if (role == 'student') {
              if (studentCollege != adminDept && userDept != adminDept) {
                return false;
              }
            } else {
              if (userDept != adminDept) return false;
            }
          }

          if (type == 'staff' && role == 'student') return false;
          if (type == 'active_staff' && role == 'student') return false;
          if (type == 'inactive_staff' && role == 'student') return false;
          if (type == 'active_staff' && accountStatus != 'active') return false;
          if (type == 'inactive_staff' && accountStatus != 'inactive')
            return false;
          if ((type == 'students' || type == 'active_students') &&
              role != 'student') {
            return false;
          }
          if (type == 'active_students' &&
              !(accountStatus == 'active' &&
                  studentVerification == 'verified')) {
            return false;
          }
          if (type == 'pending' &&
              !(role == 'student' &&
                  accountStatus == 'active' &&
                  studentVerification == _pendingStudentFilter)) {
            return false;
          }

          return _matchesSearch(data, query);
        }).toList()..sort((a, b) {
          final ad = _docSortDate(a.data());
          final bd = _docSortDate(b.data());
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });

    _filterCacheSourceDocs = rawDocs;
    _filterCacheType = type;
    _filterCacheQuery = query;
    _filterCachePendingFilter = _pendingStudentFilter;
    _filterCacheAdminRole = adminRole;
    _filterCacheAdminDept = adminDept;
    _filterCacheResult = filtered;
    return filtered;
  }

  String _randomPassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789@#%';
    final r = Random.secure();
    return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
  }

  bool _matchesSearch(Map<String, dynamic> data, String q) {
    if (q.isEmpty) return true;
    final studentProfile =
        data['studentProfile'] as Map<String, dynamic>? ?? {};
    final employeeProfile =
        data['employeeProfile'] as Map<String, dynamic>? ?? {};

    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    final accountStatus = _readAccountStatus(data, role: role);
    final studentVerification = _readStudentVerification(data, role: role);

    final hay = [
      _displayName(data),
      (data['email'] ?? '').toString(),
      (data['role'] ?? '').toString(),
      accountStatus,
      studentVerification,
      (data['status'] ?? '').toString(),
      (studentProfile['studentNo'] ?? data['studentNo'] ?? '').toString(),
      (employeeProfile['employeeNo'] ?? data['employeeNo'] ?? '').toString(),
    ].join(' ').toLowerCase();
    return hay.contains(q.toLowerCase());
  }

  Future<void> _openCreateUser() async {
    final adminRole = (_currentUserData?['role'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final adminDept =
        (_currentUserData?['employeeProfile']?['department'] ?? '').toString();
    final studentsOnly = _isDepartmentAdminScope;

    final res = await showDialog<_CreateUserResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateUserDialog(
        initialPassword: _randomPassword(),
        forcedDepartment:
            (adminRole == 'department_admin' || adminRole == 'dean')
            ? adminDept
            : null,
        studentsOnly: studentsOnly,
      ),
    );
    if (res == null || !mounted) return;

    try {
      setState(() => _submitting = true);
      await _createAuthAndUserDoc(res);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Created user: ${res.email}')));
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.contains('email-already-in-use')) {
        msg = 'This email is already registered.';
      }
      if (msg.contains('weak-password')) msg = 'The password is too weak.';
      if (msg.contains('duplicate-student-no')) {
        msg = 'Student Number already exists.';
      }
      if (msg.contains('duplicate-employee-no')) {
        msg = 'Employee ID already exists.';
      }
      if (msg.contains('auth/network-request-failed')) {
        final host = Uri.base.host;
        msg =
            'Cannot reach Firebase Auth from "$host". Check internet, disable VPN/ad-block, and add "$host" in Firebase Auth Authorized domains.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Create user failed: $msg'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _createAuthAndUserDoc(_CreateUserResult input) async {
    Future<bool> existsByField(String field, String value) async {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .where(field, isEqualTo: value)
          .limit(1)
          .get();
      return q.docs.isNotEmpty;
    }

    // Enforce unique IDs before creating auth user.
    if (input.role == 'student') {
      final studentNo = input.studentNo.trim();
      final duplicate =
          await existsByField('studentProfile.studentNo', studentNo) ||
          await existsByField('studentNo', studentNo);
      if (duplicate) throw Exception('duplicate-student-no');
    } else {
      final employeeNo = input.employeeNo.trim();
      final duplicate =
          await existsByField('employeeProfile.employeeNo', employeeNo) ||
          await existsByField('employeeNo', employeeNo);
      if (duplicate) throw Exception('duplicate-employee-no');
    }

    final primary = Firebase.app();
    final appName =
        'admin_create_user_${DateTime.now().microsecondsSinceEpoch}';
    final secondary = await Firebase.initializeApp(
      name: appName,
      options: primary.options,
    );

    final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
    UserCredential cred;

    try {
      cred = await _createUserWithRetry(
        auth: secondaryAuth,
        email: input.email,
        password: input.password,
      );
    } catch (e) {
      await secondaryAuth.signOut();
      await secondary.delete();
      rethrow;
    }

    final createdUser = cred.user;
    if (createdUser == null) {
      await secondaryAuth.signOut();
      await secondary.delete();
      throw StateError('Failed to create auth user');
    }

    try {
      // Use the same formatting logic as CompleteProfilePage
      String toTitleCase(String s) {
        if (s.isEmpty) return s;
        return s
            .split(' ')
            .map((p) {
              if (p.isEmpty) return p;
              return p[0].toUpperCase() + p.substring(1).toLowerCase();
            })
            .join(' ');
      }

      final firstName = toTitleCase(input.firstName);
      final lastName = toTitleCase(input.lastName);
      final displayName = '$firstName $lastName'.trim();

      final isStudent = _isStudentRole(input.role);
      final normalizedAccountStatus = _normalizeAccountStatus(
        isStudent ? 'active' : input.accountStatus,
      );
      final normalizedStudentVerification = isStudent
          ? 'pending_email_verification'
          : null;
      final legacyStatus = _legacyStatusValue(
        role: input.role,
        accountStatus: normalizedAccountStatus,
        studentVerificationStatus: normalizedStudentVerification,
      );
      final createdByUid = FirebaseAuth.instance.currentUser?.uid;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(createdUser.uid)
          .set({
            'uid': createdUser.uid,
            'email': input.email,
            'firstName': firstName.isEmpty ? null : firstName,
            'lastName': lastName.isEmpty ? null : lastName,
            'displayName': displayName.isEmpty ? null : displayName,
            'role': input.role,
            'accountStatus': normalizedAccountStatus,
            if (isStudent)
              'studentVerificationStatus': normalizedStudentVerification,
            if (!isStudent) 'studentVerificationStatus': FieldValue.delete(),
            'status': legacyStatus,
            'createdByAdmin': true,
            if (createdByUid != null) 'createdByUid': createdByUid,

            // ✅ NEW: Initialize Profile Objects with more detail
            'studentProfile': {
              'studentNo': input.studentNo.isEmpty ? null : input.studentNo,
              'collegeId': input.collegeId,
              'programId': input.programId,
              'yearLevel': input.yearLevel,
            },
            'employeeProfile': {
              'employeeNo': input.employeeNo.isEmpty ? null : input.employeeNo,
              'department': input.department.isEmpty ? null : input.department,
            },

            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (input.sendPasswordReset) {
        if (input.userSetsOwnPassword) {
          await _sendSetPasswordLink(secondaryAuth, input.email);
        } else {
          await _sendVerifyEmailLinkWithPassword(
            createdUser,
            input.email,
            input.password,
          );
        }
      }
    } catch (e) {
      try {
        await createdUser.delete();
      } catch (_) {}
      rethrow;
    } finally {
      await secondaryAuth.signOut();
      await secondary.delete();
    }
  }

  Future<UserCredential> _createUserWithRetry({
    required FirebaseAuth auth,
    required String email,
    required String password,
  }) async {
    const maxAttempts = 4;
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        final isNetworkError = e.code == 'network-request-failed';
        if (!isNetworkError || attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 500 * attempt * attempt),
        );
      } catch (e) {
        final isNetworkError = e.toString().contains(
          'auth/network-request-failed',
        );
        if (!isNetworkError || attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 500 * attempt * attempt),
        );
      }
    }
  }

  Future<void> _sendSetPasswordLink(FirebaseAuth auth, String email) async {
    final continueUrl = _resolveSetPasswordContinueUrl();
    final verifyContinueUrl = _resolveVerifyContinueUrl();

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-east1',
      ).httpsCallable('createCustomSetPasswordLink');
      final res = await callable.call(<String, dynamic>{
        'email': email,
        'continueUrl': continueUrl,
        'verifyContinueUrl': verifyContinueUrl,
      });
      final data = (res.data as Map?) ?? const <String, dynamic>{};
      final customLink = (data['customLink'] ?? '').toString().trim();
      final mailQueued = data['mailQueued'] == true;

      if (customLink.isNotEmpty) {
        if (mounted) {
          await _showManualSetPasswordLinkDialog(
            email: email,
            link: customLink,
            emailQueued: mailQueued,
          );
        }
        return;
      }
    } catch (_) {}

    if (kIsWeb) {
      final settings = ActionCodeSettings(
        url: continueUrl,
        handleCodeInApp: true,
      );
      try {
        await auth.sendPasswordResetEmail(
          email: email,
          actionCodeSettings: settings,
        );
        return;
      } catch (_) {}
    }
    await auth.sendPasswordResetEmail(email: email);
  }

  Future<void> _sendVerifyEmailLinkWithPassword(
    User user,
    String email,
    String temporaryPassword,
  ) async {
    final continueUrl = _resolveLoginContinueUrl(email);
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-east1',
      ).httpsCallable('createCustomVerifyEmailLink');
      final res = await callable.call(<String, dynamic>{
        'email': email,
        'continueUrl': continueUrl,
        'temporaryPassword': temporaryPassword,
      });
      final data = (res.data as Map?) ?? const <String, dynamic>{};
      final verifyLink = (data['verifyLink'] ?? '').toString().trim();
      final mailQueued = data['mailQueued'] == true;
      if (verifyLink.isNotEmpty) {
        if (mounted) {
          await _showManualSetPasswordLinkDialog(
            email: email,
            link: verifyLink,
            emailQueued: mailQueued,
          );
        }
        return;
      }
    } catch (_) {
      try {
        if (kIsWeb) {
          final settings = ActionCodeSettings(
            url: continueUrl,
            handleCodeInApp: true,
          );
          await user.sendEmailVerification(settings);
        } else {
          await user.sendEmailVerification();
        }
      } catch (_) {}
    }
  }

  String _resolveSetPasswordContinueUrl() {
    const configuredContinueUrl = String.fromEnvironment(
      'PASSWORD_RESET_CONTINUE_URL',
    );
    if (kIsWeb) {
      return '${Uri.base.origin}/#/set-password';
    }
    return configuredContinueUrl.isNotEmpty
        ? configuredContinueUrl
        : '${Uri.base.origin}/#/set-password';
  }

  String _resolveLoginContinueUrl(String email) {
    if (kIsWeb) {
      return '${Uri.base.origin}/#/login?prefillEmail=${Uri.encodeComponent(email)}';
    }
    const configuredContinueUrl = String.fromEnvironment(
      'PASSWORD_VERIFY_CONTINUE_URL',
    );
    if (configuredContinueUrl.isNotEmpty) {
      return configuredContinueUrl;
    }
    return _resolveSetPasswordContinueUrl();
  }

  String _resolveVerifyContinueUrl() {
    const configuredContinueUrl = String.fromEnvironment(
      'PASSWORD_VERIFY_CONTINUE_URL',
    );
    if (kIsWeb) {
      return _resolveSetPasswordContinueUrl();
    }
    if (configuredContinueUrl.isNotEmpty) {
      return configuredContinueUrl;
    }
    return _resolveSetPasswordContinueUrl();
  }

  Future<void> _showManualSetPasswordLinkDialog({
    required String email,
    required String link,
    bool emailQueued = false,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Account Setup Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              emailQueued
                  ? 'Setup email was queued for $email. If it does not arrive, copy this link and send it manually.'
                  : 'Email sender is not configured. Copy and send this link to: $email',
            ),
            const SizedBox(height: 12),
            SelectableText(link, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied to clipboard.')),
                );
              }
            },
            child: const Text('Copy Link'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateUserStatus(
    String uid,
    String status, {
    String? role,
  }) async {
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await ref.get();
      if (!snap.exists) throw StateError('User not found');

      final data = snap.data() ?? <String, dynamic>{};
      final roleKey = (role ?? data['role'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final isStudent = _isStudentRole(roleKey);

      var nextAccountStatus = _readAccountStatus(data, role: roleKey);
      var nextStudentVerification = _readStudentVerification(
        data,
        role: roleKey,
      );
      final action = status.trim().toLowerCase();

      if (action == 'active' || action == 'inactive') {
        nextAccountStatus = _normalizeAccountStatus(action);
      } else if (isStudent &&
          (action == 'pending_profile' ||
              action == 'pending_email_verification' ||
              action == 'pending_approval' ||
              action == 'verified')) {
        nextStudentVerification = _normalizeStudentVerification(action);
      } else if (!isStudent && action == 'verified') {
        nextAccountStatus = 'active';
      }

      final legacyStatus = _legacyStatusValue(
        role: roleKey,
        accountStatus: nextAccountStatus,
        studentVerificationStatus: nextStudentVerification,
      );

      await ref.update({
        'accountStatus': nextAccountStatus,
        if (isStudent) 'studentVerificationStatus': nextStudentVerification,
        if (!isStudent) 'studentVerificationStatus': FieldValue.delete(),
        'status': legacyStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User status updated to $legacyStatus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final showStudentsOnly = _isDepartmentAdminScope;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: ModernTableLayout(
        header: ModernTableHeader(
          title: widget.headerTitle ?? 'User Management',
          subtitle:
              widget.headerSubtitle ??
              (showStudentsOnly
                  ? 'Manage students under your department'
                  : 'Control access and verify accounts'),
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_submitting)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _submitting ? null : _openCreateUser,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: const Text(
                  'Create New User',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ],
          ),
          searchBar: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by name, ID, or email...',
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: primaryColor,
              ),
              filled: true,
              fillColor: backgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              hintStyle: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: _onSearchInputChanged,
          ),
          tabs: showStudentsOnly
              ? TabBar(
                  controller: _tabController,
                  onTap: (index) {
                    if (_selectedUserId != null || _detailEditing) {
                      _clearDetailSelection();
                    } else {
                      if (_tabController.index != index) {
                        setState(() {});
                      }
                    }
                  },
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: primaryColor,
                  unselectedLabelColor: hintColor.withOpacity(0.6),
                  indicatorColor: primaryColor,
                  indicatorWeight: 4,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  tabs: const [
                    Tab(text: 'All'),
                    Tab(text: 'Active'),
                    Tab(text: 'Pending'),
                  ],
                )
              : TabBar(
                  controller: _tabController,
                  onTap: (index) {
                    if (_selectedUserId != null || _detailEditing) {
                      _clearDetailSelection();
                    } else {
                      if (_tabController.index != index) {
                        setState(() {});
                      }
                    }
                  },
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: primaryColor,
                  unselectedLabelColor: hintColor.withOpacity(0.6),
                  indicatorColor: primaryColor,
                  indicatorWeight: 4,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  tabs: const [
                    Tab(text: 'Staff & Admins'),
                    Tab(text: 'Active'),
                    Tab(text: 'Inactive'),
                  ],
                ),
        ),
        body: showStudentsOnly && _tabController.index == 2
            ? Column(
                children: [
                  _buildPendingStudentFilterBar(),
                  Expanded(child: _buildUserList(_studentsOnlyListType())),
                ],
              )
            : _buildUserList(
                showStudentsOnly
                    ? _studentsOnlyListType()
                    : _activeUserListType(),
              ),
      ),
    );
  }

  Widget _buildUserList(String type) {
    if (_loadingAdminData) {
      return const Center(child: CircularProgressIndicator());
    }

    final stream = widget.studentsOnlyScope
        ? _studentUsersStream
        : _allUsersStream;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final q = _searchQuery;
        final allDocs = snap.data!.docs;

        final adminRole = (_currentUserData?['role'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final adminDept =
            (_currentUserData?['employeeProfile']?['department'] ?? '')
                .toString();

        final filtered = _filteredUsersMemoized(
          rawDocs: allDocs,
          type: type,
          query: q,
          adminRole: adminRole,
          adminDept: adminDept,
        );

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_search_rounded,
                  size: 64,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'No users found',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 900;

            if (isDesktop) {
              return _buildDesktopTable(filtered, type: type);
            }

            return ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final doc = filtered[i];
                final data = doc.data();
                return _buildUserCard(doc.id, data);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDesktopTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String type,
  }) {
    final statusHeaderText = (type == 'students' || type == 'pending')
        ? 'VERIFICATION STATUS'
        : 'STATUS';

    QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
    if (_selectedUserId != null) {
      for (final doc in docs) {
        if (doc.id == _selectedUserId) {
          selectedDoc = doc;
          break;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStateProperty.all(backgroundColor),
                    columnSpacing: 24,
                    columns: [
                      DataColumn(
                        label: Text(
                          'NAME',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'EMAIL',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'ID NUMBER',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'ROLE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          statusHeaderText,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'ACTIONS',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                    rows: docs.map((doc) {
                      final data = doc.data();
                      final name = _displayName(data);
                      final email = (data['email'] ?? '--').toString();
                      final id = _displayId(data);
                      final role = (data['role'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase();
                      final accountStatus = _readAccountStatus(
                        data,
                        role: role,
                      );
                      final studentVerification = _readStudentVerification(
                        data,
                        role: role,
                      );

                      return DataRow(
                        selected: _selectedUserId == doc.id,
                        color: WidgetStateProperty.resolveWith<Color?>((_) {
                          if (_selectedUserId == doc.id) {
                            return primaryColor.withValues(alpha: 0.08);
                          }
                          return null;
                        }),
                        onSelectChanged: (selected) {
                          if (selected == null) return;
                          if (selected) {
                            _loadDetailFromData(doc.id, data);
                            return;
                          }
                          if (!_detailEditing) {
                            _clearDetailSelection();
                          }
                        },
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: primaryColor.withOpacity(
                                    0.1,
                                  ),
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: textDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              email,
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              id,
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              _formatRole(role),
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(
                            _buildStatusCell(
                              role: role,
                              accountStatus: accountStatus,
                              studentVerificationStatus: studentVerification,
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (role == 'student' &&
                                    accountStatus == 'active' &&
                                    studentVerification == 'pending_approval')
                                  IconButton(
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.green,
                                    ),
                                    onPressed: () => _updateUserStatus(
                                      doc.id,
                                      'verified',
                                      role: role,
                                    ),
                                    tooltip: 'Approve User',
                                  ),
                                PopupMenuButton<String>(
                                  icon: const Icon(
                                    Icons.more_vert,
                                    size: 20,
                                    color: hintColor,
                                  ),
                                  onSelected: (val) {
                                    if (val == 'verify') {
                                      _updateUserStatus(
                                        doc.id,
                                        'verified',
                                        role: role,
                                      );
                                    }
                                    if (val == 'deactivate') {
                                      _updateUserStatus(
                                        doc.id,
                                        'inactive',
                                        role: role,
                                      );
                                    }
                                    if (val == 'activate') {
                                      _updateUserStatus(
                                        doc.id,
                                        'active',
                                        role: role,
                                      );
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    if (accountStatus != 'active')
                                      const PopupMenuItem(
                                        value: 'activate',
                                        child: Text('Activate Account'),
                                      ),
                                    if (accountStatus != 'inactive')
                                      const PopupMenuItem(
                                        value: 'deactivate',
                                        child: Text('Deactivate Account'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'reset',
                                      child: Text('Send Password Reset'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          if (selectedDoc != null) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 430,
              child: _buildDesktopDetailsPanel(selectedDoc: selectedDoc),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktopDetailsPanel({
    required QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc,
  }) {
    if (selectedDoc == null) {
      return const SizedBox.shrink();
    }

    final data = selectedDoc.data();
    final displayName = _displayName(data);
    final isStudent = _isStudentRole(_detailRole);

    Widget sectionCard(String title, List<Widget> children) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBF8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
    }

    Widget editableField(
      TextEditingController controller,
      String label, {
      IconData? icon,
      bool enabled = true,
      TextInputType? keyboardType,
      List<TextInputFormatter>? inputFormatters,
      ValueChanged<String>? onChanged,
      String? helperText,
      String? errorText,
    }) {
      return TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        style: const TextStyle(
          color: textDark,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        decoration: _detailDecor(
          label,
          enabled: enabled,
          icon: icon,
          helperText: helperText,
          errorText: errorText,
        ),
      );
    }

    Widget readOnlyField(String label, String value, {IconData? icon}) {
      return InputDecorator(
        decoration: _detailDecor(label, enabled: false, icon: icon),
        child: Text(
          value.trim().isEmpty ? '--' : value.trim(),
          style: const TextStyle(
            color: textDark,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Profile Details',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                if (_detailEditing)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: primaryColor.withOpacity(0.2)),
                    ),
                    child: const Text(
                      'EDITING',
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Clear selection',
                  onPressed: _clearDetailSelection,
                  icon: const Icon(Icons.close_rounded, color: hintColor),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              displayName,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _detailEmailCtrl.text.trim().isEmpty
                  ? '--'
                  : _detailEmailCtrl.text,
              style: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(_detailAccountStatus),
                if (isStudent)
                  _buildVerificationChip(_detailStudentVerificationStatus),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            if (!_detailEditing)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _detailEditing = true;
                      _detailStudentNoAvailabilityError = null;
                      _detailEmployeeNoAvailabilityError = null;
                    });
                    _scheduleDetailStudentNoAvailabilityCheck(
                      _detailStudentNoCtrl.text,
                    );
                    _scheduleDetailEmployeeNoAvailabilityCheck(
                      _detailEmployeeNoCtrl.text,
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text(
                    'Edit Profile',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          _loadDetailFromData(selectedDoc.id, data),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: hintColor,
                        side: BorderSide(
                          color: hintColor.withOpacity(0.6),
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Discard',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _detailSaveLocked
                          ? null
                          : _saveSelectedUserDetails,
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save Changes',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionCard('BASIC INFO', [
                      editableField(
                        _detailFirstNameCtrl,
                        'First Name',
                        icon: Icons.person_outline_rounded,
                        enabled: _detailEditing,
                      ),
                      const SizedBox(height: 10),
                      editableField(
                        _detailMiddleNameCtrl,
                        'Middle Name',
                        icon: Icons.badge_outlined,
                        enabled: _detailEditing,
                      ),
                      const SizedBox(height: 10),
                      editableField(
                        _detailLastNameCtrl,
                        'Last Name',
                        icon: Icons.person_outline_rounded,
                        enabled: _detailEditing,
                      ),
                      const SizedBox(height: 10),
                      readOnlyField(
                        'Email',
                        _detailEmailCtrl.text,
                        icon: Icons.email_outlined,
                      ),
                      const SizedBox(height: 10),
                      readOnlyField(
                        'Role',
                        _formatRole(_detailRole),
                        icon: Icons.admin_panel_settings_outlined,
                      ),
                    ]),
                    sectionCard('ACCESS', [
                      DropdownButtonFormField<String>(
                        initialValue: _detailAccountStatus,
                        decoration: _detailDecor(
                          'Account Status',
                          enabled: _detailEditing,
                          icon: Icons.security_outlined,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text('Inactive'),
                          ),
                        ],
                        onChanged: _detailEditing
                            ? (v) => setState(
                                () => _detailAccountStatus =
                                    _normalizeAccountStatus(v ?? 'active'),
                              )
                            : null,
                      ),
                      if (isStudent) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _detailStudentVerificationStatus,
                          decoration: _detailDecor(
                            'Verification Status',
                            enabled: _detailEditing,
                            icon: Icons.verified_user_outlined,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'pending_email_verification',
                              child: Text('Pending Email Verification'),
                            ),
                            DropdownMenuItem(
                              value: 'pending_profile',
                              child: Text('Pending Profile'),
                            ),
                            DropdownMenuItem(
                              value: 'pending_approval',
                              child: Text('Pending Approval'),
                            ),
                            DropdownMenuItem(
                              value: 'verified',
                              child: Text('Verified'),
                            ),
                          ],
                          onChanged: _detailEditing
                              ? (v) => setState(
                                  () => _detailStudentVerificationStatus =
                                      _normalizeStudentVerification(
                                        v ?? 'verified',
                                      ),
                                )
                              : null,
                        ),
                      ],
                    ]),
                    sectionCard(
                      isStudent ? 'STUDENT PROFILE' : 'STAFF PROFILE',
                      [
                        if (isStudent) ...[
                          editableField(
                            _detailStudentNoCtrl,
                            'Student Number',
                            icon: Icons.badge_outlined,
                            enabled: _detailEditing,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [
                              _HyphenatedDigitsFormatter(
                                firstGroup: 3,
                                secondGroup: 4,
                              ),
                            ],
                            onChanged:
                                _scheduleDetailStudentNoAvailabilityCheck,
                            helperText: _detailStudentNoChecking
                                ? 'Checking Student Number availability...'
                                : null,
                            errorText: _detailStudentNoAvailabilityError,
                          ),
                          const SizedBox(height: 10),
                          editableField(
                            _detailCollegeCtrl,
                            'College Code',
                            icon: Icons.account_balance_outlined,
                            enabled: _detailEditing,
                          ),
                          const SizedBox(height: 10),
                          editableField(
                            _detailProgramCtrl,
                            'Program Code',
                            icon: Icons.school_outlined,
                            enabled: _detailEditing,
                          ),
                          const SizedBox(height: 10),
                          editableField(
                            _detailYearLevelCtrl,
                            'Year Level',
                            icon: Icons.layers_outlined,
                            enabled: _detailEditing,
                            keyboardType: TextInputType.number,
                          ),
                        ] else ...[
                          editableField(
                            _detailEmployeeNoCtrl,
                            'Employee ID',
                            icon: Icons.badge_outlined,
                            enabled: _detailEditing,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [
                              _HyphenatedDigitsFormatter(
                                firstGroup: 4,
                                secondGroup: 3,
                              ),
                            ],
                            onChanged:
                                _scheduleDetailEmployeeNoAvailabilityCheck,
                            helperText: _detailEmployeeNoChecking
                                ? 'Checking Employee ID availability...'
                                : null,
                            errorText: _detailEmployeeNoAvailabilityError,
                          ),
                          if (_roleNeedsDepartmentFor(_detailRole)) ...[
                            const SizedBox(height: 10),
                            editableField(
                              _detailDepartmentCtrl,
                              'Department (College Code)',
                              icon: Icons.business_outlined,
                              enabled: _detailEditing,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color = Colors.grey;
    switch (status) {
      case 'active':
        color = Colors.green;
        break;
      case 'inactive':
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildVerificationChip(String status) {
    Color color = Colors.grey;
    switch (status) {
      case 'verified':
        color = Colors.green;
        break;
      case 'pending_email_verification':
      case 'pending_approval':
      case 'pending_verification':
      case 'pending_profile':
        color = Colors.orange;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildStatusCell({
    required String role,
    required String accountStatus,
    required String studentVerificationStatus,
  }) {
    if (!_isStudentRole(role)) return _buildStatusChip(accountStatus);
    if (accountStatus == 'active') {
      return _buildVerificationChip(studentVerificationStatus);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusChip(accountStatus),
        const SizedBox(height: 6),
        _buildVerificationChip(studentVerificationStatus),
      ],
    );
  }

  Widget _buildUserCard(String uid, Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    final accountStatus = _readAccountStatus(data, role: role);
    final studentVerification = _readStudentVerification(data, role: role);
    final isStudent = _isStudentRole(role);
    final name = _displayName(data);
    final id = _displayId(data);
    final email = (data['email'] ?? '').toString();

    final badgeStatus = isStudent && accountStatus == 'active'
        ? studentVerification
        : accountStatus;
    Color statusColor;
    IconData statusIcon;
    switch (badgeStatus) {
      case 'verified':
      case 'active':
        statusColor = Colors.green;
        statusIcon = Icons.verified_user_rounded;
        break;
      case 'pending_email_verification':
      case 'pending_approval':
      case 'pending_verification':
      case 'pending_profile':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top_rounded;
        break;
      case 'inactive':
        statusColor = Colors.red;
        statusIcon = Icons.block_flipped;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: primaryColor.withOpacity(0.12),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: textDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: statusColor.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 12, color: statusColor),
                            const SizedBox(width: 5),
                            Text(
                              badgeStatus.replaceAll('_', ' ').toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    email,
                    style: const TextStyle(
                      color: hintColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.badge_outlined,
                        size: 16,
                        color: primaryColor.withOpacity(0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'ID: $id',
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.work_outline_rounded,
                        size: 16,
                        color: primaryColor.withOpacity(0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatRole(role),
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  if (isStudent && accountStatus != 'active') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.fact_check_outlined,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Verification: ${studentVerification.replaceAll('_', ' ').toUpperCase()}',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (isStudent &&
                accountStatus == 'active' &&
                studentVerification == 'pending_approval')
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: () =>
                      _updateUserStatus(uid, 'verified', role: role),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: const Text(
                    'Approve',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              onSelected: (val) {
                if (val == 'verify') {
                  _updateUserStatus(uid, 'verified', role: role);
                }
                if (val == 'deactivate') {
                  _updateUserStatus(uid, 'inactive', role: role);
                }
                if (val == 'activate') {
                  _updateUserStatus(uid, 'active', role: role);
                }
              },
              itemBuilder: (context) => [
                if (accountStatus != 'active')
                  const PopupMenuItem(
                    value: 'activate',
                    child: Text('Activate Account'),
                  ),
                if (accountStatus != 'inactive')
                  const PopupMenuItem(
                    value: 'deactivate',
                    child: Text('Deactivate Account'),
                  ),
                const PopupMenuItem(
                  value: 'reset',
                  child: Text('Send Password Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UserRow {
  final String name;
  final String email;
  final String role;
  final String status;

  const _UserRow({
    required this.name,
    required this.email,
    required this.role,
    required this.status,
  });

  factory _UserRow.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final dn = (d['displayName'] ?? '').toString().trim();
    final first = (d['firstName'] ?? '').toString().trim();
    final last = (d['lastName'] ?? '').toString().trim();
    final full = ('$first $last').trim();
    final name = dn.isNotEmpty ? dn : (full.isNotEmpty ? full : '--');
    final email = (d['email'] ?? '').toString().trim();
    final role = (d['role'] ?? '').toString().trim();
    final status = (d['status'] ?? '').toString().trim();

    return _UserRow(
      name: name,
      email: email.isEmpty ? '--' : email,
      role: role.isEmpty ? '--' : role,
      status: status.isEmpty ? '--' : status,
    );
  }
}

class _CreateUserResult {
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String role;
  final String accountStatus;
  final String studentVerificationStatus;
  final bool sendPasswordReset;
  final bool userSetsOwnPassword;
  final String studentNo;
  final String employeeNo;
  final String department;

  final String? collegeId;
  final String? programId;
  final int? yearLevel;

  const _CreateUserResult({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.accountStatus,
    this.studentVerificationStatus = 'verified',
    required this.sendPasswordReset,
    this.userSetsOwnPassword = true,
    this.studentNo = '',
    this.employeeNo = '',
    this.department = '',
    this.collegeId,
    this.programId,
    this.yearLevel,
  });
}

class _CreateUserDialog extends StatefulWidget {
  final String initialPassword;
  final String? forcedDepartment;
  final bool studentsOnly;

  const _CreateUserDialog({
    required this.initialPassword,
    this.forcedDepartment,
    this.studentsOnly = false,
  });

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();

  // New role-specific controllers
  final _studentNoCtrl = TextEditingController();
  final _employeeNoCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();

  String _role = 'professor';
  String _accountStatus = 'active';
  String _studentVerificationStatus = 'pending_email_verification';
  bool _userSetsOwnPassword = true;
  bool _sendReset = true;
  final bool _submitting = false;
  Timer? _emailDebounce;
  bool _emailChecking = false;
  String? _emailAvailabilityError;
  String _lastEmailChecked = '';
  Timer? _studentNoDebounce;
  bool _studentNoChecking = false;
  String? _studentNoAvailabilityError;
  String _lastStudentNoChecked = '';
  Timer? _employeeNoDebounce;
  bool _employeeNoChecking = false;
  String? _employeeNoAvailabilityError;
  String _lastEmployeeNoChecked = '';

  // Additional student details
  String? _selectedCollege;
  String? _selectedProgram;
  int? _selectedYear;

  List<QueryDocumentSnapshot> _colleges = [];
  List<QueryDocumentSnapshot> _programs = [];

  bool get _roleNeedsDepartment =>
      _role != 'student' &&
      _role != 'osa_admin' &&
      _role != 'counseling_admin' &&
      _role != 'super_admin';

  List<DropdownMenuItem<String>> _accountStatusItems() {
    return const [
      DropdownMenuItem(value: 'active', child: Text('Active')),
      DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
    ];
  }

  List<DropdownMenuItem<String>> _studentVerificationItems() {
    return const [
      DropdownMenuItem(
        value: 'pending_email_verification',
        child: Text('Pending Email Verification'),
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _passwordCtrl.text = widget.initialPassword;
    if (widget.studentsOnly) {
      _role = 'student';
      _studentVerificationStatus = 'pending_email_verification';
    } else {
      _role = 'professor';
      _studentVerificationStatus = 'verified';
    }
    if (widget.forcedDepartment != null) {
      _deptCtrl.text = widget.forcedDepartment!;
    }
    _emailCtrl.addListener(_onAnyFieldChanged);
    _firstCtrl.addListener(_onAnyFieldChanged);
    _lastCtrl.addListener(_onAnyFieldChanged);
    _passwordCtrl.addListener(_onAnyFieldChanged);
    _studentNoCtrl.addListener(_onAnyFieldChanged);
    _employeeNoCtrl.addListener(_onAnyFieldChanged);
    _deptCtrl.addListener(_onAnyFieldChanged);
    _loadColleges();
  }

  Future<void> _loadColleges() async {
    final snap = await FirebaseFirestore.instance
        .collection('colleges')
        .where('active', isEqualTo: true)
        .get();
    if (!mounted) return;
    setState(() => _colleges = snap.docs);

    if (widget.forcedDepartment != null) {
      final found = _colleges.any((doc) => doc.id == widget.forcedDepartment);
      if (found) {
        setState(() {
          _selectedCollege = widget.forcedDepartment;
        });
        _loadPrograms(widget.forcedDepartment!);
      }
    }
  }

  Future<void> _loadPrograms(String collegeId) async {
    final snap = await FirebaseFirestore.instance
        .collection('programs')
        .where('collegeId', isEqualTo: collegeId)
        .where('active', isEqualTo: true)
        .get();
    if (!mounted) return;
    setState(() => _programs = snap.docs);
  }

  @override
  void dispose() {
    _emailDebounce?.cancel();
    _studentNoDebounce?.cancel();
    _employeeNoDebounce?.cancel();
    _emailCtrl.removeListener(_onAnyFieldChanged);
    _firstCtrl.removeListener(_onAnyFieldChanged);
    _lastCtrl.removeListener(_onAnyFieldChanged);
    _passwordCtrl.removeListener(_onAnyFieldChanged);
    _studentNoCtrl.removeListener(_onAnyFieldChanged);
    _employeeNoCtrl.removeListener(_onAnyFieldChanged);
    _deptCtrl.removeListener(_onAnyFieldChanged);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _studentNoCtrl.dispose();
    _employeeNoCtrl.dispose();
    _deptCtrl.dispose();
    super.dispose();
  }

  void _onAnyFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool _isValidEmailFormat(String email) {
    final value = email.trim().toLowerCase();
    if (value.isEmpty) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  Future<bool> _isEmailAvailable(String email) async {
    final value = email.trim().toLowerCase();
    final q = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: value)
        .limit(1)
        .get();
    return q.docs.isEmpty;
  }

  void _scheduleEmailAvailabilityCheck(String raw) {
    _emailDebounce?.cancel();
    final email = raw.trim().toLowerCase();

    if (email.isEmpty || !_isValidEmailFormat(email)) {
      setState(() {
        _emailChecking = false;
        _emailAvailabilityError = null;
      });
      return;
    }

    if (_lastEmailChecked == email && _emailAvailabilityError == null) {
      return;
    }

    setState(() {
      _emailChecking = true;
      _emailAvailabilityError = null;
    });

    _emailDebounce = Timer(const Duration(milliseconds: 450), () async {
      bool available = false;
      try {
        available = await _isEmailAvailable(email);
      } catch (_) {
        available = true;
      }
      if (!mounted) return;
      if (_emailCtrl.text.trim().toLowerCase() != email) return;
      setState(() {
        _emailChecking = false;
        _lastEmailChecked = email;
        _emailAvailabilityError = available ? null : 'Email already exists';
      });
    });
  }

  Future<bool> _isStudentNoAvailable(String studentNo) async {
    final q1 = await FirebaseFirestore.instance
        .collection('users')
        .where('studentProfile.studentNo', isEqualTo: studentNo)
        .limit(1)
        .get();
    if (q1.docs.isNotEmpty) return false;

    final q2 = await FirebaseFirestore.instance
        .collection('users')
        .where('studentNo', isEqualTo: studentNo)
        .limit(1)
        .get();
    return q2.docs.isEmpty;
  }

  Future<bool> _isEmployeeNoAvailable(String employeeNo) async {
    final q1 = await FirebaseFirestore.instance
        .collection('users')
        .where('employeeProfile.employeeNo', isEqualTo: employeeNo)
        .limit(1)
        .get();
    if (q1.docs.isNotEmpty) return false;

    final q2 = await FirebaseFirestore.instance
        .collection('users')
        .where('employeeNo', isEqualTo: employeeNo)
        .limit(1)
        .get();
    return q2.docs.isEmpty;
  }

  void _scheduleStudentNoAvailabilityCheck(String raw) {
    _studentNoDebounce?.cancel();
    final studentNo = raw.trim();
    const pattern = r'^\d{3}-\d{4}$';

    if (_role != 'student') {
      if (_studentNoChecking || _studentNoAvailabilityError != null) {
        setState(() {
          _studentNoChecking = false;
          _studentNoAvailabilityError = null;
        });
      }
      return;
    }

    if (studentNo.isEmpty || !RegExp(pattern).hasMatch(studentNo)) {
      setState(() {
        _studentNoChecking = false;
        _studentNoAvailabilityError = null;
      });
      return;
    }

    if (_lastStudentNoChecked == studentNo &&
        _studentNoAvailabilityError == null) {
      return;
    }

    setState(() {
      _studentNoChecking = true;
      _studentNoAvailabilityError = null;
    });

    _studentNoDebounce = Timer(const Duration(milliseconds: 450), () async {
      bool available = false;
      try {
        available = await _isStudentNoAvailable(studentNo);
      } catch (_) {
        available = true;
      }
      if (!mounted) return;
      if (_role != 'student') return;
      if (_studentNoCtrl.text.trim() != studentNo) return;
      setState(() {
        _studentNoChecking = false;
        _lastStudentNoChecked = studentNo;
        _studentNoAvailabilityError = available
            ? null
            : 'Student Number already exists';
      });
    });
  }

  void _scheduleEmployeeNoAvailabilityCheck(String raw) {
    _employeeNoDebounce?.cancel();
    final employeeNo = raw.trim();
    const pattern = r'^\d{4}-\d{3}$';

    if (_role == 'student') {
      if (_employeeNoChecking || _employeeNoAvailabilityError != null) {
        setState(() {
          _employeeNoChecking = false;
          _employeeNoAvailabilityError = null;
        });
      }
      return;
    }

    if (employeeNo.isEmpty || !RegExp(pattern).hasMatch(employeeNo)) {
      setState(() {
        _employeeNoChecking = false;
        _employeeNoAvailabilityError = null;
      });
      return;
    }

    if (_lastEmployeeNoChecked == employeeNo &&
        _employeeNoAvailabilityError == null) {
      return;
    }

    setState(() {
      _employeeNoChecking = true;
      _employeeNoAvailabilityError = null;
    });

    _employeeNoDebounce = Timer(const Duration(milliseconds: 450), () async {
      bool available = false;
      try {
        available = await _isEmployeeNoAvailable(employeeNo);
      } catch (_) {
        available = true;
      }
      if (!mounted) return;
      if (_role == 'student') return;
      if (_employeeNoCtrl.text.trim() != employeeNo) return;
      setState(() {
        _employeeNoChecking = false;
        _lastEmployeeNoChecked = employeeNo;
        _employeeNoAvailabilityError = available
            ? null
            : 'Employee ID already exists';
      });
    });
  }

  bool get _lockCreateAccount {
    final email = _emailCtrl.text.trim().toLowerCase();
    final emailFormatOk = _isValidEmailFormat(email);
    if (_emailChecking) return true;
    if (_emailAvailabilityError != null) return true;
    if (emailFormatOk && _lastEmailChecked != email) return true;

    if (_role != 'student') {
      final employeeNo = _employeeNoCtrl.text.trim();
      const pattern = r'^\d{4}-\d{3}$';
      final formatOk = RegExp(pattern).hasMatch(employeeNo);
      if (_employeeNoChecking) return true;
      if (_employeeNoAvailabilityError != null) return true;
      if (formatOk && _lastEmployeeNoChecked != employeeNo) return true;
      return false;
    }

    final studentNo = _studentNoCtrl.text.trim();
    const pattern = r'^\d{3}-\d{4}$';
    final formatOk = RegExp(pattern).hasMatch(studentNo);
    if (_studentNoChecking) return true;
    if (_studentNoAvailabilityError != null) return true;
    if (formatOk && _lastStudentNoChecked != studentNo) return true;
    return false;
  }

  bool get _isFormCompleteForCreate {
    final email = _emailCtrl.text.trim();
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    final hasBasic =
        email.isNotEmpty &&
        _isValidEmailFormat(email) &&
        first.isNotEmpty &&
        last.isNotEmpty;
    if (!hasBasic) return false;
    if (_emailChecking) return false;
    if (_emailAvailabilityError != null) return false;
    if (_lastEmailChecked != email.toLowerCase()) return false;

    if (!_userSetsOwnPassword) {
      if (_passwordCtrl.text.trim().length < 6) return false;
    }

    if (_role == 'student') {
      final studentNo = _studentNoCtrl.text.trim();
      final formatOk = RegExp(r'^\d{3}-\d{4}$').hasMatch(studentNo);
      if (!formatOk) return false;
      if ((_selectedCollege ?? '').trim().isEmpty) return false;
      if ((_selectedProgram ?? '').trim().isEmpty) return false;
      if (_selectedYear == null) return false;
      if (_studentNoChecking) return false;
      if (_studentNoAvailabilityError != null) return false;
      if (_lastStudentNoChecked != studentNo) return false;
      return true;
    }

    final employeeNo = _employeeNoCtrl.text.trim();
    if (!RegExp(r'^\d{4}-\d{3}$').hasMatch(employeeNo)) return false;
    if (_employeeNoChecking) return false;
    if (_employeeNoAvailabilityError != null) return false;
    if (_lastEmployeeNoChecked != employeeNo) return false;
    if (_roleNeedsDepartment && _deptCtrl.text.trim().isEmpty) return false;
    return true;
  }

  void _submit() {
    if (_lockCreateAccount) return;
    if (!_formKey.currentState!.validate()) return;
    if (widget.studentsOnly) {
      _role = 'student';
    }
    final effectivePassword = _userSetsOwnPassword
        ? widget.initialPassword
        : _passwordCtrl.text.trim();
    final effectiveAccountStatus = _role == 'student'
        ? 'active'
        : _accountStatus;
    final effectiveStudentVerification = _role == 'student'
        ? 'pending_email_verification'
        : _studentVerificationStatus;
    final effectiveSendReset = _userSetsOwnPassword ? true : _sendReset;
    final normalizedDepartment = _roleNeedsDepartment
        ? _deptCtrl.text.trim()
        : '';
    Navigator.pop(
      context,
      _CreateUserResult(
        email: _emailCtrl.text.trim().toLowerCase(),
        password: effectivePassword,
        firstName: _firstCtrl.text.trim(),
        lastName: _lastCtrl.text.trim(),
        role: _role,
        accountStatus: effectiveAccountStatus,
        studentVerificationStatus: effectiveStudentVerification,
        sendPasswordReset: effectiveSendReset,
        userSetsOwnPassword: _userSetsOwnPassword,
        studentNo: _studentNoCtrl.text.trim(),
        employeeNo: _employeeNoCtrl.text.trim(),
        department: normalizedDepartment,
        collegeId: _selectedCollege,
        programId: _selectedProgram,
        yearLevel: _selectedYear,
      ),
    );
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? helperText,
    String? errorText,
    bool enabled = true,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      errorText: errorText,
      labelStyle: const TextStyle(
        color: _UserManagementPageState.hintColor,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(
        icon,
        color: _UserManagementPageState.primaryColor.withOpacity(0.85),
      ),
      filled: true,
      fillColor: enabled ? Colors.white : Colors.grey[100],
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
        borderSide: const BorderSide(
          color: _UserManagementPageState.primaryColor,
          width: 1.6,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Create New Account',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: _UserManagementPageState.primaryColor,
        ),
      ),
      backgroundColor: _UserManagementPageState.backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BASIC INFORMATION',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _UserManagementPageState.hintColor,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _UserManagementPageState.textDark,
                  ),
                  decoration: _decor(
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    helperText: _emailChecking
                        ? 'Checking email availability...'
                        : null,
                    errorText: _emailAvailabilityError,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: _scheduleEmailAvailabilityCheck,
                  validator: (v) {
                    final s = (v ?? '').trim().toLowerCase();
                    if (s.isEmpty) return 'Email is required';
                    if (!_isValidEmailFormat(s)) return 'Invalid email';
                    if (_emailAvailabilityError != null) {
                      return _emailAvailabilityError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstCtrl,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _UserManagementPageState.textDark,
                        ),
                        decoration: _decor(
                          label: 'First Name',
                          icon: Icons.person_outline,
                        ),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lastCtrl,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _UserManagementPageState.textDark,
                        ),
                        decoration: _decor(
                          label: 'Last Name',
                          icon: Icons.person_outline,
                        ),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'ACCOUNT CONFIGURATION',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _UserManagementPageState.hintColor,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _role,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _UserManagementPageState.textDark,
                        ),
                        decoration: _decor(
                          label: 'System Role',
                          icon: Icons.admin_panel_settings_outlined,
                        ),
                        items: widget.studentsOnly
                            ? const [
                                DropdownMenuItem(
                                  value: 'student',
                                  child: Text('Student'),
                                ),
                              ]
                            : const [
                                DropdownMenuItem(
                                  value: 'professor',
                                  child: Text('Professor'),
                                ),
                                DropdownMenuItem(
                                  value: 'guard',
                                  child: Text('Guard'),
                                ),
                                DropdownMenuItem(
                                  value: 'osa_admin',
                                  child: Text('OSA Admin'),
                                ),
                                DropdownMenuItem(
                                  value: 'counseling_admin',
                                  child: Text('Counseling Admin'),
                                ),
                                DropdownMenuItem(
                                  value: 'department_admin',
                                  child: Text('Dean'),
                                ),
                              ],
                        onChanged: widget.studentsOnly
                            ? null
                            : (v) {
                                final nextRole = (v ?? 'student').trim();
                                setState(() {
                                  _role = nextRole;
                                  if (_role != 'student') {
                                    _studentVerificationStatus = 'verified';
                                    _studentNoDebounce?.cancel();
                                    _studentNoChecking = false;
                                    _studentNoAvailabilityError = null;
                                    _lastStudentNoChecked = '';
                                  } else {
                                    _accountStatus = 'active';
                                    _studentVerificationStatus =
                                        'pending_email_verification';
                                    _employeeNoDebounce?.cancel();
                                    _employeeNoChecking = false;
                                    _employeeNoAvailabilityError = null;
                                    _lastEmployeeNoChecked = '';
                                  }
                                  if (!_roleNeedsDepartment) _deptCtrl.clear();
                                });
                                if (nextRole == 'student') {
                                  _scheduleStudentNoAvailabilityCheck(
                                    _studentNoCtrl.text,
                                  );
                                } else {
                                  _scheduleEmployeeNoAvailabilityCheck(
                                    _employeeNoCtrl.text,
                                  );
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('account-status'),
                        initialValue: _accountStatus,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _UserManagementPageState.textDark,
                        ),
                        decoration: _decor(
                          label: 'Account Status',
                          icon: Icons.info_outline,
                        ),
                        items: _accountStatusItems(),
                        onChanged: _role == 'student'
                            ? null
                            : (v) => setState(
                                () => _accountStatus = (v ?? 'active').trim(),
                              ),
                      ),
                    ),
                  ],
                ),
                if (_role == 'student') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('student-verification-status'),
                    initialValue: 'pending_email_verification',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                    decoration: _decor(
                      label: 'Student Verification',
                      icon: Icons.fact_check_outlined,
                      helperText:
                          'Admin-created accounts wait for email verification first.',
                    ),
                    items: _studentVerificationItems(),
                    onChanged: null,
                  ),
                ],
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _userSetsOwnPassword,
                  contentPadding: EdgeInsets.zero,
                  activeColor: _UserManagementPageState.primaryColor,
                  title: const Text(
                    'User sets own password via email link',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                  ),
                  subtitle: const Text(
                    'Recommended: send account email after account creation.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _userSetsOwnPassword = v ?? true;
                      if (_userSetsOwnPassword) _sendReset = true;
                    });
                  },
                ),
                if (!_userSetsOwnPassword) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                    decoration: _decor(
                      label: 'Temporary Password',
                      icon: Icons.lock_outline,
                      helperText:
                          'User logs in with this temporary password, then can change it later.',
                    ),
                    validator: (v) {
                      if (_userSetsOwnPassword) return null;
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Temporary password is required';
                      if (s.length < 6) return 'Minimum 6 characters';
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'ROLE-SPECIFIC DETAILS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _UserManagementPageState.hintColor,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),
                if (_role == 'student') ...[
                  TextFormField(
                    controller: _studentNoCtrl,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                    decoration: _decor(
                      label: 'Student Number',
                      icon: Icons.badge_outlined,
                      helperText: _studentNoChecking
                          ? 'Checking Student Number availability...'
                          : null,
                      errorText: _studentNoAvailabilityError,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: const [
                      _HyphenatedDigitsFormatter(firstGroup: 3, secondGroup: 4),
                    ],
                    onChanged: _scheduleStudentNoAvailabilityCheck,
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Student Number is required';
                      if (!RegExp(r'^\d{3}-\d{4}$').hasMatch(s)) {
                        return 'Format must be ###-####';
                      }
                      if (_studentNoAvailabilityError != null) {
                        return _studentNoAvailabilityError;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCollege,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                    decoration: _decor(
                      label: 'College',
                      icon: Icons.account_balance_outlined,
                      enabled: widget.forcedDepartment == null,
                    ),
                    items: _colleges.map((doc) {
                      return DropdownMenuItem(
                        value: doc.id,
                        child: Text(doc.id),
                      );
                    }).toList(),
                    onChanged: widget.forcedDepartment != null
                        ? null
                        : (v) {
                            setState(() {
                              _selectedCollege = v;
                              _selectedProgram = null;
                              _programs = [];
                            });
                            if (v != null) _loadPrograms(v);
                          },
                    validator: (_) {
                      if (_selectedCollege == null ||
                          _selectedCollege!.trim().isEmpty) {
                        return 'College is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedProgram,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                    decoration: _decor(
                      label: 'Program/Course',
                      icon: Icons.school_outlined,
                    ),
                    items: _programs.map((doc) {
                      return DropdownMenuItem(
                        value: doc.id,
                        child: Text(doc.id),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedProgram = v),
                    validator: (_) {
                      if (_selectedProgram == null ||
                          _selectedProgram!.trim().isEmpty) {
                        return 'Program is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedYear,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                    decoration: _decor(
                      label: 'Year Level',
                      icon: Icons.layers_outlined,
                    ),
                    items: [1, 2, 3, 4, 5].map((y) {
                      return DropdownMenuItem(value: y, child: Text('Year $y'));
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedYear = v),
                    validator: (_) {
                      if (_selectedYear == null) {
                        return 'Year level is required';
                      }
                      return null;
                    },
                  ),
                ] else
                  Column(
                    children: [
                      TextFormField(
                        controller: _employeeNoCtrl,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _UserManagementPageState.textDark,
                        ),
                        decoration: _decor(
                          label: 'Employee ID',
                          icon: Icons.badge_outlined,
                          helperText: _employeeNoChecking
                              ? 'Checking Employee ID availability...'
                              : null,
                          errorText: _employeeNoAvailabilityError,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: const [
                          _HyphenatedDigitsFormatter(
                            firstGroup: 4,
                            secondGroup: 3,
                          ),
                        ],
                        onChanged: _scheduleEmployeeNoAvailabilityCheck,
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'Employee ID is required';
                          if (!RegExp(r'^\d{4}-\d{3}$').hasMatch(s)) {
                            return 'Format must be ####-###';
                          }
                          if (_employeeNoAvailabilityError != null) {
                            return _employeeNoAvailabilityError;
                          }
                          return null;
                        },
                      ),
                      if (_roleNeedsDepartment) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue:
                              _colleges.any(
                                (doc) => doc.id == _deptCtrl.text.trim(),
                              )
                              ? _deptCtrl.text.trim()
                              : null,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _UserManagementPageState.textDark,
                          ),
                          decoration: _decor(
                            label: 'Department (College)',
                            icon: Icons.business_outlined,
                            enabled: widget.forcedDepartment == null,
                          ),
                          items: _colleges.map((doc) {
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text(doc.id),
                            );
                          }).toList(),
                          onChanged: widget.forcedDepartment != null
                              ? null
                              : (v) => setState(
                                  () => _deptCtrl.text = (v ?? '').trim(),
                                ),
                          validator: (_) {
                            if (_roleNeedsDepartment &&
                                _deptCtrl.text.trim().isEmpty) {
                              return 'Department is required';
                            }
                            return null;
                          },
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 16),
                SwitchListTile(
                  value: _userSetsOwnPassword ? true : _sendReset,
                  onChanged: _userSetsOwnPassword
                      ? null
                      : (v) => setState(() => _sendReset = v),
                  title: const Text(
                    'Send account email',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeThumbColor: _UserManagementPageState.primaryColor,
                ),
                if (_submitting)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(
                      color: _UserManagementPageState.primaryColor,
                      backgroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: _UserManagementPageState.hintColor,
            ),
          ),
        ),
        FilledButton(
          onPressed:
              (_submitting || _lockCreateAccount || !_isFormCompleteForCreate)
              ? null
              : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: _UserManagementPageState.primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text(
            'Create Account',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _HyphenatedDigitsFormatter extends TextInputFormatter {
  final int firstGroup;
  final int secondGroup;

  const _HyphenatedDigitsFormatter({
    required this.firstGroup,
    required this.secondGroup,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final maxDigits = firstGroup + secondGroup;
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length > maxDigits
        ? digits.substring(0, maxDigits)
        : digits;

    String formatted;
    if (clipped.length <= firstGroup) {
      formatted = clipped;
    } else {
      formatted =
          '${clipped.substring(0, firstGroup)}-${clipped.substring(firstGroup)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

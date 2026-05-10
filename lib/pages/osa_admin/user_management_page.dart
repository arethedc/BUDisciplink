import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../shared/widgets/modern_table_layout.dart';
import '../shared/widgets/app_layout_tokens.dart';
import '../shared/widgets/responsive_layout_tokens.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';

class UserManagementPage extends StatefulWidget {
  final bool studentsOnlyScope;
  final bool professorsOnlyScope;
  final bool pendingApprovalOnlyScope;
  final bool hideCreateAction;
  final String? headerTitle;
  final String? headerSubtitle;
  final String? initialSelectedUserId;
  final Color pageBackgroundColor;

  const UserManagementPage({
    super.key,
    this.studentsOnlyScope = false,
    this.professorsOnlyScope = false,
    this.pendingApprovalOnlyScope = false,
    this.hideCreateAction = false,
    this.headerTitle,
    this.headerSubtitle,
    this.initialSelectedUserId,
    this.pageBackgroundColor = Colors.white,
  });

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

enum _HeaderQuickAction { importStudents, createUser }

class _UserManagementPageState extends State<UserManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late int _lastTabIndex;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _allUsersStream;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';

  Map<String, dynamic>? _currentUserData;
  String? _selectedUserId;
  String? _detailLoadedUserId;
  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _visibleUserDocs =
      ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        const [],
      );
  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _allUserDocs =
      ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        const [],
      );
  bool _detailEditing = false;
  String _pendingStudentFilter = 'pending_approval';

  final _detailFirstNameCtrl = TextEditingController();
  final _detailMiddleNameCtrl = TextEditingController();
  final _detailLastNameCtrl = TextEditingController();
  final _detailEmailCtrl = TextEditingController();
  final _detailStudentNoCtrl = TextEditingController();
  final _detailCollegeCtrl = TextEditingController();
  final _detailProgramCtrl = TextEditingController();
  final _detailEmployeeNoCtrl = TextEditingController();
  final _detailDepartmentCtrl = TextEditingController();
  String _detailRole = '';
  String _detailAccountStatus = 'active';
  String _detailStudentVerificationStatus = 'verified';
  Timer? _detailEmailDebounce;
  bool _detailEmailChecking = false;
  String? _detailEmailAvailabilityError;
  String _detailOriginalEmail = '';
  String _detailLastEmailChecked = '';
  Timer? _detailStudentNoDebounce;
  bool _detailStudentNoChecking = false;
  String? _detailStudentNoAvailabilityError;
  Timer? _detailEmployeeNoDebounce;
  bool _detailEmployeeNoChecking = false;
  String? _detailEmployeeNoAvailabilityError;
  String _detailOriginalStudentNo = '';
  String _detailOriginalEmployeeNo = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _detailProgramOptions =
      const [];
  bool _detailProgramLoading = false;
  String? _detailSelectedProgramId;
  int _detailProgramLoadSeq = 0;
  int _detailCollegeLoadSeq = 0;
  String _detailCollegeName = '';
  final Map<String, String> _detailCollegeNameCache = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastUserDocs = const [];
  bool _detailPhotoUploading = false;
  bool _isRefreshingTable = false;
  final Map<String, Future<String>> _resolvedPhotoUrlCache = {};
  Object? _filterCacheSourceToken;
  String _filterCacheType = '';
  String _filterCacheQuery = '';
  String _filterCachePendingFilter = '';
  String _filterCacheAdminRole = '';
  String _filterCacheAdminDept = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterCacheResult =
      const [];

  // Design Theme
  static const primaryColor = Color(0xFF1B5E20);
  static const backgroundColor = Colors.white;
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _lastTabIndex = _tabController.index;
    _tabController.addListener(_handleTabIndexChanged);
    _allUsersStream = FirebaseFirestore.instance
        .collection('users')
        .snapshots();
    final initialUid = (widget.initialSelectedUserId ?? '').trim();
    if (initialUid.isNotEmpty) {
      if (widget.studentsOnlyScope) {
        _tabController.index = 0;
        _lastTabIndex = 0;
        _pendingStudentFilter = 'pending_approval';
      }
      _selectedUserId = initialUid;
      _detailLoadedUserId = null;
    }
    _loadAdminData();
  }

  @override
  void didUpdateWidget(covariant UserManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prev = (oldWidget.initialSelectedUserId ?? '').trim();
    final next = (widget.initialSelectedUserId ?? '').trim();
    if (prev == next) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (next.isEmpty) {
        if (_selectedUserId != null) {
          _clearDetailSelection();
        }
        return;
      }
      setState(() {
        if (widget.studentsOnlyScope) {
          _tabController.index = 0;
          _lastTabIndex = 0;
          _pendingStudentFilter = 'pending_approval';
        }
        _selectedUserId = next;
        _detailLoadedUserId = null;
        _detailEditing = false;
      });
      _invalidateFilterCache();
    });
  }

  Future<void> _loadAdminData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 6));
        if (mounted) {
          setState(() {
            _currentUserData = doc.data();
          });
        }
      }
    } catch (_) {
      // Continue with fallback role scope if profile fetch is unavailable.
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _handleTabIndexChanged() {
    if (!mounted) return;
    final nextIndex = _tabController.index;
    if (nextIndex == _lastTabIndex) return;
    _lastTabIndex = nextIndex;
    _invalidateFilterCache();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selectedUserId != null || _detailEditing) {
        _clearDetailSelection();
        return;
      }
      setState(() {});
    });
  }

  void _invalidateFilterCache() {
    _filterCacheSourceToken = null;
    _filterCacheType = '';
    _filterCacheQuery = '';
    _filterCachePendingFilter = '';
    _filterCacheAdminRole = '';
    _filterCacheAdminDept = '';
    _filterCacheResult = const [];
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _detailEmailDebounce?.cancel();
    _detailStudentNoDebounce?.cancel();
    _detailEmployeeNoDebounce?.cancel();
    _tabController.removeListener(_handleTabIndexChanged);
    _tabController.dispose();
    _searchCtrl.dispose();
    _detailFirstNameCtrl.dispose();
    _detailMiddleNameCtrl.dispose();
    _detailLastNameCtrl.dispose();
    _detailEmailCtrl.dispose();
    _detailStudentNoCtrl.dispose();
    _detailCollegeCtrl.dispose();
    _detailProgramCtrl.dispose();
    _detailEmployeeNoCtrl.dispose();
    _detailDepartmentCtrl.dispose();
    _visibleUserDocs.dispose();
    _allUserDocs.dispose();
    super.dispose();
  }

  String _activeUserListType() {
    switch (_tabController.index) {
      case 0:
        return 'active_staff';
      case 1:
        return 'inactive_staff';
      case 2:
        return 'staff';
      default:
        return 'active_staff';
    }
  }

  String _studentsOnlyListType() {
    switch (_tabController.index) {
      case 0:
        return 'pending';
      case 1:
        return 'active_students';
      default:
        return 'students';
    }
  }

  int _countForType({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String type,
    required String query,
    required String adminRole,
    required String adminDept,
  }) {
    return _filteredUsersMemoized(
      rawDocs: docs,
      snapshotToken: docs,
      type: type,
      query: query,
      adminRole: adminRole,
      adminDept: adminDept,
    ).length;
  }

  Widget _buildManagementTabs({
    required bool showStudentsOnly,
    required bool showProfessorsOnly,
  }) {
    return ValueListenableBuilder<
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
    >(
      valueListenable: _allUserDocs,
      builder: (context, docs, _) {
        final sourceDocs = docs.isNotEmpty ? docs : _lastUserDocs;
        final q = _searchQuery;
        final adminRole = (_currentUserData?['role'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final adminDept =
            (_currentUserData?['employeeProfile']?['department'] ?? '')
                .toString();
        final pendingTotalCount =
            _countPendingByVerification(
              docs: sourceDocs,
              verification: 'pending_email_verification',
              query: q,
              adminRole: adminRole,
              adminDept: adminDept,
            ) +
            _countPendingByVerification(
              docs: sourceDocs,
              verification: 'pending_profile',
              query: q,
              adminRole: adminRole,
              adminDept: adminDept,
            ) +
            _countPendingByVerification(
              docs: sourceDocs,
              verification: 'pending_approval',
              query: q,
              adminRole: adminRole,
              adminDept: adminDept,
            ) +
            _countPendingByVerification(
              docs: sourceDocs,
              verification: 'rejected',
              query: q,
              adminRole: adminRole,
              adminDept: adminDept,
            );

        final common = TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: primaryColor,
          unselectedLabelColor: hintColor.withValues(alpha: 0.6),
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
          tabs: showStudentsOnly
              ? [
                  Tab(text: 'Pending ($pendingTotalCount)'),
                  Tab(
                    text:
                        'Active (${_countForType(docs: sourceDocs, type: 'active_students', query: q, adminRole: adminRole, adminDept: adminDept)})',
                  ),
                  Tab(
                    text:
                        'All (${_countForType(docs: sourceDocs, type: 'students', query: q, adminRole: adminRole, adminDept: adminDept)})',
                  ),
                ]
              : showProfessorsOnly
              ? [
                  Tab(
                    text:
                        'Active (${_countForType(docs: sourceDocs, type: 'active_staff', query: q, adminRole: adminRole, adminDept: adminDept)})',
                  ),
                  Tab(
                    text:
                        'Inactive (${_countForType(docs: sourceDocs, type: 'inactive_staff', query: q, adminRole: adminRole, adminDept: adminDept)})',
                  ),
                  Tab(
                    text:
                        'All Professors (${_countForType(docs: sourceDocs, type: 'staff', query: q, adminRole: adminRole, adminDept: adminDept)})',
                  ),
                ]
              : [
                  Tab(
                    text:
                        'Active (${_countForType(docs: sourceDocs, type: 'active_staff', query: q, adminRole: adminRole, adminDept: adminDept)})',
                  ),
                  Tab(
                    text:
                        'Inactive (${_countForType(docs: sourceDocs, type: 'inactive_staff', query: q, adminRole: adminRole, adminDept: adminDept)})',
                  ),
                  Tab(
                    text:
                        'All Staff & Admins (${_countForType(docs: sourceDocs, type: 'staff', query: q, adminRole: adminRole, adminDept: adminDept)})',
                  ),
                ],
        );
        return common;
      },
    );
  }

  bool _isPendingApprovalEditContext() {
    if (widget.pendingApprovalOnlyScope) return true;
    if (!widget.studentsOnlyScope) return false;
    return _studentsOnlyListType() == 'pending';
  }

  int _countPendingByVerification({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String verification,
    required String query,
    required String adminRole,
    required String adminDept,
  }) {
    return docs.where((doc) {
      final data = doc.data();
      final role = (data['role'] ?? '').toString().trim().toLowerCase();
      if (role != 'student') return false;

      final userDept = (data['employeeProfile']?['department'] ?? '')
          .toString();
      final studentCollege = (data['studentProfile']?['collegeId'] ?? '')
          .toString();
      if (adminRole == 'department_admin' || adminRole == 'dean') {
        if (studentCollege != adminDept && userDept != adminDept) {
          return false;
        }
      }

      final accountStatus = _readAccountStatus(data, role: role);
      final allowInactiveForRejected = verification == 'rejected';
      if (!allowInactiveForRejected && accountStatus != 'active') return false;

      final studentVerification = _readStudentVerification(data, role: role);
      final matchesVerification = verification == 'pending_email_verification'
          ? (_hasPendingEmailVerification(data, role: role) ||
                studentVerification == verification)
          : studentVerification == verification;
      if (!matchesVerification) return false;

      return _matchesSearch(data, query);
    }).length;
  }

  Widget _buildPendingStudentFilterBar() {
    return ValueListenableBuilder<
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
    >(
      valueListenable: _allUserDocs,
      builder: (context, docs, _) {
        final sourceDocs = docs.isNotEmpty ? docs : _lastUserDocs;
        final q = _searchQuery;
        final adminRole = (_currentUserData?['role'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final adminDept =
            (_currentUserData?['employeeProfile']?['department'] ?? '')
                .toString();

        final pendingEmailCount = _countPendingByVerification(
          docs: sourceDocs,
          verification: 'pending_email_verification',
          query: q,
          adminRole: adminRole,
          adminDept: adminDept,
        );
        final pendingProfileCount = _countPendingByVerification(
          docs: sourceDocs,
          verification: 'pending_profile',
          query: q,
          adminRole: adminRole,
          adminDept: adminDept,
        );
        final pendingApprovalCount = _countPendingByVerification(
          docs: sourceDocs,
          verification: 'pending_approval',
          query: q,
          adminRole: adminRole,
          adminDept: adminDept,
        );
        final rejectedCount = _countPendingByVerification(
          docs: sourceDocs,
          verification: 'rejected',
          query: q,
          adminRole: adminRole,
          adminDept: adminDept,
        );

        const filterRadius = AppRadii.md;

        Widget statusTab({required String value, required String label}) {
          final selected = _pendingStudentFilter == value;
          return InkWell(
            borderRadius: BorderRadius.circular(filterRadius),
            onTap: () {
              if (_pendingStudentFilter == value) return;
              setState(() {
                _pendingStudentFilter = value;
                _invalidateFilterCache();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected
                    ? primaryColor.withValues(alpha: 0.12)
                    : Colors.white,
                borderRadius: BorderRadius.circular(filterRadius),
                border: Border.all(
                  color: selected
                      ? primaryColor.withValues(alpha: 0.36)
                      : Colors.black.withValues(alpha: 0.10),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? primaryColor : textDark,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }

        return Container(
          color: widget.pageBackgroundColor,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  statusTab(
                    value: 'pending_email_verification',
                    label: 'Pending Email ($pendingEmailCount)',
                  ),
                  const SizedBox(width: 8),
                  statusTab(
                    value: 'pending_profile',
                    label: 'Pending Profile ($pendingProfileCount)',
                  ),
                  const SizedBox(width: 8),
                  statusTab(
                    value: 'pending_approval',
                    label: 'Pending Approval ($pendingApprovalCount)',
                  ),
                  const SizedBox(width: 8),
                  statusTab(
                    value: 'rejected',
                    label: 'Rejected ($rejectedCount)',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _displayName(Map<String, dynamic> data) {
    final first = (data['firstName'] ?? '').toString().trim();
    final middle = (data['middleName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final full = [
      first,
      middle,
      last,
    ].where((part) => part.isNotEmpty).join(' ').trim();
    if (full.isNotEmpty) return full;
    final dn = (data['displayName'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    final email = (data['email'] ?? '').toString().trim();
    if (email.contains('@')) return email.split('@').first;
    return '--';
  }

  String _photoUrl(Map<String, dynamic> data) {
    final direct = (data['photoUrl'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final profilePhoto = (data['profilePhotoUrl'] ?? '').toString().trim();
    if (profilePhoto.isNotEmpty) return profilePhoto;

    final studentProfile = data['studentProfile'] as Map<String, dynamic>?;
    final nestedStudentPhoto = (studentProfile?['photoUrl'] ?? '')
        .toString()
        .trim();
    if (nestedStudentPhoto.isNotEmpty) return nestedStudentPhoto;

    final employeeProfile = data['employeeProfile'] as Map<String, dynamic>?;
    final nestedEmployeePhoto = (employeeProfile?['photoUrl'] ?? '')
        .toString()
        .trim();
    if (nestedEmployeePhoto.isNotEmpty) return nestedEmployeePhoto;

    return '';
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

  Widget _buildUserAvatar(
    Map<String, dynamic> data,
    String name, {
    double radius = 14,
    double fontSize = 10,
  }) {
    final photoUrl = _photoUrl(data);
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    Widget fallbackInitial() {
      return Text(
        initial,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: primaryColor,
        ),
      );
    }

    if (photoUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: primaryColor.withValues(alpha: 0.12),
        child: fallbackInitial(),
      );
    }

    if (_isHttpPhotoUrl(photoUrl)) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: primaryColor.withValues(alpha: 0.12),
        foregroundImage: NetworkImage(photoUrl),
        child: null,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: primaryColor.withValues(alpha: 0.12),
      child: FutureBuilder<String>(
        future: _resolvedPhotoUrlCache.putIfAbsent(
          photoUrl,
          () => _resolvePhotoUrl(photoUrl),
        ),
        builder: (context, snapshot) {
          final resolvedUrl = (snapshot.data ?? '').trim();
          if (resolvedUrl.isEmpty) return fallbackInitial();
          return CircleAvatar(
            radius: radius,
            backgroundColor: Colors.transparent,
            foregroundImage: NetworkImage(resolvedUrl),
          );
        },
      ),
    );
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

  bool _isDepartmentAdminActor() {
    final role = (_currentUserData?['role'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return role == 'department_admin' || role == 'dean';
  }

  String _imageExt(String pathOrName) {
    final dot = pathOrName.lastIndexOf('.');
    if (dot < 0 || dot == pathOrName.length - 1) return 'jpg';
    return pathOrName.substring(dot + 1).toLowerCase();
  }

  String _imageContentType(String ext) {
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

  Future<void> _changeDetailProfilePhoto({
    required String targetUid,
    required Map<String, dynamic> targetData,
    required String targetVerificationStatus,
  }) async {
    if (_detailPhotoUploading) return;
    if (!_isDepartmentAdminActor()) return;

    final targetRole = (targetData['role'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (!_isStudentRole(targetRole)) return;
    if (targetVerificationStatus != 'pending_approval') {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Profile photo can only be changed while student is pending approval.',
          ),
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            'Update Profile Photo',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'Are you sure you want to update this student profile photo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;

    setState(() => _detailPhotoUploading = true);
    try {
      final filename = picked.name.isNotEmpty ? picked.name : picked.path;
      final ext = _imageExt(filename);
      final ref = FirebaseStorage.instance.ref(
        'users/$targetUid/profile/profile_admin_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      final metadata = SettableMetadata(contentType: _imageContentType(ext));

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          throw Exception(
            'Selected image is too large. Please use an image under 5 MB.',
          );
        }
        await ref.putData(bytes, metadata);
      } else {
        final file = File(picked.path);
        final size = await file.length();
        if (size > 5 * 1024 * 1024) {
          throw Exception(
            'Selected image is too large. Please use an image under 5 MB.',
          );
        }
        await ref.putFile(file, metadata);
      }

      final nextUrl = await ref.getDownloadURL();
      final prevUrl = (targetData['photoUrl'] ?? '').toString().trim();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .update({
            'photoUrl': nextUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      await _appendUserProfileLog(
        targetUid: targetUid,
        action: 'photo_updated',
        title: 'Profile photo updated',
        details: 'Department admin updated student profile photo.',
        payload: {
          'field': 'photoUrl',
          'before': prevUrl,
          'after': nextUrl,
          'verificationStatus': targetVerificationStatus,
        },
      );

      await _notifyUser(
        uid: targetUid,
        title: 'Profile Photo Updated',
        body:
            'Your profile photo was updated by your department admin during profile review.',
        payload: {
          'type': 'profile_update',
          'field': 'photoUrl',
          'verificationStatus': targetVerificationStatus,
        },
      );

      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _detailPhotoUploading = false);
      }
    }
  }

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
        value == 'rejected' ||
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

  bool _hasPendingEmailVerification(
    Map<String, dynamic> data, {
    required String role,
  }) {
    if (!_isStudentRole(role)) return false;
    final field = (data['studentVerificationStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final legacy = (data['status'] ?? '').toString().trim().toLowerCase();
    final emailVerifiedFlag = data['emailVerified'];
    if (field == 'pending_email_verification') return true;
    if (legacy == 'pending_email_verification') return true;
    if (emailVerifiedFlag is bool && emailVerifiedFlag == false) return true;
    return false;
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
        key != 'super_admin' &&
        key != 'guard';
  }

  void _clearDetailSelection() {
    setState(() {
      _selectedUserId = null;
      _detailLoadedUserId = null;
      _detailEditing = false;
      _detailRole = '';
      _detailAccountStatus = 'active';
      _detailStudentVerificationStatus = 'verified';
      _detailEmailChecking = false;
      _detailEmailAvailabilityError = null;
      _detailOriginalEmail = '';
      _detailLastEmailChecked = '';
      _detailStudentNoChecking = false;
      _detailStudentNoAvailabilityError = null;
      _detailEmployeeNoChecking = false;
      _detailEmployeeNoAvailabilityError = null;
      _detailOriginalStudentNo = '';
      _detailOriginalEmployeeNo = '';
      _detailProgramOptions = const [];
      _detailProgramLoading = false;
      _detailSelectedProgramId = null;
      _detailFirstNameCtrl.clear();
      _detailMiddleNameCtrl.clear();
      _detailLastNameCtrl.clear();
      _detailEmailCtrl.clear();
      _detailStudentNoCtrl.clear();
      _detailCollegeCtrl.clear();
      _detailProgramCtrl.clear();
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
    final rawCollegeId = (studentProfile['collegeId'] ?? '').toString().trim();
    final rawProgramId = (studentProfile['programId'] ?? '').toString().trim();

    setState(() {
      _selectedUserId = uid;
      _detailLoadedUserId = uid;
      if (resetEditing) _detailEditing = false;
      _detailRole = role;
      _detailAccountStatus = accountStatus;
      _detailStudentVerificationStatus = studentVerification;
      _detailEmailChecking = false;
      _detailEmailAvailabilityError = null;
      _detailEmailCtrl.text = (data['email'] ?? '').toString().trim();
      _detailOriginalEmail = _detailEmailCtrl.text.trim().toLowerCase();
      _detailLastEmailChecked = _detailOriginalEmail;
      _detailStudentNoChecking = false;
      _detailStudentNoAvailabilityError = null;
      _detailEmployeeNoChecking = false;
      _detailEmployeeNoAvailabilityError = null;

      _detailFirstNameCtrl.text = (data['firstName'] ?? '').toString().trim();
      _detailMiddleNameCtrl.text = (data['middleName'] ?? '').toString().trim();
      _detailLastNameCtrl.text = (data['lastName'] ?? '').toString().trim();
      _detailStudentNoCtrl.text =
          (studentProfile['studentNo'] ?? data['studentNo'] ?? '')
              .toString()
              .trim();
      _detailCollegeCtrl.text = rawCollegeId;
      _detailProgramCtrl.text = rawProgramId;
      _detailSelectedProgramId = _detailProgramCtrl.text.trim().isEmpty
          ? null
          : _detailProgramCtrl.text.trim();
      _detailEmployeeNoCtrl.text =
          (employeeProfile['employeeNo'] ?? data['employeeNo'] ?? '')
              .toString()
              .trim();
      _detailOriginalStudentNo = _detailStudentNoCtrl.text.trim();
      _detailOriginalEmployeeNo = _detailEmployeeNoCtrl.text.trim();
      _detailDepartmentCtrl.text = (employeeProfile['department'] ?? '')
          .toString()
          .trim();
      _detailCollegeName = '';
    });

    if (_isStudentRole(role)) {
      final collegeId = _detailCollegeCtrl.text.trim();
      _loadDetailProgramsForCollege(
        collegeId,
        initialProgramId: _detailSelectedProgramId,
      );
      _loadDetailCollegeName(collegeId);
    } else {
      setState(() {
        _detailProgramOptions = const [];
        _detailProgramLoading = false;
        _detailSelectedProgramId = null;
        _detailCollegeName = '';
      });
    }
  }

  Future<void> _loadDetailProgramsForCollege(
    String collegeId, {
    String? initialProgramId,
  }) async {
    final trimmed = collegeId.trim();
    final seq = ++_detailProgramLoadSeq;
    final normalizedInitial = (initialProgramId ?? '').trim();

    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _detailProgramOptions = const [];
        _detailProgramLoading = false;
        _detailSelectedProgramId = normalizedInitial.isEmpty
            ? null
            : normalizedInitial;
      });
      return;
    }

    setState(() {
      _detailProgramLoading = true;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('programs')
          .where('collegeId', isEqualTo: trimmed)
          .where('active', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!mounted || seq != _detailProgramLoadSeq) return;

      final docs = snap.docs;
      final preferred = (initialProgramId ?? _detailProgramCtrl.text).trim();
      final hasPreferred =
          preferred.isNotEmpty && docs.any((doc) => doc.id.trim() == preferred);

      setState(() {
        _detailProgramOptions = docs;
        _detailProgramLoading = false;
        if (hasPreferred) {
          _detailSelectedProgramId = preferred;
          _detailProgramCtrl.text = preferred;
        } else if (_detailSelectedProgramId != null &&
            docs.any((doc) => doc.id == _detailSelectedProgramId)) {
          _detailProgramCtrl.text = _detailSelectedProgramId!;
        } else {
          _detailSelectedProgramId = null;
        }
      });
    } catch (_) {
      if (!mounted || seq != _detailProgramLoadSeq) return;
      setState(() {
        _detailProgramOptions = const [];
        _detailProgramLoading = false;
        _detailSelectedProgramId = normalizedInitial.isEmpty
            ? null
            : normalizedInitial;
      });
    }
  }

  Future<void> _loadDetailCollegeName(String collegeId) async {
    final id = collegeId.trim();
    final seq = ++_detailCollegeLoadSeq;

    if (id.isEmpty) {
      if (!mounted) return;
      setState(() => _detailCollegeName = '');
      return;
    }

    final cached = _detailCollegeNameCache[id];
    if (cached != null && cached.trim().isNotEmpty) {
      if (!mounted) return;
      setState(() => _detailCollegeName = cached.trim());
      return;
    }

    String resolved = '';
    try {
      final byId = await FirebaseFirestore.instance
          .collection('colleges')
          .doc(id)
          .get()
          .timeout(const Duration(seconds: 6));
      final byIdData = byId.data();
      if (byIdData != null) {
        resolved =
            (byIdData['name'] ??
                    byIdData['collegeName'] ??
                    byIdData['title'] ??
                    '')
                .toString()
                .trim();
      }
      if (resolved.isEmpty) {
        final byCode = await FirebaseFirestore.instance
            .collection('colleges')
            .where('collegeCode', isEqualTo: id)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 6));
        if (byCode.docs.isNotEmpty) {
          final data = byCode.docs.first.data();
          resolved =
              (data['name'] ?? data['collegeName'] ?? data['title'] ?? '')
                  .toString()
                  .trim();
        }
      }
    } catch (_) {
      // Keep detail panel resilient if lookup fails.
    }

    if (!mounted || seq != _detailCollegeLoadSeq) return;
    setState(() {
      _detailCollegeName = resolved;
      if (resolved.isNotEmpty) {
        _detailCollegeNameCache[id] = resolved;
      }
    });
  }

  bool _isValidEmailFormat(String email) {
    final value = email.trim().toLowerCase();
    if (value.isEmpty) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
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

  Future<bool> _isDetailEmailAvailable(String email) async {
    final uid = _selectedUserId;
    if (uid == null) return true;
    if (email == _detailOriginalEmail) return true;
    final hasDuplicate = await _existsByFieldForOtherUser(
      field: 'email',
      value: email,
      currentUid: uid,
    );
    return !hasDuplicate;
  }

  void _scheduleDetailEmailAvailabilityCheck(String raw) {
    _detailEmailDebounce?.cancel();
    final email = raw.trim().toLowerCase();

    if (!_detailEditing) {
      if (_detailEmailChecking || _detailEmailAvailabilityError != null) {
        setState(() {
          _detailEmailChecking = false;
          _detailEmailAvailabilityError = null;
        });
      }
      return;
    }

    if (email.isEmpty || !_isValidEmailFormat(email)) {
      setState(() {
        _detailEmailChecking = false;
        _detailEmailAvailabilityError = null;
      });
      return;
    }

    if (email == _detailOriginalEmail) {
      setState(() {
        _detailEmailChecking = false;
        _detailEmailAvailabilityError = null;
        _detailLastEmailChecked = email;
      });
      return;
    }

    if (_detailLastEmailChecked == email &&
        _detailEmailAvailabilityError == null) {
      return;
    }

    setState(() {
      _detailEmailChecking = true;
      _detailEmailAvailabilityError = null;
    });

    _detailEmailDebounce = Timer(const Duration(milliseconds: 450), () async {
      bool available = true;
      try {
        available = await _isDetailEmailAvailable(email);
      } catch (_) {
        available = true;
      }
      if (!mounted) return;
      if (!_detailEditing) return;
      if (_detailEmailCtrl.text.trim().toLowerCase() != email) return;
      setState(() {
        _detailEmailChecking = false;
        _detailLastEmailChecked = email;
        _detailEmailAvailabilityError = available
            ? null
            : 'Email already exists';
      });
    });
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

  String? _detailStudentNoErrorText() {
    if (!_detailEditing || !_isStudentRole(_detailRole)) return null;
    final studentNo = _detailStudentNoCtrl.text.trim();
    if (studentNo.isEmpty) return 'Student Number is required.';
    if (!RegExp(r'^\d{3}-\d{4}$').hasMatch(studentNo)) {
      return 'Student Number format is incorrect (###-####).';
    }
    return _detailStudentNoAvailabilityError;
  }

  String? _detailStudentNoHelperText() {
    if (!_detailEditing || !_isStudentRole(_detailRole)) return null;
    final studentNo = _detailStudentNoCtrl.text.trim();
    if (_detailStudentNoChecking)
      return 'Checking Student Number availability...';
    if (studentNo.isEmpty ||
        !RegExp(r'^\d{3}-\d{4}$').hasMatch(studentNo) ||
        _detailStudentNoAvailabilityError != null) {
      return null;
    }
    if (studentNo == _detailOriginalStudentNo) return 'Current Student Number';
    return 'Student Number is available.';
  }

  String? _detailEmployeeNoErrorText() {
    if (!_detailEditing || _isStudentRole(_detailRole)) return null;
    final employeeNo = _detailEmployeeNoCtrl.text.trim();
    if (employeeNo.isEmpty) return 'Employee ID is required.';
    if (!RegExp(r'^\d{4}-\d{3}$').hasMatch(employeeNo)) {
      return 'Employee ID format is incorrect (####-###).';
    }
    return _detailEmployeeNoAvailabilityError;
  }

  String? _detailEmployeeNoHelperText() {
    if (!_detailEditing || _isStudentRole(_detailRole)) return null;
    final employeeNo = _detailEmployeeNoCtrl.text.trim();
    if (_detailEmployeeNoChecking)
      return 'Checking Employee ID availability...';
    if (employeeNo.isEmpty ||
        !RegExp(r'^\d{4}-\d{3}$').hasMatch(employeeNo) ||
        _detailEmployeeNoAvailabilityError != null) {
      return null;
    }
    if (employeeNo == _detailOriginalEmployeeNo) return 'Current Employee ID';
    return 'Employee ID is available.';
  }

  bool get _detailSaveLocked {
    if (!_detailEditing) return false;
    if (_detailFirstNameCtrl.text.trim().isEmpty ||
        _detailLastNameCtrl.text.trim().isEmpty) {
      return true;
    }
    if (_detailEmailChecking ||
        _detailStudentNoChecking ||
        _detailEmployeeNoChecking) {
      return true;
    }
    if (_detailEmailAvailabilityError != null) return true;
    final email = _detailEmailCtrl.text.trim().toLowerCase();
    final emailChanged = email != _detailOriginalEmail;
    if (email.isEmpty || !_isValidEmailFormat(email)) return true;
    if (emailChanged && _detailLastEmailChecked != email) return true;
    if (_detailStudentNoAvailabilityError != null ||
        _detailEmployeeNoAvailabilityError != null) {
      return true;
    }

    if (_isStudentRole(_detailRole)) {
      if (_detailProgramLoading) return true;
      final studentNo = _detailStudentNoCtrl.text.trim();
      if (studentNo.isEmpty) return true;
      if (_detailCollegeCtrl.text.trim().isEmpty) return true;
      final selectedProgramId = (_detailSelectedProgramId ?? '').trim();
      if (selectedProgramId.isEmpty) return true;
      if (studentNo.isNotEmpty &&
          !RegExp(r'^\d{3}-\d{4}$').hasMatch(studentNo)) {
        return true;
      }
      return false;
    }

    final employeeNo = _detailEmployeeNoCtrl.text.trim();
    if (employeeNo.isEmpty) return true;
    if (employeeNo.isNotEmpty &&
        !RegExp(r'^\d{4}-\d{3}$').hasMatch(employeeNo)) {
      return true;
    }
    if (_roleNeedsDepartmentFor(_detailRole) &&
        _detailDepartmentCtrl.text.trim().isEmpty) {
      return true;
    }
    return false;
  }

  Future<void> _saveSelectedUserDetails() async {
    final uid = _selectedUserId;
    if (uid == null) return;

    final normalizedVerification = _normalizeStudentVerification(
      _detailStudentVerificationStatus,
    );
    final inPendingEditContext = _isPendingApprovalEditContext();
    final canEditProfileNow =
        inPendingEditContext &&
        _isStudentRole(_detailRole) &&
        normalizedVerification == 'pending_approval';
    if (!canEditProfileNow) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Profile editing is allowed only while student status is Pending Approval.',
          ),
        ),
      );
      return;
    }

    if (_detailSaveLocked) return;

    final role = _detailRole;
    final firstName = _detailFirstNameCtrl.text.trim();
    final middleName = _detailMiddleNameCtrl.text.trim();
    final lastName = _detailLastNameCtrl.text.trim();
    final email = _detailEmailCtrl.text.trim().toLowerCase();
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    Map<String, dynamic> beforeData = const <String, dynamic>{};
    try {
      beforeData = (await userRef.get()).data() ?? const <String, dynamic>{};
    } catch (_) {}
    if (!mounted) return;

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('First name, last name, and email are required.'),
        ),
      );
      return;
    }

    if (!_isValidEmailFormat(email)) {
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email address format is incorrect.')),
      );
      return;
    }
    if (email != _detailOriginalEmail) {
      final available = await _isDetailEmailAvailable(email);
      if (!mounted) return;
      if (!available) {
        setState(() {
          _detailEmailAvailabilityError = 'Email already exists';
        });
        AppScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Email already exists.')));
        return;
      }
    }

    if (_isStudentRole(role)) {
      _detailProgramCtrl.text = (_detailSelectedProgramId ?? '').trim();
      final studentNo = _detailStudentNoCtrl.text.trim();
      if (studentNo.isNotEmpty &&
          !RegExp(r'^\d{3}-\d{4}$').hasMatch(studentNo)) {
        AppScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student Number must be ###-####.')),
        );
        return;
      }
      if (studentNo.isNotEmpty) {
        final available = await _isDetailStudentNoAvailable(studentNo);
        if (!mounted) return;
        if (!available) {
          setState(() {
            _detailStudentNoAvailabilityError = 'Student Number already exists';
          });
          AppScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Student Number already exists.')),
          );
          return;
        }
      }
    } else {
      final employeeNo = _detailEmployeeNoCtrl.text.trim();
      if (employeeNo.isNotEmpty &&
          !RegExp(r'^\d{4}-\d{3}$').hasMatch(employeeNo)) {
        AppScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee ID must be ####-###.')),
        );
        return;
      }
      if (employeeNo.isNotEmpty) {
        final available = await _isDetailEmployeeNoAvailable(employeeNo);
        if (!mounted) return;
        if (!available) {
          setState(() {
            _detailEmployeeNoAvailabilityError = 'Employee ID already exists';
          });
          AppScaffoldMessenger.of(context).showSnackBar(
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
      'displayName': [
        firstName,
        middleName,
        lastName,
      ].where((part) => part.trim().isNotEmpty).join(' ').trim(),
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

    final changedFields = <String>[];
    void markChanged(String label, dynamic oldValue, dynamic newValue) {
      final oldText = (oldValue ?? '').toString().trim();
      final newText = (newValue ?? '').toString().trim();
      if (oldText != newText) changedFields.add(label);
    }

    markChanged('First Name', beforeData['firstName'], firstName);
    markChanged('Middle Name', beforeData['middleName'], middleName);
    markChanged('Last Name', beforeData['lastName'], lastName);
    markChanged('Account Status', beforeData['accountStatus'], accountStatus);

    if (_isStudentRole(role)) {
      final oldStudent =
          beforeData['studentProfile'] as Map<String, dynamic>? ?? {};
      markChanged(
        'Student Number',
        oldStudent['studentNo'],
        _detailStudentNoCtrl.text.trim(),
      );
      markChanged(
        'College',
        oldStudent['collegeId'],
        _detailCollegeCtrl.text.trim(),
      );
      markChanged(
        'Program',
        oldStudent['programId'],
        _detailProgramCtrl.text.trim(),
      );
    } else {
      final oldEmployee =
          beforeData['employeeProfile'] as Map<String, dynamic>? ?? {};
      markChanged(
        'Employee ID',
        oldEmployee['employeeNo'],
        _detailEmployeeNoCtrl.text.trim(),
      );
      if (_roleNeedsDepartmentFor(role)) {
        markChanged(
          'Department',
          oldEmployee['department'],
          _detailDepartmentCtrl.text.trim(),
        );
      }
    }

    try {
      await userRef.update(update);
      if (changedFields.isNotEmpty) {
        await _appendUserProfileLog(
          targetUid: uid,
          action: 'edited',
          title: 'Profile updated',
          details: 'Updated fields: ${changedFields.join(', ')}.',
          payload: {'fields': changedFields, 'role': role},
        );
        if (_isStudentRole(role)) {
          const maxFieldsPreview = 6;
          final previewFields = changedFields.length > maxFieldsPreview
              ? changedFields.take(maxFieldsPreview).join(', ')
              : changedFields.join(', ');
          final more = changedFields.length > maxFieldsPreview
              ? ' and ${changedFields.length - maxFieldsPreview} more'
              : '';
          await _notifyUser(
            uid: uid,
            title: 'Profile Updated',
            body: 'An administrator updated your profile: $previewFields$more.',
            payload: {
              'type': 'profile_update',
              'source': 'user_management',
              'fields': changedFields,
            },
          );
        }
      }
      if (!mounted) return;
      setState(() => _detailEditing = false);
      AppScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User profile updated.')));
    } catch (e) {
      if (!mounted) return;
      AppScaffoldMessenger.of(
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
    bool required = false,
    bool readOnly = false,
  }) {
    return InputDecoration(
      label: Text.rich(
        TextSpan(
          text: label,
          style: const TextStyle(color: hintColor, fontWeight: FontWeight.w700),
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w900,
                ),
              ),
            if (readOnly)
              TextSpan(
                text: ' (Read-only)',
                style: TextStyle(
                  color: hintColor.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
          ],
        ),
      ),
      helperText: helperText,
      errorText: errorText,
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: primaryColor.withValues(alpha: 0.82), size: 20),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
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

  String _actorDisplayName() {
    final actorData = _currentUserData ?? const <String, dynamic>{};
    final fromProfile = _displayName(actorData).trim();
    if (fromProfile.isNotEmpty && fromProfile != '--') return fromProfile;
    final authEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    if (authEmail.trim().isNotEmpty) return authEmail.trim();
    return 'System';
  }

  String _formatLogDateTime(DateTime? date) {
    if (date == null) return '--';
    final local = date.toLocal();
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hour:$min';
  }

  Future<void> _appendUserProfileLog({
    required String targetUid,
    required String action,
    required String title,
    String? details,
    Map<String, dynamic>? payload,
  }) async {
    if (targetUid.trim().isEmpty) return;
    try {
      final actorUid = FirebaseAuth.instance.currentUser?.uid;
      final actorRole = (_currentUserData?['role'] ?? '').toString().trim();
      final actorName = _actorDisplayName();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .collection('profile_logs')
          .add({
            'action': action.trim().toLowerCase(),
            'title': title.trim(),
            'details': (details ?? '').trim(),
            'actorUid': actorUid,
            'actorName': actorName,
            'actorRole': actorRole,
            if (payload != null && payload.isNotEmpty) 'payload': payload,
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtEpochMs': DateTime.now().millisecondsSinceEpoch,
          });
    } catch (e) {
      debugPrint('Failed to append profile log for $targetUid: $e');
    }
  }

  Future<void> _notifyUser({
    required String uid,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(safeUid)
          .collection('notifications')
          .add({
            'title': title.trim(),
            'body': body.trim(),
            'payload': payload ?? const <String, dynamic>{},
            'createdAt': FieldValue.serverTimestamp(),
            'readAt': null,
          });
    } catch (e) {
      debugPrint('Failed to notify user $safeUid: $e');
    }
  }

  Widget _buildUserLogsList({
    required String uid,
    required String collection,
    required String emptyLabel,
    required String defaultTitle,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(collection)
          .orderBy('createdAtEpochMs', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(
            child: Text(
              'Could not load logs.',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: primaryColor),
          );
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              emptyLabel,
              style: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          itemCount: docs.length,
          separatorBuilder: (_, index) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final data = docs[index].data();
            final action = (data['action'] ?? data['event'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final title = (data['title'] ?? '').toString().trim();
            final details = (data['details'] ?? data['description'] ?? '')
                .toString()
                .trim();
            final actorName = (data['actorName'] ?? data['actor'] ?? 'System')
                .toString()
                .trim();
            final actorRole = (data['actorRole'] ?? '')
                .toString()
                .trim()
                .replaceAll('_', ' ');
            final createdAt =
                _asDate(data['createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(
                  (data['createdAtEpochMs'] as num?)?.toInt() ?? 0,
                );

            Color chipColor = Colors.blueGrey;
            switch (action) {
              case 'created':
              case 'create':
                chipColor = Colors.blue;
                break;
              case 'approved':
              case 'approve':
                chipColor = Colors.green;
                break;
              case 'rejected':
              case 'reject':
                chipColor = Colors.red;
                break;
              case 'edited':
              case 'edit':
              case 'updated':
                chipColor = Colors.orange;
                break;
              case 'logged_in':
              case 'login':
                chipColor = Colors.teal;
                break;
              case 'logged_out':
              case 'logout':
                chipColor = Colors.indigo;
                break;
            }

            return Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title.isEmpty ? defaultTitle : title,
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: chipColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(
                            color: chipColor.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          action.isEmpty
                              ? 'update'
                              : action.replaceAll('_', ' '),
                          style: TextStyle(
                            color: chipColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      details,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Text(
                    '${_formatLogDateTime(createdAt)} - $actorName${actorRole.isEmpty ? '' : ' (${_formatRole(actorRole.replaceAll(' ', '_'))})'}',
                    style: const TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showUserActivityLogsDialog({
    required String uid,
    required String displayName,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: widget.pageBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        color: primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Activity Logs - $displayName',
                          style: const TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: hintColor),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.10),
                            ),
                          ),
                          child: const TabBar(
                            indicatorColor: primaryColor,
                            labelColor: primaryColor,
                            unselectedLabelColor: hintColor,
                            labelStyle: TextStyle(fontWeight: FontWeight.w900),
                            tabs: [
                              Tab(text: 'Profile Logs'),
                              Tab(text: 'Login Logs'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildUserLogsList(
                                uid: uid,
                                collection: 'profile_logs',
                                emptyLabel: 'No profile logs yet.',
                                defaultTitle: 'Profile Update',
                              ),
                              _buildUserLogsList(
                                uid: uid,
                                collection: 'auth_logs',
                                emptyLabel: 'No login logs yet.',
                                defaultTitle: 'Session Activity',
                              ),
                            ],
                          ),
                        ),
                      ],
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

  void _onSearchInputChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final next = value.trim().toLowerCase();
      if (_searchQuery == next) return;
      setState(() => _searchQuery = next);
    });
  }

  void _clearSearchQuery() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    if (!mounted) return;
    if (_searchQuery.isNotEmpty) {
      setState(() => _searchQuery = '');
    }
  }

  Future<void> _refreshCurrentTable() async {
    if (_isRefreshingTable || !mounted) return;
    setState(() => _isRefreshingTable = true);
    _invalidateFilterCache();
    setState(() {
      _allUsersStream = FirebaseFirestore.instance
          .collection('users')
          .snapshots();
    });
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _isRefreshingTable = false);
  }

  Widget _buildHandbookStyleSearchBar({Widget? compactTrailingAction}) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1000;
    final shouldConstrainWidth = width >= 900;
    final constrainedWidth = width >= 1600
        ? 640.0
        : width >= 1300
        ? 580.0
        : 520.0;
    final height = isDesktop ? 56.0 : 48.0;
    final borderRadius = isDesktop ? 16.0 : 18.0;
    final iconSize = isDesktop ? 24.0 : 22.0;
    final fontSize = isDesktop ? 15.0 : 13.5;

    final searchField = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchCtrl,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;

        return Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.black12),
            boxShadow: isDesktop
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: hintColor, size: iconSize),
              SizedBox(width: isDesktop ? 12 : 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchInputChanged,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by name, ID, or email...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(
                      color: hintColor,
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
              if (hasText)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: _clearSearchQuery,
                  icon: Icon(
                    Icons.close_rounded,
                    color: hintColor.withValues(alpha: 0.85),
                    size: isDesktop ? 20 : 18,
                  ),
                ),
            ],
          ),
        );
      },
    );

    final refreshButton = Tooltip(
      message: 'Refresh table',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _isRefreshingTable ? null : _refreshCurrentTable,
        child: Container(
          width: height,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.75),
            border: Border.all(color: Colors.black12),
            boxShadow: isDesktop
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: _isRefreshingTable
              ? SizedBox(
                  width: isDesktop ? 18 : 16,
                  height: isDesktop ? 18 : 16,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: hintColor,
                  ),
                )
              : Icon(
                  Icons.refresh_rounded,
                  color: hintColor.withValues(alpha: 0.9),
                  size: isDesktop ? 20 : 18,
                ),
        ),
      ),
    );

    Widget searchWithRefresh() {
      return Row(
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 8),
          refreshButton,
          if (!isDesktop && compactTrailingAction != null) ...[
            const SizedBox(width: 8),
            compactTrailingAction,
          ],
        ],
      );
    }

    if (!shouldConstrainWidth) return searchWithRefresh();
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: constrainedWidth, child: searchWithRefresh()),
    );
  }

  Widget? _buildFullHeaderActions({
    required bool showImportStudentButton,
    required bool showStudentsOnly,
    required bool showProfessorsOnly,
    required bool useCompactHeaderActions,
  }) {
    if (widget.hideCreateAction || useCompactHeaderActions) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showImportStudentButton) ...[
          OutlinedButton.icon(
            onPressed: _submitting ? null : _openImportStudents,
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryColor,
              side: BorderSide(color: primaryColor.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
            icon: const Icon(Icons.upload_file_rounded, size: 20),
            label: const Text(
              'Import Student',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
        ],
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            elevation: 2,
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
          label: Text(
            showStudentsOnly
                ? 'Create Student'
                : (showProfessorsOnly ? 'Create Professor' : 'Create New User'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ),
      ],
    );
  }

  Widget? _buildCompactHeaderOptionsButton({
    required bool showImportStudentButton,
    required bool showStudentsOnly,
    required bool showProfessorsOnly,
    required bool useCompactHeaderActions,
  }) {
    if (widget.hideCreateAction || !useCompactHeaderActions) return null;
    return Tooltip(
      message: 'More options',
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.75),
          border: Border.all(color: Colors.black12),
        ),
        child: PopupMenuButton<_HeaderQuickAction>(
          tooltip: 'More options',
          enabled: !_submitting,
          padding: EdgeInsets.zero,
          icon: const Icon(
            Icons.more_horiz_rounded,
            color: hintColor,
            size: 20,
          ),
          onSelected: (action) {
            if (action == _HeaderQuickAction.importStudents) {
              _openImportStudents();
              return;
            }
            _openCreateUser();
          },
          itemBuilder: (context) {
            final items = <PopupMenuEntry<_HeaderQuickAction>>[];
            if (showImportStudentButton) {
              items.add(
                const PopupMenuItem<_HeaderQuickAction>(
                  value: _HeaderQuickAction.importStudents,
                  child: Row(
                    children: [
                      Icon(Icons.upload_file_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Import Student'),
                    ],
                  ),
                ),
              );
            }
            items.add(
              PopupMenuItem<_HeaderQuickAction>(
                value: _HeaderQuickAction.createUser,
                child: Row(
                  children: [
                    const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      showStudentsOnly
                          ? 'Create Student'
                          : (showProfessorsOnly
                                ? 'Create Professor'
                                : 'Create User'),
                    ),
                  ],
                ),
              ),
            );
            return items;
          },
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredUsersMemoized({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> rawDocs,
    required Object snapshotToken,
    required String type,
    required String query,
    required String adminRole,
    required String adminDept,
  }) {
    final cacheHit =
        identical(_filterCacheSourceToken, snapshotToken) &&
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

          if (widget.studentsOnlyScope && role != 'student') return false;
          if (widget.professorsOnlyScope && role != 'professor') return false;
          if (type == 'pending_approval_queue') {
            return role == 'student' &&
                accountStatus == 'active' &&
                studentVerification == 'pending_approval' &&
                _matchesSearch(data, query);
          }

          if (type == 'staff' && role == 'student') return false;
          if (type == 'active_staff' && role == 'student') return false;
          if (type == 'inactive_staff' && role == 'student') return false;
          if (type == 'active_staff' && accountStatus != 'active') return false;
          if (type == 'inactive_staff' && accountStatus != 'inactive') {
            return false;
          }
          if ((type == 'students' || type == 'active_students') &&
              role != 'student') {
            return false;
          }
          if (type == 'active_students' &&
              !(accountStatus == 'active' &&
                  studentVerification == 'verified')) {
            return false;
          }
          if (type == 'active_students' &&
              _hasPendingEmailVerification(data, role: role)) {
            return false;
          }
          if (type == 'pending') {
            final matchesVerification =
                _pendingStudentFilter == 'pending_email_verification'
                ? (_hasPendingEmailVerification(data, role: role) ||
                      studentVerification == _pendingStudentFilter)
                : studentVerification == _pendingStudentFilter;
            final canShowByAccountStatus = _pendingStudentFilter == 'rejected'
                ? true
                : accountStatus == 'active';
            if (!(role == 'student' &&
                canShowByAccountStatus &&
                matchesVerification)) {
              return false;
            }
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

    _filterCacheSourceToken = snapshotToken;
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
    final studentsOnly = widget.studentsOnlyScope;
    final professorsOnly = widget.professorsOnlyScope;

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
        forcedRole: professorsOnly ? 'professor' : null,
      ),
    );
    if (res == null || !mounted) return;

    try {
      setState(() => _submitting = true);
      await _createAuthAndUserDoc(res);
      if (!mounted) return;
      final entityLabel = studentsOnly
          ? 'student'
          : (professorsOnly ? 'professor' : 'user');
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created $entityLabel: ${res.email}')),
      );
    } catch (e) {
      if (!mounted) return;
      final entityLabel = studentsOnly
          ? 'student'
          : (professorsOnly ? 'professor' : 'user');
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

      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Create $entityLabel failed: $msg'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openImportStudents() async {
    if (!mounted) return;

    final dialogResult = await showDialog<_StudentImportDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _StudentBulkImportDialog(onValidateCsv: _validateStudentImportCsv),
    );
    if (dialogResult == null || dialogResult.rows.isEmpty || !mounted) return;

    try {
      setState(() => _submitting = true);
      final commit = await _commitStudentImportRows(dialogResult.rows);
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import complete: ${commit.created} created, ${commit.updated} updated, ${dialogResult.invalidCount} invalid skipped.',
          ),
          backgroundColor: primaryColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _importKey(String raw) {
    return raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  List<List<String>> _parseCsvRows(String csvText) {
    final rows = <List<String>>[];
    final row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < csvText.length; i++) {
      final ch = csvText[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < csvText.length && csvText[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (!inQuotes && ch == ',') {
        row.add(cell.toString().trim());
        cell.clear();
        continue;
      }

      if (!inQuotes && (ch == '\n' || ch == '\r')) {
        if (ch == '\r' && i + 1 < csvText.length && csvText[i + 1] == '\n') {
          i++;
        }
        row.add(cell.toString().trim());
        cell.clear();
        if (row.any((v) => v.trim().isNotEmpty)) {
          rows.add(List<String>.from(row));
        }
        row.clear();
        continue;
      }

      cell.write(ch);
    }

    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString().trim());
      if (row.any((v) => v.trim().isNotEmpty)) {
        rows.add(List<String>.from(row));
      }
    }

    return rows;
  }

  String _csvCell(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  String _titleCaseWords(String input) {
    final value = input.trim();
    if (value.isEmpty) return '';
    return value
        .split(RegExp(r'\s+'))
        .map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1).toLowerCase();
        })
        .join(' ');
  }

  String _displayNameFromParts({
    required String firstName,
    required String middleName,
    required String lastName,
  }) {
    return [
      firstName.trim(),
      middleName.trim(),
      lastName.trim(),
    ].where((p) => p.isNotEmpty).join(' ').trim();
  }

  bool _isValidImportEmail(String email) {
    final value = email.trim().toLowerCase();
    if (value.isEmpty) return true;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  int? _headerIndex(Map<String, int> headerIndexByKey, List<String> aliases) {
    for (final alias in aliases) {
      final index = headerIndexByKey[_importKey(alias)];
      if (index != null) return index;
    }
    return null;
  }

  Future<_StudentImportValidationResult> _validateStudentImportCsv(
    String csvText,
  ) async {
    final cleaned = csvText.replaceFirst('\uFEFF', '').trim();
    if (cleaned.isEmpty) {
      return const _StudentImportValidationResult(
        totalRows: 0,
        validRows: [],
        issues: [
          _StudentImportIssue(
            rowNumber: 0,
            message: 'The file is empty. Please upload a CSV with data rows.',
          ),
        ],
      );
    }

    final rows = _parseCsvRows(cleaned);
    if (rows.isEmpty) {
      return const _StudentImportValidationResult(
        totalRows: 0,
        validRows: [],
        issues: [
          _StudentImportIssue(
            rowNumber: 0,
            message: 'Unable to read rows from CSV. Check the file format.',
          ),
        ],
      );
    }

    final header = rows.first;
    final headerIndexByKey = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final key = _importKey(header[i]);
      if (key.isEmpty) continue;
      headerIndexByKey.putIfAbsent(key, () => i);
    }

    final idxStudentNo = _headerIndex(headerIndexByKey, [
      'studentNo',
      'student_number',
      'student number',
      'student id',
    ]);
    final idxFirstName = _headerIndex(headerIndexByKey, [
      'firstName',
      'first_name',
      'first name',
      'given name',
    ]);
    final idxMiddleName = _headerIndex(headerIndexByKey, [
      'middleName',
      'middle_name',
      'middle name',
    ]);
    final idxLastName = _headerIndex(headerIndexByKey, [
      'lastName',
      'last_name',
      'last name',
      'surname',
      'family name',
    ]);
    final idxCollege = _headerIndex(headerIndexByKey, [
      'college',
      'collegeId',
      'college id',
      'college code',
    ]);
    final idxProgram = _headerIndex(headerIndexByKey, [
      'program',
      'programId',
      'program id',
      'program code',
      'course',
    ]);
    final idxEmail = _headerIndex(headerIndexByKey, [
      'email',
      'emailAddress',
      'email address',
    ]);

    final missingHeaders = <String>[
      if (idxStudentNo == null) 'studentNo',
      if (idxFirstName == null) 'firstName',
      if (idxLastName == null) 'lastName',
      if (idxCollege == null) 'college',
      if (idxProgram == null) 'program',
    ];
    if (missingHeaders.isNotEmpty) {
      return _StudentImportValidationResult(
        totalRows: rows.length <= 1 ? 0 : rows.length - 1,
        validRows: const [],
        issues: [
          _StudentImportIssue(
            rowNumber: 0,
            message:
                'Missing required header(s): ${missingHeaders.join(', ')}.',
          ),
        ],
      );
    }

    final db = FirebaseFirestore.instance;
    final collegeSnap = await db
        .collection('colleges')
        .where('active', isEqualTo: true)
        .get();
    final programSnap = await db
        .collection('programs')
        .where('active', isEqualTo: true)
        .get();
    final usersSnap = await db.collection('users').get();

    final collegeLookup = <String, String>{};
    for (final doc in collegeSnap.docs) {
      final data = doc.data();
      final collegeId = doc.id.trim();
      final code = (data['collegeCode'] ?? '').toString().trim();
      final name = (data['name'] ?? data['collegeName'] ?? data['title'] ?? '')
          .toString()
          .trim();
      for (final raw in [collegeId, code, name]) {
        final key = _importKey(raw);
        if (key.isEmpty) continue;
        collegeLookup[key] = collegeId;
      }
    }

    final programsByCollegeAndKey = <String, String>{};
    for (final doc in programSnap.docs) {
      final data = doc.data();
      final programId = doc.id.trim();
      final collegeId = (data['collegeId'] ?? '').toString().trim();
      final code = (data['programCode'] ?? '').toString().trim();
      final name = (data['name'] ?? data['programName'] ?? data['title'] ?? '')
          .toString()
          .trim();
      for (final raw in [programId, code, name]) {
        final key = _importKey(raw);
        if (key.isEmpty || collegeId.isEmpty) continue;
        programsByCollegeAndKey['$collegeId::$key'] = programId;
      }
    }

    final existingStudentNoToUid = <String, String>{};
    final existingEmailToUid = <String, String>{};
    for (final doc in usersSnap.docs) {
      final data = doc.data();
      final role = (data['role'] ?? '').toString().trim().toLowerCase();
      if (role == 'student') {
        final profile = data['studentProfile'] as Map<String, dynamic>?;
        final studentNo = (profile?['studentNo'] ?? data['studentNo'] ?? '')
            .toString()
            .trim();
        if (studentNo.isNotEmpty) {
          existingStudentNoToUid.putIfAbsent(studentNo, () => doc.id);
        }
      }
      final email = (data['email'] ?? '').toString().trim().toLowerCase();
      if (email.isNotEmpty) {
        existingEmailToUid.putIfAbsent(email, () => doc.id);
      }
    }

    final issues = <_StudentImportIssue>[];
    final valids = <_ImportedStudentDraft>[];
    final seenStudentNos = <String>{};
    final seenEmails = <String>{};

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowNumber = i + 1;

      final studentNo = _csvCell(row, idxStudentNo);
      final firstName = _titleCaseWords(_csvCell(row, idxFirstName));
      final middleName = _titleCaseWords(_csvCell(row, idxMiddleName));
      final lastName = _titleCaseWords(_csvCell(row, idxLastName));
      final collegeRaw = _csvCell(row, idxCollege);
      final programRaw = _csvCell(row, idxProgram);
      final email = _csvCell(row, idxEmail).toLowerCase();

      final isCompletelyBlank = [
        studentNo,
        firstName,
        middleName,
        lastName,
        collegeRaw,
        programRaw,
        email,
      ].every((v) => v.trim().isEmpty);
      if (isCompletelyBlank) continue;

      final rowErrors = <String>[];
      if (studentNo.isEmpty) rowErrors.add('Student Number is required.');
      if (firstName.isEmpty) rowErrors.add('First Name is required.');
      if (lastName.isEmpty) rowErrors.add('Last Name is required.');
      if (collegeRaw.isEmpty) rowErrors.add('College is required.');
      if (programRaw.isEmpty) rowErrors.add('Program is required.');

      if (studentNo.isNotEmpty &&
          !RegExp(r'^\d{3}-\d{4}$').hasMatch(studentNo)) {
        rowErrors.add('Student Number must follow 123-1234 format.');
      }
      if (studentNo.isNotEmpty && !seenStudentNos.add(studentNo)) {
        rowErrors.add('Duplicate Student Number inside file.');
      }

      if (email.isNotEmpty) {
        if (!_isValidImportEmail(email)) {
          rowErrors.add('Invalid email format.');
        } else if (!seenEmails.add(email)) {
          rowErrors.add('Duplicate email inside file.');
        }
      }

      final collegeId = collegeLookup[_importKey(collegeRaw)] ?? '';
      if (collegeRaw.isNotEmpty && collegeId.isEmpty) {
        rowErrors.add('Unknown college: "$collegeRaw".');
      }

      final programId =
          programsByCollegeAndKey['$collegeId::${_importKey(programRaw)}'] ??
          '';
      if (programRaw.isNotEmpty && (collegeId.isEmpty || programId.isEmpty)) {
        rowErrors.add(
          collegeId.isEmpty
              ? 'Program cannot be resolved without a valid college.'
              : 'Unknown program "$programRaw" for selected college.',
        );
      }

      final existingUid = existingStudentNoToUid[studentNo];
      if (email.isNotEmpty) {
        final existingUidByEmail = existingEmailToUid[email];
        if (existingUidByEmail != null && existingUidByEmail != existingUid) {
          rowErrors.add('Email is already used by another account.');
        }
      }

      if (rowErrors.isNotEmpty) {
        issues.add(
          _StudentImportIssue(
            rowNumber: rowNumber,
            studentNo: studentNo,
            fullName: _displayNameFromParts(
              firstName: firstName,
              middleName: middleName,
              lastName: lastName,
            ),
            message: rowErrors.join(' '),
          ),
        );
        continue;
      }

      valids.add(
        _ImportedStudentDraft(
          rowNumber: rowNumber,
          studentNo: studentNo,
          firstName: firstName,
          middleName: middleName,
          lastName: lastName,
          collegeId: collegeId,
          programId: programId,
          email: email,
          existingUid: existingUid,
        ),
      );
    }

    return _StudentImportValidationResult(
      totalRows: rows.length <= 1 ? 0 : rows.length - 1,
      validRows: valids,
      issues: issues,
    );
  }

  Future<_StudentImportCommitResult> _commitStudentImportRows(
    List<_ImportedStudentDraft> rows,
  ) async {
    var created = 0;
    var updated = 0;

    final db = FirebaseFirestore.instance;
    final createdByUid = FirebaseAuth.instance.currentUser?.uid;

    WriteBatch batch = db.batch();
    var pendingWrites = 0;

    Future<void> flushIfNeeded({bool force = false}) async {
      if (!force && pendingWrites < 400) return;
      if (pendingWrites == 0) return;
      await batch.commit();
      batch = db.batch();
      pendingWrites = 0;
    }

    for (final row in rows) {
      final docRef = row.existingUid == null
          ? db.collection('users').doc()
          : db.collection('users').doc(row.existingUid!);

      final displayName = _displayNameFromParts(
        firstName: row.firstName,
        middleName: row.middleName,
        lastName: row.lastName,
      );

      if (row.existingUid == null) {
        final verification = row.email.isEmpty
            ? 'pending_profile'
            : 'pending_email_verification';
        final status = _legacyStatusValue(
          role: 'student',
          accountStatus: 'active',
          studentVerificationStatus: verification,
        );

        batch.set(docRef, {
          'uid': docRef.id,
          'email': row.email.isEmpty ? null : row.email,
          'firstName': row.firstName,
          'middleName': row.middleName.isEmpty ? null : row.middleName,
          'lastName': row.lastName,
          'displayName': displayName.isEmpty ? null : displayName,
          'role': 'student',
          'accountStatus': 'active',
          'studentVerificationStatus': verification,
          'status': status,
          'createdByAdmin': true,
          'importedByAdmin': true,
          'directoryVisible': true,
          if (createdByUid != null) 'createdByUid': createdByUid,
          'studentProfile': {
            'studentNo': row.studentNo,
            'collegeId': row.collegeId,
            'programId': row.programId,
          },
          'employeeProfile': {'employeeNo': null, 'department': null},
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        created++;
      } else {
        final update = <String, dynamic>{
          'firstName': row.firstName,
          'middleName': row.middleName.isEmpty ? null : row.middleName,
          'lastName': row.lastName,
          'displayName': displayName.isEmpty ? null : displayName,
          'importedByAdmin': true,
          'directoryVisible': true,
          'studentProfile': {
            'studentNo': row.studentNo,
            'collegeId': row.collegeId,
            'programId': row.programId,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (row.email.isNotEmpty) {
          update['email'] = row.email;
        }
        batch.set(docRef, update, SetOptions(merge: true));
        updated++;
      }

      pendingWrites++;
      await flushIfNeeded();
    }

    await flushIfNeeded(force: true);
    return _StudentImportCommitResult(created: created, updated: updated);
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
      final middleName = toTitleCase(input.middleName);
      final lastName = toTitleCase(input.lastName);
      final displayName = [
        firstName,
        middleName,
        lastName,
      ].where((p) => p.trim().isNotEmpty).join(' ').trim();

      final isStudent = _isStudentRole(input.role);
      final normalizedAccountStatus = _normalizeAccountStatus('active');
      final normalizedStudentVerification = isStudent
          ? 'pending_email_verification'
          : null;
      final legacyStatus = _legacyStatusValue(
        role: input.role,
        accountStatus: normalizedAccountStatus,
        studentVerificationStatus: normalizedStudentVerification,
      );
      final createdByUid = FirebaseAuth.instance.currentUser?.uid;
      String? uploadedPhotoUrl;
      if (input.profilePhoto != null) {
        uploadedPhotoUrl = await _uploadCreatedUserProfilePhoto(
          uid: createdUser.uid,
          picked: input.profilePhoto!,
        );
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(createdUser.uid)
          .set({
            'uid': createdUser.uid,
            'email': input.email,
            'firstName': firstName.isEmpty ? null : firstName,
            'middleName': middleName.isEmpty ? null : middleName,
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
            if (uploadedPhotoUrl != null && uploadedPhotoUrl.isNotEmpty)
              'photoUrl': uploadedPhotoUrl,

            // ✅ NEW: Initialize Profile Objects with more detail
            'studentProfile': {
              'studentNo': input.studentNo.isEmpty ? null : input.studentNo,
              'collegeId': input.collegeId,
              'programId': input.programId,
            },
            'employeeProfile': {
              'employeeNo': input.employeeNo.isEmpty ? null : input.employeeNo,
              'department': input.department.isEmpty ? null : input.department,
            },

            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      await _appendUserProfileLog(
        targetUid: createdUser.uid,
        action: 'created',
        title: 'Account created',
        details: 'Account created by admin.',
        payload: {
          'role': input.role,
          if (input.studentNo.trim().isNotEmpty)
            'studentNo': input.studentNo.trim(),
          if (input.employeeNo.trim().isNotEmpty)
            'employeeNo': input.employeeNo.trim(),
        },
      );

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

  Future<String> _uploadCreatedUserProfilePhoto({
    required String uid,
    required XFile picked,
  }) async {
    final filename = picked.name.isNotEmpty ? picked.name : picked.path;
    final ext = _imageExt(filename);
    final ref = FirebaseStorage.instance.ref(
      'users/$uid/profile/profile_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    final metadata = SettableMetadata(contentType: _imageContentType(ext));

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      await ref.putData(bytes, metadata);
    } else {
      final file = File(picked.path);
      await ref.putFile(file, metadata);
    }

    return ref.getDownloadURL();
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

      if (customLink.isNotEmpty) {
        // Link generated/handled by backend; no modal popup after account creation.
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
      if (verifyLink.isNotEmpty) {
        // Link generated/handled by backend; no modal popup after account creation.
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

  Future<String?> _showRejectReasonDialog() async {
    final reasonCtrl = TextEditingController();
    String? reasonError;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final hasText = reasonCtrl.text.trim().isNotEmpty;
          return AlertDialog(
            backgroundColor: widget.pageBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reject Student Profile',
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please provide a clear reason so the student knows what to correct.',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4F4),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.redAccent,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This action keeps the account in review and asks the student to update profile details.',
                          style: TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.2,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  onChanged: (_) {
                    if (reasonError != null &&
                        reasonCtrl.text.trim().isNotEmpty) {
                      setModalState(() => reasonError = null);
                    } else {
                      setModalState(() {});
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Reason for rejection',
                    hintText:
                        'Example: Student is not enrolled in this department.',
                    errorText: reasonError,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppRadii.md),
                      ),
                      borderSide: BorderSide(color: primaryColor, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  final reason = reasonCtrl.text.trim();
                  if (reason.isEmpty) {
                    setModalState(
                      () => reasonError = 'Reject reason is required.',
                    );
                    return;
                  }
                  Navigator.pop(ctx, reason);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(
                  hasText ? 'Reject Profile' : 'Reject',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          );
        },
      ),
    );
    reasonCtrl.dispose();
    return result;
  }

  Future<void> _reviewPendingStudent({
    required String uid,
    required bool approve,
    String? rejectReason,
  }) async {
    try {
      final reviewerUid = FirebaseAuth.instance.currentUser?.uid;
      final update = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewDecision': approve ? 'approved' : 'rejected',
        'status': approve ? 'verified' : 'rejected',
        'accountStatus': 'active',
        'studentVerificationStatus': approve ? 'verified' : 'rejected',
      };
      if (reviewerUid != null) update['reviewedByUid'] = reviewerUid;
      if (approve) {
        update['reviewReason'] = FieldValue.delete();
      } else {
        update['reviewReason'] = (rejectReason ?? '').trim();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(update);
      await _appendUserProfileLog(
        targetUid: uid,
        action: approve ? 'approved' : 'rejected',
        title: approve ? 'Profile approved' : 'Profile rejected',
        details: approve
            ? 'Student profile approved by reviewer.'
            : 'Student profile rejected. Reason: ${(rejectReason ?? '').trim()}',
        payload: {
          'decision': approve ? 'approved' : 'rejected',
          if (!approve && (rejectReason ?? '').trim().isNotEmpty)
            'reason': (rejectReason ?? '').trim(),
        },
      );
      await _notifyUser(
        uid: uid,
        title: approve ? 'Profile Approved' : 'Profile Rejected',
        body: approve
            ? 'Your profile has been approved. You may now access student features.'
            : 'Your profile was rejected. Please review the reason and update your details.',
        payload: {
          'type': 'profile_review',
          'decision': approve ? 'approved' : 'rejected',
          if (!approve && (rejectReason ?? '').trim().isNotEmpty)
            'reason': (rejectReason ?? '').trim(),
        },
      );
      if (!mounted) return;
      _invalidateFilterCache();
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Student profile approved.' : 'Student profile rejected.',
          ),
          backgroundColor: approve
              ? Colors.green.shade700
              : Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Review failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final showStudentsOnly =
        widget.studentsOnlyScope || widget.pendingApprovalOnlyScope;
    final showProfessorsOnly = widget.professorsOnlyScope;
    // Keep the same compact header layout style used by Student Management
    // so search/actions/tabs align consistently across management pages.
    const showHeaderTitleSection = false;
    final showImportStudentButton =
        showStudentsOnly && !widget.pendingApprovalOnlyScope;
    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompactHeaderActions =
            !widget.hideCreateAction && constraints.maxWidth < 900;
        final detailsPaneWidth = (constraints.maxWidth * 0.33)
            .clamp(320.0, 420.0)
            .toDouble();

        return Scaffold(
          backgroundColor: widget.pageBackgroundColor,
          body: ModernTableLayout(
            detailsWidth: detailsPaneWidth,
            header: ModernTableHeader(
              title: widget.headerTitle ?? 'User Management',
              subtitle:
                  widget.headerSubtitle ??
                  (widget.pendingApprovalOnlyScope
                      ? 'Review, approve, or reject pending students'
                      : showStudentsOnly
                      ? 'Manage students under your department'
                      : showProfessorsOnly
                      ? 'Manage professors under your department'
                      : 'Control access and verify accounts'),
              showTitleSection: showHeaderTitleSection,
              showTopControlsWhenTitleHidden: !showHeaderTitleSection,
              action: _buildFullHeaderActions(
                showImportStudentButton: showImportStudentButton,
                showStudentsOnly: showStudentsOnly,
                showProfessorsOnly: showProfessorsOnly,
                useCompactHeaderActions: useCompactHeaderActions,
              ),
              searchBar: _buildHandbookStyleSearchBar(
                compactTrailingAction: _buildCompactHeaderOptionsButton(
                  showImportStudentButton: showImportStudentButton,
                  showStudentsOnly: showStudentsOnly,
                  showProfessorsOnly: showProfessorsOnly,
                  useCompactHeaderActions: useCompactHeaderActions,
                ),
              ),
              tabs: widget.pendingApprovalOnlyScope
                  ? null
                  : _buildManagementTabs(
                      showStudentsOnly: showStudentsOnly,
                      showProfessorsOnly: showProfessorsOnly,
                    ),
            ),
            body: widget.pendingApprovalOnlyScope
                ? _buildUserList('pending_approval_queue')
                : showStudentsOnly && _studentsOnlyListType() == 'pending'
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
            showDetails: _selectedUserId != null,
            details: _selectedUserId != null
                ? ValueListenableBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>
                  >(
                    valueListenable: _visibleUserDocs,
                    builder: (context, docs, _) {
                      QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
                      for (final doc in docs) {
                        if (doc.id == _selectedUserId) {
                          selectedDoc = doc;
                          break;
                        }
                      }
                      if (selectedDoc == null) {
                        return const SizedBox();
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: _buildDesktopDetailsPanel(
                          selectedDoc: selectedDoc,
                        ),
                      );
                    },
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildUserList(String type) {
    // Use one base stream for both pages so initial paint/caching behavior
    // stays consistent between User Management and Student Management.
    final stream = _allUsersStream;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (snap.hasData) {
          _lastUserDocs = snap.data!.docs;
        }
        final allDocs = snap.data?.docs ?? _lastUserDocs;
        if (allDocs.isEmpty &&
            snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final needsAllDocsSync = !listEquals(_allUserDocs.value, allDocs);
        if (needsAllDocsSync) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!listEquals(_allUserDocs.value, allDocs)) {
              _allUserDocs.value = allDocs;
            }
          });
        }

        final q = _searchQuery;

        final adminRole = (_currentUserData?['role'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final adminDept =
            (_currentUserData?['employeeProfile']?['department'] ?? '')
                .toString();

        final filtered = _filteredUsersMemoized(
          rawDocs: allDocs,
          snapshotToken: allDocs,
          type: type,
          query: q,
          adminRole: adminRole,
          adminDept: adminDept,
        );
        final needsVisibleDocsSync = !listEquals(
          _visibleUserDocs.value,
          filtered,
        );
        if (needsVisibleDocsSync) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!listEquals(_visibleUserDocs.value, filtered)) {
              _visibleUserDocs.value = filtered;
            }
          });
        }
        final selectedMissing =
            _selectedUserId != null &&
            !filtered.any((doc) => doc.id == _selectedUserId);
        if (selectedMissing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _selectedUserId == null) return;
            final stillMissing = !filtered.any(
              (doc) => doc.id == _selectedUserId,
            );
            if (stillMissing) {
              _clearDetailSelection();
            }
          });
        } else if (_selectedUserId != null) {
          QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
          for (final doc in filtered) {
            if (doc.id == _selectedUserId) {
              selectedDoc = doc;
              break;
            }
          }
          if (selectedDoc != null && _detailLoadedUserId != selectedDoc.id) {
            final doc = selectedDoc;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_selectedUserId != doc.id) return;
              _loadDetailFromData(doc.id, doc.data());
            });
          }
        }

        if (filtered.isEmpty) {
          final emptyLabel = widget.studentsOnlyScope
              ? 'No students found'
              : (widget.professorsOnlyScope
                    ? 'No professors found'
                    : 'No users found');
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
                  emptyLabel,
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

        final useDesktopTable = MediaQuery.sizeOf(context).width >= 900;
        if (useDesktopTable) {
          return _buildDesktopTable(filtered, type: type);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final doc = filtered[i];
            final data = doc.data();
            return _buildUserCard(doc.id, data, listType: type);
          },
        );
      },
    );
  }

  Widget _buildDesktopTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String type,
  }) {
    final hideRoleInStudentViews =
        widget.studentsOnlyScope || widget.pendingApprovalOnlyScope;
    final showAccountStatusColumn =
        type != 'pending' &&
        type != 'pending_approval_queue' &&
        type != 'active_students';
    final showVerificationColumn =
        type == 'students' || type == 'active_students';
    final showRoleColumn = !hideRoleInStudentViews;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = constraints.maxWidth;
            final detailsPaneVisible =
                _selectedUserId != null &&
                MediaQuery.sizeOf(context).width >=
                    ResponsiveBreakpoints.splitDetails;
            final compactTable = detailsPaneVisible || tableWidth < 1120;
            final tableHorizontalMargin = compactTable ? 8.0 : 12.0;
            final tableColumnSpacing = compactTable ? 12.0 : 24.0;
            final columnCount =
                3 +
                (showRoleColumn ? 1 : 0) +
                (showAccountStatusColumn ? 1 : 0) +
                (showVerificationColumn ? 1 : 0);
            const nameWeight = 2.4;
            const emailWeight = 2.8;
            const idWeight = 1.2;
            const roleWeight = 1.3;
            const accountStatusWeight = 1.2;
            const verificationWeight = 1.5;
            final totalWeight =
                nameWeight +
                emailWeight +
                idWeight +
                (showRoleColumn ? roleWeight : 0) +
                (showAccountStatusColumn ? accountStatusWeight : 0) +
                (showVerificationColumn ? verificationWeight : 0);
            final usableWidth =
                (tableWidth -
                        (tableHorizontalMargin * 2) -
                        (tableColumnSpacing * (columnCount - 1)))
                    .clamp(420.0, double.infinity)
                    .toDouble();
            double colWidth(
              double weight,
              double minWidth, {
              double? compactMinWidth,
            }) {
              final value = usableWidth * (weight / totalWeight);
              final effectiveMin = compactTable
                  ? (compactMinWidth ?? minWidth)
                  : minWidth;
              return value < effectiveMin ? effectiveMin : value;
            }

            final nameColWidth = colWidth(
              nameWeight,
              190,
              compactMinWidth: 164,
            );
            final emailColWidth = colWidth(
              emailWeight,
              220,
              compactMinWidth: 180,
            );
            final idColWidth = colWidth(idWeight, 120, compactMinWidth: 100);
            final roleColWidth = showRoleColumn
                ? colWidth(roleWeight, 130, compactMinWidth: 110)
                : 0.0;
            final accountStatusColWidth = showAccountStatusColumn
                ? colWidth(accountStatusWeight, 130, compactMinWidth: 108)
                : 0.0;
            final verificationColWidth = showVerificationColumn
                ? colWidth(verificationWeight, 170, compactMinWidth: 132)
                : 0.0;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(
                    widget.pageBackgroundColor,
                  ),
                  horizontalMargin: tableHorizontalMargin,
                  columnSpacing: tableColumnSpacing,
                  columns: [
                    DataColumn(
                      label: SizedBox(
                        width: nameColWidth,
                        child: Text(
                          'NAME',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: emailColWidth,
                        child: Text(
                          'EMAIL',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: idColWidth,
                        child: Text(
                          'ID NUMBER',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: hintColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    if (showRoleColumn)
                      DataColumn(
                        label: SizedBox(
                          width: roleColWidth,
                          child: Text(
                            'ROLE',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: hintColor,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    if (showAccountStatusColumn)
                      DataColumn(
                        label: SizedBox(
                          width: accountStatusColWidth,
                          child: Text(
                            'STATUS',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: hintColor,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    if (showVerificationColumn)
                      DataColumn(
                        label: SizedBox(
                          width: verificationColWidth,
                          child: Text(
                            'VERIFICATION STATUS',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: hintColor,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
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
                    final accountStatus = _readAccountStatus(data, role: role);
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
                        final canShowSideDetails =
                            MediaQuery.sizeOf(context).width >=
                            ResponsiveBreakpoints.splitDetails;
                        if (!canShowSideDetails && selected) {
                          _openMobileProfileDetailsSheet(
                            uid: doc.id,
                            data: data,
                          );
                          return;
                        }
                        if (!selected) {
                          if (!_detailEditing) {
                            _clearDetailSelection();
                          }
                          return;
                        }
                        if (_selectedUserId == doc.id) {
                          if (!_detailEditing) {
                            _clearDetailSelection();
                          }
                          return;
                        }
                        _loadDetailFromData(doc.id, data);
                      },
                      cells: [
                        DataCell(
                          SizedBox(
                            width: nameColWidth,
                            child: Row(
                              children: [
                                _buildUserAvatar(
                                  data,
                                  name,
                                  radius: 14,
                                  fontSize: 10,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: emailColWidth,
                            child: Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: idColWidth,
                            child: Text(
                              id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        if (showRoleColumn)
                          DataCell(
                            SizedBox(
                              width: roleColWidth,
                              child: Text(
                                _formatRole(role),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: textDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        if (showAccountStatusColumn)
                          DataCell(
                            SizedBox(
                              width: accountStatusColWidth,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _buildStatusChip(
                                  accountStatus,
                                  compact: true,
                                ),
                              ),
                            ),
                          ),
                        if (showVerificationColumn)
                          DataCell(
                            SizedBox(
                              width: verificationColWidth,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _buildVerificationChip(
                                  studentVerification,
                                  compact: true,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktopDetailsPanel({
    required QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc,
    VoidCallback? onClose,
  }) {
    if (selectedDoc == null) {
      return const SizedBox.shrink();
    }
    final isLoadingSelection = _detailLoadedUserId != selectedDoc.id;
    if (isLoadingSelection) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
                SizedBox(height: 10),
                Text(
                  'Loading profile details...',
                  style: TextStyle(
                    color: hintColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = selectedDoc.data();
    final detailName = _displayName(data);
    final isStudent = _isStudentRole(_detailRole);
    final hideRoleInStudentViews =
        widget.studentsOnlyScope || widget.pendingApprovalOnlyScope;
    final detailAccountStatus = _readAccountStatus(data, role: _detailRole);
    final detailVerification = _readStudentVerification(
      data,
      role: _detailRole,
    );
    final canReviewPendingStudent =
        isStudent &&
        detailAccountStatus == 'active' &&
        detailVerification == 'pending_approval';
    final inPendingEditContext = _isPendingApprovalEditContext();
    final canEditProfileNow =
        inPendingEditContext &&
        isStudent &&
        detailVerification == 'pending_approval';
    final canDeptAdminEditPhoto =
        _isDepartmentAdminActor() && canEditProfileNow;
    final isDeptScopedReviewer = _isDepartmentAdminActor();
    final selectedProgram = (() {
      final current = _detailSelectedProgramId?.trim();
      if (current != null && current.isNotEmpty) {
        return current;
      }
      final fallback = _detailProgramCtrl.text.trim();
      return fallback.isEmpty ? null : fallback;
    })();
    final hasSelectedProgram =
        selectedProgram != null &&
        _detailProgramOptions.any((doc) => doc.id.trim() == selectedProgram);
    final selectedProgramLabel = (() {
      final value = (selectedProgram ?? '').trim();
      if (value.isEmpty) return '--';
      for (final doc in _detailProgramOptions) {
        if (doc.id.trim() != value) continue;
        final row = doc.data();
        final code = (row['programCode'] ?? doc.id).toString();
        final name = (row['name'] ?? row['programName'] ?? row['title'] ?? '')
            .toString()
            .trim();
        return name.isEmpty ? code : name;
      }
      return value;
    })();
    final selectedCollegeLabel = (() {
      final resolved = _detailCollegeName.trim();
      if (resolved.isNotEmpty) return resolved;
      final fallback = _detailCollegeCtrl.text.trim();
      return fallback.isEmpty ? '--' : fallback;
    })();
    final readOnlyMode = !_detailEditing;
    final detailStudentNo = _detailStudentNoCtrl.text.trim();
    final detailEmployeeNo = _detailEmployeeNoCtrl.text.trim();

    Widget sectionCard(String title, List<Widget> children) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBF8),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: readOnlyMode ? textDark : hintColor,
                fontWeight: FontWeight.w900,
                letterSpacing: readOnlyMode ? 0.0 : 0.7,
                fontSize: readOnlyMode ? 31 / 2 : 11,
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
      bool required = false,
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
          required: required,
          readOnly: _detailEditing && !enabled,
        ),
      );
    }

    Widget readOnlyField(
      String label,
      String value, {
      IconData? icon,
      bool required = false,
    }) {
      return TextFormField(
        initialValue: value.trim().isEmpty ? '--' : value.trim(),
        readOnly: true,
        enabled: false,
        style: const TextStyle(
          color: textDark,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        decoration: _detailDecor(
          label,
          enabled: false,
          icon: icon,
          required: required,
          readOnly: _detailEditing,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    color: primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _detailEditing ? 'Edit Profile' : 'Profile Details',
                      style: const TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: onClose != null
                        ? 'Close details'
                        : 'Clear selection',
                    onPressed: onClose ?? _clearDetailSelection,
                    icon: const Icon(Icons.close_rounded, color: hintColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_detailEditing) ...[
                      const Text(
                        '* Required fields',
                        style: TextStyle(
                          color: hintColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    sectionCard(
                      readOnlyMode ? 'Student Information' : 'PROFILE PHOTO',
                      [
                        Row(
                          children: [
                            _buildUserAvatar(
                              data,
                              detailName,
                              radius: 24,
                              fontSize: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: readOnlyMode
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          detailName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: textDark,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 17,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          isStudent
                                              ? 'Student No: ${detailStudentNo.isEmpty ? '--' : detailStudentNo}'
                                              : 'Employee ID: ${detailEmployeeNo.isEmpty ? '--' : detailEmployeeNo}',
                                          style: const TextStyle(
                                            color: hintColor,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isStudent
                                              ? 'Program: $selectedProgramLabel'
                                              : 'Role: ${_formatRole(_detailRole)}',
                                          style: const TextStyle(
                                            color: hintColor,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Profile Photo',
                                      style: TextStyle(
                                        color: textDark,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14.5,
                                      ),
                                    ),
                            ),
                            if (canDeptAdminEditPhoto) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 36,
                                child: OutlinedButton.icon(
                                  onPressed: _detailPhotoUploading
                                      ? null
                                      : () => _changeDetailProfilePhoto(
                                          targetUid: selectedDoc.id,
                                          targetData: data,
                                          targetVerificationStatus:
                                              detailVerification,
                                        ),
                                  icon: _detailPhotoUploading
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.photo_camera_outlined,
                                          size: 16,
                                        ),
                                  label: Text(
                                    _detailPhotoUploading
                                        ? 'Uploading...'
                                        : 'Change Photo',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primaryColor,
                                    side: BorderSide(
                                      color: primaryColor.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 0,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.md,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    sectionCard(
                      readOnlyMode ? 'Basic Information' : 'BASIC INFO',
                      [
                        editableField(
                          _detailFirstNameCtrl,
                          'First Name',
                          icon: Icons.person_outline_rounded,
                          enabled: _detailEditing,
                          required: _detailEditing,
                          errorText:
                              _detailEditing &&
                                  _detailFirstNameCtrl.text.trim().isEmpty
                              ? 'First Name is required.'
                              : null,
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
                          required: _detailEditing,
                          errorText:
                              _detailEditing &&
                                  _detailLastNameCtrl.text.trim().isEmpty
                              ? 'Last Name is required.'
                              : null,
                        ),
                        const SizedBox(height: 10),
                        editableField(
                          _detailEmailCtrl,
                          'Email',
                          icon: Icons.email_outlined,
                          enabled: false,
                        ),
                        if (!hideRoleInStudentViews &&
                            !(isStudent && isDeptScopedReviewer)) ...[
                          const SizedBox(height: 10),
                          readOnlyField(
                            'Role',
                            _formatRole(_detailRole),
                            icon: Icons.admin_panel_settings_outlined,
                          ),
                        ],
                      ],
                    ),
                    sectionCard(
                      readOnlyMode
                          ? (isStudent ? 'Student Profile' : 'Staff Profile')
                          : (isStudent ? 'STUDENT PROFILE' : 'STAFF PROFILE'),
                      [
                        if (isStudent) ...[
                          editableField(
                            _detailStudentNoCtrl,
                            'Student Number',
                            icon: Icons.badge_outlined,
                            enabled: _detailEditing,
                            required: false,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [
                              _HyphenatedDigitsFormatter(
                                firstGroup: 3,
                                secondGroup: 4,
                              ),
                            ],
                            onChanged:
                                _scheduleDetailStudentNoAvailabilityCheck,
                            helperText: _detailStudentNoHelperText(),
                            errorText: _detailStudentNoErrorText(),
                          ),
                          if (!isDeptScopedReviewer) ...[
                            const SizedBox(height: 10),
                            readOnlyField(
                              'College',
                              selectedCollegeLabel,
                              icon: Icons.account_balance_outlined,
                              required: false,
                            ),
                          ],
                          const SizedBox(height: 10),
                          if (!_detailEditing)
                            readOnlyField(
                              'Program',
                              selectedProgramLabel,
                              icon: Icons.school_outlined,
                            )
                          else
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                'detail-program-${_selectedUserId ?? ''}-${selectedProgram ?? 'none'}-${_detailProgramOptions.length}',
                              ),
                              isExpanded: true,
                              initialValue: selectedProgram,
                              decoration: _detailDecor(
                                'Program',
                                enabled: !_detailProgramLoading,
                                icon: Icons.school_outlined,
                                required: true,
                                helperText: _detailProgramLoading
                                    ? 'Loading programs...'
                                    : null,
                                errorText:
                                    (selectedProgram == null ||
                                        selectedProgram.trim().isEmpty)
                                    ? 'Program is required.'
                                    : null,
                              ),
                              items: [
                                if (selectedProgram != null &&
                                    !hasSelectedProgram)
                                  DropdownMenuItem<String>(
                                    value: selectedProgram,
                                    child: Text(
                                      selectedProgram,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ..._detailProgramOptions.map((doc) {
                                  final row = doc.data();
                                  final code = (row['programCode'] ?? doc.id)
                                      .toString();
                                  final name =
                                      (row['name'] ??
                                              row['programName'] ??
                                              row['title'] ??
                                              '')
                                          .toString()
                                          .trim();
                                  final label = name.isEmpty ? code : name;
                                  return DropdownMenuItem<String>(
                                    value: doc.id,
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }),
                              ],
                              onChanged: !_detailProgramLoading
                                  ? (v) {
                                      setState(() {
                                        _detailSelectedProgramId = v;
                                        _detailProgramCtrl.text = (v ?? '')
                                            .trim();
                                      });
                                    }
                                  : null,
                            ),
                        ] else ...[
                          editableField(
                            _detailEmployeeNoCtrl,
                            'Employee ID',
                            icon: Icons.badge_outlined,
                            enabled: _detailEditing,
                            required: _detailEditing,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [
                              _HyphenatedDigitsFormatter(
                                firstGroup: 4,
                                secondGroup: 3,
                              ),
                            ],
                            onChanged:
                                _scheduleDetailEmployeeNoAvailabilityCheck,
                            helperText: _detailEmployeeNoHelperText(),
                            errorText: _detailEmployeeNoErrorText(),
                          ),
                          if (_roleNeedsDepartmentFor(_detailRole)) ...[
                            const SizedBox(height: 10),
                            editableField(
                              _detailDepartmentCtrl,
                              'Department (College Code)',
                              icon: Icons.business_outlined,
                              enabled: _detailEditing,
                              required: _detailEditing,
                              errorText:
                                  _detailEditing &&
                                      _detailDepartmentCtrl.text.trim().isEmpty
                                  ? 'Department is required.'
                                  : null,
                            ),
                          ],
                        ],
                      ],
                    ),
                    sectionCard(readOnlyMode ? 'Access' : 'ACCESS', [
                      if (!_detailEditing)
                        readOnlyField(
                          'Account Status',
                          _detailAccountStatus
                              .trim()
                              .replaceAll('_', ' ')
                              .toUpperCase(),
                        )
                      else
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _detailAccountStatus,
                          decoration: _detailDecor(
                            'Account Status',
                            enabled: true,
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
                          onChanged: (v) => setState(
                            () => _detailAccountStatus =
                                _normalizeAccountStatus(v ?? 'active'),
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                ),
              ),
              child: !_detailEditing
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (canReviewPendingStudent) ...[
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _reviewPendingStudent(
                                    uid: selectedDoc.id,
                                    approve: true,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF81C784),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.md,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Approve',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () async {
                                    final reason =
                                        await _showRejectReasonDialog();
                                    if (!mounted || reason == null) return;
                                    await _reviewPendingStudent(
                                      uid: selectedDoc.id,
                                      approve: false,
                                      rejectReason: reason,
                                    );
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFE57373),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.md,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Reject',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (canEditProfileNow) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                setState(() {
                                  _detailEditing = true;
                                  _detailEmailAvailabilityError = null;
                                  _detailStudentNoAvailabilityError = null;
                                  _detailEmployeeNoAvailabilityError = null;
                                });
                                if (_isStudentRole(_detailRole)) {
                                  _loadDetailProgramsForCollege(
                                    _detailCollegeCtrl.text.trim(),
                                    initialProgramId: _detailSelectedProgramId,
                                  );
                                }
                                _scheduleDetailEmailAvailabilityCheck(
                                  _detailEmailCtrl.text,
                                );
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
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.md,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text(
                                'Edit Profile',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _showUserActivityLogsDialog(
                              uid: selectedDoc.id,
                              displayName: _displayName(data),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(
                                color: primaryColor.withValues(alpha: 0.30),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.md,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.history_rounded, size: 18),
                            label: const Text(
                              'View Activity Logs',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                _loadDetailFromData(selectedDoc.id, data),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: primaryColor,
                              side: BorderSide(
                                color: primaryColor.withValues(alpha: 0.30),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.md,
                                ),
                              ),
                            ),
                            child: const Text(
                              'Discard Changes',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
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
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.md,
                                ),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, {bool compact = false}) {
    String chipLabel(String raw) {
      switch (raw.trim().toLowerCase()) {
        case 'active':
          return 'Active';
        case 'inactive':
          return 'Inactive';
        default:
          return raw.replaceAll('_', ' ').trim();
      }
    }

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
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        chipLabel(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildVerificationChip(String status, {bool compact = false}) {
    String verificationLabel(String raw) {
      switch (raw.trim().toLowerCase()) {
        case 'verified':
          return 'Verified';
        case 'pending_email_verification':
          return 'Email Pending';
        case 'pending_profile':
          return 'Profile Pending';
        case 'pending_approval':
        case 'pending_verification':
          return 'Approval Pending';
        case 'rejected':
          return 'Rejected';
        default:
          return raw.replaceAll('_', ' ').trim();
      }
    }

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
      case 'rejected':
        color = Colors.red;
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        verificationLabel(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Future<void> _openMobileProfileDetailsSheet({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    _loadDetailFromData(uid, data);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final reservedTop = media.padding.top + kToolbarHeight + 8;
        final modalHeight = (media.size.height - reservedTop)
            .clamp(420.0, media.size.height * 0.92)
            .toDouble();
        return SafeArea(
          top: false,
          child: SizedBox(
            height: modalHeight,
            child:
                ValueListenableBuilder<
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>
                >(
                  valueListenable: _allUserDocs,
                  builder: (context, docs, _) {
                    QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
                    for (final doc in docs) {
                      if (doc.id == uid) {
                        selectedDoc = doc;
                        break;
                      }
                    }
                    if (selectedDoc == null) {
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: _buildDesktopDetailsPanel(
                        selectedDoc: selectedDoc,
                        onClose: () => Navigator.of(sheetContext).pop(),
                      ),
                    );
                  },
                ),
          ),
        );
      },
    );

    if (!mounted) return;
    _clearDetailSelection();
  }

  Widget _buildUserCard(
    String uid,
    Map<String, dynamic> data, {
    required String listType,
  }) {
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    final accountStatus = _readAccountStatus(data, role: role);
    final studentVerification = _readStudentVerification(data, role: role);
    final isStudent = _isStudentRole(role);
    final hideRoleInStudentViews =
        widget.studentsOnlyScope || widget.pendingApprovalOnlyScope;
    final name = _displayName(data);
    final id = _displayId(data);
    final email = (data['email'] ?? '').toString();

    final badgeStatus = (() {
      if (!isStudent) return accountStatus;
      if (listType == 'active_students') return studentVerification;
      if (listType == 'students') return accountStatus;
      return accountStatus == 'active' ? studentVerification : accountStatus;
    })();
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

    final showPendingStatusChip =
        listType != 'pending' && listType != 'pending_approval_queue';
    final isSelected = _selectedUserId == uid;

    return GestureDetector(
      onTap: () => _openMobileProfileDetailsSheet(uid: uid, data: data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : Colors.black.withValues(alpha: 0.05),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildUserAvatar(data, name, radius: 24, fontSize: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: textDark,
                          ),
                        ),
                      ),
                      if (showPendingStatusChip) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadii.xxl),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 11, color: statusColor),
                              const SizedBox(width: 5),
                              Text(
                                badgeStatus.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 9.8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: hintColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.badge_outlined,
                            size: 14,
                            color: primaryColor.withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            id,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      if (!hideRoleInStudentViews)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.work_outline_rounded,
                              size: 14,
                              color: primaryColor.withValues(alpha: 0.55),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatRole(role),
                              style: const TextStyle(
                                color: textDark,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      if (isStudent && !showPendingStatusChip)
                        Text(
                          studentVerification
                              .replaceAll('_', ' ')
                              .toUpperCase(),
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

typedef _StudentImportValidator =
    Future<_StudentImportValidationResult> Function(String csvText);

class _ImportedStudentDraft {
  final int rowNumber;
  final String studentNo;
  final String firstName;
  final String middleName;
  final String lastName;
  final String collegeId;
  final String programId;
  final String email;
  final String? existingUid;

  const _ImportedStudentDraft({
    required this.rowNumber,
    required this.studentNo,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.collegeId,
    required this.programId,
    required this.email,
    required this.existingUid,
  });

  String get fullName => [
    firstName.trim(),
    middleName.trim(),
    lastName.trim(),
  ].where((p) => p.isNotEmpty).join(' ').trim();
}

class _StudentImportIssue {
  final int rowNumber;
  final String message;
  final String? studentNo;
  final String? fullName;

  const _StudentImportIssue({
    required this.rowNumber,
    required this.message,
    this.studentNo,
    this.fullName,
  });
}

class _StudentImportValidationResult {
  final int totalRows;
  final List<_ImportedStudentDraft> validRows;
  final List<_StudentImportIssue> issues;

  const _StudentImportValidationResult({
    required this.totalRows,
    required this.validRows,
    required this.issues,
  });

  int get invalidCount => issues.length;
}

class _StudentImportDialogResult {
  final List<_ImportedStudentDraft> rows;
  final int invalidCount;
  final int totalRows;
  final String fileName;

  const _StudentImportDialogResult({
    required this.rows,
    required this.invalidCount,
    required this.totalRows,
    required this.fileName,
  });
}

class _StudentImportCommitResult {
  final int created;
  final int updated;

  const _StudentImportCommitResult({
    required this.created,
    required this.updated,
  });
}

class _StudentBulkImportDialog extends StatefulWidget {
  final _StudentImportValidator onValidateCsv;

  const _StudentBulkImportDialog({required this.onValidateCsv});

  @override
  State<_StudentBulkImportDialog> createState() =>
      _StudentBulkImportDialogState();
}

class _StudentBulkImportDialogState extends State<_StudentBulkImportDialog> {
  static const _bg = Colors.white;
  static const _primary = Color(0xFF1B5E20);
  static const _hint = Color(0xFF6D7F62);
  static const _text = Color(0xFF1F2A1F);

  bool _validating = false;
  String _fileName = '';
  _StudentImportValidationResult? _result;
  String? _errorText;

  Future<void> _pickAndValidateCsv() async {
    setState(() {
      _validating = true;
      _errorText = null;
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: kIsWeb,
      );
      if (picked == null || picked.files.isEmpty) {
        if (!mounted) return;
        setState(() => _validating = false);
        return;
      }

      final file = picked.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        setState(() {
          _validating = false;
          _errorText = 'Unable to read selected file.';
        });
        return;
      }

      final csvText = utf8.decode(bytes, allowMalformed: true);
      final validated = await widget.onValidateCsv(csvText);
      if (!mounted) return;
      setState(() {
        _fileName = file.name.trim().isEmpty
            ? 'students.csv'
            : file.name.trim();
        _result = validated;
        _validating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _errorText = 'Unable to validate CSV: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final validCount = result?.validRows.length ?? 0;
    final invalidCount = result?.invalidCount ?? 0;
    final totalRows = result?.totalRows ?? 0;
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 760;
    final dialogWidth = compact ? (viewport.width * 0.95) : 760.0;

    return AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 24,
        vertical: compact ? 10 : 24,
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Import Students',
              style: TextStyle(
                color: _primary,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
          IconButton(
            onPressed: _validating ? null : () => Navigator.pop(context),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: _hint),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              const Text(
                'Upload a CSV file using this header format:',
                style: TextStyle(color: _hint, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.table_rows_rounded, size: 18, color: _hint),
                        SizedBox(width: 8),
                        Text(
                          'Template Header',
                          style: TextStyle(
                            color: _hint,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    SelectableText(
                      'studentNo,firstName,middleName,lastName,college,program,email',
                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Required: studentNo, firstName, lastName, college, program',
                      style: TextStyle(
                        color: _hint,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _validating ? null : _pickAndValidateCsv,
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text(
                      'Choose CSV',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _fileName.isEmpty ? 'No file selected.' : _fileName,
                      style: TextStyle(
                        color: _fileName.isEmpty ? _hint : _text,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (_validating) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: _primary),
              ],
              if (_errorText != null && _errorText!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _errorText!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (result != null) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(label: 'Rows: $totalRows', color: _hint),
                    _SummaryChip(label: 'Valid: $validCount', color: _primary),
                    _SummaryChip(
                      label: 'Invalid: $invalidCount',
                      color: invalidCount > 0 ? Colors.red : _hint,
                    ),
                  ],
                ),
                if (result.issues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Validation Issues',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: result.issues.length.clamp(0, 8),
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final issue = result.issues[index];
                        final titleBits = <String>[
                          'Row ${issue.rowNumber}',
                          if ((issue.studentNo ?? '').isNotEmpty)
                            issue.studentNo!,
                          if ((issue.fullName ?? '').isNotEmpty)
                            issue.fullName!,
                        ];
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titleBits.join(' - '),
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                issue.message,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: _validating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _validating || validCount == 0
              ? null
              : () {
                  Navigator.pop(
                    context,
                    _StudentImportDialogResult(
                      rows: result!.validRows,
                      invalidCount: result.invalidCount,
                      totalRows: result.totalRows,
                      fileName: _fileName,
                    ),
                  );
                },
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          icon: const Icon(Icons.playlist_add_check_rounded),
          label: Text(
            validCount == 0 ? 'Import' : 'Import $validCount',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;

  const _SummaryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _CreateUserResult {
  final String email;
  final String password;
  final String firstName;
  final String middleName;
  final String lastName;
  final String role;
  final String studentVerificationStatus;
  final bool sendPasswordReset;
  final bool userSetsOwnPassword;
  final String studentNo;
  final String employeeNo;
  final String department;

  final String? collegeId;
  final String? programId;
  final XFile? profilePhoto;

  const _CreateUserResult({
    required this.email,
    required this.password,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.role,
    this.studentVerificationStatus = 'verified',
    required this.sendPasswordReset,
    this.userSetsOwnPassword = true,
    this.studentNo = '',
    this.employeeNo = '',
    this.department = '',
    this.collegeId,
    this.programId,
    this.profilePhoto,
  });
}

class _CreateUserDialog extends StatefulWidget {
  final String initialPassword;
  final String? forcedDepartment;
  final bool studentsOnly;
  final String? forcedRole;

  const _CreateUserDialog({
    required this.initialPassword,
    this.forcedDepartment,
    this.studentsOnly = false,
    this.forcedRole,
  });

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();

  // New role-specific controllers
  final _studentNoCtrl = TextEditingController();
  final _employeeNoCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();

  String _role = 'professor';
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
  XFile? _profilePhoto;
  Uint8List? _profilePhotoBytes;
  String? _photoError;
  final ImagePicker _imagePicker = ImagePicker();

  // Additional student details
  String? _selectedCollege;
  String? _selectedProgram;

  List<QueryDocumentSnapshot> _colleges = [];
  List<QueryDocumentSnapshot> _programs = [];

  bool get _roleNeedsDepartment =>
      _role != 'student' &&
      _role != 'osa_admin' &&
      _role != 'counseling_admin' &&
      _role != 'super_admin' &&
      _role != 'guard';

  @override
  void initState() {
    super.initState();
    _passwordCtrl.text = widget.initialPassword;
    final forcedRole = widget.forcedRole?.trim().toLowerCase();
    if (widget.studentsOnly || forcedRole == 'student') {
      _role = 'student';
      _studentVerificationStatus = 'pending_email_verification';
    } else if (forcedRole != null && forcedRole.isNotEmpty) {
      _role = forcedRole;
      _studentVerificationStatus = 'verified';
    } else {
      _role = 'professor';
      _studentVerificationStatus = 'verified';
    }
    if (widget.forcedDepartment != null) {
      _deptCtrl.text = widget.forcedDepartment!;
    }
    _emailCtrl.addListener(_onAnyFieldChanged);
    _firstCtrl.addListener(_onAnyFieldChanged);
    _middleCtrl.addListener(_onAnyFieldChanged);
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
    final docs = [...snap.docs]
      ..sort((a, b) {
        final ad = a.data() as Map<String, dynamic>? ?? const {};
        final bd = b.data() as Map<String, dynamic>? ?? const {};
        final ao = (ad['sortOrder'] as num?)?.toInt() ?? 999;
        final bo = (bd['sortOrder'] as num?)?.toInt() ?? 999;
        if (ao != bo) return ao.compareTo(bo);
        final ac = (ad['collegeCode'] ?? a.id).toString().trim();
        final bc = (bd['collegeCode'] ?? b.id).toString().trim();
        return ac.compareTo(bc);
      });
    setState(() => _colleges = docs);

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
    final docs = [...snap.docs]
      ..sort((a, b) {
        final ad = a.data() as Map<String, dynamic>? ?? const {};
        final bd = b.data() as Map<String, dynamic>? ?? const {};
        final ao = (ad['sortOrder'] as num?)?.toInt() ?? 999;
        final bo = (bd['sortOrder'] as num?)?.toInt() ?? 999;
        if (ao != bo) return ao.compareTo(bo);
        final ac = (ad['programCode'] ?? a.id).toString().trim();
        final bc = (bd['programCode'] ?? b.id).toString().trim();
        return ac.compareTo(bc);
      });
    setState(() => _programs = docs);
  }

  String _collegeDropdownLabel(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    final code = (data['collegeCode'] ?? doc.id).toString().trim();
    final name = (data['name'] ?? data['collegeName'] ?? data['title'] ?? '')
        .toString()
        .trim();
    return name.isEmpty ? code : '$code - $name';
  }

  String _programDropdownLabel(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    final code = (data['programCode'] ?? doc.id).toString().trim();
    final name = (data['name'] ?? data['programName'] ?? data['title'] ?? '')
        .toString()
        .trim();
    return name.isEmpty ? code : '$code - $name';
  }

  String _collegeLabelById(String collegeId) {
    final id = collegeId.trim();
    if (id.isEmpty) return '-';
    for (final doc in _colleges) {
      if (doc.id != id) continue;
      return _collegeDropdownLabel(doc);
    }
    return id;
  }

  String _programLabelById(String programId) {
    final id = programId.trim();
    if (id.isEmpty) return '-';
    for (final doc in _programs) {
      if (doc.id != id) continue;
      return _programDropdownLabel(doc);
    }
    return id;
  }

  @override
  void dispose() {
    _emailDebounce?.cancel();
    _studentNoDebounce?.cancel();
    _employeeNoDebounce?.cancel();
    _emailCtrl.removeListener(_onAnyFieldChanged);
    _firstCtrl.removeListener(_onAnyFieldChanged);
    _middleCtrl.removeListener(_onAnyFieldChanged);
    _lastCtrl.removeListener(_onAnyFieldChanged);
    _passwordCtrl.removeListener(_onAnyFieldChanged);
    _studentNoCtrl.removeListener(_onAnyFieldChanged);
    _employeeNoCtrl.removeListener(_onAnyFieldChanged);
    _deptCtrl.removeListener(_onAnyFieldChanged);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _firstCtrl.dispose();
    _middleCtrl.dispose();
    _lastCtrl.dispose();
    _studentNoCtrl.dispose();
    _employeeNoCtrl.dispose();
    _deptCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();

      setState(() {
        _profilePhoto = picked;
        _profilePhotoBytes = bytes;
        _photoError = null;
      });
    } catch (e) {
      if (!mounted) return;
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  String? _emailErrorText() {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) return null;
    if (!_isValidEmailFormat(email))
      return 'Email address format is incorrect.';
    return _emailAvailabilityError;
  }

  String? _emailHelperText() {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (_emailChecking) return 'Checking email availability...';
    if (email.isEmpty || !_isValidEmailFormat(email)) return null;
    if (_emailAvailabilityError != null) return null;
    if (_lastEmailChecked == email) return 'Email address is available.';
    return null;
  }

  String? _studentNoErrorText() {
    if (_role != 'student') return null;
    final studentNo = _studentNoCtrl.text.trim();
    if (studentNo.isEmpty) return null;
    if (!RegExp(r'^\d{3}-\d{4}$').hasMatch(studentNo)) {
      return 'Student Number format is incorrect (###-####).';
    }
    return _studentNoAvailabilityError;
  }

  String? _studentNoHelperText() {
    if (_role != 'student') return null;
    final studentNo = _studentNoCtrl.text.trim();
    if (_studentNoChecking) return 'Checking Student Number availability...';
    if (studentNo.isEmpty ||
        !RegExp(r'^\d{3}-\d{4}$').hasMatch(studentNo) ||
        _studentNoAvailabilityError != null) {
      return null;
    }
    if (_lastStudentNoChecked == studentNo)
      return 'Student Number is available.';
    return null;
  }

  String? _employeeNoErrorText() {
    if (_role == 'student') return null;
    final employeeNo = _employeeNoCtrl.text.trim();
    if (employeeNo.isEmpty) return null;
    if (!RegExp(r'^\d{4}-\d{3}$').hasMatch(employeeNo)) {
      return 'Employee ID format is incorrect (####-###).';
    }
    return _employeeNoAvailabilityError;
  }

  String? _employeeNoHelperText() {
    if (_role == 'student') return null;
    final employeeNo = _employeeNoCtrl.text.trim();
    if (_employeeNoChecking) return 'Checking Employee ID availability...';
    if (employeeNo.isEmpty ||
        !RegExp(r'^\d{4}-\d{3}$').hasMatch(employeeNo) ||
        _employeeNoAvailabilityError != null) {
      return null;
    }
    if (_lastEmployeeNoChecked == employeeNo)
      return 'Employee ID is available.';
    return null;
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
      if (_profilePhoto == null) return false;
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

  String _roleLabel(String role) {
    switch (role.trim().toLowerCase()) {
      case 'osa_admin':
        return 'OSA Admin';
      case 'counseling_admin':
        return 'Counseling Admin';
      case 'department_admin':
        return 'Dean';
      case 'super_admin':
        return 'Super Admin';
      case 'professor':
        return 'Professor';
      case 'guard':
        return 'Guard';
      case 'student':
        return 'Student';
      default:
        return role;
    }
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _UserManagementPageState.hintColor,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _UserManagementPageState.textDark,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showCreateConfirmationDialog({
    required String role,
    required String email,
    required String firstName,
    required String middleName,
    required String lastName,
    required String studentNo,
    required String employeeNo,
    required String departmentCode,
    required String collegeId,
    required String programId,
    required bool hasProfilePhoto,
  }) async {
    final fullName = [
      firstName,
      middleName,
      lastName,
    ].where((v) => v.trim().isNotEmpty).join(' ');
    final idLabel = role == 'student' ? 'Student Number' : 'Employee ID';
    final idValue = role == 'student' ? studentNo : employeeNo;
    final roleNeedsDepartment =
        role != 'student' &&
        role != 'osa_admin' &&
        role != 'counseling_admin' &&
        role != 'super_admin' &&
        role != 'guard';
    final createLabel = widget.studentsOnly
        ? 'Create Student'
        : ((widget.forcedRole ?? '').trim().toLowerCase() == 'professor'
              ? 'Create Professor'
              : 'Create Account');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _UserManagementPageState.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        title: const Row(
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: _UserManagementPageState.primaryColor,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Confirm Account Creation',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _UserManagementPageState.primaryColor,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please review the account details before creating.',
              style: TextStyle(
                color: _UserManagementPageState.textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: _UserManagementPageState.primaryColor.withValues(
                    alpha: 0.16,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _confirmRow(
                    'Name',
                    fullName.trim().isEmpty ? '-' : fullName.trim(),
                  ),
                  _confirmRow(
                    'Email',
                    email.trim().isEmpty ? '-' : email.trim(),
                  ),
                  _confirmRow('Role', _roleLabel(role)),
                  _confirmRow(idLabel, idValue.trim().isEmpty ? '-' : idValue),
                  if (role == 'student') ...[
                    _confirmRow('College', _collegeLabelById(collegeId)),
                    _confirmRow('Program', _programLabelById(programId)),
                  ],
                  if (roleNeedsDepartment)
                    _confirmRow(
                      'Department',
                      _collegeLabelById(departmentCode),
                    ),
                  _confirmRow(
                    'Profile Photo',
                    hasProfilePhoto ? 'Selected' : 'Not uploaded',
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _UserManagementPageState.hintColor,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: _UserManagementPageState.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
            child: Text(
              createLabel,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _submit() async {
    if (_lockCreateAccount) return;
    if (!_formKey.currentState!.validate()) return;
    final effectiveRole = widget.studentsOnly
        ? 'student'
        : (widget.forcedRole?.trim().toLowerCase().isNotEmpty == true
              ? widget.forcedRole!.trim().toLowerCase()
              : _role);
    final roleNeedsDepartment =
        effectiveRole != 'student' &&
        effectiveRole != 'osa_admin' &&
        effectiveRole != 'counseling_admin' &&
        effectiveRole != 'super_admin' &&
        effectiveRole != 'guard';
    final effectivePassword = _userSetsOwnPassword
        ? widget.initialPassword
        : _passwordCtrl.text.trim();
    final effectiveStudentVerification = effectiveRole == 'student'
        ? 'pending_email_verification'
        : _studentVerificationStatus;
    final effectiveSendReset = _userSetsOwnPassword ? true : _sendReset;
    final normalizedDepartment = roleNeedsDepartment
        ? _deptCtrl.text.trim()
        : '';
    if (effectiveRole == 'student' && _profilePhoto == null) {
      setState(() {
        _photoError = 'Profile photo is required';
      });
      return;
    }

    final confirmed = await _showCreateConfirmationDialog(
      role: effectiveRole,
      email: _emailCtrl.text.trim().toLowerCase(),
      firstName: _firstCtrl.text.trim(),
      middleName: _middleCtrl.text.trim(),
      lastName: _lastCtrl.text.trim(),
      studentNo: _studentNoCtrl.text.trim(),
      employeeNo: _employeeNoCtrl.text.trim(),
      departmentCode: normalizedDepartment,
      collegeId: (_selectedCollege ?? '').trim(),
      programId: (_selectedProgram ?? '').trim(),
      hasProfilePhoto: _profilePhoto != null,
    );
    if (!confirmed || !mounted) return;

    Navigator.pop(
      context,
      _CreateUserResult(
        email: _emailCtrl.text.trim().toLowerCase(),
        password: effectivePassword,
        firstName: _firstCtrl.text.trim(),
        middleName: _middleCtrl.text.trim(),
        lastName: _lastCtrl.text.trim(),
        role: effectiveRole,
        studentVerificationStatus: effectiveStudentVerification,
        sendPasswordReset: effectiveSendReset,
        userSetsOwnPassword: _userSetsOwnPassword,
        studentNo: _studentNoCtrl.text.trim(),
        employeeNo: _employeeNoCtrl.text.trim(),
        department: normalizedDepartment,
        collegeId: _selectedCollege,
        programId: _selectedProgram,
        profilePhoto: _profilePhoto,
      ),
    );
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? helperText,
    String? errorText,
    bool enabled = true,
    bool required = false,
  }) {
    final baseLabelStyle = const TextStyle(
      color: _UserManagementPageState.hintColor,
      fontWeight: FontWeight.w700,
    );
    return InputDecoration(
      label: Text.rich(
        TextSpan(
          text: label,
          style: baseLabelStyle,
          children: required
              ? const [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ]
              : const [],
        ),
      ),
      helperText: helperText,
      errorText: errorText,
      prefixIcon: Icon(
        icon,
        color: _UserManagementPageState.primaryColor.withValues(alpha: 0.85),
      ),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
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
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 760;
    final dialogWidth = compact ? (viewport.width * 0.95) : 500.0;
    final forcedRole = widget.forcedRole?.trim().toLowerCase();
    final forceProfessor = forcedRole == 'professor';
    final dialogTitle = widget.studentsOnly
        ? 'Create New Student'
        : (forceProfessor ? 'Create New Professor' : 'Create New Account');
    final submitLabel = widget.studentsOnly
        ? 'Create Student'
        : (forceProfessor ? 'Create Professor' : 'Create Account');
    return AlertDialog(
      title: Text(
        dialogTitle,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: _UserManagementPageState.primaryColor,
        ),
      ),
      backgroundColor: _UserManagementPageState.backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 24,
        vertical: compact ? 10 : 24,
      ),
      content: SizedBox(
        width: dialogWidth,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _role == 'student' ? 'PROFILE PHOTO *' : 'PROFILE PHOTO',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _UserManagementPageState.hintColor,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: _UserManagementPageState.primaryColor.withValues(
                        alpha: 0.16,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: _UserManagementPageState.primaryColor
                            .withValues(alpha: 0.10),
                        foregroundImage: _profilePhoto == null
                            ? null
                            : (kIsWeb
                                      ? (_profilePhotoBytes != null
                                            ? MemoryImage(_profilePhotoBytes!)
                                            : null)
                                      : FileImage(File(_profilePhoto!.path)))
                                  as ImageProvider<Object>?,
                        child: _profilePhoto == null
                            ? const Icon(
                                Icons.person,
                                color: _UserManagementPageState.primaryColor,
                                size: 28,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _profilePhoto == null
                              ? 'No photo selected'
                              : (_profilePhoto!.name.isEmpty
                                    ? 'Photo selected'
                                    : _profilePhoto!.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _UserManagementPageState.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _pickProfilePhoto,
                        icon: const Icon(Icons.upload_rounded, size: 18),
                        label: Text(
                          _profilePhoto == null ? 'Upload' : 'Change',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              _UserManagementPageState.primaryColor,
                          side: BorderSide(
                            color: _UserManagementPageState.primaryColor
                                .withValues(alpha: 0.45),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                        ),
                      ),
                      if (_profilePhoto != null) ...[
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _profilePhoto = null;
                              _profilePhotoBytes = null;
                              _photoError = _role == 'student'
                                  ? 'Profile photo is required'
                                  : null;
                            });
                          },
                          child: const Text(
                            'Clear',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _role == 'student'
                      ? 'Profile photo is required for student accounts.'
                      : 'Profile photo is optional.',
                  style: TextStyle(
                    color: _UserManagementPageState.hintColor.withValues(
                      alpha: 0.9,
                    ),
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
                if ((_photoError ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _photoError!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
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
                    helperText: _emailHelperText(),
                    errorText: _emailErrorText(),
                    required: true,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: _scheduleEmailAvailabilityCheck,
                  validator: (v) {
                    final s = (v ?? '').trim().toLowerCase();
                    if (s.isEmpty) return 'Email is required';
                    if (!_isValidEmailFormat(s)) {
                      return 'Email address format is incorrect.';
                    }
                    final error = _emailErrorText();
                    if (error != null) {
                      return error;
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
                          required: true,
                        ),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _middleCtrl,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _UserManagementPageState.textDark,
                        ),
                        decoration: _decor(
                          label: 'Middle Name (optional)',
                          icon: Icons.person_outline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastCtrl,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _UserManagementPageState.textDark,
                  ),
                  decoration: _decor(
                    label: 'Last Name',
                    icon: Icons.person_outline,
                    required: true,
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                if (!widget.studentsOnly && !forceProfessor) ...[
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
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                    decoration: _decor(
                      label: 'System Role',
                      icon: Icons.admin_panel_settings_outlined,
                      required: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'professor',
                        child: Text('Professor'),
                      ),
                      DropdownMenuItem(value: 'guard', child: Text('Guard')),
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
                    onChanged: (v) {
                      final nextRole = (v ?? 'student').trim();
                      setState(() {
                        _role = nextRole;
                        _photoError = null;
                        if (_role != 'student') {
                          _studentVerificationStatus = 'verified';
                          _studentNoDebounce?.cancel();
                          _studentNoChecking = false;
                          _studentNoAvailabilityError = null;
                          _lastStudentNoChecked = '';
                        } else {
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
                      required: true,
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
                      helperText: _studentNoHelperText(),
                      errorText: _studentNoErrorText(),
                      required: true,
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
                        return 'Student Number format is incorrect (###-####).';
                      }
                      final error = _studentNoErrorText();
                      if (error != null) {
                        return error;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedCollege,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                    decoration: _decor(
                      label: 'College',
                      icon: Icons.account_balance_outlined,
                      enabled: widget.forcedDepartment == null,
                      required: true,
                    ),
                    items: _colleges.map((doc) {
                      return DropdownMenuItem(
                        value: doc.id,
                        child: Text(
                          _collegeDropdownLabel(doc),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                    isExpanded: true,
                    initialValue: _selectedProgram,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _UserManagementPageState.textDark,
                    ),
                    decoration: _decor(
                      label: 'Program/Course',
                      icon: Icons.school_outlined,
                      required: true,
                    ),
                    items: _programs.map((doc) {
                      return DropdownMenuItem(
                        value: doc.id,
                        child: Text(
                          _programDropdownLabel(doc),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                          helperText: _employeeNoHelperText(),
                          errorText: _employeeNoErrorText(),
                          required: true,
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
                            return 'Employee ID format is incorrect (####-###).';
                          }
                          final error = _employeeNoErrorText();
                          if (error != null) {
                            return error;
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
                            required: _roleNeedsDepartment,
                          ),
                          items: _colleges.map((doc) {
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text(
                                _collegeDropdownLabel(doc),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            submitLabel,
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

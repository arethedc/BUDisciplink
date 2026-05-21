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
import '../shared/widgets/app_empty_state.dart';
import 'package:apps/pages/shared/widgets/app_inline_notice.dart';
import '../../utils/download_helper.dart' as download_helper;
import '../../utils/xlsx_reader.dart';
import '../../utils/xlsx_template_builder.dart';
import 'package:apps/services/app_firestore.dart';

class UserManagementPage extends StatefulWidget {
  final bool studentsOnlyScope;
  final bool professorsOnlyScope;
  final bool pendingApprovalOnlyScope;
  final bool hideCreateAction;
  final String? headerTitle;
  final String? headerSubtitle;
  final String? initialSelectedUserId;
  final String? initialStudentNo;
  final String? initialEmployeeNo;
  final String? initialTab;
  final ValueChanged<String>? onTabChanged;
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
    this.initialStudentNo,
    this.initialEmployeeNo,
    this.initialTab,
    this.onTabChanged,
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
  String _userRoleFilter = 'All';
  String _userSourceFilter = 'All';
  String _userAccountStatusFilter = 'All';
  String _userVerificationFilter = 'All';
  String _userCollegeFilter = 'All';
  String _userProgramFilter = 'All';

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
  String _filterCacheRoleFilter = '';
  String _filterCacheSourceFilter = '';
  String _filterCacheAccountStatusFilter = '';
  String _filterCacheVerificationFilter = '';
  String _filterCacheCollegeFilter = '';
  String _filterCacheProgramFilter = '';
  String _filterCacheAdminRole = '';
  String _filterCacheAdminDept = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterCacheResult =
      const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _userFilterCollegeOptions =
      const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _userFilterProgramOptions =
      const [];

  // Design Theme
  static const primaryColor = Color(0xFF1B5E20);
  static const backgroundColor = Colors.white;
  static const textDark = Color(0xFF1F2A1F);
  static const hintColor = Color(0xFF6D7F62);

  int _tabIndexFromKey(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (widget.studentsOnlyScope) {
      switch (value) {
        case 'pending':
          return 0;
        case 'active':
          return 1;
        case 'all':
          return 2;
        default:
          return 0;
      }
    }
    switch (value) {
      case 'active':
        return 0;
      case 'inactive':
        return 1;
      case 'all':
        return 2;
      default:
        return 0;
    }
  }

  String _tabKeyForIndex(int index) {
    if (widget.studentsOnlyScope) {
      switch (index) {
        case 0:
          return 'pending';
        case 1:
          return 'active';
        case 2:
          return 'all';
        default:
          return 'pending';
      }
    }
    switch (index) {
      case 0:
        return 'active';
      case 1:
        return 'inactive';
      case 2:
        return 'all';
      default:
        return 'active';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.index = _tabIndexFromKey(widget.initialTab);
    _lastTabIndex = _tabController.index;
    _tabController.addListener(_handleTabIndexChanged);
    _allUsersStream = AppFirestore.instance.collection('users').snapshots();
    final initialStudentNo = (widget.initialStudentNo ?? '').trim();
    final initialEmployeeNo = (widget.initialEmployeeNo ?? '').trim();
    final initialTarget = widget.studentsOnlyScope
        ? initialStudentNo
        : initialEmployeeNo;
    if (initialTarget.isNotEmpty) {
      if (widget.studentsOnlyScope) {
        _tabController.index = 0;
        _lastTabIndex = 0;
        _pendingStudentFilter = 'pending_approval';
      }
      _searchCtrl.text = initialTarget;
      _searchQuery = initialTarget.toLowerCase();
    }
    _loadAdminData();
    _loadUserAcademicFilterOptions();
  }

  @override
  void didUpdateWidget(covariant UserManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      final nextIndex = _tabIndexFromKey(widget.initialTab);
      if (_tabController.index != nextIndex) {
        _tabController.index = nextIndex;
      }
    }
    final prev = widget.studentsOnlyScope
        ? (oldWidget.initialStudentNo ?? '').trim()
        : (oldWidget.initialEmployeeNo ?? '').trim();
    final next = widget.studentsOnlyScope
        ? (widget.initialStudentNo ?? '').trim()
        : (widget.initialEmployeeNo ?? '').trim();
    if (prev == next) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (next.isEmpty) {
        _clearSearchQuery();
        return;
      }
      setState(() {
        if (widget.studentsOnlyScope) {
          _tabController.index = 0;
          _lastTabIndex = 0;
          _pendingStudentFilter = 'pending_approval';
        }
        _searchCtrl.text = next;
        _searchQuery = next.toLowerCase();
      });
      _invalidateFilterCache();
    });
  }

  Future<void> _loadAdminData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await AppFirestore.instance
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
    widget.onTabChanged?.call(_tabKeyForIndex(nextIndex));
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
    _filterCacheRoleFilter = '';
    _filterCacheSourceFilter = '';
    _filterCacheAccountStatusFilter = '';
    _filterCacheVerificationFilter = '';
    _filterCacheCollegeFilter = '';
    _filterCacheProgramFilter = '';
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
      if (!_matchesUserAdvancedFilters(
        data: data,
        role: role,
        accountStatus: accountStatus,
        studentVerification: studentVerification,
      )) {
        return false;
      }

      return _matchesSearch(data, query);
    }).length;
  }

  String _readAccountSource(Map<String, dynamic> data) {
    final source = (data['accountSource'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    switch (source) {
      case 'self_signup':
      case 'admin_manual':
      case 'admin_import':
        return source;
    }

    if (data['importedByAdmin'] == true) return 'admin_import';
    if (data['createdByAdmin'] == true) return 'admin_manual';
    return 'self_signup';
  }

  String _accountSourceLabel(String source) {
    switch (source) {
      case 'admin_import':
        return 'Imported';
      case 'admin_manual':
        return 'Admin Created';
      case 'self_signup':
      default:
        return 'Self Signup';
    }
  }

  String _displayAffiliation(Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    if (_isStudentRole(role)) {
      final studentProfile =
          data['studentProfile'] as Map<String, dynamic>? ?? {};
      final collegeId = (studentProfile['collegeId'] ?? '').toString().trim();
      if (collegeId.isNotEmpty) return _collegeFilterLabelById(collegeId);
      return '--';
    }

    final employeeProfile =
        data['employeeProfile'] as Map<String, dynamic>? ?? {};
    final department = (employeeProfile['department'] ?? '').toString().trim();
    return department.isEmpty ? '--' : _collegeFilterLabelById(department);
  }

  String _collegeFilterLabel(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final code = (data['collegeCode'] ?? '').toString().trim();
    final name = (data['name'] ?? data['collegeName'] ?? data['title'] ?? '')
        .toString()
        .trim();
    if (code.isEmpty && name.isEmpty) return '--';
    if (name.isEmpty || name == code) return code.isEmpty ? name : code;
    return '${code.isEmpty ? name : code} - $name';
  }

  String _programFilterLabel(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final code = (data['programCode'] ?? '').toString().trim();
    final name = (data['name'] ?? data['programName'] ?? data['title'] ?? '')
        .toString()
        .trim();
    if (code.isEmpty && name.isEmpty) return '--';
    if (name.isEmpty || name == code) return code.isEmpty ? name : code;
    return '${code.isEmpty ? name : code} - $name';
  }

  String _collegeFilterLabelById(String collegeId) {
    final id = collegeId.trim();
    if (id.isEmpty || id == 'All') return 'All colleges';
    for (final doc in _userFilterCollegeOptions) {
      if (doc.id.trim() == id) return _collegeFilterLabel(doc);
      final code = (doc.data()['collegeCode'] ?? '').toString().trim();
      if (code == id) return _collegeFilterLabel(doc);
    }
    return '--';
  }

  Set<String> _collegeFilterAliases(String collegeId) {
    final id = collegeId.trim();
    final aliases = <String>{if (id.isNotEmpty) id};
    for (final doc in _userFilterCollegeOptions) {
      if (doc.id.trim() != id) continue;
      final data = doc.data();
      final code = (data['collegeCode'] ?? '').toString().trim();
      if (code.isNotEmpty) aliases.add(code);
      break;
    }
    return aliases;
  }

  String _programFilterLabelById(String programId) {
    final id = programId.trim();
    if (id.isEmpty || id == 'All') return 'All programs';
    for (final doc in _userFilterProgramOptions) {
      if (doc.id.trim() == id) return _programFilterLabel(doc);
    }
    return '--';
  }

  String _programDropdownLabel(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final code = (data['programCode'] ?? '').toString().trim();
    final name = (data['name'] ?? data['programName'] ?? data['title'] ?? '')
        .toString()
        .trim();
    if (code.isEmpty && name.isEmpty) return '--';
    if (name.isEmpty || name == code) return code.isEmpty ? name : code;
    return '${code.isEmpty ? name : code} - $name';
  }

  bool _matchesUserAdvancedFilters({
    required Map<String, dynamic> data,
    required String role,
    required String accountStatus,
    required String studentVerification,
  }) {
    final showStudentFilters =
        widget.studentsOnlyScope || widget.pendingApprovalOnlyScope;
    if (!showStudentFilters &&
        _userRoleFilter != 'All' &&
        role != _userRoleFilter) {
      return false;
    }
    if (_userAccountStatusFilter != 'All' &&
        accountStatus != _userAccountStatusFilter) {
      return false;
    }
    if (showStudentFilters && _userVerificationFilter != 'All') {
      if (!_isStudentRole(role)) return false;
      if (studentVerification != _userVerificationFilter) return false;
    }
    if (showStudentFilters && _userSourceFilter != 'All') {
      if (!_isStudentRole(role)) return false;
      if (_readAccountSource(data) != _userSourceFilter) return false;
    }
    if (_userCollegeFilter != 'All') {
      final acceptedCollegeValues = _collegeFilterAliases(_userCollegeFilter);
      if (_isStudentRole(role)) {
        final studentProfile =
            data['studentProfile'] as Map<String, dynamic>? ?? {};
        final collegeId = (studentProfile['collegeId'] ?? '').toString().trim();
        if (!acceptedCollegeValues.contains(collegeId)) return false;
      } else {
        final employeeProfile =
            data['employeeProfile'] as Map<String, dynamic>? ?? {};
        final department = (employeeProfile['department'] ?? '')
            .toString()
            .trim();
        if (!acceptedCollegeValues.contains(department)) return false;
      }
    }
    if (showStudentFilters && _userProgramFilter != 'All') {
      final studentProfile =
          data['studentProfile'] as Map<String, dynamic>? ?? {};
      final programId = (studentProfile['programId'] ?? '').toString().trim();
      if (programId != _userProgramFilter) return false;
    }
    return true;
  }

  bool _hasUserAdvancedFilters() {
    final showStudentFilters =
        widget.studentsOnlyScope || widget.pendingApprovalOnlyScope;
    return (!showStudentFilters && _userRoleFilter != 'All') ||
        _userAccountStatusFilter != 'All' ||
        _userCollegeFilter != 'All' ||
        (showStudentFilters && _userSourceFilter != 'All') ||
        (showStudentFilters && _userVerificationFilter != 'All') ||
        (showStudentFilters && _userProgramFilter != 'All');
  }

  void _clearUserAdvancedFilters() {
    setState(() {
      _userRoleFilter = 'All';
      _userSourceFilter = 'All';
      _userAccountStatusFilter = 'All';
      _userVerificationFilter = 'All';
      _userCollegeFilter = 'All';
      _userProgramFilter = 'All';
      _invalidateFilterCache();
    });
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
    final dn = (data['displayName'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    final first = (data['firstName'] ?? '').toString().trim();
    final middle = (data['middleName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final full = [
      first,
      middle,
      last,
    ].where((part) => part.isNotEmpty).join(' ').trim();
    if (full.isNotEmpty) return full;
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

  Widget _buildDetailIdentityAvatar(Map<String, dynamic> data, String name) {
    final source = _photoUrl(data);
    final future = source.trim().isEmpty
        ? Future<String>.value('')
        : _resolvedPhotoUrlCache.putIfAbsent(
            source,
            () => _resolvePhotoUrl(source),
          );

    return FutureBuilder<String>(
      key: ValueKey('profile-details-photo-${_selectedUserId ?? ''}-$source'),
      future: future,
      initialData: _isHttpPhotoUrl(source) ? source : '',
      builder: (context, snapshot) {
        final photoUrl = (snapshot.data ?? '').trim();
        return MouseRegion(
          cursor: photoUrl.isEmpty
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: photoUrl.isEmpty
                ? null
                : () => _openDetailProfilePhotoViewer(
                    sourceUrl: photoUrl,
                    displayName: name,
                  ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: photoUrl.isEmpty
                      ? const Icon(
                          Icons.person_rounded,
                          color: primaryColor,
                          size: 24,
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.md - 1),
                          child: Image.network(
                            photoUrl,
                            key: ValueKey(photoUrl),
                            fit: BoxFit.cover,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.prefer,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.person_rounded,
                              color: primaryColor,
                              size: 24,
                            ),
                          ),
                        ),
                ),
                if (photoUrl.isNotEmpty)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 17,
                      height: 17,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(color: Colors.white, width: 1.3),
                      ),
                      child: const Icon(
                        Icons.open_in_full_rounded,
                        color: Colors.white,
                        size: 10,
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

  Future<void> _openDetailProfilePhotoViewer({
    required String sourceUrl,
    required String displayName,
  }) async {
    if (sourceUrl.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName.trim().isEmpty
                            ? 'Profile Photo'
                            : displayName.trim(),
                        style: const TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: hintColor),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      sourceUrl,
                      fit: BoxFit.contain,
                      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                      errorBuilder: (_, __, ___) => Container(
                        width: 320,
                        height: 320,
                        alignment: Alignment.center,
                        color: primaryColor.withValues(alpha: 0.08),
                        child: const Icon(
                          Icons.person_rounded,
                          color: primaryColor,
                          size: 56,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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

      await AppFirestore.instance.collection('users').doc(targetUid).update({
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
      final snap = await AppFirestore.instance
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
      final byId = await AppFirestore.instance
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
        final byCode = await AppFirestore.instance
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
    final query = await AppFirestore.instance
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
    if (_detailStudentNoChecking) {
      return 'Checking Student Number availability...';
    }
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
    if (_detailEmployeeNoChecking) {
      return 'Checking Employee ID availability...';
    }
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
    final userRef = AppFirestore.instance.collection('users').doc(uid);
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

      await AppFirestore.instance
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
      await AppFirestore.instance
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
      stream: AppFirestore.instance
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
      _allUsersStream = AppFirestore.instance.collection('users').snapshots();
    });
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _isRefreshingTable = false);
  }

  Widget _buildHandbookStyleSearchBar({
    Widget? filterAction,
    Widget? compactTrailingAction,
  }) {
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
    final hasFilters = _hasUserAdvancedFilters();

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
          if (filterAction != null) ...[filterAction, const SizedBox(width: 8)],
          Expanded(child: searchField),
          const SizedBox(width: 8),
          refreshButton,
          if (hasFilters) ...[
            const SizedBox(width: 8),
            _buildUserClearFiltersIconButton(),
          ],
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

  Widget _buildUserFilterButton() {
    final size = 44.0;
    final hasFilters = _hasUserAdvancedFilters();

    return Tooltip(
      message: 'Advanced filters',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _openUserFiltersSheet,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hasFilters
                ? primaryColor.withValues(alpha: 0.12)
                : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: hasFilters
                  ? primaryColor.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.tune_rounded,
            color: hasFilters ? primaryColor : hintColor.withValues(alpha: 0.9),
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildUserClearFiltersIconButton() {
    final hasFilters = _hasUserAdvancedFilters();
    return Tooltip(
      message: 'Clear filters',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: hasFilters ? _clearUserAdvancedFilters : null,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.filter_alt_off_rounded,
            color: hasFilters
                ? primaryColor.withValues(alpha: 0.9)
                : hintColor.withValues(alpha: 0.75),
            size: 19,
          ),
        ),
      ),
    );
  }

  Future<void> _openUserFiltersSheet() async {
    var role = _userRoleFilter;
    var source = _userSourceFilter;
    var accountStatus = _userAccountStatusFilter;
    var verification = _userVerificationFilter;
    var college = _userCollegeFilter;
    var program = _userProgramFilter;
    final panelWidth = min(390.0, MediaQuery.sizeOf(context).width - 20);
    final showStudentFilters =
        widget.studentsOnlyScope || widget.pendingApprovalOnlyScope;

    List<DropdownMenuItem<String>> roleItems() {
      final items = <String>['All'];
      if (widget.professorsOnlyScope) {
        items.add('professor');
      } else {
        items.addAll([
          'professor',
          'osa_admin',
          'department_admin',
          'counseling_admin',
          'guard',
        ]);
      }
      return items
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(value == 'All' ? 'All roles' : _formatRole(value)),
            ),
          )
          .toList();
    }

    List<DropdownMenuItem<String>> collegeItems() {
      return [
        const DropdownMenuItem(value: 'All', child: Text('All colleges')),
        ..._userFilterCollegeOptions.map(
          (doc) => DropdownMenuItem(
            value: doc.id,
            child: Text(_collegeFilterLabel(doc)),
          ),
        ),
      ];
    }

    List<DropdownMenuItem<String>> programItems({required String collegeId}) {
      final filtered = _userFilterProgramOptions.where((doc) {
        if (collegeId == 'All') return true;
        final data = doc.data();
        return (data['collegeId'] ?? '').toString().trim() == collegeId;
      }).toList();
      return [
        const DropdownMenuItem(value: 'All', child: Text('All programs')),
        ...filtered.map(
          (doc) => DropdownMenuItem(
            value: doc.id,
            child: Text(_programFilterLabel(doc)),
          ),
        ),
      ];
    }

    Widget dropdown({
      required String label,
      required String value,
      required List<DropdownMenuItem<String>> items,
      required ValueChanged<String> onChanged,
    }) {
      final values = items
          .map((item) => item.value)
          .whereType<String>()
          .toSet();
      final safeValue = values.contains(value) ? value : 'All';
      return DropdownButtonFormField<String>(
        initialValue: safeValue,
        isExpanded: true,
        menuMaxHeight: 320,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: hintColor,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.20)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.20)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: primaryColor, width: 1.6),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
        items: items,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
    }

    Widget filterRow(List<Widget> fields) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            Expanded(child: fields[i]),
            if (i < fields.length - 1) const SizedBox(width: 14),
          ],
        ],
      );
    }

    List<_UserFilterChipData> draftChips(StateSetter setModalState) {
      final chips = <_UserFilterChipData>[];
      if (!showStudentFilters && role != 'All') {
        chips.add(
          _UserFilterChipData(
            label: 'Role: ${_formatRole(role)}',
            onRemove: () => setModalState(() => role = 'All'),
          ),
        );
      }
      if (accountStatus != 'All') {
        chips.add(
          _UserFilterChipData(
            label: 'Account: ${accountStatus.replaceAll('_', ' ')}',
            onRemove: () => setModalState(() => accountStatus = 'All'),
          ),
        );
      }
      if (college != 'All') {
        chips.add(
          _UserFilterChipData(
            label: 'College: ${_collegeFilterLabelById(college)}',
            onRemove: () => setModalState(() {
              college = 'All';
              program = 'All';
            }),
          ),
        );
      }
      if (showStudentFilters && program != 'All') {
        chips.add(
          _UserFilterChipData(
            label: 'Program: ${_programFilterLabelById(program)}',
            onRemove: () => setModalState(() => program = 'All'),
          ),
        );
      }
      if (showStudentFilters && source != 'All') {
        chips.add(
          _UserFilterChipData(
            label: 'Source: ${_accountSourceLabel(source)}',
            onRemove: () => setModalState(() => source = 'All'),
          ),
        );
      }
      if (showStudentFilters && verification != 'All') {
        chips.add(
          _UserFilterChipData(
            label: 'Verification: ${verification.replaceAll('_', ' ')}',
            onRemove: () => setModalState(() => verification = 'All'),
          ),
        );
      }
      return chips;
    }

    Widget panel(StateSetter setModalState, VoidCallback close) {
      final chips = draftChips(setModalState);
      final collegeField = dropdown(
        label: 'College',
        value: college,
        items: collegeItems(),
        onChanged: (v) {
          setModalState(() {
            college = v;
            if (program != 'All') {
              final programDocMatchesCollege = _userFilterProgramOptions.any((
                doc,
              ) {
                if (doc.id != program) return false;
                if (college == 'All') return true;
                return (doc.data()['collegeId'] ?? '').toString().trim() ==
                    college;
              });
              if (!programDocMatchesCollege) {
                program = 'All';
              }
            }
          });
        },
      );
      final accountField = dropdown(
        label: 'Account Status',
        value: accountStatus,
        items: const [
          DropdownMenuItem(value: 'All', child: Text('All account status')),
          DropdownMenuItem(value: 'active', child: Text('Active')),
          DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
        ],
        onChanged: (v) => setModalState(() => accountStatus = v),
      );
      final roleField = dropdown(
        label: 'Role',
        value: role,
        items: roleItems(),
        onChanged: (v) => setModalState(() => role = v),
      );
      final programField = dropdown(
        label: 'Program',
        value: program,
        items: programItems(collegeId: college),
        onChanged: (v) => setModalState(() => program = v),
      );
      final sourceField = dropdown(
        label: 'Source',
        value: source,
        items: const [
          DropdownMenuItem(value: 'All', child: Text('All sources')),
          DropdownMenuItem(value: 'self_signup', child: Text('Self Signup')),
          DropdownMenuItem(value: 'admin_manual', child: Text('Admin Created')),
          DropdownMenuItem(value: 'admin_import', child: Text('Imported')),
        ],
        onChanged: (v) => setModalState(() => source = v),
      );
      final verificationField = dropdown(
        label: 'Verification Status',
        value: verification,
        items: const [
          DropdownMenuItem(
            value: 'All',
            child: Text('All verification status'),
          ),
          DropdownMenuItem(
            value: 'pending_email_verification',
            child: Text('Email Pending'),
          ),
          DropdownMenuItem(
            value: 'pending_profile',
            child: Text('Profile Pending'),
          ),
          DropdownMenuItem(
            value: 'pending_approval',
            child: Text('Approval Pending'),
          ),
          DropdownMenuItem(value: 'verified', child: Text('Verified')),
          DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
        ],
        onChanged: (v) => setModalState(() => verification = v),
      );

      return Container(
        width: panelWidth,
        margin: const EdgeInsets.fromLTRB(10, 12, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(-2, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Advanced Filters',
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: close,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Filter user records by key attributes.',
              style: TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: Colors.black.withValues(alpha: 0.08)),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (chips.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...chips.map(_buildUserActiveFilterChip),
                          OutlinedButton.icon(
                            onPressed: () {
                              setModalState(() {
                                role = 'All';
                                source = 'All';
                                accountStatus = 'All';
                                verification = 'All';
                                college = 'All';
                                program = 'All';
                              });
                            },
                            icon: const Icon(
                              Icons.filter_alt_off_rounded,
                              size: 16,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(
                                color: primaryColor.withValues(alpha: 0.25),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            label: const Text(
                              'Clear Filters',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth >= 620) {
                          return Column(
                            children: [
                              filterRow([roleField, collegeField]),
                              const SizedBox(height: 14),
                              filterRow([
                                accountField,
                                showStudentFilters ? programField : sourceField,
                              ]),
                              const SizedBox(height: 14),
                              if (showStudentFilters)
                                filterRow([sourceField, verificationField])
                              else
                                verificationField,
                            ],
                          );
                        }
                        return Column(
                          children: [
                            if (!showStudentFilters) ...[
                              roleField,
                              const SizedBox(height: 12),
                              collegeField,
                              const SizedBox(height: 12),
                              accountField,
                              const SizedBox(height: 12),
                              sourceField,
                              const SizedBox(height: 12),
                              verificationField,
                            ] else ...[
                              collegeField,
                              const SizedBox(height: 12),
                              accountField,
                              const SizedBox(height: 12),
                              programField,
                              const SizedBox(height: 12),
                              sourceField,
                              const SizedBox(height: 12),
                              verificationField,
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    setModalState(() {
                      role = 'All';
                      source = 'All';
                      accountStatus = 'All';
                      verification = 'All';
                      college = 'All';
                      program = 'All';
                    });
                  },
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _userRoleFilter = showStudentFilters ? 'All' : role;
                      _userSourceFilter = showStudentFilters ? source : 'All';
                      _userAccountStatusFilter = accountStatus;
                      _userVerificationFilter = showStudentFilters
                          ? verification
                          : 'All';
                      _userCollegeFilter = college;
                      _userProgramFilter = showStudentFilters ? program : 'All';
                      _invalidateFilterCache();
                    });
                    close();
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Apply Filters'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Advanced Filters',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Material(
                color: Colors.transparent,
                child: SafeArea(
                  child: panel(
                    setModalState,
                    () => Navigator.of(context).pop(),
                  ),
                ),
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final offsetTween = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        );
        return SlideTransition(
          position: offsetTween.animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  List<Widget> _buildUserActiveFilterChips() {
    final chips = <_UserFilterChipData>[];
    final showStudentFilters =
        widget.studentsOnlyScope || widget.pendingApprovalOnlyScope;
    if (_searchQuery.isNotEmpty) {
      chips.add(
        _UserFilterChipData(
          label: 'Search: ${_searchCtrl.text.trim()}',
          onRemove: _clearSearchQuery,
        ),
      );
    }
    if (!showStudentFilters && _userRoleFilter != 'All') {
      chips.add(
        _UserFilterChipData(
          label: 'Role: ${_formatRole(_userRoleFilter)}',
          onRemove: () => setState(() {
            _userRoleFilter = 'All';
            _invalidateFilterCache();
          }),
        ),
      );
    }
    if (showStudentFilters && _userSourceFilter != 'All') {
      chips.add(
        _UserFilterChipData(
          label: 'Source: ${_accountSourceLabel(_userSourceFilter)}',
          onRemove: () => setState(() {
            _userSourceFilter = 'All';
            _invalidateFilterCache();
          }),
        ),
      );
    }
    if (_userAccountStatusFilter != 'All') {
      chips.add(
        _UserFilterChipData(
          label: 'Account: ${_userAccountStatusFilter.replaceAll('_', ' ')}',
          onRemove: () => setState(() {
            _userAccountStatusFilter = 'All';
            _invalidateFilterCache();
          }),
        ),
      );
    }
    if (showStudentFilters && _userVerificationFilter != 'All') {
      chips.add(
        _UserFilterChipData(
          label:
              'Verification: ${_userVerificationFilter.replaceAll('_', ' ')}',
          onRemove: () => setState(() {
            _userVerificationFilter = 'All';
            _invalidateFilterCache();
          }),
        ),
      );
    }
    if (_userCollegeFilter != 'All') {
      chips.add(
        _UserFilterChipData(
          label: 'College: ${_collegeFilterLabelById(_userCollegeFilter)}',
          onRemove: () => setState(() {
            _userCollegeFilter = 'All';
            _userProgramFilter = 'All';
            _invalidateFilterCache();
          }),
        ),
      );
    }
    if (showStudentFilters && _userProgramFilter != 'All') {
      chips.add(
        _UserFilterChipData(
          label: 'Program: ${_programFilterLabelById(_userProgramFilter)}',
          onRemove: () => setState(() {
            _userProgramFilter = 'All';
            _invalidateFilterCache();
          }),
        ),
      );
    }
    if (chips.isEmpty) return const [];

    return [
      ...chips.map(
        (chip) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _buildUserActiveFilterChip(chip),
        ),
      ),
      OutlinedButton.icon(
        onPressed: _clearUserAdvancedFilters,
        icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor.withValues(alpha: 0.25)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        label: const Text(
          'Clear All',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    ];
  }

  Widget _buildUserActiveFilterChip(_UserFilterChipData chip) {
    final raw = chip.label.trim();
    final splitIndex = raw.indexOf(':');
    final hasFieldLabel = splitIndex > 0 && splitIndex < raw.length - 1;
    final fieldLabel = hasFieldLabel ? raw.substring(0, splitIndex).trim() : '';
    final fieldValue = hasFieldLabel
        ? raw.substring(splitIndex + 1).trim()
        : raw;

    return InputChip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      onDeleted: chip.onRemove,
      deleteIcon: Icon(
        Icons.close_rounded,
        size: 16,
        color: primaryColor.withValues(alpha: 0.9),
      ),
      deleteButtonTooltipMessage: 'Remove filter',
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      backgroundColor: const Color(0xFFF7FBF7),
      side: BorderSide(color: primaryColor.withValues(alpha: 0.25)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      label: RichText(
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            if (hasFieldLabel)
              TextSpan(
                text: '$fieldLabel: ',
                style: const TextStyle(
                  color: hintColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            TextSpan(
              text: fieldValue,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w800,
                fontSize: 12.8,
              ),
            ),
          ],
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
        _filterCacheRoleFilter == _userRoleFilter &&
        _filterCacheSourceFilter == _userSourceFilter &&
        _filterCacheAccountStatusFilter == _userAccountStatusFilter &&
        _filterCacheVerificationFilter == _userVerificationFilter &&
        _filterCacheCollegeFilter == _userCollegeFilter &&
        _filterCacheProgramFilter == _userProgramFilter &&
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
          if (!_matchesUserAdvancedFilters(
            data: data,
            role: role,
            accountStatus: accountStatus,
            studentVerification: studentVerification,
          )) {
            return false;
          }
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
    _filterCacheRoleFilter = _userRoleFilter;
    _filterCacheSourceFilter = _userSourceFilter;
    _filterCacheAccountStatusFilter = _userAccountStatusFilter;
    _filterCacheVerificationFilter = _userVerificationFilter;
    _filterCacheCollegeFilter = _userCollegeFilter;
    _filterCacheProgramFilter = _userProgramFilter;
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

  Future<bool> _ensureStudentAcademicSetup({
    required String actionLabel,
  }) async {
    try {
      final db = AppFirestore.instance;
      final results = await Future.wait([
        db
            .collection('colleges')
            .where('active', isEqualTo: true)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 8)),
        db
            .collection('programs')
            .where('active', isEqualTo: true)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 8)),
      ]);

      final hasCollege = results[0].docs.isNotEmpty;
      final hasProgram = results[1].docs.isNotEmpty;
      if (hasCollege && hasProgram) return true;

      if (!mounted) return false;
      final missing = <String>[
        if (!hasCollege) 'active college',
        if (!hasProgram) 'active program',
      ].join(' and ');
      AppScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot $actionLabel yet. Please add at least one $missing in Institution Setup first.',
          ),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      AppScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to verify colleges/programs right now. Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Future<void> _openCreateUser() async {
    if (widget.studentsOnlyScope) {
      final canCreateStudent = await _ensureStudentAcademicSetup(
        actionLabel: 'create student accounts',
      );
      if (!canCreateStudent || !mounted) return;
    }

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
    final canImportStudents = await _ensureStudentAcademicSetup(
      actionLabel: 'import student accounts',
    );
    if (!canImportStudents || !mounted) return;

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
            'Import complete: ${commit.created} created, ${commit.updated} updated, ${dialogResult.noChangeCount} unchanged skipped, ${dialogResult.invalidCount} invalid skipped.',
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

  String _cleanNamePart(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _formatImportSuffix(String input) {
    final cleaned = _cleanNamePart(input);
    final normalized = cleaned.replaceAll('.', '').toUpperCase();
    if (normalized == 'JR' || normalized == 'SR') return '$normalized.';
    return normalized;
  }

  bool _looksLikeSuffix(String input) {
    final value = _cleanNamePart(
      input,
    ).replaceAll('.', '').toUpperCase().trim();
    return {
      'JR',
      'SR',
      'II',
      'III',
      'IV',
      'V',
      'VI',
      'VII',
      'VIII',
      'IX',
      'X',
    }.contains(value);
  }

  _ParsedImportName _parseImportStudentName(String rawName) {
    final raw = _cleanNamePart(rawName);
    if (raw.isEmpty) return const _ParsedImportName.empty();

    final parts = raw
        .split(',')
        .map(_cleanNamePart)
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) {
      final display = _titleCaseWords(raw);
      return _ParsedImportName(
        displayName: display,
        firstName: display,
        middleName: '',
        lastName: '',
        suffix: '',
      );
    }

    final lastName = _titleCaseWords(parts[0]);
    final firstName = _titleCaseWords(parts[1]);
    var middleName = '';
    var suffix = '';

    if (parts.length >= 3) {
      if (parts.length == 3 && _looksLikeSuffix(parts[2])) {
        suffix = _formatImportSuffix(parts[2]);
      } else {
        middleName = _titleCaseWords(parts[2]);
        if (parts.length >= 4) suffix = _formatImportSuffix(parts[3]);
      }
    }

    final displayName = [
      '${lastName.toUpperCase()},',
      firstName,
      suffix,
    ].where((part) => part.trim().isNotEmpty).join(' ').trim();

    return _ParsedImportName(
      displayName: displayName,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      suffix: suffix,
    );
  }

  String _displayNameFromParts({
    required String firstName,
    required String middleName,
    required String lastName,
    String suffix = '',
  }) {
    return [
      firstName.trim(),
      middleName.trim(),
      lastName.trim(),
      suffix.trim(),
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
    final idxStudentName = _headerIndex(headerIndexByKey, [
      'studentName',
      'student name',
      'name',
      'fullName',
      'full name',
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
    final idxProgram = _headerIndex(headerIndexByKey, [
      'program',
      'programId',
      'program id',
      'program code',
      'course',
      'program strand',
      'program / strand',
      'program/strand',
    ]);
    final idxEmail = _headerIndex(headerIndexByKey, [
      'email',
      'emailAddress',
      'email address',
    ]);

    final missingHeaders = <String>[
      if (idxStudentNo == null) 'studentNo',
      if (idxStudentName == null &&
          (idxFirstName == null || idxLastName == null))
        'studentName',
      if (idxProgram == null) 'program',
      if (idxEmail == null) 'email',
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

    final db = AppFirestore.instance;
    final collegeSnap = await db
        .collection('colleges')
        .where('active', isEqualTo: true)
        .get();
    final programSnap = await db
        .collection('programs')
        .where('active', isEqualTo: true)
        .get();
    final usersSnap = await db.collection('users').get();

    final activeCollegeIds = collegeSnap.docs.map((doc) => doc.id).toSet();
    final programLookup =
        <String, ({String programId, String collegeId, String label})>{};
    final programLabelById = <String, String>{};
    for (final doc in programSnap.docs) {
      final data = doc.data();
      final programId = doc.id.trim();
      final collegeId = (data['collegeId'] ?? '').toString().trim();
      if (collegeId.isEmpty || !activeCollegeIds.contains(collegeId)) continue;
      final code = (data['programCode'] ?? '').toString().trim();
      final name = (data['name'] ?? data['programName'] ?? data['title'] ?? '')
          .toString()
          .trim();
      final label = [
        code,
        name,
      ].where((value) => value.trim().isNotEmpty).join(' - ').trim();
      programLabelById[programId] = label.isEmpty ? programId : label;
      for (final raw in [programId, code, name]) {
        final key = _importKey(raw);
        if (key.isEmpty) continue;
        programLookup.putIfAbsent(
          key,
          () => (
            programId: programId,
            collegeId: collegeId,
            label: label.isEmpty ? programId : label,
          ),
        );
      }
    }

    final existingStudentNoToUser =
        <String, ({String uid, String email, Map<String, dynamic> data})>{};
    final existingEmailToUid = <String, String>{};
    for (final doc in usersSnap.docs) {
      final data = doc.data();
      final role = (data['role'] ?? '').toString().trim().toLowerCase();
      final email = (data['email'] ?? '').toString().trim().toLowerCase();
      if (role == 'student') {
        final profile = data['studentProfile'] as Map<String, dynamic>?;
        final studentNo = (profile?['studentNo'] ?? data['studentNo'] ?? '')
            .toString()
            .trim();
        if (studentNo.isNotEmpty) {
          existingStudentNoToUser.putIfAbsent(
            studentNo,
            () => (uid: doc.id, email: email, data: data),
          );
        }
      }
      if (email.isNotEmpty) {
        existingEmailToUid.putIfAbsent(email, () => doc.id);
      }
    }

    final issues = <_StudentImportIssue>[];
    final valids = <_ImportedStudentDraft>[];
    final seenStudentNos = <String>{};
    final seenEmails = <String>{};
    String normalizeImportValue(dynamic value) =>
        (value ?? '').toString().trim();

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowNumber = i + 1;

      final studentNo = _csvCell(row, idxStudentNo);
      final rawStudentName = _csvCell(row, idxStudentName);
      final parsedName = idxStudentName == null
          ? null
          : _parseImportStudentName(rawStudentName);
      final firstName =
          parsedName?.firstName ?? _titleCaseWords(_csvCell(row, idxFirstName));
      final middleName =
          parsedName?.middleName ??
          _titleCaseWords(_csvCell(row, idxMiddleName));
      final lastName =
          parsedName?.lastName ?? _titleCaseWords(_csvCell(row, idxLastName));
      final suffix = parsedName?.suffix ?? '';
      final programRaw = _csvCell(row, idxProgram);
      final email = _csvCell(row, idxEmail).toLowerCase();
      final programToken = programRaw.trim().split(RegExp(r'\s+')).first;
      final nameForDisplay = (parsedName?.displayName ?? '').isNotEmpty
          ? parsedName!.displayName
          : _displayNameFromParts(
              firstName: firstName,
              middleName: middleName,
              lastName: lastName,
              suffix: suffix,
            );

      final isCompletelyBlank = [
        studentNo,
        nameForDisplay,
        programRaw,
        email,
      ].every((v) => v.trim().isEmpty);
      if (isCompletelyBlank) continue;

      final rowErrors = <String>[];
      if (studentNo.isEmpty) rowErrors.add('Student Number is required.');
      if (nameForDisplay.isEmpty) rowErrors.add('Student Name is required.');
      if (programRaw.isEmpty) rowErrors.add('Program is required.');
      if (email.isEmpty) rowErrors.add('School email is required.');

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

      final matchedProgram = programLookup[_importKey(programToken)];
      final collegeId = matchedProgram?.collegeId ?? '';
      final programId = matchedProgram?.programId ?? '';
      if (programRaw.isNotEmpty && matchedProgram == null) {
        rowErrors.add('Unknown program: "$programToken".');
      }

      final existingStudent = existingStudentNoToUser[studentNo];
      final existingUid = existingStudent?.uid;
      if (existingStudent != null && existingStudent.email != email) {
        rowErrors.add(
          'Student Number already exists with a different school email.',
        );
      }
      if (email.isNotEmpty) {
        final existingUidByEmail = existingEmailToUid[email];
        if (existingUidByEmail != null && existingUidByEmail != existingUid) {
          rowErrors.add(
            existingUid == null
                ? 'School email already belongs to another account.'
                : 'School email belongs to another account and cannot be used to update this student.',
          );
        }
      }

      if (rowErrors.isNotEmpty) {
        issues.add(
          _StudentImportIssue(
            rowNumber: rowNumber,
            studentNo: studentNo,
            fullName: nameForDisplay,
            program: programRaw,
            email: email,
            message: rowErrors.join(' '),
          ),
        );
        continue;
      }

      var hasChanges = existingUid == null;
      var changeSummary = existingUid == null ? 'New student account' : '';
      if (existingStudent != null) {
        final existingData = existingStudent.data;
        final existingProfile =
            existingData['studentProfile'] as Map<String, dynamic>? ?? {};
        bool differs(dynamic current, String imported) {
          return normalizeImportValue(current) != imported.trim();
        }

        String existingProgramLabel() {
          final id = normalizeImportValue(existingProfile['programId']);
          return programLabelById[id] ?? id;
        }

        String summarizeChange(String label, String before, String after) {
          final oldValue = before.trim().isEmpty ? '-' : before.trim();
          final newValue = after.trim().isEmpty ? '-' : after.trim();
          return '$label: $oldValue -> $newValue';
        }

        final changes = <String>[];
        if (differs(existingData['displayName'], nameForDisplay)) {
          changes.add(
            summarizeChange(
              'Name',
              normalizeImportValue(existingData['displayName']),
              nameForDisplay,
            ),
          );
        }
        if (differs(existingProfile['programId'], programId)) {
          changes.add(
            summarizeChange(
              'Program',
              existingProgramLabel(),
              matchedProgram?.label ?? programRaw,
            ),
          );
        }
        if (differs(existingProfile['collegeId'], collegeId)) {
          changes.add(
            summarizeChange(
              'College',
              normalizeImportValue(existingProfile['collegeId']),
              collegeId,
            ),
          );
        }

        hasChanges =
            differs(existingData['firstName'], firstName) ||
            differs(existingData['middleName'], middleName) ||
            differs(existingData['lastName'], lastName) ||
            differs(existingData['suffix'], suffix) ||
            differs(existingData['displayName'], nameForDisplay) ||
            differs(existingProfile['studentNo'], studentNo) ||
            differs(existingProfile['collegeId'], collegeId) ||
            differs(existingProfile['programId'], programId);
        changeSummary = hasChanges
            ? (changes.isEmpty
                  ? 'Profile fields changed'
                  : changes.take(3).join(' | '))
            : 'No profile changes detected';
      }

      valids.add(
        _ImportedStudentDraft(
          rowNumber: rowNumber,
          studentNo: studentNo,
          displayName: nameForDisplay,
          firstName: firstName,
          middleName: middleName,
          lastName: lastName,
          suffix: suffix,
          collegeId: collegeId,
          programId: programId,
          programLabel: programRaw,
          email: email,
          existingUid: existingUid,
          hasChanges: hasChanges,
          changeSummary: changeSummary,
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

    final db = AppFirestore.instance;
    final createdByUid = FirebaseAuth.instance.currentUser?.uid;
    final newRows = rows.where((row) => row.existingUid == null).toList();
    FirebaseApp? secondaryApp;
    FirebaseAuth? secondaryAuth;
    if (newRows.isNotEmpty) {
      final primary = Firebase.app();
      secondaryApp = await Firebase.initializeApp(
        name: 'student_import_${DateTime.now().microsecondsSinceEpoch}',
        options: primary.options,
      );
      secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    }

    WriteBatch batch = db.batch();
    var pendingWrites = 0;

    Future<void> flushIfNeeded({bool force = false}) async {
      if (!force && pendingWrites < 400) return;
      if (pendingWrites == 0) return;
      await batch.commit();
      batch = db.batch();
      pendingWrites = 0;
    }

    try {
      for (final row in rows) {
        final isNew = row.existingUid == null;
        if (!isNew && !row.hasChanges) continue;
        final displayName = row.fullName;

        if (isNew) {
          if (secondaryAuth == null) {
            throw StateError('Student import auth session is not ready.');
          }
          User? createdUser;
          DocumentReference<Map<String, dynamic>>? docRef;
          var docWritten = false;
          try {
            final password = _randomPassword();
            final cred = await _createUserWithRetry(
              auth: secondaryAuth,
              email: row.email,
              password: password,
            );
            createdUser = cred.user;
            if (createdUser == null) {
              throw StateError('Failed to create auth user for ${row.email}.');
            }

            docRef = db.collection('users').doc(createdUser.uid);
            final verification = 'pending_email_verification';
            final status = _legacyStatusValue(
              role: 'student',
              accountStatus: 'active',
              studentVerificationStatus: verification,
            );

            await docRef.set({
              'uid': createdUser.uid,
              'email': row.email,
              'firstName': row.firstName,
              'middleName': row.middleName.isEmpty ? null : row.middleName,
              'lastName': row.lastName,
              'suffix': row.suffix.isEmpty ? null : row.suffix,
              'displayName': displayName.isEmpty ? null : displayName,
              'role': 'student',
              'accountStatus': 'active',
              'studentVerificationStatus': verification,
              'status': status,
              'accountSource': 'admin_import',
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
            docWritten = true;
            await _sendSetPasswordLink(row.email);
            created++;
            continue;
          } catch (_) {
            if (docWritten && docRef != null) {
              try {
                await docRef.delete();
              } catch (_) {}
            }
            if (createdUser != null) {
              try {
                await createdUser.delete();
              } catch (_) {}
            }
            rethrow;
          }
        }

        final docRef = db.collection('users').doc(row.existingUid!);
        final update = <String, dynamic>{
          'firstName': row.firstName,
          'middleName': row.middleName.isEmpty ? null : row.middleName,
          'lastName': row.lastName,
          'suffix': row.suffix.isEmpty ? null : row.suffix,
          'displayName': displayName.isEmpty ? null : displayName,
          'accountSource': 'admin_import',
          'importedByAdmin': true,
          'directoryVisible': true,
          'studentProfile': {
            'studentNo': row.studentNo,
            'collegeId': row.collegeId,
            'programId': row.programId,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        };
        batch.set(docRef, update, SetOptions(merge: true));
        updated++;

        pendingWrites++;
        await flushIfNeeded();
      }

      await flushIfNeeded(force: true);
      return _StudentImportCommitResult(created: created, updated: updated);
    } finally {
      if (secondaryAuth != null) {
        await secondaryAuth.signOut();
      }
      if (secondaryApp != null) {
        await secondaryApp.delete();
      }
    }
  }

  Future<void> _loadUserAcademicFilterOptions() async {
    try {
      final db = AppFirestore.instance;
      final results = await Future.wait([
        db.collection('colleges').get().timeout(const Duration(seconds: 8)),
        db.collection('programs').get().timeout(const Duration(seconds: 8)),
      ]);
      if (!mounted) return;

      final colleges = results[0].docs.toList()
        ..sort(
          (a, b) => _collegeFilterLabel(a).compareTo(_collegeFilterLabel(b)),
        );
      final programs = results[1].docs.toList()
        ..sort(
          (a, b) => _programFilterLabel(a).compareTo(_programFilterLabel(b)),
        );

      setState(() {
        _userFilterCollegeOptions = colleges;
        _userFilterProgramOptions = programs;
      });
    } catch (_) {
      // Filters still work with raw IDs if the setup collections cannot load.
    }
  }

  Future<void> _createAuthAndUserDoc(_CreateUserResult input) async {
    final normalizedEmail = input.email.trim().toLowerCase();

    Future<bool> existsByField(String field, String value) async {
      final q = await AppFirestore.instance
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
        email: normalizedEmail,
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
      final isStudent = _isStudentRole(input.role);
      final displayName = [
        firstName,
        middleName,
        lastName,
      ].where((p) => p.trim().isNotEmpty).join(' ').trim();
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

      await AppFirestore.instance.collection('users').doc(createdUser.uid).set({
        'uid': createdUser.uid,
        'email': (createdUser.email ?? normalizedEmail).trim().toLowerCase(),
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
        'accountSource': 'admin_manual',
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
          await _sendSetPasswordLink(normalizedEmail);
        } else {
          await _sendVerifyEmailLinkWithPassword(
            normalizedEmail,
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

  Future<void> _sendSetPasswordLink(String email) async {
    final continueUrl = _resolveSetPasswordContinueUrl();
    final verifyContinueUrl = _resolveVerifyContinueUrl();
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-east1',
    ).httpsCallable('createCustomSetPasswordLink');
    final res = await callable.call<Map<dynamic, dynamic>>(<String, dynamic>{
      'email': email,
      'continueUrl': continueUrl,
      'verifyContinueUrl': verifyContinueUrl,
    });
    final data = (res.data ?? const <dynamic, dynamic>{})
        .cast<dynamic, dynamic>();
    final customLink = (data['customLink'] ?? '').toString().trim();
    if (customLink.isEmpty || data['mailQueued'] != true) {
      throw StateError('Account setup email was not queued.');
    }
  }

  Future<void> _sendVerifyEmailLinkWithPassword(
    String email,
    String temporaryPassword,
  ) async {
    final continueUrl = _resolveLoginContinueUrl(email);
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-east1',
    ).httpsCallable('createCustomVerifyEmailLink');
    final res = await callable.call<Map<dynamic, dynamic>>(<String, dynamic>{
      'email': email,
      'continueUrl': continueUrl,
      'temporaryPassword': temporaryPassword,
    });
    final data = (res.data ?? const <dynamic, dynamic>{})
        .cast<dynamic, dynamic>();
    final verifyLink = (data['verifyLink'] ?? '').toString().trim();
    if (verifyLink.isEmpty || data['mailQueued'] != true) {
      throw StateError('Verify-email message was not queued.');
    }
  }

  String _resolveSetPasswordContinueUrl() {
    const configuredContinueUrl = String.fromEnvironment(
      'PASSWORD_RESET_CONTINUE_URL',
    );
    if (kIsWeb) {
      return '${Uri.base.origin}/set-password';
    }
    return configuredContinueUrl.isNotEmpty
        ? configuredContinueUrl
        : '${Uri.base.origin}/set-password';
  }

  String _resolveLoginContinueUrl(String email) {
    if (kIsWeb) {
      return '${Uri.base.origin}/login?prefillEmail=${Uri.encodeComponent(email)}';
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

      await AppFirestore.instance.collection('users').doc(uid).update(update);
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
                filterAction: _buildUserFilterButton(),
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
              filters: _buildUserActiveFilterChips(),
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
                      return _buildDesktopDetailsPanel(
                        selectedDoc: selectedDoc,
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
          final hasFilters =
              _hasUserAdvancedFilters() || _searchQuery.isNotEmpty;
          final isStudentList =
              widget.studentsOnlyScope ||
              widget.pendingApprovalOnlyScope ||
              type == 'students' ||
              type == 'active_students' ||
              type == 'pending' ||
              type == 'pending_approval_queue';
          final isStaffList =
              type == 'staff' ||
              type == 'active_staff' ||
              type == 'inactive_staff';
          final emptyLabel = hasFilters
              ? (isStudentList
                    ? 'No students match these filters'
                    : (widget.professorsOnlyScope
                          ? 'No professors match these filters'
                          : (isStaffList
                                ? 'No staff match these filters'
                                : 'No users match these filters')))
              : (isStudentList
                    ? 'No students found'
                    : (widget.professorsOnlyScope
                          ? 'No professors found'
                          : (isStaffList
                                ? 'No staff found'
                                : 'No users found')));
          final emptySubtitle = hasFilters
              ? 'Try adjusting the selected filters or clear them to show more users.'
              : 'There are no users to show in this list yet.';
          return AppEmptyState(
            icon: Icons.person_search_rounded,
            title: emptyLabel,
            subtitle: emptySubtitle,
            actionLabel: hasFilters ? 'Clear Filters' : null,
            onAction: hasFilters
                ? () {
                    _clearSearchQuery();
                    if (_hasUserAdvancedFilters()) {
                      _clearUserAdvancedFilters();
                    }
                  }
                : null,
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
    final showSourceColumn =
        type == 'pending' &&
        _pendingStudentFilter == 'pending_email_verification';

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
                4 +
                (showSourceColumn ? 1 : 0) +
                (showRoleColumn ? 1 : 0) +
                (showAccountStatusColumn ? 1 : 0) +
                (showVerificationColumn ? 1 : 0);
            const nameWeight = 2.4;
            const idWeight = 1.2;
            const sourceWeight = 1.3;
            const affiliationWeight = 1.7;
            const emailWeight = 2.8;
            const roleWeight = 1.3;
            const accountStatusWeight = 1.2;
            const verificationWeight = 1.5;
            final totalWeight =
                nameWeight +
                idWeight +
                (showSourceColumn ? sourceWeight : 0) +
                affiliationWeight +
                emailWeight +
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
            final idColWidth = colWidth(idWeight, 120, compactMinWidth: 100);
            final sourceColWidth = showSourceColumn
                ? colWidth(sourceWeight, 140, compactMinWidth: 118)
                : 0.0;
            final affiliationColWidth = colWidth(
              affiliationWeight,
              170,
              compactMinWidth: 130,
            );
            final emailColWidth = colWidth(
              emailWeight,
              220,
              compactMinWidth: 180,
            );
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
                    if (showSourceColumn)
                      DataColumn(
                        label: SizedBox(
                          width: sourceColWidth,
                          child: Text(
                            'SOURCE',
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
                        width: affiliationColWidth,
                        child: Text(
                          'COLLEGE',
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
                    final affiliation = _displayAffiliation(data);
                    final role = (data['role'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();
                    final accountStatus = _readAccountStatus(data, role: role);
                    final studentVerification = _readStudentVerification(
                      data,
                      role: role,
                    );
                    final accountSource = _readAccountSource(data);

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
                        if (showSourceColumn)
                          DataCell(
                            SizedBox(
                              width: sourceColWidth,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _buildAccountSourceChip(
                                  accountSource,
                                  compact: true,
                                ),
                              ),
                            ),
                          ),
                        DataCell(
                          SizedBox(
                            width: affiliationColWidth,
                            child: Text(
                              affiliation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w700,
                              ),
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
        final code = (row['programCode'] ?? '').toString().trim();
        final name = (row['name'] ?? row['programName'] ?? row['title'] ?? '')
            .toString()
            .trim();
        if (code.isEmpty && name.isEmpty) return '--';
        if (name.isEmpty || name == code) return code.isEmpty ? name : code;
        return '${code.isEmpty ? name : code} - $name';
      }
      return '--';
    })();
    final selectedCollegeLabel = (() {
      final fallback = _detailCollegeCtrl.text.trim();
      final formatted = _collegeFilterLabelById(fallback);
      if (formatted != '--') return formatted;
      final resolved = _detailCollegeName.trim();
      if (resolved.isNotEmpty) return resolved;
      return '--';
    })();
    final readOnlyMode = !_detailEditing;
    final detailStudentNo = _detailStudentNoCtrl.text.trim();
    final detailEmployeeNo = _detailEmployeeNoCtrl.text.trim();

    Widget sectionCard(String title, List<Widget> children) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FBF7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
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
      final displayValue = value.trim().isEmpty ? '--' : value.trim();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(
                color: textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      );
    }

    Widget readOnlyGap() => const SizedBox(height: 8);

    Widget editableGap() => const SizedBox(height: 10);

    Widget footerAction({
      required String label,
      required Color fill,
      required Color textColor,
      required Color borderColor,
      required VoidCallback? onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    void startDetailEditing() {
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
      _scheduleDetailEmailAvailabilityCheck(_detailEmailCtrl.text);
      _scheduleDetailStudentNoAvailabilityCheck(_detailStudentNoCtrl.text);
      _scheduleDetailEmployeeNoAvailabilityCheck(_detailEmployeeNoCtrl.text);
    }

    return Container(
      color: Colors.white,
      child: Column(
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
                    readOnlyMode
                        ? (isStudent
                              ? 'Student Information'
                              : 'User Information')
                        : 'Profile Photo',
                    [
                      Row(
                        children: [
                          _buildDetailIdentityAvatar(data, detailName),
                          const SizedBox(width: 12),
                          Expanded(
                            child: readOnlyMode
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        detailName,
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
                                    color: primaryColor.withValues(alpha: 0.4),
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
                  sectionCard('Basic Information', [
                    if (readOnlyMode) ...[
                      readOnlyField('First Name', _detailFirstNameCtrl.text),
                      readOnlyGap(),
                      readOnlyField('Middle Name', _detailMiddleNameCtrl.text),
                      readOnlyGap(),
                      readOnlyField('Last Name', _detailLastNameCtrl.text),
                      readOnlyGap(),
                      readOnlyField('Email', _detailEmailCtrl.text),
                    ] else ...[
                      editableField(
                        _detailFirstNameCtrl,
                        'First Name',
                        icon: Icons.person_outline_rounded,
                        enabled: true,
                        required: true,
                        errorText: _detailFirstNameCtrl.text.trim().isEmpty
                            ? 'First Name is required.'
                            : null,
                      ),
                      editableGap(),
                      editableField(
                        _detailMiddleNameCtrl,
                        'Middle Name',
                        icon: Icons.badge_outlined,
                        enabled: true,
                      ),
                      editableGap(),
                      editableField(
                        _detailLastNameCtrl,
                        'Last Name',
                        icon: Icons.person_outline_rounded,
                        enabled: true,
                        required: true,
                        errorText: _detailLastNameCtrl.text.trim().isEmpty
                            ? 'Last Name is required.'
                            : null,
                      ),
                      editableGap(),
                      editableField(
                        _detailEmailCtrl,
                        'Email',
                        icon: Icons.email_outlined,
                        enabled: false,
                      ),
                    ],
                    if (!hideRoleInStudentViews &&
                        !(isStudent && isDeptScopedReviewer)) ...[
                      readOnlyMode ? readOnlyGap() : editableGap(),
                      readOnlyField(
                        'Role',
                        _formatRole(_detailRole),
                        icon: Icons.admin_panel_settings_outlined,
                      ),
                    ],
                  ]),
                  sectionCard(isStudent ? 'Student Profile' : 'Staff Profile', [
                    if (isStudent) ...[
                      if (readOnlyMode)
                        readOnlyField(
                          'Student Number',
                          _detailStudentNoCtrl.text,
                        )
                      else
                        editableField(
                          _detailStudentNoCtrl,
                          'Student Number',
                          icon: Icons.badge_outlined,
                          enabled: true,
                          required: false,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [
                            _HyphenatedDigitsFormatter(
                              firstGroup: 3,
                              secondGroup: 4,
                            ),
                          ],
                          onChanged: _scheduleDetailStudentNoAvailabilityCheck,
                          helperText: _detailStudentNoHelperText(),
                          errorText: _detailStudentNoErrorText(),
                        ),
                      if (!isDeptScopedReviewer) ...[
                        readOnlyMode ? readOnlyGap() : editableGap(),
                        readOnlyField(
                          'College',
                          selectedCollegeLabel,
                          icon: Icons.account_balance_outlined,
                          required: false,
                        ),
                      ],
                      readOnlyMode ? readOnlyGap() : editableGap(),
                      if (readOnlyMode)
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
                            if (selectedProgram != null && !hasSelectedProgram)
                              DropdownMenuItem<String>(
                                value: selectedProgram,
                                child: Text(
                                  '--',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ..._detailProgramOptions.map((doc) {
                              return DropdownMenuItem<String>(
                                value: doc.id,
                                child: Text(
                                  _programDropdownLabel(doc),
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
                                    _detailProgramCtrl.text = (v ?? '').trim();
                                  });
                                }
                              : null,
                        ),
                    ] else ...[
                      if (readOnlyMode)
                        readOnlyField('Employee ID', _detailEmployeeNoCtrl.text)
                      else
                        editableField(
                          _detailEmployeeNoCtrl,
                          'Employee ID',
                          icon: Icons.badge_outlined,
                          enabled: true,
                          required: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [
                            _HyphenatedDigitsFormatter(
                              firstGroup: 4,
                              secondGroup: 3,
                            ),
                          ],
                          onChanged: _scheduleDetailEmployeeNoAvailabilityCheck,
                          helperText: _detailEmployeeNoHelperText(),
                          errorText: _detailEmployeeNoErrorText(),
                        ),
                      if (_roleNeedsDepartmentFor(_detailRole)) ...[
                        readOnlyMode ? readOnlyGap() : editableGap(),
                        if (readOnlyMode)
                          readOnlyField(
                            'College',
                            _collegeFilterLabelById(_detailDepartmentCtrl.text),
                          )
                        else
                          editableField(
                            _detailDepartmentCtrl,
                            'College (Code)',
                            icon: Icons.business_outlined,
                            enabled: true,
                            required: true,
                            errorText: _detailDepartmentCtrl.text.trim().isEmpty
                                ? 'College is required.'
                                : null,
                          ),
                      ],
                    ],
                  ]),
                  sectionCard('Access', [
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
                          () => _detailAccountStatus = _normalizeAccountStatus(
                            v ?? 'active',
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 72),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
                              child: footerAction(
                                label: 'Approve',
                                fill: const Color(0xFF81C784),
                                textColor: Colors.white,
                                borderColor: const Color(0xFF81C784),
                                onTap: () => _reviewPendingStudent(
                                  uid: selectedDoc.id,
                                  approve: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: footerAction(
                                label: 'Reject',
                                fill: const Color(0xFFE57373),
                                textColor: Colors.white,
                                borderColor: const Color(0xFFE57373),
                                onTap: () async {
                                  final reason =
                                      await _showRejectReasonDialog();
                                  if (!mounted || reason == null) return;
                                  await _reviewPendingStudent(
                                    uid: selectedDoc.id,
                                    approve: false,
                                    rejectReason: reason,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (canEditProfileNow) ...[
                        Row(
                          children: [
                            Expanded(
                              child: footerAction(
                                label: 'Edit Profile',
                                fill: primaryColor,
                                textColor: Colors.white,
                                borderColor: primaryColor,
                                onTap: startDetailEditing,
                              ),
                            ),
                            const SizedBox(width: 10),
                            PopupMenuButton<String>(
                              tooltip: 'More actions',
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.md,
                                ),
                              ),
                              color: Colors.white,
                              onSelected: (action) {
                                if (action != 'logs') return;
                                _showUserActivityLogsDialog(
                                  uid: selectedDoc.id,
                                  displayName: _displayName(data),
                                );
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem<String>(
                                  value: 'logs',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.history_rounded,
                                      color: primaryColor,
                                    ),
                                    title: Text('Activity Logs'),
                                  ),
                                ),
                              ],
                              child: Container(
                                height: 44,
                                width: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.md,
                                  ),
                                  border: Border.all(
                                    color: primaryColor.withValues(alpha: 0.30),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.more_vert_rounded,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        footerAction(
                          label: 'View Activity Logs',
                          fill: Colors.white,
                          textColor: primaryColor,
                          borderColor: primaryColor.withValues(alpha: 0.30),
                          onTap: () => _showUserActivityLogsDialog(
                            uid: selectedDoc.id,
                            displayName: _displayName(data),
                          ),
                        ),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: footerAction(
                          label: 'Discard Changes',
                          fill: Colors.white,
                          textColor: primaryColor,
                          borderColor: primaryColor.withValues(alpha: 0.30),
                          onTap: () =>
                              _loadDetailFromData(selectedDoc.id, data),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: footerAction(
                          label: 'Save Changes',
                          fill: _detailSaveLocked
                              ? Colors.grey.withValues(alpha: 0.25)
                              : primaryColor,
                          textColor: _detailSaveLocked
                              ? hintColor
                              : Colors.white,
                          borderColor: _detailSaveLocked
                              ? Colors.grey.withValues(alpha: 0.25)
                              : primaryColor,
                          onTap: _detailSaveLocked
                              ? null
                              : _saveSelectedUserDetails,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
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

  Widget _buildAccountSourceChip(String source, {bool compact = false}) {
    final normalized = source.trim().toLowerCase();
    final color = normalized == 'self_signup'
        ? Colors.orange
        : normalized == 'admin_import'
        ? Colors.blueGrey
        : primaryColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        _accountSourceLabel(normalized),
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
    final affiliation = _displayAffiliation(data);
    final accountSource = _readAccountSource(data);
    final showAccountSourceChip =
        listType == 'pending' &&
        _pendingStudentFilter == 'pending_email_verification';

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
                      if (hideRoleInStudentViews)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.school_outlined,
                              size: 14,
                              color: primaryColor.withValues(alpha: 0.55),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              affiliation,
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
                      if (showAccountSourceChip)
                        _buildAccountSourceChip(accountSource, compact: true),
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

class _UserFilterChipData {
  final String label;
  final VoidCallback onRemove;

  const _UserFilterChipData({required this.label, required this.onRemove});
}

class _ImportedStudentDraft {
  final int rowNumber;
  final String studentNo;
  final String displayName;
  final String firstName;
  final String middleName;
  final String lastName;
  final String suffix;
  final String collegeId;
  final String programId;
  final String programLabel;
  final String email;
  final String? existingUid;
  final bool hasChanges;
  final String changeSummary;

  const _ImportedStudentDraft({
    required this.rowNumber,
    required this.studentNo,
    required this.displayName,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.suffix,
    required this.collegeId,
    required this.programId,
    required this.programLabel,
    required this.email,
    required this.existingUid,
    required this.hasChanges,
    required this.changeSummary,
  });

  String get fullName {
    final display = displayName.trim();
    if (display.isNotEmpty) return display;
    return [
      firstName.trim(),
      middleName.trim(),
      lastName.trim(),
      suffix.trim(),
    ].where((p) => p.isNotEmpty).join(' ').trim();
  }
}

class _ParsedImportName {
  final String displayName;
  final String firstName;
  final String middleName;
  final String lastName;
  final String suffix;

  const _ParsedImportName({
    required this.displayName,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.suffix,
  });

  const _ParsedImportName.empty()
    : displayName = '',
      firstName = '',
      middleName = '',
      lastName = '',
      suffix = '';
}

class _StudentImportIssue {
  final int rowNumber;
  final String message;
  final String? studentNo;
  final String? fullName;
  final String? program;
  final String? email;

  const _StudentImportIssue({
    required this.rowNumber,
    required this.message,
    this.studentNo,
    this.fullName,
    this.program,
    this.email,
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
  int get createCount =>
      validRows.where((row) => row.existingUid == null).length;
  int get updateCount => validRows
      .where((row) => row.existingUid != null && row.hasChanges)
      .length;
  int get noChangeCount => validRows
      .where((row) => row.existingUid != null && !row.hasChanges)
      .length;
  int get actionableCount => createCount + updateCount;
}

class _StudentImportDialogResult {
  final List<_ImportedStudentDraft> rows;
  final int invalidCount;
  final int noChangeCount;
  final int totalRows;
  final String fileName;

  const _StudentImportDialogResult({
    required this.rows,
    required this.invalidCount,
    required this.noChangeCount,
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
  String _previewTab = 'all';
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
        allowedExtensions: const ['csv', 'xlsx'],
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

      final isXlsx = file.name.toLowerCase().endsWith('.xlsx');
      final csvText = isXlsx
          ? _rowsToCsvText(readXlsxRows(bytes))
          : utf8.decode(bytes, allowMalformed: true);
      final validated = await widget.onValidateCsv(csvText);
      if (!mounted) return;
      setState(() {
        _fileName = file.name.trim().isEmpty
            ? (isXlsx ? 'students.xlsx' : 'students.csv')
            : file.name.trim();
        _result = validated;
        _previewTab = 'all';
        _validating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _errorText = 'Unable to validate file: $e';
      });
    }
  }

  String _rowsToCsvText(List<List<String>> rows) {
    String escape(String value) {
      final needsQuotes =
          value.contains(',') || value.contains('"') || value.contains('\n');
      final escaped = value.replaceAll('"', '""');
      return needsQuotes ? '"$escaped"' : escaped;
    }

    return rows.map((row) => row.map(escape).join(',')).join('\n');
  }

  Future<void> _downloadTemplateXlsx() async {
    final bytes = buildStudentImportTemplateXlsx();
    try {
      if (kIsWeb) {
        final downloaded = await download_helper.downloadBytes(
          bytes: bytes,
          fileName: 'BUDiscipLink_student_accounts_import_template.xlsx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        if (!downloaded) {
          throw Exception('Browser download is not available.');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student import template downloaded.')),
        );
        return;
      }

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save student import template',
        fileName: 'BUDiscipLink_student_accounts_import_template.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (path == null) return;
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await File(path).writeAsBytes(bytes);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student import template downloaded.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Template download failed: $e')));
    }
  }

  List<_StudentImportPreviewRow> _previewRows(
    _StudentImportValidationResult result,
  ) {
    final rows = <_StudentImportPreviewRow>[
      ...result.validRows.map(
        (row) => _StudentImportPreviewRow(
          rowNumber: row.rowNumber,
          studentNo: row.studentNo,
          fullName: row.fullName,
          program: row.programLabel,
          email: row.email,
          status: row.existingUid == null
              ? 'New'
              : (row.hasChanges ? 'Update' : 'No Change'),
          issue: null,
          changeSummary: row.changeSummary,
        ),
      ),
      ...result.issues.map(
        (issue) => _StudentImportPreviewRow(
          rowNumber: issue.rowNumber,
          studentNo: issue.studentNo ?? '',
          fullName: issue.fullName ?? '',
          program: issue.program ?? '',
          email: issue.email ?? '',
          status: 'Invalid',
          issue: issue.message,
          changeSummary: issue.message,
        ),
      ),
    ];
    rows.sort((a, b) => a.rowNumber.compareTo(b.rowNumber));
    return rows;
  }

  List<_StudentImportPreviewRow> _filteredPreviewRows(
    _StudentImportValidationResult result,
  ) {
    final rows = _previewRows(result);
    switch (_previewTab) {
      case 'ready':
        return rows.where((row) => row.issue == null).toList();
      case 'new':
        return rows.where((row) => row.status == 'New').toList();
      case 'updates':
        return rows.where((row) => row.status == 'Update').toList();
      case 'no_change':
        return rows.where((row) => row.status == 'No Change').toList();
      case 'invalid':
        return rows.where((row) => row.status == 'Invalid').toList();
      default:
        return rows;
    }
  }

  int get _previewTabIndex {
    switch (_previewTab) {
      case 'ready':
        return 1;
      case 'new':
        return 2;
      case 'updates':
        return 3;
      case 'no_change':
        return 4;
      case 'invalid':
        return 5;
      default:
        return 0;
    }
  }

  void _setPreviewTabByIndex(int index) {
    const tabs = ['all', 'ready', 'new', 'updates', 'no_change', 'invalid'];
    setState(() => _previewTab = tabs[index]);
  }

  Widget _statusBadge(String status) {
    final color = status == 'Invalid'
        ? Colors.red
        : status == 'Update'
        ? Colors.blueGrey
        : status == 'No Change'
        ? _hint
        : _primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11.5,
        ),
      ),
    );
  }

  Widget _previewRowCard(_StudentImportPreviewRow row, bool compact) {
    final invalid = row.issue != null;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: invalid
              ? Colors.red.withValues(alpha: 0.22)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.fullName.isEmpty ? 'Unnamed student' : row.fullName,
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    _statusBadge(row.status),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Row ${row.rowNumber} - ${row.studentNo.isEmpty ? 'No student number' : row.studentNo}',
                  style: const TextStyle(
                    color: _hint,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    row.program,
                    row.email,
                  ].where((value) => value.trim().isNotEmpty).join(' - '),
                  style: const TextStyle(
                    color: _hint,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                if (invalid) ...[
                  const SizedBox(height: 8),
                  Text(
                    row.issue!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ] else if (row.changeSummary.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    row.changeSummary,
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    '${row.rowNumber}',
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    row.studentNo,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    row.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    row.program,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _hint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    invalid ? row.issue! : row.email,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: invalid ? Colors.red.shade700 : _hint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: 86, child: _statusBadge(row.status)),
              ],
            ),
    );
  }

  Widget _previewDataTable(List<_StudentImportPreviewRow> rows) {
    if (rows.isEmpty) {
      return const Center(
        child: Text(
          'No rows in this tab.',
          style: TextStyle(color: _hint, fontWeight: FontWeight.w800),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 10),
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
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth < 1240
                      ? 1240
                      : constraints.maxWidth,
                ),
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF7FAF6),
                  ),
                  horizontalMargin: 12,
                  columnSpacing: 22,
                  dataRowMinHeight: 58,
                  dataRowMaxHeight: 66,
                  columns: const [
                    DataColumn(
                      label: Text(
                        'ROW',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _hint,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'STUDENT',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _hint,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'PROGRAM',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _hint,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'SCHOOL EMAIL',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _hint,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'CHANGES / ISSUE',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _hint,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'STATUS',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _hint,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                  rows: rows.map((row) {
                    final invalid = row.issue != null;
                    return DataRow(
                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (invalid) return Colors.red.withValues(alpha: 0.04);
                        return null;
                      }),
                      cells: [
                        DataCell(
                          Text(
                            '${row.rowNumber}',
                            style: const TextStyle(
                              color: _hint,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 240,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.fullName.isEmpty
                                      ? 'Unnamed student'
                                      : row.fullName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  row.studentNo.isEmpty
                                      ? 'No student number'
                                      : row.studentNo,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _hint,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 130,
                            child: Text(
                              row.program,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _hint,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 270,
                            child: Text(
                              row.email,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: invalid ? Colors.red.shade700 : _hint,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 360,
                            child: Text(
                              invalid ? row.issue! : row.changeSummary,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: invalid ? Colors.red.shade700 : _hint,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        DataCell(_statusBadge(row.status)),
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

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final validCount = result?.validRows.length ?? 0;
    final invalidCount = result?.invalidCount ?? 0;
    final createCount = result?.createCount ?? 0;
    final updateCount = result?.updateCount ?? 0;
    final noChangeCount = result?.noChangeCount ?? 0;
    final actionableCount = result?.actionableCount ?? 0;
    final previewRowCount = result == null
        ? 0
        : result.validRows.length + result.issues.length;
    final filteredRows = result == null
        ? const <_StudentImportPreviewRow>[]
        : _filteredPreviewRows(result);
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 760;
    final dialogWidth = compact
        ? (viewport.width * 0.96)
        : (viewport.width * 0.92).clamp(1120.0, 1360.0).toDouble();
    final dialogHeight = viewport.height * (compact ? 0.82 : 0.78);

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
        height: dialogHeight.clamp(480.0, 720.0).toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _validating ? null : _downloadTemplateXlsx,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primary,
                    side: BorderSide(color: _primary.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text(
                    'Download Template Again',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _validating ? null : _pickAndValidateCsv,
                  style: FilledButton.styleFrom(
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                  ),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text(
                    'Choose CSV / Excel',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compact ? dialogWidth - 24 : 420,
                  ),
                  child: Text(
                    _fileName.isEmpty
                        ? 'Download the template, fill it, then upload the file for validation.'
                        : _fileName,
                    style: TextStyle(
                      color: _fileName.isEmpty ? _hint : _text,
                      fontWeight: FontWeight.w800,
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
                  border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
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
            const SizedBox(height: 14),
            if (result == null)
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.table_view_rounded,
                          size: 44,
                          color: Color(0xFFCAD5C7),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'No file validated yet',
                          style: TextStyle(
                            color: _hint,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              DefaultTabController(
                key: ValueKey(_previewTab),
                length: 6,
                initialIndex: _previewTabIndex,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: _primary,
                  indicatorColor: _primary,
                  dividerColor: Colors.transparent,
                  onTap: _setPreviewTabByIndex,
                  tabs: [
                    Tab(text: 'All Rows ($previewRowCount)'),
                    Tab(text: 'Ready ($validCount)'),
                    Tab(text: 'New ($createCount)'),
                    Tab(text: 'Updates ($updateCount)'),
                    Tab(text: 'No Change ($noChangeCount)'),
                    Tab(text: 'Invalid ($invalidCount)'),
                  ],
                ),
              ),
              Expanded(
                child: compact
                    ? (filteredRows.isEmpty
                          ? const Center(
                              child: Text(
                                'No rows in this tab.',
                                style: TextStyle(
                                  color: _hint,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(top: 10),
                              itemCount: filteredRows.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) =>
                                  _previewRowCard(filteredRows[index], compact),
                            ))
                    : _previewDataTable(filteredRows),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: _validating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _validating || actionableCount == 0
              ? null
              : () {
                  Navigator.pop(
                    context,
                    _StudentImportDialogResult(
                      rows: result!.validRows
                          .where(
                            (row) => row.existingUid == null || row.hasChanges,
                          )
                          .toList(),
                      invalidCount: result.invalidCount,
                      noChangeCount: result.noChangeCount,
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
            actionableCount == 0 ? 'Import' : 'Import $actionableCount',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _StudentImportPreviewRow {
  final int rowNumber;
  final String studentNo;
  final String fullName;
  final String program;
  final String email;
  final String status;
  final String? issue;
  final String changeSummary;

  const _StudentImportPreviewRow({
    required this.rowNumber,
    required this.studentNo,
    required this.fullName,
    required this.program,
    required this.email,
    required this.status,
    required this.issue,
    required this.changeSummary,
  });
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
    final snap = await AppFirestore.instance
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
    final snap = await AppFirestore.instance
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
    final code = (data['collegeCode'] ?? '').toString().trim();
    final name = (data['name'] ?? data['collegeName'] ?? data['title'] ?? '')
        .toString()
        .trim();
    if (code.isEmpty && name.isEmpty) return '--';
    if (name.isEmpty || name == code) return code.isEmpty ? name : code;
    return '${code.isEmpty ? name : code} - $name';
  }

  String _programDropdownLabel(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    final code = (data['programCode'] ?? '').toString().trim();
    final name = (data['name'] ?? data['programName'] ?? data['title'] ?? '')
        .toString()
        .trim();
    if (code.isEmpty && name.isEmpty) return '--';
    if (name.isEmpty || name == code) return code.isEmpty ? name : code;
    return '${code.isEmpty ? name : code} - $name';
  }

  String _collegeLabelById(String collegeId) {
    final id = collegeId.trim();
    if (id.isEmpty) return '-';
    for (final doc in _colleges) {
      if (doc.id != id) continue;
      return _collegeDropdownLabel(doc);
    }
    return '--';
  }

  String _programLabelById(String programId) {
    final id = programId.trim();
    if (id.isEmpty) return '-';
    for (final doc in _programs) {
      if (doc.id != id) continue;
      return _programDropdownLabel(doc);
    }
    return '--';
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
    final q = await AppFirestore.instance
        .collection('users')
        .where('email', isEqualTo: value)
        .limit(1)
        .get();
    // NOTE: On this firebase_auth version, auth-side preflight email lookup
    // isn't available here. Auth uniqueness is enforced at create time
    // (email-already-in-use), while this pre-check guards Firestore duplicates.
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
    final q1 = await AppFirestore.instance
        .collection('users')
        .where('studentProfile.studentNo', isEqualTo: studentNo)
        .limit(1)
        .get();
    if (q1.docs.isNotEmpty) return false;

    final q2 = await AppFirestore.instance
        .collection('users')
        .where('studentNo', isEqualTo: studentNo)
        .limit(1)
        .get();
    return q2.docs.isEmpty;
  }

  Future<bool> _isEmployeeNoAvailable(String employeeNo) async {
    final q1 = await AppFirestore.instance
        .collection('users')
        .where('employeeProfile.employeeNo', isEqualTo: employeeNo)
        .limit(1)
        .get();
    if (q1.docs.isNotEmpty) return false;

    final q2 = await AppFirestore.instance
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
    if (!_isValidEmailFormat(email)) {
      return 'Email address format is incorrect.';
    }
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
    if (_lastStudentNoChecked == studentNo) {
      return 'Student Number is available.';
    }
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
    if (_lastEmployeeNoChecked == employeeNo) {
      return 'Employee ID is available.';
    }
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
                              _photoError = null;
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
                  'Profile photo is optional.',
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
                      label: 'Program',
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

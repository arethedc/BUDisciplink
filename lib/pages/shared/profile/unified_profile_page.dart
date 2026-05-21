import 'package:apps/services/notification_sound_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:apps/services/user_preferences_service.dart';
import 'package:apps/services/app_firestore.dart';
import 'package:apps/services/institution_label_service.dart';

class UnifiedProfilePage extends StatefulWidget {
  const UnifiedProfilePage({super.key});

  @override
  State<UnifiedProfilePage> createState() => _UnifiedProfilePageState();
}

class _UnifiedProfilePageState extends State<UnifiedProfilePage> {
  static const bg = Colors.white;
  static const primary = Color(0xFF1B5E20);
  static const textDark = Color(0xFF1F2A1F);
  static const hint = Color(0xFF6D7F62);

  final _formKey = GlobalKey<FormState>();

  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _studentNoCtrl = TextEditingController();
  final _collegeCtrl = TextEditingController();
  final _programCtrl = TextEditingController();
  final _employeeNoCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();

  final bool _editing = false;
  String _role = '';
  String _accountStatus = '';
  String _studentVerificationStatus = '';
  String _collegeDisplay = '';
  String _programDisplay = '';
  String _studentLookupKey = '';
  int _studentLookupSeq = 0;
  Map<String, dynamic>? _latestData;
  bool _notificationSoundEnabled = false;
  bool _systemPrefsLoading = true;

  bool get _isStudent => _role == 'student';
  bool get _roleNeedsDepartment =>
      _role != 'student' &&
      _role != 'osa_admin' &&
      _role != 'counseling_admin' &&
      _role != 'super_admin';

  @override
  void initState() {
    super.initState();
    _loadSystemPreferences();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _studentNoCtrl.dispose();
    _collegeCtrl.dispose();
    _programCtrl.dispose();
    _employeeNoCtrl.dispose();
    _departmentCtrl.dispose();
    super.dispose();
  }

  void _loadFromDoc(Map<String, dynamic> data) {
    final studentProfile =
        (data['studentProfile'] as Map<String, dynamic>?) ?? {};
    final employeeProfile =
        (data['employeeProfile'] as Map<String, dynamic>?) ?? {};

    _latestData = data;
    _role = (data['role'] ?? '').toString().trim().toLowerCase();

    final legacy = (data['status'] ?? '').toString().trim().toLowerCase();
    final accountField = (data['accountStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    _accountStatus = accountField.isEmpty
        ? (legacy == 'inactive' ? 'inactive' : 'active')
        : accountField;

    if (_isStudent) {
      final verificationField = (data['studentVerificationStatus'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      _studentVerificationStatus = verificationField.isEmpty
          ? (legacy == 'pending_email_verification' ||
                    legacy == 'pending_profile' ||
                    legacy == 'pending_approval' ||
                    legacy == 'pending_verification' ||
                    legacy == 'verified'
                ? (legacy == 'pending_verification'
                      ? 'pending_approval'
                      : legacy)
                : (legacy == 'active' ? 'verified' : 'pending_profile'))
          : (verificationField == 'pending_verification'
                ? 'pending_approval'
                : verificationField);
    } else {
      _studentVerificationStatus = '';
    }

    _firstNameCtrl.text = (data['firstName'] ?? '').toString();
    _middleNameCtrl.text = (data['middleName'] ?? '').toString();
    _lastNameCtrl.text = (data['lastName'] ?? '').toString();
    _emailCtrl.text =
        (data['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '')
            .toString();

    _studentNoCtrl.text =
        (studentProfile['studentNo'] ?? data['studentNo'] ?? '').toString();
    _collegeCtrl.text = (studentProfile['collegeId'] ?? '').toString();
    _programCtrl.text = (studentProfile['programId'] ?? '').toString();
    _employeeNoCtrl.text =
        (employeeProfile['employeeNo'] ?? data['employeeNo'] ?? '').toString();
    _departmentCtrl.text = (employeeProfile['department'] ?? '').toString();

    final lookupKey = '${_collegeCtrl.text.trim()}|${_programCtrl.text.trim()}';
    if (_isStudent && lookupKey != _studentLookupKey) {
      _studentLookupKey = lookupKey;
      _loadStudentProgramLabels(
        collegeId: _collegeCtrl.text.trim(),
        programId: _programCtrl.text.trim(),
      );
    } else if (!_isStudent) {
      _studentLookupKey = '';
      final employeeCollegeKey = _departmentCtrl.text.trim();
      if (employeeCollegeKey.isNotEmpty) {
        _collegeDisplay = employeeCollegeKey;
        InstitutionLabelService.resolveCollegeLabel(employeeCollegeKey)
            .then((label) {
              if (!mounted) return;
              if (_departmentCtrl.text.trim() != employeeCollegeKey) return;
              setState(() => _collegeDisplay = label.trim());
            })
            .catchError((_) {
              if (!mounted) return;
              if (_departmentCtrl.text.trim() != employeeCollegeKey) return;
              setState(() => _collegeDisplay = '--');
            });
      } else {
        _collegeDisplay = '';
      }
      _programDisplay = '';
    }
  }

  Future<void> _loadStudentProgramLabels({
    required String collegeId,
    required String programId,
  }) async {
    final seq = ++_studentLookupSeq;
    try {
      final collegeLabel = collegeId.trim().isEmpty
          ? '--'
          : await InstitutionLabelService.resolveCollegeLabel(
              collegeId.trim(),
            ).timeout(const Duration(seconds: 6));
      final programLabel = programId.trim().isEmpty
          ? '--'
          : await InstitutionLabelService.resolveProgramLabel(
              programId.trim(),
            ).timeout(const Duration(seconds: 6));

      if (!mounted || seq != _studentLookupSeq) return;
      setState(() {
        _collegeDisplay = collegeLabel;
        _programDisplay = programLabel;
      });
      return;
    } catch (_) {
      // Keep profile readable with stored IDs if lookup is unavailable.
    }

    if (!mounted || seq != _studentLookupSeq) return;
    setState(() {
      _collegeDisplay = '--';
      _programDisplay = '--';
    });
  }

  Future<void> _loadSystemPreferences() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _notificationSoundEnabled = false;
        _systemPrefsLoading = false;
      });
      return;
    }
    final enabled = await UserPreferencesService.getNotificationSoundEnabled(
      uid,
    );
    if (!mounted) return;
    setState(() {
      _notificationSoundEnabled = enabled;
      _systemPrefsLoading = false;
    });
  }

  Future<void> _setNotificationSoundEnabled(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) return;
    setState(() => _notificationSoundEnabled = enabled);
    await UserPreferencesService.setNotificationSoundEnabled(uid, enabled);
  }

  Future<void> _testNotificationSound() async {
    final ok = await NotificationSoundService.instance.play();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not play notification sound on this device.'),
        ),
      );
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'osa_admin':
        return 'OSA Admin';
      case 'counseling_admin':
        return 'Counseling Admin';
      case 'super_admin':
        return 'Super Admin';
      case 'department_admin':
        return 'Department Admin';
      case 'professor':
        return 'Professor';
      case 'guard':
        return 'Guard';
      case 'student':
        return 'Student';
      default:
        return role.isEmpty ? '--' : role;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'verified':
      case 'active':
        return const Color(0xFF2E7D32);
      case 'pending_email_verification':
      case 'pending_approval':
      case 'pending_verification':
      case 'pending_profile':
        return const Color(0xFFEF6C00);
      case 'inactive':
        return Colors.red.shade700;
      default:
        return hint;
    }
  }

  String _statusLabel(String raw) {
    if (raw.isEmpty) return '--';
    return raw.replaceAll('_', ' ').toUpperCase();
  }

  String _profilePhotoUrl(Map<String, dynamic> data) {
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
    if (_isHttpPhotoUrl(value)) {
      if (value.contains('firebasestorage.googleapis.com') ||
          value.contains('firebasestorage.app')) {
        try {
          return await FirebaseStorage.instance
              .refFromURL(value)
              .getDownloadURL();
        } catch (_) {
          return value;
        }
      }
      return value;
    }
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

  Widget _buildProfilePhotoAvatar(String sourceUrl) {
    final source = sourceUrl.trim();
    const fallback = Icon(Icons.person_rounded, color: hint, size: 30);
    final fallbackAvatar = Container(
      width: 60,
      height: 60,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F5F2),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: fallback,
    );

    Widget photoAvatar(String url) {
      return ClipOval(
        child: Image.network(
          url,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          errorBuilder: (_, __, ___) => fallbackAvatar,
        ),
      );
    }

    if (source.isEmpty) {
      return fallbackAvatar;
    }

    if (_isHttpPhotoUrl(source)) {
      return FutureBuilder<String>(
        future: _resolvePhotoUrl(source),
        builder: (context, snapshot) {
          final resolved = (snapshot.data ?? source).trim();
          return resolved.isEmpty ? fallbackAvatar : photoAvatar(resolved);
        },
      );
    }

    return FutureBuilder<String>(
      future: _resolvePhotoUrl(source),
      builder: (context, snapshot) {
        final resolved = (snapshot.data ?? '').trim();
        return resolved.isEmpty ? fallbackAvatar : photoAvatar(resolved);
      },
    );
  }

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
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

  Widget _buildCombinedUserLogsList({required String uid}) {
    final profileLogsStream = AppFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('profile_logs')
        .orderBy('createdAtEpochMs', descending: true)
        .snapshots();
    final authLogsStream = AppFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('auth_logs')
        .orderBy('createdAtEpochMs', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: profileLogsStream,
      builder: (context, profileSnap) {
        if (profileSnap.hasError) {
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
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: authLogsStream,
          builder: (context, authSnap) {
            if (authSnap.hasError) {
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

            final loading =
                profileSnap.connectionState == ConnectionState.waiting &&
                authSnap.connectionState == ConnectionState.waiting &&
                !profileSnap.hasData &&
                !authSnap.hasData;
            if (loading) {
              return const Center(
                child: CircularProgressIndicator(color: primary),
              );
            }

            final entries = <Map<String, dynamic>>[];
            for (final doc in profileSnap.data?.docs ?? const []) {
              entries.add({
                'data': doc.data(),
                'defaultTitle': 'Profile Update',
              });
            }
            for (final doc in authSnap.data?.docs ?? const []) {
              entries.add({
                'data': doc.data(),
                'defaultTitle': 'Session Activity',
              });
            }

            DateTime entryDate(Map<String, dynamic> entry) {
              final data =
                  (entry['data'] as Map<String, dynamic>?) ??
                  <String, dynamic>{};
              return _asDate(data['createdAt']) ??
                  DateTime.fromMillisecondsSinceEpoch(
                    (data['createdAtEpochMs'] as num?)?.toInt() ?? 0,
                  );
            }

            entries.sort((a, b) => entryDate(b).compareTo(entryDate(a)));

            if (entries.isEmpty) {
              return const Center(
                child: Text(
                  'No activity logs yet.',
                  style: TextStyle(color: hint, fontWeight: FontWeight.w700),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              itemCount: entries.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final entry = entries[index];
                final data =
                    (entry['data'] as Map<String, dynamic>?) ??
                    <String, dynamic>{};
                final defaultTitle =
                    (entry['defaultTitle'] as String?) ?? 'Activity';

                final action = (data['action'] ?? data['event'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                final title = (data['title'] ?? '').toString().trim();
                final details = (data['details'] ?? data['description'] ?? '')
                    .toString()
                    .trim();
                final actorName =
                    (data['actorName'] ?? data['actor'] ?? 'System')
                        .toString()
                        .trim();
                final actorRole = (data['actorRole'] ?? '').toString().trim();
                final createdAt = entryDate(entry);

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

                final roleLabel = actorRole.isEmpty
                    ? ''
                    : actorRole.replaceAll('_', ' ').trim();

                return Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                              borderRadius: BorderRadius.circular(999),
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
                        '${_formatLogDateTime(createdAt)} - $actorName${roleLabel.isEmpty ? '' : ' ($roleLabel)'}',
                        style: const TextStyle(
                          color: hint,
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
      },
    );
  }

  Future<void> _showActivityLogsDialog({
    required String uid,
    required String displayName,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
                        color: primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Activity Logs - $displayName',
                          style: const TextStyle(
                            color: primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: hint),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _buildCombinedUserLogsList(uid: uid)),
              ],
            ),
          ),
        );
      },
    );
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    bool enabled = true,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: hint, fontWeight: FontWeight.w700),
      prefixIcon: Icon(
        icon,
        color: enabled
            ? primary.withValues(alpha: 0.85)
            : primary.withValues(alpha: 0.65),
      ),
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

  Widget _plainDetailField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final displayValue = value.trim().isEmpty ? '--' : value.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: hint,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                displayValue,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profileField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    bool editable = true,
    String? readOnlyValue,
    String? Function(String?)? validator,
  }) {
    if (!_editing || !editable) {
      return _plainDetailField(
        label: label,
        icon: icon,
        value: readOnlyValue ?? controller.text,
      );
    }
    return TextFormField(
      controller: controller,
      readOnly: false,
      decoration: _decor(label: label, icon: icon, enabled: true),
      validator: validator,
      style: const TextStyle(fontWeight: FontWeight.w700, color: textDark),
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: primary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children:
                children.expand((w) => [w, const SizedBox(height: 12)]).toList()
                  ..removeLast(),
          );
        }
        return Row(
          children:
              children
                  .expand(
                    (w) => [Expanded(child: w), const SizedBox(width: 12)],
                  )
                  .toList()
                ..removeLast(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      backgroundColor: bg,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: AppFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: primary),
            );
          }

          final data = snap.data!.data() ?? <String, dynamic>{};
          if (!_editing || _latestData == null) {
            _loadFromDoc(data);
          }

          final displayName =
              (data['displayName'] ??
                      '${_firstNameCtrl.text} ${_lastNameCtrl.text}')
                  .toString()
                  .trim();
          final email = _emailCtrl.text.trim();
          final profilePhotoUrl = _profilePhotoUrl(data);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 720;
                            final logsButton = OutlinedButton.icon(
                              onPressed: () => _showActivityLogsDialog(
                                uid: uid,
                                displayName: displayName.isEmpty
                                    ? email
                                    : displayName,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primary,
                                side: BorderSide(
                                  color: primary.withValues(alpha: 0.30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.history_rounded, size: 17),
                              label: const Text(
                                'View Activity Logs',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _buildProfilePhotoAvatar(profilePhotoUrl),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            displayName.isEmpty
                                                ? '--'
                                                : displayName,
                                            style: const TextStyle(
                                              color: textDark,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            email.isEmpty ? '--' : email,
                                            style: const TextStyle(
                                              color: hint,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _roleLabel(_role),
                                            style: const TextStyle(
                                              color: hint,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!compact) ...[
                                      const SizedBox(width: 12),
                                      logsButton,
                                    ],
                                  ],
                                ),
                                if (compact) const SizedBox(height: 10),
                                if (compact)
                                  SizedBox(
                                    width: double.infinity,
                                    child: logsButton,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        title: 'Basic Information',
                        children: [
                          _row([
                            _profileField(
                              label: 'First Name',
                              icon: Icons.person_outline,
                              controller: _firstNameCtrl,
                              validator: (v) =>
                                  (v ?? '').trim().isEmpty ? 'Required' : null,
                            ),
                            _profileField(
                              label: 'Last Name',
                              icon: Icons.person_outline,
                              controller: _lastNameCtrl,
                              validator: (v) =>
                                  (v ?? '').trim().isEmpty ? 'Required' : null,
                            ),
                          ]),
                          const SizedBox(height: 12),
                          _row([
                            _profileField(
                              label: 'Middle Name',
                              icon: Icons.person_outline,
                              controller: _middleNameCtrl,
                            ),
                            _profileField(
                              label: 'Email Address',
                              icon: Icons.email_outlined,
                              controller: _emailCtrl,
                              editable: false,
                            ),
                          ]),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _section(
                        title: _isStudent
                            ? 'Student Details'
                            : 'Employee Details',
                        children: _isStudent
                            ? [
                                _row([
                                  _profileField(
                                    label: 'Student Number',
                                    icon: Icons.badge_outlined,
                                    controller: _studentNoCtrl,
                                    editable: false,
                                  ),
                                ]),
                                const SizedBox(height: 12),
                                _row([
                                  _profileField(
                                    label: 'College',
                                    icon: Icons.account_balance_outlined,
                                    controller: _collegeCtrl,
                                    readOnlyValue:
                                        _collegeDisplay.trim().isEmpty
                                        ? 'Loading...'
                                        : _collegeDisplay,
                                  ),
                                  _profileField(
                                    label: 'Program/Course',
                                    icon: Icons.school_outlined,
                                    controller: _programCtrl,
                                    readOnlyValue:
                                        _programDisplay.trim().isEmpty
                                        ? 'Loading...'
                                        : _programDisplay,
                                  ),
                                ]),
                              ]
                            : [
                                _row([
                                  _profileField(
                                    label: 'Employee ID',
                                    icon: Icons.badge_outlined,
                                    controller: _employeeNoCtrl,
                                    editable: false,
                                  ),
                                  if (_roleNeedsDepartment)
                                    _profileField(
                                      label: 'College',
                                      icon: Icons.business_outlined,
                                      controller: _departmentCtrl,
                                      readOnlyValue:
                                          _collegeDisplay.trim().isEmpty
                                          ? 'Loading...'
                                          : _collegeDisplay,
                                    )
                                  else
                                    _plainDetailField(
                                      label: 'Account Type',
                                      icon: Icons.admin_panel_settings_outlined,
                                      value: _roleLabel(_role),
                                    ),
                                ]),
                              ],
                      ),
                      const SizedBox(height: 16),
                      if (_isStudent) ...[
                        _section(
                          title: 'System Preferences',
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                10,
                              ),
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
                                  Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: primary.withValues(
                                            alpha: 0.10,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.volume_up_rounded,
                                          color: primary,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Notification Sound',
                                              style: TextStyle(
                                                color: textDark,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Play a short alert sound when a new notification arrives.',
                                              style: TextStyle(
                                                color: hint,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      if (_systemPrefsLoading)
                                        const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: primary,
                                          ),
                                        )
                                      else
                                        Switch.adaptive(
                                          value: _notificationSoundEnabled,
                                          activeThumbColor: primary,
                                          activeTrackColor: primary.withValues(
                                            alpha: 0.28,
                                          ),
                                          onChanged:
                                              _setNotificationSoundEnabled,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      onPressed: _systemPrefsLoading
                                          ? null
                                          : _testNotificationSound,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primary,
                                        side: BorderSide(
                                          color: primary.withValues(
                                            alpha: 0.28,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Test Sound',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              color: hint,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Profile editing is locked. Updates are only allowed during the pending approval review phase.',
                                style: TextStyle(
                                  color: hint,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

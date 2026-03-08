import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class UnifiedProfilePage extends StatefulWidget {
  const UnifiedProfilePage({super.key});

  @override
  State<UnifiedProfilePage> createState() => _UnifiedProfilePageState();
}

class _UnifiedProfilePageState extends State<UnifiedProfilePage> {
  static const bg = Color(0xFFF6FAF6);
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
  final _yearLevelCtrl = TextEditingController();
  final _employeeNoCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();

  bool _editing = false;
  bool _saving = false;
  String _role = '';
  String _accountStatus = '';
  String _studentVerificationStatus = '';
  Map<String, dynamic>? _latestData;

  bool get _isStudent => _role == 'student';
  bool get _roleNeedsDepartment =>
      _role != 'student' &&
      _role != 'osa_admin' &&
      _role != 'counseling_admin' &&
      _role != 'super_admin';

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _studentNoCtrl.dispose();
    _collegeCtrl.dispose();
    _programCtrl.dispose();
    _yearLevelCtrl.dispose();
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
    _yearLevelCtrl.text = (studentProfile['yearLevel'] ?? '').toString();

    _employeeNoCtrl.text =
        (employeeProfile['employeeNo'] ?? data['employeeNo'] ?? '').toString();
    _departmentCtrl.text = (employeeProfile['department'] ?? '').toString();
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

  InputDecoration _decor({
    required String label,
    required IconData icon,
    bool enabled = true,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: hint, fontWeight: FontWeight.w700),
      prefixIcon: Icon(icon, color: primary.withValues(alpha: 0.85)),
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
        borderSide: const BorderSide(color: primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: hint,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
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

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      final firstName = _firstNameCtrl.text.trim();
      final middleName = _middleNameCtrl.text.trim();
      final lastName = _lastNameCtrl.text.trim();

      final updates = <String, dynamic>{
        'firstName': firstName,
        'middleName': middleName.isEmpty ? null : middleName,
        'lastName': lastName,
        'displayName': '$firstName $lastName'.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isStudent) {
        updates['studentProfile'] = {
          'studentNo': _studentNoCtrl.text.trim().isEmpty
              ? null
              : _studentNoCtrl.text.trim(),
          'collegeId': _collegeCtrl.text.trim().isEmpty
              ? null
              : _collegeCtrl.text.trim(),
          'programId': _programCtrl.text.trim().isEmpty
              ? null
              : _programCtrl.text.trim(),
          'yearLevel': int.tryParse(_yearLevelCtrl.text.trim()),
        };
      } else {
        updates['employeeProfile'] = {
          'employeeNo': _employeeNoCtrl.text.trim().isEmpty
              ? null
              : _employeeNoCtrl.text.trim(),
          if (_roleNeedsDepartment)
            'department': _departmentCtrl.text.trim().isEmpty
                ? null
                : _departmentCtrl.text.trim(),
        };
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(updates, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discardChanges() {
    if (_latestData != null) _loadFromDoc(_latestData!);
    setState(() => _editing = false);
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
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
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
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: primary.withValues(alpha: 0.12),
                              child: const Icon(
                                Icons.person_rounded,
                                color: primary,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName.isEmpty ? '--' : displayName,
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
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Chip(
                                        label: Text(_roleLabel(_role)),
                                        backgroundColor: primary.withValues(
                                          alpha: 0.10,
                                        ),
                                        labelStyle: const TextStyle(
                                          color: primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          'ACCOUNT: ${_statusLabel(_accountStatus)}',
                                        ),
                                        backgroundColor: _statusColor(
                                          _accountStatus,
                                        ).withValues(alpha: 0.12),
                                        labelStyle: TextStyle(
                                          color: _statusColor(_accountStatus),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (_isStudent)
                                        Chip(
                                          label: Text(
                                            'VERIFICATION: ${_statusLabel(_studentVerificationStatus)}',
                                          ),
                                          backgroundColor: _statusColor(
                                            _studentVerificationStatus,
                                          ).withValues(alpha: 0.12),
                                          labelStyle: TextStyle(
                                            color: _statusColor(
                                              _studentVerificationStatus,
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        title: 'Basic Information',
                        children: [
                          _row([
                            TextFormField(
                              controller: _firstNameCtrl,
                              readOnly: !_editing,
                              decoration: _decor(
                                label: 'First Name',
                                icon: Icons.person_outline,
                                enabled: _editing,
                              ),
                              validator: (v) =>
                                  (v ?? '').trim().isEmpty ? 'Required' : null,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: textDark,
                              ),
                            ),
                            TextFormField(
                              controller: _lastNameCtrl,
                              readOnly: !_editing,
                              decoration: _decor(
                                label: 'Last Name',
                                icon: Icons.person_outline,
                                enabled: _editing,
                              ),
                              validator: (v) =>
                                  (v ?? '').trim().isEmpty ? 'Required' : null,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: textDark,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          _row([
                            TextFormField(
                              controller: _middleNameCtrl,
                              readOnly: !_editing,
                              decoration: _decor(
                                label: 'Middle Name',
                                icon: Icons.person_outline,
                                enabled: _editing,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: textDark,
                              ),
                            ),
                            TextFormField(
                              controller: _emailCtrl,
                              readOnly: true,
                              decoration: _decor(
                                label: 'Email Address',
                                icon: Icons.email_outlined,
                                enabled: false,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: textDark,
                              ),
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
                                  TextFormField(
                                    controller: _studentNoCtrl,
                                    readOnly: true,
                                    decoration: _decor(
                                      label: 'Student Number',
                                      icon: Icons.badge_outlined,
                                      enabled: false,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: textDark,
                                    ),
                                  ),
                                  TextFormField(
                                    controller: _yearLevelCtrl,
                                    readOnly: !_editing,
                                    keyboardType: TextInputType.number,
                                    decoration: _decor(
                                      label: 'Year Level',
                                      icon: Icons.layers_outlined,
                                      enabled: _editing,
                                    ),
                                    validator: (v) {
                                      final value = (v ?? '').trim();
                                      if (value.isEmpty) return null;
                                      return int.tryParse(value) == null
                                          ? 'Numbers only'
                                          : null;
                                    },
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: textDark,
                                    ),
                                  ),
                                ]),
                                const SizedBox(height: 12),
                                _row([
                                  TextFormField(
                                    controller: _collegeCtrl,
                                    readOnly: !_editing,
                                    decoration: _decor(
                                      label: 'College',
                                      icon: Icons.account_balance_outlined,
                                      enabled: _editing,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: textDark,
                                    ),
                                  ),
                                  TextFormField(
                                    controller: _programCtrl,
                                    readOnly: !_editing,
                                    decoration: _decor(
                                      label: 'Program/Course',
                                      icon: Icons.school_outlined,
                                      enabled: _editing,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: textDark,
                                    ),
                                  ),
                                ]),
                              ]
                            : [
                                _row([
                                  TextFormField(
                                    controller: _employeeNoCtrl,
                                    readOnly: true,
                                    decoration: _decor(
                                      label: 'Employee ID',
                                      icon: Icons.badge_outlined,
                                      enabled: false,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: textDark,
                                    ),
                                  ),
                                  if (_roleNeedsDepartment)
                                    TextFormField(
                                      controller: _departmentCtrl,
                                      readOnly: !_editing,
                                      decoration: _decor(
                                        label: 'Department',
                                        icon: Icons.business_outlined,
                                        enabled: _editing,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: textDark,
                                      ),
                                    )
                                  else
                                    TextFormField(
                                      initialValue: _roleLabel(_role),
                                      readOnly: true,
                                      decoration: _decor(
                                        label: 'Account Type',
                                        icon:
                                            Icons.admin_panel_settings_outlined,
                                        enabled: false,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: textDark,
                                      ),
                                    ),
                                ]),
                              ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.end,
                          children: [
                            if (!_editing)
                              FilledButton.icon(
                                onPressed: () =>
                                    setState(() => _editing = true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                ),
                                icon: const Icon(Icons.edit_rounded, size: 18),
                                label: const Text(
                                  'Edit Profile',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            if (_editing) ...[
                              OutlinedButton(
                                onPressed: _saving ? null : _discardChanges,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: hint,
                                  side: const BorderSide(color: hint),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text(
                                  'Discard Changes',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: _saving ? null : _saveProfile,
                                style: FilledButton.styleFrom(
                                  backgroundColor: primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                ),
                                icon: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded, size: 18),
                                label: Text(
                                  _saving ? 'Saving...' : 'Save Changes',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
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
            ),
          );
        },
      ),
    );
  }
}

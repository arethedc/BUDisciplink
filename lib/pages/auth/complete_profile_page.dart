import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../../services/role_router.dart';
import '../shared/widgets/logout_confirm_dialog.dart';

class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  // ✅ Controllers
  final _studentNoController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  // ✅ Selections
  String? selectedCollege;
  String? selectedProgram;
  int? selectedYear;

  // ✅ Loaded options
  List<QueryDocumentSnapshot> colleges = [];
  List<QueryDocumentSnapshot> programs = [];

  // ✅ UI state
  bool _saving = false;

  // ✅ Field-specific errors (inline)
  String? _firstNameError;
  String? _middleNameError;
  String? _lastNameError;
  String? _studentNoError;
  String? _collegeError;
  String? _programError;
  String? _yearError;

  // ===== DESIGN THEME =====
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  // For student number formatting
  bool _isFormattingStudentNo = false;

  @override
  void initState() {
    super.initState();
    _loadColleges();

    // ✅ Smart student number formatter:
    // - digits only
    // - auto dash after 3 digits
    // - total digits max 7 (3+4)
    // - handles paste: 1231234 -> 123-1234
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

  // ====== Student number helpers ======
  String _digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');

  String _formatDigitsToStudentNo(String digits) {
    // digits max 7
    final d = digits.length > 7 ? digits.substring(0, 7) : digits;

    if (d.length <= 3) return d; // no dash until after 3 digits
    return '${d.substring(0, 3)}-${d.substring(3)}';
  }

  void _formatStudentNo() {
    if (_isFormattingStudentNo) return;

    final raw = _studentNoController.text;
    final digits = _digitsOnly(raw);

    final formatted = _formatDigitsToStudentNo(digits);

    // If already formatted, do nothing
    if (raw == formatted) return;

    _isFormattingStudentNo = true;

    // Place cursor at end (simple and stable; avoids weird cursor jumps on paste)
    _studentNoController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );

    _isFormattingStudentNo = false;
  }

  bool _isStudentNoValid(String value) {
    // Must be exactly 123-1234
    final reg = RegExp(r'^\d{3}-\d{4}$');
    return reg.hasMatch(value);
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
  }

  bool _validateFields() {
    _clearErrors();

    final studentNo = _studentNoController.text.trim();
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    bool ok = true;

    if (firstName.isEmpty) {
      _firstNameError = 'First name is required';
      ok = false;
    }

    if (middleName.isEmpty) {
      _middleNameError = 'Middle name is required';
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

    setState(() {});
    return ok;
  }

  Future<void> _saveProfile() async {
    if (_saving) return;

    // ✅ Field-specific validation
    final valid = _validateFields();
    if (!valid) return;

    setState(() => _saving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Normalize names (safe and consistent)
      final firstName = _toTitleCase(_firstNameController.text);
      final middleName = _toTitleCase(_middleNameController.text);
      final lastName = _toTitleCase(_lastNameController.text);

      final displayName = '${_toUpper(lastName)}, $firstName $middleName';

      final studentNo = _studentNoController.text.trim();

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        // ✅ NEW: Organized Profiles
        'studentProfile': {
          'studentNo': studentNo,
          'collegeId': selectedCollege,
          'programId': selectedProgram,
          'yearLevel': selectedYear,
        },

        // ✅ required name fields
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,

        // ✅ generated displayName
        'displayName': displayName,

        // ✅ On successful submit: update status
        'accountStatus': 'active',
        'studentVerificationStatus': 'pending_approval',
        'status': 'pending_approval',

        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      // ✅ Required success message
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Text("Profile submitted"),
            content: const Text(
              "Your profile has been submitted. Please wait for your department admin’s approval.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("OK"),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      // ✅ Navigate to pending approval flow via RoleRouter (keeps your existing system logic)
      await RoleRouter.route(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to save: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decor({
    required String label,
    required IconData icon,
    String? helperText,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      errorText: errorText,
      helperStyle: TextStyle(
        color: hint.withOpacity(0.9),
        fontWeight: FontWeight.w700,
      ),
      labelStyle: const TextStyle(color: hint, fontWeight: FontWeight.w700),
      prefixIcon: Icon(icon, color: primary.withOpacity(0.85)),
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

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final contentMaxWidth = w >= 900 ? 420.0 : double.infinity;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        foregroundColor: primary,
        automaticallyImplyLeading: false,
        title: const Text(
          'Complete Profile',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final confirmed = await showLogoutConfirmDialog(context);
              if (!context.mounted || !confirmed) return;
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/welcome',
                (r) => false,
              );
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Logout'),
            style: TextButton.styleFrom(
              foregroundColor: primary,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    "COMPLETE YOUR PROFILE",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      fontSize: 18,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "Please fill in the required details to continue",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: hint,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ✅ First Name
                  TextField(
                    controller: _firstNameController,
                    onChanged: (_) {
                      if (_firstNameError != null)
                        setState(() => _firstNameError = null);
                    },
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _decor(
                      label: 'First Name',
                      icon: Icons.person_outline_rounded,
                      errorText: _firstNameError,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),

                  // ✅ Middle Name
                  TextField(
                    controller: _middleNameController,
                    onChanged: (_) {
                      if (_middleNameError != null)
                        setState(() => _middleNameError = null);
                    },
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _decor(
                      label: 'Middle Name',
                      icon: Icons.person_outline_rounded,
                      errorText: _middleNameError,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),

                  // ✅ Last Name
                  TextField(
                    controller: _lastNameController,
                    onChanged: (_) {
                      if (_lastNameError != null)
                        setState(() => _lastNameError = null);
                    },
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _decor(
                      label: 'Last Name',
                      icon: Icons.person_outline_rounded,
                      errorText: _lastNameError,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // ✅ Student Number
                  TextField(
                    controller: _studentNoController,
                    onChanged: (_) {
                      if (_studentNoError != null)
                        setState(() => _studentNoError = null);
                    },
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _decor(
                      label: 'Student Number',
                      icon: Icons.badge_outlined,
                      helperText: "Format: 123-1234",
                      errorText: _studentNoError,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      // extra safety: prevent non-digits from being typed (dash is inserted by formatter)
                      FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
                      LengthLimitingTextInputFormatter(8), // 123-1234 length
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ✅ College dropdown
                  DropdownButtonFormField<String>(
                    initialValue: selectedCollege,
                    isExpanded: true,
                    decoration: _decor(
                      label: 'College',
                      icon: Icons.account_balance_outlined,
                      errorText: _collegeError,
                    ),
                    hint: Text(
                      'Select College',
                      style: TextStyle(
                        color: hint.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    items: colleges.map<DropdownMenuItem<String>>((c) {
                      return DropdownMenuItem<String>(
                        value: c.id,
                        child: Text(
                          (c['name'] as String),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedCollege = value;
                        selectedProgram = null;
                        programs.clear();
                        _collegeError = null;
                        _programError = null; // will be re-validated on save
                      });
                      _loadPrograms(value);
                    },
                  ),
                  const SizedBox(height: 16),

                  // ✅ Program dropdown
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedCollege),
                    initialValue: selectedProgram,
                    isExpanded: true,
                    decoration: _decor(
                      label: 'Program',
                      icon: Icons.school_outlined,
                      errorText: _programError,
                    ),
                    hint: Text(
                      'Select Program',
                      style: TextStyle(
                        color: hint.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    items: programs.map<DropdownMenuItem<String>>((p) {
                      return DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(
                          (p['name'] as String),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedProgram = value;
                        _programError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // ✅ Year level dropdown
                  DropdownButtonFormField<int>(
                    initialValue: selectedYear,
                    isExpanded: true,
                    decoration: _decor(
                      label: 'Year Level',
                      icon: Icons.calendar_today_outlined,
                      errorText: _yearError,
                    ),
                    hint: Text(
                      'Select Year Level',
                      style: TextStyle(
                        color: hint.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    items: [1, 2, 3, 4].map((y) {
                      return DropdownMenuItem<int>(
                        value: y,
                        child: Text(
                          'Year $y',
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedYear = value;
                        _yearError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 22),

                  // ✅ Save button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
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
                    height: 1,
                    width: double.infinity,
                    color: primary.withValues(alpha: 0.25),
                  ),
                  const SizedBox(height: 10),

                  Container(
                    width: double.infinity,
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
                        Expanded(
                          child: Text(
                            "Make sure your details are correct before saving.",
                            style: TextStyle(
                              color: textDark.withValues(alpha: 0.85),
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
      ),
    );
  }
}

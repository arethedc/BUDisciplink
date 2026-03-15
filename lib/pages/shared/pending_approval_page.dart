import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'widgets/logout_confirm_dialog.dart';

class PendingApprovalPage extends StatefulWidget {
  const PendingApprovalPage({super.key});

  @override
  State<PendingApprovalPage> createState() => _PendingApprovalPageState();
}

class _PendingApprovalPageState extends State<PendingApprovalPage> {
  // ===== DESIGN THEME (match your app) =====
  static const bg = Color(0xFFF6FAF6);
  static const primary = Color(0xFF1B5E20);
  static const hint = Color(0xFF6D7F62);
  static const textDark = Color(0xFF1F2A1F);

  late final Future<_PendingProfileSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _loadSummary();
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showLogoutConfirmDialog(context);
    if (!context.mounted || !confirmed) return;
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (r) => false);
  }

  String _valueOrDash(String? value) {
    final v = (value ?? '').trim();
    return v.isEmpty ? '-' : v;
  }

  String _buildDisplayName({
    required String firstName,
    required String middleName,
    required String lastName,
  }) {
    final parts = <String>[];
    if (firstName.trim().isNotEmpty) parts.add(firstName.trim());
    if (middleName.trim().isNotEmpty) parts.add(middleName.trim());
    if (lastName.trim().isNotEmpty) parts.add(lastName.trim());
    return parts.join(' ').trim();
  }

  Future<String> _resolveNameFromCollection(
    String collection,
    String docId,
  ) async {
    if (docId.trim().isEmpty) return '-';
    try {
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(docId)
          .get();
      final data = doc.data();
      if (data == null) return '-';
      final rawName = data['name'];
      if (rawName is String && rawName.trim().isNotEmpty) {
        return rawName.trim();
      }
    } catch (_) {
      // Keep summary resilient if lookup fails.
    }
    return '-';
  }

  Future<_PendingProfileSummary> _loadSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const _PendingProfileSummary.empty();

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = userDoc.data() ?? <String, dynamic>{};

    final firstName = (data['firstName'] as String? ?? '').trim();
    final middleName = (data['middleName'] as String? ?? '').trim();
    final lastName = (data['lastName'] as String? ?? '').trim();

    final profileRaw = data['studentProfile'];
    final profile = profileRaw is Map
        ? Map<String, dynamic>.from(profileRaw)
        : <String, dynamic>{};

    final studentNo = (profile['studentNo'] ?? data['studentNo'] ?? '')
        .toString()
        .trim();
    final collegeId = (profile['collegeId'] ?? data['collegeId'] ?? '')
        .toString()
        .trim();
    final programId = (profile['programId'] ?? data['programId'] ?? '')
        .toString()
        .trim();
    final yearLevel = profile['yearLevel'] ?? data['yearLevel'];

    final collegeName = await _resolveNameFromCollection('colleges', collegeId);
    final programName = await _resolveNameFromCollection('programs', programId);

    return _PendingProfileSummary(
      studentName: _buildDisplayName(
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
      ),
      studentNumber: studentNo,
      collegeName: collegeName,
      programName: programName,
      yearLabel: yearLevel == null ? '-' : 'Year ${yearLevel.toString()}',
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 122,
            child: Text(
              label,
              style: TextStyle(
                color: hint.withValues(alpha: 0.95),
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
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

  Widget _buildSummaryCard() {
    return FutureBuilder<_PendingProfileSummary>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primary.withValues(alpha: 0.16)),
            ),
            child: const Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final summary = snapshot.data ?? const _PendingProfileSummary.empty();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primary.withValues(alpha: 0.16)),
          ),
          child: Column(
            children: [
              _summaryRow('Student Name', _valueOrDash(summary.studentName)),
              _summaryRow(
                'Student Number',
                _valueOrDash(summary.studentNumber),
              ),
              _summaryRow('College', _valueOrDash(summary.collegeName)),
              _summaryRow('Program', _valueOrDash(summary.programName)),
              _summaryRow('Year Level', _valueOrDash(summary.yearLabel)),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final contentMaxWidth = w >= 900 ? 560.0 : double.infinity;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Container(
              margin: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: primary.withValues(alpha: 0.15),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        color: primary,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'PENDING APPROVAL',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Your profile has been submitted. Please wait for your department admin's approval.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textDark.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Submitted Profile',
                        style: TextStyle(
                          color: primary.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSummaryCard(),
                    const SizedBox(height: 18),
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
                              "You can log out and come back later. Once approved, you'll be able to access your dashboard.",
                              style: TextStyle(
                                color: hint,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () => _logout(context),
                        icon: const Icon(Icons.logout_rounded, size: 20),
                        label: const Text(
                          'Log out',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: const BorderSide(color: primary, width: 2),
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
    );
  }
}

class _PendingProfileSummary {
  final String studentName;
  final String studentNumber;
  final String collegeName;
  final String programName;
  final String yearLabel;

  const _PendingProfileSummary({
    required this.studentName,
    required this.studentNumber,
    required this.collegeName,
    required this.programName,
    required this.yearLabel,
  });

  const _PendingProfileSummary.empty()
    : studentName = '-',
      studentNumber = '-',
      collegeName = '-',
      programName = '-',
      yearLabel = '-';
}

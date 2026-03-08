import 'package:apps/pages/osa_admin/osa_dashboard.dart';
import 'package:apps/pages/department_admin/department_admin_dashboard.dart';
import 'package:apps/pages/counseling_admin/counseling_dashboard.dart';
import 'package:apps/pages/guard/guard_dashboard.dart';
import 'package:apps/pages/professor/professor_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../pages/student/student_dashboard.dart';
import '../pages/auth/complete_profile_page.dart';
import '../pages/shared/pending_approval_page.dart';
import '../pages/super_admin/super_admin_dashboard.dart';

class RoleRouter {
  static Future<void> route(BuildContext context) async {
    // ✅ Prevent crashes if currentUser is null
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // If you have a welcome route, send them there safely
      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (r) => false);
      return;
    }

    // Reload auth user (keep existing email verification behavior)
    await user.reload();
    if (!context.mounted) return;
    final freshUser = FirebaseAuth.instance.currentUser;

    // ✅ Keep email verification check
    final uid = user.uid;

    // ✅ Handle missing Firestore user doc safely
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!context.mounted) return;
    if (!doc.exists) {
      // No doc means app logic didn't create it yet (or deleted); force safe exit
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (r) => false);
      return;
    }

    final data = doc.data() ?? {};

    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    final createdByAdmin = data['createdByAdmin'] == true;
    final accountStatus = (data['accountStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final legacyStatus = (data['status'] ?? '').toString().trim().toLowerCase();
    final effectiveAccountStatus = accountStatus.isEmpty
        ? (legacyStatus == 'inactive' ? 'inactive' : 'active')
        : accountStatus;
    final studentVerificationStatus = (data['studentVerificationStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    String normalizedVerification(String raw) {
      switch (raw) {
        case 'pending_email_verification':
        case 'pending_profile':
        case 'pending_approval':
        case 'verified':
          return raw;
        case 'pending_verification':
          return 'pending_approval';
        default:
          return '';
      }
    }

    var effectiveStudentVerification = normalizedVerification(
      studentVerificationStatus,
    );
    if (effectiveStudentVerification.isEmpty) {
      final normalizedLegacy = normalizedVerification(legacyStatus);
      if (normalizedLegacy.isNotEmpty) {
        effectiveStudentVerification = normalizedLegacy;
      } else {
        effectiveStudentVerification = legacyStatus == 'active'
            ? 'verified'
            : 'pending_profile';
      }
    }

    Future<void> syncStudentVerification(String status) async {
      try {
        await doc.reference.update({
          'studentVerificationStatus': status,
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    if (freshUser != null && !freshUser.emailVerified) {
      if (role == 'student' &&
          effectiveStudentVerification != 'pending_email_verification') {
        await syncStudentVerification('pending_email_verification');
        if (!context.mounted) return;
      }
      if (!context.mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/verify-email', (r) => false);
      return;
    }

    if (effectiveAccountStatus != 'active') {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (r) => false);
      return;
    }

    // STUDENT: status-aware Option A routing
    if (role == 'student') {
      if (effectiveStudentVerification == 'pending_email_verification') {
        final nextStatus = createdByAdmin ? 'verified' : 'pending_profile';
        effectiveStudentVerification = nextStatus;
        await syncStudentVerification(nextStatus);
        if (!context.mounted) return;
      }

      if (effectiveStudentVerification == 'pending_profile') {
        if (!context.mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CompleteProfilePage()),
        );
        return;
      }

      if (effectiveStudentVerification == 'pending_approval') {
        if (!context.mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PendingApprovalPage()),
        );
        return;
      }

      if (effectiveStudentVerification == 'verified') {
        if (!context.mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StudentDashboard()),
        );
        return;
      }

      // Unknown status: safe fallback (avoid confusing access)
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (r) => false);
      return;
    }

    // SUPER ADMIN (for testing)
    if (role == 'super_admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SuperAdminDashboard()),
      );
      return;
    }
    if (role == 'professor') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfessorDashboard()),
      );
      return;
    }
    if (role == 'osa_admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OsaDashboard()),
      );
      return;
    }
    if (role == 'department_admin' || role == 'dean') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DepartmentAdminDashboard()),
      );
      return;
    }
    if (role == 'counseling_admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CounselingDashboard()),
      );
      return;
    }
    if (role == 'guard') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const GuardDashboard()),
      );
      return;
    }

    // Default: unknown role -> fail safe to avoid hanging on login.
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (r) => false);
  }
}

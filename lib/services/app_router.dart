import 'package:apps/pages/auth/complete_profile_page.dart';
import 'package:apps/pages/auth/forgot_password_assistance_page.dart';
import 'package:apps/pages/auth/forgot_password_page.dart';
import 'package:apps/pages/auth/login_page.dart';
import 'package:apps/pages/auth/set_password_page.dart';
import 'package:apps/pages/auth/sign_up_page.dart';
import 'package:apps/pages/auth/verify_email_page.dart';
import 'package:apps/pages/counseling_admin/counseling_dashboard.dart';
import 'package:apps/pages/department_admin/department_admin_dashboard.dart';
import 'package:apps/pages/guard/guard_dashboard.dart';
import 'package:apps/pages/osa_admin/osa_dashboard.dart';
import 'package:apps/pages/professor/professor_dashboard.dart';
import 'package:apps/pages/shared/landing_page.dart';
import 'package:apps/pages/shared/pending_approval_page.dart';
import 'package:apps/pages/shared/splash_screen_page.dart';
import 'package:apps/pages/shared/welcome_screen_page.dart';
import 'package:apps/pages/student/student_dashboard.dart';
import 'package:apps/pages/super_admin/super_admin_dashboard.dart';
import 'package:apps/services/app_auth_bootstrap.dart';
import 'package:apps/services/app_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class AppRoutes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const forgotPasswordAssist = '/forgot-password-assist';
  static const setPassword = '/set-password';
  static const verifyEmail = '/verify-email';
  static const completeProfile = '/complete-profile';
  static const pendingApproval = '/pending-approval';
  static const landing = '/landing';

  static const student = '/student';
  static const professor = '/professor';
  static const osaAdmin = '/osa-admin';
  static const departmentAdmin = '/department-admin';
  static const counselingAdmin = '/counseling-admin';
  static const guard = '/guard';
  static const superAdmin = '/super-admin';

  static String withSection(String base, String section) => '$base/$section';

  static const Set<String> studentSections = <String>{
    'home',
    'handbook',
    'violations',
    'counseling',
    'profile',
    'notifications',
  };

  static const Set<String> professorSections = <String>{
    'home',
    'handbook',
    'report',
    'my-reports',
    'counseling',
    'profile',
    'notifications',
  };

  static const Set<String> departmentAdminSections = <String>{
    'dashboard',
    'handbook',
    'alerts',
    'report',
    'counseling',
    'my-reports',
    'students',
    'professors',
    'profile',
    'notifications',
  };

  static const Set<String> counselingAdminSections = <String>{
    'dashboard',
    'handbook',
    'review',
    'referral',
    'report',
    'my-reports',
    'records',
    'analytics',
    'meeting-schedule',
    'setup',
    'profile',
    'notifications',
  };

  static const Set<String> osaAdminSections = <String>{
    'dashboard',
    'handbook',
    'records',
    'setup',
    'meeting-schedule',
    'handbook-workflow',
    'handbook-editor',
    'analytics',
    'review',
    'report',
    'counseling',
    'my-reports',
    'profile',
    'notifications',
  };

  static const Set<String> guardSections = <String>{
    'home',
    'handbook',
    'report',
    'my-reports',
    'profile',
    'notifications',
  };

  static const Set<String> superAdminSections = <String>{
    'dashboard',
    'users',
    'students',
    'institution',
    'handbook',
    'profile',
    'notifications',
  };

  static const publicPaths = <String>{
    welcome,
    login,
    signup,
    forgotPassword,
    forgotPasswordAssist,
    setPassword,
    verifyEmail,
    landing,
    splash,
  };

  static const authActionPaths = <String>{
    setPassword,
    verifyEmail,
    forgotPasswordAssist,
  };

  static const statusPaths = <String>{completeProfile, pendingApproval};

  static String studentDefault() => withSection(student, 'home');
  static String professorDefault() => withSection(professor, 'home');
  static String osaAdminDefault() => withSection(osaAdmin, 'dashboard');
  static String departmentAdminDefault() =>
      withSection(departmentAdmin, 'dashboard');
  static String counselingAdminDefault() =>
      withSection(counselingAdmin, 'dashboard');
  static String guardDefault() => withSection(guard, 'home');
  static String superAdminDefault() => withSection(superAdmin, 'dashboard');
}

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: AppAuthBootstrap.instance,
    redirect: (context, state) async {
      final authActionRedirect = _authActionRouteFromUri(state.uri);
      if (authActionRedirect != null &&
          state.uri.toString() != authActionRedirect) {
        return authActionRedirect;
      }
      final path = state.uri.path;
      if (!AppAuthBootstrap.instance.ready) {
        // Auth action paths carry oobCode in the URL — redirecting to splash
        // drops the query params and breaks the flow (verify email, reset password).
        if (AppRoutes.authActionPaths.contains(path)) return null;
        return path == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final user = AppAuthBootstrap.instance.currentUser;
      if (user == null) {
        if (path == AppRoutes.splash) {
          return AppRoutes.welcome;
        }
        if (AppRoutes.publicPaths.contains(path)) return null;
        return _buildLoginRedirect(state.uri);
      }

      final landing = await _resolveLandingPath(
        user: user,
        currentUri: state.uri,
      );
      if (landing == null) return null;
      if (landing == state.uri.toString() || landing == state.uri.path) {
        return null;
      }
      return landing;
    },
    routes: <RouteBase>[
      GoRoute(path: '/', redirect: (_, state) => AppRoutes.splash),
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, state) =>
            LoginPage(prefillEmail: state.uri.queryParameters['prefillEmail']),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (_, state) => const SignUpPage(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.forgotPasswordAssist,
        builder: (_, state) => ForgotPasswordAssistancePage(
          email: state.uri.queryParameters['email'],
          mode: state.uri.queryParameters['mode'],
        ),
      ),
      GoRoute(
        path: AppRoutes.setPassword,
        builder: (_, state) => const SetPasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (_, state) => VerifyEmailPage(
          prefillEmail: state.uri.queryParameters['prefillEmail'],
          source: state.uri.queryParameters['source'],
          emailAlreadySent:
              state.uri.queryParameters['verificationEmailAlreadySent'] ==
              'true',
        ),
      ),
      GoRoute(
        path: AppRoutes.completeProfile,
        builder: (_, state) => const CompleteProfilePage(),
      ),
      GoRoute(
        path: AppRoutes.pendingApproval,
        builder: (_, state) => const PendingApprovalPage(),
      ),
      GoRoute(
        path: AppRoutes.landing,
        builder: (_, state) => const LandingPage(),
      ),
      GoRoute(
        path: AppRoutes.student,
        redirect: (_, state) => AppRoutes.studentDefault(),
      ),
      GoRoute(
        path: '${AppRoutes.student}/:section',
        builder: (_, state) => StudentDashboard(
          section: state.pathParameters['section'] ?? 'home',
          tabDeepLink: state.uri.queryParameters['tab'],
          handbookSectionId: state.uri.queryParameters['sectionId'],
          handbookHighlightText: state.uri.queryParameters['highlight'],
        ),
      ),
      GoRoute(
        path: AppRoutes.professor,
        redirect: (_, state) => AppRoutes.professorDefault(),
      ),
      GoRoute(
        path: '${AppRoutes.professor}/:section',
        builder: (_, state) => ProfessorDashboard(
          section: state.pathParameters['section'] ?? 'home',
          tabDeepLink: state.uri.queryParameters['tab'],
          handbookSectionId: state.uri.queryParameters['sectionId'],
          handbookHighlightText: state.uri.queryParameters['highlight'],
        ),
      ),
      GoRoute(
        path: AppRoutes.osaAdmin,
        redirect: (_, state) => AppRoutes.osaAdminDefault(),
      ),
      GoRoute(
        path: '${AppRoutes.osaAdmin}/:section',
        builder: (_, state) => OsaDashboard(
          section: state.pathParameters['section'] ?? 'dashboard',
          initialSelectedCaseCode: state.uri.queryParameters['caseCode'],
          initialSelectedReviewCaseCode:
              state.uri.queryParameters['reviewCaseCode'],
          reviewInboxOnOpen: state.uri.queryParameters['reviewInbox'] == '1',
          recordsPreset: state.uri.queryParameters['preset'],
          tabDeepLink: state.uri.queryParameters['tab'],
          handbookSectionId: state.uri.queryParameters['sectionId'],
          handbookHighlightText: state.uri.queryParameters['highlight'],
        ),
      ),
      GoRoute(
        path: AppRoutes.departmentAdmin,
        redirect: (_, state) => AppRoutes.departmentAdminDefault(),
      ),
      GoRoute(
        path: '${AppRoutes.departmentAdmin}/:section',
        builder: (_, state) => DepartmentAdminDashboard(
          section: state.pathParameters['section'] ?? 'dashboard',
          initialSelectedUserId: state.uri.queryParameters['studentUid'],
          initialSelectedCaseId: state.uri.queryParameters['caseId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.counselingAdmin,
        redirect: (_, state) => AppRoutes.counselingAdminDefault(),
      ),
      GoRoute(
        path: '${AppRoutes.counselingAdmin}/:section',
        builder: (_, state) => CounselingDashboard(
          section: state.pathParameters['section'] ?? 'dashboard',
          tabDeepLink: state.uri.queryParameters['tab'],
          handbookSectionId: state.uri.queryParameters['sectionId'],
          handbookHighlightText: state.uri.queryParameters['highlight'],
        ),
      ),
      GoRoute(
        path: AppRoutes.guard,
        redirect: (_, state) => AppRoutes.guardDefault(),
      ),
      GoRoute(
        path: '${AppRoutes.guard}/:section',
        builder: (_, state) =>
            GuardDashboard(section: state.pathParameters['section'] ?? 'home'),
      ),
      GoRoute(
        path: AppRoutes.superAdmin,
        redirect: (_, state) => AppRoutes.superAdminDefault(),
      ),
      GoRoute(
        path: '${AppRoutes.superAdmin}/:section',
        builder: (_, state) => SuperAdminDashboard(
          section: state.pathParameters['section'] ?? 'dashboard',
          initialEmployeeNo: state.uri.queryParameters['employeeNo'],
          initialStudentNo: state.uri.queryParameters['studentNo'],
          tabDeepLink: state.uri.queryParameters['tab'],
          handbookSectionId: state.uri.queryParameters['sectionId'],
          handbookHighlightText: state.uri.queryParameters['highlight'],
        ),
      ),
    ],
  );
}

String? _authActionRouteFromUri(Uri uri) {
  final mode = (uri.queryParameters['mode'] ?? '').trim();
  final oobCode = (uri.queryParameters['oobCode'] ?? '').trim();
  if (mode.isEmpty || oobCode.isEmpty) return null;

  final normalizedPath = uri.path.trim();
  if (mode == 'verifyEmail' && normalizedPath != AppRoutes.verifyEmail) {
    return Uri(
      path: AppRoutes.verifyEmail,
      queryParameters: uri.queryParameters,
    ).toString();
  }
  if (mode == 'resetPassword' && normalizedPath != AppRoutes.setPassword) {
    return Uri(
      path: AppRoutes.setPassword,
      queryParameters: uri.queryParameters,
    ).toString();
  }
  return null;
}

String _buildLoginRedirect(
  Uri targetUri, {
  String? prefillEmail,
  String? reason,
  bool includeNext = true,
}) {
  final next = targetUri.toString().trim();
  return Uri(
    path: AppRoutes.login,
    queryParameters: <String, String>{
      if (includeNext && next.isNotEmpty) 'next': next,
      if ((prefillEmail ?? '').trim().isNotEmpty)
        'prefillEmail': prefillEmail!.trim(),
      if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
    },
  ).toString();
}

Future<String?> _resolveLandingPath({
  required User user,
  required Uri currentUri,
}) async {
  final uid = user.uid.trim();
  if (uid.isEmpty) return AppRoutes.welcome;

  final normalizedPath = currentUri.path.trim();
  if (AppRoutes.authActionPaths.contains(normalizedPath)) {
    return null;
  }

  await user.reload();
  final freshUser = FirebaseAuth.instance.currentUser ?? user;
  if (!freshUser.emailVerified) {
    if (normalizedPath == AppRoutes.signup) return null;
    if (normalizedPath == AppRoutes.verifyEmail) return null;
    final email = (freshUser.email ?? '').trim();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    return _buildLoginRedirect(
      currentUri,
      prefillEmail: email,
      reason: 'unverified',
      includeNext: false,
    );
  }

  final userRef = AppFirestore.instance.collection('users').doc(uid);
  DocumentSnapshot<Map<String, dynamic>> doc;
  try {
    doc = await userRef.get();
  } catch (_) {
    return AppRoutes.welcome;
  }

  if (!doc.exists) {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    return AppRoutes.welcome;
  }

  final data = doc.data() ?? const <String, dynamic>{};
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
      case 'rejected':
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

  if (role == 'student' &&
      effectiveStudentVerification == 'rejected' &&
      effectiveAccountStatus != 'active') {
    try {
      await userRef.update({
        'accountStatus': 'active',
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> syncStudentVerification(String status) async {
    try {
      await userRef.update({
        'studentVerificationStatus': status,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  if (effectiveAccountStatus != 'active') {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    return AppRoutes.welcome;
  }

  if (role == 'student') {
    if (effectiveStudentVerification == 'pending_email_verification') {
      final nextStatus = createdByAdmin ? 'verified' : 'pending_profile';
      effectiveStudentVerification = nextStatus;
      await syncStudentVerification(nextStatus);
    }

    if (effectiveStudentVerification == 'pending_profile' ||
        effectiveStudentVerification == 'rejected') {
      if (normalizedPath == AppRoutes.completeProfile) return null;
      return AppRoutes.completeProfile;
    }

    if (effectiveStudentVerification == 'pending_approval') {
      if (normalizedPath == AppRoutes.pendingApproval) return null;
      return AppRoutes.pendingApproval;
    }

    if (normalizedPath == AppRoutes.completeProfile ||
        normalizedPath == AppRoutes.pendingApproval) {
      return AppRoutes.studentDefault();
    }

    final nextTarget = _resolveNextPath(currentUri.queryParameters['next']);
    if (normalizedPath == AppRoutes.login && nextTarget != null) {
      final nextPath = Uri.parse(nextTarget).path;
      if (_isAllowedPathForRole(role: role, path: nextPath)) {
        return nextTarget;
      }
      return AppRoutes.studentDefault();
    }

    if (_isPublicOrAuthLanding(normalizedPath)) {
      return AppRoutes.studentDefault();
    }

    if (!_isAllowedPathForRole(role: role, path: normalizedPath)) {
      return AppRoutes.studentDefault();
    }

    if (normalizedPath == AppRoutes.student) {
      return AppRoutes.studentDefault();
    }

    return null;
  }

  final roleDefault = _roleDefaultPath(role);
  if (roleDefault == AppRoutes.welcome) {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    return AppRoutes.welcome;
  }

  final nextTarget = _resolveNextPath(currentUri.queryParameters['next']);
  if (normalizedPath == AppRoutes.login && nextTarget != null) {
    final nextPath = Uri.parse(nextTarget).path;
    if (_isAllowedPathForRole(role: role, path: nextPath)) {
      return nextTarget;
    }
    return roleDefault;
  }

  if (_isPublicOrAuthLanding(normalizedPath) || normalizedPath == '/') {
    return roleDefault;
  }

  if (!_isAllowedPathForRole(role: role, path: normalizedPath)) {
    return roleDefault;
  }

  if (normalizedPath == _roleBasePath(role)) {
    return roleDefault;
  }

  return null;
}

String? _resolveNextPath(String? rawNext) {
  final raw = (rawNext ?? '').trim();
  if (raw.isEmpty) return null;

  Uri? uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    return null;
  }

  String path;
  if (uri.hasScheme || uri.hasAuthority) {
    path = uri.path;
    if (path.trim().isEmpty) path = '/';
    final query = uri.query;
    if (query.isNotEmpty) {
      path = '$path?$query';
    }
  } else {
    path = raw;
  }

  if (!path.startsWith('/')) return null;
  if (path.startsWith('//')) return null;
  return path;
}

String _roleBasePath(String role) {
  switch (role) {
    case 'student':
      return AppRoutes.student;
    case 'super_admin':
      return AppRoutes.superAdmin;
    case 'professor':
      return AppRoutes.professor;
    case 'osa_admin':
      return AppRoutes.osaAdmin;
    case 'department_admin':
    case 'dean':
      return AppRoutes.departmentAdmin;
    case 'counseling_admin':
      return AppRoutes.counselingAdmin;
    case 'guard':
      return AppRoutes.guard;
    default:
      return AppRoutes.welcome;
  }
}

String _roleDefaultPath(String role) {
  switch (role) {
    case 'student':
      return AppRoutes.studentDefault();
    case 'super_admin':
      return AppRoutes.superAdminDefault();
    case 'professor':
      return AppRoutes.professorDefault();
    case 'osa_admin':
      return AppRoutes.osaAdminDefault();
    case 'department_admin':
    case 'dean':
      return AppRoutes.departmentAdminDefault();
    case 'counseling_admin':
      return AppRoutes.counselingAdminDefault();
    case 'guard':
      return AppRoutes.guardDefault();
    default:
      return AppRoutes.welcome;
  }
}

bool _isAllowedSectionPath({
  required String path,
  required String root,
  required Set<String> sections,
}) {
  if (path == root) return true;
  if (!path.startsWith('$root/')) return false;
  final section = path.substring(root.length + 1);
  if (section.isEmpty || section.contains('/')) return false;
  return sections.contains(section);
}

bool _isAllowedPathForRole({required String role, required String path}) {
  switch (role) {
    case 'student':
      return _isAllowedSectionPath(
        path: path,
        root: AppRoutes.student,
        sections: AppRoutes.studentSections,
      );
    case 'super_admin':
      return _isAllowedSectionPath(
        path: path,
        root: AppRoutes.superAdmin,
        sections: AppRoutes.superAdminSections,
      );
    case 'professor':
      return _isAllowedSectionPath(
        path: path,
        root: AppRoutes.professor,
        sections: AppRoutes.professorSections,
      );
    case 'osa_admin':
      return _isAllowedSectionPath(
        path: path,
        root: AppRoutes.osaAdmin,
        sections: AppRoutes.osaAdminSections,
      );
    case 'department_admin':
    case 'dean':
      return _isAllowedSectionPath(
        path: path,
        root: AppRoutes.departmentAdmin,
        sections: AppRoutes.departmentAdminSections,
      );
    case 'counseling_admin':
      return _isAllowedSectionPath(
        path: path,
        root: AppRoutes.counselingAdmin,
        sections: AppRoutes.counselingAdminSections,
      );
    case 'guard':
      return _isAllowedSectionPath(
        path: path,
        root: AppRoutes.guard,
        sections: AppRoutes.guardSections,
      );
    default:
      return false;
  }
}

bool _isPublicOrAuthLanding(String path) {
  return path == AppRoutes.welcome ||
      path == AppRoutes.login ||
      path == AppRoutes.signup ||
      path == AppRoutes.forgotPassword ||
      path == AppRoutes.landing ||
      path == AppRoutes.splash;
}

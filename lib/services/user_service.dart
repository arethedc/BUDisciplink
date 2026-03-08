import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  Future<void> ensureUserDocExists() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'uid': user.uid,
        'email': user.email,
        'photoUrl': user.photoURL,
        'firstName': null,
        'middleName': null,
        'lastName': null,
        'displayName': user.displayName,
        'role': 'student',
        'accountStatus': 'active',
        'studentVerificationStatus': 'pending_email_verification',
        'status': 'pending_email_verification',
        'studentProfile': {
          'studentNo': null,
          'collegeId': null,
          'programId': null,
          'yearLevel': null,
        },
        'employeeProfile': {'employeeNo': null, 'department': null},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final data = snap.data() ?? <String, dynamic>{};
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if ((data['accountStatus'] ?? '').toString().trim().isEmpty) {
      final legacy = (data['status'] ?? '').toString().trim().toLowerCase();
      updates['accountStatus'] = legacy == 'inactive' ? 'inactive' : 'active';
    }

    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    if (role == 'student' &&
        (data['studentVerificationStatus'] ?? '').toString().trim().isEmpty) {
      final legacy = (data['status'] ?? '').toString().trim().toLowerCase();
      if (legacy == 'pending_profile' ||
          legacy == 'pending_email_verification' ||
          legacy == 'pending_approval' ||
          legacy == 'pending_verification' ||
          legacy == 'verified') {
        updates['studentVerificationStatus'] = legacy == 'pending_verification'
            ? 'pending_approval'
            : legacy;
      } else if (legacy == 'active') {
        updates['studentVerificationStatus'] = 'verified';
      } else {
        updates['studentVerificationStatus'] = user.emailVerified
            ? 'pending_profile'
            : 'pending_email_verification';
      }
    }

    await ref.update(updates);
  }

  Future<Map<String, dynamic>> getCurrentUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    return doc.data() ?? {};
  }
}

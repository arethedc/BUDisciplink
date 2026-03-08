import 'package:cloud_firestore/cloud_firestore.dart';

/// Migration Script: Run this to organize existing flat user data into nested profiles.
/// 
/// How to use:
/// Call [UserMigration.migrateToNestedProfiles()] from a temporary button or during app init (once).
class UserMigration {
  static Future<void> migrateToNestedProfiles() async {
    final db = FirebaseFirestore.instance;
    final usersSnap = await db.collection('users').get();

    WriteBatch batch = db.batch();
    int count = 0;

    for (var doc in usersSnap.docs) {
      final data = doc.data();
      
      // Skip if already migrated
      if (data.containsKey('studentProfile') || data.containsKey('employeeProfile')) {
        continue;
      }

      final updates = <String, dynamic>{};

      // 1. Move Student fields
      final studentProfile = {
        'studentNo': data['studentNo'],
        'collegeId': data['collegeId'],
        'programId': data['programId'],
        'yearLevel': data['yearLevel'],
      };
      updates['studentProfile'] = studentProfile;

      // 2. Move Employee fields
      final employeeProfile = {
        'employeeNo': data['employeeNo'],
        'department': data['department'] ?? data['collegeId'], // Fallback if applicable
      };
      updates['employeeProfile'] = employeeProfile;

      // 3. Remove old fields
      updates['studentNo'] = FieldValue.delete();
      updates['employeeNo'] = FieldValue.delete();
      updates['collegeId'] = FieldValue.delete();
      updates['programId'] = FieldValue.delete();
      updates['yearLevel'] = FieldValue.delete();
      updates['section'] = FieldValue.delete(); // Also cleanup section as requested

      batch.update(doc.reference, updates);
      count++;

      // Commit every 500 docs (Firestore limit)
      if (count % 500 == 0) {
        await batch.commit();
        batch = db.batch();
      }
    }

    if (count % 500 != 0) {
      await batch.commit();
    }
    
    print('Migration complete. Updated $count users.');
  }
}

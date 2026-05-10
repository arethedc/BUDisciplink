import 'package:cloud_firestore/cloud_firestore.dart';

class InstitutionSetupService {
  InstitutionSetupService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _colleges =>
      _db.collection('colleges');
  CollectionReference<Map<String, dynamic>> get _programs =>
      _db.collection('programs');

  Stream<QuerySnapshot<Map<String, dynamic>>> streamColleges() {
    return _colleges.snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamPrograms() {
    return _programs.snapshots();
  }

  Future<bool> collegeCodeExists(
    String code, {
    String? excludeCollegeId,
  }) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    final snap = await _colleges
        .where('collegeCode', isEqualTo: normalized)
        .limit(10)
        .get();
    if (excludeCollegeId == null || excludeCollegeId.trim().isEmpty) {
      return snap.docs.isNotEmpty;
    }
    return snap.docs.any((doc) => doc.id != excludeCollegeId.trim());
  }

  Future<bool> programCodeExistsInCollege(
    String collegeId,
    String code, {
    String? excludeProgramId,
  }) async {
    final normalizedCollegeId = collegeId.trim();
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCollegeId.isEmpty || normalizedCode.isEmpty) return false;
    final snap = await _programs
        .where('collegeId', isEqualTo: normalizedCollegeId)
        .limit(200)
        .get();
    return snap.docs.any((doc) {
      if (excludeProgramId != null && excludeProgramId.trim() == doc.id) {
        return false;
      }
      final value = (doc.data()['programCode'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      return value == normalizedCode;
    });
  }

  Future<void> createCollege({
    required String code,
    required String name,
    bool active = true,
    int sortOrder = 999,
  }) async {
    final normalizedCode = code.trim().toUpperCase();
    final normalizedName = name.trim();
    await _colleges.add({
      'collegeCode': normalizedCode,
      'name': normalizedName,
      'active': active,
      'sortOrder': sortOrder,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCollege({
    required String collegeId,
    required String code,
    required String name,
    required bool active,
  }) async {
    await _colleges.doc(collegeId.trim()).update({
      'collegeCode': code.trim().toUpperCase(),
      'name': name.trim(),
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createProgram({
    required String collegeId,
    required String code,
    required String name,
    bool active = true,
    int sortOrder = 999,
  }) async {
    await _programs.add({
      'collegeId': collegeId.trim(),
      'programCode': code.trim().toUpperCase(),
      'name': name.trim(),
      'active': active,
      'sortOrder': sortOrder,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateProgram({
    required String programId,
    required String collegeId,
    required String code,
    required String name,
    required bool active,
  }) async {
    await _programs.doc(programId.trim()).update({
      'programCode': code.trim().toUpperCase(),
      'name': name.trim(),
      'active': active,
      'collegeId': collegeId.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

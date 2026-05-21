import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:apps/services/app_firestore.dart';

class InstitutionSetupService {
  InstitutionSetupService({FirebaseFirestore? db})
    : _db = db ?? AppFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _colleges =>
      _db.collection('colleges');
  CollectionReference<Map<String, dynamic>> get _programs =>
      _db.collection('programs');

  String _collegeDocIdFromCode(String code) => code.trim().toLowerCase();

  String _programDocIdFromParts({
    required String collegeId,
    required String programCode,
  }) {
    return '${collegeId.trim().toLowerCase()}_${programCode.trim().toLowerCase()}';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamColleges() {
    return _colleges.snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamPrograms() {
    return _programs.snapshots();
  }

  int _coerceSortOrder(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString().trim()) ?? 0;
  }

  Future<int> _nextCollegeSortOrder() async {
    final snap = await _colleges.get();
    var maxSortOrder = 0;
    for (final doc in snap.docs) {
      final sortOrder = _coerceSortOrder(doc.data()['sortOrder']);
      if (sortOrder > maxSortOrder) maxSortOrder = sortOrder;
    }
    return maxSortOrder + 1;
  }

  Future<int> _nextProgramSortOrder(String collegeId) async {
    final normalizedCollegeId = collegeId.trim();
    final snap = await _programs
        .where('collegeId', isEqualTo: normalizedCollegeId)
        .get();
    var maxSortOrder = 0;
    for (final doc in snap.docs) {
      final sortOrder = _coerceSortOrder(doc.data()['sortOrder']);
      if (sortOrder > maxSortOrder) maxSortOrder = sortOrder;
    }
    return maxSortOrder + 1;
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
    int? sortOrder,
  }) async {
    final normalizedCode = code.trim().toUpperCase();
    final normalizedName = name.trim();
    final collegeDocId = _collegeDocIdFromCode(normalizedCode);
    final resolvedSortOrder = sortOrder ?? await _nextCollegeSortOrder();
    await _colleges.doc(collegeDocId).set({
      'collegeCode': normalizedCode,
      'name': normalizedName,
      'active': active,
      'sortOrder': resolvedSortOrder,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    int? sortOrder,
  }) async {
    final normalizedCollegeId = collegeId.trim().toLowerCase();
    final normalizedCode = code.trim().toUpperCase();
    final programDocId = _programDocIdFromParts(
      collegeId: normalizedCollegeId,
      programCode: normalizedCode,
    );
    final resolvedSortOrder =
        sortOrder ?? await _nextProgramSortOrder(normalizedCollegeId);
    await _programs.doc(programDocId).set({
      'collegeId': normalizedCollegeId,
      'programCode': normalizedCode,
      'name': name.trim(),
      'active': active,
      'sortOrder': resolvedSortOrder,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

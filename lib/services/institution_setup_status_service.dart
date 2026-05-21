import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_firestore.dart';

class InstitutionSetupStatus {
  final bool hasActiveSchoolYear;
  final bool hasActiveTerm;
  final bool hasColleges;
  final bool hasPrograms;

  const InstitutionSetupStatus({
    required this.hasActiveSchoolYear,
    required this.hasActiveTerm,
    required this.hasColleges,
    required this.hasPrograms,
  });

  bool get isComplete =>
      hasActiveSchoolYear && hasActiveTerm && hasColleges && hasPrograms;

  List<String> get missingItems {
    final items = <String>[];
    if (!hasActiveSchoolYear) items.add('Create an active school year');
    if (!hasActiveTerm) items.add('Set an active semester');
    if (!hasColleges) items.add('Add at least one college');
    if (!hasPrograms) items.add('Add at least one program');
    return items;
  }
}

class InstitutionSetupStatusService {
  InstitutionSetupStatusService({FirebaseFirestore? db})
    : _db = db ?? AppFirestore.instance;

  final FirebaseFirestore _db;

  Future<InstitutionSetupStatus> load() async {
    final activeAcademicSnap = await _db
        .collection('academic_years')
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    final hasActiveSchoolYear = activeAcademicSnap.docs.isNotEmpty;
    final hasActiveTerm = hasActiveSchoolYear
        ? (activeAcademicSnap.docs.first.data()['activeTermId'] ?? '')
              .toString()
              .trim()
              .isNotEmpty
        : false;

    final collegesSnap = await _db.collection('colleges').limit(1).get();
    final programsSnap = await _db.collection('programs').limit(1).get();

    return InstitutionSetupStatus(
      hasActiveSchoolYear: hasActiveSchoolYear,
      hasActiveTerm: hasActiveTerm,
      hasColleges: collegesSnap.docs.isNotEmpty,
      hasPrograms: programsSnap.docs.isNotEmpty,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:apps/services/app_firestore.dart';

class CollegeProgramSeedService {
  final FirebaseFirestore _db;

  CollegeProgramSeedService({FirebaseFirestore? db})
    : _db = db ?? AppFirestore.instance;

  static const List<_SeedCollege> _buColleges = [
    _SeedCollege(
      code: 'CITE',
      name: 'College of Information Technology Education',
      programs: [
        _SeedProgram(
          code: 'BSIT',
          name: 'Bachelor of Science in Information Technology',
        ),
        _SeedProgram(
          code: 'BSCS',
          name: 'Bachelor of Science in Computer Science',
        ),
        _SeedProgram(
          code: 'ACT',
          name: 'Associate in Computer Technology (Diploma Program)',
        ),
      ],
    ),
    _SeedCollege(
      code: 'CEHD',
      name: 'College of Education and Human Development',
      programs: [
        _SeedProgram(code: 'BEED', name: 'Bachelor of Elementary Education'),
        _SeedProgram(code: 'BSED', name: 'Bachelor of Secondary Education'),
        _SeedProgram(code: 'CTE', name: 'Certificate in Teacher Education'),
        _SeedProgram(
          code: 'BLIS',
          name: 'Bachelor of Library Information Science',
        ),
        _SeedProgram(code: 'BSPSY', name: 'Bachelor of Science in Psychology'),
        _SeedProgram(code: 'BSSW', name: 'Bachelor of Science in Social Work'),
      ],
    ),
    _SeedCollege(
      code: 'CLAGE',
      name: 'College of Liberal Arts and General Education',
      programs: [
        _SeedProgram(code: 'BAC', name: 'Bachelor of Arts in Communication'),
        _SeedProgram(
          code: 'BAPS',
          name: 'Bachelor of Arts in Political Science',
        ),
      ],
    ),
    _SeedCollege(
      code: 'CNAHS',
      name: 'College of Nursing and Allied Health Sciences',
      programs: [
        _SeedProgram(code: 'BSN', name: 'Bachelor of Science in Nursing'),
        _SeedProgram(
          code: 'BSMT',
          name: 'Bachelor of Science in Medical Technology',
        ),
        _SeedProgram(
          code: 'BSND',
          name: 'Bachelor of Science in Nutrition and Dietetics',
        ),
      ],
    ),
    _SeedCollege(
      code: 'CBAA',
      name: 'College of Business Administration and Accountancy',
      programs: [
        _SeedProgram(code: 'BSA', name: 'Bachelor of Science in Accountancy'),
        _SeedProgram(
          code: 'BSMA',
          name: 'Bachelor of Science in Management Accounting',
        ),
      ],
    ),
    _SeedCollege(
      code: 'CHMT',
      name: 'College of Hospitality Management and Tourism',
      programs: [
        _SeedProgram(
          code: 'BSHM',
          name: 'Bachelor of Science in Hospitality Management',
        ),
        _SeedProgram(
          code: 'BSTM',
          name: 'Bachelor of Science in Tourism Management',
        ),
      ],
    ),
    _SeedCollege(
      code: 'CEDE',
      name: 'College of Environmental Design and Engineering',
      programs: [
        _SeedProgram(
          code: 'BSCE',
          name: 'Bachelor of Science in Civil Engineering',
        ),
        _SeedProgram(
          code: 'BSCPE',
          name: 'Bachelor of Science in Computer Engineering',
        ),
        _SeedProgram(
          code: 'BSEEC',
          name: 'Bachelor of Science in Electronics Engineering',
        ),
        _SeedProgram(
          code: 'BSEE',
          name: 'Bachelor of Science in Electrical Engineering',
        ),
        _SeedProgram(
          code: 'BSIE',
          name: 'Bachelor of Science in Industrial Engineering',
        ),
        _SeedProgram(
          code: 'BSME',
          name: 'Bachelor of Science in Mechanical Engineering',
        ),
      ],
    ),
  ];

  Future<Map<String, int>> seedBuCollegesAndPrograms() async {
    final collegesRef = _db.collection('colleges');
    final programsRef = _db.collection('programs');
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    final existingCollegesSnap = await collegesRef.get();
    final existingProgramsSnap = await programsRef.get();

    final legacyCollegeIdsByCode = <String, String>{};
    for (final doc in existingCollegesSnap.docs) {
      final code = (doc.data()['collegeCode'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      if (code.isEmpty) continue;
      legacyCollegeIdsByCode[code] = doc.id.trim();
    }

    var collegesCount = 0;
    var programsCount = 0;

    for (var i = 0; i < _buColleges.length; i++) {
      final college = _buColleges[i];
      final collegeId = college.code.trim().toLowerCase();
      final collegeDoc = collegesRef.doc(collegeId);
      final collegeData = <String, dynamic>{
        'collegeCode': college.code,
        'name': college.name,
        'active': true,
        'sortOrder': i + 1,
        'updatedAt': now,
      };
      collegeData['createdAt'] = now;
      batch.set(collegeDoc, collegeData, SetOptions(merge: true));
      collegesCount++;

      for (var j = 0; j < college.programs.length; j++) {
        final program = college.programs[j];
        final programId = '${collegeId}_${program.code.trim().toLowerCase()}';
        final programDoc = programsRef.doc(programId);
        final legacyCollegeId = legacyCollegeIdsByCode[college.code] ?? '';
        final normalizedProgramCode = program.code.trim().toUpperCase();
        final hasLegacyProgram = existingProgramsSnap.docs.any((doc) {
          final data = doc.data();
          final dataCode = (data['programCode'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
          final dataCollegeId = (data['collegeId'] ?? '').toString().trim();
          return dataCode == normalizedProgramCode &&
              (dataCollegeId == collegeId || dataCollegeId == legacyCollegeId);
        });
        final programData = <String, dynamic>{
          'programCode': program.code,
          'name': program.name,
          'collegeId': collegeId,
          'active': true,
          'sortOrder': j + 1,
          'updatedAt': now,
        };
        if (!hasLegacyProgram) {
          programData['createdAt'] = now;
        }
        batch.set(programDoc, programData, SetOptions(merge: true));
        programsCount++;
      }
    }

    await batch.commit();
    return <String, int>{'colleges': collegesCount, 'programs': programsCount};
  }
}

class _SeedCollege {
  final String code;
  final String name;
  final List<_SeedProgram> programs;

  const _SeedCollege({
    required this.code,
    required this.name,
    required this.programs,
  });
}

class _SeedProgram {
  final String code;
  final String name;

  const _SeedProgram({required this.code, required this.name});
}

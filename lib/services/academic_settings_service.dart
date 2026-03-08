import 'package:cloud_firestore/cloud_firestore.dart';

class AcademicSettingsService {
  final FirebaseFirestore _db;
  AcademicSettingsService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _years =>
      _db.collection('academic_years');

  Stream<QuerySnapshot<Map<String, dynamic>>> streamYears() {
    return _years.orderBy('label', descending: true).snapshots();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getYear(String syId) {
    return _years.doc(syId).get();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamTerms(String syId) {
    return _years.doc(syId).collection('terms').snapshots();
  }

  Future<void> createSchoolYear({
    required String syId, // e.g. 2025-2026
    required String label,
  }) async {
    final ref = _years.doc(syId);
    final now = FieldValue.serverTimestamp();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        throw Exception('School Year already exists.');
      }

      tx.set(ref, {
        'label': label,
        'status': 'inactive',
        'activeTermId': 'term1',
        'createdAt': now,
        'updatedAt': now,
      });

      // Pre-create 3 terms (empty dates)
      final termsCol = ref.collection('terms');
      tx.set(termsCol.doc('term1'), {
        'name': '1st Sem',
        'order': 1,
        'startAt': null,
        'endAt': null,
      });
      tx.set(termsCol.doc('term2'), {
        'name': '2nd Sem',
        'order': 2,
        'startAt': null,
        'endAt': null,
      });
      tx.set(termsCol.doc('term3'), {
        'name': '3rd Sem',
        'order': 3,
        'startAt': null,
        'endAt': null,
      });
    });
  }

  Future<void> saveTermsAndActiveTerm({
    required String syId,
    required String activeTermId, // term1/term2/term3
    required Map<String, TermDates> termDates, // term1->dates...
  }) async {
    final yearRef = _years.doc(syId);
    final now = FieldValue.serverTimestamp();

    await _db.runTransaction((tx) async {
      tx.set(
        yearRef,
        {
          'activeTermId': activeTermId,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      final termsRef = yearRef.collection('terms');
      for (final entry in termDates.entries) {
        tx.set(
          termsRef.doc(entry.key),
          {
            'startAt': entry.value.startAt,
            'endAt': entry.value.endAt,
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  /// Set this SY active and mark all others inactive.
  Future<void> setActiveSchoolYear(String syId) async {
    final now = FieldValue.serverTimestamp();

    // WriteBatch is simpler here; it also avoids invalid transaction APIs
    // (transactions can't read a whole collection via tx.get).
    final snap = await _years.get();
    final batch = _db.batch();

    bool targetFound = false;
    for (final doc in snap.docs) {
      final id = doc.id;
      final isTarget = id == syId;
      if (isTarget) targetFound = true;
      batch.set(
        _years.doc(id),
        {
          'status': isTarget ? 'active' : 'inactive',
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    }

    if (!targetFound) {
      batch.set(
        _years.doc(syId),
        {
          'status': 'active',
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<Map<String, dynamic>?> getActiveSY() async {
    final q = await _years.where('status', isEqualTo: 'active').limit(1).get();
    if (q.docs.isEmpty) return null;
    return {'id': q.docs.first.id, ...q.docs.first.data()};
  }

  /// Generate a readable case code like VC-2526-1S-001
  /// Format: VC-[SY]-[TERM]-[NUMBER]
  /// Example: VC-2526-1S-001 = Violation Case, SY 2025-2026, 1st Sem, #001
  Future<String> generateCaseCode() async {
    final activeSY = await getActiveSY();
    if (activeSY == null) {
      throw Exception('No active school year. Please set one first.');
    }

    final syId = activeSY['id'] as String; // e.g., "2025-2026"
    final activeTermId = (activeSY['activeTermId'] ?? 'term1').toString();

    // Convert syId "2025-2026" to "2526"
    final syParts = syId.split('-');
    final syShort = syParts.length == 2
        ? '${syParts[0].substring(2)}${syParts[1].substring(2)}'
        : syId.replaceAll('-', '').substring(0, 4);

    // Convert termId "term1" to "1S", "term2" to "2S", etc.
    final termNum = activeTermId.replaceAll('term', '');
    final termShort = '${termNum}S';

    // Get next counter for this SY+Term
    final counterRef = _years.doc(syId).collection('counters').doc(activeTermId);

    // Use transaction to safely increment
    final newCount = await _db.runTransaction<int>((tx) async {
      final snap = await tx.get(counterRef);
      final current = snap.exists ? (snap.data()?['caseCount'] ?? 0) : 0;
      final next = current + 1;

      tx.set(
        counterRef,
        {'caseCount': next, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

      return next;
    });

    // Format: VC-2526-1S-001
    final caseNum = newCount.toString().padLeft(3, '0');
    return 'VC-$syShort-$termShort-$caseNum';
  }
}

class TermDates {
  final Timestamp? startAt;
  final Timestamp? endAt;
  const TermDates({required this.startAt, required this.endAt});
}

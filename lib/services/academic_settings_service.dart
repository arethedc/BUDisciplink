import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:apps/services/app_firestore.dart';

class AcademicSettingsService {
  final FirebaseFirestore _db;
  AcademicSettingsService({FirebaseFirestore? db})
    : _db = db ?? AppFirestore.instance;

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
        'activeTermId': '',
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
    final hasCompleteSemesters = _hasCompleteValidTermDates(termDates);
    final resolvedActiveTermId = hasCompleteSemesters
        ? _resolveActiveTermIdByDate(
            termDates: termDates,
            fallback: activeTermId,
          )
        : '';

    await _db.runTransaction((tx) async {
      tx.set(yearRef, {
        'activeTermId': resolvedActiveTermId,
        'updatedAt': now,
      }, SetOptions(merge: true));

      final termsRef = yearRef.collection('terms');
      for (final entry in termDates.entries) {
        tx.set(termsRef.doc(entry.key), {
          'startAt': entry.value.startAt,
          'endAt': entry.value.endAt,
        }, SetOptions(merge: true));
      }
    });
  }

  DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool _hasCompleteValidTermDates(Map<String, TermDates> termDates) {
    DateTime? startOf(String key) => termDates[key]?.startAt?.toDate();
    DateTime? endOf(String key) => termDates[key]?.endAt?.toDate();

    final t1s = startOf('term1');
    final t1e = endOf('term1');
    final t2s = startOf('term2');
    final t2e = endOf('term2');
    final t3s = startOf('term3');
    final t3e = endOf('term3');

    if (t1s == null ||
        t1e == null ||
        t2s == null ||
        t2e == null ||
        t3s == null ||
        t3e == null) {
      return false;
    }

    final t1Start = _dayOnly(t1s);
    final t1End = _dayOnly(t1e);
    final t2Start = _dayOnly(t2s);
    final t2End = _dayOnly(t2e);
    final t3Start = _dayOnly(t3s);
    final t3End = _dayOnly(t3e);

    if (!t1Start.isBefore(t1End)) return false;
    if (!t2Start.isBefore(t2End)) return false;
    if (!t3Start.isBefore(t3End)) return false;

    if (!t1End.isBefore(t2Start)) return false;
    if (!t2End.isBefore(t3Start)) return false;

    return true;
  }

  String _resolveActiveTermIdByDate({
    required Map<String, TermDates> termDates,
    required String fallback,
  }) {
    final today = _dayOnly(DateTime.now());
    final ranges = <_TermRange>[];
    for (final entry in termDates.entries) {
      final startTs = entry.value.startAt;
      final endTs = entry.value.endAt;
      if (startTs == null || endTs == null) continue;
      final start = _dayOnly(startTs.toDate());
      final end = _dayOnly(endTs.toDate());
      if (end.isBefore(start)) continue;
      ranges.add(_TermRange(id: entry.key, start: start, end: end));
    }

    if (ranges.isEmpty) return fallback;

    ranges.sort((a, b) => a.start.compareTo(b.start));

    for (final range in ranges) {
      if ((today.isAtSameMomentAs(range.start) || today.isAfter(range.start)) &&
          (today.isAtSameMomentAs(range.end) || today.isBefore(range.end))) {
        return range.id;
      }
    }

    if (today.isBefore(ranges.first.start)) return ranges.first.id;
    if (today.isAfter(ranges.last.end)) return ranges.last.id;

    for (final range in ranges) {
      if (today.isBefore(range.start)) return range.id;
    }

    return fallback;
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
      batch.set(_years.doc(id), {
        'status': isTarget ? 'active' : 'inactive',
        'updatedAt': now,
      }, SetOptions(merge: true));
    }

    if (!targetFound) {
      batch.set(_years.doc(syId), {
        'status': 'active',
        'updatedAt': now,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  String _resolveTermSlot(String termDocId, Map<String, dynamic> data) {
    final id = termDocId.toLowerCase().trim();
    if (id == 'term1' || id == '1' || id.contains('1st')) return 'term1';
    if (id == 'term2' || id == '2' || id.contains('2nd')) return 'term2';
    if (id == 'term3' || id == '3' || id.contains('3rd')) return 'term3';

    final order = data['order'];
    if (order == 1 || order == '1') return 'term1';
    if (order == 2 || order == '2') return 'term2';
    if (order == 3 || order == '3') return 'term3';

    final name = (data['name'] ?? '').toString().toLowerCase();
    if (name.contains('1st') || name.contains('first')) return 'term1';
    if (name.contains('2nd') || name.contains('second')) return 'term2';
    if (name.contains('3rd') ||
        name.contains('third') ||
        name.contains('short')) {
      return 'term3';
    }
    return '';
  }

  Future<String> syncActiveTermByDate(String syId) async {
    final yearRef = _years.doc(syId);
    final yearSnap = await yearRef.get();
    if (!yearSnap.exists) {
      throw Exception('School year not found: $syId');
    }

    final yearData = yearSnap.data() ?? const <String, dynamic>{};
    final fallback = (yearData['activeTermId'] ?? 'term1').toString().trim();

    final termsSnap = await yearRef.collection('terms').get();
    final termDates = <String, TermDates>{};
    for (final doc in termsSnap.docs) {
      final data = doc.data();
      final slot = _resolveTermSlot(doc.id, data);
      if (slot.isEmpty) continue;
      final startAt = data['startAt'] as Timestamp?;
      final endAt = data['endAt'] as Timestamp?;
      termDates[slot] = TermDates(startAt: startAt, endAt: endAt);
    }

    final resolvedActiveTermId = _hasCompleteValidTermDates(termDates)
        ? _resolveActiveTermIdByDate(
            termDates: termDates,
            fallback: fallback.isEmpty ? 'term1' : fallback,
          )
        : '';

    if (resolvedActiveTermId != fallback) {
      await yearRef.set({
        'activeTermId': resolvedActiveTermId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return resolvedActiveTermId;
  }

  Future<Map<String, dynamic>?> getActiveSY() async {
    final q = await _years.where('status', isEqualTo: 'active').limit(1).get();
    if (q.docs.isEmpty) return null;
    return {'id': q.docs.first.id, ...q.docs.first.data()};
  }

  Future<String> _generateCaseCodeWithPrefix({
    required String prefix,
    required String counterField,
  }) async {
    final activeSY = await getActiveSY();
    if (activeSY == null) {
      throw Exception('No active school year. Please set one first.');
    }

    final syId = activeSY['id'] as String; // e.g., "2025-2026"
    final activeTermId = (activeSY['activeTermId'] ?? '').toString().trim();
    if (activeTermId.isEmpty) {
      throw Exception(
        'No active semester yet. Complete all semester dates in School Year & Semesters.',
      );
    }

    // Convert syId "2025-2026" to "2526"
    final syParts = syId.split('-');
    final syShort = syParts.length == 2
        ? '${syParts[0].substring(2)}${syParts[1].substring(2)}'
        : syId.replaceAll('-', '').substring(0, 4);

    // Convert termId "term1" to "1S", "term2" to "2S", etc.
    final termNum = activeTermId.replaceAll('term', '');
    final termShort = '${termNum}S';

    // Get next counter for this SY+Term
    final counterRef = _years
        .doc(syId)
        .collection('counters')
        .doc(activeTermId);

    // Use transaction to safely increment
    final newCount = await _db.runTransaction<int>((tx) async {
      final snap = await tx.get(counterRef);
      final current = snap.exists ? (snap.data()?[counterField] ?? 0) : 0;
      final next = current + 1;

      tx.set(counterRef, {
        counterField: next,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return next;
    });

    // Format: PREFIX-2526-1S-001
    final caseNum = newCount.toString().padLeft(3, '0');
    return '$prefix-$syShort-$termShort-$caseNum';
  }

  /// Generate a readable violation case code like VC-2526-1S-001.
  Future<String> generateCaseCode() {
    return _generateCaseCodeWithPrefix(prefix: 'VC', counterField: 'caseCount');
  }

  /// Generate a readable counseling case code like CC-2526-1S-001.
  Future<String> generateCounselingCaseCode() {
    return _generateCaseCodeWithPrefix(
      prefix: 'CC',
      counterField: 'counselingCaseCount',
    );
  }
}

class TermDates {
  final Timestamp? startAt;
  final Timestamp? endAt;
  const TermDates({required this.startAt, required this.endAt});
}

class _TermRange {
  final String id;
  final DateTime start;
  final DateTime end;

  const _TermRange({required this.id, required this.start, required this.end});
}

import 'package:cloud_firestore/cloud_firestore.dart';

import 'violation_case_service.dart';

class ViolationCaseMigration {
  ViolationCaseMigration({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _cases =>
      _db.collection('violation_cases');

  /// One-time migration for existing `violation_cases`.
  ///
  /// Backfills:
  /// - `actionTypeCode` from existing action fields
  /// - `sanctionTypeCode` from existing sanction fields
  ///
  /// Returns simple counters for logging.
  Future<Map<String, int>> migrateActionAndSanctionTypes({
    int pageSize = 400,
  }) async {
    int scanned = 0;
    int updated = 0;
    int actionBackfilled = 0;
    int sanctionBackfilled = 0;

    DocumentSnapshot<Map<String, dynamic>>? lastDoc;

    while (true) {
      Query<Map<String, dynamic>> query = _cases
          .orderBy(FieldPath.documentId)
          .limit(pageSize);
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final page = await query.get();
      if (page.docs.isEmpty) break;

      final batch = _db.batch();

      for (final doc in page.docs) {
        scanned++;
        final data = doc.data();
        final updates = <String, dynamic>{};

        final existingActionCode = (data['actionTypeCode'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (existingActionCode.isEmpty) {
          final rawAction = (data['actionSelected'] ?? data['actionType'] ?? '')
              .toString();
          final resolvedAction = ViolationSetActionTypes.resolve(rawAction);
          if (resolvedAction != null) {
            updates['actionTypeCode'] = resolvedAction.code;
            actionBackfilled++;
          }
        }

        final existingSanctionCode = (data['sanctionTypeCode'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (existingSanctionCode.isEmpty) {
          final rawSanction = (data['sanctionType'] ?? '').toString();
          final resolvedSanction = ViolationSanctionTypes.normalizeCode(
            rawSanction,
          );
          if (resolvedSanction != null) {
            updates['sanctionTypeCode'] = resolvedSanction;
            sanctionBackfilled++;
          }
        }

        if (updates.isNotEmpty) {
          updates['updatedAt'] = FieldValue.serverTimestamp();
          batch.update(doc.reference, updates);
          updated++;
        }
      }

      await batch.commit();
      lastDoc = page.docs.last;
    }

    return {
      'scanned': scanned,
      'updated': updated,
      'actionTypeCodeBackfilled': actionBackfilled,
      'sanctionTypeCodeBackfilled': sanctionBackfilled,
    };
  }
}

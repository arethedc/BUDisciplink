import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:apps/services/app_firestore.dart';

class ViolationTypesService {
  static const int _defaultBookingWindowDays = 3;
  static const int _defaultGraceWindowDays = 2;
  static const int _immediateBookingWindowDays = 2;
  static const List<String> fixedSeverityLevels = <String>[
    'Minor',
    'Moderate',
    'Major',
  ];

  final FirebaseFirestore _db;
  ViolationTypesService({FirebaseFirestore? db})
    : _db = db ?? AppFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection('violation_categories');

  CollectionReference<Map<String, dynamic>> get _types =>
      _db.collection('violation_types');
  CollectionReference<Map<String, dynamic>> get _sanctionTypes =>
      _db.collection('sanction_types');
  CollectionReference<Map<String, dynamic>> get _setActions =>
      _db.collection('action_types');

  int _defaultBookingDaysForActionId(String actionId) {
    final normalized = actionId.trim().toLowerCase();
    if (normalized == 'immediate_action_required') {
      return _immediateBookingWindowDays;
    }
    return _defaultBookingWindowDays;
  }

  int _defaultGraceDaysForActionId(String actionId) {
    final normalized = actionId.trim().toLowerCase();
    if (normalized == 'immediate_action_required') return 0;
    return _defaultGraceWindowDays;
  }

  int _normalizeBookingDays(int? value, int fallback) {
    final raw = value ?? fallback;
    if (raw < 1) return fallback;
    return raw;
  }

  int _normalizeGraceDays(int? value, int fallback) {
    final raw = value ?? fallback;
    if (raw < 0) return fallback;
    return raw;
  }

  // ============================================
  // CATEGORIES
  // ============================================

  Stream<QuerySnapshot<Map<String, dynamic>>> streamCategories({
    String? concern, // filter by basic | serious
  }) {
    Query<Map<String, dynamic>> query = _categories;
    if (concern != null) {
      query = query.where('concern', isEqualTo: concern);
    }
    return query.snapshots();
  }

  Future<void> createCategory({
    required String categoryId, // e.g., dress_code
    required String concern, // basic | serious
    required String name,
    bool isActive = true,
  }) async {
    final ref = _categories.doc(categoryId);
    await ref.set({
      'concern': concern.toLowerCase().trim(),
      'name': name.trim(),
      'isActive': isActive,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCategory({
    required String categoryId,
    String? name,
    String? concern,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) updates['name'] = name.trim();
    if (concern != null && concern.trim().isNotEmpty) {
      updates['concern'] = concern.toLowerCase().trim();
    }
    if (isActive != null) updates['isActive'] = isActive;

    final batch = _db.batch();
    batch.update(_categories.doc(categoryId), updates);

    if (updates.containsKey('concern')) {
      final concernValue = updates['concern'] as String;
      final typesSnap = await _types
          .where('categoryId', isEqualTo: categoryId)
          .get();
      for (final doc in typesSnap.docs) {
        batch.update(doc.reference, {
          'concern': concernValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
  }

  Future<void> deleteCategory(String categoryId) async {
    // Check if any types reference this category
    final typesSnap = await _types
        .where('categoryId', isEqualTo: categoryId)
        .limit(1)
        .get();

    if (typesSnap.docs.isNotEmpty) {
      throw Exception(
        'Cannot delete category: violation types are still using it.',
      );
    }

    await _categories.doc(categoryId).delete();
  }

  // ============================================
  // TYPES
  // ============================================

  Stream<QuerySnapshot<Map<String, dynamic>>> streamTypes({
    String? categoryId,
    String? concern,
  }) {
    Query<Map<String, dynamic>> query = _types.orderBy('label');

    if (categoryId != null) {
      query = query.where('categoryId', isEqualTo: categoryId);
    }
    if (concern != null) {
      query = query.where('concern', isEqualTo: concern);
    }

    return query.snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamTypesByCategoryRaw(
    String categoryId,
  ) {
    return _types.where('categoryId', isEqualTo: categoryId.trim()).snapshots();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> getTypesByCategory(
    String categoryId,
  ) {
    return _types
        .where('categoryId', isEqualTo: categoryId)
        .orderBy('label')
        .get();
  }

  Future<void> createType({
    required String typeId, // e.g., improper_uniform
    required String categoryId,
    required String concern, // basic | serious (copied from category)
    required String label,
    String? descriptionHint,
    bool isActive = true,
  }) async {
    final trimmedCategoryId = categoryId.trim();
    final existingTypes = await _types
        .where('categoryId', isEqualTo: trimmedCategoryId)
        .get();
    var maxOrder = 0;
    for (final doc in existingTypes.docs) {
      final raw = doc.data()['order'];
      final next = raw is num ? raw.toInt() : 0;
      if (next > maxOrder) maxOrder = next;
    }

    final ref = _types.doc(typeId);
    await ref.set({
      'categoryId': trimmedCategoryId,
      'concern': concern.toLowerCase().trim(),
      'label': label.trim(),
      'descriptionHint':
          (descriptionHint == null || descriptionHint.trim().isEmpty)
          ? null
          : descriptionHint.trim(),
      'order': maxOrder + 1,
      'isActive': isActive,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateType({
    required String typeId,
    String? categoryId,
    String? label,
    String? descriptionHint,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (categoryId != null) updates['categoryId'] = categoryId.trim();
    if (label != null) updates['label'] = label.trim();
    if (descriptionHint != null) {
      updates['descriptionHint'] = descriptionHint.trim().isEmpty
          ? null
          : descriptionHint.trim();
    }
    if (isActive != null) updates['isActive'] = isActive;

    await _types.doc(typeId).update(updates);
  }

  Future<void> deleteType(String typeId) async {
    await _types.doc(typeId).delete();
  }

  Future<void> saveCategoryOrder(List<String> orderedCategoryIds) async {
    if (orderedCategoryIds.isEmpty) return;
    final batch = _db.batch();
    for (var i = 0; i < orderedCategoryIds.length; i++) {
      batch.update(_categories.doc(orderedCategoryIds[i]), {
        'order': i + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> saveTypeOrder(List<String> orderedTypeIds) async {
    if (orderedTypeIds.isEmpty) return;
    final batch = _db.batch();
    for (var i = 0; i < orderedTypeIds.length; i++) {
      batch.update(_types.doc(orderedTypeIds[i]), {
        'order': i + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // ============================================
  // VIOLATION SET ACTIONS
  // ============================================

  Stream<QuerySnapshot<Map<String, dynamic>>> streamSetActions() {
    return _setActions.orderBy('order').snapshots();
  }

  Future<void> createSetAction({
    required String setActionId,
    required String label,
    String? description,
    required bool meetingRequired,
    int? bookingWindowDays,
    int? graceWindowDays,
    int? order,
    bool isActive = true,
  }) async {
    int resolvedOrder = order ?? 1;
    if (order == null) {
      final existing = await _setActions.get();
      var maxOrder = 0;
      for (final doc in existing.docs) {
        final raw = doc.data()['order'];
        final next = raw is num ? raw.toInt() : 0;
        if (next > maxOrder) maxOrder = next;
      }
      resolvedOrder = maxOrder + 1;
    }

    final normalizedId = setActionId.trim();
    final fallbackBooking = _defaultBookingDaysForActionId(normalizedId);
    final fallbackGrace = _defaultGraceDaysForActionId(normalizedId);
    final normalizedBookingDays = _normalizeBookingDays(
      bookingWindowDays,
      fallbackBooking,
    );
    final normalizedGraceDays = meetingRequired
        ? _normalizeGraceDays(
            graceWindowDays,
            normalizedId.toLowerCase() == 'immediate_action_required'
                ? 0
                : fallbackGrace,
          )
        : 0;

    await _setActions.doc(setActionId.trim()).set({
      'label': label.trim(),
      'description': description == null || description.trim().isEmpty
          ? null
          : description.trim(),
      'meetingRequired': meetingRequired,
      'bookingWindowDays': normalizedBookingDays,
      'graceWindowDays': normalizedGraceDays,
      'order': resolvedOrder,
      'isActive': isActive,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSetActionActive({
    required String setActionId,
    required bool isActive,
  }) async {
    await _setActions.doc(setActionId.trim()).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSetAction({
    required String setActionId,
    String? label,
    String? description,
    bool? meetingRequired,
    int? bookingWindowDays,
    int? graceWindowDays,
    int? order,
    bool? isActive,
  }) async {
    final actionId = setActionId.trim();
    final existingDoc = await _setActions.doc(actionId).get();
    if (!existingDoc.exists) {
      throw Exception('Action type not found.');
    }
    final existing = existingDoc.data() ?? const <String, dynamic>{};
    final existingMeetingRequired = existing['meetingRequired'] == true;
    final effectiveMeetingRequired = meetingRequired ?? existingMeetingRequired;
    final defaultBooking = _defaultBookingDaysForActionId(actionId);
    final defaultGrace = _defaultGraceDaysForActionId(actionId);
    final existingBooking = (existing['bookingWindowDays'] as num?)?.toInt();
    final existingGrace = (existing['graceWindowDays'] as num?)?.toInt();

    final resolvedBookingDays = _normalizeBookingDays(
      bookingWindowDays,
      existingBooking ?? defaultBooking,
    );
    final resolvedGraceDays = effectiveMeetingRequired
        ? _normalizeGraceDays(
            graceWindowDays,
            existingGrace ??
                (actionId.toLowerCase() == 'immediate_action_required'
                    ? 0
                    : defaultGrace),
          )
        : 0;

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (label != null) updates['label'] = label.trim();
    if (description != null) {
      updates['description'] = description.trim().isEmpty
          ? null
          : description.trim();
    }
    if (meetingRequired != null) updates['meetingRequired'] = meetingRequired;
    if (bookingWindowDays != null || existing['bookingWindowDays'] == null) {
      updates['bookingWindowDays'] = resolvedBookingDays;
    }
    if (meetingRequired != null ||
        graceWindowDays != null ||
        existing['graceWindowDays'] == null) {
      updates['graceWindowDays'] = resolvedGraceDays;
    }
    if (order != null) updates['order'] = order;
    if (isActive != null) updates['isActive'] = isActive;
    await _setActions.doc(setActionId.trim()).update(updates);
  }

  Future<List<Map<String, dynamic>>> fetchActiveActionTypes() async {
    final snap = await _setActions.orderBy('order').get();
    return snap.docs
        .where((doc) => doc.data()['isActive'] != false)
        .map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'id': doc.id,
            'label': (data['label'] ?? '').toString().trim(),
            'meetingRequired': data['meetingRequired'] == true,
            'bookingWindowDays': _normalizeBookingDays(
              (data['bookingWindowDays'] as num?)?.toInt(),
              _defaultBookingDaysForActionId(doc.id),
            ),
            'graceWindowDays': (data['meetingRequired'] == true)
                ? _normalizeGraceDays(
                    (data['graceWindowDays'] as num?)?.toInt(),
                    _defaultGraceDaysForActionId(doc.id),
                  )
                : 0,
            'order': (data['order'] as num?)?.toInt() ?? 0,
          };
        })
        .where((item) => (item['label'] as String).isNotEmpty)
        .toList(growable: false);
  }

  Future<List<String>> fetchActiveConcernOptions() async {
    final snap = await _categories.where('isActive', isEqualTo: true).get();
    final seen = <String>{};
    final result = <String>[];
    for (final doc in snap.docs) {
      final concern = (doc.data()['concern'] ?? '').toString().trim();
      if (concern.isEmpty) continue;
      final key = concern.toLowerCase();
      if (seen.add(key)) result.add(key);
    }
    return result;
  }

  Future<List<String>> fetchSeverityLevels() async {
    return fixedSeverityLevels;
  }

  Future<List<Map<String, dynamic>>> fetchActiveSetActions() {
    return fetchActiveActionTypes();
  }

  // ============================================
  // SANCTION TYPES
  // ============================================

  Stream<QuerySnapshot<Map<String, dynamic>>> streamSanctionTypes() {
    return _sanctionTypes.orderBy('order').snapshots();
  }

  Future<void> createSanctionType({
    required String sanctionTypeId,
    required String label,
    String? description,
    String? severity,
    int? order,
    bool isActive = true,
  }) async {
    int resolvedOrder = order ?? 1;
    if (order == null) {
      final existing = await _sanctionTypes.get();
      var maxOrder = 0;
      for (final doc in existing.docs) {
        final raw = doc.data()['order'];
        final next = raw is num ? raw.toInt() : 0;
        if (next > maxOrder) maxOrder = next;
      }
      resolvedOrder = maxOrder + 1;
    }

    await _sanctionTypes.doc(sanctionTypeId.trim()).set({
      'label': label.trim(),
      'description': description == null || description.trim().isEmpty
          ? null
          : description.trim(),
      'severity': severity == null || severity.trim().isEmpty
          ? null
          : severity.trim(),
      'order': resolvedOrder,
      'isActive': isActive,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSanctionTypeActive({
    required String sanctionTypeId,
    required bool isActive,
  }) async {
    await _sanctionTypes.doc(sanctionTypeId.trim()).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSanctionType({
    required String sanctionTypeId,
    String? label,
    String? description,
    String? severity,
    int? order,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (label != null) updates['label'] = label.trim();
    if (description != null) {
      updates['description'] = description.trim().isEmpty
          ? null
          : description.trim();
    }
    if (severity != null) {
      updates['severity'] = severity.trim().isEmpty ? null : severity.trim();
    }
    if (order != null) updates['order'] = order;
    if (isActive != null) updates['isActive'] = isActive;
    await _sanctionTypes.doc(sanctionTypeId.trim()).update(updates);
  }

  Future<List<Map<String, dynamic>>> fetchActiveSanctionTypes() async {
    final snap = await _sanctionTypes.orderBy('order').get();
    return snap.docs
        .where((doc) => doc.data()['isActive'] != false)
        .map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'id': doc.id,
            'label': (data['label'] ?? '').toString().trim(),
            'description': (data['description'] ?? '').toString().trim(),
            'severity': (data['severity'] ?? '').toString().trim(),
            'order': (data['order'] as num?)?.toInt() ?? 0,
          };
        })
        .where((item) => (item['label'] as String).isNotEmpty)
        .toList(growable: false);
  }

  Future<int> seedDefaultActionTypes() async {
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    final actionDefaults = <Map<String, dynamic>>[
      {
        'id': 'advisory_reminder',
        'label': 'Advisory / Reminder',
        'description':
            'No meeting required. Case can be resolved after assessment.',
        'meetingRequired': false,
        'bookingWindowDays': 3,
        'graceWindowDays': 0,
        'order': 1,
      },
      {
        'id': 'formal_warning',
        'label': 'Formal Warning',
        'description': 'No meeting required. Formal warning is recorded.',
        'meetingRequired': false,
        'bookingWindowDays': 3,
        'graceWindowDays': 0,
        'order': 2,
      },
      {
        'id': 'osa_check_in',
        'label': 'OSA Check-in (soft meeting)',
        'description': 'Meeting required for follow-up.',
        'meetingRequired': true,
        'bookingWindowDays': 3,
        'graceWindowDays': 2,
        'order': 3,
      },
      {
        'id': 'parent_guardian_conference',
        'label': 'Parent/Guardian Conference',
        'description': 'Meeting required with parent/guardian coordination.',
        'meetingRequired': true,
        'bookingWindowDays': 3,
        'graceWindowDays': 2,
        'order': 4,
      },
      {
        'id': 'osa_endorsement_disciplinary_call',
        'label': 'OSA Endorsement / Disciplinary Call',
        'description': 'Meeting required with disciplinary handling.',
        'meetingRequired': true,
        'bookingWindowDays': 3,
        'graceWindowDays': 2,
        'order': 5,
      },
      {
        'id': 'immediate_action_required',
        'label': 'Immediate Action Required',
        'description': 'Meeting required with urgent intervention.',
        'meetingRequired': true,
        'bookingWindowDays': 2,
        'graceWindowDays': 0,
        'order': 6,
      },
    ];

    for (final item in actionDefaults) {
      final docRef = _setActions.doc(item['id'] as String);
      batch.set(docRef, {
        'label': item['label'],
        'description': item['description'],
        'meetingRequired': item['meetingRequired'],
        'bookingWindowDays': item['bookingWindowDays'],
        'graceWindowDays': item['graceWindowDays'],
        'order': item['order'],
        'isActive': true,
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }

    await batch.commit();
    return actionDefaults.length;
  }

  Future<int> seedDefaultSanctionTypes() async {
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    final sanctionDefaults = <Map<String, dynamic>>[
      {
        'id': 'none',
        'label': 'None',
        'description': 'No sanction applied after assessment.',
        'severity': null,
        'order': 1,
      },
      {
        'id': 'suspension',
        'label': 'Suspension',
        'description': 'Student is suspended based on case decision.',
        'severity': 'major',
        'order': 2,
      },
    ];

    for (final item in sanctionDefaults) {
      final docRef = _sanctionTypes.doc(item['id'] as String);
      batch.set(docRef, {
        'label': item['label'],
        'description': item['description'],
        'severity': item['severity'],
        'order': item['order'],
        'isActive': true,
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }

    await batch.commit();
    return sanctionDefaults.length;
  }

  Future<Map<String, int>> seedDefaultActionAndSanctionTypes() async {
    final actions = await seedDefaultActionTypes();
    final sanctions = await seedDefaultSanctionTypes();
    return <String, int>{'actions': actions, 'sanctions': sanctions};
  }

  // ============================================
  // SEED DATA (helper for initial setup)
  // ============================================

  /// Seeds the database with initial categories and types
  Future<void> seedDefaultData() async {
    final batch = _db.batch();

    // ====================================
    // BASIC OFFENSE CATEGORIES
    // ====================================

    // 1. Dress Code & Uniform
    batch.set(_categories.doc('dress_code'), {
      'concern': 'basic',
      'name': 'Dress Code & Uniform',
      'order': 1,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final dressCodeTypes = [
      {'id': 'improper_uniform_general', 'label': 'Improper Uniform (General)'},
      {'id': 'improper_pe_uniform', 'label': 'Improper PE Uniform'},
      {'id': 'improper_nstp_attire', 'label': 'Improper NSTP Attire'},
      {
        'id': 'improper_practicum_uniform',
        'label': 'Improper Practicum Uniform',
      },
      {'id': 'unauthorized_org_shirt', 'label': 'Unauthorized Org Shirt'},
      {
        'id': 'inappropriate_dressdown_attire',
        'label': 'Inappropriate Dress-down Attire',
      },
    ];

    for (final type in dressCodeTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'dress_code',
        'concern': 'basic',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 2. ID Compliance
    batch.set(_categories.doc('id_compliance'), {
      'concern': 'basic',
      'name': 'ID Compliance',
      'order': 2,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final idTypes = [
      {'id': 'no_id', 'label': 'No School ID'},
      {'id': 'id_not_visible', 'label': 'ID Not Visible'},
      {'id': 'failed_to_present_id', 'label': 'Failed to Present ID'},
      {
        'id': 'nameplate_instead_of_id',
        'label': 'Using Nameplate Instead of ID',
      },
    ];

    for (final type in idTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'id_compliance',
        'concern': 'basic',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 3. Classroom Conduct
    batch.set(_categories.doc('classroom_conduct'), {
      'concern': 'basic',
      'name': 'Classroom Conduct',
      'order': 3,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final classroomTypes = [
      {'id': 'minor_disruption', 'label': 'Minor Disruption in Class'},
      {
        'id': 'disrespectful_language_non_threat',
        'label': 'Disrespectful Language (Non-Threatening)',
      },
      {'id': 'arguing_non_threat', 'label': 'Arguing (Non-Threatening)'},
    ];

    for (final type in classroomTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'classroom_conduct',
        'concern': 'basic',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 4. Attendance & Punctuality
    batch.set(_categories.doc('attendance_punctuality'), {
      'concern': 'basic',
      'name': 'Attendance & Punctuality',
      'order': 4,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final attendanceTypes = [
      {'id': 'late_to_class', 'label': 'Late to Class'},
      {'id': 'skipping_class', 'label': 'Skipping Class'},
      {'id': 'frequent_absences', 'label': 'Frequent Absences'},
    ];

    for (final type in attendanceTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'attendance_punctuality',
        'concern': 'basic',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 5. Tech Misuse (Basic)
    batch.set(_categories.doc('tech_misuse_basic'), {
      'concern': 'basic',
      'name': 'Technology Misuse (Basic)',
      'order': 5,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final techBasicTypes = [
      {'id': 'disruptive_phone_use', 'label': 'Disruptive Phone Use in Class'},
      {'id': 'minor_it_misuse', 'label': 'Minor IT Misuse'},
    ];

    for (final type in techBasicTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'tech_misuse_basic',
        'concern': 'basic',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // ====================================
    // SERIOUS OFFENSE CATEGORIES
    // ====================================

    // 6. Academic Dishonesty
    batch.set(_categories.doc('academic_dishonesty'), {
      'concern': 'serious',
      'name': 'Academic Dishonesty',
      'order': 6,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final academicTypes = [
      {'id': 'cheating', 'label': 'Cheating'},
      {'id': 'plagiarism', 'label': 'Plagiarism'},
      {'id': 'work_not_by_student', 'label': 'Submitting Work Not by Student'},
    ];

    for (final type in academicTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'academic_dishonesty',
        'concern': 'serious',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 7. Fraud & Falsification
    batch.set(_categories.doc('fraud_falsification'), {
      'concern': 'serious',
      'name': 'Fraud & Falsification',
      'order': 7,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final fraudTypes = [
      {'id': 'misappropriation_of_funds', 'label': 'Misappropriation of Funds'},
      {
        'id': 'false_information',
        'label': 'Providing False Information to Staff',
      },
      {
        'id': 'forgery_falsification_records',
        'label': 'Forgery/Falsification of Records',
      },
      {
        'id': 'misrepresentation_as_agent',
        'label': 'Misrepresentation as School Agent',
      },
    ];

    for (final type in fraudTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'fraud_falsification',
        'concern': 'serious',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 8. Harm to Persons
    batch.set(_categories.doc('harm_to_persons'), {
      'concern': 'serious',
      'name': 'Harm to Persons',
      'order': 8,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final harmTypes = [
      {
        'id': 'threats_bullying_intimidation',
        'label': 'Threats/Bullying/Intimidation',
      },
      {'id': 'physical_fight_assault', 'label': 'Physical Fight/Assault'},
      {'id': 'hazing', 'label': 'Hazing'},
      {'id': 'cyberbullying', 'label': 'Cyberbullying'},
      {'id': 'theft_extortion', 'label': 'Theft/Extortion'},
      {'id': 'weapons_dangerous_items', 'label': 'Weapons/Dangerous Items'},
      {
        'id': 'gender_based_harassment',
        'label': 'Gender-Based Harassment (Flag for Special Pipeline)',
      },
      {'id': 'religion_offense', 'label': 'Religious Offense'},
    ];

    for (final type in harmTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'harm_to_persons',
        'concern': 'serious',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 9. Damage to Property
    batch.set(_categories.doc('damage_to_property'), {
      'concern': 'serious',
      'name': 'Damage to Property',
      'order': 9,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final damageTypes = [
      {'id': 'vandalism', 'label': 'Vandalism'},
      {
        'id': 'tampering_security_systems',
        'label': 'Tampering with Security Systems',
      },
    ];

    for (final type in damageTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'damage_to_property',
        'concern': 'serious',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 10. Community Disturbance
    batch.set(_categories.doc('community_disturbance'), {
      'concern': 'serious',
      'name': 'Community Disturbance',
      'order': 10,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final disturbanceTypes = [
      {
        'id': 'disruption_excessive_noise',
        'label': 'Disruption/Excessive Noise',
      },
      {
        'id': 'unauthorized_entry_restricted',
        'label': 'Unauthorized Entry to Restricted Area',
      },
      {
        'id': 'class_stoppage_risky_activity',
        'label': 'Class Stoppage/Risky Activity',
      },
      {'id': 'bomb_threat_false_threat', 'label': 'Bomb Threat/False Threat'},
      {'id': 'fire_alarm_misuse', 'label': 'Fire Alarm Misuse'},
      {'id': 'pda', 'label': 'Public Display of Affection (PDA)'},
      {
        'id': 'pornographic_materials_system_risk',
        'label': 'Pornographic Materials/System Risk',
      },
      {
        'id': 'nonconsensual_recording_sharing',
        'label': 'Non-consensual Recording/Sharing',
      },
    ];

    for (final type in disturbanceTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'community_disturbance',
        'concern': 'serious',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 11. Health & Safety
    batch.set(_categories.doc('health_safety'), {
      'concern': 'serious',
      'name': 'Health & Safety',
      'order': 11,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final healthTypes = [
      {'id': 'smoking_vaping', 'label': 'Smoking/Vaping'},
      {'id': 'drugs_controlled', 'label': 'Drugs/Controlled Substances'},
      {
        'id': 'alcohol_intoxication_possession',
        'label': 'Alcohol Intoxication/Possession',
      },
    ];

    for (final type in healthTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'health_safety',
        'concern': 'serious',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 12. Against Disciplinary Process
    batch.set(_categories.doc('disciplinary_process'), {
      'concern': 'serious',
      'name': 'Against Disciplinary Process',
      'order': 12,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final disciplinaryTypes = [
      {'id': 'lying_in_investigation', 'label': 'Lying in Investigation'},
      {
        'id': 'retaliation_witness_intimidation',
        'label': 'Retaliation/Witness Intimidation',
      },
      {
        'id': 'ignoring_summons_noncompliance',
        'label': 'Ignoring Summons/Non-compliance',
      },
    ];

    for (final type in disciplinaryTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'disciplinary_process',
        'concern': 'serious',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 13. Other Prohibited
    batch.set(_categories.doc('other_prohibited'), {
      'concern': 'serious',
      'name': 'Other Prohibited Conduct',
      'order': 13,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final otherTypes = [
      {'id': 'gambling_betting_bribery', 'label': 'Gambling/Betting/Bribery'},
      {'id': 'defying_directives', 'label': 'Defying Directives'},
      {'id': 'flag_code_violation', 'label': 'Flag Code Violation'},
    ];

    for (final type in otherTypes) {
      batch.set(_types.doc(type['id'] as String), {
        'categoryId': 'other_prohibited',
        'concern': 'serious',
        'label': type['label'],
        'descriptionHint': null,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Commit all changes
    await batch.commit();
  }
}

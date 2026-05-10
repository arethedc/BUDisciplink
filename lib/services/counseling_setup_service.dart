import 'package:cloud_firestore/cloud_firestore.dart';

class CounselingSetupGroup {
  final String id;
  final String title;
  final List<String> items;

  const CounselingSetupGroup({
    required this.id,
    required this.title,
    required this.items,
  });

  CounselingSetupGroup copyWith({
    String? id,
    String? title,
    List<String>? items,
  }) {
    return CounselingSetupGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      items: items ?? this.items,
    );
  }

  factory CounselingSetupGroup.fromMap(Map<String, dynamic> raw) {
    final id = (raw['id'] ?? '').toString().trim();
    final title = (raw['title'] ?? '').toString().trim();
    final items = (raw['items'] is Iterable)
        ? (raw['items'] as Iterable)
              .map((e) => (e ?? '').toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
        : <String>[];
    return CounselingSetupGroup(
      id: id,
      title: title,
      items: items,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'items': items,
    };
  }
}

class CounselingSetupConfig {
  static const String moodsKey = 'moodsBehaviors';
  static const String schoolKey = 'schoolConcerns';
  static const String relationshipsKey = 'relationships';
  static const String homeKey = 'homeConcerns';

  static const Map<String, String> defaultSectionTitles =
      <String, String>{
        moodsKey: 'Moods / Behaviors',
        schoolKey: 'School Concerns',
        relationshipsKey: 'Relationships',
        homeKey: 'Home Concerns',
      };

  final List<String> moodsBehaviors;
  final List<String> schoolConcerns;
  final List<String> relationships;
  final List<String> homeConcerns;
  final Map<String, String> sectionTitles;
  final List<CounselingSetupGroup> groups;

  const CounselingSetupConfig({
    required this.moodsBehaviors,
    required this.schoolConcerns,
    required this.relationships,
    required this.homeConcerns,
    this.sectionTitles = defaultSectionTitles,
    this.groups = const <CounselingSetupGroup>[],
  });

  static const CounselingSetupConfig defaults = CounselingSetupConfig(
    moodsBehaviors: <String>[
      'Anxious or worried',
      'Depressed or unhappy',
      'Eating disorder concerns',
      'Body image concerns',
      'Hyperactive or inattentive',
      'Shy or withdrawn',
      'Low self-esteem',
      'Aggressive behavior',
      'Stealing',
    ],
    schoolConcerns: <String>[
      'Homework not submitted',
      'Incomplete classwork',
      'Low test or assignment grades',
      'Poor classroom performance',
      'Sleeping in class or always tired',
      'Sudden change in grades',
      'Frequently tardy or absent',
      'New student',
    ],
    relationships: <String>[
      'Bullying',
      'Difficulty making friends',
      'Poor social skills',
      'Problems with friends',
      'Boyfriend or girlfriend issues',
    ],
    homeConcerns: <String>[
      'Fighting with family members',
      'Illness or death in the family',
      'Parents divorced or separated',
      'Suspected abuse',
      'Suspected substance abuse',
      'Parent request',
    ],
    groups: <CounselingSetupGroup>[
      CounselingSetupGroup(
        id: moodsKey,
        title: 'Moods / Behaviors',
        items: <String>[
          'Anxious or worried',
          'Depressed or unhappy',
          'Eating disorder concerns',
          'Body image concerns',
          'Hyperactive or inattentive',
          'Shy or withdrawn',
          'Low self-esteem',
          'Aggressive behavior',
          'Stealing',
        ],
      ),
      CounselingSetupGroup(
        id: schoolKey,
        title: 'School Concerns',
        items: <String>[
          'Homework not submitted',
          'Incomplete classwork',
          'Low test or assignment grades',
          'Poor classroom performance',
          'Sleeping in class or always tired',
          'Sudden change in grades',
          'Frequently tardy or absent',
          'New student',
        ],
      ),
      CounselingSetupGroup(
        id: relationshipsKey,
        title: 'Relationships',
        items: <String>[
          'Bullying',
          'Difficulty making friends',
          'Poor social skills',
          'Problems with friends',
          'Boyfriend or girlfriend issues',
        ],
      ),
      CounselingSetupGroup(
        id: homeKey,
        title: 'Home Concerns',
        items: <String>[
          'Fighting with family members',
          'Illness or death in the family',
          'Parents divorced or separated',
          'Suspected abuse',
          'Suspected substance abuse',
          'Parent request',
        ],
      ),
    ],
  );

  factory CounselingSetupConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    final parsedGroups = _normalizeGroups(raw);
    final byId = <String, CounselingSetupGroup>{
      for (final g in parsedGroups) g.id: g,
    };
    return CounselingSetupConfig(
      moodsBehaviors: _normalizeList(
        byId[moodsKey]?.items ?? raw['moodsBehaviors'],
        fallback: defaults.moodsBehaviors,
      ),
      schoolConcerns: _normalizeList(
        byId[schoolKey]?.items ?? raw['schoolConcerns'],
        fallback: defaults.schoolConcerns,
      ),
      relationships: _normalizeList(
        byId[relationshipsKey]?.items ?? raw['relationships'],
        fallback: defaults.relationships,
      ),
      homeConcerns: _normalizeList(
        byId[homeKey]?.items ?? raw['homeConcerns'],
        fallback: defaults.homeConcerns,
      ),
      sectionTitles: _normalizeSectionTitles(raw['sectionTitles']),
      groups: parsedGroups,
    );
  }

  Map<String, dynamic> toMap() {
    final byId = <String, CounselingSetupGroup>{
      for (final g in groups) g.id: g,
    };
    return <String, dynamic>{
      'moodsBehaviors': byId[moodsKey]?.items ?? moodsBehaviors,
      'schoolConcerns': byId[schoolKey]?.items ?? schoolConcerns,
      'relationships': byId[relationshipsKey]?.items ?? relationships,
      'homeConcerns': byId[homeKey]?.items ?? homeConcerns,
      'sectionTitles': sectionTitles,
      'groups': groups.map((g) => g.toMap()).toList(),
    };
  }

  static List<String> _normalizeList(dynamic value, {required List<String> fallback}) {
    if (value is! Iterable) return List<String>.from(fallback);
    final result = value
        .map((e) => (e ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (result.isEmpty) return List<String>.from(fallback);
    result.sort();
    return result;
  }

  static Map<String, String> _normalizeSectionTitles(dynamic raw) {
    final source = raw is Map ? raw : const <String, dynamic>{};
    final result = <String, String>{};
    for (final entry in defaultSectionTitles.entries) {
      final key = entry.key;
      final fallback = entry.value;
      final value = (source[key] ?? '').toString().trim();
      result[key] = value.isEmpty ? fallback : value;
    }
    return result;
  }

  static List<CounselingSetupGroup> _normalizeGroups(Map<String, dynamic> raw) {
    final dynamic groupsRaw = raw['groups'];
    if (groupsRaw is Iterable) {
      final groups = groupsRaw
          .map((e) => e is Map ? CounselingSetupGroup.fromMap(Map<String, dynamic>.from(e)) : null)
          .whereType<CounselingSetupGroup>()
          .where((g) => g.id.trim().isNotEmpty)
          .toList();
      if (groups.isNotEmpty) {
        return groups;
      }
    }

    final sectionTitles = _normalizeSectionTitles(raw['sectionTitles']);
    return <CounselingSetupGroup>[
      CounselingSetupGroup(
        id: moodsKey,
        title: sectionTitles[moodsKey] ?? defaultSectionTitles[moodsKey]!,
        items: _normalizeList(raw['moodsBehaviors'], fallback: defaults.moodsBehaviors),
      ),
      CounselingSetupGroup(
        id: schoolKey,
        title: sectionTitles[schoolKey] ?? defaultSectionTitles[schoolKey]!,
        items: _normalizeList(raw['schoolConcerns'], fallback: defaults.schoolConcerns),
      ),
      CounselingSetupGroup(
        id: relationshipsKey,
        title: sectionTitles[relationshipsKey] ?? defaultSectionTitles[relationshipsKey]!,
        items: _normalizeList(raw['relationships'], fallback: defaults.relationships),
      ),
      CounselingSetupGroup(
        id: homeKey,
        title: sectionTitles[homeKey] ?? defaultSectionTitles[homeKey]!,
        items: _normalizeList(raw['homeConcerns'], fallback: defaults.homeConcerns),
      ),
    ];
  }
}

class CounselingSetupService {
  CounselingSetupService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('system_settings').doc('counseling_setup');

  Stream<CounselingSetupConfig> streamConfig() {
    return _doc.snapshots().map((snapshot) {
      final data = snapshot.data();
      return CounselingSetupConfig.fromMap(data);
    });
  }

  Future<CounselingSetupConfig> getConfig() async {
    final snapshot = await _doc.get();
    return CounselingSetupConfig.fromMap(snapshot.data());
  }

  Future<void> saveConfig(CounselingSetupConfig config) async {
    await _doc.set(<String, dynamic>{
      ...config.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

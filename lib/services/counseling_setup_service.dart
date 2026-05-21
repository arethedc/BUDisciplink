import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:apps/services/app_firestore.dart';

import 'counseling_setup_seed_data.dart';

class CounselingSetupItem {
  final String id;
  final String label;
  final int sortOrder;
  final bool active;

  const CounselingSetupItem({
    required this.id,
    required this.label,
    this.sortOrder = 0,
    this.active = true,
  });

  CounselingSetupItem copyWith({
    String? id,
    String? label,
    int? sortOrder,
    bool? active,
  }) {
    return CounselingSetupItem(
      id: id ?? this.id,
      label: label ?? this.label,
      sortOrder: sortOrder ?? this.sortOrder,
      active: active ?? this.active,
    );
  }

  factory CounselingSetupItem.fromMap(Map<String, dynamic> raw) {
    final id = (raw['id'] ?? '').toString().trim();
    final label = (raw['label'] ?? raw['title'] ?? '').toString().trim();
    final sortOrder = int.tryParse((raw['sortOrder'] ?? 0).toString()) ?? 0;
    final active = raw['active'] != false;
    return CounselingSetupItem(
      id: id,
      label: label,
      sortOrder: sortOrder,
      active: active,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'sortOrder': sortOrder,
      'active': active,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is CounselingSetupItem &&
        other.id == id &&
        other.label == label &&
        other.sortOrder == sortOrder &&
        other.active == active;
  }

  @override
  int get hashCode => Object.hash(id, label, sortOrder, active);
}

class CounselingSetupGroup {
  final String id;
  final String? key;
  final String title;
  final List<CounselingSetupItem> items;
  final int sortOrder;
  final bool active;

  const CounselingSetupGroup({
    required this.id,
    this.key,
    required this.title,
    required this.items,
    this.sortOrder = 0,
    this.active = true,
  });

  CounselingSetupGroup copyWith({
    String? id,
    String? key,
    String? title,
    List<CounselingSetupItem>? items,
    int? sortOrder,
    bool? active,
  }) {
    return CounselingSetupGroup(
      id: id ?? this.id,
      key: key ?? this.key,
      title: title ?? this.title,
      items: items ?? this.items,
      sortOrder: sortOrder ?? this.sortOrder,
      active: active ?? this.active,
    );
  }

  factory CounselingSetupGroup.fromMap(Map<String, dynamic> raw) {
    final id = (raw['id'] ?? '').toString().trim();
    final key = (raw['key'] ?? '').toString().trim();
    final title = (raw['title'] ?? '').toString().trim();
    final sortOrder = int.tryParse((raw['sortOrder'] ?? 0).toString()) ?? 0;
    final active = raw['active'] != false;
    final items = (raw['items'] is Iterable)
        ? (raw['items'] as Iterable)
              .map((e) {
                if (e is CounselingSetupItem) return e;
                if (e is Map) {
                  return CounselingSetupItem.fromMap(
                    Map<String, dynamic>.from(e),
                  );
                }
                final label = (e ?? '').toString().trim();
                if (label.isEmpty) return null;
                return CounselingSetupItem(id: '', label: label, active: true);
              })
              .whereType<CounselingSetupItem>()
              .toList()
        : <CounselingSetupItem>[];
    return CounselingSetupGroup(
      id: id,
      key: key.isEmpty ? null : key,
      title: title,
      items: items,
      sortOrder: sortOrder,
      active: active,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      if (key != null) 'key': key,
      'title': title,
      'items': items.map((item) => item.toMap()).toList(),
      'sortOrder': sortOrder,
      'active': active,
    };
  }
}

class CounselingSetupConfig {
  static const String academicPerformanceKey = 'academicPerformanceInformation';
  static const String physicalAttributesKey = 'physicalAttributes';
  static const String crisisIndicatorsKey = 'crisisIndicators';
  static const String atypicalBehaviorKey = 'atypicalBehavior';

  static const Map<String, String> legacyKeyAliases = <String, String>{
    'moodsBehaviors': academicPerformanceKey,
    'schoolConcerns': physicalAttributesKey,
    'relationships': crisisIndicatorsKey,
    'homeConcerns': atypicalBehaviorKey,
  };

  static const Map<String, String> defaultSectionTitles = <String, String>{
    academicPerformanceKey: 'Academic Performance Information',
    physicalAttributesKey: 'Physical Attributes',
    crisisIndicatorsKey: 'Crisis Indicators',
    atypicalBehaviorKey: 'Atypical Behavior',
  };

  final List<String> academicPerformanceInformation;
  final List<String> physicalAttributes;
  final List<String> crisisIndicators;
  final List<String> atypicalBehavior;
  final Map<String, String> sectionTitles;
  final List<CounselingSetupGroup> groups;

  bool get hasAnyActiveGroups => groups.any((group) => group.active);

  bool get hasAnyActiveItems => groups.any(
    (group) => group.active && group.items.any((item) => item.active),
  );

  bool get hasAnyActiveOptions =>
      academicPerformanceInformation.isNotEmpty ||
      physicalAttributes.isNotEmpty ||
      crisisIndicators.isNotEmpty ||
      atypicalBehavior.isNotEmpty;

  bool get hasMinimumCounselingSetup => hasAnyActiveGroups && hasAnyActiveItems;

  const CounselingSetupConfig({
    required this.academicPerformanceInformation,
    required this.physicalAttributes,
    required this.crisisIndicators,
    required this.atypicalBehavior,
    this.sectionTitles = defaultSectionTitles,
    this.groups = const <CounselingSetupGroup>[],
  });

  static const CounselingSetupConfig empty = CounselingSetupConfig(
    academicPerformanceInformation: <String>[],
    physicalAttributes: <String>[],
    crisisIndicators: <String>[],
    atypicalBehavior: <String>[],
    groups: <CounselingSetupGroup>[],
  );

  factory CounselingSetupConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return empty;
    final parsedGroups = _normalizeGroups(raw);
    final byId = <String, CounselingSetupGroup>{
      for (final g in parsedGroups) (g.key ?? g.id).trim(): g,
    };
    return CounselingSetupConfig(
      academicPerformanceInformation: _normalizeList(
        byId[academicPerformanceKey]?.items ??
            raw[academicPerformanceKey] ??
            raw['moodsBehaviors'],
        fallback: empty.academicPerformanceInformation,
      ),
      physicalAttributes: _normalizeList(
        byId[physicalAttributesKey]?.items ??
            raw[physicalAttributesKey] ??
            raw['schoolConcerns'],
        fallback: empty.physicalAttributes,
      ),
      crisisIndicators: _normalizeList(
        byId[crisisIndicatorsKey]?.items ??
            raw[crisisIndicatorsKey] ??
            raw['relationships'],
        fallback: empty.crisisIndicators,
      ),
      atypicalBehavior: _normalizeList(
        byId[atypicalBehaviorKey]?.items ??
            raw[atypicalBehaviorKey] ??
            raw['homeConcerns'],
        fallback: empty.atypicalBehavior,
      ),
      sectionTitles: _normalizeSectionTitles(raw['sectionTitles']),
      groups: parsedGroups,
    );
  }

  factory CounselingSetupConfig.fromGroups(List<CounselingSetupGroup> groups) {
    final byKey = <String, CounselingSetupGroup>{
      for (final group in groups) (group.key ?? group.id).trim(): group,
    };
    String titleFor(String key) {
      final title = byKey[key]?.title ?? '';
      final trimmed = title.trim();
      return trimmed.isEmpty ? defaultSectionTitles[key]! : trimmed;
    }

    return CounselingSetupConfig(
      academicPerformanceInformation: _normalizeList(
        byKey[academicPerformanceKey]?.items
            .where((item) => item.active)
            .map((item) => item.label),
        fallback: empty.academicPerformanceInformation,
      ),
      physicalAttributes: _normalizeList(
        byKey[physicalAttributesKey]?.items
            .where((item) => item.active)
            .map((item) => item.label),
        fallback: empty.physicalAttributes,
      ),
      crisisIndicators: _normalizeList(
        byKey[crisisIndicatorsKey]?.items
            .where((item) => item.active)
            .map((item) => item.label),
        fallback: empty.crisisIndicators,
      ),
      atypicalBehavior: _normalizeList(
        byKey[atypicalBehaviorKey]?.items
            .where((item) => item.active)
            .map((item) => item.label),
        fallback: empty.atypicalBehavior,
      ),
      sectionTitles: {
        for (final entry in defaultSectionTitles.entries)
          entry.key: titleFor(entry.key),
      },
      groups: groups,
    );
  }

  Map<String, dynamic> toMap() {
    final byId = <String, CounselingSetupGroup>{
      for (final g in groups) (g.key ?? g.id).trim(): g,
    };
    return <String, dynamic>{
      academicPerformanceKey:
          byId[academicPerformanceKey]?.items
              .where((item) => item.active)
              .map((item) => item.label)
              .toList() ??
          academicPerformanceInformation,
      physicalAttributesKey:
          byId[physicalAttributesKey]?.items
              .where((item) => item.active)
              .map((item) => item.label)
              .toList() ??
          physicalAttributes,
      crisisIndicatorsKey:
          byId[crisisIndicatorsKey]?.items
              .where((item) => item.active)
              .map((item) => item.label)
              .toList() ??
          crisisIndicators,
      atypicalBehaviorKey:
          byId[atypicalBehaviorKey]?.items
              .where((item) => item.active)
              .map((item) => item.label)
              .toList() ??
          atypicalBehavior,
      'sectionTitles': sectionTitles,
      'groups': groups.map((g) => g.toMap()).toList(),
    };
  }

  @Deprecated('Use academicPerformanceInformation')
  List<String> get moodsBehaviors => academicPerformanceInformation;

  @Deprecated('Use physicalAttributes')
  List<String> get schoolConcerns => physicalAttributes;

  @Deprecated('Use crisisIndicators')
  List<String> get relationships => crisisIndicators;

  @Deprecated('Use atypicalBehavior')
  List<String> get homeConcerns => atypicalBehavior;

  static List<String> _normalizeList(
    dynamic value, {
    required List<String> fallback,
  }) {
    if (value is! Iterable) return List<String>.from(fallback);
    final seen = <String>{};
    final result = <String>[];
    for (final e in value) {
      String label;
      if (e is CounselingSetupItem) {
        label = e.label.trim();
      } else if (e is Map) {
        final raw = Map<String, dynamic>.from(e);
        label = (raw['label'] ?? raw['title'] ?? '').toString().trim();
      } else {
        label = (e ?? '').toString().trim();
      }
      if (label.isEmpty || !seen.add(label)) continue;
      result.add(label);
    }
    if (result.isEmpty) return List<String>.from(fallback);
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
          .map((e) {
            if (e is! Map) return null;
            final group = CounselingSetupGroup.fromMap(
              Map<String, dynamic>.from(e),
            );
            final canonicalId = legacyKeyAliases[group.id] ?? group.id;
            final title = (group.title.trim().isEmpty)
                ? (defaultSectionTitles[canonicalId] ?? group.title)
                : group.title;
            return CounselingSetupGroup(
              id: canonicalId,
              key: group.key ?? canonicalId,
              title: title,
              items: group.items,
              sortOrder: group.sortOrder,
              active: group.active,
            );
          })
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
        id: academicPerformanceKey,
        key: academicPerformanceKey,
        title:
            sectionTitles[academicPerformanceKey] ??
            defaultSectionTitles[academicPerformanceKey]!,
        items: _itemsFromLabels(
          raw[academicPerformanceKey] ?? raw['moodsBehaviors'],
          fallback: empty.moodsBehaviors,
        ),
      ),
      CounselingSetupGroup(
        id: physicalAttributesKey,
        key: physicalAttributesKey,
        title:
            sectionTitles[physicalAttributesKey] ??
            defaultSectionTitles[physicalAttributesKey]!,
        items: _itemsFromLabels(
          raw[physicalAttributesKey] ?? raw['schoolConcerns'],
          fallback: empty.schoolConcerns,
        ),
      ),
      CounselingSetupGroup(
        id: crisisIndicatorsKey,
        key: crisisIndicatorsKey,
        title:
            sectionTitles[crisisIndicatorsKey] ??
            defaultSectionTitles[crisisIndicatorsKey]!,
        items: _itemsFromLabels(
          raw[crisisIndicatorsKey] ?? raw['relationships'],
          fallback: empty.relationships,
        ),
      ),
      CounselingSetupGroup(
        id: atypicalBehaviorKey,
        key: atypicalBehaviorKey,
        title:
            sectionTitles[atypicalBehaviorKey] ??
            defaultSectionTitles[atypicalBehaviorKey]!,
        items: _itemsFromLabels(
          raw[atypicalBehaviorKey] ?? raw['homeConcerns'],
          fallback: empty.homeConcerns,
        ),
      ),
    ];
  }

  static List<CounselingSetupItem> _itemsFromLabels(
    dynamic value, {
    required List<String> fallback,
  }) {
    final labels = _normalizeList(value, fallback: fallback);
    return labels
        .asMap()
        .entries
        .map(
          (entry) => CounselingSetupItem(
            id: '',
            label: entry.value,
            sortOrder: entry.key + 1,
            active: true,
          ),
        )
        .toList(growable: false);
  }
}

class CounselingSetupService {
  CounselingSetupService({FirebaseFirestore? db})
    : _db = db ?? AppFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('counseling_groups');
  DocumentReference<Map<String, dynamic>> get _legacyDoc =>
      _db.collection('system_settings').doc('counseling_setup');

  Stream<CounselingSetupConfig> streamConfig() {
    return _groups.snapshots().asyncMap((_) => getConfig());
  }

  Future<CounselingSetupConfig> getConfig() async {
    final groups = await _loadGroupsFromCollection();
    if (groups.isNotEmpty) {
      return CounselingSetupConfig.fromGroups(groups);
    }

    final snapshot = await _legacyDoc.get();
    final legacy = CounselingSetupConfig.fromMap(snapshot.data());
    if (legacy.groups.isEmpty) return legacy;

    final converted = legacy.groups
        .asMap()
        .entries
        .map((entry) {
          final group = entry.value;
          return CounselingSetupGroup(
            id: _groups.doc().id,
            key: group.key ?? group.id,
            title: group.title,
            items: group.items,
            sortOrder: entry.key + 1,
            active: group.active,
          );
        })
        .toList(growable: false);
    return CounselingSetupConfig.fromGroups(converted);
  }

  Future<Map<String, int>> seedDefaultConfig() async {
    final seedGroups = CounselingSetupSeedData.config.groups;
    final converted = seedGroups
        .asMap()
        .entries
        .map((entry) {
          final seedGroup = entry.value;
          return CounselingSetupGroup(
            id: _groups.doc().id,
            key: seedGroup.id,
            title: seedGroup.title,
            items: seedGroup.items,
            sortOrder: entry.key + 1,
            active: true,
          );
        })
        .toList(growable: false);
    await _syncGroups(converted);
    return <String, int>{
      'groups': converted.length,
      'items': converted.fold<int>(
        0,
        (total, group) => total + group.items.length,
      ),
    };
  }

  Future<bool> hasActiveSetup() async {
    final config = await getConfig();
    return config.hasAnyActiveOptions;
  }

  Future<void> saveConfig(CounselingSetupConfig config) async {
    final incoming = config.groups.isNotEmpty
        ? config.groups
        : _groupsFromConfig(config);
    await _syncGroups(incoming);
  }

  List<CounselingSetupGroup> _groupsFromConfig(CounselingSetupConfig config) {
    return <CounselingSetupGroup>[
      CounselingSetupGroup(
        id: CounselingSetupConfig.academicPerformanceKey,
        key: CounselingSetupConfig.academicPerformanceKey,
        title:
            config.sectionTitles[CounselingSetupConfig
                .academicPerformanceKey] ??
            CounselingSetupConfig.defaultSectionTitles[CounselingSetupConfig
                .academicPerformanceKey]!,
        items: config.academicPerformanceInformation
            .asMap()
            .entries
            .map(
              (entry) => CounselingSetupItem(
                id: '',
                label: entry.value,
                sortOrder: entry.key + 1,
                active: true,
              ),
            )
            .toList(growable: false),
        sortOrder: 1,
      ),
      CounselingSetupGroup(
        id: CounselingSetupConfig.physicalAttributesKey,
        key: CounselingSetupConfig.physicalAttributesKey,
        title:
            config.sectionTitles[CounselingSetupConfig.physicalAttributesKey] ??
            CounselingSetupConfig.defaultSectionTitles[CounselingSetupConfig
                .physicalAttributesKey]!,
        items: config.physicalAttributes
            .asMap()
            .entries
            .map(
              (entry) => CounselingSetupItem(
                id: '',
                label: entry.value,
                sortOrder: entry.key + 1,
                active: true,
              ),
            )
            .toList(growable: false),
        sortOrder: 2,
      ),
      CounselingSetupGroup(
        id: CounselingSetupConfig.crisisIndicatorsKey,
        key: CounselingSetupConfig.crisisIndicatorsKey,
        title:
            config.sectionTitles[CounselingSetupConfig.crisisIndicatorsKey] ??
            CounselingSetupConfig.defaultSectionTitles[CounselingSetupConfig
                .crisisIndicatorsKey]!,
        items: config.crisisIndicators
            .asMap()
            .entries
            .map(
              (entry) => CounselingSetupItem(
                id: '',
                label: entry.value,
                sortOrder: entry.key + 1,
                active: true,
              ),
            )
            .toList(growable: false),
        sortOrder: 3,
      ),
      CounselingSetupGroup(
        id: CounselingSetupConfig.atypicalBehaviorKey,
        key: CounselingSetupConfig.atypicalBehaviorKey,
        title:
            config.sectionTitles[CounselingSetupConfig.atypicalBehaviorKey] ??
            CounselingSetupConfig.defaultSectionTitles[CounselingSetupConfig
                .atypicalBehaviorKey]!,
        items: config.atypicalBehavior
            .asMap()
            .entries
            .map(
              (entry) => CounselingSetupItem(
                id: '',
                label: entry.value,
                sortOrder: entry.key + 1,
                active: true,
              ),
            )
            .toList(growable: false),
        sortOrder: 4,
      ),
    ];
  }

  Future<List<CounselingSetupGroup>> _loadGroupsFromCollection() async {
    final groupsSnap = await _groups.orderBy('sortOrder').get();
    if (groupsSnap.docs.isEmpty) return const <CounselingSetupGroup>[];

    final result = <CounselingSetupGroup>[];
    for (final groupDoc in groupsSnap.docs) {
      final data = groupDoc.data();
      final itemsSnap = await groupDoc.reference
          .collection('items')
          .orderBy('sortOrder')
          .get();
      final items = itemsSnap.docs
          .map((doc) {
            final itemData = doc.data();
            final label = (itemData['label'] ?? '').toString().trim();
            if (label.isEmpty) return null;
            return CounselingSetupItem(
              id: doc.id,
              label: label,
              sortOrder:
                  int.tryParse((itemData['sortOrder'] ?? 0).toString()) ?? 0,
              active: itemData['active'] != false,
            );
          })
          .whereType<CounselingSetupItem>()
          .toList(growable: false);
      result.add(
        CounselingSetupGroup(
          id: groupDoc.id,
          key: (data['key'] ?? '').toString().trim().isEmpty
              ? null
              : (data['key'] ?? '').toString().trim(),
          title: (data['title'] ?? '').toString().trim(),
          items: items,
          sortOrder: int.tryParse((data['sortOrder'] ?? 0).toString()) ?? 0,
          active: data['active'] != false,
        ),
      );
    }
    return result;
  }

  Future<void> _syncGroups(List<CounselingSetupGroup> groups) async {
    final existingGroupsSnap = await _groups.get();
    final existingById = {
      for (final doc in existingGroupsSnap.docs) doc.id: doc,
    };
    final incomingIds = groups.map((group) => group.id).toSet();
    final batch = _db.batch();

    for (final doc in existingGroupsSnap.docs) {
      if (!incomingIds.contains(doc.id)) {
        final itemsSnap = await doc.reference.collection('items').get();
        for (final itemDoc in itemsSnap.docs) {
          batch.delete(itemDoc.reference);
        }
        batch.delete(doc.reference);
      }
    }

    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      final groupRef = _groups.doc(group.id);
      final groupData = <String, dynamic>{
        'title': group.title.trim(),
        'key': (group.key ?? group.id).trim(),
        'sortOrder': group.sortOrder > 0 ? group.sortOrder : index + 1,
        'active': group.active,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (existingById.containsKey(group.id)) {
        groupData.remove('createdAt');
      }
      batch.set(groupRef, groupData, SetOptions(merge: true));

      final itemsCol = groupRef.collection('items');
      final oldItems = await itemsCol.get();
      final incomingItemIds = group.items
          .map((item) => item.id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final old in oldItems.docs) {
        if (!incomingItemIds.contains(old.id)) {
          batch.delete(old.reference);
        }
      }
      for (var itemIndex = 0; itemIndex < group.items.length; itemIndex++) {
        final item = group.items[itemIndex];
        if (item.label.trim().isEmpty) continue;
        final isNewItem =
            item.id.trim().isEmpty ||
            !oldItems.docs.any((doc) => doc.id == item.id.trim());
        final itemRef = item.id.trim().isEmpty
            ? itemsCol.doc()
            : itemsCol.doc(item.id.trim());
        final itemData = <String, dynamic>{
          'label': item.label.trim(),
          'sortOrder': item.sortOrder > 0 ? item.sortOrder : itemIndex + 1,
          'active': item.active,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (isNewItem) {
          itemData['createdAt'] = FieldValue.serverTimestamp();
        }
        batch.set(itemRef, itemData, SetOptions(merge: true));
      }
    }

    await batch.commit();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class HandbookNodeDoc {
  final String id;
  final String handbookId;
  final String parentId;
  final String title;
  final String content;
  final String category;
  final List<String> tags;
  final String type;
  final int sortOrder;
  final String status;
  final bool isVisible;
  final String handbookVersion;
  final String linkedOffice;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<Map<String, dynamic>> attachments;

  const HandbookNodeDoc({
    required this.id,
    required this.handbookId,
    required this.parentId,
    required this.title,
    required this.content,
    required this.category,
    required this.tags,
    required this.type,
    required this.sortOrder,
    required this.status,
    required this.isVisible,
    required this.handbookVersion,
    required this.linkedOffice,
    required this.createdAt,
    required this.updatedAt,
    required this.attachments,
  });

  bool get isRoot => parentId.trim().isEmpty;

  bool get isPublished => status.trim().toLowerCase() == 'published';

  HandbookNodeDoc copyWith({
    String? handbookId,
    String? parentId,
    String? title,
    String? content,
    String? category,
    List<String>? tags,
    String? type,
    int? sortOrder,
    String? status,
    bool? isVisible,
    String? handbookVersion,
    String? linkedOffice,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Map<String, dynamic>>? attachments,
  }) {
    return HandbookNodeDoc(
      id: id,
      handbookId: handbookId ?? this.handbookId,
      parentId: parentId ?? this.parentId,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      type: type ?? this.type,
      sortOrder: sortOrder ?? this.sortOrder,
      status: status ?? this.status,
      isVisible: isVisible ?? this.isVisible,
      handbookVersion: handbookVersion ?? this.handbookVersion,
      linkedOffice: linkedOffice ?? this.linkedOffice,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attachments: attachments ?? this.attachments,
    );
  }

  factory HandbookNodeDoc.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final tagsRaw = (data['tags'] as List?) ?? const [];
    final attachmentRaw = (data['attachments'] as List?) ?? const [];

    return HandbookNodeDoc(
      id: doc.id,
      handbookId: (data['handbookId'] ?? '').toString().trim(),
      parentId: (data['parentId'] ?? '').toString().trim(),
      title: (data['title'] ?? '').toString(),
      content: (data['content'] ?? '[]').toString(),
      category: (data['category'] ?? 'general').toString().trim(),
      tags: tagsRaw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      type: (data['type'] ?? 'info').toString().trim(),
      sortOrder: (data['sortOrder'] ?? 0) as int,
      status: (data['status'] ?? 'draft').toString().trim(),
      isVisible: (data['isVisible'] ?? true) as bool,
      handbookVersion: (data['handbookVersion'] ?? '').toString().trim(),
      linkedOffice: (data['linkedOffice'] ?? '').toString().trim(),
      createdAt: _asDateTime(data['createdAt']),
      updatedAt: _asDateTime(data['updatedAt']),
      attachments: attachmentRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'handbookId': handbookId,
      'parentId': parentId,
      'title': title,
      'content': content,
      'category': category,
      'tags': tags,
      'type': type,
      'sortOrder': sortOrder,
      'status': status,
      'isVisible': isVisible,
      'handbookVersion': handbookVersion,
      'linkedOffice': linkedOffice,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      'attachments': attachments,
    };
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class HandbookTopicDoc {
  final String id;          // doc id e.g. SY2024-2025_01_01
  final String code;        // "1.1"
  final String title;       // "History and Milestones"
  final int order;          // 1
  final String sectionCode; // "1"
  final bool isPublished;   // true

  HandbookTopicDoc({
    required this.id,
    required this.code,
    required this.title,
    required this.order,
    required this.sectionCode,
    required this.isPublished,
  });

  factory HandbookTopicDoc.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return HandbookTopicDoc(
      id: doc.id,
      code: (data['code'] ?? '') as String,
      title: (data['title'] ?? '') as String,
      order: (data['order'] ?? 0) as int,
      sectionCode: (data['sectionCode'] ?? '') as String,
      isPublished: (data['isPublished'] ?? false) as bool,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class HandbookSectionDoc {
  final String id;        // doc id e.g. SY2024-2025_01
  final String code;      // "1"
  final String title;     // "About the University"
  final int order;        // 1
  final bool isPublished; // true

  HandbookSectionDoc({
    required this.id,
    required this.code,
    required this.title,
    required this.order,
    required this.isPublished,
  });

  factory HandbookSectionDoc.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    return HandbookSectionDoc(
      id: doc.id,
      code: (data['code'] ?? '') as String,
      title: (data['title'] ?? '') as String,
      order: (data['order'] ?? 0) as int,
      isPublished: (data['isPublished'] ?? false) as bool,
    );
  }
}

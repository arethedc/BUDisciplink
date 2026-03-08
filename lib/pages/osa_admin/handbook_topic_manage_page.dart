import 'package:apps/models/handbook_topic_doc.dart';
import 'package:apps/pages/shared/handbook/handbook_topic_content_screen.dart';
import 'package:flutter/material.dart';

class HandbookTopicManagePage extends StatelessWidget {
  final HandbookTopicDoc topic;

  const HandbookTopicManagePage({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    return HandbookTopicContentScreen(
      topic: topic,
      manageMode: true,
      overrideTitle: 'Manage Topic Content',
    );
  }
}

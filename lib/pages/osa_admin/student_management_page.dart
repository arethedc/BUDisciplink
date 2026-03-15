import 'package:flutter/material.dart';

import 'user_management_page.dart';

class StudentManagementPage extends StatelessWidget {
  final String? initialSelectedUserId;

  const StudentManagementPage({super.key, this.initialSelectedUserId});

  @override
  Widget build(BuildContext context) {
    return UserManagementPage(
      studentsOnlyScope: true,
      headerTitle: 'Student Management',
      headerSubtitle: 'Manage student accounts and verification',
      initialSelectedUserId: initialSelectedUserId,
      pageBackgroundColor: Colors.white,
    );
  }
}

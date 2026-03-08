import 'package:flutter/material.dart';

import 'user_management_page.dart';

class StudentManagementPage extends StatelessWidget {
  const StudentManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const UserManagementPage(
      studentsOnlyScope: true,
      headerTitle: 'Student Management',
      headerSubtitle: 'Manage student accounts and verification',
    );
  }
}

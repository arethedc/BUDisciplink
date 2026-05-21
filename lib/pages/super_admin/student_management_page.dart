import 'package:flutter/material.dart';

import 'user_management_page.dart';

class StudentManagementPage extends StatelessWidget {
  final String? initialStudentNo;
  final String? initialTab;
  final ValueChanged<String>? onTabChanged;

  const StudentManagementPage({
    super.key,
    this.initialStudentNo,
    this.initialTab,
    this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return UserManagementPage(
      studentsOnlyScope: true,
      initialStudentNo: initialStudentNo,
      initialTab: initialTab,
      onTabChanged: onTabChanged,
      pageBackgroundColor: Colors.white,
    );
  }
}

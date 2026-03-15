import 'package:flutter/material.dart';

import '../osa_admin/user_management_page.dart';

class ProfessorManagementPage extends StatelessWidget {
  const ProfessorManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const UserManagementPage(
      professorsOnlyScope: true,
      headerTitle: 'Professor Management',
      headerSubtitle: 'Manage professor accounts under your department',
      pageBackgroundColor: Colors.white,
    );
  }
}

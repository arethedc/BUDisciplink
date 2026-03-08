import 'package:flutter/material.dart';

class ManageUsersPage extends StatelessWidget {
  const ManageUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _UserCard(name: 'Juan Dela Cruz', role: 'Student', status: 'Active'),
        _UserCard(
          name: 'Prof. Maria Santos',
          role: 'Professor',
          status: 'Active',
        ),
        _UserCard(name: 'OSA Office', role: 'OSA Admin', status: 'Inactive'),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  final String name;
  final String role;
  final String status;

  const _UserCard({
    required this.name,
    required this.role,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'Active';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.account_circle,
              size: 40,
              color: isActive ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(role),
                  Text(
                    status,
                    style: TextStyle(
                      color: isActive ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.edit), onPressed: () {}),
          ],
        ),
      ),
    );
  }
}

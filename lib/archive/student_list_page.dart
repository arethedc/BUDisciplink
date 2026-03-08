import 'package:flutter/material.dart';

class StudentListPage extends StatelessWidget {
  const StudentListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Students'),
        backgroundColor: Colors.green,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          StudentCard(
            name: 'Juan Dela Cruz',
            grade: 'Grade 10 - A',
            violations: 2,
          ),
          StudentCard(
            name: 'Maria Santos',
            grade: 'Grade 9 - B',
            violations: 0,
          ),
          StudentCard(
            name: 'Pedro Reyes',
            grade: 'Grade 11 - C',
            violations: 4,
          ),
        ],
      ),
    );
  }
}

class StudentCard extends StatelessWidget {
  final String name;
  final String grade;
  final int violations;

  const StudentCard({
    super.key,
    required this.name,
    required this.grade,
    required this.violations,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green,
          child: Text(
            name[0],
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(grade),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning, color: Colors.green),
            Text(
              violations.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        onTap: () {
          // TODO: open student profile / violation history
        },
      ),
    );
  }
}

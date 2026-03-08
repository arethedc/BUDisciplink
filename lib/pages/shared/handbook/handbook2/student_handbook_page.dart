import 'package:flutter/material.dart';

class StudentHandbookPage extends StatelessWidget {
  const StudentHandbookPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Handbook'),
        backgroundColor: Colors.green,
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          HandbookSection(
            icon: Icons.checkroom,
            title: 'Uniform Policy',
            description:
            'Students must wear the complete and proper school uniform at all times while inside the campus.',
          ),
          HandbookSection(
            icon: Icons.people,
            title: 'Student Behavior',
            description:
            'Students are expected to show respect to teachers, staff, and fellow students.',
          ),
          HandbookSection(
            icon: Icons.schedule,
            title: 'Attendance Rules',
            description:
            'Students must attend all classes regularly and arrive on time.',
          ),
          HandbookSection(
            icon: Icons.school,
            title: 'Academic Honesty',
            description:
            'Cheating, plagiarism, and other dishonest academic practices are strictly prohibited.',
          ),
        ],
      ),
    );
  }
}

class HandbookSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const HandbookSection({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.green, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

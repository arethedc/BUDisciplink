import 'package:flutter/material.dart';

class ProfessorViolationPage extends StatelessWidget {
  const ProfessorViolationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Report Violation',
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

const _bg = Color(0xFFF6FAF6);
const _hint = Color(0xFF6D7F62);

class OsaHomePage extends StatelessWidget {
  final VoidCallback? onOpenAcademicSettings;

  const OsaHomePage({super.key, this.onOpenAcademicSettings});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      alignment: Alignment.center,
      child: const Text(
        'Dashboard content is temporarily hidden.',
        style: TextStyle(
          color: _hint,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }
}

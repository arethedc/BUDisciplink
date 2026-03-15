import 'package:flutter/material.dart';

/// Centralized branding assets and labels.
class AppBranding {
  /// Target logo asset for the new BU Discipline branding.
  static const String logoAsset = 'lib/assets/bud_discipline_logo_2026.png';

  static Widget logo({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  }) {
    return Image.asset(
      logoAsset,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, error, stackTrace) => SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFE7F5EB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1B5E20), width: 1.2),
          ),
          child: const Center(
            child: Icon(Icons.shield_rounded, color: Color(0xFF1B5E20)),
          ),
        ),
      ),
    );
  }
}

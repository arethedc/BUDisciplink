import 'package:flutter/material.dart';
import '../../shared/widgets/app_layout_tokens.dart';

class OsaStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color primaryColor;
  final Color hintColor;
  final Color textColor;

  const OsaStatChip({
    super.key,
    required this.label,
    required this.value,
    required this.primaryColor,
    required this.hintColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'Roboto'),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: hintColor, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class OsaWarningBanner extends StatelessWidget {
  final String text;

  const OsaWarningBanner({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF7A5B00),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class OsaPrimaryTabBar extends StatelessWidget {
  final Key? controllerKey;
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final Color primaryColor;

  const OsaPrimaryTabBar({
    super.key,
    this.controllerKey,
    required this.tabs,
    required this.selectedIndex,
    required this.onTap,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      key: controllerKey,
      length: tabs.length,
      initialIndex: selectedIndex,
      child: Material(
        color: Colors.white,
        child: TabBar(
          labelColor: primaryColor,
          unselectedLabelColor: Colors.black54,
          indicatorColor: primaryColor,
          indicatorWeight: 2,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.black.withValues(alpha: 0.08),
          onTap: onTap,
          tabs: tabs.map((label) => Tab(text: label)).toList(),
        ),
      ),
    );
  }
}

class OsaPanelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool withShadow;
  final Color backgroundColor;

  const OsaPanelCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppRadii.lg,
    this.withShadow = false,
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: withShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

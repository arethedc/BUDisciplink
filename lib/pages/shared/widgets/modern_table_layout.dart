import 'package:flutter/material.dart';

class ModernTableLayout extends StatelessWidget {
  final Widget header;
  final Widget body;
  final Widget? desktopBody; // Optional specialized body for desktop (Excel-like)
  final Widget? details;
  final double? detailsWidth;
  final bool showDetails;

  const ModernTableLayout({
    super.key,
    required this.header,
    required this.body,
    this.desktopBody,
    this.details,
    this.detailsWidth,
    this.showDetails = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 1100;
        final activeBody = isDesktop ? (desktopBody ?? body) : body;

        return Column(
          children: [
            header,
            const Divider(height: 1),
            Expanded(
              child: isDesktop && showDetails && details != null
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: activeBody),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: detailsWidth ?? 450,
                          child: details,
                        ),
                      ],
                    )
                  : activeBody,
            ),
          ],
        );
      },
    );
  }
}

class ModernTableHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget searchBar;
  final Widget? tabs;
  final List<Widget>? filters;

  const ModernTableHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    required this.searchBar,
    this.tabs,
    this.filters,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    const hintColor = Color(0xFF6D7F62);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: hintColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 760;

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (tabs != null) tabs!,
                    if (tabs != null) const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: searchBar,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  if (tabs != null) Expanded(child: tabs!),
                  if (tabs == null) const Spacer(),
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 300,
                    child: searchBar,
                  ),
                ],
              );
            },
          ),
          if (filters != null && filters!.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters!,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

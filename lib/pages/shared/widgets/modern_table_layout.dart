import 'package:flutter/material.dart';

import 'app_theme_tokens.dart';
import 'responsive_layout_tokens.dart';

class ModernTableLayout extends StatelessWidget {
  final Widget header;
  final Widget body;
  final Widget?
  desktopBody; // Optional specialized body for desktop (Excel-like)
  final Widget? details;
  final double? detailsWidth;
  final bool showDetails;
  final bool detailsIncludeHeader;

  const ModernTableLayout({
    super.key,
    required this.header,
    required this.body,
    this.desktopBody,
    this.details,
    this.detailsWidth,
    this.showDetails = false,
    this.detailsIncludeHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop =
            constraints.maxWidth >= ResponsiveBreakpoints.splitDetails;
        final activeBody = isDesktop ? (desktopBody ?? body) : body;
        final showDesktopDetails = isDesktop && showDetails && details != null;

        if (showDesktopDetails && detailsIncludeHeader) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    header,
                    const Divider(height: 1),
                    Expanded(child: activeBody),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(width: detailsWidth ?? 450, child: details),
            ],
          );
        }

        return Column(
          children: [
            header,
            const Divider(height: 1),
            Expanded(
              child: showDesktopDetails
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: activeBody),
                        const VerticalDivider(width: 1),
                        SizedBox(width: detailsWidth ?? 450, child: details),
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
    const hintColor = AppColors.hint;
    final viewport = MediaQuery.sizeOf(context);
    final compactDesktopHeader =
        viewport.width >= ResponsiveBreakpoints.shellDesktop &&
        viewport.width <= ResponsiveBreakpoints.compactDesktopMaxWidth &&
        viewport.height <= ResponsiveBreakpoints.compactHeaderMaxHeight;

    return Container(
      padding: EdgeInsets.fromLTRB(24, compactDesktopHeader ? 12 : 20, 24, 0),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compactDesktopHeader)
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
            )
          else if (action != null)
            Align(alignment: Alignment.centerRight, child: action!),
          SizedBox(height: compactDesktopHeader ? 12 : 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow =
                  constraints.maxWidth < ResponsiveBreakpoints.narrowHeader;

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (tabs != null) tabs!,
                    if (tabs != null) const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: searchBar),
                  ],
                );
              }

              return Row(
                children: [
                  if (tabs != null) Expanded(child: tabs!),
                  if (tabs == null) const Spacer(),
                  const SizedBox(width: 20),
                  SizedBox(width: 300, child: searchBar),
                ],
              );
            },
          ),
          if (filters != null && filters!.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: filters!),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

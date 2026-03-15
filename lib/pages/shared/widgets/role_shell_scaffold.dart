import 'package:flutter/material.dart';

import 'app_theme_tokens.dart';

class RoleShellScaffold extends StatelessWidget {
  final Color backgroundColor;
  final Color headerColor;
  final String title;
  final bool usesDrawerSidebar;
  final bool showPermanentSidebar;
  final Widget? drawer;
  final Widget? sidebar;
  final double sidebarWidth;
  final Widget content;
  final VoidCallback? onNotificationsTap;
  final bool showDesktopOverlay;
  final Widget? desktopOverlay;
  final VoidCallback? onDismissDesktopOverlay;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final double headerHeight;

  const RoleShellScaffold({
    super.key,
    required this.backgroundColor,
    this.headerColor = AppColors.primary,
    required this.title,
    required this.usesDrawerSidebar,
    required this.showPermanentSidebar,
    this.drawer,
    this.sidebar,
    this.sidebarWidth = 260,
    required this.content,
    this.onNotificationsTap,
    this.showDesktopOverlay = false,
    this.desktopOverlay,
    this.onDismissDesktopOverlay,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.headerHeight = kToolbarHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      drawer: usesDrawerSidebar ? drawer : null,
      body: Row(
        children: [
          if (showPermanentSidebar && sidebar != null)
            SizedBox(
              width: sidebarWidth,
              child: Material(color: AppColors.surface, child: sidebar!),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    children: [
                      Builder(
                        builder: (ctx) {
                          return Container(
                            height: headerHeight,
                            width: double.infinity,
                            color: headerColor,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                if (usesDrawerSidebar && drawer != null)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.menu_rounded,
                                      color: Colors.white,
                                    ),
                                    onPressed: () =>
                                        Scaffold.of(ctx).openDrawer(),
                                  )
                                else
                                  const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    title,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (onNotificationsTap != null)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.notifications_none_rounded,
                                      color: Colors.white,
                                    ),
                                    onPressed: onNotificationsTap,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      Expanded(child: content),
                    ],
                  ),
                ),
                if (showDesktopOverlay && desktopOverlay != null) ...[
                  if (onDismissDesktopOverlay != null)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: onDismissDesktopOverlay,
                      ),
                    ),
                  Positioned(
                    top: headerHeight + 8,
                    right: 14,
                    child: desktopOverlay!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

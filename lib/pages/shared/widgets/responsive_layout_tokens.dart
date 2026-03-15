import 'package:flutter/widgets.dart';

enum ShellLayoutMode { mobile, desktopDrawer, desktopSidebar }

class ShellLayoutState {
  final ShellLayoutMode mode;

  const ShellLayoutState(this.mode);

  bool get isDesktop => mode != ShellLayoutMode.mobile;
  bool get usesDrawerSidebar => mode != ShellLayoutMode.desktopSidebar;
  bool get showPermanentSidebar => mode == ShellLayoutMode.desktopSidebar;
}

class ResponsiveBreakpoints {
  static const double mobile = 600;
  static const double tablet = 1024;
  static const double desktop = 1366;
  static const double wideDesktop = 1920;

  // Shared shell/layout thresholds used across dashboard modules.
  static const double shellDesktop = 900;
  static const double splitDetails = 1100;
  static const double compactDesktopMaxWidth = 1450;
  static const double compactDesktopMaxHeight = 820;
  static const double compactHeaderMaxHeight = 900;
  static const double narrowHeader = 760;
}

class ResponsiveSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

class ResponsiveLayoutTokens {
  static bool isMobile(double width) => width < ResponsiveBreakpoints.mobile;

  static bool isTablet(double width) =>
      width >= ResponsiveBreakpoints.mobile &&
      width < ResponsiveBreakpoints.tablet;

  static bool isDesktop(double width) => width >= ResponsiveBreakpoints.desktop;

  static bool usesDesktopShell(double width) =>
      width >= ResponsiveBreakpoints.shellDesktop;

  static ShellLayoutState resolveShellLayout({
    required double width,
    required double height,
    bool allowCompactDesktopDrawer = false,
  }) {
    if (width < ResponsiveBreakpoints.shellDesktop) {
      return const ShellLayoutState(ShellLayoutMode.mobile);
    }

    if (allowCompactDesktopDrawer &&
        (width <= ResponsiveBreakpoints.compactDesktopMaxWidth ||
            height <= ResponsiveBreakpoints.compactDesktopMaxHeight)) {
      return const ShellLayoutState(ShellLayoutMode.desktopDrawer);
    }

    return const ShellLayoutState(ShellLayoutMode.desktopSidebar);
  }

  static double contentMaxWidth(double width) {
    if (width >= ResponsiveBreakpoints.wideDesktop) return 1600;
    if (width >= ResponsiveBreakpoints.desktop) return 1420;
    return width;
  }

  static double pageHorizontalPadding(double width) {
    if (width >= ResponsiveBreakpoints.desktop) return ResponsiveSpacing.lg;
    if (width >= ResponsiveBreakpoints.mobile) return ResponsiveSpacing.md;
    return ResponsiveSpacing.sm;
  }

  static double cardPadding(double width) {
    if (width >= ResponsiveBreakpoints.desktop) return ResponsiveSpacing.md;
    if (width >= ResponsiveBreakpoints.mobile) return ResponsiveSpacing.sm;
    return ResponsiveSpacing.xs;
  }

  static EdgeInsets pagePadding(double width) => EdgeInsets.symmetric(
    horizontal: pageHorizontalPadding(width),
    vertical: width >= ResponsiveBreakpoints.desktop
        ? ResponsiveSpacing.md
        : ResponsiveSpacing.sm,
  );
}

import 'package:material_ui/material_ui.dart';

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;

  static BorderRadius circular(double radius) => BorderRadius.circular(radius);
}

abstract final class AppBreakpoints {
  static const double compactMax = 360;
  static const double mobileMax = 600;
  static const double tabletMax = 840;

  static double horizontalPadding(double width) {
    if (width < compactMax) return AppSpacing.lg;
    if (width < mobileMax) return AppSpacing.xxl;
    return AppSpacing.xxxl;
  }

  static double cardPadding(double width) {
    if (width < compactMax) return AppSpacing.lg;
    if (width < mobileMax) return AppSpacing.xl;
    return AppSpacing.xxl;
  }

  static double authMaxWidth(double width) {
    if (width >= mobileMax) return 440;
    return 400;
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens — documented in docs/DESIGN.md.
abstract class AppColors {
  static const bg = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E8EE);

  static const textPrimary = Color(0xFF0E1726);
  static const textSecondary = Color(0xFF5B6478);

  static const primary = Color(0xFF2563EB);
  static const primarySoft = Color(0xFFE8EFFE);
  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFE7F6EC);
  static const warning = Color(0xFFD97706);
  static const warningSoft = Color(0xFFFEF1E1);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFCE8E8);

  static const accentSecondary = Color(0xFF60A5FA);
  static const inputBg = Color(0xFFF1F5F9);
  static const inputBorder = Color(0xFFCBD5E1);

  // Wallet / dark panel palette
  static const ink = Color(0xFF0F172A);
  static const inkMuted = Color(0xFF94A3B8);
  static const gold = Color(0xFFFBBF24);

  // Profile family-banner gradient
  static const indigo = Color(0xFF6366F1);
  static const violet = Color(0xFF8B5CF6);

  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, accentSecondary],
  );

  /// Rotating pastel accents used by dashboard member cards / reward banners.
  static const softAccents = [
    primarySoft,
    successSoft,
    warningSoft,
    dangerSoft
  ];
  static const accents = [primary, success, warning, danger];
}

abstract class AppRadii {
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const pill = 999.0;
}

/// The app is desktop-navigated above this width, mobile-navigated below.
const kMobileBreakpoint = 768.0;

/// Whether to use the wide (desktop/tablet) presentation. Width alone is not
/// enough on mobile: a phone in landscape is >768px wide but must keep the
/// mobile navigation, so a tablet-class shortest side is also required.
bool isWideLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width > kMobileBreakpoint && size.shortestSide >= 600;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      error: AppColors.danger,
      surface: AppColors.surface,
    ),
  );

  final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  return base.copyWith(
    textTheme: textTheme,
    dividerColor: AppColors.border,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md)),
      contentTextStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700, color: Colors.white),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.primary),
  );
}

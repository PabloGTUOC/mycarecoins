import 'package:flutter/material.dart';

/// Design tokens copied from fluterFront/lib/theme/app_theme.dart.
abstract class AppColors {
  static const bg = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E8EE);

  static const textPrimary = Color(0xFF0E1726);
  static const textSecondary = Color(0xFF5B6478);

  static const primary = Color(0xFF006EB8);
  static const primarySoft = Color(0xFFE6F0F8);
  static const primaryInk = Color(0xFF005B8D);

  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFE7F6EC);
  static const successInk = Color(0xFF166534);
  static const successStrong = Color(0xFF15803D);

  static const warning = Color(0xFFD97706);
  static const warningSoft = Color(0xFFFEF1E1);
  static const warningInk = Color(0xFF92400E);
  static const warningStrong = Color(0xFFB45309);


  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFCE8E8);
  static const dangerInk = Color(0xFFB91C1C);

  static const inputBg = Color(0xFFF1F5F9);
  static const inputBorder = Color(0xFFCBD5E1);
}

abstract class AppRadii {
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const pill = 999.0;
}

ThemeData buildAdminTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondaryContainer: AppColors.primarySoft,
      onSecondaryContainer: AppColors.primaryInk,
      error: AppColors.danger,
      surface: AppColors.surface,
    ),
  );

  return base.copyWith(
    dividerColor: AppColors.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      iconTheme: IconThemeData(color: AppColors.textSecondary),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      elevation: 1,
      labelType: NavigationRailLabelType.all,
      selectedIconTheme: const IconThemeData(color: AppColors.primaryInk),
      unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
      selectedLabelTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryInk,
      ),
      unselectedLabelTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primarySoft;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryInk;
          }
          return AppColors.textSecondary;
        }),
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.border),
        ),
        textStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 13,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: const WidgetStatePropertyAll(AppColors.surface),
      headingTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      dataTextStyle: const TextStyle(
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
      dividerThickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      contentTextStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      labelStyle: const TextStyle(
        fontSize: 13,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

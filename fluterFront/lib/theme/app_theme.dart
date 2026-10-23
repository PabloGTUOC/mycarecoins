import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens — documented in docs/DESIGN.md.
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

  static const accentSecondary = Color(0xFF5A82B3);
  static const inputBg = Color(0xFFF1F5F9);
  static const inputBorder = Color(0xFFCBD5E1);

  // Wallet / dark panel palette
  static const ink = Color(0xFF0F172A);
  static const inkMuted = Color(0xFF94A3B8);
  static const successOnDark = Color(0xFF34D399); // +amounts on the dark wallet card
  static const dangerOnDark = Color(0xFFF87171); // −amounts on the dark wallet card

  // Coins (Wada combination 267). Never household amber, never text on coin.
  static const coin = Color(0xFFF99D1B);      // Yellow Orange: the coin mark
  static const coinSoft = Color(0xFFFEE9CA);  // Cream Yellow at 35 %: coin pill fill
  static const coinInk = Color(0xFF7C4226);   // Wada Brown: text on coinSoft, 6.65:1

  // People: who someone is, never a status. Mark for fills and bars, soft for
  // tints, ink for text and icons on the soft (all >= 5.9:1).
  static const people = [
    PersonColor(Color(0xFF006EB8), Color(0xFFE0EEF6), Color(0xFF005B8D)), // Blue
    PersonColor(Color(0xFF00978D), Color(0xFFE0F3F1), Color(0xFF00665F)), // Benzol Green
    PersonColor(Color(0xFFF99D1B), Color(0xFFFEF3E4), Color(0xFF7C4226)), // Yellow Orange
    PersonColor(Color(0xFFA36AA5), Color(0xFFF4EDF4), Color(0xFF6E3F70)), // Aconite Violet
  ];
}

@immutable
class PersonColor {
  final Color mark, soft, ink;
  const PersonColor(this.mark, this.soft, this.ink);
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

/// Theme extension for CareCoins semantic ink and strong status colors.
@immutable
class CareColors extends ThemeExtension<CareColors> {
  final Color primaryInk;
  final Color successInk;
  final Color successStrong;
  final Color warningInk;
  final Color warningStrong;
  final Color dangerInk;

  const CareColors({
    required this.primaryInk,
    required this.successInk,
    required this.successStrong,
    required this.warningInk,
    required this.warningStrong,
    required this.dangerInk,
  });

  static const light = CareColors(
    primaryInk: AppColors.primaryInk,
    successInk: AppColors.successInk,
    successStrong: AppColors.successStrong,
    warningInk: AppColors.warningInk,
    warningStrong: AppColors.warningStrong,
    dangerInk: AppColors.dangerInk,
  );

  @override
  CareColors copyWith({
    Color? primaryInk,
    Color? successInk,
    Color? successStrong,
    Color? warningInk,
    Color? warningStrong,
    Color? dangerInk,
  }) {
    return CareColors(
      primaryInk: primaryInk ?? this.primaryInk,
      successInk: successInk ?? this.successInk,
      successStrong: successStrong ?? this.successStrong,
      warningInk: warningInk ?? this.warningInk,
      warningStrong: warningStrong ?? this.warningStrong,
      dangerInk: dangerInk ?? this.dangerInk,
    );
  }

  @override
  CareColors lerp(ThemeExtension<CareColors>? other, double t) {
    if (other is! CareColors) return this;
    return CareColors(
      primaryInk: Color.lerp(primaryInk, other.primaryInk, t)!,
      successInk: Color.lerp(successInk, other.successInk, t)!,
      successStrong: Color.lerp(successStrong, other.successStrong, t)!,
      warningInk: Color.lerp(warningInk, other.warningInk, t)!,
      warningStrong: Color.lerp(warningStrong, other.warningStrong, t)!,
      dangerInk: Color.lerp(dangerInk, other.dangerInk, t)!,
    );
  }
}

extension CareColorsTheme on BuildContext {
  CareColors get careColors =>
      Theme.of(this).extension<CareColors>() ?? CareColors.light;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      // Tonal buttons and selected states use the secondary container; pin it
      // to the brand's soft blue, or fromSeed derives a lavender.
      secondaryContainer: AppColors.primarySoft,
      onSecondaryContainer: AppColors.primaryInk,
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
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      elevation: 0,
      indicatorColor: AppColors.primarySoft,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.primaryInk);
        }
        return const IconThemeData(color: AppColors.textSecondary);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryInk,
          );
        }
        return GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        );
      }),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: AppColors.primary,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w500,
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
          return GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          );
        }),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md)),
      contentTextStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700, color: Colors.white),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.primary),
    extensions: const [CareColors.light],
  );
}

package com.carecoins.quickcore

object Palette {
    const val bg: Long = 0xFFF7F8FA
    const val surface: Long = 0xFFFFFFFF
    const val surfaceDark: Long = 0xFF1E293B
    const val border: Long = 0xFFE5E8EE
    const val textPrimary: Long = 0xFF0E1726
    const val textSecondary: Long = 0xFF5B6478
    const val primary: Long = 0xFF006EB8
    const val primarySoft: Long = 0xFFE6F0F8
    const val primaryInk: Long = 0xFF005B8D
    const val success: Long = 0xFF16A34A
    const val successSoft: Long = 0xFFE7F6EC
    const val successInk: Long = 0xFF166534
    const val warning: Long = 0xFFD97706
    const val warningSoft: Long = 0xFFFEF1E1
    const val warningInk: Long = 0xFF92400E
    const val danger: Long = 0xFFDC2626
    const val dangerSoft: Long = 0xFFFCE8E8
    const val dangerInk: Long = 0xFFB91C1C
    const val ink: Long = 0xFF0F172A
    const val inkMuted: Long = 0xFF94A3B8
    const val successOnDark: Long = 0xFF34D399
    const val dangerOnDark: Long = 0xFFF87171
    const val coin: Long = 0xFFF99D1B
    const val coinSoft: Long = 0xFFFEE9CA
    const val coinInk: Long = 0xFF7C4226

    fun widgetBackground(isDark: Boolean): Long = if (isDark) ink else bg
    fun widgetTile(isDark: Boolean): Long = if (isDark) surfaceDark else surface
    fun widgetText(isDark: Boolean): Long = if (isDark) 0xFFFFFFFF else textPrimary
    fun widgetSecondaryText(isDark: Boolean): Long = if (isDark) inkMuted else textSecondary
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/task_icon.dart';

/// ── VCard ─────────────────────────────────────────────────────────
class VCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? action;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const VCard({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.margin = const EdgeInsets.only(bottom: 24),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, subtitle != null ? 4 : 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
            ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// ── Activity structural icons ─────────────────────────────────────

/// Material Rounded icon for an activity by its subclass and type.
IconData activityTypeIcon(String? type, {String? category, String? title}) {
  if (category == 'self') {
    return personalTimeTypeIcon(type);
  }
  if ((category == null || category == 'care') &&
      (type == 'care' || type == 'household')) {
    final taskIcon = taskIconFor(title);
    if (taskIcon != null) return taskIcon;
  }
  return switch (type) {
    'care' => Icons.favorite_rounded,
    'household' => Icons.restaurant_rounded,
    'coverage' => Icons.home_rounded,
    'sport' => Icons.fitness_center_rounded,
    'social' => Icons.groups_rounded,
    'rest' => Icons.self_improvement_rounded,
    'appointment' => Icons.event_rounded,
    'other' => Icons.auto_awesome_rounded,
    _ => Icons.restaurant_rounded,
  };
}

/// Material Rounded icon for a personal-time activity type.
IconData personalTimeTypeIcon(String? type) => switch (type) {
      'sport' => Icons.fitness_center_rounded,
      'social' => Icons.groups_rounded,
      'rest' => Icons.self_improvement_rounded,
      'appointment' => Icons.event_rounded,
      _ => Icons.auto_awesome_rounded,
    };

/// Tinted background and foreground colors for an activity icon.
(Color bg, Color fg) activityTypeColors(String? type, {String? category}) {
  if (category == 'self' ||
      type == 'sport' ||
      type == 'social' ||
      type == 'rest' ||
      type == 'appointment' ||
      type == 'other') {
    return (AppColors.primarySoft, AppColors.primaryInk);
  }
  return switch (type) {
    'care' => (AppColors.successSoft, AppColors.successInk),
    'coverage' => (AppColors.primarySoft, AppColors.primaryInk),
    _ => (AppColors.warningSoft, AppColors.warningInk), // household
  };
}

/// Structural activity icon rendered inside a tinted circle.
class ActivityTypeIcon extends StatelessWidget {
  final String? type;
  final String? category;
  final String? title;
  final double size;
  final double iconSize;

  const ActivityTypeIcon({
    super.key,
    this.type,
    this.category,
    this.title,
    this.size = 34,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = activityTypeColors(type, category: category);
    final icon = activityTypeIcon(type, category: category, title: title);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: iconSize, color: fg),
    );
  }
}

/// ── VButton ───────────────────────────────────────────────────────
enum VButtonType { primary, secondary, outline, danger }

class VButton extends StatelessWidget {
  final VButtonType type;
  final bool block;
  final bool disabled;
  final VoidCallback? onPressed;
  final Widget child;

  const VButton({
    super.key,
    this.type = VButtonType.primary,
    this.block = false,
    this.disabled = false,
    this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = disabled ? null : onPressed;

    final Widget button = switch (type) {
      VButtonType.primary => FilledButton(
          onPressed: effectiveOnPressed,
          child: child,
        ),
      VButtonType.secondary => FilledButton.tonal(
          onPressed: effectiveOnPressed,
          child: child,
        ),
      VButtonType.outline => OutlinedButton(
          onPressed: effectiveOnPressed,
          child: child,
        ),
      VButtonType.danger => FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: child,
        ),
    };

    return block ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// ── VInput ────────────────────────────────────────────────────────
class VInput extends StatelessWidget {
  final TextEditingController controller;
  final String? label;
  final String? placeholder;
  final bool obscure;
  final bool enabled;
  final bool pill;
  final int maxLines;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const VInput({
    super.key,
    required this.controller,
    this.label,
    this.placeholder,
    this.obscure = false,
    this.enabled = true,
    this.pill = true,
    this.maxLines = 1,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
        pill && maxLines == 1 ? AppRadii.pill : AppRadii.md);
    return Column(
      // min, or a VInput used directly as AlertDialog content stretches
      // the dialog to full screen height.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!,
              style: const TextStyle(
                  fontSize: 13.6,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          maxLines: maxLines,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: placeholder,
            // Slate at full opacity: the old 50%-alpha hint fell to ~2:1
            // contrast, below the WCAG AA floor PRODUCT.md commits to.
            hintStyle: const TextStyle(color: Color(0xFF64748B)),
            filled: true,
            fillColor: AppColors.inputBg,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: const BorderSide(color: AppColors.inputBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5)),
            disabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: const BorderSide(color: AppColors.inputBorder)),
          ),
        ),
      ],
    );
  }
}

/// ── KpiCard ───────────────────────────────────────────────────────
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String? subtitle;
  final String? delta;
  final Color? accent;
  final Color deltaColor;
  final Color deltaBg;
  final double? progress; // 0–100

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.subtitle,
    this.delta,
    this.accent,
    this.deltaColor = AppColors.successInk,
    this.deltaBg = AppColors.successSoft,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final compact = !isWideLayout(context);
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius:
            BorderRadius.circular(compact ? AppRadii.md : AppRadii.lg),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A0E1726), blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: AppColors.textSecondary)),
              ),
              if (delta != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: deltaBg,
                      borderRadius: BorderRadius.circular(AppRadii.pill)),
                  child: Text(delta!,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: deltaColor)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: compact ? 20 : 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1,
                      color: accent ?? AppColors.textPrimary)),
              if (unit != null) ...[
                const SizedBox(width: 6),
                Text(unit!,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary)),
          ],
          if (progress != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                value: (progress!.clamp(0, 100)) / 100,
                minHeight: compact ? 2 : 3,
                backgroundColor: AppColors.bg,
                valueColor: AlwaysStoppedAnimation(accent ?? AppColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ── Avatar circle with initial ─────────────────────────────────────
class AvatarCircle extends StatelessWidget {
  final String name;
  final double size;
  final Color? background;
  final Color? foreground;

  /// Backend-relative (`/uploads/...`) or absolute avatar image URL.
  /// Falls back to the initial when null or when loading fails.
  final String? imageUrl;

  const AvatarCircle({
    super.key,
    required this.name,
    this.size = 40,
    this.background,
    this.foreground,
    this.imageUrl,
  });

  /// Resolves relative avatar paths against the API origin (avatarStyle.js).
  static String? resolve(dynamic url) {
    final s = url?.toString() ?? '';
    if (s.isEmpty) return null;
    return s.startsWith('http') ? s : '${ApiClient.apiBase}$s';
  }

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final resolved = resolve(imageUrl);
    final fallback = Text(initial,
        style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
            color: foreground ?? Colors.white));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        gradient: background == null ? AppColors.accentGradient : null,
        shape: BoxShape.circle,
      ),
      child: resolved == null
          ? fallback
          : Image.network(resolved,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Decode at display resolution so the image cache holds small
              // bitmaps, and keep the old frame while a URL re-resolves.
              cacheWidth:
                  (size * MediaQuery.devicePixelRatioOf(context)).round(),
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => fallback),
    );
  }
}

/// ── Small pill badge (badge / coin-badge styles) ───────────────────
class PillBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  final double fontSize;

  const PillBadge({
    super.key,
    required this.text,
    this.color = AppColors.warningInk,
    this.background = AppColors.warningSoft,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Text(text,
          style: TextStyle(
              fontSize: fontSize, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

/// ── Segmented tab bar (marketplace .mkt-tab-bar / activity filters) ─
class SegmentedTabs extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;

  const SegmentedTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final validSelected = (selected >= 0 && selected < tabs.length)
        ? {selected}
        : (tabs.isNotEmpty ? {0} : <int>{});
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: [
        for (var i = 0; i < tabs.length; i++)
          ButtonSegment<int>(
            value: i,
            label: Text(tabs[i]),
          ),
      ],
      selected: validSelected,
      onSelectionChanged: (newSelection) {
        if (newSelection.isNotEmpty) {
          onChanged(newSelection.first);
        }
      },
    );
  }
}

/// ── Tappable (GestureDetector + pointer cursor) ────────────────────
/// Flutter's GestureDetector keeps the default arrow on web/desktop, hiding that an element is
/// clickable. Use this for tap targets that are not Material buttons.
class Tappable extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior? behavior;
  final Widget child;

  const Tappable({
    super.key,
    this.onTap,
    this.onLongPress,
    this.behavior,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || onLongPress != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: behavior,
        onTap: onTap,
        onLongPress: onLongPress,
        child: child,
      ),
    );
  }
}

/// ── EmptyState (teaching empty states, onboarding-help-plan Phase 1) ──
/// An empty list is a chance to explain the mechanic and point at the next
/// action, instead of a bare "nothing here".
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: AppColors.textSecondary)),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              VButton(
                  type: VButtonType.outline,
                  onPressed: onAction,
                  child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error placeholder with a retry button. Shown when a screen's load fails
/// and there is no data to fall back on, so failures stop masquerading as
/// empty states on flaky connections.
class LoadErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;

  const LoadErrorState({
    super.key,
    required this.onRetry,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 36, color: AppColors.textSecondary),
            const SizedBox(height: 14),
            Text(message ?? AppLocalizations.of(context).loadErrorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.5)),
            const SizedBox(height: 18),
            VButton(
                type: VButtonType.outline,
                onPressed: onRetry,
                child: Text(AppLocalizations.of(context).retry)),
          ],
        ),
      ),
    );
  }
}

/// Large page heading used at the top of each screen.
class PageHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSubtitleTap;

  const PageHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.onSubtitleTap,
  });

  @override
  Widget build(BuildContext context) {
    final mobile = !isWideLayout(context);
    final subText = subtitle != null
        ? Text(subtitle!,
            style: const TextStyle(
                fontSize: 16, color: AppColors.textSecondary, height: 1.6))
        : null;

    if (mobile) {
      if (subtitle != null && onSubtitleTap != null) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Tappable(
            onTap: onSubtitleTap,
            child: subText!,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                color: AppColors.textPrimary)),
        if (subText != null) ...[
          const SizedBox(height: 6),
          if (onSubtitleTap != null)
            Tappable(
              onTap: onSubtitleTap,
              child: subText,
            )
          else
            subText,
        ],
        const SizedBox(height: 28),
      ],
    );
  }
}

/// Compact coin balance pill displaying user avatar, balance, and 'cc'.
class CoinBalancePill extends StatelessWidget {
  final String alias;
  final String balance;
  final VoidCallback? onTap;

  const CoinBalancePill({
    super.key,
    required this.alias,
    required this.balance,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarCircle(
            name: alias,
            size: 24,
            background: AppColors.warning,
            foreground: Colors.white,
          ),
          const SizedBox(width: 8),
          Text(
            balance,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.warningInk,
            ),
          ),
          const SizedBox(width: 3),
          const Text(
            'cc',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.warningInk,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: pill,
    );
  }
}

/// Which subclass an activity row belongs to (docs/personal-time-plan.md §4).
///
/// `category` is 'care' (work for the family, whose kinds `type` describes) or
/// 'self' (personal time, whose own types are sport, social, rest, appointment
/// and other). Rows written before the subclasses existed carry no `category`
/// at all, so anything not explicitly 'self' is care work.
bool isSelfActivity(Map<String, dynamic> item) => item['category'] == 'self';

/// ── AssigneeBadge ──────────────────────────────────────────────────
/// "Who's doing this" pill for activity chips/cards, so simultaneous
/// activities from different caregivers are tellable apart. Shows "You"
/// (accented) for the viewer's own activities, the assignee's alias
/// otherwise; hides itself when there is no one to show.
class AssigneeBadge extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool compact;

  const AssigneeBadge({super.key, required this.item, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final mine = item['assigned_to']?.toString() == app.userId?.toString();
    final name = (item['assigned_alias'] ?? item['assigned_to_name'] ?? '')
        .toString()
        .trim();
    if (!mine && name.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 10, vertical: compact ? 2 : 4),
      constraints: BoxConstraints(maxWidth: compact ? 110 : 160),
      decoration: BoxDecoration(
        color: mine ? AppColors.primarySoft : AppColors.bg,
        border:
            Border.all(color: mine ? AppColors.primary : AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        mine ? AppLocalizations.of(context).assigneeYou : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: mine ? AppColors.primaryInk : AppColors.textSecondary,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/push_service.dart';
import '../services/telemetry.dart';
import '../services/tour_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/help_sheet.dart';
import '../widgets/ui.dart';
import 'activities_screen.dart';
import 'dashboard_screen.dart';
import 'marketplace_screen.dart';
import 'profile_screen.dart';
import 'stats_screen.dart';

/// App shell: pill header (logo, desktop nav, coin counter, avatar menu)
/// plus the mobile bottom tab bar with the same five tabs.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  // Lazy tab construction: a tab's screen (and its API calls) is only built
  // on first visit instead of firing ~10 requests at startup.
  final Set<int> _visited = {0};
  late final AppLifecycleListener _lifecycle;
  bool _welcomeChecked = false;

  @override
  void initState() {
    super.initState();
    // Refresh /api/me when the app comes back to the foreground.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (mounted) context.read<AppState>().fetchUserData();
      },
    );
    // Silent FCM re-registration when permission was already granted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PushService.init(context.read<AppState>());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Navigate to a tab, marking it visited so it gets built.
  void _go(int i) => setState(() {
        _index = i;
        _visited.add(i);
      });

  /// One-time welcome after the user first lands in the shell with a
  /// family (docs/onboarding-help-plan.md Phase 2). Frames the economy in
  /// one sentence, then either starts the guided tour or opts out of it.
  Future<void> _maybeShowWelcome() async {
    if (await TourService.I.hasSeen(TourService.welcome)) return;
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(l.welcomeTitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(l.welcomeBody,
            style: const TextStyle(
                height: 1.55, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'solo'),
              child: Text(l.welcomeExplore)),
          VButton(
              onPressed: () => Navigator.pop(ctx, 'tour'),
              child: Text(l.welcomeTour)),
        ],
      ),
    );
    Telemetry.log(
        'welcome_choice', {'choice': choice == 'solo' ? 'explore' : 'tour'});
    if (choice == 'solo') {
      await TourService.I.suppressAll();
    } else {
      // Welcome decided: notify so the visible tab starts its tour.
      await TourService.I.markSeen(TourService.welcome, notify: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);
    final l = AppLocalizations.of(context);
    final tabs = <({IconData icon, String label})>[
      (icon: Icons.home_rounded, label: l.tabFamily),
      (icon: Icons.calendar_today_rounded, label: l.tabActivities),
      (icon: Icons.shopping_bag_rounded, label: l.tabRewards),
      (icon: Icons.bar_chart_rounded, label: l.tabStats),
      (icon: Icons.person_rounded, label: l.tabMe),
    ];

    // Trigger the welcome check once the user actually has a family (the
    // onboarding wizard runs before this for brand-new users).
    final hasFamilies = context.watch<AppState>().hasFamilies;
    if (hasFamilies && !_welcomeChecked) {
      _welcomeChecked = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeShowWelcome());
    }

    // `active` tells a screen it just became the visible tab so it can
    // silently refetch — without it, tabs go stale (IndexedStack keeps
    // them alive but initState never runs again).
    final screens = [
      DashboardScreen(
          active: _index == 0,
          onOpenStats: () => _go(3),
          onOpenActivities: () => _go(1),
          onOpenMarketplace: () => _go(2)),
      ActivitiesScreen(active: _index == 1),
      MarketplaceScreen(active: _index == 2),
      StatsScreen(active: _index == 3),
      ProfileScreen(active: _index == 4),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _PillHeader(
              wide: wide,
              index: _index,
              onNavigate: _go,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1140),
                  child: IndexedStack(
                    index: _index,
                    children: [
                      for (var i = 0; i < screens.length; i++)
                        if (_visited.contains(i))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: screens[i],
                          )
                        else
                          const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 60,
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        Expanded(
                          child: InkWell(
                            onTap: () => _go(i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(tabs[i].icon,
                                    size: 22,
                                    color: i == _index
                                        ? AppColors.primary
                                        : AppColors.textSecondary),
                                const SizedBox(height: 2),
                                Text(tabs[i].label,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: i == _index
                                            ? AppColors.primary
                                            : AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _PillHeader extends StatelessWidget {
  final bool wide;
  final int index;
  final ValueChanged<int> onNavigate;

  const _PillHeader(
      {required this.wide, required this.index, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = AppLocalizations.of(context);
    final family = app.family;
    final alias =
        (family?['alias'] ?? app.profile?['display_name'] ?? 'C').toString();
    final balance = family?['coin_balance']?.toString() ?? '0';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      constraints: const BoxConstraints(maxWidth: 1140),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A0E1726), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          // Logo
          InkWell(
            onTap: () => onNavigate(0),
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: Row(
              children: [
                // Logo mark: primary square with the same
                // coin mark the PWA/launcher icons use (icon-mark.svg).
                Container(
                  width: wide ? 32 : 24,
                  height: wide ? 32 : 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadii.sm)),
                  child: Image.asset('assets/icon/icon-512.png',
                      width: 18,
                      height: 18,
                      cacheWidth:
                          (18 * MediaQuery.devicePixelRatioOf(context))
                              .round()),
                ),
                const SizedBox(width: 8),
                const Text('CareCoins',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ),
          const Spacer(),
          if (wide && app.hasFamilies) ...[
            _NavLink(
                label: l.tabFamily,
                icon: Icons.home_rounded,
                active: index == 0,
                onTap: () => onNavigate(0)),
            _NavLink(
                label: l.tabActivities,
                icon: Icons.calendar_today_rounded,
                active: index == 1,
                onTap: () => onNavigate(1)),
            _NavLink(
                label: l.navMarketplace,
                icon: Icons.shopping_bag_rounded,
                active: index == 2,
                onTap: () => onNavigate(2)),
            _NavLink(
                label: l.navPersonal,
                icon: Icons.person_rounded,
                active: index == 4,
                onTap: () => onNavigate(4)),
            const Spacer(),
          ],
          IconButton(
            onPressed: () => showHelpSheet(context),
            tooltip: l.helpTooltip,
            icon: const Icon(Icons.help_outline_rounded,
                size: 22, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 2),
          // Coin counter
          if (app.hasFamilies)
            InkWell(
              onTap: () => onNavigate(4),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Row(
                  children: [
                    AvatarCircle(
                        name: alias,
                        size: 24,
                        background: AppColors.warning,
                        foreground: Colors.white),
                    const SizedBox(width: 8),
                    Text(balance,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.warningInk)),
                    const SizedBox(width: 3),
                    const Text('cc',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warningInk)),
                  ],
                ),
              ),
            ),
          if (wide) ...[
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              tooltip: l.userMenuTooltip,
              offset: const Offset(0, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md)),
              onSelected: (v) {
                if (v == 'logout') app.logout();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'logout', child: Text(l.menuLogout)),
              ],
              child: AvatarCircle(
                  name: (app.profile?['display_name'] ?? app.user?.email ?? '?')
                      .toString(),
                  imageUrl: app.profile?['avatar_url']?.toString(),
                  size: 34),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _NavLink(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: active ? AppColors.primaryInk : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? AppColors.primaryInk
                          : AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

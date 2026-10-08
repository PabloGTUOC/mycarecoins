import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
import 'daily_screen.dart';
import 'dashboard_screen.dart';
import 'marketplace_screen.dart';
import 'profile_screen.dart';
import 'stats_screen.dart';

/// App shell: pill header (logo, desktop nav, coin counter, avatar menu)
/// plus the mobile bottom tab bar with the same five tabs.
class Shell extends StatefulWidget {
  final int initialIndex;
  const Shell({super.key, this.initialIndex = 0});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late int _index;
  // Lazy tab construction: a tab's screen (and its API calls) is only built
  // on first visit instead of firing ~10 requests at startup.
  late final Set<int> _visited;
  late final AppLifecycleListener _lifecycle;
  bool _welcomeChecked = false;
  String _dailyDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  bool _hasNeedsYou = false;
  bool _needsAttention = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _visited = {widget.initialIndex, 0};
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

  int _profileTab = 0;

  void _openWallet() {
    setState(() {
      _profileTab = 2;
      _index = 4;
      _visited.add(4);
    });
  }

  /// Navigate to a tab, marking it visited so it gets built.
  void _go(int i) => setState(() {
        _index = i;
        _visited.add(i);
        if (i == 0) {
          _needsAttention = false;
        }
        if (i == 4) {
          _profileTab = 0;
        }
      });

  void _openDailyTab(DateTime day) {
    setState(() {
      _dailyDate = DateFormat('yyyy-MM-dd').format(day);
      _index = 0;
      _visited.add(0);
      _needsAttention = false;
    });
  }

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
      (icon: Icons.today_rounded, label: l.tabToday),
      (icon: Icons.home_rounded, label: l.tabFamily),
      (icon: Icons.checklist_rounded, label: l.tabTasks),
      (icon: Icons.shopping_bag_rounded, label: l.tabRewards),
      (icon: Icons.person_rounded, label: l.tabMe),
    ];

    // Trigger the welcome check once the user actually has a family (the
    // onboarding wizard runs before this for brand-new users).
    final app = context.watch<AppState>();
    final hasFamilies = app.hasFamilies;
    final family = app.family;
    final alias =
        (family?['alias'] ?? app.profile?['display_name'] ?? 'C').toString();
    final balance = family?['coin_balance']?.toString() ?? '0';

    if (hasFamilies && !_welcomeChecked) {
      _welcomeChecked = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeShowWelcome());
    }

    // `active` tells a screen it just became the visible tab so it can
    // silently refetch — without it, tabs go stale (IndexedStack keeps
    // them alive but initState never runs again).
    final screens = [
      DailyScreen(
        date: _dailyDate,
        isTab: true,
        active: _index == 0,
        onOpenWallet: _openWallet,
        onNeedsYouChanged: (hasItems) {
          if (_hasNeedsYou != hasItems) {
            setState(() {
              _hasNeedsYou = hasItems;
              if (hasItems && _index != 0) {
                _needsAttention = true;
              } else if (!hasItems) {
                _needsAttention = false;
              }
            });
          }
        },
      ),
      DashboardScreen(
        active: _index == 1,
        onOpenDaily: _openDailyTab,
        onOpenStats: () => Navigator.of(context).push(statsRoute()),
        onOpenActivities: () => _go(2),
        onOpenMarketplace: () => _go(3),
      ),
      ActivitiesScreen(active: _index == 2),
      MarketplaceScreen(active: _index == 3),
      ProfileScreen(active: _index == 4, initialTab: _profileTab),
    ];

    final showDot = _hasNeedsYou && _needsAttention;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: wide || _index == 0
          ? null
          : AppBar(
              title: Text(tabs[_index].label),
              actions: [
                IconButton(
                  onPressed: () => showHelpSheet(context),
                  tooltip: l.helpTooltip,
                  icon: const Icon(Icons.help_outline_rounded,
                      size: 22, color: AppColors.textSecondary),
                ),
                if (hasFamilies) ...[
                  CoinBalancePill(
                    alias: alias,
                    balance: balance,
                    onTap: _openWallet,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
      body: SafeArea(
        bottom: false,
        top: wide,
        child: Column(
          children: [
            if (wide)
              _PillHeader(
                wide: wide,
                index: _index,
                onNavigate: _go,
                onOpenWallet: _openWallet,
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
                            padding: EdgeInsets.symmetric(
                                horizontal: (i == 0 && !wide) ? 0 : 16),
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
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _go,
              destinations: [
                NavigationDestination(
                  icon: showDot
                      ? Semantics(
                          label: l.tabNeedsAttention,
                          // No label: Material draws the small dot (D2, never
                          // a count). isLabelVisible: false would hide it.
                          child: const Badge(
                            key: Key('today_tab_dot'),
                            child: Icon(Icons.today_rounded),
                          ),
                        )
                      : const Icon(Icons.today_rounded),
                  label: tabs[0].label,
                  tooltip: showDot
                      ? '${tabs[0].label}${l.tabNeedsAttention}'
                      : tabs[0].label,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.home_rounded),
                  label: tabs[1].label,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.checklist_rounded),
                  label: tabs[2].label,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.shopping_bag_rounded),
                  label: tabs[3].label,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_rounded),
                  label: tabs[4].label,
                ),
              ],
            ),
    );
  }
}

class _PillHeader extends StatelessWidget {
  final bool wide;
  final int index;
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenWallet;

  const _PillHeader(
      {required this.wide,
      required this.index,
      required this.onNavigate,
      required this.onOpenWallet});

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
                label: l.tabToday,
                icon: Icons.today_rounded,
                active: index == 0,
                onTap: () => onNavigate(0)),
            _NavLink(
                label: l.tabFamily,
                icon: Icons.home_rounded,
                active: index == 1,
                onTap: () => onNavigate(1)),
            _NavLink(
                label: l.tabTasks,
                icon: Icons.checklist_rounded,
                active: index == 2,
                onTap: () => onNavigate(2)),
            _NavLink(
                label: l.navMarketplace,
                icon: Icons.shopping_bag_rounded,
                active: index == 3,
                onTap: () => onNavigate(3)),
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
            CoinBalancePill(
              alias: alias,
              balance: balance,
              onTap: onOpenWallet,
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';
import 'app_store_screen.dart';
import 'families_screen.dart';
import 'not_an_operator_screen.dart';
import 'overview_screen.dart';
import 'plans_screen.dart';
import 'sign_in_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    switch (state.status) {
      case OperatorAuthStatus.signedOut:
        return const SignInScreen();
      case OperatorAuthStatus.checking:
        return Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  Strings.authLoading,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      case OperatorAuthStatus.notAnOperator:
        return const NotAnOperatorScreen();
      case OperatorAuthStatus.error:
        return Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 40,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      state.statusError ?? Strings.errGenericFallback,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(
                          onPressed: () => state.signOut(),
                          child: Text(Strings.signOut),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () => state.checkOperatorStatus(),
                          child: Text(Strings.retry),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      case OperatorAuthStatus.authorized:
        return _buildConsoleLayout(context, state);
    }
  }

  Widget _buildConsoleLayout(BuildContext context, AppState state) {
    final email = state.currentUser?.email ?? Strings.emptyDash;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            leading: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Strings.appTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Tooltip(
                          message: email,
                          child: Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      IconButton(
                        tooltip: Strings.signOut,
                        icon: const Icon(
                          Icons.logout_rounded,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => state.signOut(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.dashboard_outlined),
                selectedIcon: const Icon(Icons.dashboard_rounded),
                label: Text(Strings.navOverview),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.groups_outlined),
                selectedIcon: const Icon(Icons.groups_rounded),
                label: Text(Strings.navFamilies),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.inventory_2_outlined),
                selectedIcon: const Icon(Icons.inventory_2_rounded),
                label: Text(Strings.navPlans),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.store_outlined),
                selectedIcon: const Icon(Icons.store_rounded),
                label: Text(Strings.navAppStore),
              ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const minWidth = 1024.0;
                final contentWidth = constraints.maxWidth < minWidth
                    ? minWidth
                    : constraints.maxWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    height: constraints.maxHeight,
                    child: _selectedIndex == 0
                        ? const OverviewScreen()
                        : _selectedIndex == 1
                            ? const FamiliesScreen()
                            : _selectedIndex == 2
                                ? const PlansScreen()
                                : const AppStoreScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

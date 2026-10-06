import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/purchase_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Store display names are brands — intentionally not localized.
const _platformNames = {'app_store': 'App Store', 'play': 'Google Play'};

/// "MyCareCoins Pro" section of Account Settings (plan Phase 4).
///
/// Reads the family's plan from the BACKEND entitlements endpoint (the
/// single source of truth — a purchase by any caregiver on any platform
/// shows here for everyone). The paywall/customer-center/restore actions
/// are RevenueCat-native and only exist on iOS/Android; on web the section
/// hides itself.
class SubscriptionCard extends StatefulWidget {
  const SubscriptionCard({super.key});

  @override
  State<SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends State<SubscriptionCard> {
  Map<String, dynamic>? _ent;
  bool _loading = true;
  bool _busy = false;

  int get _familyId => context.read<AppState>().familyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!PurchaseService.supported || _familyId == 0) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data = await context
          .read<AppState>()
          .api
          .get('/api/families/$_familyId/entitlements');
      if (!mounted) return;
      setState(() {
        _ent = (data as Map).cast<String, dynamic>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _thisPlatform => Platform.isIOS ? 'app_store' : 'play';

  Future<void> _upgrade() async {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();

    // Double-purchase guard: only our backend can know the family is
    // already subscribed via the *other* store.
    final subscribedPlatform = _ent?['platform']?.toString();
    if (_ent?['subscribed'] == true &&
        subscribedPlatform != null &&
        subscribedPlatform != _thisPlatform) {
      app.setError(l.proOtherPlatform(
          _platformNames[subscribedPlatform] ?? subscribedPlatform));
      return;
    }

    setState(() => _busy = true);
    final purchased = await PurchaseService.presentPaywall(familyId: _familyId);
    if (purchased) {
      // The upgrade lands via the RevenueCat → backend webhook; give it a
      // few seconds before declaring victory.
      var confirmed = false;
      for (var i = 0; i < 5 && !confirmed; i++) {
        await Future.delayed(const Duration(seconds: 2));
        await _load();
        confirmed = _ent?['subscribed'] == true;
      }
      if (mounted) {
        app.setSuccess(confirmed ? l.proPurchaseSuccess : l.proSyncDelayed);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    setState(() => _busy = true);
    final restored = await PurchaseService.restorePurchases();
    await _load();
    if (mounted) {
      restored ? app.setSuccess(l.proRestoreDone) : app.setError(l.proRestoreNone);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PurchaseService.supported) return const SizedBox.shrink();
    final app = context.watch<AppState>();
    if (!app.hasFamilies) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final subscribed = _ent?['subscribed'] == true;
    final platform = _ent?['platform']?.toString();
    final periodEnd =
        DateTime.tryParse(_ent?['currentPeriodEnd']?.toString() ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l.proSectionTitle,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
            ),
            if (subscribed)
              PillBadge(
                  text: _ent?['planCode']?.toString() ?? 'pro',
                  color: AppColors.successInk,
                  background: AppColors.successSoft,
                  fontSize: 12),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else ...[
          Text(
            subscribed
                ? [
                    l.proActive,
                    if (platform != null)
                      l.proManagedVia(_platformNames[platform] ?? platform),
                    if (periodEnd != null)
                      l.proRenewsOn(DateFormat('d MMM yyyy',
                              Localizations.localeOf(context).toString())
                          .format(periodEnd.toLocal())),
                  ].join(' · ')
                : l.proFreePlan,
            style: const TextStyle(
                fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (!subscribed && app.isCaregiver)
                VButton(
                  disabled: _busy,
                  onPressed: _upgrade,
                  child: Text(l.proUpgradeBtn),
                ),
              if (subscribed)
                VButton(
                  type: VButtonType.outline,
                  disabled: _busy,
                  onPressed: PurchaseService.presentCustomerCenter,
                  child: Text(l.proManageBtn),
                ),
              VButton(
                type: VButtonType.secondary,
                disabled: _busy,
                onPressed: _restore,
                child: Text(l.proRestoreBtn),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

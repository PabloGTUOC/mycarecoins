import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/push_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/activity_title.dart';
import '../utils/avatar_upload.dart';
import '../utils/json.dart';
import '../services/tour_service.dart';
import 'admin_screen.dart';
import 'stats_screen.dart';
import '../widgets/coach_marks.dart';
import '../widgets/family_circle.dart';
import '../widgets/help_sheet.dart';
import '../widgets/subscription_card.dart';
import '../utils/legal_links.dart';
import '../widgets/ui.dart';

/// Native display name per shipped language code (each shown in its own
/// language, so these are intentionally not localized). Add a new entry when
/// adding an app_*.arb; the language picker falls back to the raw code.
const kLanguageNativeNames = {
  'en': 'English',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
};

/// Personal Area: identity line, deletion-request banner,
/// account settings (name/email/alias, notification prefs, delete account),
/// Family Circle with delete-family, and the wallet panel with humanised
/// ledger and un-check revert. Mobile is one scrolling page with Wallet,
/// Family, and You sections.
class ProfileScreen extends StatefulWidget {
  /// Whether this is the visible tab; becoming active triggers a refetch.
  final bool active;
  final int initialTab;

  const ProfileScreen({super.key, this.active = true, this.initialTab = 0});

  /// Human-readable label for a ledger row.
  static String ledgerLabel(AppLocalizations l, Map<String, dynamic> item) =>
      _WalletPanel.ledgerLabel(l, item);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _deletionRequests = [];
  DateTime _month = DateTime.now();
  bool _showFullLedger = false;

  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _alias = TextEditingController();

  // Single source of truth for notification preferences: this list drives
  // loading, saving and rendering, so a new pref only has to be added here
  // (plus its label in _notifPrefLabel).
  static const _notifPrefKeys = [
    'activity_assigned',
    'activity_validated',
    'activity_completed',
    'bounty_offered',
    'family_events',
    'coverage_requests',
  ];

  String _notifPrefLabel(AppLocalizations l, String key) => switch (key) {
        'activity_assigned' => l.notifActivityAssigned,
        'activity_validated' => l.notifActivityValidated,
        'activity_completed' => l.notifActivityCompleted,
        'bounty_offered' => l.notifBountyOffered,
        'family_events' => l.notifFamilyEvents,
        'coverage_requests' => l.notifCoverageRequests,
        _ => key,
      };
  Map<String, bool> _notifPrefs = {};
  bool _notifGranted = false;

  final _tourWalletKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _maybeScrollToWallet();
    final app = context.read<AppState>();
    _displayName.text = app.profile?['display_name']?.toString() ?? '';
    _email.text = app.profile?['email']?.toString() ?? '';
    _alias.text = app.family?['alias']?.toString() ?? '';
    TourService.I.addListener(_maybeTour);
    _loadLedger();
    _loadDeletionRequests();
    _checkNotifPermission();
    _maybeTour();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen old) {
    super.didUpdateWidget(old);
    // Only when the coin pill opens Me, not on every rebuild while the
    // shell still passes 2, or scrolling Me would keep jumping to the top.
    if (widget.initialTab != old.initialTab ||
        (widget.active && !old.active)) {
      _maybeScrollToWallet();
    }
    if (widget.active && !old.active) {
      _loadLedger();
      _loadDeletionRequests();
      _maybeTour();
    }
  }

  void _maybeScrollToWallet() {
    if (widget.initialTab == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  void _maybeTour() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) return;
      final l = AppLocalizations.of(context);
      maybeShowTour(context, 'profile', [
        CoachMark(
          targetKey: _tourWalletKey,
          title: l.tourWalletTitle,
          body: l.tourWalletBody,
        ),
      ]);
    });
  }

  Future<void> _checkNotifPermission() async {
    final granted = await PushService.granted;
    if (mounted) setState(() => _notifGranted = granted);
    if (granted) await _loadNotifPrefs();
  }

  Future<void> _enableNotifications() async {
    final app = context.read<AppState>();
    final ok = await PushService.enable(app);
    if (!mounted) return;
    setState(() => _notifGranted = ok);
    if (ok) {
      app.setSuccess(AppLocalizations.of(context).toastNotificationsEnabled);
      await _loadNotifPrefs();
    }
  }

  Future<void> _disableNotifications() async {
    await PushService.disable(context.read<AppState>());
    if (mounted) setState(() => _notifGranted = false);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    TourService.I.removeListener(_maybeTour);
    _displayName.dispose();
    _email.dispose();
    _alias.dispose();
    super.dispose();
  }

  Future<void> _loadLedger() async {
    final app = context.read<AppState>();
    if (app.familyId == 0) return;
    try {
      final month = DateFormat('yyyy-MM').format(_month);
      final data = await app.api
          .get('/api/me/ledger?familyId=${app.familyId}&month=$month');
      final list = data is List ? data : (data['ledger'] as List? ?? []);
      if (mounted) {
        setState(() => _ledger =
            list.cast<Map>().map((m) => m.cast<String, dynamic>()).toList());
      }
    } catch (_) {}
  }

  Future<void> _loadDeletionRequests() async {
    final app = context.read<AppState>();
    if (app.familyId == 0 || !app.isCaregiver) return;
    try {
      final data = await app.api
          .get('/api/families/${app.familyId}/deletion-requests');
      final list = (data['deletionRequests'] as List?) ?? [];
      if (mounted) {
        setState(() => _deletionRequests =
            list.cast<Map>().map((m) => m.cast<String, dynamic>()).toList());
      }
    } catch (_) {}
  }

  Future<void> _loadNotifPrefs() async {
    final app = context.read<AppState>();
    try {
      final data = await app.api.get('/api/me/notification-preferences');
      if (mounted && data is Map) {
        setState(() => _notifPrefs = {
              for (final key in _notifPrefKeys) key: data[key] != false,
            });
      }
    } catch (_) {}
  }

  Future<void> _saveNotifPrefs() async {
    final app = context.read<AppState>();
    try {
      await app.api.put('/api/me/notification-preferences', _notifPrefs);
    } catch (_) {
      if (mounted) {
        app.setError(AppLocalizations.of(context).errSaveNotifPrefs);
      }
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _loadLedger();
  }

  Future<bool> _confirm(String title, String body,
      {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx).cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(ctx).confirm,
                  style: TextStyle(
                      color: danger ? AppColors.danger : AppColors.primary))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _updateProfile() async {
    final app = context.read<AppState>();
    await app.runAction(() async {
      await app.api.patch('/api/me/profile', {
        'displayName': _displayName.text.trim(),
        'email': _email.text.trim(),
        if (app.familyId != 0) 'familyId': app.familyId,
        if (app.familyId != 0) 'alias': _alias.text.trim(),
      });
      await app.fetchUserData();
    }, AppLocalizations.of(context).toastProfileUpdated);
  }

  Future<void> _deleteAccount() async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final ok =
        await _confirm(l.deleteAccountTitle, l.deleteAccountBody, danger: true);
    if (!ok) return;
    await app.runAction(() async {
      await app.api.delete('/api/me');
      await app.logout();
    }, l.toastAccountDeleted);
  }

  Future<void> _deleteFamily() async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final ok =
        await _confirm(l.deleteFamilyTitle, l.deleteFamilyBody, danger: true);
    if (!ok) return;
    await app.runAction(() async {
      final res = await app.api.delete('/api/families/${app.familyId}');
      if (res is Map && res['deleted'] == true) {
        await app.fetchUserData();
      } else if (res is Map && res['pendingApproval'] == true) {
        app.setSuccess(l.toastDeletionRequestSent);
        await _loadDeletionRequests();
      }
    });
  }

  Future<void> _respondToDeletionRequest(dynamic reqId, String action) async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    await app.runAction(() async {
      final res = await app.api.post(
          '/api/families/${app.familyId}/deletion-requests/$reqId/$action');
      if (res is Map && res['deleted'] == true) {
        await app.fetchUserData();
      } else {
        await _loadDeletionRequests();
      }
    }, action == 'approve' ? l.toastDeletionApproved : l.toastDeletionRejected);
  }

  Future<void> _uncheckActivity(Map<String, dynamic> item) async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final actTitle = displayTitle(l, item);
    final ok = await _confirm(
        l.uncheckTitle,
        l.uncheckBody(
            '${toNum(item['amount']).abs()}',
            actTitle.isNotEmpty ? actTitle : l.fallbackThisActivity));
    if (!ok) return;
    await app.runAction(() async {
      await app.api.post('/api/activities/${item['activity_id']}/revert');
      await app.fetchUserData();
      await _loadLedger();
    }, l.toastUnchecked);
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = AppLocalizations.of(context);
    final family = app.family;
    final wide = isWideLayout(context);

    final wallet = _WalletPanel(
      key: _tourWalletKey,
      balance: toNum(family?['coin_balance']),
      month: _month,
      ledger: _ledger,
      showFullLedger: _showFullLedger,
      onToggleLedger: () =>
          setState(() => _showFullLedger = !_showFullLedger),
      onPrevMonth: () => _changeMonth(-1),
      onNextMonth: () => _changeMonth(1),
      onUncheck: _uncheckActivity,
    );

    final account = _buildAccountCard(app, family);

    final familySection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FamilyCircle(),
        if (app.isCaregiver && family != null) ...[
          const SizedBox(height: 16),
          VButton(
              type: VButtonType.danger,
              onPressed: _deleteFamily,
              child: Text(l.deleteFamilyBtn)),
        ],
      ],
    );

    return RefreshIndicator(
      onRefresh: () async {
        await app.fetchUserData();
        await _loadLedger();
        await _loadDeletionRequests();
      },
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 16, bottom: 40),
        children: [
          PageHeading(title: l.profileTitle, subtitle: l.profileSubtitle),

          // ── Deletion requests banner ──
          for (final req in _deletionRequests)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                border: Border.all(color: AppColors.danger),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.deletionBannerTitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.dangerInk)),
                  const SizedBox(height: 8),
                  Text(
                      l.deletionBannerBody(
                          (req['requested_by_name'] ?? l.fallbackACaregiver)
                              .toString()),
                      style: const TextStyle(fontSize: 13.5)),
                  const SizedBox(height: 8),
                  for (final a in ((req['approvals'] as List?) ?? [])
                      .cast<Map>()
                      .map((m) => m.cast<String, dynamic>()))
                    Text(
                        '${a['caregiver_name']}: ${(a['status'] ?? '').toString().toUpperCase()}',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: a['status'] == 'approved'
                                ? AppColors.success
                                : a['status'] == 'rejected'
                                    ? AppColors.dangerInk
                                    : AppColors.warning)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      VButton(
                          type: VButtonType.danger,
                          onPressed: () =>
                              _respondToDeletionRequest(req['id'], 'approve'),
                          child: Text(l.approveDeletion)),
                      const SizedBox(width: 10),
                      VButton(
                          type: VButtonType.outline,
                          onPressed: () =>
                              _respondToDeletionRequest(req['id'], 'reject'),
                          child: Text(l.reject)),
                    ],
                  ),
                ],
              ),
            ),

          if (family != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l.meIdentityLine(
                  (family['name'] ??
                          family['family_name'] ??
                          l.fallbackMyFamily)
                      .toString(),
                  (family['alias'] ??
                          app.profile?['display_name'] ??
                          l.fallbackMember)
                      .toString(),
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ),

          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(children: [
                    account,
                    const SizedBox(height: 24),
                    familySection,
                  ]),
                ),
                const SizedBox(width: 24),
                Expanded(child: wallet),
              ],
            )
          else ...[
            _sectionTitle(l.tabWallet),
            wallet,
            _sectionTitle(l.tabFamily),
            familySection,
            _sectionTitle(l.sectionYou),
            account,
          ],
        ],
      ),
    );
  }

  Widget _buildAccountCard(AppState app, Map<String, dynamic>? family) {
    final l = AppLocalizations.of(context);
    return VCard(
      title: l.accountSettings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Tooltip(
                message: l.tapChangePhoto,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () async {
                    final ok = await pickAndUploadAvatar(
                        context, '/api/me/avatar',
                        successMessage: l.toastAvatarUpdated);
                    if (ok && context.mounted) {
                      await context.read<AppState>().fetchUserData();
                    }
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AvatarCircle(
                          name: (app.profile?['display_name'] ??
                                  app.user?.email ??
                                  '?')
                              .toString(),
                          imageUrl: app.profile?['avatar_url']?.toString(),
                          size: 56),
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                              color: AppColors.indigo,
                              shape: BoxShape.circle),
                          child: const Text('📷',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        (app.profile?['display_name'] ?? l.fallbackYourName)
                            .toString(),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text((app.profile?['email'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary)),
                    if (family?['role'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: PillBadge(
                            text: family!['role']
                                .toString()
                                .replaceAll('_', ' ')
                                .toUpperCase(),
                            fontSize: 12,
                            color: AppColors.indigo,
                            background: AppColors.primarySoft),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          VInput(
              controller: _displayName,
              label: l.fullNameLabel,
              placeholder: l.fallbackYourName),
          const SizedBox(height: 12),
          VInput(
              controller: _email,
              label: l.emailLabel,
              placeholder: 'your@email.com',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email]),
          if (family != null) ...[
            const SizedBox(height: 12),
            VInput(
                controller: _alias,
                label: l.aliasLabel,
                placeholder: l.aliasHint),
          ],
          const SizedBox(height: 16),
          VButton(
            onPressed: _updateProfile,
            block: true,
            child: Text(l.updateProfileBtn),
          ),
          const Divider(height: 32),
          Text(l.pushNotifications,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          if (!_notifGranted)
            VButton(
                type: VButtonType.outline,
                onPressed: _enableNotifications,
                child: Text(l.enableNotifications))
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(l.notificationsEnabled,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success)),
                ),
                TextButton(
                    onPressed: _disableNotifications,
                    child: Text(l.disableBtn,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            decoration: TextDecoration.underline))),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (final key in _notifPrefKeys)
                    SwitchListTile(
                      dense: true,
                      activeThumbColor: AppColors.primary,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      title: Text(_notifPrefLabel(l, key),
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                      value: _notifPrefs[key] ?? true,
                      onChanged: (v) {
                        setState(() => _notifPrefs[key] = v);
                        _saveNotifPrefs();
                      },
                    ),
                ],
              ),
            ),
          ],
          const Divider(height: 32),
          // MyCareCoins Pro (docs/admin-family-management-plan.md Phase 4).
          // Rendered only when store purchases are available on this platform.
          if (SubscriptionCard.isAvailable(app)) ...[
            const SubscriptionCard(),
            const Divider(height: 32),
          ],
          // Directly under the subscription entry point on purpose: Apple
          // requires the privacy policy and terms to be reachable in-app when
          // the app sells subscriptions, and expects them near the purchase.
          // Shown on web too, where the card above hides itself.
          const LegalLinks(),
          const Divider(height: 32),
          // Language picker (docs/i18n-plan.md §2). Language names stay in
          // their own language on purpose; only "system" is translated.
          Text(AppLocalizations.of(context).languageTitle,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.bg,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                // Clamp to a known item: a stale/unsupported stored code must
                // fall back to "system" rather than trip DropdownButton's
                // "exactly one item with [value]" assertion.
                value: AppState.supportedLanguageCodes
                        .contains(app.locale?.languageCode)
                    ? app.locale!.languageCode
                    : 'system',
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                items: [
                  DropdownMenuItem(
                      value: 'system',
                      child: Text(AppLocalizations.of(context).languageSystem)),
                  // Built from the shipped locales so a new app_*.arb surfaces
                  // in the picker automatically (just add its native name).
                  for (final loc in AppLocalizations.supportedLocales)
                    DropdownMenuItem(
                        value: loc.languageCode,
                        child: Text(kLanguageNativeNames[loc.languageCode] ??
                            loc.languageCode)),
                ],
                onChanged: (v) => context.read<AppState>().setLocale(
                    v == null || v == 'system' ? null : Locale(v)),
              ),
            ),
          ),
          const Divider(height: 32),
          // Help entry (docs/onboarding-help-plan.md Phase 1): same sheet
          // as the header's ? button, for people who look in settings.
          Tappable(
            onTap: () => showHelpSheet(context),
            child: Row(
              children: [
                const Icon(Icons.help_outline_rounded,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l.helpEntry,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
          // Platform admin console (docs/admin-family-management-plan.md
          // Phase 5). UI gating only — every /api/admin call re-checks the
          // role server-side.
          if (app.isPlatformAdmin) ...[
            const Divider(height: 32),
            Tappable(
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminScreen())),
              child: Row(
                children: [
                  const Icon(Icons.admin_panel_settings_outlined,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l.adminEntry,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.textSecondary),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          VButton(
            type: VButtonType.outline,
            block: true,
            onPressed: () => app.logout(),
            child: Text(l.menuLogout),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _deleteAccount,
              child: Text(
                l.deleteAccountBtn,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wallet panel: dark balance widget with a
/// 3-row preview, expandable monthly ledger with humanised reasons and
/// un-check revert, plus the Activity Insights card.
class _WalletPanel extends StatelessWidget {
  final num balance;
  final DateTime month;
  final List<Map<String, dynamic>> ledger;
  final bool showFullLedger;
  final VoidCallback onToggleLedger;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<Map<String, dynamic>> onUncheck;

  const _WalletPanel({
    super.key,
    required this.balance,
    required this.month,
    required this.ledger,
    required this.showFullLedger,
    required this.onToggleLedger,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onUncheck,
  });

  /// Human-readable label for a ledger row.
  static String ledgerLabel(AppLocalizations l, Map<String, dynamic> item) {
    final rawTitle = (item['activity_title'] ?? item['title'])?.toString();
    final title = rawTitle != null && rawTitle.isNotEmpty
        ? displayTitle(l, item)
        : null;
    final reason = item['reason']?.toString();

    if (reason != null && reason.startsWith('Redeemed: ')) {
      final reward = reason.substring('Redeemed: '.length).trim();
      return l.ledgerRedeemed(reward);
    }

    switch (reason) {
      case 'activity_completed':
        return title ?? l.ledgerActivityCompleted;
      case 'activity_reverted':
        return title ?? l.ledgerActivityReverted;
      case 'bounty_escrow':
      case 'bounty_paid':
        return title != null ? l.ledgerPaidNotDoing(title) : l.ledgerBountyPaid;
      case 'bounty_earned':
        return title != null
            ? l.ledgerBountyEarnedT(title)
            : l.ledgerBountyEarned;
      case 'bounty_refunded':
        return title != null
            ? l.ledgerBountyRefundedT(title)
            : l.ledgerBountyRefunded;
      case 'bounty_reverted':
        return title != null
            ? l.ledgerBountyRevertedT(title)
            : l.ledgerBountyReverted;
      case 'coverage_earned':
        return title ?? l.ledgerCoverageEarned;
      case 'coverage_reverted':
      case 'coverage_sweetener_reverted':
        return title ?? l.ledgerCoverageReverted;
      case 'coverage_sweetener_paid':
        return l.ledgerSweetenerPaid;
      case 'coverage_sweetener_escrow':
        return l.ledgerSweetenerEscrow;
      case 'coverage_sweetener_refunded':
        return l.ledgerSweetenerRefunded;
      case 'monthly_distribution':
        return l.ledgerMonthlyDistribution;
      default:
        return title ?? l.ledgerMovement;
    }
  }

  /// Ledger row date: Today/Yesterday with HH:mm, else a short date.
  static String ledgerDate(AppLocalizations l, String loc, dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (days == 0) return l.todayAt(DateFormat('HH:mm').format(d));
    if (days == 1) return l.yesterdayAt(DateFormat('HH:mm').format(d));
    return DateFormat('MMM d, yyyy', loc).format(d);
  }

  static const _reversalReasons = {
    'activity_reverted',
    'bounty_reverted',
    'coverage_reverted',
    'coverage_sweetener_reverted',
  };

  /// Activities whose payout has been reverted. The ledger is append-only, so
  /// the original credit stays beside its reversal row.
  Set<dynamic> get _revertedActivityIds => {
        for (final i in ledger)
          if (_reversalReasons.contains(i['reason']) &&
              i['activity_id'] != null)
            i['activity_id'],
      };

  /// Struck through: a reversal row, or a credit that a reversal undid.
  static bool _isReverted(
          Map<String, dynamic> item, Set<dynamic> revertedIds) =>
      _reversalReasons.contains(item['reason']) ||
      (item['activity_id'] != null &&
          revertedIds.contains(item['activity_id']));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    final preview = ledger.take(3).toList();
    final revertedIds = _revertedActivityIds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Balance widget ──
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.yourBalance,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Text('${NumberFormat.decimalPattern(loc).format(balance)} cc',
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              if (preview.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(l.noActivityThisMonth,
                        style: const TextStyle(
                            fontSize: 13.5, color: AppColors.textSecondary)),
                  ),
                )
              else
                for (final (i, row) in preview.indexed)
                  // Plain rows with hairlines, not boxes inside the card.
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : const Border(
                              top: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ledgerLabel(l, row),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary
                                          .withValues(
                                              alpha: _isReverted(row, revertedIds)
                                                  ? 0.6
                                                  : 1),
                                      decoration: _isReverted(row, revertedIds)
                                          ? TextDecoration.lineThrough
                                          : null)),
                              Text(ledgerDate(l, loc, row['created_at']),
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        _AmountText(
                            amount: toNum(row['amount']),
                            suffix: ' cc',
                            dark: false),
                      ],
                    ),
                  ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onToggleLedger,
                  child: Text(showFullLedger ? l.hideLedger : l.viewFullLedger,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
              ),
            ],
          ),
        ),

        // ── Full ledger ──
        if (showFullLedger) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(l.monthlyLedger,
                          style:
                              const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                        onPressed: onPrevMonth,
                        tooltip: l.prevMonth,
                        icon: const Icon(Icons.chevron_left_rounded,
                            color: AppColors.textSecondary)),
                    Text(DateFormat('MMM yyyy', loc).format(month),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    IconButton(
                        onPressed: onNextMonth,
                        tooltip: l.nextMonth,
                        icon: const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 8),
                if (ledger.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l.ledgerEmpty,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: AppColors.textSecondary)),
                  )
                else
                  for (final row in ledger)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ledgerLabel(l, row),
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary
                                            .withValues(
                                                alpha: _isReverted(row, revertedIds)
                                                    ? 0.6
                                                    : 1),
                                        decoration: _isReverted(row, revertedIds)
                                            ? TextDecoration.lineThrough
                                            : null)),
                                Text(ledgerDate(l, loc, row['created_at']),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                                if (toNum(row['duration_minutes']) > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: PillBadge(
                                        text:
                                            '${row['duration_minutes']} min',
                                        fontSize: 12,
                                        color: AppColors.violet,
                                        background: AppColors.primarySoft),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _AmountText(
                                  amount: toNum(row['amount']),
                                  suffix: ' cc',
                                  dark: false),
                              if (row['reason'] == 'activity_completed' &&
                                  !revertedIds.contains(row['activity_id']))
                                TextButton(
                                  onPressed: () => onUncheck(row),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    minimumSize: const Size(0, 28),
                                  ),
                                  child: Text(l.uncheckBtn,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.danger)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],

        // ── Insights ──
        // ── See family stats ──
        Card(
          margin: const EdgeInsets.only(top: 16),
          child: ListTile(
            title: Text(l.seeFamilyStats,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            onTap: () => Navigator.of(context).push(statsRoute()),
          ),
        ),
      ],
    );
  }
}

class _AmountText extends StatelessWidget {
  final num amount;
  final String suffix;
  final bool dark;

  const _AmountText({required this.amount, this.suffix = '', this.dark = false});

  @override
  Widget build(BuildContext context) {
    final positive = amount > 0;
    final color = dark
        ? (positive ? const Color(0xFF34D399) : const Color(0xFFF87171))
        : (positive ? AppColors.success : AppColors.danger);
    return Text('${positive ? '+' : ''}$amount$suffix',
        style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: color));
  }
}

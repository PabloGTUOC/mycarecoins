import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/starter_packs.dart';
import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Onboarding: create-family wizard (details,
/// additional caretakers, objects of care), pending invitations with an
/// alias prompt, and join by invite link/token.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _CaretakerEntry {
  final name = TextEditingController();
  final email = TextEditingController();

  void dispose() {
    name.dispose();
    email.dispose();
  }
}

class _CareObjectEntry {
  final name = TextEditingController();
  String type = 'child';
  String careTime = 'full_time';

  void dispose() => name.dispose();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _familyName = TextEditingController();
  final _alias = TextEditingController();
  final _mainCaretakerName = TextEditingController();
  final _token = TextEditingController();
  final _tokenAlias = TextEditingController();
  final List<_CaretakerEntry> _caretakers = [_CaretakerEntry()];
  final List<_CareObjectEntry> _careObjects = [_CareObjectEntry()];
  List<dynamic> _invites = [];

  // ── Wizard state (docs/family-setup-questionnaire-plan.md Stage B) ──
  static const _stepCount = 4;
  int _step = 0;
  bool _submitting = false;

  /// Starter-task areas. Pre-checked from the dependents entered in step 3
  /// and re-derived whenever those change, so the questionnaire always
  /// reflects who the family actually cares for; manual edits survive as
  /// long as the dependents don't change.
  Set<StarterArea> _areas = {...kUniversalAreas};
  List<String> _derivedFromTypes = const [];

  /// Tasks unchecked in the preview, by [starterTaskKey].
  final Set<String> _excludedTasks = {};

  /// Q2: "start empty" skips seeding entirely (sends an empty list).
  bool _startEmpty = false;

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  List<String> get _dependentTypes => [
        for (final o in _careObjects)
          if (o.name.text.trim().isNotEmpty) o.type,
      ];

  /// Re-derives the pre-checked areas when the dependents changed since the
  /// last derivation. Called on entering the questionnaire step.
  void _syncAreasWithDependents() {
    final types = _dependentTypes;
    if (listEquals(types, _derivedFromTypes)) return;
    _derivedFromTypes = types;
    _areas = areasForDependents(types);
    _excludedTasks.clear();
  }

  List<(String, String)> _typeOptions(AppLocalizations l) => [
        ('child', l.typeChildPlain),
        ('elderly', l.typeElderlyPlain),
        ('pet', l.typePetPlain),
      ];
  List<(String, String)> _careTimeOptions(AppLocalizations l) => [
        ('full_time', l.careFullTime),
        ('part_time', l.carePartTime),
      ];

  @override
  void initState() {
    super.initState();
    _mainCaretakerName.text =
        context.read<AppState>().profile?['display_name']?.toString() ?? '';
    _loadInvites();
  }

  @override
  void dispose() {
    _familyName.dispose();
    _alias.dispose();
    _mainCaretakerName.dispose();
    _token.dispose();
    _tokenAlias.dispose();
    for (final c in _caretakers) {
      c.dispose();
    }
    for (final o in _careObjects) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInvites() async {
    try {
      final data = await context.read<AppState>().api.get('/api/me/invites');
      if (mounted) {
        setState(() =>
            _invites = data is List ? data : (data['invites'] as List? ?? []));
      }
    } catch (_) {}
  }

  /// Per-step validation. Returns null when the step may be left, or the
  /// message to show. Steps 3 and 4 have nothing mandatory.
  String? _validateStep(int step, AppLocalizations l) => switch (step) {
        0 => _familyName.text.trim().isEmpty ? l.errFamilyNameRequired : null,
        1 => _caretakers.any((c) =>
                c.email.text.trim().isNotEmpty &&
                !_emailRe.hasMatch(c.email.text.trim()))
            ? l.errInvalidCaregiverEmail
            : null,
        _ => null,
      };

  void _goToStep(int next) {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    if (next > _step) {
      final error = _validateStep(_step, l);
      if (error != null) {
        app.setError(error);
        return;
      }
    }
    setState(() {
      _step = next.clamp(0, _stepCount - 1);
      if (_step == 3) _syncAreasWithDependents();
    });
  }

  Future<void> _createFamily() async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    // Re-check every step: the button is only reachable from the last one,
    // but a validation gap earlier must not create a broken family.
    for (var step = 0; step < _stepCount; step++) {
      final error = _validateStep(step, l);
      if (error != null) {
        app.setError(error);
        setState(() => _step = step);
        return;
      }
    }

    // Seed the activity library in the user's language
    // (docs/family-setup-questionnaire-plan.md). An empty list is explicit:
    // it means "start empty", which the backend distinguishes from an
    // absent field (legacy English seeding).
    final starterTasks = _startEmpty
        ? const <Map<String, dynamic>>[]
        : starterTasksPayload(l, _areas, excluded: _excludedTasks);

    setState(() => _submitting = true);
    await app.runAction(() async {
      await app.api.post('/api/families', {
        'name': _familyName.text.trim(),
        'alias': _alias.text.trim().isEmpty ? null : _alias.text.trim(),
        'mainCaretakerName': _mainCaretakerName.text.trim(),
        'caretakers': [
          for (final c in _caretakers)
            if (c.email.text.trim().isNotEmpty)
              {'name': c.name.text.trim(), 'email': c.email.text.trim()},
        ],
        'objectsOfCare': [
          for (final o in _careObjects)
            if (o.name.text.trim().isNotEmpty)
              {
                'name': o.name.text.trim(),
                'type': o.type,
                'careTime': o.careTime,
              },
        ],
        'starterTasks': starterTasks,
      });
      await app.fetchUserData();
    }, l.toastFamilyCreated);
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _joinByToken() async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    // Accept a full invite link or a bare token (mirror of joinByToken).
    final match = RegExp(
            r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
            caseSensitive: false)
        .firstMatch(_token.text.trim());
    if (match == null) {
      app.setError(l.errNoValidToken);
      return;
    }
    await app.runAction(() async {
      await app.api.post('/api/families/join-by-token', {
        'token': match.group(0),
        if (_tokenAlias.text.trim().isNotEmpty)
          'alias': _tokenAlias.text.trim(),
      });
      await app.fetchUserData();
    }, l.toastJoinedFamily);
  }

  Future<void> _acceptInvite(Map invite) async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final aliasCtl = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(
            l.joinFamilyPrompt(
                (invite['family_name'] ?? l.fallbackFamily).toString()),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: VInput(
            controller: aliasCtl,
            label: l.aliasOptional,
            placeholder: l.aliasJoinHint),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.join)),
        ],
      ),
    );
    if (accepted != true) {
      aliasCtl.dispose();
      return;
    }
    await app.runAction(() async {
      await app.api.post('/api/families/join-request', {
        'familyId': invite['family_id'],
        if (aliasCtl.text.trim().isNotEmpty) 'alias': aliasCtl.text.trim(),
      });
      await app.fetchUserData();
    }, l.toastJoinedFamily);
    aliasCtl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wide = isWideLayout(context);
    final l = AppLocalizations.of(context);

    final createCard = _buildCreateWizard(app);

    final joinCard = VCard(
      title: l.joinTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.joinIntro,
              style: const TextStyle(
                  color: AppColors.textSecondary, height: 1.6)),
          const SizedBox(height: 20),
          VInput(
              controller: _token,
              label: l.inviteLinkOrToken,
              placeholder: l.inviteLinkHint),
          const SizedBox(height: 14),
          VInput(
              controller: _tokenAlias,
              label: l.aliasOptional,
              placeholder: l.aliasGrandmaHint),
          const SizedBox(height: 20),
          VButton(
              type: VButtonType.outline,
              onPressed: _joinByToken,
              block: true,
              child: Text(l.joinFamilyBtn)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  PageHeading(
                      title: l.onboardingTitle,
                      subtitle: l.onboardingSubtitle),
                  if (app.pendingRequests.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.warningSoft,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Text(
                        l.requestPending(
                            ((app.pendingRequests.first as Map)['name'] ??
                                    l.fallbackAFamily)
                                .toString()),
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (_invites.isNotEmpty)
                    VCard(
                      title: l.invitedToJoin,
                      child: Column(
                        children: [
                          for (final inv in _invites)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            ((inv as Map)['family_name'] ??
                                                    l.fallbackFamily)
                                                .toString(),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800)),
                                        Text(
                                            l.invitedBy((inv['inviter_name'] ??
                                                    l.fallbackAMember)
                                                .toString()),
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color:
                                                    AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  VButton(
                                      onPressed: () => _acceptInvite(inv),
                                      child: Text(l.accept)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: createCard),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: joinCard),
                      ],
                    )
                  else ...[createCard, joinCard],
                  Center(
                    child: TextButton(
                      onPressed: () => app.logout(),
                      child: Text(l.menuLogout,
                          style: const TextStyle(
                              color: AppColors.textSecondary)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateWizard(AppState app) {
    final l = AppLocalizations.of(context);
    final isLast = _step == _stepCount - 1;
    return VCard(
      title: l.setupFamilyTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WizardProgress(step: _step, total: _stepCount),
          const SizedBox(height: 18),
          switch (_step) {
            0 => _stepFamilyDetails(l),
            1 => _stepCaregivers(app, l),
            2 => _stepCareObjects(l),
            _ => _stepStarterTasks(l),
          },
          const SizedBox(height: 24),
          Row(
            children: [
              if (_step > 0) ...[
                VButton(
                    type: VButtonType.secondary,
                    disabled: _submitting,
                    onPressed: () => _goToStep(_step - 1),
                    child: Text(l.back)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: VButton(
                  block: true,
                  disabled: _submitting,
                  onPressed: isLast ? _createFamily : () => _goToStep(_step + 1),
                  child: Text(isLast ? l.completeSetup : l.next),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 1: family details ──
  Widget _stepFamilyDetails(AppLocalizations l) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepTitle(l.step1Title, l.step1Desc),
          VInput(
              controller: _familyName,
              label: l.familyNameLabel,
              placeholder: l.familyNameHint),
          const SizedBox(height: 12),
          VInput(
              controller: _alias,
              label: l.aliasRoleLabel,
              placeholder: l.aliasRoleHint),
        ],
      );

  // ── Step 2: caregivers ──
  Widget _stepCaregivers(AppState app, AppLocalizations l) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepTitle(l.step2Title, l.step2Desc),
          VInput(
              controller: _mainCaretakerName,
              label: l.yourDisplayName,
              placeholder: l.yourNameHint),
          const SizedBox(height: 6),
          Text((app.profile?['email'] ?? '').toString(),
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          for (final (i, c) in _caretakers.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Short placeholders: the long ones truncated to
                  // "Name (op…" / "caregiver…" on 390dp-wide screens.
                  Expanded(
                      child: VInput(
                          controller: c.name, placeholder: l.nameLabel)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: VInput(
                          controller: c.email,
                          placeholder: l.emailAddressHint,
                          keyboardType: TextInputType.emailAddress)),
                  IconButton(
                    onPressed: () => setState(() {
                      _caretakers.removeAt(i).dispose();
                    }),
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: AppColors.danger),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: VButton(
                type: VButtonType.outline,
                onPressed: () =>
                    setState(() => _caretakers.add(_CaretakerEntry())),
                child: Text(l.addAnotherCaregiver)),
          ),
        ],
      );

  // ── Step 3: objects of care ──
  Widget _stepCareObjects(AppLocalizations l) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepTitle(l.step3Title, l.step3Desc),
          for (final (i, o) in _careObjects.indexed)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: VInput(
                              controller: o.name,
                              placeholder: l.careObjectNameHint)),
                      IconButton(
                        onPressed: () => setState(() {
                          _careObjects.removeAt(i).dispose();
                        }),
                        icon: const Icon(Icons.close_rounded,
                            size: 20, color: AppColors.danger),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: o.type,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: [
                            for (final (v, label) in _typeOptions(l))
                              DropdownMenuItem(value: v, child: Text(label)),
                          ],
                          onChanged: (v) =>
                              setState(() => o.type = v ?? 'child'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        // isExpanded ellipsizes the long "Full Time (24
                        // coins/day)" label instead of colliding with the
                        // dropdown arrow on narrow screens.
                        child: DropdownButtonFormField<String>(
                          initialValue: o.careTime,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: [
                            for (final (v, label) in _careTimeOptions(l))
                              DropdownMenuItem(
                                  value: v,
                                  child: Text(label,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13))),
                          ],
                          onChanged: (v) =>
                              setState(() => o.careTime = v ?? 'full_time'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: VButton(
                type: VButtonType.outline,
                onPressed: () =>
                    setState(() => _careObjects.add(_CareObjectEntry())),
                child: Text(l.addSomeoneToCareFor)),
          ),
        ],
      );

  // ── Step 4: starter tasks questionnaire ──
  Widget _stepStarterTasks(AppLocalizations l) {
    final entries = starterEntries(_areas);
    final selectedCount =
        entries.where((e) => !_excludedTasks.contains(_keyOf(e))).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepTitle(l.step4Title, l.step4Desc),

        // Q2 — starting point. Asked first so "start empty" can hide the
        // rest instead of making people scroll past choices they don't want.
        _ChoiceRow(
          label: l.startWithTasks,
          description: l.startWithTasksDesc,
          selected: !_startEmpty,
          onTap: () => setState(() => _startEmpty = false),
        ),
        const SizedBox(height: 8),
        _ChoiceRow(
          label: l.startEmpty,
          description: l.startEmptyDesc,
          selected: _startEmpty,
          onTap: () => setState(() => _startEmpty = true),
        ),

        if (!_startEmpty) ...[
          const Divider(height: 32),
          // Q1 — activity areas, pre-checked from the dependents entered.
          Text(l.areasLabel,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final area in StarterArea.values)
                FilterChip(
                  label: Text(starterAreaLabel(l, area)),
                  avatar: Icon(_areaIcons[area], size: 18),
                  selected: _areas.contains(area),
                  showCheckmark: false,
                  selectedColor: AppColors.primarySoft,
                  onSelected: (on) => setState(() {
                    on ? _areas.add(area) : _areas.remove(area);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(l.starterPreviewTitle(selectedCount),
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l.starterPreviewEmpty,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Column(
                children: [
                  for (final entry in entries)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(entry.task.title(l),
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${entry.task.durationMinutes} min'
                          '${entry.task.isRecurrent ? ' · ${l.recurringLabel}' : ''}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      value: !_excludedTasks.contains(_keyOf(entry)),
                      onChanged: (on) => setState(() {
                        on == true
                            ? _excludedTasks.remove(_keyOf(entry))
                            : _excludedTasks.add(_keyOf(entry));
                      }),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _keyOf(StarterEntry e) => starterTaskKey(e.area, e.index);

  static const Map<StarterArea, IconData> _areaIcons = {
    StarterArea.meals: Icons.restaurant_rounded,
    StarterArea.cleaning: Icons.cleaning_services_rounded,
    StarterArea.errands: Icons.receipt_long_rounded,
    StarterArea.kidsRoutines: Icons.backpack_rounded,
    StarterArea.homework: Icons.menu_book_rounded,
    StarterArea.nightCare: Icons.bedtime_rounded,
    StarterArea.pets: Icons.pets_rounded,
    StarterArea.elderCare: Icons.medical_services_rounded,
  };
}

/// Progress dots + "Step x of y" for the create-family wizard.
class _WizardProgress extends StatelessWidget {
  final int step;
  final int total;
  const _WizardProgress({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4,
              decoration: BoxDecoration(
                color: i <= step ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 6),
        ],
        const SizedBox(width: 12),
        Text(l.stepIndicator(step + 1, total),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
      ],
    );
  }
}

/// Radio-style option row used by the "starting point" question.
class _ChoiceRow extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceRow({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.bg,
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          children: [
            Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  final String title;
  final String description;
  const _StepTitle(this.title, this.description);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(description,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/json.dart';
import 'ui.dart';

/// The self-activity types the API accepts, with the glyph the timeline uses.
const kPersonalTimeTypes = ['sport', 'social', 'rest', 'appointment', 'other'];

String personalTimeTypeLabel(AppLocalizations l, String type) => switch (type) {
      'sport' => l.ptTypeSport,
      'social' => l.ptTypeSocial,
      'rest' => l.ptTypeRest,
      'appointment' => l.ptTypeAppointment,
      _ => l.ptTypeOther,
    };

String personalTimeTypeGlyph(String type) => switch (type) {
      'sport' => '🏃',
      'social' => '👥',
      'rest' => '😴',
      'appointment' => '🩺',
      _ => '✨',
    };

/// The recurrences the API accepts, mirroring RECURRENCES in
/// personalTimeService.js; null is "just once".
const kPersonalTimeRepeats = <String?>[null, 'daily', 'weekdays', 'weekly'];

String personalTimeRepeatLabel(AppLocalizations l, String? r) => switch (r) {
      'daily' => l.personalTimeRepeatDaily,
      'weekdays' => l.personalTimeRepeatWeekdays,
      'weekly' => l.personalTimeRepeatWeekly,
      _ => l.personalTimeRepeatNever,
    };

const _durations = [30, 60, 90, 120, 180, 240, 480, 720];

String _durationLabel(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h$m';
}

/// "Book personal time" sheet, opened by double-tapping the hour grid.
///
/// Personal time always carries a coverage offer to another caretaker and is
/// only real once they accept, so this asks for the window *and* what the offer
/// is worth — the baseline comes from the family budget, and anything on top
/// comes out of the requester's own wallet. Returns true when a request was
/// created.
Future<bool> showPersonalTimeSheet(BuildContext context,
    {required DateTime start}) async {
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _PersonalTimeSheet(start: start),
    ),
  );
  return created == true;
}

class _PersonalTimeSheet extends StatefulWidget {
  final DateTime start;
  const _PersonalTimeSheet({required this.start});

  @override
  State<_PersonalTimeSheet> createState() => _PersonalTimeSheetState();
}

class _PersonalTimeSheetState extends State<_PersonalTimeSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();

  late DateTime _start = widget.start;
  String _type = 'sport';
  int _minutes = 60;
  bool _coverageNeeded = true;
  int _sweetener = 0;

  String? _recurrence;
  DateTime? _until;
  int? _requestedOf;

  bool _quoting = true;
  int _baseline = 0;
  int _balance = 0;
  String? _coverName;
  List<Map> _candidates = const [];
  int _occurrences = 1;
  List<String> _conflicts = const [];
  bool _submitting = false;

  /// Why the last attempt failed. This sheet is a modal bottom sheet and
  /// SnackBars render *underneath* it, so a refusal shown only as a toast is
  /// invisible — the sheet just sits there looking like a dead button.
  String? _error;

  DateTime get _end => _start.add(Duration(minutes: _minutes));

  /// What the whole ask costs the requester: the sweetener buys one favour per
  /// occurrence, and all of it is escrowed the moment they ask.
  int get _escrow => _sweetener * _occurrences;

  /// Sent as a plain date; the server owns the end-of-day boundary.
  String? get _untilIso => _until == null
      ? null
      : '${_until!.year.toString().padLeft(4, '0')}-'
          '${_until!.month.toString().padLeft(2, '0')}-'
          '${_until!.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _quote());
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Prices the window server-side, so the sheet never invents a number the
  /// API would disagree with.
  Future<void> _quote() async {
    if (!mounted) return;
    setState(() => _quoting = true);
    final app = context.read<AppState>();
    try {
      final q = await app.api.post('/api/personal-time/quote', {
        'familyId': app.familyId,
        'startsAt': _start.toUtc().toIso8601String(),
        'endsAt': _end.toUtc().toIso8601String(),
        'coverageNeeded': _coverageNeeded,
        'requestedOf': _requestedOf,
        'recurrence': _recurrence,
        'recurrenceUntil': _untilIso,
      });
      if (!mounted) return;
      setState(() {
        _baseline = toNum(q['baselineCoins']).toInt();
        _balance = toNum(q['yourBalance']).toInt();
        _occurrences = toNum(q['occurrences'] ?? 1).toInt();
        _conflicts = ((q['theirConflicts'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        _candidates = ((q['candidates'] as List?) ?? []).cast<Map>();
        // The server resolves an unnamed counterparty when there is only one
        // other caregiver, so read the answer back rather than assuming.
        final target = q['requestedOf'];
        _coverName = target == null
            ? null
            : _candidates
                .firstWhere((c) => c['user_id'].toString() == target.toString(),
                    orElse: () => {})['name']
                ?.toString();
        // A longer series can put the chosen sweetener out of reach.
        if (_occurrences > 0 && _escrow > _balance) {
          _sweetener = _balance ~/ _occurrences;
        }
        _quoting = false;
        _error = null;
      });
    } catch (e) {
      // Swallowing this left the sheet showing a price the server never
      // agreed to, with no hint anything had gone wrong.
      if (!mounted) return;
      setState(() {
        _quoting = false;
        _error = app.errorTextFor(e);
      });
    }
  }

  /// Choosing a repeat needs an end date, so one is offered rather than
  /// demanded: four weeks out, which the user can then move.
  Future<void> _setRecurrence(String? value) async {
    setState(() {
      _recurrence = value;
      _until = value == null
          ? null
          : (_until ?? DateTime(_start.year, _start.month, _start.day + 28));
      if (value == null) _occurrences = 1;
    });
    await _quote();
  }

  Future<void> _pickUntil() async {
    final first = DateTime(_start.year, _start.month, _start.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? first,
      firstDate: first,
      lastDate: DateTime(first.year + 1, first.month, first.day),
    );
    if (picked == null || !mounted) return;
    setState(() => _until = picked);
    await _quote();
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t == null || !mounted) return;
    setState(() => _start =
        DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
    await _quote();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    if (_title.text.trim().isEmpty) {
      setState(() => _error = l.errNameFirst);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await app.runAction(() async {
      await app.api.post('/api/personal-time', {
        'familyId': app.familyId,
        'title': _title.text.trim(),
        'type': _type,
        'description': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'startsAt': _start.toUtc().toIso8601String(),
        'endsAt': _end.toUtc().toIso8601String(),
        'coverageNeeded': _coverageNeeded,
        'sweetenerCoins': _coverageNeeded ? _sweetener : 0,
        'requestedOf': _requestedOf,
        'recurrence': _recurrence,
        'recurrenceUntil': _untilIso,
      });
    }, _coverageNeeded ? l.toastPersonalTimeAsked : l.toastPersonalTimeBooked);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      // runAction raises a toast that this sheet covers; mirror it here.
      _error = ok ? null : app.error;
    });
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    final total = _baseline + _sweetener;
    final who = _coverName ?? l.personalTimeAnyone;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.personalTimeSheetTitle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            VInput(
                controller: _title,
                label: l.fieldTitle,
                placeholder: l.personalTimeNameHint),
            const SizedBox(height: 14),
            _Label(l.personalTimeTypeLabel),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in kPersonalTimeTypes)
                  ChoiceChip(
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                    avatar: ActivityTypeIcon(
                      type: t,
                      category: 'self',
                      size: 20,
                      iconSize: 13,
                    ),
                    label: Text(personalTimeTypeLabel(l, t)),
                    labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _type == t
                            ? AppColors.primaryInk
                            : AppColors.textSecondary),
                    selectedColor: AppColors.primarySoft,
                    backgroundColor: AppColors.bg,
                    showCheckmark: false,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickStart,
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(
                        '${l.personalTimeStartLabel}: ${DateFormat('HH:mm').format(_start)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _minutes,
                    decoration: InputDecoration(
                      labelText: l.personalTimeDurationLabel,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: [
                      for (final m in _durations)
                        DropdownMenuItem(
                            value: m, child: Text(_durationLabel(m))),
                    ],
                    onChanged: (m) {
                      if (m == null) return;
                      setState(() => _minutes = m);
                      _quote();
                    },
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '${DateFormat('EEE d MMM', loc).format(_start)} · '
                  '${DateFormat('HH:mm').format(_start)}–${DateFormat('HH:mm').format(_end)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 14),
            _Label(l.personalTimeRepeatLabel),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in kPersonalTimeRepeats)
                  ChoiceChip(
                    selected: _recurrence == r,
                    onSelected: (_) => _setRecurrence(r),
                    label: Text(personalTimeRepeatLabel(l, r)),
                    labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _recurrence == r
                            ? AppColors.primaryInk
                            : AppColors.textSecondary),
                    selectedColor: AppColors.primarySoft,
                    backgroundColor: AppColors.bg,
                    showCheckmark: false,
                  ),
              ],
            ),
            if (_recurrence != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  onPressed: _pickUntil,
                  icon: const Icon(Icons.event_repeat_rounded, size: 18),
                  label: Text(l.personalTimeRepeatUntil(
                      DateFormat('d MMM y', loc).format(_until!))),
                ),
              ),
            const SizedBox(height: 8),
            VInput(
                controller: _note,
                label: l.personalTimeNoteLabel,
                placeholder: l.personalTimeNoteHint),
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              value: _coverageNeeded,
              onChanged: (v) {
                setState(() {
                  _coverageNeeded = v;
                  if (!v) _sweetener = 0;
                });
                _quote();
              },
              contentPadding: EdgeInsets.zero,
              title: Text(l.personalTimeCoverageLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: _coverageNeeded
                  ? null
                  : Text(l.personalTimeCoverageOff,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
            ),
            if (_coverageNeeded) ...[
              // With two caregivers there is nothing to pick — it is the other
              // one — so the picker only appears when it has a decision to make.
              if (_candidates.length > 1) ...[
                const SizedBox(height: 6),
                _Label(l.personalTimeWhoLabel),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in [null, ..._candidates])
                      ChoiceChip(
                        selected: _requestedOf ==
                            (c == null ? null : toNum(c['user_id']).toInt()),
                        onSelected: (_) {
                          setState(() => _requestedOf =
                              c == null ? null : toNum(c['user_id']).toInt());
                          _quote();
                        },
                        label: Text(c == null
                            ? l.personalTimeAnyone
                            : (c['name']?.toString() ?? '')),
                        labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _requestedOf ==
                                    (c == null
                                        ? null
                                        : toNum(c['user_id']).toInt())
                                ? AppColors.primaryInk
                                : AppColors.textSecondary),
                        selectedColor: AppColors.primarySoft,
                        backgroundColor: AppColors.bg,
                        showCheckmark: false,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 6),
              _Label(l.personalTimeSweetenerLabel),
              Row(
                children: [
                  _StepButton(
                      icon: Icons.remove_rounded,
                      tooltip: l.decrease,
                      onTap: _sweetener > 0
                          ? () => setState(() => _sweetener--)
                          : null),
                  Expanded(
                    child: Center(
                      child: Text('$_sweetener cc',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  _StepButton(
                      icon: Icons.add_rounded,
                      tooltip: l.increase,
                      onTap: (_sweetener + 1) * _occurrences <= _balance
                          ? () => setState(() => _sweetener++)
                          : null),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _quoting ? '…' : l.personalTimeQuote(who, total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary),
                    ),
                    if (!_quoting && _sweetener > 0)
                      Text(l.personalTimeQuoteExtra(_baseline, _sweetener),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.primary)),
                    if (!_quoting && _occurrences > 1)
                      Text(l.personalTimeSeriesCost(_occurrences, _escrow),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    if (!_quoting)
                      Text(l.personalTimeBalanceAfter(_balance - _escrow),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (_occurrences > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l.personalTimeSeriesNote,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
              if (_conflicts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l.personalTimeTheirConflict(_conflicts.first),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.warning)),
                ),
            ],
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: AppColors.dangerInk),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: AppColors.dangerInk)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: VButton(
                    type: VButtonType.outline,
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l.cancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: VButton(
                    disabled: _submitting,
                    onPressed: _submitting ? null : _submit,
                    child: Text(
                        _coverageNeeded ? l.personalTimeAsk : l.scheduleAction),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary)),
      );
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;
  const _StepButton({required this.icon, this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tip = tooltip ??
        (icon == Icons.remove_rounded ? l.decrease : l.increase);
    return IconButton(
      onPressed: onTap,
      tooltip: tip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md)),
      ),
    );
  }
}

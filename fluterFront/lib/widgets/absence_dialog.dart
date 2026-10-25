import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import 'ui.dart';

/// The half-open midnight-to-midnight window an inclusive picker range maps to.
///
/// Adding a [Duration] rather than incrementing the day field keeps the window
/// exactly 24 h of elapsed time per selected day even across a daylight-saving
/// change, which is what the API measures. A single-day range is therefore
/// always exactly the 24 h minimum, never a minute under it.
@visibleForTesting
({DateTime start, DateTime end}) absenceWindowFromRange(DateTimeRange range) => (
      start: DateUtils.dateOnly(range.start),
      end: DateUtils.dateOnly(range.end).add(const Duration(days: 1)),
    );

/// Shared "Log time off" dialog (Daily and Dashboard).
///
/// Time off means being away for a day or more — work travel, urgent family
/// matters (docs/personal-time-plan.md Phase 1). The window is therefore picked
/// as a **date range** and always runs midnight to midnight, so the shortest
/// thing this dialog can produce is exactly the 24 h the API requires.
/// Returns true when an absence was created.
Future<bool> showLogAbsenceDialog(BuildContext context,
    {required DateTime day}) async {
  final l = AppLocalizations.of(context);
  final loc = l.localeName;
  final title = TextEditingController();
  // The picker asserts that the initial range sits inside its bounds, and the
  // Daily view can be scrolled arbitrarily far, so clamp the anchor day.
  final firstDate = addCalendarDays(DateTime.now(), -365);
  final lastDate = addCalendarDays(DateTime.now(), 365);
  var anchor = DateUtils.dateOnly(day);
  if (anchor.isBefore(firstDate)) anchor = firstDate;
  if (anchor.isAfter(lastDate)) anchor = lastDate;
  // Inclusive range: start and end on the same day means "away that one day".
  var range = DateTimeRange(start: anchor, end: anchor);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final days = range.end.difference(range.start).inDays + 1;
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg)),
          title: Text(l.absenceDialogTitle,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VInput(
                  controller: title,
                  label: l.fieldTitle,
                  placeholder: l.absenceHint),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: ctx,
                    initialDateRange: range,
                    firstDate: firstDate,
                    lastDate: lastDate,
                  );
                  if (picked == null) return;
                  setLocal(() => range = picked);
                },
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  '${l.absenceDatesLabel}: '
                  '${DateFormat('d MMM', loc).format(range.start)}'
                  ' → ${DateFormat('d MMM', loc).format(range.end)}'
                  ' · ${l.absenceDaysCount(days)}',
                ),
              ),
              const SizedBox(height: 8),
              Text('${l.absenceWholeDaysNote}\n${l.absenceCostNote}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.cancel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.logAction)),
          ],
        );
      },
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final app = context.read<AppState>();
  if (title.text.trim().isEmpty) {
    app.setError(l.errFillAllFields);
    return false;
  }

  final window = absenceWindowFromRange(range);

  return app.runAction(() async {
    await app.api.post('/api/absences', {
      'familyId': app.familyId,
      'title': title.text.trim(),
      'startTime': window.start.toUtc().toIso8601String(),
      'endTime': window.end.toUtc().toIso8601String(),
    });
  }, l.toastTimeOffLogged);
}

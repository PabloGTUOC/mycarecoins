/**
 * Absence rules (docs/personal-time-plan.md Phase 1).
 *
 * An absence means "away for a day or more" — work travel, urgent family
 * matters. Shorter, discretionary time off is a different thing and does not
 * belong here, so the floor is enforced in two places: this rule, which the
 * route runs on every write, and the `absences_min_duration` constraint in
 * scripts/migrate-absence-floor.sql, which is NOT VALID so absences created
 * before the rule existed keep loading and deleting normally.
 */

export const MIN_ABSENCE_HOURS = 24;

const MIN_ABSENCE_MS = MIN_ABSENCE_HOURS * 60 * 60 * 1000;

/**
 * Validates an absence window, returning { key, message, params } on failure or null.
 */
export function absenceWindowError(startTime, endTime) {
  const start = new Date(startTime);
  const end = new Date(endTime);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
    return { key: 'timeWindowInvalidDates', message: 'Start and end must be valid date/time values.' };
  }
  if (end.getTime() <= start.getTime()) {
    return { key: 'timeWindowEndBeforeStart', message: 'End time must be after start time.' };
  }
  if (end.getTime() - start.getTime() < MIN_ABSENCE_MS) {
    return {
      key: 'absenceTooShort',
      message: `Time off covers whole days: it must last at least ${MIN_ABSENCE_HOURS} hours.`,
      params: { hours: MIN_ABSENCE_HOURS },
    };
  }
  return null;
}

/**
 * Validates an absence window. Returns an error message, or null when the
 * window is usable. Pure — no DB access — so the rule is unit-testable on its
 * own, the way validateStarterTasks is.
 */
export function validateAbsenceWindow(startTime, endTime) {
  return absenceWindowError(startTime, endTime)?.message ?? null;
}

/**
 * Most templates shown in the collapsed tray once the user has a habit.
 */
export const TRAY_QUICK_MAX = 8;

/**
 * Distinct used templates needed before the tray stops listing everything.
 */
export const TRAY_QUICK_MIN = 3;

const LOOK_BACK_MS = 60 * 24 * 60 * 60 * 1000;
const LOOK_AHEAD_MS = 14 * 24 * 60 * 60 * 1000;

/**
 * Ranks [templates] by how often *this user* scheduled them recently.
 *
 * An instance belongs to a template when title AND type match (instances
 * carry no template id). Only the user's own care instances count, within the
 * last 60 days (and up to 14 days ahead), so an old habit fades out.
 *
 * `ordered` is every template: count desc, most recent use desc, title
 * (case-insensitive); unused ones last, by title. `quick` is the collapsed
 * tray set: with [kTrayQuickMin] or more distinct used templates, only the
 * used ones (at most [kTrayQuickMax]); otherwise the full ordered list.
 */
export function rankTemplates({ templates = [], activities = [], userId, now }) {
  function key(m) {
    return `${m?.title ?? ''}\u0000${m?.type ?? ''}`;
  }

  const nowDate = now instanceof Date ? now : new Date(now);
  const nowMs = nowDate.getTime();
  const fromMs = nowMs - LOOK_BACK_MS;
  const toMs = nowMs + LOOK_AHEAD_MS;

  const counts = new Map();
  const latest = new Map();

  if (userId != null) {
    const userStr = String(userId);
    for (const a of activities) {
      if (a?.is_template === true) continue;
      if (a?.assigned_to == null || String(a.assigned_to) !== userStr) continue;
      const category = String(a.category ?? '').toLowerCase();
      if (category !== 'care') continue;
      const type = String(a.type ?? '').toLowerCase();
      if (type === 'coverage' || type === 'self') continue;
      const status = String(a.status ?? '').toLowerCase();
      if (status === 'rejected') continue;
      if (!a.starts_at) continue;
      const ts = new Date(a.starts_at).getTime();
      if (Number.isNaN(ts)) continue;
      if (ts < fromMs || ts > toMs) continue;

      const k = key(a);
      counts.set(k, (counts.get(k) || 0) + 1);
      const prev = latest.get(k);
      if (prev == null || ts > prev) {
        latest.set(k, ts);
      }
    }
  }

  function byTitle(a, b) {
    const tA = String(a?.title ?? '').toLowerCase();
    const tB = String(b?.title ?? '').toLowerCase();
    if (tA < tB) return -1;
    if (tA > tB) return 1;
    const typeA = String(a?.type ?? '').toLowerCase();
    const typeB = String(b?.type ?? '').toLowerCase();
    if (typeA < typeB) return -1;
    if (typeA > typeB) return 1;
    return 0;
  }

  const ordered = [...templates];
  ordered.sort((a, b) => {
    const cA = counts.get(key(a)) || 0;
    const cB = counts.get(key(b)) || 0;
    if (cA !== cB) return cB - cA;
    if (cA > 0) {
      const byRecent = latest.get(key(b)) - latest.get(key(a));
      if (byRecent !== 0) return byRecent;
    }
    return byTitle(a, b);
  });

  const used = ordered.filter((t) => (counts.get(key(t)) || 0) > 0);
  const distinctKeys = new Set(used.map(key));
  const quick = distinctKeys.size >= TRAY_QUICK_MIN
    ? used.slice(0, TRAY_QUICK_MAX)
    : [...ordered];

  return { ordered, quick };
}

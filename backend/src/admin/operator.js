/**
 * Who may use the operator console, and when they must sign in again
 * (docs/management-platform-plan.md §2.2).
 *
 * Unlike requireAdmin (middleware/rbac.js), requireOperator never upserts the
 * caller into users: the console's database role cannot read or write users,
 * only the admin_operators view.
 */
import { sendError } from '../utils/httpError.js';

export function requireOperator(db) {
  return async (req, res, next) => {
    try {
      const { rows } = await db.query(
        `SELECT id FROM admin_operators WHERE firebase_uid = $1`,
        [req.auth.uid]
      );
      if (!rows.length) return sendError(res, 403, 'adminOnly', 'Requires platform admin.');
      req.adminUser = { id: Number(rows[0].id) };
      return next();
    } catch {
      return sendError(res, 500, 'internal', 'Authorization check failed.');
    }
  };
}

export const RECENT_SIGN_IN_SECONDS = 30 * 60;

const READ_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

/** Changes need a sign-in from the last 30 minutes; reads do not. */
export function requireRecentSignIn(maxAgeSeconds = RECENT_SIGN_IN_SECONDS, now = () => Date.now()) {
  return (req, res, next) => {
    if (READ_METHODS.has(req.method)) return next();
    const authTime = Number(req.auth?.authTime);
    const ageSeconds = now() / 1000 - authTime;
    if (!authTime || ageSeconds > maxAgeSeconds) {
      return sendError(res, 401, 'adminReauthRequired', 'Sign in again to make changes.',
        { maxAgeMinutes: Math.round(maxAgeSeconds / 60) });
    }
    return next();
  };
}

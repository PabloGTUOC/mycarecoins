/**
 * Role-based access control.
 *
 * Role hierarchy (highest → lowest): caregiver > member
 *
 * Two exports:
 *
 *   requireRole(role, getFamilyId)
 *     Express middleware. Use when familyId is available in req (params/body/query).
 *     Example:
 *       router.patch('/:familyId/…', requireRole('caregiver', r => r.params.familyId), handler)
 *
 *   assertMemberRole(client, userId, familyId, role)
 *     In-transaction helper. Use when familyId is derived from a prior DB query.
 *     Returns { error: { code, message } } on failure, null on success.
 *     Example (inside withTransaction):
 *       const rbacErr = await assertMemberRole(client, user.id, act.family_id, 'caregiver');
 *       if (rbacErr) return rbacErr;
 *
 * Platform admin (docs/admin-family-management-plan.md) is a separate, global
 * axis stored in users.platform_role — deliberately NOT part of the family
 * role hierarchy, so an admin gains no implicit rights inside any family:
 *
 *   requireAdmin
 *     Express middleware for /api/admin routes. The DB is authoritative;
 *     nothing from the client is trusted. Sets req.adminUser on success.
 *
 *   checkPlatformAdmin(client, auth)
 *     In-transaction helper behind requireAdmin.
 *     Returns { user } on success, { error: { code, message } } on failure.
 */

import { pool } from '../db/pool.js';
import { upsertUserFromAuth, assertActiveMember } from '../db/users.js';
import { sendError } from '../utils/httpError.js';

const ROLE_LEVELS = { caregiver: 2, member: 1 };

function meetsRole(userRole, requiredRole) {
  return (ROLE_LEVELS[userRole] ?? 0) >= (ROLE_LEVELS[requiredRole] ?? 0);
}

// ─── Express middleware ───────────────────────────────────────────────────────

export function requireRole(role, getFamilyId) {
  return async (req, res, next) => {
    const familyId = Number(getFamilyId(req));

    const client = await pool.connect();
    try {
      const user = await upsertUserFromAuth(client, req.auth);
      const { rows } = await client.query(
        `SELECT role FROM family_members WHERE family_id = $1 AND user_id = $2 AND status = 'active'`,
        [familyId, user.id]
      );

      if (!rows.length) {
        return sendError(res, 403, 'familyNotMember', 'Not a family member.');
      }
      if (!meetsRole(rows[0].role, role)) {
        return sendError(res, 403, 'roleRequired', `Requires ${role} role.`, { role });
      }

      next();
    } catch {
      return sendError(res, 500, 'internal', 'Authorization check failed.');
    } finally {
      client.release();
    }
  };
}

// ─── Platform admin ───────────────────────────────────────────────────────────

export async function checkPlatformAdmin(client, auth) {
  const user = await upsertUserFromAuth(client, auth);
  const { rows } = await client.query(
    `SELECT platform_role FROM users WHERE id = $1 AND is_deleted = false`,
    [user.id]
  );

  if (!rows.length || rows[0].platform_role !== 'admin') {
    return { error: { code: 403, message: 'Requires platform admin.' } };
  }

  return { user };
}

export function requireAdmin(req, res, next) {
  (async () => {
    const client = await pool.connect();
    try {
      const result = await checkPlatformAdmin(client, req.auth);
      if (result.error) {
        return sendError(res, result.error.code, 'adminOnly', result.error.message);
      }
      req.adminUser = result.user;
      next();
    } catch {
      return sendError(res, 500, 'internal', 'Authorization check failed.');
    } finally {
      client.release();
    }
  })();
}

// ─── In-transaction helper ────────────────────────────────────────────────────

export async function assertMemberRole(client, userId, familyId, role) {
  const { rows } = await client.query(
    `SELECT role FROM family_members WHERE family_id = $1 AND user_id = $2 AND status = 'active'`,
    [familyId, userId]
  );

  if (!rows.length) {
    return { error: { code: 403, key: 'familyNotMember', message: 'Not a family member.' } };
  }
  if (!meetsRole(rows[0].role, role)) {
    return { error: { code: 403, key: 'roleRequired', message: `Requires ${role} role.`, params: { role } } };
  }

  return null;
}

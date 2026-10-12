import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { upsertUserFromAuth } from '../db/users.js';
import { requireRole } from '../middleware/rbac.js';
import { validateParams } from '../middleware/validate.js';
import { sendServiceError, serviceError, sendError } from '../utils/httpError.js';

export const inviteLinksRouter = Router();

// POST /api/families/:familyId/invite-links — generate a new shareable link
inviteLinksRouter.post('/:familyId/invite-links',
  validateParams('familyId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    const { maxUses, expiresAt } = req.body;

    try {
      const link = await withTransaction(async (client) => {
        const user = await upsertUserFromAuth(client, req.auth);
        const { rows } = await client.query(
          `INSERT INTO invite_links (family_id, created_by, max_uses, expires_at)
           VALUES ($1, $2, $3, $4)
           RETURNING id, family_id, max_uses, uses, expires_at, revoked, created_at`,
          [familyId, user.id,
           maxUses ? Number(maxUses) : null,
           expiresAt ? new Date(expiresAt) : null]
        );
        return rows[0];
      });
      return res.status(201).json({ link });
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to create invite link.');
    }
  }
);

// GET /api/families/:familyId/invite-links — list active (non-revoked) links
inviteLinksRouter.get('/:familyId/invite-links',
  validateParams('familyId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    try {
      const links = await withTransaction(async (client) => {
        const { rows } = await client.query(
          `SELECT id, family_id, max_uses, uses, expires_at, revoked, created_at
           FROM invite_links
           WHERE family_id = $1 AND revoked = false
           ORDER BY created_at DESC`,
          [familyId]
        );
        return rows;
      });
      return res.json({ links });
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to fetch invite links.');
    }
  }
);

// DELETE /api/families/:familyId/invite-links/:linkId — revoke a link
inviteLinksRouter.delete('/:familyId/invite-links/:linkId',
  validateParams('familyId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    const linkId = req.params.linkId;

    try {
      const result = await withTransaction(async (client) => {
        const { rowCount } = await client.query(
          `UPDATE invite_links SET revoked = true WHERE id = $1 AND family_id = $2`,
          [linkId, familyId]
        );
        if (!rowCount) return serviceError(404, 'inviteLinkNotFound', 'Invite link not found.');
        return { data: { revoked: true } };
      });
      if (result.error) return sendServiceError(res, result.error);
      return res.json(result.data);
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to revoke invite link.');
    }
  }
);
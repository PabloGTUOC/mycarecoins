import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { upsertUserFromAuth, assertActiveMember } from '../db/users.js';
import { validateBody, validateParams, required, string, positiveInt, isoDate } from '../middleware/validate.js';
import { absenceWindowError } from '../services/absenceService.js';
import { sendServiceError, serviceError, sendError } from '../utils/httpError.js';

export const absencesRouter = Router();

// ─────────────────────────────────────────────
// GET /api/absences?familyId=X
// Returns all absences for a family
// ─────────────────────────────────────────────
absencesRouter.get('/', async (req, res) => {
  const familyId = Number(req.query.familyId);
  if (!familyId) return sendError(res, 400, 'familyIdRequired', 'familyId query param is required.');

  try {
    const absences = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      if (!await assertActiveMember(client, familyId, user.id)) return null;

      const { rows } = await client.query(
        `SELECT a.*, u.display_name as user_name, fm.alias as user_alias
         FROM absences a
         JOIN users u ON u.id = a.user_id
         JOIN family_members fm ON fm.user_id = a.user_id AND fm.family_id = a.family_id
         WHERE a.family_id = $1
         ORDER BY a.start_time ASC`,
        [familyId]
      );
      return rows;
    });

    if (absences === null) return sendError(res, 403, 'familyNotMember', 'Not a family member.');
    return res.json({ absences });
  } catch (err) {
    console.error('GET /absences error:', err);
    return sendError(res, 500, 'internal', 'Failed to fetch absences.');
  }
});

// ─────────────────────────────────────────────
// POST /api/absences
// Creates a new absence
// ─────────────────────────────────────────────
absencesRouter.post('/', validateBody({
  familyId: [required(), positiveInt()],
  startTime: [required(), isoDate()],
  endTime: [required(), isoDate()],
  title: [required(), string(1, 100)]
}), async (req, res) => {
  const { familyId, startTime, endTime, title } = req.body;

  const windowError = absenceWindowError(startTime, endTime);
  if (windowError) return sendError(res, 400, windowError.key, windowError.message, windowError.params);

  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      if (!await assertActiveMember(client, familyId, user.id)) {
        return serviceError(403, 'familyNotMember', 'Not a family member.');
      }

      const { rows: activityOverlap } = await client.query(
        `SELECT id, title FROM activities 
         WHERE assigned_to = $1 
         AND family_id = $2
         AND is_template = false
         AND status IN ('pending', 'approved', 'pending_validation')
         AND (starts_at < $4 AND ends_at > $3)`,
        [user.id, familyId, startTime, endTime]
      );

      if (activityOverlap.length > 0) {
        return serviceError(
          400,
          'absenceActivityConflict',
          `You have scheduled activities ("${activityOverlap[0].title}") during this period. Please cancel or transfer them first.`,
          { title: activityOverlap[0].title }
        );
      }

      const { rows } = await client.query(
        `INSERT INTO absences (family_id, user_id, start_time, end_time, title)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [familyId, user.id, startTime, endTime, title.trim()]
      );
      return { data: rows[0] };
    });

    if (result.error) return sendServiceError(res, result.error);
    return res.status(201).json({ absence: result.data });
  } catch (err) {
    console.error('POST /absences error:', err);
    return sendError(res, 500, 'internal', 'Failed to create absence.');
  }
});

// ─────────────────────────────────────────────
// DELETE /api/absences/:id
// Removes an absence
// ─────────────────────────────────────────────
absencesRouter.delete('/:id', validateParams('id'), async (req, res) => {
  const absenceId = Number(req.params.id);

  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      
      const { rows } = await client.query(
        `SELECT family_id, user_id FROM absences WHERE id = $1 FOR UPDATE`,
        [absenceId]
      );

      if (!rows.length) return serviceError(404, 'absenceNotFound', 'Absence not found.');
      const absence = rows[0];

      const { rows: memberRows } = await client.query(
        `SELECT role FROM family_members WHERE family_id = $1 AND user_id = $2 AND status = 'active'`,
        [absence.family_id, user.id]
      );

      if (!memberRows.length) return serviceError(403, 'familyNotMember', 'Not a family member.');

      const isOwner      = Number(absence.user_id) === Number(user.id);
      const isCaregiver  = memberRows[0].role === 'caregiver';

      if (!isOwner && !isCaregiver) {
        return serviceError(403, 'absenceDeleteForbidden', 'You do not have permission to delete this absence.');
      }

      await client.query(`DELETE FROM absences WHERE id = $1`, [absenceId]);
      return { data: { success: true } };
    });

    if (result.error) return sendServiceError(res, result.error);
    return res.json(result.data);
  } catch (err) {
    console.error('DELETE /absences error:', err);
    return sendError(res, 500, 'internal', 'Failed to delete absence.');
  }
});

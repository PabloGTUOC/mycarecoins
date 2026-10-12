import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { upsertUserFromAuth, assertActiveMember } from '../db/users.js';
import { runAutoCompleteSweep } from '../db/autoComplete.js';
import { runMonthlyDistribution } from '../services/distributionService.js';
import { sendError } from '../utils/httpError.js';

export const dashboardRouter = Router();

dashboardRouter.get('/:familyId', async (req, res) => {
  const familyId = Number(req.params.familyId);
  if (!familyId) return sendError(res, 400, 'familyIdInvalid', 'Invalid familyId.');

  try {
    const data = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      if (!await assertActiveMember(client, familyId, user.id)) return null;

      if (!await runMonthlyDistribution(client, familyId)) return null;

      await runAutoCompleteSweep(client, familyId);

      const { rows: members } = await client.query(
        `SELECT fm.user_id, COALESCE(fm.alias, u.display_name, u.email, u.firebase_uid) AS name, fm.role, fm.coin_balance, fm.status, u.avatar_url
         FROM family_members fm JOIN users u ON u.id = fm.user_id
         WHERE fm.family_id = $1
         ORDER BY fm.coin_balance DESC`,
        [familyId]
      );

      const { rows: byDay } = await client.query(
        `SELECT DATE(starts_at) AS day,
                COUNT(*)::int AS total_activities,
                SUM(CASE WHEN status='approved' THEN coin_value ELSE 0 END)::int AS approved_coins
         FROM activities
         WHERE family_id = $1
         GROUP BY DATE(starts_at)
         ORDER BY day DESC
         LIMIT 30`,
        [familyId]
      );

      const { rows: objectsOfCare } = await client.query(
        `SELECT id, name, actor_type, care_time, avatar_url 
         FROM actors 
         WHERE family_id = $1 AND actor_type != 'person'
         ORDER BY id ASC`,
        [familyId]
      );

      const { rows: usedRows } = await client.query(
        `SELECT COALESCE(SUM(coin_value), 0)::int as used_this_month
         FROM activities
         WHERE family_id = $1
           AND category = 'care'
           AND status = 'completed'
           AND starts_at >= date_trunc('month', NOW())`,
        [familyId]
      );
      const used_this_month = usedRows[0].used_this_month;

      return { members, calendar: byDay, objectsOfCare, used_this_month };
    });

    if (!data) return sendError(res, 403, 'familyNotMember', 'Not a family member.');
    return res.json(data);
  } catch (err) {
    console.error('DASHBOARD ERROR:', err);
    return sendError(res, 500, 'internal', 'Failed to load dashboard.');
  }
});

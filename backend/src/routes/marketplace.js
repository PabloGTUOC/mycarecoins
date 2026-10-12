import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { upsertUserFromAuth, assertActiveMember } from '../db/users.js';
import { validateBody, required, string, positiveInt, isoDate } from '../middleware/validate.js';
import { requireRole } from '../middleware/rbac.js';
import { getFamilyEntitlements, limitWarning, assertFamilyWritable } from '../services/entitlementService.js';
import { sendServiceError } from '../utils/httpError.js';

export const marketplaceRouter = Router();

marketplaceRouter.get('/rewards/:familyId', async (req, res) => {
  const familyId = Number(req.params.familyId);
  if (!familyId) return res.status(400).json({ error: 'Invalid familyId.' });

  try {
    const data = await withTransaction(async (client) => {
      const me = await upsertUserFromAuth(client, req.auth);
      if (!await assertActiveMember(client, familyId, me.id)) return null;

      const { rows } = await client.query(
        `SELECT id, family_id, creator_id, title, description, cost, status, created_at,
                max_uses, valid_from, valid_until,
                (SELECT COUNT(*) FROM reward_redemptions rr WHERE rr.reward_id = marketplace_rewards.id)::int as uses
         FROM marketplace_rewards
         WHERE family_id = $1 AND status = 'active'
           AND (max_uses IS NULL OR (SELECT COUNT(*) FROM reward_redemptions rr WHERE rr.reward_id = marketplace_rewards.id) < max_uses)
           AND (valid_from IS NULL OR NOW() >= valid_from)
           AND (valid_until IS NULL OR NOW() <= valid_until)
         ORDER BY created_at DESC`,
        [familyId]
      );

      const { rows: claimed } = await client.query(
        `SELECT rr.id as redemption_id, mr.title, mr.cost, rr.redeemed_at, 
                COALESCE(fm.alias, u.display_name, u.email) as buyer_name, u.avatar_url as buyer_avatar
         FROM reward_redemptions rr
         JOIN marketplace_rewards mr ON mr.id = rr.reward_id
         JOIN users u ON u.id = rr.user_id
         JOIN family_members fm ON fm.user_id = u.id AND fm.family_id = rr.family_id
         WHERE rr.family_id = $1
         ORDER BY rr.redeemed_at DESC
         LIMIT 30`,
        [familyId]
      );

      return { rewards: rows, claimed };
    });

    if (data === null) return res.status(403).json({ error: 'Not a family member.' });
    return res.json(data);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'Failed to load rewards.' });
  }
});

marketplaceRouter.post('/rewards',
  validateBody({
    familyId: [required(), positiveInt()],
    title: [required(), string(1, 100)],
    description: [string(1, 500)],
    cost: [required(), positiveInt()],
    maxUses: [positiveInt()],
    validFrom: [isoDate()],
    validUntil: [isoDate()]
  }),
  requireRole('caregiver', r => r.body.familyId),
  async (req, res) => {
    const { familyId, title, description, cost, maxUses, validFrom, validUntil } = req.body;
    if (!familyId || !title || !cost) return res.status(400).json({ error: 'familyId, title and cost are required.' });

    try {
      const result = await withTransaction(async (client) => {
        const me = await upsertUserFromAuth(client, req.auth);

        const gate = await assertFamilyWritable(client, familyId);
        if (gate) return gate;

        const { rows } = await client.query(
          `INSERT INTO marketplace_rewards (family_id, creator_id, title, description, cost, max_uses, valid_from, valid_until)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
         RETURNING *`,
          [
            familyId, me.id, title.trim(), description ? description.trim() : null, Number(cost),
            maxUses ? Number(maxUses) : null,
            validFrom ? new Date(validFrom) : null,
            validUntil ? new Date(validUntil) : null
          ]
        );

        const entitlements = await getFamilyEntitlements(client, familyId);
        let warning = null;
        if (entitlements.limits.max_active_rewards != null) {
          const { rows: countRows } = await client.query(
            `SELECT COUNT(*)::int AS n FROM marketplace_rewards WHERE family_id = $1 AND status = 'active'`,
            [familyId]
          );
          warning = limitWarning(entitlements, 'max_active_rewards', countRows[0].n, 'reward_limit_exceeded');
        }
        return { reward: rows[0], warning };
      });

      if (result.error) return sendServiceError(res, result.error);
      return res.status(201).json({ reward: result.reward, ...(result.warning && { warning: result.warning }) });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ error: 'Failed to create reward.' });
    }
  });

marketplaceRouter.post('/rewards/:rewardId/redeem', async (req, res) => {
  const { rewardId } = req.params;
  if (!rewardId || typeof rewardId !== 'string' || rewardId.length < 10) {
    return res.status(400).json({ error: 'rewardId: must be a valid UUID' });
  }

  try {
    const result = await withTransaction(async (client) => {
      const me = await upsertUserFromAuth(client, req.auth);

      const { rows: rewardRows } = await client.query(
        `SELECT id, family_id, cost, title, status, max_uses, valid_from, valid_until FROM marketplace_rewards WHERE id=$1 FOR UPDATE`,
        [rewardId]
      );
      if (!rewardRows.length) return { error: { code: 404, message: 'Reward not found.' } };
      const reward = rewardRows[0];
      if (reward.status !== 'active') return { error: { code: 409, message: 'Reward is no longer active.' } };

      const now = new Date();
      if (reward.valid_from && now < reward.valid_from) return { error: { code: 409, message: 'Reward is not yet available.' } };
      if (reward.valid_until && now > reward.valid_until) return { error: { code: 409, message: 'Reward has expired.' } };

      if (reward.max_uses) {
        const { rows: usageRows } = await client.query('SELECT COUNT(*) as c FROM reward_redemptions WHERE reward_id=$1', [reward.id]);
        if (Number(usageRows[0].c) >= reward.max_uses) {
          return { error: { code: 409, message: 'Reward is sold out.' } };
        }
      }

      const { rows: buyerRows } = await client.query(
        `SELECT coin_balance FROM family_members WHERE family_id=$1 AND user_id=$2 AND status='active' FOR UPDATE`,
        [reward.family_id, me.id]
      );
      if (!buyerRows.length) return { error: { code: 403, message: 'Not a family member.' } };
      if (buyerRows[0].coin_balance < reward.cost) {
        return { error: { code: 409, message: 'Insufficient coins.' } };
      }

      await client.query('UPDATE family_members SET coin_balance = coin_balance - $1 WHERE family_id=$2 AND user_id=$3', [reward.cost, reward.family_id, me.id]);

      await client.query('INSERT INTO reward_redemptions (reward_id, user_id, family_id) VALUES ($1,$2,$3)', [reward.id, me.id, reward.family_id]);

      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, amount, reason) VALUES ($1,$2,$3,$4)`,
        [reward.family_id, me.id, -reward.cost, `Redeemed: ${reward.title}`]
      );

      return { data: { redeemed: true, cost: reward.cost } };
    });

    if (result.error) return sendServiceError(res, result.error);
    return res.json(result.data);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'Failed to redeem reward.' });
  }
});

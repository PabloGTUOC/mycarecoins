import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { upsertUserFromAuth, assertActiveMember } from '../db/users.js';

export const statsRouter = Router();

statsRouter.get('/:familyId', async (req, res) => {
    const familyId = Number(req.params.familyId);
    if (!familyId) return res.status(400).json({ error: 'Invalid familyId.' });

    try {
        const data = await withTransaction(async (client) => {
            const user = await upsertUserFromAuth(client, req.auth);

            if (!await assertActiveMember(client, familyId, user.id)) return null;

            const { rows: kpis } = await client.query(
                `SELECT
           COALESCE(SUM(coin_value), 0)::int as total_lifetime_coins,
           COUNT(*)::int as total_lifetime_tasks
         FROM activities
         WHERE family_id = $1 AND category = 'care' AND status = 'completed'`,
                [familyId]
            );

            const { rows: kpiExtra } = await client.query(
                `SELECT
           (SELECT COUNT(*) FROM coin_ledger  WHERE family_id = $1 AND reason = 'bounty_escrow')::int as total_bounties_offered,
           (SELECT COUNT(*) FROM reward_redemptions WHERE family_id = $1)::int as total_rewards_claimed`,
                [familyId]
            );

            const { rows: caregiversList } = await client.query(
                `SELECT COALESCE(fm.alias, u.display_name, 'Unknown') as name
                 FROM family_members fm
                 JOIN users u ON u.id = fm.user_id
                 WHERE fm.family_id = $1 AND fm.role = 'caregiver' AND fm.status = 'active'`,
                [familyId]
            );
            const activeCaregivers = caregiversList.map(c => c.name);

            const { rows: trendByMonth } = await client.query(
                `SELECT
           COALESCE(fm.alias, u.display_name, 'Unknown') as caregiver,
           to_char(starts_at AT TIME ZONE 'UTC', 'YYYY-MM') as month,
           COALESCE(SUM(coin_value), 0)::int as coins,
           COUNT(*)::int as tasks
         FROM activities a
         JOIN family_members fm ON fm.user_id = a.assigned_to AND fm.family_id = a.family_id
         JOIN users u ON u.id = a.assigned_to
         WHERE a.family_id = $1 AND a.category = 'care' AND a.status = 'completed'
         GROUP BY caregiver, month
         ORDER BY month ASC
         LIMIT 100`,
                [familyId]
            );

            const { rows: typeSplit } = await client.query(
                `SELECT
           COALESCE(fm.alias, u.display_name, 'Unknown') as caregiver,
           type,
           COUNT(*)::int as value
         FROM activities a
         JOIN family_members fm ON fm.user_id = a.assigned_to AND fm.family_id = a.family_id
         JOIN users u ON u.id = a.assigned_to
         WHERE a.family_id = $1 AND a.category = 'care' AND a.status = 'completed'
         GROUP BY caregiver, type`,
                [familyId]
            );

            const { rows: activityFrequency } = await client.query(
                `SELECT
           COALESCE(fm.alias, u.display_name, 'Unknown') as caregiver,
           title,
           COUNT(*)::int as value
         FROM activities a
         JOIN family_members fm ON fm.user_id = a.assigned_to AND fm.family_id = a.family_id
         JOIN users u ON u.id = a.assigned_to
         WHERE a.family_id = $1 AND a.category = 'care' AND a.status = 'completed'
         GROUP BY caregiver, title
         ORDER BY value DESC
         LIMIT 100`,
                [familyId]
            );

            // Fairness (docs/personal-time-plan.md Phase 7): personal time taken
            // set against coverage given, per member and month. Both fall out of
            // the subclass columns — self activities carry category = 'self',
            // coverage carries type = 'coverage' — so nothing new is stored.
            //
            // There is deliberately no declined count here, and there must never
            // be one anywhere: declining has to stay free and invisible, or the
            // sweetener stops being an offer and becomes social pressure (§10).
            const { rows: fairnessByMonth } = await client.query(
                `SELECT
           COALESCE(fm.alias, u.display_name, 'Unknown') as caregiver,
           to_char(a.starts_at AT TIME ZONE 'UTC', 'YYYY-MM') as month,
           COALESCE(SUM(a.duration_minutes) FILTER (WHERE a.category = 'self'), 0)::int as personal_minutes,
           COUNT(*) FILTER (WHERE a.category = 'self')::int as personal_count,
           COALESCE(SUM(a.duration_minutes) FILTER (WHERE a.type = 'coverage'), 0)::int as coverage_minutes,
           COUNT(*) FILTER (WHERE a.type = 'coverage')::int as coverage_count
         FROM activities a
         JOIN family_members fm ON fm.user_id = a.assigned_to AND fm.family_id = a.family_id
         JOIN users u ON u.id = a.assigned_to
         WHERE a.family_id = $1 AND a.status = 'completed' AND a.is_template = false
           AND (a.category = 'self' OR a.type = 'coverage')
         GROUP BY caregiver, month
         ORDER BY month ASC
         LIMIT 100`,
                [familyId]
            );

            const { rows: memberBalances } = await client.query(
                `SELECT COALESCE(fm.alias, u.display_name, 'Unknown') as name,
                        fm.coin_balance,
                        fm.role
                 FROM family_members fm
                 JOIN users u ON u.id = fm.user_id
                 WHERE fm.family_id = $1 AND fm.status = 'active'
                 ORDER BY fm.coin_balance DESC`,
                [familyId]
            );

            const { rows: bountyStats } = await client.query(
                `SELECT COALESCE(fm.alias, u.display_name, 'Unknown') as name,
                        SUM(CASE WHEN cl.reason IN ('bounty_escrow', 'bounty_paid') THEN ABS(cl.amount) ELSE 0 END)::int as offered,
                        SUM(CASE WHEN cl.reason IN ('bounty_earned', 'bounty_reverted') THEN cl.amount ELSE 0 END)::int as earned,
                        SUM(CASE WHEN cl.reason = 'bounty_refunded' THEN cl.amount ELSE 0 END)::int as refunded
                 FROM coin_ledger cl
                 JOIN family_members fm ON fm.user_id = cl.user_id AND fm.family_id = cl.family_id
                 JOIN users u ON u.id = cl.user_id
                 WHERE cl.family_id = $1
                 GROUP BY name
                 ORDER BY offered DESC`,
                [familyId]
            );

            const { rows: rewardsByUser } = await client.query(
                `SELECT COALESCE(fm.alias, u.display_name, 'Unknown') as name,
                        COUNT(rr.id)::int as redemptions,
                        COALESCE(SUM(mr.cost), 0)::int as coins_spent
                 FROM reward_redemptions rr
                 JOIN users u ON u.id = rr.user_id
                 JOIN family_members fm ON fm.user_id = rr.user_id AND fm.family_id = rr.family_id
                 JOIN marketplace_rewards mr ON mr.id = rr.reward_id
                 WHERE rr.family_id = $1
                 GROUP BY name
                 ORDER BY redemptions DESC`,
                [familyId]
            );

            const { rows: topRewards } = await client.query(
                `SELECT mr.title, mr.cost, COUNT(rr.id)::int as redemptions
                 FROM marketplace_rewards mr
                 LEFT JOIN reward_redemptions rr ON rr.reward_id = mr.id
                 WHERE mr.family_id = $1
                 GROUP BY mr.id, mr.title, mr.cost
                 ORDER BY redemptions DESC
                 LIMIT 8`,
                [familyId]
            );

            const { rows: completionRates } = await client.query(
                `SELECT COALESCE(fm.alias, u.display_name, 'Unknown') as caregiver,
                        COUNT(*)::int as total,
                        SUM(CASE WHEN a.status = 'completed' THEN 1 ELSE 0 END)::int as completed
                 FROM activities a
                 JOIN family_members fm ON fm.user_id = a.assigned_to AND fm.family_id = a.family_id
                 JOIN users u ON u.id = a.assigned_to
                 WHERE a.family_id = $1
                   AND a.category = 'care'
                   AND a.assigned_to IS NOT NULL
                   AND a.status != 'rejected'
                 GROUP BY caregiver`,
                [familyId]
            );

            const { rows: statusDistribution } = await client.query(
                `SELECT status, COUNT(*)::int as count
                 FROM activities
                 WHERE family_id = $1 AND category = 'care'
                 GROUP BY status`,
                [familyId]
            );

            const { rows: coinFlowByReason } = await client.query(
                // A reversal (negative amount) is folded into the payout it undoes,
                // so a reverted activity nets out instead of counting as earned.
                `SELECT to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM') as month,
                        CASE WHEN reason LIKE 'Redeemed%' THEN 'redeemed'
                             WHEN reason = 'bounty_paid' THEN 'bounty_escrow'
                             WHEN reason = 'activity_reverted' THEN 'activity_completed'
                             WHEN reason = 'bounty_reverted' THEN 'bounty_earned'
                             WHEN reason = 'coverage_reverted' THEN 'coverage_earned'
                             WHEN reason = 'coverage_sweetener_reverted' THEN 'coverage_sweetener_paid'
                             ELSE reason END as reason,
                        SUM(CASE WHEN reason IN ('activity_reverted', 'bounty_reverted',
                                                 'coverage_reverted', 'coverage_sweetener_reverted')
                                 THEN amount ELSE ABS(amount) END)::int as total
                 FROM coin_ledger
                 WHERE family_id = $1
                 GROUP BY 1, 2
                 ORDER BY month ASC`,
                [familyId]
            );

            return {
                kpis: { ...kpis[0], ...kpiExtra[0] },
                activeCaregivers,
                trendByMonth,
                typeSplit,
                activityFrequency,
                memberBalances,
                bountyStats,
                rewardsByUser,
                topRewards,
                completionRates,
                statusDistribution,
                coinFlowByReason,
                fairnessByMonth
            };
        });

        if (!data) return res.status(403).json({ error: 'Not a family member or forbidden.' });
        return res.json(data);
    } catch (err) {
        console.error('Failed to load stats:', err);
        return res.status(500).json({ error: 'Failed to load statistics.' });
    }
});

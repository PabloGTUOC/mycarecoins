/**
 * Completes all approved activities whose end time has passed.
 * Must be called inside an existing transaction (client already has BEGIN).
 * Uses FOR UPDATE to prevent concurrent sweeps from double-awarding coins.
 */
import { payoutReasons } from './ledgerReasons.js';

export const RUNNING_CAP_MINUTES = 240;

export async function runAutoCompleteSweep(client, familyId) {
  await client.query(
    `UPDATE activities
        SET running_since = NULL,
            ends_at = starts_at + ($2 * interval '1 minute'),
            duration_minutes = $2,
            coin_value = $2
      WHERE family_id = $1 AND running_since IS NOT NULL AND running_since <= NOW() - ($2 * interval '1 minute')`,
    [familyId, RUNNING_CAP_MINUTES]
  );

  const { rows: expired } = await client.query(
    `SELECT id, assigned_to, type, coin_value, bounty_amount, bounty_offered_by FROM activities
     WHERE family_id = $1 AND status = 'approved' AND ends_at <= NOW() AND running_since IS NULL
     FOR UPDATE`,
    [familyId]
  );

  for (const act of expired) {
    const bountyAmt = act.bounty_amount || 0;
    const totalAward = (act.coin_value || 0) + bountyAmt;
    const reason = payoutReasons(act.type);

    await client.query(
      `UPDATE activities SET status = 'completed', bounty_amount = 0, bounty_offered_by = NULL WHERE id = $1`,
      [act.id]
    );

    if (totalAward > 0) {
      await client.query(
        `UPDATE family_members SET coin_balance = coin_balance + $1 WHERE family_id = $2 AND user_id = $3`,
        [totalAward, familyId, act.assigned_to]
      );
    }

    if (act.coin_value > 0) {
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason)
         VALUES ($1, $2, $3, $4, $5)`,
        [familyId, act.assigned_to, act.id, act.coin_value, reason.value]
      );
    }

    if (bountyAmt > 0) {
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason)
         VALUES ($1, $2, $3, $4, $5)`,
        [familyId, act.assigned_to, act.id, bountyAmt, reason.bonus]
      );
    }
  }
}

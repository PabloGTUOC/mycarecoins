-- Restore the credits that revertActivity used to overwrite.
--
-- revertActivity once rewrote a payout's credit row into the reversal
-- (amount -> -amount, reason -> *_reverted) instead of appending one, so
-- SUM(coin_ledger.amount) fell 2x the reverted amount below the balances.
-- It now appends. This puts back the credit each old reversal swallowed,
-- dated with the reversal so a month's ledger still nets to zero.
--
-- Idempotent: a reversal that already has its credit beside it is skipped,
-- and that is true of every reversal written by the fixed code. Reversals
-- whose activity has since been deleted (activity_id NULL) cannot be paired
-- and are left alone.
INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason, created_at)
SELECT r.family_id, r.user_id, r.activity_id, -r.amount, m.credit, r.created_at
FROM coin_ledger r
JOIN (VALUES
  ('activity_reverted',           'activity_completed'),
  ('bounty_reverted',             'bounty_earned'),
  ('coverage_reverted',           'coverage_earned'),
  ('coverage_sweetener_reverted', 'coverage_sweetener_paid')
) AS m(reversal, credit) ON m.reversal = r.reason
WHERE r.activity_id IS NOT NULL
  AND r.amount < 0
  AND NOT EXISTS (
    SELECT 1 FROM coin_ledger c
    WHERE c.activity_id = r.activity_id
      AND c.user_id = r.user_id
      AND c.reason = m.credit
  );

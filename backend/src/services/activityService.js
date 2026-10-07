import { assertActiveMember } from '../db/users.js';
import { runAutoCompleteSweep } from '../db/autoComplete.js';
import { assertMemberRole } from '../middleware/rbac.js';
import { payoutReasons } from '../db/ledgerReasons.js';

export async function listActivities(client, userId, familyId) {
  if (!await assertActiveMember(client, familyId, userId)) {
    return { error: { code: 403, message: 'Not a family member.' } };
  }
  await runAutoCompleteSweep(client, familyId);
  const { rows } = await client.query(
    `SELECT a.id, a.title, a.category, a.type, a.description,
            a.starts_at, a.ends_at, a.duration_minutes,
            a.coin_value, a.status, a.created_by, a.assigned_to, a.is_template, a.is_recurrent,
            a.approved_by, a.approved_at, a.bounty_amount, a.bounty_offered_by,
            a.counterpart_activity_id,
            fm.alias AS assigned_alias,
            COALESCE(fm.alias, u.display_name) AS assigned_to_name
     FROM activities a
     LEFT JOIN family_members fm ON fm.user_id = a.assigned_to AND fm.family_id = a.family_id
     LEFT JOIN users u ON u.id = a.assigned_to
     WHERE a.family_id = $1
     ORDER BY a.is_template DESC, a.starts_at ASC NULLS FIRST`,
    [familyId]
  );
  return { data: { activities: rows } };
}

export async function createActivity(client, userId, { familyId, title, type, durationMinutes, coinValue, isRecurrent }) {
  if (!await assertActiveMember(client, familyId, userId)) {
    return { error: { code: 403, message: 'Not a family member.' } };
  }
  const { rows } = await client.query(
    `INSERT INTO activities
       (family_id, created_by, assigned_to, title, type,
        starts_at, ends_at, duration_minutes, coin_value, status, is_template, is_recurrent)
     VALUES ($1, $2, NULL, $3, $4, NULL, NULL, $5, $6, 'pending', true, $7)
     RETURNING *`,
    [
      familyId, userId,
      title.trim(), type,
      Number(durationMinutes),
      coinValue ? Number(coinValue) : Number(durationMinutes),
      Boolean(isRecurrent),
    ]
  );
  return { data: rows[0] };
}

export async function approveActivity(client, userId, activityId) {
  const { rows: tmplRows } = await client.query(
    `SELECT * FROM activities WHERE id = $1 AND is_template = true
     AND family_id IN (SELECT family_id FROM family_members WHERE user_id = $2 AND status = 'active')
     FOR UPDATE`,
    [activityId, userId]
  );
  if (!tmplRows.length) return { error: { code: 404, message: 'Template not found.' } };
  const tmpl = tmplRows[0];
  if (tmpl.status !== 'pending') {
    return { error: { code: 409, message: 'Only pending templates can be approved.' } };
  }
  const rbacErr = await assertMemberRole(client, userId, tmpl.family_id, 'caregiver');
  if (rbacErr) return rbacErr;
  await client.query(
    `UPDATE activities SET status = 'approved', approved_by = $1, approved_at = NOW() WHERE id = $2`,
    [userId, tmpl.id]
  );
  return { data: { approved: true } };
}

export async function scheduleActivity(client, userId, activityId, startsAt) {
  const { rows: tmpl } = await client.query(
    `SELECT * FROM activities
     WHERE id = $1 AND is_template = true AND status = 'approved'
       AND family_id IN (SELECT family_id FROM family_members WHERE user_id = $2 AND status = 'active')`,
    [activityId, userId]
  );
  if (!tmpl.length) {
    return { error: { code: 404, message: 'Approved activity template not found.' } };
  }
  const t = tmpl[0];
  const start = new Date(startsAt);
  const endsAtDate = new Date(start.getTime() + t.duration_minutes * 60000);
  const isPast = endsAtDate < new Date();
  let initialStatus = isPast ? 'pending_validation' : 'approved';

  if (isPast) {
    const { rows: cgRows } = await client.query(
      `SELECT user_id FROM family_members WHERE family_id = $1 AND role = 'caregiver' AND status = 'active'`,
      [t.family_id]
    );
    if (cgRows.length === 1 && cgRows[0].user_id === userId) initialStatus = 'approved';
  }

  const { rows: absenceOverlap } = await client.query(
    `SELECT id, title FROM absences
     WHERE user_id = $1 AND family_id = $2 AND (start_time < $4 AND end_time > $3)`,
    [userId, t.family_id, start.toISOString(), endsAtDate.toISOString()]
  );
  if (absenceOverlap.length > 0) {
    return { error: { code: 400, message: `You are marked as absent during this time ("${absenceOverlap[0].title}").` } };
  }

  // Coverage is deliberately exempt: it is supervision, not busy hands. Someone
  // covering a dependent still cooks dinner and runs bath time inside that
  // window, so accepting coverage must not freeze the rest of their evening.
  const { rows: selfOverlap } = await client.query(
    `SELECT id, title FROM activities
     WHERE assigned_to = $1 AND family_id = $2 AND is_template = false
       AND type <> 'coverage'
       AND status IN ('approved', 'pending_validation')
       AND (starts_at < $4 AND ends_at > $3)`,
    [userId, t.family_id, start.toISOString(), endsAtDate.toISOString()]
  );
  if (selfOverlap.length > 0) {
    return { error: { code: 409, message: `You already have "${selfOverlap[0].title}" scheduled during this time.` } };
  }

  const { rows: budgetRows } = await client.query(`
    SELECT f.monthly_coin_budget,
      COALESCE((
        SELECT SUM(coin_value) FROM activities
        WHERE family_id = $1 AND category = 'care' AND is_template = false
          AND status IN ('approved', 'completed')
          AND date_trunc('month', starts_at) = date_trunc('month', $2::timestamptz)
      ), 0)::int as used_this_month
    FROM families f WHERE f.id = $1
  `, [t.family_id, start.toISOString()]);

  let warning = null;
  if (budgetRows.length && budgetRows[0].used_this_month + Number(t.coin_value) > budgetRows[0].monthly_coin_budget) {
    warning = 'budget_exceeded';
  }

  const { rows } = await client.query(
    `INSERT INTO activities
       (family_id, created_by, assigned_to, title, type,
        starts_at, ends_at, duration_minutes, coin_value,
        status, is_template, is_recurrent, approved_by, approved_at)
     VALUES ($1, $2, $3, $4, $5, $6::timestamptz,
             $6::timestamptz + ($7::int || ' minutes')::interval,
             $7::int, $8::int, $11, false, $12, $9, $10)
     RETURNING *`,
    [
      t.family_id, t.created_by, userId, t.title, t.type,
      start.toISOString(), Number(t.duration_minutes), Number(t.coin_value),
      t.approved_by, t.approved_at, initialStatus, t.is_recurrent,
    ]
  );
  let activity = rows[0];

  if (initialStatus === 'approved' && isPast) {
    await runAutoCompleteSweep(client, t.family_id);
    const { rows: updated } = await client.query(`SELECT * FROM activities WHERE id = $1`, [activity.id]);
    if (updated.length) activity = updated[0];
  }
  return { data: activity, warning };
}

export async function createRecurrence(client, userId, instanceId, { frequency, untilDate }) {
  const until = new Date(untilDate);
  until.setHours(23, 59, 59, 999);

  const { rows: actRows } = await client.query(
    `SELECT * FROM activities WHERE id = $1 AND is_template = false AND is_recurrent = true
     AND family_id IN (SELECT family_id FROM family_members WHERE user_id = $2 AND status = 'active')`,
    [instanceId, userId]
  );
  if (!actRows.length) return { error: { code: 404, message: 'Valid recurrent scheduled instance not found.' } };
  const act = actRows[0];

  let current = new Date(act.starts_at);
  const clones = [];
  while (true) {
    if (frequency === 'daily') current.setDate(current.getDate() + 1);
    else if (frequency === 'weekdays') {
      current.setDate(current.getDate() + 1);
      if (current.getDay() === 0 || current.getDay() === 6) continue;
    } else if (frequency === 'weekly') current.setDate(current.getDate() + 7);
    if (current > until) break;
    clones.push(new Date(current));
  }
  if (!clones.length) return { data: { created: 0 } };

  let count = 0;
  for (const d of clones) {
    const startIso = d.toISOString();
    const endIso = new Date(d.getTime() + act.duration_minutes * 60000).toISOString();
    const { rows: absenceOverlap } = await client.query(
      `SELECT id FROM absences WHERE user_id = $1 AND family_id = $2 AND (start_time < $4 AND end_time > $3)`,
      [act.assigned_to, act.family_id, startIso, endIso]
    );
    if (absenceOverlap.length > 0) continue;
    const { rows: selfOverlap } = await client.query(
      `SELECT id FROM activities
       WHERE assigned_to = $1 AND family_id = $2 AND is_template = false
         AND type <> 'coverage'
         AND status IN ('approved', 'pending_validation')
         AND (starts_at < $4 AND ends_at > $3)`,
      [act.assigned_to, act.family_id, startIso, endIso]
    );
    if (selfOverlap.length > 0) continue;
    await client.query(
      `INSERT INTO activities
         (family_id, created_by, assigned_to, title, type,
          starts_at, ends_at, duration_minutes, coin_value,
          status, is_template, is_recurrent, approved_by, approved_at)
       VALUES ($1,$2,$3,$4,$5,$6::timestamptz,$6::timestamptz+($7::int||' minutes')::interval,$7,$8,$11,false,true,$9,$10)`,
      [act.family_id, act.created_by, act.assigned_to, act.title, act.type,
       startIso, act.duration_minutes, act.coin_value, act.approved_by, act.approved_at, 'approved']
    );
    count++;
  }
  return { data: { created: count } };
}

export async function completeActivity(client, userId, instanceId) {
  const { rows: instRows } = await client.query(
    `SELECT * FROM activities
     WHERE id = $1 AND is_template = false AND assigned_to = $2 AND status = 'approved'
       AND family_id IN (SELECT family_id FROM family_members WHERE user_id = $2 AND status = 'active')
     FOR UPDATE`,
    [instanceId, userId]
  );
  if (!instRows.length) {
    return { error: { code: 404, message: 'Instance not found, not yours, or already completed.' } };
  }
  const inst = instRows[0];
  await client.query(`UPDATE activities SET status = 'completed' WHERE id = $1`, [inst.id]);

  const bountyAmt = inst.bounty_amount || 0;
  const totalAward = (inst.coin_value || 0) + bountyAmt;
  const reason = payoutReasons(inst.type);
  if (totalAward > 0) {
    await client.query(
      `UPDATE family_members SET coin_balance = coin_balance + $1 WHERE family_id = $2 AND user_id = $3`,
      [totalAward, inst.family_id, inst.assigned_to]
    );
    if (inst.coin_value > 0) {
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason) VALUES ($1,$2,$3,$4,$5)`,
        [inst.family_id, inst.assigned_to, inst.id, inst.coin_value, reason.value]
      );
    }
    if (bountyAmt > 0) {
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason) VALUES ($1,$2,$3,$4,$5)`,
        [inst.family_id, inst.assigned_to, inst.id, bountyAmt, reason.bonus]
      );
    }
  }
  return { data: { completed: true, coinsAwarded: totalAward }, inst };
}

export async function validateActivity(client, userId, activityId) {
  const { rows: actRows } = await client.query(
    `SELECT id, family_id, assigned_to, status, type, coin_value, bounty_amount FROM activities WHERE id = $1
     AND family_id IN (SELECT family_id FROM family_members WHERE user_id = $2 AND status = 'active')
     FOR UPDATE`,
    [activityId, userId]
  );
  if (!actRows.length) return { error: { code: 404, message: 'Activity not found.' } };
  const act = actRows[0];
  if (act.status !== 'pending_validation') return { error: { code: 409, message: 'Activity is not pending validation.' } };
  if (act.assigned_to === userId) return { error: { code: 403, message: 'You cannot validate your own retroactive activity.' } };

  await client.query(`UPDATE activities SET status = 'completed' WHERE id = $1`, [act.id]);

  const bountyAmt = act.bounty_amount || 0;
  const totalAward = (act.coin_value || 0) + bountyAmt;
  const reason = payoutReasons(act.type);
  if (totalAward > 0) {
    await client.query(
      `UPDATE family_members SET coin_balance = coin_balance + $1 WHERE family_id = $2 AND user_id = $3`,
      [totalAward, act.family_id, act.assigned_to]
    );
    if (act.coin_value > 0) {
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason) VALUES ($1,$2,$3,$4,$5)`,
        [act.family_id, act.assigned_to, act.id, act.coin_value, reason.value]
      );
    }
    if (bountyAmt > 0) {
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason) VALUES ($1,$2,$3,$4,$5)`,
        [act.family_id, act.assigned_to, act.id, bountyAmt, reason.bonus]
      );
    }
  }
  return { data: { success: true, coinsAwarded: totalAward }, act };
}

export async function offerBounty(client, userId, activityId, bountyAmount) {
  const { rows: actRows } = await client.query(
    `SELECT family_id, assigned_to, starts_at, category, type FROM activities WHERE id = $1
     AND family_id IN (SELECT family_id FROM family_members WHERE user_id = $2 AND status = 'active')
     FOR UPDATE`,
    [activityId, userId]
  );
  if (!actRows.length) return { error: { code: 404, message: 'Activity not found.' } };
  const act = actRows[0];
  // A coverage shift is someone's agreement to cover a specific person's time,
  // and its bounty fields already carry that person's sweetener; personal time
  // is nobody's shift to hand over. Neither can be put up for a bounty.
  if (act.type === 'coverage' || act.category === 'self') {
    return { error: { code: 409, message: 'Coverage and personal time cannot be handed over.' } };
  }
  if (act.assigned_to !== userId) {
    return { error: { code: 403, message: 'Only the assigned caregiver can offer a bounty on this shift.' } };
  }
  const { rows: memRows } = await client.query(
    `SELECT coin_balance FROM family_members WHERE family_id = $1 AND user_id = $2 AND status = 'active'`,
    [act.family_id, userId]
  );
  if (!memRows.length || memRows[0].coin_balance < bountyAmount) {
    return { error: { code: 409, message: 'Insufficient personal coins to offer this bounty.' } };
  }
  await client.query(
    `UPDATE family_members SET coin_balance = coin_balance - $1 WHERE family_id = $2 AND user_id = $3`,
    [bountyAmount, act.family_id, userId]
  );
  await client.query(
    `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason) VALUES ($1,$2,$3,$4,'bounty_escrow')`,
    [act.family_id, userId, activityId, -bountyAmount]
  );
  await client.query(
    `UPDATE activities SET bounty_amount = $1, bounty_offered_by = $2 WHERE id = $3`,
    [bountyAmount, userId, activityId]
  );
  return { data: { success: true }, act, bountyAmount };
}

export async function acceptBounty(client, userId, activityId) {
  const { rows: actRows } = await client.query(
    `SELECT family_id, assigned_to, bounty_amount, bounty_offered_by, status, category, type
     FROM activities WHERE id = $1
     AND family_id IN (SELECT family_id FROM family_members WHERE user_id = $2 AND status = 'active')
     FOR UPDATE`,
    [activityId, userId]
  );
  if (!actRows.length) return { error: { code: 404, message: 'Activity not found.' } };
  const act = actRows[0];
  // A coverage shift's bounty is the requester's sweetener, not an offer:
  // "accepting" it would let them cover their own personal time.
  if (act.type === 'coverage' || act.category === 'self') {
    return { error: { code: 409, message: 'Coverage and personal time cannot be handed over.' } };
  }
  if (act.status === 'completed' || act.status === 'pending_validation') {
    return { error: { code: 409, message: 'Cannot accept bounty for a completed or pending validation activity.' } };
  }
  if (act.assigned_to === userId) return { error: { code: 409, message: 'You already own this shift.' } };
  if (!act.bounty_amount || !act.bounty_offered_by) return { error: { code: 409, message: 'No bounty available.' } };
  await client.query(`UPDATE activities SET assigned_to = $1 WHERE id = $2`, [userId, activityId]);
  return { data: { success: true } };
}

export async function deleteActivity(client, userId, activityId, isSeries) {
  const { rows } = await client.query(
    `SELECT family_id, assigned_to, created_by, status, starts_at,
            bounty_amount, bounty_offered_by, title, category, type, is_template,
            counterpart_activity_id
     FROM activities WHERE id = $1
     AND family_id IN (SELECT family_id FROM family_members WHERE user_id = $2 AND status = 'active')
     FOR UPDATE`,
    [activityId, userId]
  );
  if (!rows.length) return { error: { code: 404, message: 'Activity not found.' } };
  const act = rows[0];

  if (act.is_template) {
    const roleErr = await assertMemberRole(client, userId, act.family_id, 'caregiver');
    if (roleErr && act.created_by !== userId) {
      return { error: { code: 403, message: 'Only caregivers or the creator can delete an activity template.' } };
    }
    await client.query(`DELETE FROM activities WHERE id = $1`, [activityId]);
    return { data: { success: true } };
  }

  // Personal time belongs to the person taking it, and its coverage shift
  // exists only because of it: nobody else may cancel the one, and nobody may
  // remove the other on its own. Cancelling personal time takes its coverage
  // with it. Caregiver rights do not override either rule.
  if (act.type === 'coverage') {
    return { error: { code: 409, message: 'Coverage ends when its personal time is cancelled.' } };
  }
  if (act.category === 'self') {
    if (act.assigned_to !== userId) {
      return { error: { code: 403, message: 'Only the person taking this time can cancel it.' } };
    }
    if (!['approved', 'pending_validation', 'pending'].includes(act.status)) {
      return { error: { code: 409, message: 'Can only un-schedule upcoming activities.' } };
    }
    return cancelPersonalTime(client, act, activityId);
  }

  const caregiverCheck = await assertMemberRole(client, userId, act.family_id, 'caregiver');
  const isCaregiver = !caregiverCheck;
  if (act.assigned_to !== userId && !isCaregiver) {
    return { error: { code: 403, message: 'Cannot delete an activity that is not yours.' } };
  }
  if (!['approved', 'pending_validation', 'pending'].includes(act.status)) {
    return { error: { code: 409, message: 'Can only un-schedule upcoming activities.' } };
  }

  if (isSeries) {
    const { rows: refundRows } = await client.query(`
      SELECT bounty_amount, bounty_offered_by FROM activities
      WHERE family_id = $1 AND title = $2 AND type = $3 AND assigned_to = $4
        AND is_template = false AND is_recurrent = true AND starts_at >= $5
        AND status IN ('approved', 'pending_validation') AND bounty_amount > 0 AND bounty_offered_by IS NOT NULL
    `, [act.family_id, act.title, act.type, act.assigned_to, act.starts_at]);
    for (const refund of refundRows) {
      await client.query(
        `UPDATE family_members SET coin_balance = coin_balance + $1 WHERE family_id = $2 AND user_id = $3`,
        [refund.bounty_amount, act.family_id, refund.bounty_offered_by]
      );
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, amount, reason) VALUES ($1,$2,$3,'bounty_refunded')`,
        [act.family_id, refund.bounty_offered_by, refund.bounty_amount]
      );
    }
    await client.query(`
      DELETE FROM activities
      WHERE family_id = $1 AND title = $2 AND type = $3 AND assigned_to = $4
        AND is_template = false AND is_recurrent = true AND starts_at >= $5
        AND status IN ('approved', 'pending_validation')
    `, [act.family_id, act.title, act.type, act.assigned_to, act.starts_at]);
  } else {
    if (act.bounty_amount > 0 && act.bounty_offered_by) {
      await client.query(
        `UPDATE family_members SET coin_balance = coin_balance + $1 WHERE family_id = $2 AND user_id = $3`,
        [act.bounty_amount, act.family_id, act.bounty_offered_by]
      );
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason) VALUES ($1,$2,$3,$4,'bounty_refunded')`,
        [act.family_id, act.bounty_offered_by, activityId, act.bounty_amount]
      );
    }
    await client.query(`DELETE FROM activities WHERE id = $1`, [activityId]);
  }
  return { data: { success: true } };
}

/**
 * Moves a scheduled activity to a new start, keeping its duration. Who may move
 * it follows the removal rules: the assignee or a caregiver for ordinary work;
 * personal time only by the person taking it, and not once someone has agreed
 * to cover it (they accepted that window); a coverage shift never on its own.
 * The assignee's absences and other work are checked at the new time, with
 * coverage exempt as in scheduleActivity.
 */
export async function rescheduleActivity(client, userId, activityId, startsAt, now = new Date()) {
  const { rows } = await client.query(
    `SELECT family_id, assigned_to, category, type, status, is_template,
            duration_minutes, counterpart_activity_id
     FROM activities WHERE id = $1
     AND family_id IN (SELECT family_id FROM family_members WHERE user_id = $2 AND status = 'active')
     FOR UPDATE`,
    [activityId, userId]
  );
  if (!rows.length || rows[0].is_template) {
    return { error: { code: 404, message: 'Activity not found.' } };
  }
  const act = rows[0];

  if (act.type === 'coverage') {
    return { error: { code: 409, message: 'Coverage moves only with its personal time.' } };
  }
  if (act.category === 'self') {
    if (act.assigned_to !== userId) {
      return { error: { code: 403, message: 'Only the person taking this time can move it.' } };
    }
    if (act.counterpart_activity_id) {
      return { error: { code: 409, message: 'Someone is covering this time. Cancel it and ask again to change it.' } };
    }
  } else if (act.assigned_to !== userId) {
    const roleErr = await assertMemberRole(client, userId, act.family_id, 'caregiver');
    if (roleErr) return { error: { code: 403, message: 'Cannot move an activity that is not yours.' } };
  }
  if (act.status !== 'approved') {
    return { error: { code: 409, message: 'Only upcoming activities can be moved.' } };
  }

  const start = new Date(startsAt);
  if (Number.isNaN(start.getTime()) || start <= now) {
    return { error: { code: 400, message: 'Pick a time that has not passed.' } };
  }
  const end = new Date(start.getTime() + Number(act.duration_minutes) * 60000);

  const { rows: absenceOverlap } = await client.query(
    `SELECT id, title FROM absences
     WHERE user_id = $1 AND family_id = $2 AND (start_time < $4 AND end_time > $3)`,
    [act.assigned_to, act.family_id, start.toISOString(), end.toISOString()]
  );
  if (absenceOverlap.length > 0) {
    return { error: { code: 409, message: `They are away during this time ("${absenceOverlap[0].title}").` } };
  }

  const { rows: overlap } = await client.query(
    `SELECT id, title FROM activities
     WHERE assigned_to = $1 AND family_id = $2 AND is_template = false
       AND id <> $5 AND type <> 'coverage'
       AND status IN ('approved', 'pending_validation')
       AND (starts_at < $4 AND ends_at > $3)`,
    [act.assigned_to, act.family_id, start.toISOString(), end.toISOString(), activityId]
  );
  if (overlap.length > 0) {
    return { error: { code: 409, message: `"${overlap[0].title}" is already scheduled during this time.` } };
  }

  const { rows: updated } = await client.query(
    `UPDATE activities SET starts_at = $1::timestamptz, ends_at = $2::timestamptz
     WHERE id = $3 RETURNING *`,
    [start.toISOString(), end.toISOString(), activityId]
  );
  return { data: updated[0] };
}

/**
 * Deletes a personal-time activity and, when someone accepted to cover it, the
 * coverage shift too, returning the shift's sweetener to the requester: the
 * favour it paid for will not happen. A coverage shift that has already been
 * paid stays, and so does the personal time it covered.
 */
async function cancelPersonalTime(client, act, activityId) {
  if (act.counterpart_activity_id) {
    const { rows } = await client.query(
      `SELECT id, status, bounty_amount, bounty_offered_by FROM activities
       WHERE id = $1 FOR UPDATE`,
      [act.counterpart_activity_id]
    );
    const coverage = rows[0];
    if (coverage) {
      if (!['approved', 'pending_validation', 'pending'].includes(coverage.status)) {
        return { error: { code: 409, message: 'Its coverage has already been paid.' } };
      }
      if (coverage.bounty_amount > 0 && coverage.bounty_offered_by) {
        await client.query(
          `UPDATE family_members SET coin_balance = coin_balance + $1 WHERE family_id = $2 AND user_id = $3`,
          [coverage.bounty_amount, act.family_id, coverage.bounty_offered_by]
        );
        await client.query(
          `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason) VALUES ($1,$2,$3,$4,$5)`,
          [act.family_id, coverage.bounty_offered_by, coverage.id, coverage.bounty_amount,
           payoutReasons('coverage').bonusRefunded]
        );
      }
      await client.query(`DELETE FROM activities WHERE id = $1`, [coverage.id]);
    }
  }
  await client.query(`DELETE FROM activities WHERE id = $1`, [activityId]);
  return { data: { success: true } };
}

export async function revertActivity(client, userId, activityId) {
  const { rows } = await client.query(
    `SELECT family_id, assigned_to, status, type, coin_value, bounty_amount, bounty_offered_by
     FROM activities WHERE id = $1
     AND family_id IN (SELECT family_id FROM family_members WHERE user_id = $2 AND status = 'active')
     FOR UPDATE`,
    [activityId, userId]
  );
  if (!rows.length) return { error: { code: 404, message: 'Activity not found.' } };
  const act = rows[0];
  if (act.assigned_to !== userId) return { error: { code: 403, message: "Cannot revert someone else's completion." } };
  if (act.type === 'coverage') {
    return { error: { code: 409, message: 'Coverage ends when its personal time is cancelled.' } };
  }
  if (act.status !== 'completed') return { error: { code: 409, message: 'Activity is not completed.' } };

  const bountyAmt = act.bounty_amount || 0;
  const totalAward = (act.coin_value || 0) + bountyAmt;
  // The ledger is append-only: the original credit stays and a reversal row
  // is added beside it, so SUM(amount) keeps matching the balances. Rewriting
  // the credit into a debit (as this once did) left the ledger 2x the amount
  // short. A coverage shift files under its own reasons, hence payoutReasons.
  const reason = payoutReasons(act.type);
  if (totalAward > 0) {
    await client.query(
      `UPDATE family_members SET coin_balance = coin_balance - $1 WHERE family_id = $2 AND user_id = $3`,
      [totalAward, act.family_id, userId]
    );
    if (act.coin_value > 0) {
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason) VALUES ($1,$2,$3,$4,$5)`,
        [act.family_id, userId, activityId, -act.coin_value, reason.valueReverted]
      );
    }
    if (bountyAmt > 0) {
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason) VALUES ($1,$2,$3,$4,$5)`,
        [act.family_id, userId, activityId, -bountyAmt, reason.bonusReverted]
      );
      await client.query(
        `UPDATE family_members SET coin_balance = coin_balance + $1 WHERE family_id = $2 AND user_id = $3`,
        [bountyAmt, act.family_id, act.bounty_offered_by]
      );
      await client.query(
        `INSERT INTO coin_ledger (family_id, user_id, activity_id, amount, reason) VALUES ($1,$2,$3,$4,$5)`,
        [act.family_id, act.bounty_offered_by, activityId, bountyAmt, reason.bonusRefunded]
      );
    }
  }
  await client.query(`UPDATE activities SET status = 'rejected' WHERE id = $1`, [activityId]);
  return { data: { success: true, coinsDeducted: totalAward } };
}

import { runAutoCompleteSweep, RUNNING_CAP_MINUTES } from '../db/autoComplete.js';
import { rankTemplates } from '../utils/trayRanking.js';
import * as activityService from './activityService.js';
import { serviceError } from '../utils/httpError.js';

const CLIENT_REF_REGEX = /^[A-Za-z0-9-]{8,64}$/;

function isValidClientRef(ref) {
  return typeof ref === 'string' && CLIENT_REF_REGEX.test(ref);
}

export async function getQuick(client, userId, familyId) {
  await runAutoCompleteSweep(client, familyId);

  const { rows: famRows } = await client.query(
    `SELECT f.id, f.name, COALESCE(fm.coin_balance, 0)::int AS balance
     FROM families f
     JOIN family_members fm ON fm.family_id = f.id AND fm.user_id = $2
     WHERE f.id = $1`,
    [familyId, userId]
  );
  if (!famRows.length) {
    return serviceError(403, 'familyNotMember', 'Not a family member.');
  }
  const fam = famRows[0];

  const { rows: needsYouRows } = await client.query(
    `SELECT (
       (SELECT COUNT(*)::int FROM activities
        WHERE family_id = $1 AND is_template = false AND status = 'pending_validation'
          AND (assigned_to IS NULL OR assigned_to <> $2))
       +
       (SELECT COUNT(*)::int FROM activities
        WHERE family_id = $1 AND is_template = true AND status = 'pending')
     ) AS count`,
    [familyId, userId]
  );
  const needsYou = Number(needsYouRows[0]?.count || 0);

  const { rows: templateRows } = await client.query(
    `SELECT id, title, type, duration_minutes, coin_value, category
     FROM activities
     WHERE family_id = $1 AND is_template = true AND status = 'approved'
       AND category = 'care' AND type IN ('care', 'household')`,
    [familyId]
  );

  const { rows: instanceRows } = await client.query(
    `SELECT title, type, category, status, starts_at, assigned_to, is_template
     FROM activities
     WHERE family_id = $1 AND assigned_to = $2 AND is_template = false AND category = 'care'
       AND starts_at >= NOW() - interval '60 days'
       AND starts_at <= NOW() + interval '14 days'`,
    [familyId, userId]
  );

  const ranked = rankTemplates({
    templates: templateRows,
    activities: instanceRows,
    userId,
    now: new Date(),
  });

  const tasks = ranked.quick.slice(0, 8).map((t) => ({
    id: t.id,
    title: t.title,
    type: t.type,
    durationMinutes: t.duration_minutes,
    coinValue: t.coin_value,
  }));

  const { rows: upcomingRows } = await client.query(
    `SELECT id, title, type, starts_at, ends_at, status
     FROM activities
     WHERE family_id = $1 AND assigned_to = $2 AND is_template = false AND category = 'care'
       AND status IN ('approved', 'pending_validation')
       AND running_since IS NULL
       AND starts_at BETWEEN NOW() - interval '2 hours' AND NOW() + interval '24 hours'
     ORDER BY starts_at ASC`,
    [familyId, userId]
  );

  const upcoming = upcomingRows.map((r) => ({
    id: r.id,
    title: r.title,
    type: r.type,
    startsAt: r.starts_at instanceof Date ? r.starts_at.toISOString() : new Date(r.starts_at).toISOString(),
    endsAt: r.ends_at instanceof Date ? r.ends_at.toISOString() : (r.ends_at ? new Date(r.ends_at).toISOString() : null),
    status: r.status,
  }));

  const { rows: runningRows } = await client.query(
    `SELECT id, title, type, running_since, client_ref
     FROM activities
     WHERE family_id = $1 AND assigned_to = $2 AND running_since IS NOT NULL
     LIMIT 1`,
    [familyId, userId]
  );

  const running = runningRows.length
    ? {
        id: runningRows[0].id,
        title: runningRows[0].title,
        type: runningRows[0].type,
        startedAt:
          runningRows[0].running_since instanceof Date
            ? runningRows[0].running_since.toISOString()
            : new Date(runningRows[0].running_since).toISOString(),
        clientRef: runningRows[0].client_ref,
      }
    : null;

  return {
    data: {
      family: { id: fam.id, name: fam.name },
      balance: fam.balance,
      needsYou,
      tasks,
      upcoming,
      running,
      serverTime: new Date().toISOString(),
    },
  };
}

export async function start(client, userId, familyId, { templateId, type, title, clientRef, now = new Date() }) {
  if (!isValidClientRef(clientRef)) {
    return serviceError(400, 'quickClientRefRequired', 'clientRef is required.');
  }

  const hasTemplate = templateId != null;
  const hasType = type != null;
  if ((hasTemplate && hasType) || (!hasTemplate && !hasType)) {
    return serviceError(400, 'quickStartInvalid', 'Choose a task or a type.');
  }

  const { rows: existingRows } = await client.query(
    `SELECT * FROM activities WHERE assigned_to = $1 AND client_ref = $2`,
    [userId, clientRef]
  );
  if (existingRows.length) {
    return { data: { activity: existingRows[0], replayed: true } };
  }

  if (hasTemplate) {
    const { rows: tmplRows } = await client.query(
      `SELECT * FROM activities
       WHERE id = $1 AND is_template = true AND status = 'approved' AND family_id = $2`,
      [templateId, familyId]
    );
    if (!tmplRows.length) {
      return serviceError(404, 'activityApprovedTemplateNotFound', 'Approved activity template not found.');
    }

    const schedIso = (now instanceof Date ? now : new Date(now)).toISOString();
    const sched = await activityService.scheduleActivity(client, userId, templateId, schedIso);
    if (sched.error) return sched;

    const { rows: updatedRows } = await client.query(
      `UPDATE activities SET client_ref = $1 WHERE id = $2 RETURNING *`,
      [clientRef, sched.data.id]
    );

    return {
      data: {
        activity: updatedRows[0] || sched.data,
        ...(sched.warning && { warning: sched.warning }),
      },
    };
  }

  const trimmedTitle = typeof title === 'string' ? title.trim() : '';
  if (!trimmedTitle || trimmedTitle.length > 100 || !['care', 'household'].includes(type)) {
    return serviceError(400, 'quickStartInvalid', 'Choose a task or a type.');
  }

  const { rows: runningRows } = await client.query(
    `SELECT id, title FROM activities WHERE assigned_to = $1 AND running_since IS NOT NULL`,
    [userId]
  );
  if (runningRows.length) {
    return serviceError(409, 'quickTaskAlreadyRunning', 'You already have a task running.', {
      title: runningRows[0].title,
    });
  }

  const startDate = now instanceof Date ? now : new Date(now);
  const endsAtDate = new Date(startDate.getTime() + 15 * 60000);

  const { rows: absenceOverlap } = await client.query(
    `SELECT id, title FROM absences
     WHERE user_id = $1 AND family_id = $2 AND (start_time < $4 AND end_time > $3)`,
    [userId, familyId, startDate.toISOString(), endsAtDate.toISOString()]
  );
  if (absenceOverlap.length > 0) {
    return serviceError(
      400,
      'absentDuringTime',
      `You are marked as absent during this time ("${absenceOverlap[0].title}").`,
      { title: absenceOverlap[0].title }
    );
  }

  const { rows: selfOverlap } = await client.query(
    `SELECT id, title FROM activities
     WHERE assigned_to = $1 AND family_id = $2 AND is_template = false
       AND type <> 'coverage'
       AND status IN ('approved', 'pending_validation')
       AND (starts_at < $4 AND ends_at > $3)`,
    [userId, familyId, startDate.toISOString(), endsAtDate.toISOString()]
  );
  if (selfOverlap.length > 0) {
    return serviceError(
      409,
      'scheduleOverlap',
      `You already have "${selfOverlap[0].title}" scheduled during this time.`,
      { title: selfOverlap[0].title }
    );
  }

  const { rows: insertRows } = await client.query(
    `INSERT INTO activities (family_id, created_by, assigned_to, title, category, type,
       starts_at, ends_at, duration_minutes, coin_value, status, is_template, is_recurrent,
       running_since, client_ref)
     VALUES ($1,$2,$2,$3,'care',$4, NOW(), NOW() + interval '15 minutes', 15, 15, 'approved',
       false, false, NOW(), $5)
     RETURNING *`,
    [familyId, userId, trimmedTitle, type, clientRef]
  );

  return { data: { activity: insertRows[0] } };
}

export async function done(client, userId, familyId, { templateId, activityId, clientRef, now = new Date() }) {
  const hasTemplate = templateId != null;
  const hasActivity = activityId != null;
  if ((hasTemplate && hasActivity) || (!hasTemplate && !hasActivity)) {
    return serviceError(400, 'quickStartInvalid', 'Choose a task or a type.');
  }

  if (hasTemplate) {
    if (!isValidClientRef(clientRef)) {
      return serviceError(400, 'quickClientRefRequired', 'clientRef is required.');
    }

    const { rows: existingRows } = await client.query(
      `SELECT * FROM activities WHERE assigned_to = $1 AND client_ref = $2`,
      [userId, clientRef]
    );
    if (existingRows.length) {
      return { data: { activity: existingRows[0], replayed: true } };
    }

    const { rows: tmplRows } = await client.query(
      `SELECT * FROM activities
       WHERE id = $1 AND is_template = true AND status = 'approved' AND family_id = $2`,
      [templateId, familyId]
    );
    if (!tmplRows.length) {
      return serviceError(404, 'activityApprovedTemplateNotFound', 'Approved activity template not found.');
    }
    const tmpl = tmplRows[0];

    const nowDate = now instanceof Date ? now : new Date(now);
    const startsAt = new Date(nowDate.getTime() - Number(tmpl.duration_minutes) * 60000).toISOString();

    const sched = await activityService.scheduleActivity(client, userId, templateId, startsAt);
    if (sched.error) return sched;

    const { rows: updatedRows } = await client.query(
      `UPDATE activities SET client_ref = $1 WHERE id = $2 RETURNING *`,
      [clientRef, sched.data.id]
    );

    return {
      data: {
        activity: updatedRows[0] || sched.data,
        ...(sched.warning && { warning: sched.warning }),
      },
    };
  }

  if (clientRef) {
    const { rows: existingRows } = await client.query(
      `SELECT * FROM activities WHERE assigned_to = $1 AND client_ref = $2`,
      [userId, clientRef]
    );
    if (existingRows.length) {
      return { data: { activity: existingRows[0], replayed: true } };
    }
  }

  const { rows: actRows } = await client.query(
    `SELECT id, running_since, status FROM activities
     WHERE id = $1 AND family_id = $2 AND assigned_to = $3 AND is_template = false`,
    [activityId, familyId, userId]
  );
  if (!actRows.length) {
    return serviceError(404, 'activityInstanceNotFoundOrCompleted', 'Instance not found, not yours, or already completed.');
  }

  const act = actRows[0];
  if (act.running_since != null) {
    return stop(client, userId, familyId, { activityId, now });
  }

  if (clientRef) {
    await client.query(`UPDATE activities SET client_ref = $1 WHERE id = $2`, [clientRef, activityId]);
  }

  return activityService.completeActivity(client, userId, activityId);
}

export async function stop(client, userId, familyId, { activityId, now = new Date() }) {
  const { rows } = await client.query(
    `SELECT * FROM activities
     WHERE id = $1 AND assigned_to = $2 AND family_id = $3 AND running_since IS NOT NULL
     FOR UPDATE`,
    [activityId, userId, familyId]
  );
  if (!rows.length) {
    return serviceError(409, 'quickTaskNotRunning', 'This task is not running.');
  }
  const act = rows[0];

  const nowDate = now instanceof Date ? now : new Date(now);
  const startMs = new Date(act.starts_at).getTime();
  const diffMinutes = Math.max(0, (nowDate.getTime() - startMs) / 60000);
  let elapsed = Math.ceil(diffMinutes / 15) * 15;
  if (elapsed < 15) elapsed = 15;
  if (elapsed > RUNNING_CAP_MINUTES) elapsed = RUNNING_CAP_MINUTES;

  await client.query(
    `UPDATE activities SET running_since = NULL, ends_at = starts_at + make_interval(mins => $2),
           duration_minutes = $2, coin_value = $2 WHERE id = $1`,
    [activityId, elapsed]
  );

  return activityService.completeActivity(client, userId, activityId);
}

export async function undo(client, userId, familyId, { clientRef }) {
  const { rows } = await client.query(
    `SELECT id, status FROM activities
     WHERE assigned_to = $1 AND family_id = $2 AND client_ref = $3
       AND created_at >= NOW() - interval '60 seconds'`,
    [userId, familyId, clientRef]
  );
  if (!rows.length) {
    return serviceError(409, 'quickUndoExpired', 'Too late to undo. Change it in the app.');
  }
  const act = rows[0];

  if (act.status === 'completed') {
    const rev = await activityService.revertActivity(client, userId, act.id);
    if (rev.error) return rev;
    return { data: { undone: true } };
  }

  const del = await activityService.deleteActivity(client, userId, act.id, false);
  if (del.error) return del;
  return { data: { undone: true } };
}

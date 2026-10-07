import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { upsertUserFromAuth } from '../db/users.js';
import { validateBody, validateParams, required, string, positiveInt, isoDate, oneOf } from '../middleware/validate.js';
import { notifyUser, notifyFamilyCaregivers, notifyFamilyAll } from '../utils/notify.js';
import * as activityService from '../services/activityService.js';

export const activitiesRouter = Router();

activitiesRouter.get('/', async (req, res) => {
  const familyId = Number(req.query.familyId);
  if (!familyId) return res.status(400).json({ error: 'familyId query param is required.' });
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.listActivities(client, user.id, familyId);
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    return res.json(result.data);
  } catch (err) {
    console.error('GET /activities error:', err);
    return res.status(500).json({ error: 'Failed to fetch activities.' });
  }
});

activitiesRouter.post('/', validateBody({
  familyId: [required(), positiveInt()],
  title: [required(), string(1, 100)],
  type: [required(), oneOf(['care', 'household'])],
  durationMinutes: [required(), positiveInt()],
  coinValue: [positiveInt()],
}), async (req, res) => {
  const { familyId, title, type, durationMinutes, coinValue, isRecurrent } = req.body;
  if (Number(durationMinutes) < 15) {
    return res.status(400).json({ error: 'Minimum duration is 15 minutes.' });
  }
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.createActivity(client, user.id, { familyId, title, type, durationMinutes, coinValue, isRecurrent });
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    notifyFamilyCaregivers(result.data.family_id, result.data.created_by, {
      title: 'New activity pending approval',
      body: `"${result.data.title}" needs your review.`,
      url: '/activities',
      prefKey: 'activity_assigned',
    });
    return res.status(201).json({ activity: result.data });
  } catch (err) {
    console.error('POST /activities error:', err);
    return res.status(500).json({ error: 'Failed to create activity.' });
  }
});

activitiesRouter.post('/:activityId/approve', validateParams('activityId'), async (req, res) => {
  const activityId = Number(req.params.activityId);
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.approveActivity(client, user.id, activityId);
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    return res.status(200).json(result.data);
  } catch (err) {
    console.error('POST /approve error:', err);
    return res.status(500).json({ error: 'Failed to approve activity.' });
  }
});

activitiesRouter.post('/:activityId/schedule', validateParams('activityId'), validateBody({
  startsAt: [required(), isoDate()],
}), async (req, res) => {
  const activityId = Number(req.params.activityId);
  const { startsAt } = req.body;
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.scheduleActivity(client, user.id, activityId, startsAt);
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    const act = result.data;
    if (act.assigned_to) {
      const when = new Date(act.starts_at).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
      notifyUser(act.assigned_to, {
        title: 'Activity scheduled for you',
        body: `"${act.title}" starts at ${when}.`,
        url: '/activities',
        prefKey: 'activity_assigned',
      });
    }
    if (act.status === 'pending_validation') {
      notifyFamilyCaregivers(act.family_id, act.assigned_to, {
        title: 'Activity needs validation',
        body: `"${act.title}" was added in the past and needs your approval.`,
        url: '/activities',
        prefKey: 'activity_assigned',
      });
    }
    return res.status(201).json({ activity: act, warning: result.warning });
  } catch (err) {
    console.error('POST /schedule error:', err);
    return res.status(500).json({ error: 'Failed to schedule activity.' });
  }
});

activitiesRouter.patch('/:id/time', validateParams('id'), validateBody({
  startsAt: [required(), isoDate()],
}), async (req, res) => {
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.rescheduleActivity(client, user.id, Number(req.params.id), req.body.startsAt);
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    return res.json({ activity: result.data });
  } catch (err) {
    console.error('PATCH /:id/time error:', err);
    return res.status(500).json({ error: 'Failed to move activity.' });
  }
});

activitiesRouter.post('/:activityId/recurrence', validateParams('activityId'), validateBody({
  frequency: [required(), oneOf(['daily', 'weekdays', 'weekly'])],
  untilDate: [required(), isoDate()],
}), async (req, res) => {
  const instanceId = Number(req.params.activityId);
  const { frequency, untilDate } = req.body;
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.createRecurrence(client, user.id, instanceId, { frequency, untilDate });
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    return res.status(201).json(result.data);
  } catch (err) {
    console.error('POST /recurrence error:', err);
    return res.status(500).json({ error: 'Failed to create recurrences.' });
  }
});

activitiesRouter.post('/:activityId/complete', validateParams('activityId'), async (req, res) => {
  const instanceId = Number(req.params.activityId);
  if (!instanceId) return res.status(400).json({ error: 'Invalid activityId.' });
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.completeActivity(client, user.id, instanceId);
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    notifyFamilyAll(result.inst.family_id, result.inst.assigned_to, {
      title: 'Activity completed',
      body: `"${result.inst.title}" has just been completed.`,
      url: '/activities',
      prefKey: 'activity_completed',
    });
    return res.status(200).json(result.data);
  } catch (err) {
    console.error('POST /complete error:', err);
    return res.status(500).json({ error: 'Failed to complete activity.' });
  }
});

activitiesRouter.post('/:id/validate', validateParams('id'), async (req, res) => {
  const activityId = Number(req.params.id);
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.validateActivity(client, user.id, activityId);
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    notifyUser(result.act.assigned_to, {
      title: 'Activity validated!',
      body: `Your activity was approved. You earned ${result.data.coinsAwarded} coins.`,
      url: '/dashboard',
      prefKey: 'activity_validated',
    });
    return res.json(result.data);
  } catch (err) {
    console.error('POST /validate error:', err);
    return res.status(500).json({ error: 'Failed to validate activity.' });
  }
});

activitiesRouter.post('/:id/bounty', validateParams('id'), async (req, res) => {
  const activityId = Number(req.params.id);
  const bountyAmount = Number(req.body.bountyAmount);
  if (!activityId || !bountyAmount || bountyAmount <= 0) {
    return res.status(400).json({ error: 'Valid bountyAmount required.' });
  }
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.offerBounty(client, user.id, activityId, bountyAmount);
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    notifyFamilyAll(result.act.family_id, result.act.assigned_to, {
      title: 'Bounty offered on a shift!',
      body: `Someone is offering ${result.bountyAmount} coins for someone to take their activity.`,
      url: '/activities',
      prefKey: 'bounty_offered',
    });
    return res.json(result.data);
  } catch (err) {
    console.error('POST /bounty error:', err);
    return res.status(500).json({ error: 'Failed to post bounty.' });
  }
});

activitiesRouter.post('/:id/accept-bounty', validateParams('id'), async (req, res) => {
  const activityId = Number(req.params.id);
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.acceptBounty(client, user.id, activityId);
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    return res.json(result.data);
  } catch (err) {
    console.error('POST /accept-bounty error:', err);
    return res.status(500).json({ error: 'Failed to accept bounty.' });
  }
});

activitiesRouter.delete('/:id', validateParams('id'), async (req, res) => {
  const activityId = Number(req.params.id);
  const isSeries = req.query.series === 'true';
  if (!activityId) return res.status(400).json({ error: 'Valid activity ID required.' });
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.deleteActivity(client, user.id, activityId, isSeries);
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    return res.json(result.data);
  } catch (err) {
    console.error('DELETE /activities error:', err);
    return res.status(500).json({ error: 'Failed to delete activity.' });
  }
});

activitiesRouter.post('/:id/revert', validateParams('id'), async (req, res) => {
  const activityId = Number(req.params.id);
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return activityService.revertActivity(client, user.id, activityId);
    });
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    return res.json(result.data);
  } catch (err) {
    console.error('POST /revert error:', err);
    return res.status(500).json({ error: 'Failed to revert completion.' });
  }
});

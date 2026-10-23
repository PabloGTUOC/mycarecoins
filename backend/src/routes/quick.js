import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { upsertUserFromAuth } from '../db/users.js';
import { validateBody, required, string, positiveInt, oneOf } from '../middleware/validate.js';
import { notifyFamilyCaregivers, notifyFamilyAll } from '../utils/notify.js';
import * as quickService from '../services/quickService.js';
import { sendServiceError, sendError } from '../utils/httpError.js';

export const quickRouter = Router();

quickRouter.use((req, _res, next) => {
  req.body = req.body || {};
  if (req.device?.familyId) {
    req.body.familyId = req.device.familyId;
  }
  next();
});

quickRouter.get('/', async (req, res) => {
  const familyId = req.device.familyId;
  req.body.familyId = familyId;
  try {
    const runner = req._withTransaction || withTransaction;
    const result = await runner(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return quickService.getQuick(client, user.id, familyId);
    });
    if (result.error) return sendServiceError(res, result.error);
    return res.status(200).json(result.data);
  } catch (err) {
    console.error('GET /api/quick error:', err);
    return sendError(res, 500, 'internal', 'Internal server error.');
  }
});

quickRouter.post('/start', validateBody({
  clientRef: [required(), string(8, 64)],
  templateId: [positiveInt()],
  type: [oneOf(['care', 'household'])],
  title: [string(1, 100)],
}), async (req, res) => {
  const familyId = req.device.familyId;
  req.body.familyId = familyId;
  const { clientRef, templateId, type, title } = req.body;
  try {
    const runner = req._withTransaction || withTransaction;
    const result = await runner(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return quickService.start(client, user.id, familyId, { clientRef, templateId, type, title });
    });
    if (result.error) return sendServiceError(res, result.error);

    const act = result.data?.activity;
    if (act && !result.data?.replayed) {
      if (act.status === 'pending_validation') {
        notifyFamilyCaregivers(act.family_id, act.assigned_to, {
          title: 'Activity needs validation',
          body: `"${act.title}" was added in the past and needs your approval.`,
          url: '/activities',
          prefKey: 'activity_assigned',
        });
      }
    }

    return res.status(201).json(result.data);
  } catch (err) {
    console.error('POST /api/quick/start error:', err);
    return sendError(res, 500, 'internal', 'Internal server error.');
  }
});

quickRouter.post('/done', validateBody({
  clientRef: [string(8, 64)],
  templateId: [positiveInt()],
  activityId: [positiveInt()],
}), async (req, res) => {
  const familyId = req.device.familyId;
  req.body.familyId = familyId;
  const { clientRef, templateId, activityId } = req.body;

  if (templateId && !clientRef) {
    return sendError(res, 400, 'quickClientRefRequired', 'clientRef is required.');
  }

  try {
    const runner = req._withTransaction || withTransaction;
    const result = await runner(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return quickService.done(client, user.id, familyId, { clientRef, templateId, activityId });
    });
    if (result.error) return sendServiceError(res, result.error);

    const act = result.data?.activity;
    if (act && !result.data?.replayed) {
      if (act.status === 'pending_validation') {
        notifyFamilyCaregivers(act.family_id, act.assigned_to, {
          title: 'Activity needs validation',
          body: `"${act.title}" was added in the past and needs your approval.`,
          url: '/activities',
          prefKey: 'activity_assigned',
        });
      } else if (act.status === 'completed') {
        notifyFamilyAll(act.family_id, act.assigned_to, {
          title: 'Activity completed',
          body: `"${act.title}" has just been completed.`,
          url: '/activities',
          prefKey: 'activity_completed',
        });
      }
    }

    if (result.inst) {
      notifyFamilyAll(result.inst.family_id, result.inst.assigned_to, {
        title: 'Activity completed',
        body: `"${result.inst.title}" has just been completed.`,
        url: '/activities',
        prefKey: 'activity_completed',
      });
    }

    return res.status(200).json(result.data);
  } catch (err) {
    console.error('POST /api/quick/done error:', err);
    return sendError(res, 500, 'internal', 'Internal server error.');
  }
});

quickRouter.post('/stop', validateBody({
  activityId: [required(), positiveInt()],
}), async (req, res) => {
  const familyId = req.device.familyId;
  req.body.familyId = familyId;
  const activityId = Number(req.body.activityId);
  try {
    const runner = req._withTransaction || withTransaction;
    const result = await runner(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return quickService.stop(client, user.id, familyId, { activityId });
    });
    if (result.error) return sendServiceError(res, result.error);

    if (result.inst) {
      notifyFamilyAll(result.inst.family_id, result.inst.assigned_to, {
        title: 'Activity completed',
        body: `"${result.inst.title}" has just been completed.`,
        url: '/activities',
        prefKey: 'activity_completed',
      });
    }

    return res.status(200).json(result.data);
  } catch (err) {
    console.error('POST /api/quick/stop error:', err);
    return sendError(res, 500, 'internal', 'Internal server error.');
  }
});

quickRouter.post('/undo', validateBody({
  clientRef: [required(), string(8, 64)],
}), async (req, res) => {
  const familyId = req.device.familyId;
  req.body.familyId = familyId;
  const { clientRef } = req.body;
  try {
    const runner = req._withTransaction || withTransaction;
    const result = await runner(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return quickService.undo(client, user.id, familyId, { clientRef });
    });
    if (result.error) return sendServiceError(res, result.error);
    return res.status(200).json(result.data);
  } catch (err) {
    console.error('POST /api/quick/undo error:', err);
    return sendError(res, 500, 'internal', 'Internal server error.');
  }
});

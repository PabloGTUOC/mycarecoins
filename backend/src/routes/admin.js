/**
 * Platform admin API (docs/admin-family-management-plan.md).
 *
 * Mounted twice while the console moves out of the app
 * (docs/management-platform-plan.md):
 *   app.js:       app.use('/api/admin', requireAuth, adminLimiter, requireAdmin, adminRouter)
 *   admin/app.js: '/admin-api', behind the Access check, auth and requireOperator
 * so every handler here can assume req.auth and req.adminUser are set, and
 * must only touch what the carecoins_admin database role can reach.
 *
 * PRIVACY BOUNDARY: handlers expose family registry + billing state only —
 * never family internals. See src/services/adminService.js.
 */
import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { validateBody, validateParams, required, string, oneOf, isoDate } from '../middleware/validate.js';
import * as adminService from '../services/adminService.js';

export const adminRouter = Router();

// Self-check for admin clients: confirms the caller passed requireAdmin.
// The Flutter shell uses this to gate the admin section (server remains
// authoritative on every real endpoint regardless).
adminRouter.get('/status', (req, res) => {
  res.json({ ok: true, adminId: req.adminUser.id });
});

adminRouter.get('/families', async (req, res) => {
  const { search, status, page, pageSize } = req.query;
  try {
    const result = await withTransaction((client) =>
      adminService.listFamilies(client, { search, status, page, pageSize }));
    return res.json(result.data);
  } catch (err) {
    console.error('Admin family list failed:', err);
    return res.status(500).json({ error: 'Failed to list families.' });
  }
});

adminRouter.get('/families/:familyId', validateParams('familyId'), async (req, res) => {
  const familyId = Number(req.params.familyId);
  try {
    const result = await withTransaction((client) =>
      adminService.getFamilyRegistry(client, familyId));
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    return res.json(result.data);
  } catch (err) {
    console.error('Admin family detail failed:', err);
    return res.status(500).json({ error: 'Failed to fetch family.' });
  }
});

// ─── Plan catalog ────────────────────────────────────────────────────────────

adminRouter.get('/plans', async (_req, res) => {
  try {
    const result = await withTransaction((client) => adminService.listPlans(client));
    return res.json(result.data);
  } catch (err) {
    console.error('Admin plan list failed:', err);
    return res.status(500).json({ error: 'Failed to list plans.' });
  }
});

adminRouter.post('/plans',
  validateBody({
    code: [required(), string(1, 40)],
    name: [required(), string(1, 100)],
    billingPeriod: [oneOf(['monthly', 'yearly'])],
  }),
  async (req, res) => {
    try {
      const result = await withTransaction((client) =>
        adminService.createPlan(client, req.adminUser.id, req.body));
      if (result.error) return res.status(result.error.code).json({ error: result.error.message });
      return res.status(201).json(result.data);
    } catch (err) {
      console.error('Admin plan create failed:', err);
      return res.status(500).json({ error: 'Failed to create plan.' });
    }
  });

adminRouter.patch('/plans/:code',
  validateBody({
    name: [string(1, 100)],
    billingPeriod: [oneOf(['monthly', 'yearly'])],
  }),
  async (req, res) => {
    try {
      const result = await withTransaction((client) =>
        adminService.updatePlan(client, req.adminUser.id, req.params.code, req.body));
      if (result.error) return res.status(result.error.code).json({ error: result.error.message });
      return res.json(result.data);
    } catch (err) {
      console.error('Admin plan update failed:', err);
      return res.status(500).json({ error: 'Failed to update plan.' });
    }
  });

// ─── Family billing & grants ─────────────────────────────────────────────────

adminRouter.get('/families/:familyId/billing', validateParams('familyId'), async (req, res) => {
  const familyId = Number(req.params.familyId);
  try {
    const result = await withTransaction((client) =>
      adminService.getFamilyBilling(client, familyId));
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    return res.json(result.data);
  } catch (err) {
    console.error('Admin billing view failed:', err);
    return res.status(500).json({ error: 'Failed to fetch billing.' });
  }
});

adminRouter.post('/families/:familyId/grants',
  validateParams('familyId'),
  validateBody({
    planCode: [required(), string(1, 40)],
    reason: [string(1, 300)],
    expiresAt: [isoDate()],
  }),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    try {
      const result = await withTransaction((client) =>
        adminService.createGrant(client, req.adminUser.id, familyId, req.body));
      if (result.error) return res.status(result.error.code).json({ error: result.error.message });
      return res.status(201).json(result.data);
    } catch (err) {
      console.error('Admin grant create failed:', err);
      return res.status(500).json({ error: 'Failed to create grant.' });
    }
  });

adminRouter.delete('/families/:familyId/grants/:grantId',
  validateParams('familyId', 'grantId'),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    const grantId = Number(req.params.grantId);
    try {
      const result = await withTransaction((client) =>
        adminService.revokeGrant(client, req.adminUser.id, familyId, grantId));
      if (result.error) return res.status(result.error.code).json({ error: result.error.message });
      return res.json(result.data);
    } catch (err) {
      console.error('Admin grant revoke failed:', err);
      return res.status(500).json({ error: 'Failed to revoke grant.' });
    }
  });

adminRouter.post('/families/:familyId/notify-inactive', validateParams('familyId'), async (req, res) => {
  const familyId = Number(req.params.familyId);
  try {
    const result = await withTransaction((client) =>
      adminService.requestInactivityNotice(client, req.adminUser.id, familyId));
    if (result.error) return res.status(result.error.code).json({ error: result.error.message });
    // The push is queued, not sent here: see src/services/noticeOutbox.js.
    return res.json(result.data);
  } catch (err) {
    console.error('Admin inactivity notice failed:', err);
    return res.status(500).json({ error: 'Failed to send inactivity notice.' });
  }
});

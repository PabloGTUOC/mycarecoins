/**
 * The operator console's API (docs/management-platform-plan.md).
 *
 * A separate Express app and process from the public API (src/app.js), run as
 * the admin-api container and reached only through admin-web's nginx at
 * /admin-api. It connects to Postgres as carecoins_admin, so every query here
 * is limited to the views and billing tables that role is granted
 * (scripts/admin-role.js). src/app.js must never import from this folder.
 *
 * Every request passes, in order: the Cloudflare Access token, a Firebase ID
 * token, the per-operator rate limit, the operator check, and, for changes, a
 * recent sign-in.
 */
import express from 'express';
import rateLimit from 'express-rate-limit';
import { requireAuth } from '../middleware/auth.js';
import { adminRouter } from '../routes/admin.js';
import { sendError } from '../utils/httpError.js';
import { requireAccess } from './access.js';
import { requireOperator, requireRecentSignIn } from './operator.js';

import { Router } from 'express';
import { validateParams } from '../middleware/validate.js';
import { resetGrantRcSync } from '../services/adminService.js';
import { syncPending } from './rcSync.js';

export function createOperatorLimiter({
  max = 300,
  windowMs = 15 * 60 * 1000,
} = {}) {
  return rateLimit({
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    keyGenerator: (req) => req.auth?.uid,
    handler: (_req, res) => {
      sendError(res, 429, 'rateLimited', 'Too many requests. Please try again later.');
    },
  });
}

export function createAdminApp({
  db,
  verifyAccess = null,
  authenticate = requireAuth,
  now = () => Date.now(),
  operatorLimiter = null,
  rc = null,
  rcConfig = null,
} = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json());

  app.get('/health', (_req, res) => {
    res.status(200).json({ status: 'ok', service: 'carecoins-admin-api' });
  });

  const limiter = operatorLimiter ?? createOperatorLimiter();

  const consoleRouter = Router();
  consoleRouter.use(adminRouter);

  consoleRouter.post(
    '/families/:familyId/grants/:grantId/rc-sync',
    validateParams('familyId', 'grantId'),
    async (req, res) => {
      const familyId = Number(req.params.familyId);
      const grantId = Number(req.params.grantId);

      const client = typeof db.connect === 'function' ? await db.connect() : db;
      let resetResult;
      try {
        await client.query('BEGIN');
        resetResult = await resetGrantRcSync(client, req.adminUser.id, familyId, grantId);
        if (resetResult.error) {
          await client.query('ROLLBACK');
          return sendError(res, resetResult.error.code, 'notFound', resetResult.error.message);
        }
        await client.query('COMMIT');
      } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        console.error('Failed to reset RC sync row:', err);
        return sendError(res, 500, 'internal', 'Failed to retry sync.');
      } finally {
        if (typeof client.release === 'function') client.release();
      }

      if (!rcConfig || !rc) {
        return res.json({ status: 'pending', mirror: 'off' });
      }

      try {
        await syncPending(db, rc, {
          entitlementId: rcConfig.entitlementId,
          now,
          grantId,
        });

        const checkClient = typeof db.connect === 'function' ? await db.connect() : db;
        try {
          const { rows } = await checkClient.query(
            `SELECT status, attempts, last_error, synced_at FROM admin_rc_sync WHERE grant_id = $1`,
            [grantId]
          );
          const current = rows[0];
          return res.json({
            status: current?.status ?? 'pending',
            attempts: Number(current?.attempts ?? 0),
            lastError: current?.last_error ?? null,
            syncedAt: current?.synced_at ?? null,
          });
        } finally {
          if (typeof checkClient.release === 'function') checkClient.release();
        }
      } catch (err) {
        console.error('Error running syncPending on retry:', err);
        return sendError(res, 500, 'internal', 'Failed to retry sync.');
      }
    }
  );

  app.use('/admin-api',
    requireAccess(verifyAccess),
    authenticate,
    limiter,
    requireOperator(db),
    requireRecentSignIn(undefined, now),
    consoleRouter);

  app.use((_req, res) => {
    sendError(res, 404, 'notFound', 'Not found.');
  });

  app.use((err, _req, res, _next) => {
    console.error(err);
    sendError(res, 500, 'internal', 'Internal server error.');
  });

  return app;
}

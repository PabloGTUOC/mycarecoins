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
import { logAdminAction, resetGrantRcSync } from '../services/adminService.js';
import { syncPending } from './rcSync.js';
import { AppStoreError } from './appstore.js';

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
  appStore = null,
  appStoreConfig = null,
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

  let catalogCache = null;

  consoleRouter.get('/appstore/catalog', async (req, res) => {
    if (!appStoreConfig?.connect || !appStore?.connect) {
      return sendError(res, 503, 'appStoreNotConfigured', 'App Store API is not configured.');
    }

    const nowMs = typeof now === 'function' ? now() : Date.now();
    const bypassCache = req.query.refresh === '1';

    if (!bypassCache && catalogCache && (nowMs - catalogCache.timestamp < 10 * 60 * 1000)) {
      return res.json(catalogCache.data);
    }

    try {
      const data = await appStore.connect.getCatalog(appStoreConfig.connect.bundleId);
      catalogCache = { data, timestamp: nowMs };
      return res.json(data);
    } catch (err) {
      const isUnavailable = err instanceof AppStoreError ? err.kind === 'unavailable' : false;
      const code = isUnavailable ? 'appStoreUnavailable' : 'appStoreRejected';
      return sendError(res, 502, code, err.message || 'Failed to fetch App Store catalog.');
    }
  });

  consoleRouter.get('/appstore/transactions/:transactionId', async (req, res) => {
    const { transactionId } = req.params;
    if (!/^\d{1,20}$/.test(transactionId)) {
      return sendError(res, 400, 'invalidInput', 'transactionId: must be 1-20 digits', { field: 'transactionId' });
    }

    if (!appStoreConfig?.server || !appStore?.server) {
      return sendError(res, 503, 'appStoreNotConfigured', 'App Store API is not configured.');
    }

    const environment = req.query.environment === 'sandbox' ? 'sandbox' : 'production';

    try {
      const data = await appStore.server.lookupTransaction(transactionId, { environment });

      await logAdminAction(db, req.adminUser.id, 'appstore.transaction_lookup', {
        targetType: 'transaction',
        targetId: transactionId,
        payload: { transactionId, environment },
      });

      return res.json(data);
    } catch (err) {
      if (err instanceof AppStoreError && err.status === 404) {
        return sendError(res, 404, 'notFound', 'Transaction not found.');
      }
      const isUnavailable = err instanceof AppStoreError ? err.kind === 'unavailable' : false;
      const code = isUnavailable ? 'appStoreUnavailable' : 'appStoreRejected';
      return sendError(res, 502, code, err.message || 'Failed to lookup transaction.');
    }
  });

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

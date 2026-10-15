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

export function createAdminApp({
  db,
  verifyAccess = null,
  authenticate = requireAuth,
  now = () => Date.now(),
} = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json());

  app.get('/health', (_req, res) => {
    res.status(200).json({ status: 'ok', service: 'carecoins-admin-api' });
  });

  const operatorLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 300,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many requests. Please try again later.' },
    keyGenerator: (req) => req.auth.uid,
  });

  app.use('/admin-api',
    requireAccess(verifyAccess),
    authenticate,
    operatorLimiter,
    requireOperator(db),
    requireRecentSignIn(undefined, now),
    adminRouter);

  app.use((_req, res) => {
    sendError(res, 404, 'notFound', 'Not found.');
  });

  app.use((err, _req, res, _next) => {
    console.error(err);
    sendError(res, 500, 'internal', 'Internal server error.');
  });

  return app;
}

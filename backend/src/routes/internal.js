/**
 * Internal backend API (docs/management-platform-plan.md MP3d).
 *
 * Mounted at /internal in src/app.js.
 * Unreachable from the outside:
 * - The frontend nginx only proxies /api/ and /uploads/
 * - The backend container publishes no host ports
 * - Reached only over the internal Docker network (e.g. by admin-api)
 *
 * Authenticated via shared secret header `X-Internal-Token` matching
 * INTERNAL_API_TOKEN using crypto.timingSafeEqual. If the token is unset
 * or mismatched, returns 404 so the route is not advertised.
 */
import { Router } from 'express';
import crypto from 'node:crypto';
import rateLimit from 'express-rate-limit';
import { withTransaction } from '../db/pool.js';
import { reprocessEvent } from '../services/billingService.js';
import { validateParams } from '../middleware/validate.js';
import { sendServiceError, sendError } from '../utils/httpError.js';

export function createInternalLimiter({
  windowMs = 15 * 60 * 1000,
  max = 120,
} = {}) {
  return rateLimit({
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    handler: (_req, res) => {
      sendError(res, 429, 'rateLimited', 'Too many requests. Please try again later.');
    },
  });
}

export function createInternalRouter({
  token = undefined,
  limiter = createInternalLimiter(),
  runTransaction = withTransaction,
} = {}) {
  const router = Router();

  router.use((req, res, next) => {
    const configuredToken = token !== undefined ? token : process.env.INTERNAL_API_TOKEN;
    if (!configuredToken) {
      return sendError(res, 404, 'notFound', 'Not found.');
    }

    const headerValue = req.headers['x-internal-token'];
    if (!headerValue || typeof headerValue !== 'string') {
      return sendError(res, 404, 'notFound', 'Not found.');
    }

    const a = Buffer.from(headerValue);
    const b = Buffer.from(configuredToken);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      return sendError(res, 404, 'notFound', 'Not found.');
    }

    return next();
  });

  if (limiter) {
    router.use(limiter);
  }

  router.post(
    '/billing-events/:id/reprocess',
    validateParams('id'),
    async (req, res) => {
      try {
        const result = await runTransaction((client) =>
          reprocessEvent(client, req.params.id)
        );
        if (result.error) {
          return sendServiceError(res, result.error);
        }
        return res.json(result.data);
      } catch (err) {
        console.error('Internal billing event reprocess failed:', err);
        return sendError(res, 500, 'internal', 'Internal error reprocessing event.');
      }
    }
  );

  return router;
}

export const internalRouter = createInternalRouter();

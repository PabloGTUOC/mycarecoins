import './env.js';
import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { requireAuth } from './middleware/auth.js';
import { logLoginHistory } from './middleware/audit.js';
import { requireAdmin } from './middleware/rbac.js';
import { familyHeartbeat } from './middleware/heartbeat.js';
import { familiesRouter } from './routes/families.js';
import { adminRouter } from './routes/admin.js';
import { billingRouter } from './routes/billing.js';
import { activitiesRouter } from './routes/activities.js';
import { meRouter } from './routes/me.js';
import { dashboardRouter } from './routes/dashboard.js';
import { marketplaceRouter } from './routes/marketplace.js';
import { statsRouter } from './routes/stats.js';
import { absencesRouter } from './routes/absences.js';
import { personalTimeRouter } from './routes/personalTime.js';
import { eventsRouter } from './routes/events.js';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sendError } from './utils/httpError.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

// Trust the nginx reverse proxy sitting in front of this service
app.set('trust proxy', 1);

const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || 'http://localhost:5173')
  .split(',')
  .map(o => o.trim());

app.use(cors({
  origin: function (origin, callback) {
    if (!origin) {
      return callback(null, process.env.NODE_ENV !== 'production');
    }
    if (ALLOWED_ORIGINS.includes(origin)) {
      return callback(null, true);
    }
    callback(new Error(`Origin ${origin} not allowed by CORS policy.`));
  },
  credentials: true
}));
app.use(express.json());

app.use(rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 1000,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please try again later.' },
}));

const perUserLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please try again later.' },
  keyGenerator: (req) => req.auth.uid, // auth is guaranteed set by this point
});

// Admin routes get a much tighter budget than regular user traffic.
const adminLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please try again later.' },
  keyGenerator: (req) => req.auth.uid,
});

app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok', service: 'carecoins-backend' });
});

app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

// Provider webhooks authenticate by shared secret, not Firebase — see the
// router. Covered by the global IP limiter only.
app.use('/api/billing', billingRouter);

app.use('/api/admin', requireAuth, adminLimiter, requireAdmin, adminRouter);
app.use('/api/me', requireAuth, perUserLimiter, meRouter);
app.use('/api/families', requireAuth, perUserLimiter, familyHeartbeat, familiesRouter);
app.use('/api/activities', requireAuth, perUserLimiter, familyHeartbeat, activitiesRouter);
app.use('/api/dashboard', requireAuth, perUserLimiter, familyHeartbeat, dashboardRouter);
app.use('/api/marketplace', requireAuth, perUserLimiter, familyHeartbeat, marketplaceRouter);
app.use('/api/stats', requireAuth, perUserLimiter, familyHeartbeat, statsRouter);
app.use('/api/absences', requireAuth, perUserLimiter, familyHeartbeat, absencesRouter);
app.use('/api/personal-time', requireAuth, perUserLimiter, familyHeartbeat, personalTimeRouter);
app.use('/api/events', requireAuth, perUserLimiter, familyHeartbeat, eventsRouter);

app.use((_req, res) => {
  sendError(res, 404, 'notFound', 'Not found.');
});

app.use((err, _req, res, _next) => {
  console.error(err);
  sendError(res, 500, 'internal', 'Internal server error.');
});

export default app;

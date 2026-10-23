import { Router } from 'express';
import { withTransaction, pool } from '../db/pool.js';
import { upsertUserFromAuth, assertActiveMember } from '../db/users.js';
import { validateBody, string, email, required, positiveInt } from '../middleware/validate.js';
import { deleteFirebaseUser } from '../middleware/auth.js';
import { sendError, sendServiceError } from '../utils/httpError.js';
import {
  createDeviceKey,
  listDeviceKeys,
  revokeDeviceKey,
  revokeAllDeviceKeys,
} from '../services/deviceKeyService.js';
import multer from 'multer';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const safeUid = req.auth.uid.replace(/[^a-zA-Z0-9_-]/g, '');
    if (!safeUid) return cb(new Error('Invalid user ID.'));
    const dir = path.join(__dirname, '../../uploads/users', safeUid);
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: function (req, file, cb) {
    cb(null, 'avatar' + path.extname(file.originalname).toLowerCase());
  }
});

const upload = multer({
  storage,
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: function (_req, file, cb) {
    if (ALLOWED_MIME_TYPES.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only JPEG, PNG, and WebP images are allowed.'));
    }
  }
});

export const meRouter = Router();

meRouter.get('/', async (req, res) => {
  try {
    const payload = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      const { rows: families } = await client.query(
        `SELECT fm.family_id, f.name, fm.role, fm.alias, fm.coin_balance
         FROM family_members fm
         JOIN families f ON f.id = fm.family_id
         WHERE fm.user_id = $1 AND fm.status = 'active'
         ORDER BY f.created_at DESC`,
        [user.id]
      );

      const { rows: pendingRequests } = await client.query(
        `SELECT fm.family_id, f.name
         FROM family_members fm
         JOIN families f ON f.id = fm.family_id
         WHERE fm.user_id = $1 AND fm.status = 'pending'`,
        [user.id]
      );

      const { rows: actors } = await client.query(
        `SELECT a.id, a.family_id, a.name, a.actor_type, a.avatar_url, a.care_time
         FROM actors a
         JOIN family_members fm ON fm.family_id = a.family_id
         WHERE fm.user_id = $1 AND fm.status = 'active' AND a.actor_type != 'person'`,
        [user.id]
      );

      return { user, families, pendingRequests, actors };
    });

    return res.json(payload);
  } catch (err) {
    console.error('ME ROUTE ERROR:', err);
    return sendError(res, 500, 'internal', 'Failed to load current user.');
  }
});

meRouter.post('/avatar', (req, res, next) => {
  upload.single('avatar')(req, res, (err) => {
    if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
      return sendError(res, 400, 'fileTooLarge', 'File too large. Maximum size is 2 MB.', { maxSize: '2 MB' });
    }
    if (err) {
      if (err.message === 'Only JPEG, PNG, and WebP images are allowed.') {
        return sendError(res, 400, 'fileInvalidType', err.message);
      }
      return sendError(res, 400, 'invalidInput', err.message);
    }
    next();
  });
}, async (req, res) => {
  if (!req.file) {
    return sendError(res, 400, 'fileNoAvatar', 'No avatar image uploaded.');
  }

  const avatarUrl = `/uploads/users/${req.auth.uid}/${req.file.filename}`;

  try {
    const user = await withTransaction(async (client) => {
      const me = await upsertUserFromAuth(client, req.auth);
      await client.query(
        `UPDATE users SET avatar_url = $1 WHERE id = $2`,
        [avatarUrl, me.id]
      );
      me.avatar_url = avatarUrl;
      return me;
    });

    return res.json({ avatar_url: user.avatar_url });
  } catch (err) {
    console.error('Avatar upload error:', err);
    return sendError(res, 500, 'internal', 'Failed to upload avatar.');
  }
});
meRouter.post('/login-event', async (req, res) => {
  try {
    const eventId = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      const { rows } = await client.query(
        `INSERT INTO login_history (user_id, ip_address, user_agent)
         VALUES ($1, $2, $3)
         RETURNING id`,
        [user.id, req.ip || null, req.headers['user-agent'] || null]
      );
      return rows[0].id;
    });
    return res.json({ eventId });
  } catch (err) {
    return sendError(res, 500, 'internal', 'Failed to record login event.');
  }
});

meRouter.post('/logout-event', async (req, res) => {
  const { eventId } = req.body;
  try {
    await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      if (eventId) {
        await client.query(
          `UPDATE login_history SET logout_at = NOW() WHERE id = $1 AND user_id = $2`,
          [eventId, user.id]
        );
      } else {
        await client.query(
          `UPDATE login_history SET logout_at = NOW() 
           WHERE id = (
             SELECT id FROM login_history 
             WHERE user_id = $1 AND logout_at IS NULL 
             ORDER BY login_at DESC LIMIT 1
           )`,
          [user.id]
        );
      }
    });
    return res.json({ success: true });
  } catch (err) {
    return sendError(res, 500, 'internal', 'Failed to record logout event.');
  }
});

meRouter.patch('/profile', validateBody({
  displayName: [string(1, 100)],
  email: [string(1, 255), email()],
  alias: [string(1, 50)],
}), async (req, res) => {
  const { displayName, email, familyId, alias } = req.body;

  try {
    const user = await withTransaction(async (client) => {
      const me = await upsertUserFromAuth(client, req.auth);
      const { rows } = await client.query(
        `UPDATE users
         SET display_name = COALESCE($1, display_name),
             email = COALESCE($2, email)
         WHERE id = $3
         RETURNING id, firebase_uid, email, display_name, avatar_url`,
        [displayName || null, email || null, me.id]
      );

      if (familyId && alias !== undefined) {
        if (await assertActiveMember(client, familyId, me.id)) {
          await client.query('UPDATE family_members SET alias = $1 WHERE family_id = $2 AND user_id = $3', [alias.trim() || null, familyId, me.id]);
        }
      }
      return rows[0];
    });

    return res.json({ user });
  } catch (err) {
    console.error(err);
    return sendError(res, 500, 'internal', 'Failed to update profile.');
  }
});

meRouter.get('/invites', async (req, res) => {
  try {
    const invites = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      if (!user.email) return [];
      const { rows } = await client.query(
        `SELECT fi.id, fi.family_id, f.name AS family_name, fi.name AS inviter_name, fi.created_at
         FROM family_invitations fi
         JOIN families f ON f.id = fi.family_id
         WHERE fi.email = $1 AND fi.status = 'pending'
         ORDER BY fi.created_at DESC`,
        [user.email.toLowerCase()]
      );
      return rows;
    });
    return res.json({ invites });
  } catch (err) {
    console.error(err);
    return sendError(res, 500, 'internal', 'Failed to fetch invitations.');
  }
});

meRouter.get('/login-history', async (req, res) => {
  try {
    const rows = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      const { rows } = await client.query(
        `SELECT id, login_at, ip_address, user_agent
         FROM login_history
         WHERE user_id = $1
         ORDER BY login_at DESC
         LIMIT 20`,
        [user.id]
      );
      return rows;
    });

    return res.json({ loginHistory: rows });
  } catch {
    return sendError(res, 500, 'internal', 'Failed to load login history.');
  }
});

meRouter.get('/ledger', async (req, res) => {
  const familyId = Number(req.query.familyId);
  const monthStr = req.query.month;
  if (!familyId || !monthStr) return sendError(res, 400, 'ledgerParamsRequired', 'familyId and month (YYYY-MM) required.');

  try {
    const data = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);

      if (!await assertActiveMember(client, familyId, user.id)) return null;

      const startOfMonth = new Date(`${monthStr}-01T00:00:00Z`);
      if (isNaN(startOfMonth.getTime())) throw new Error("Invalid month format");

      const { rows: ledger } = await client.query(`
        SELECT cl.id, cl.amount, cl.reason, cl.created_at, cl.activity_id, a.title as activity_title, a.duration_minutes
        FROM coin_ledger cl
        LEFT JOIN activities a ON a.id = cl.activity_id
        WHERE cl.family_id = $1 AND cl.user_id = $2
          AND cl.created_at >= date_trunc('month', $3::timestamptz)
          AND cl.created_at < date_trunc('month', $3::timestamptz) + interval '1 month'
        ORDER BY cl.created_at DESC
      `, [familyId, user.id, startOfMonth.toISOString()]);

      return { ledger };
    });

    if (!data) return sendError(res, 403, 'familyNotMember', 'Not a family member.');
    return res.json(data);
  } catch (err) {
    console.error('Ledger Error:', err);
    return sendError(res, 500, 'internal', 'Failed to fetch ledger.');
  }
});

meRouter.delete('/', async (req, res) => {
  try {
    await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);

      await client.query(`
        DELETE FROM activities
        WHERE assigned_to = $1 AND starts_at > NOW()
      `, [user.id]);

      await client.query(`
        UPDATE family_members
        SET status = 'inactive'
        WHERE user_id = $1
      `, [user.id]);

      await client.query(`
        UPDATE users
        SET email = NULL,
            display_name = 'Deleted User',
            firebase_uid = 'deleted_' || id,
            is_deleted = true,
            avatar_url = NULL
        WHERE id = $1
      `, [user.id]);

      await deleteFirebaseUser(req.auth.uid);
    });

    return res.json({ success: true });
  } catch (err) {
    console.error('DELETE /me error:', err);
    return sendError(res, 500, 'internal', 'Failed to delete account.');
  }
});

// ─────────────────────────────────────────────
// POST /api/me/fcm-token  — register push token
// DELETE /api/me/fcm-token — remove push token
// ─────────────────────────────────────────────
meRouter.post('/fcm-token', async (req, res) => {
  const { token } = req.body;
  if (!token || typeof token !== 'string') {
    return sendError(res, 400, 'tokenRequired', 'token is required.', { field: 'token' });
  }
  try {
    const user = await withTransaction(async (client) => upsertUserFromAuth(client, req.auth));
    await pool.query(
      `INSERT INTO fcm_tokens (user_id, token) VALUES ($1, $2)
       ON CONFLICT (token) DO UPDATE SET user_id = $1`,
      [user.id, token]
    );
    return res.json({ ok: true });
  } catch (err) {
    console.error('POST /fcm-token error:', err);
    return sendError(res, 500, 'internal', 'Failed to save token.');
  }
});

meRouter.delete('/fcm-token', async (req, res) => {
  const { token } = req.body;
  if (!token || typeof token !== 'string') {
    return sendError(res, 400, 'tokenRequired', 'token is required.', { field: 'token' });
  }
  try {
    const user = await withTransaction(async (client) => upsertUserFromAuth(client, req.auth));
    await pool.query(
      'DELETE FROM fcm_tokens WHERE user_id = $1 AND token = $2',
      [user.id, token]
    );
    return res.json({ ok: true });
  } catch (err) {
    console.error('DELETE /fcm-token error:', err);
    return sendError(res, 500, 'internal', 'Failed to remove token.');
  }
});

// ─────────────────────────────────────────────
// GET  /api/me/notification-preferences
// PUT  /api/me/notification-preferences
// ─────────────────────────────────────────────
const DEFAULT_PREFS = {
  activity_assigned: true,
  activity_validated: true,
  activity_completed: true,
  bounty_offered: true,
  family_events: true,
  coverage_requests: true,
};

meRouter.get('/notification-preferences', async (req, res) => {
  try {
    const user = await withTransaction(async (client) => upsertUserFromAuth(client, req.auth));
    const { rows } = await pool.query(
      `SELECT activity_assigned, activity_validated, activity_completed, bounty_offered,
              family_events, coverage_requests
       FROM notification_preferences WHERE user_id = $1`,
      [user.id]
    );
    return res.json(rows[0] ? { ...DEFAULT_PREFS, ...rows[0] } : DEFAULT_PREFS);
  } catch (err) {
    console.error('GET /notification-preferences error:', err);
    return sendError(res, 500, 'internal', 'Failed to load preferences.');
  }
});

meRouter.put('/notification-preferences', async (req, res) => {
  const { activity_assigned, activity_validated, activity_completed, bounty_offered, family_events } = req.body;
  if ([activity_assigned, activity_validated, activity_completed, bounty_offered, family_events].some(v => typeof v !== 'boolean')) {
    return sendError(res, 400, 'notificationPreferencesBooleanRequired', 'All preference fields must be boolean.');
  }
  // Optional so a client that predates coverage requests keeps working — and,
  // because it is absent rather than false, does not silently switch them back on.
  const { coverage_requests } = req.body;
  if (coverage_requests !== undefined && typeof coverage_requests !== 'boolean') {
    return sendError(res, 400, 'notificationPreferencesCoverageRequestsBoolean', 'coverage_requests must be boolean.', { field: 'coverage_requests' });
  }
  try {
    const user = await withTransaction(async (client) => upsertUserFromAuth(client, req.auth));
    await pool.query(
      `INSERT INTO notification_preferences
         (user_id, activity_assigned, activity_validated, activity_completed, bounty_offered,
          family_events, coverage_requests)
       VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7, true))
       ON CONFLICT (user_id) DO UPDATE SET
         activity_assigned  = $2,
         activity_validated = $3,
         activity_completed = $4,
         bounty_offered     = $5,
         family_events      = $6,
         coverage_requests  = COALESCE($7, notification_preferences.coverage_requests)`,
      [user.id, activity_assigned, activity_validated, activity_completed, bounty_offered,
       family_events, coverage_requests ?? null]
    );
    return res.json({ ok: true });
  } catch (err) {
    console.error('PUT /notification-preferences error:', err);
    return sendError(res, 500, 'internal', 'Failed to save preferences.');
  }
});

// ─────────────────────────────────────────────
// Device keys (docs/ios-widget-watch-plan.md §3.1)
// ─────────────────────────────────────────────

meRouter.post(
  '/device-keys',
  validateBody({
    familyId: [required(), positiveInt()],
    label: [required(), string(1, 60)],
  }),
  async (req, res) => {
    try {
      const result = await withTransaction(async (client) => {
        const user = await upsertUserFromAuth(client, req.auth);
        return await createDeviceKey(client, user.id, {
          familyId: Number(req.body.familyId),
          label: req.body.label,
        });
      });

      if (result.error) {
        return sendServiceError(res, result.error);
      }

      return res.status(201).json({ deviceKey: result.data });
    } catch (err) {
      console.error('POST /device-keys error:', err);
      return sendError(res, 500, 'internal', 'Failed to create device key.');
    }
  }
);

meRouter.get('/device-keys', async (req, res) => {
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return await listDeviceKeys(client, user.id);
    });

    if (result.error) {
      return sendServiceError(res, result.error);
    }

    return res.json({ deviceKeys: result.data });
  } catch (err) {
    console.error('GET /device-keys error:', err);
    return sendError(res, 500, 'internal', 'Failed to list device keys.');
  }
});

meRouter.delete('/device-keys', async (req, res) => {
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return await revokeAllDeviceKeys(client, user.id);
    });

    if (result.error) {
      return sendServiceError(res, result.error);
    }

    return res.json({ success: true });
  } catch (err) {
    console.error('DELETE /device-keys error:', err);
    return sendError(res, 500, 'internal', 'Failed to revoke device keys.');
  }
});

meRouter.delete('/device-keys/:id', async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) {
      return sendError(res, 404, 'deviceKeyNotFound', 'Device not found.');
    }
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return await revokeDeviceKey(client, user.id, id);
    });

    if (result.error) {
      return sendServiceError(res, result.error);
    }

    return res.json({ success: true });
  } catch (err) {
    console.error('DELETE /device-keys/:id error:', err);
    return sendError(res, 500, 'internal', 'Failed to revoke device key.');
  }
});


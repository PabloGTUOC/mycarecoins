import crypto from 'node:crypto';
import { serviceError } from '../utils/httpError.js';
import { assertMemberRole } from '../middleware/rbac.js';

export function hashDeviceKey(key) {
  return crypto.createHash('sha256').update(key).digest('hex');
}

export async function createDeviceKey(client, userId, { familyId, label }) {
  const rbacErr = await assertMemberRole(client, userId, familyId, 'caregiver');
  if (rbacErr) {
    return serviceError(403, 'deviceKeyCaregiverOnly', 'Only caregivers can connect a widget or watch.');
  }

  const { rows: countRows } = await client.query(
    `SELECT COUNT(*)::int AS count FROM device_keys WHERE user_id = $1 AND revoked_at IS NULL`,
    [userId]
  );
  if (Number(countRows[0]?.count ?? 0) >= 10) {
    return serviceError(409, 'deviceKeyLimit', 'Too many connected devices. Remove one first.', { max: 10 });
  }

  const trimmedLabel = String(label ?? '').trim().slice(0, 60);
  const rawKey = 'cck_' + crypto.randomBytes(32).toString('base64url');
  const keyHash = hashDeviceKey(rawKey);

  const { rows } = await client.query(
    `INSERT INTO device_keys (user_id, family_id, label, key_hash)
     VALUES ($1, $2, $3, $4)
     RETURNING id, created_at`,
    [userId, familyId, trimmedLabel, keyHash]
  );
  const row = rows[0];

  return {
    data: {
      id: row.id,
      key: rawKey,
      label: trimmedLabel,
      familyId,
      createdAt: row.created_at,
    },
  };
}

export async function listDeviceKeys(client, userId) {
  const { rows } = await client.query(
    `SELECT id, label, family_id, created_at, last_used_at
     FROM device_keys
     WHERE user_id = $1 AND revoked_at IS NULL
     ORDER BY created_at DESC`,
    [userId]
  );
  return { data: rows };
}

export async function revokeDeviceKey(client, userId, id) {
  const { rowCount } = await client.query(
    `UPDATE device_keys
     SET revoked_at = NOW()
     WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL`,
    [id, userId]
  );
  if (!rowCount) {
    return serviceError(404, 'deviceKeyNotFound', 'Device not found.');
  }
  return { data: { success: true } };
}

export async function revokeAllDeviceKeys(client, userId) {
  await client.query(
    `UPDATE device_keys
     SET revoked_at = NOW()
     WHERE user_id = $1 AND revoked_at IS NULL`,
    [userId]
  );
  return { data: { success: true } };
}

export async function resolveDeviceKey(client, rawKey) {
  if (!rawKey || typeof rawKey !== 'string') {
    return serviceError(401, 'deviceKeyInvalid', 'This device is no longer connected.');
  }
  const keyHash = hashDeviceKey(rawKey);

  const { rows } = await client.query(
    `SELECT dk.id, dk.user_id, dk.family_id, dk.revoked_at, u.firebase_uid, u.is_deleted,
            fm.role, fm.status
     FROM device_keys dk
     JOIN users u ON u.id = dk.user_id
     LEFT JOIN family_members fm ON fm.family_id = dk.family_id AND fm.user_id = dk.user_id
     WHERE dk.key_hash = $1`,
    [keyHash]
  );

  if (!rows.length) {
    return serviceError(401, 'deviceKeyInvalid', 'This device is no longer connected.');
  }

  const row = rows[0];
  if (row.revoked_at) {
    return serviceError(401, 'deviceKeyRevoked', 'This device was disconnected.');
  }

  if (row.is_deleted || row.role !== 'caregiver' || row.status !== 'active') {
    return serviceError(403, 'deviceKeyCaregiverOnly', 'Only caregivers can connect a widget or watch.');
  }

  await client.query(
    `UPDATE device_keys SET last_used_at = NOW() WHERE id = $1`,
    [row.id]
  );

  return {
    data: {
      deviceKeyId: row.id,
      userId: row.user_id,
      familyId: row.family_id,
      firebaseUid: row.firebase_uid,
    },
  };
}

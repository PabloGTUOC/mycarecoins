import { withTransaction } from '../db/pool.js';
import { resolveDeviceKey } from '../services/deviceKeyService.js';
import { sendError, sendServiceError } from '../utils/httpError.js';

export async function requireDeviceKey(req, res, next) {
  const authHeader = req.headers?.authorization || '';
  if (!authHeader.startsWith('Device ')) {
    return sendError(res, 401, 'deviceKeyInvalid', 'This device is no longer connected.');
  }

  const key = authHeader.slice(7).trim();
  if (!key) {
    return sendError(res, 401, 'deviceKeyInvalid', 'This device is no longer connected.');
  }

  try {
    const runner = req._withTransaction || withTransaction;
    const result = await runner((client) => resolveDeviceKey(client, key));

    if (result.error) {
      return sendServiceError(res, result.error);
    }

    const { deviceKeyId, userId, familyId, firebaseUid } = result.data;
    req.auth = { uid: firebaseUid, email: null, name: null, authTime: null };
    req.device = { id: deviceKeyId, userId, familyId };
    return next();
  } catch (err) {
    console.error('requireDeviceKey error:', err);
    return sendError(res, 500, 'internal', 'Authentication failed.');
  }
}

import admin from 'firebase-admin';

let firebaseApp;

function getFirebaseApp() {
  if (firebaseApp) return firebaseApp;

  const projectId = process.env.FIREBASE_PROJECT_ID;
  if (!projectId) {
    return null;
  }

  if (!admin.apps.length) {
    // When Auth Emulator is active, verifyIdToken is local — no real credential needed.
    const credential = process.env.FIREBASE_AUTH_EMULATOR_HOST
      ? undefined
      : admin.credential.applicationDefault();
    firebaseApp = admin.initializeApp({ ...(credential && { credential }), projectId });
  } else {
    firebaseApp = admin.app();
  }

  return firebaseApp;
}

import { sendError } from '../utils/httpError.js';

export async function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (!token) {
    return sendError(res, 401, 'authMissingToken', 'Missing Bearer token.');
  }

  try {
    const app = getFirebaseApp();

    if (!app) {
      return sendError(res, 500, 'internal', 'Firebase not configured. Set FIREBASE_PROJECT_ID and credentials.');
    }

    const decoded = await admin.auth().verifyIdToken(token);
    req.auth = {
      uid: decoded.uid,
      email: decoded.email || null,
      name: decoded.name || null,
      // Seconds-since-epoch of the user's last credential entry; lets
      // destructive endpoints demand a recent re-login when one is added.
      authTime: decoded.auth_time ?? null
    };

    return next();
  } catch (error) {
    return sendError(res, 401, 'authInvalidToken', 'Invalid or expired token.');
  }
}

export async function deleteFirebaseUser(uid) {
  const app = getFirebaseApp();
  if (app) {
    await admin.auth().deleteUser(uid);
  }
}


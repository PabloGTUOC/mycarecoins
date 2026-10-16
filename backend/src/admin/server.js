import './env.js';
import { pool } from '../db/pool.js';
import { ADMIN_ROLE } from '../../scripts/admin-role.js';
import { accessVerifierFromEnv } from './access.js';
import { createAdminApp } from './app.js';
import { createRevenueCatClient, revenueCatConfigFromEnv } from './revenuecat.js';
import { syncPending } from './rcSync.js';
import { createAppStoreClients, appStoreConfigFromEnv } from './appstore.js';

const port = Number(process.env.PORT || 3001);

const verifyAccess = accessVerifierFromEnv();
if (!verifyAccess) {
  console.warn('Cloudflare Access check is OFF (CF_ACCESS_* not set). Never run like this in production.');
}

// The database role is the privacy boundary: refuse to serve as anyone else.
const { rows } = await pool.query('SELECT current_user AS role');
if (rows[0].role !== ADMIN_ROLE) {
  const message = `admin-api is connected as "${rows[0].role}", not ${ADMIN_ROLE}.`;
  if (process.env.NODE_ENV === 'production') throw new Error(message);
  console.warn(`${message} Fine for local work; never in production.`);
}

const rcConfig = revenueCatConfigFromEnv(process.env);
const rcClient = rcConfig ? createRevenueCatClient(rcConfig) : null;

if (rcConfig && rcClient) {
  const runSync = async () => {
    try {
      await syncPending(pool, rcClient, { entitlementId: rcConfig.entitlementId });
    } catch (err) {
      console.error('RevenueCat sync error:', err.message);
    }
  };
  // Run once at start
  runSync();
  // Schedule every 5 minutes
  const timer = setInterval(runSync, 5 * 60 * 1000);
  timer.unref?.();
} else {
  console.log('RevenueCat mirror off');
}

const appStoreConfig = appStoreConfigFromEnv(process.env);
const appStoreClients = (appStoreConfig?.connect || appStoreConfig?.server)
  ? createAppStoreClients({ config: appStoreConfig })
  : null;

if (appStoreClients) {
  console.log('App Store integration on');
} else {
  console.log('App Store integration off');
}

const app = createAdminApp({
  db: pool,
  verifyAccess,
  rc: rcClient,
  rcConfig,
  appStore: appStoreClients,
  appStoreConfig,
});

app.listen(port, '0.0.0.0', () => {
  console.log(`CareCoins admin API running on port ${port}`);
});

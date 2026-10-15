import './env.js';
import { pool } from '../db/pool.js';
import { ADMIN_ROLE } from '../../scripts/admin-role.js';
import { accessVerifierFromEnv } from './access.js';
import { createAdminApp } from './app.js';

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

const app = createAdminApp({ db: pool, verifyAccess });

app.listen(port, '0.0.0.0', () => {
  console.log(`CareCoins admin API running on port ${port}`);
});

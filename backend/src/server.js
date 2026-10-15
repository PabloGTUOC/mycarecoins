import app from './app.js';
import { pool } from './db/pool.js';
import { startNoticeOutbox } from './services/noticeOutbox.js';

const port = Number(process.env.PORT || 3000);

app.listen(port, '0.0.0.0', () => {
  console.log(`CareCoins backend running on port ${port} and bound to 0.0.0.0`);
});

// Family notices queued by the operator console (docs/management-platform-plan.md).
startNoticeOutbox(pool);

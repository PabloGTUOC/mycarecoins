import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../src/db/pool.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  const schemaPath    = path.join(__dirname, '../src/db/schema.sql');
  const migrationPath = path.join(__dirname, 'migrate-deletion.sql');

  await pool.query(await fs.readFile(schemaPath, 'utf8'));
  console.log('Database schema initialized.');

  await pool.query(await fs.readFile(migrationPath, 'utf8'));
  console.log('Database migrations applied.');

  const fcmMigrationPath = path.join(__dirname, 'migrate-fcm.sql');
  await pool.query(await fs.readFile(fcmMigrationPath, 'utf8'));
  console.log('FCM token table ready.');

  const fcmIndexPath = path.join(__dirname, 'migrate-fcm-index.sql');
  await pool.query(await fs.readFile(fcmIndexPath, 'utf8'));
  console.log('FCM token index ready.');

  const notifPrefsPath = path.join(__dirname, 'migrate-notif-prefs.sql');
  await pool.query(await fs.readFile(notifPrefsPath, 'utf8'));
  console.log('Notification preferences table ready.');

  const platformAdminPath = path.join(__dirname, 'migrate-platform-admin.sql');
  await pool.query(await fs.readFile(platformAdminPath, 'utf8'));
  console.log('Platform admin role and audit log ready.');

  const heartbeatPath = path.join(__dirname, 'migrate-heartbeat.sql');
  await pool.query(await fs.readFile(heartbeatPath, 'utf8'));
  console.log('Family heartbeat column ready.');

  const plansPath = path.join(__dirname, 'migrate-plans.sql');
  await pool.query(await fs.readFile(plansPath, 'utf8'));
  console.log('Plans, subscriptions and grants ready.');

  const onboardingEventsPath = path.join(__dirname, 'migrate-onboarding-events.sql');
  await pool.query(await fs.readFile(onboardingEventsPath, 'utf8'));
  console.log('Onboarding events table ready.');

  const absenceFloorPath = path.join(__dirname, 'migrate-absence-floor.sql');
  await pool.query(await fs.readFile(absenceFloorPath, 'utf8'));
  console.log('Absence duration floor ready.');

  const activitySubclassesPath = path.join(__dirname, 'migrate-activity-subclasses.sql');
  await pool.query(await fs.readFile(activitySubclassesPath, 'utf8'));
  console.log('Activity subclasses (category + type) ready.');

  const personalTimePath = path.join(__dirname, 'migrate-personal-time.sql');
  await pool.query(await fs.readFile(personalTimePath, 'utf8'));
  console.log('Personal-time requests ready.');

  const ledgerReversalsPath = path.join(__dirname, 'migrate-ledger-reversals.sql');
  await pool.query(await fs.readFile(ledgerReversalsPath, 'utf8'));
  console.log('Reverted payouts have their credits back.');

  await pool.end();
}

main().catch((error) => {
  console.error('Failed to initialize database schema:', error);
  process.exitCode = 1;
});

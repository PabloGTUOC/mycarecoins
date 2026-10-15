// Loaded before the database pool. In the admin-api container the database URL
// carries no password; it comes from ADMIN_DB_PASSWORD (backend/admin-db.env),
// the same value db-init uses to set the role's password.
import '../env.js';

if (process.env.ADMIN_DB_PASSWORD && !process.env.PGPASSWORD) {
  process.env.PGPASSWORD = process.env.ADMIN_DB_PASSWORD;
}

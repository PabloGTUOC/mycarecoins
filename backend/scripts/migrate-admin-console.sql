-- Operator console (docs/management-platform-plan.md Phase 1).
--
-- The console's API (src/admin/) connects as the restricted carecoins_admin
-- role, which can read only what is defined here plus the billing tables
-- (grants: scripts/admin-role.js). Views run with their owner's rights, so they
-- can count members and actors that the admin role itself cannot read.
-- security_barrier stops a caller's WHERE clause from running before the view's
-- own filters.

CREATE OR REPLACE VIEW admin_family_registry WITH (security_barrier) AS
SELECT f.id, f.name, f.created_at, f.last_active_at,
       fp.plan_code, fp.status AS subscription_status,
       (SELECT COUNT(*) FROM family_members fm
         WHERE fm.family_id = f.id AND fm.status = 'active') AS member_count,
       (SELECT COUNT(*) FROM family_members fm
         WHERE fm.family_id = f.id AND fm.status = 'pending') AS pending_member_count,
       (SELECT COUNT(*) FROM actors a
         WHERE a.family_id = f.id AND a.user_id IS NULL) AS actor_count
FROM families f
LEFT JOIN family_plans fp ON fp.family_id = f.id;

-- Who may use the console. requireOperator (src/admin/operator.js) looks the
-- caller up here instead of reading users.
CREATE OR REPLACE VIEW admin_operators WITH (security_barrier) AS
SELECT id, firebase_uid
FROM users
WHERE platform_role = 'admin' AND is_deleted = false;

-- Family notices the console asks for. The admin role cannot see who is in a
-- family, so it only queues the request; the public backend sends the push
-- (src/services/noticeOutbox.js).
CREATE TABLE IF NOT EXISTS admin_family_notices (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('inactive')),
  requested_by BIGINT NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_admin_family_notices_unsent
  ON admin_family_notices (id) WHERE sent_at IS NULL;

-- Free plans mirrored into RevenueCat (plan §4). One row per grant; the
-- console's sync loop moves it from pending to synced or failed.
CREATE TABLE IF NOT EXISTS admin_rc_sync (
  grant_id BIGINT PRIMARY KEY REFERENCES admin_grants(id) ON DELETE CASCADE,
  rc_customer_id TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('grant', 'revoke')),
  status TEXT NOT NULL CHECK (status IN ('pending', 'synced', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  synced_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

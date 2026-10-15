CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  firebase_uid TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE,
  display_name TEXT,
  avatar_url TEXT,
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  platform_role TEXT NOT NULL DEFAULT 'user' CHECK (platform_role IN ('user', 'admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS families (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  monthly_coin_budget INTEGER NOT NULL DEFAULT 1000 CHECK (monthly_coin_budget > 0),
  last_coin_distribution_month VARCHAR(7),
  created_by BIGINT NOT NULL REFERENCES users(id),
  last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Databases created before the heartbeat work already have `families`, so the
-- CREATE TABLE above is a no-op for them and the column would be missing when
-- the index below runs. scripts/migrate-heartbeat.sql backfills it and sets the
-- default/NOT NULL afterwards.
ALTER TABLE families ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_families_last_active ON families (last_active_at);

CREATE TABLE IF NOT EXISTS family_members (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('caregiver', 'member')),
  alias TEXT,
  coin_balance INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'pending', 'inactive')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (family_id, user_id)
);

CREATE TABLE IF NOT EXISTS family_invitations (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  name TEXT,
  role TEXT NOT NULL DEFAULT 'caregiver',
  invited_by BIGINT NOT NULL REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (family_id, email)
);

CREATE TABLE IF NOT EXISTS actors (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
  actor_type TEXT NOT NULL DEFAULT 'person',
  name TEXT,
  care_time TEXT CHECK (care_time IN ('full_time', 'part_time')),
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (family_id, user_id)
);

CREATE TABLE IF NOT EXISTS activities (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  created_by BIGINT NOT NULL REFERENCES users(id),
  assigned_to BIGINT REFERENCES users(id),
  title TEXT NOT NULL,
  -- Activities are a base class with two subclasses (docs/personal-time-plan.md
  -- §4): `category` is the subclass — 'care' is work for the family, 'self' is
  -- personal time — and `type` is the sub-type within it. Both are NOT NULL,
  -- which is what keeps the CHECK below from ever evaluating to NULL: a CHECK
  -- rejects only on false, so a nullable column here would let bad rows through.
  category TEXT NOT NULL DEFAULT 'care',
  type TEXT NOT NULL,
  description TEXT,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  duration_minutes INTEGER NOT NULL CHECK (duration_minutes >= 15),
  coin_value INTEGER NOT NULL CHECK (coin_value >= 0),
  status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'completed', 'pending_validation')) DEFAULT 'pending',
  is_template BOOLEAN NOT NULL DEFAULT true,
  is_recurrent BOOLEAN NOT NULL DEFAULT false,
  approved_by BIGINT REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  bounty_amount INTEGER NOT NULL DEFAULT 0,
  bounty_offered_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT activities_category_type_check CHECK (
    -- 'coverage' is care work created by accepting someone's personal-time
    -- request. Only that flow writes it — the API validator still accepts only
    -- 'care' and 'household' — and it is the one type that may overlap another
    -- activity, because covering a dependent is supervision, not busy hands.
    (category = 'care' AND type IN ('care', 'household', 'coverage')) OR
    (category = 'self' AND coin_value = 0
                       AND type IN ('sport', 'social', 'rest', 'appointment', 'other'))
  ),
  CHECK ((ends_at > starts_at) OR (starts_at IS NULL AND ends_at IS NULL))
);

CREATE TABLE IF NOT EXISTS coin_ledger (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_id BIGINT REFERENCES activities(id) ON DELETE SET NULL,
  amount INTEGER NOT NULL,
  reason TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS login_history (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  logout_at TIMESTAMPTZ,
  ip_address TEXT,
  user_agent TEXT
);

CREATE TABLE IF NOT EXISTS marketplace_rewards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  creator_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  cost INTEGER NOT NULL CHECK (cost > 0),
  max_uses INTEGER,
  valid_from TIMESTAMPTZ,
  valid_until TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reward_redemptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reward_id UUID NOT NULL REFERENCES marketplace_rewards(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  redeemed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activities_assignee_period ON activities (assigned_to, starts_at, ends_at);
CREATE INDEX IF NOT EXISTS idx_activities_family_status ON activities (family_id, status);
CREATE INDEX IF NOT EXISTS idx_activities_family_category_status
  ON activities (family_id, category, status);
CREATE INDEX IF NOT EXISTS idx_marketplace_family_status ON marketplace_rewards (family_id, status);

CREATE TABLE IF NOT EXISTS absences (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  title TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (end_time > start_time)
);

-- An absence must last at least 24 hours (docs/personal-time-plan.md Phase 1).
-- The constraint lives in scripts/migrate-absence-floor.sql because it is added
-- NOT VALID, to grandfather the shorter absences already in live databases.

CREATE INDEX IF NOT EXISTS idx_absences_family_period ON absences (family_id, start_time, end_time);

CREATE TABLE IF NOT EXISTS invite_links (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  family_id  BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  created_by BIGINT NOT NULL REFERENCES users(id),
  max_uses   INTEGER,
  uses       INTEGER NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ,
  revoked    BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invite_links_family ON invite_links (family_id);

CREATE TABLE IF NOT EXISTS family_deletion_requests (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  requested_by BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS family_deletion_approvals (
  id BIGSERIAL PRIMARY KEY,
  request_id BIGINT NOT NULL REFERENCES family_deletion_requests(id) ON DELETE CASCADE,
  caregiver_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  responded_at TIMESTAMPTZ,
  UNIQUE (request_id, caregiver_id)
);

CREATE TABLE IF NOT EXISTS fcm_tokens (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user_id ON fcm_tokens (user_id);

CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id            BIGINT  PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  activity_assigned  BOOLEAN NOT NULL DEFAULT true,
  activity_validated BOOLEAN NOT NULL DEFAULT true,
  activity_completed BOOLEAN NOT NULL DEFAULT true,
  bounty_offered     BOOLEAN NOT NULL DEFAULT true,
  family_events      BOOLEAN NOT NULL DEFAULT true
);

-- Plan / entitlement model (docs/admin-family-management-plan.md Phase 3):
-- provider-agnostic subscription state; see scripts/migrate-plans.sql.
CREATE TABLE IF NOT EXISTS plans (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  price_cents INTEGER NOT NULL DEFAULT 0 CHECK (price_cents >= 0),
  currency TEXT NOT NULL DEFAULT 'EUR',
  billing_period TEXT NOT NULL DEFAULT 'monthly' CHECK (billing_period IN ('monthly', 'yearly')),
  limits JSONB NOT NULL DEFAULT '{}',
  features JSONB NOT NULL DEFAULT '{}',
  is_default BOOLEAN NOT NULL DEFAULT false,
  active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS family_plans (
  family_id BIGINT PRIMARY KEY REFERENCES families(id) ON DELETE CASCADE,
  plan_code TEXT NOT NULL REFERENCES plans(code),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN
    ('trialing', 'active', 'in_grace', 'past_due', 'paused', 'canceled', 'expired')),
  current_period_end TIMESTAMPTZ,
  platform TEXT,
  provider TEXT,
  provider_subscription_id TEXT,
  billing_owner_user_id BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS billing_events (
  id BIGSERIAL PRIMARY KEY,
  provider TEXT NOT NULL,
  event_id TEXT UNIQUE,
  event_type TEXT NOT NULL,
  family_id BIGINT REFERENCES families(id) ON DELETE SET NULL,
  payload JSONB NOT NULL,
  processed BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_billing_events_family ON billing_events (family_id, created_at);

CREATE TABLE IF NOT EXISTS admin_grants (
  id BIGSERIAL PRIMARY KEY,
  family_id BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  plan_code TEXT NOT NULL REFERENCES plans(code),
  granted_by BIGINT NOT NULL REFERENCES users(id),
  reason TEXT,
  expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_grants_family ON admin_grants (family_id);

-- Platform admin audit trail (docs/admin-family-management-plan.md Phase 1):
-- one row per mutating admin action, written in the same transaction.
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id BIGSERIAL PRIMARY KEY,
  admin_id BIGINT NOT NULL REFERENCES users(id),
  action TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT,
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin_time
  ON admin_audit_log (admin_id, created_at);

-- Personal-time requests (docs/personal-time-plan.md Phase 4): booking personal
-- time always carries a coverage offer, and is only real once another caretaker
-- accepts. See scripts/migrate-personal-time.sql.
CREATE TABLE IF NOT EXISTS personal_time_requests (
  id                BIGSERIAL PRIMARY KEY,
  family_id         BIGINT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  requester_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- NULL means "ask anyone": any active caregiver may accept, first one wins.
  requested_of      BIGINT REFERENCES users(id) ON DELETE CASCADE,
  -- Reserved for per-instance renegotiation of a recurring request (Phase 6);
  -- present from the start so adding it later needs no data migration.
  parent_request_id BIGINT REFERENCES personal_time_requests(id) ON DELETE CASCADE,
  title             TEXT NOT NULL,
  type              TEXT NOT NULL CHECK (type IN ('sport', 'social', 'rest', 'appointment', 'other')),
  description       TEXT,
  starts_at         TIMESTAMPTZ NOT NULL,
  ends_at           TIMESTAMPTZ NOT NULL,
  -- False = the dependent needs nobody during this window (gym while the kid is
  -- at daycare). The partner is still told, but there is nothing to accept and
  -- no coins move; such a request is created already 'accepted', with
  -- responded_by NULL to show no one had to answer it.
  coverage_needed   BOOLEAN NOT NULL DEFAULT true,
  baseline_coins    INTEGER NOT NULL DEFAULT 0 CHECK (baseline_coins >= 0),
  sweetener_coins   INTEGER NOT NULL DEFAULT 0 CHECK (sweetener_coins >= 0),
  -- What actually left the requester's wallet: `sweetener_coins` is per
  -- occurrence, so a ten-Friday series escrows ten sweeteners up front. Kept
  -- separately so a refund never has to recompute an occurrence list to know
  -- what to give back — a refund that recomputes is a refund that can drift.
  escrowed_coins    INTEGER NOT NULL DEFAULT 0 CHECK (escrowed_coins >= 0),
  recurrence        TEXT CHECK (recurrence IN ('daily', 'weekdays', 'weekly')),
  recurrence_until  DATE,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  responded_by      BIGINT REFERENCES users(id),
  responded_at      TIMESTAMPTZ,
  expires_at        TIMESTAMPTZ NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (ends_at > starts_at),
  CHECK (ends_at - starts_at <= INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_personal_time_family_status
  ON personal_time_requests (family_id, status, starts_at);
CREATE INDEX IF NOT EXISTS idx_personal_time_requested_of
  ON personal_time_requests (requested_of, status);

-- Which request an activity came from, and the row on the other side of it.
ALTER TABLE activities ADD COLUMN IF NOT EXISTS personal_time_request_id BIGINT
  REFERENCES personal_time_requests(id) ON DELETE SET NULL;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS counterpart_activity_id BIGINT
  REFERENCES activities(id) ON DELETE SET NULL;

ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS coverage_requests BOOLEAN NOT NULL DEFAULT true;

-- Onboarding instrumentation (docs/onboarding-help-plan.md Phase 4):
-- one row per guided-tour / checklist event, for the activation analysis.
CREATE TABLE IF NOT EXISTS onboarding_events (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event TEXT NOT NULL,
  detail JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_onboarding_events_user_event
  ON onboarding_events (user_id, event);

-- Operator console (docs/management-platform-plan.md Phase 1); see
-- scripts/migrate-admin-console.sql for why each piece exists. The
-- carecoins_admin role and its grants are applied by scripts/admin-role.js.
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

CREATE OR REPLACE VIEW admin_operators WITH (security_barrier) AS
SELECT id, firebase_uid
FROM users
WHERE platform_role = 'admin' AND is_deleted = false;

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

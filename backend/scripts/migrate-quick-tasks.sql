ALTER TABLE activities ADD COLUMN IF NOT EXISTS running_since TIMESTAMPTZ;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS client_ref TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS activities_client_ref_uniq
  ON activities (assigned_to, client_ref) WHERE client_ref IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS activities_one_running_per_user
  ON activities (assigned_to) WHERE running_since IS NOT NULL;

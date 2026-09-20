-- Fixture: two tables, neither has Row Level Security enabled anywhere in this file.
CREATE TABLE orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  total_cents INTEGER NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- audit_log is intentionally never referenced anywhere outside this migration,
-- to exercise the disconnected-schema check in scan-schema.sh.
CREATE TABLE audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID NOT NULL,
  action TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

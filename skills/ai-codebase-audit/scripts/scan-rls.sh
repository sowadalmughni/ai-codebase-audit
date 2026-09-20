#!/usr/bin/env bash
# =============================================================================
# AI Codebase Audit — Row Level Security Scanner
# Md. Sowad Al-Mughni | https://github.com/sowadalmughni/ai-codebase-audit
#
# USAGE:  bash scripts/scan-rls.sh [root-dir]
# REQUIRES: DATABASE_URL env var for live DB checks (falls back to static scan)
# =============================================================================

ROOT="${1:-.}"

# shellcheck source=lib/preflight.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/preflight.sh"
require_gnu_grep
require_dir "$ROOT"
EXCLUDE="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=.next"
FINDINGS=0

# Tables that almost always contain user data and must have RLS
HIGH_RISK_TABLES="users|profiles|orders|payments|subscriptions|sessions|documents|messages|transactions|accounts|invoices|receipts|addresses|cards|tokens"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  ROW LEVEL SECURITY SCAN — CRITICAL"
echo "  $(date)"
echo "═══════════════════════════════════════════════════"
echo "  Context: 88% of AI-built Supabase apps had RLS"
echo "  disabled or misconfigured in 2026 security audits."
echo "  Disabled RLS = anyone with the anon key can read"
echo "  and modify any row in the database."
echo "═══════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────────────
# 1. Live database check (if DATABASE_URL available)
# ─────────────────────────────────────────────────────
if [ -n "$DATABASE_URL" ]; then
  echo "Connected to database. Running live checks..."
  echo ""

  echo "── Tables with RLS disabled ──────────────────────"
  psql "$DATABASE_URL" -t -c "
    SELECT '  ⛔ CRITICAL: ' || tablename || ' — RLS is DISABLED'
    FROM pg_tables
    WHERE schemaname = 'public'
    AND rowsecurity = false
    ORDER BY tablename;" 2>/dev/null || echo "  Could not query pg_tables"

  echo ""
  echo "── Tables with RLS enabled but NO policies ───────"
  psql "$DATABASE_URL" -t -c "
    SELECT '  ⛔ CRITICAL: ' || t.tablename || ' — RLS enabled but ZERO policies defined'
    FROM pg_tables t
    WHERE t.schemaname = 'public'
    AND t.rowsecurity = true
    AND NOT EXISTS (
      SELECT 1 FROM pg_policies p
      WHERE p.schemaname = 'public'
      AND p.tablename = t.tablename
    )
    ORDER BY t.tablename;" 2>/dev/null || echo "  Could not query policies"

  echo ""
  echo "── Current RLS policies ──────────────────────────"
  psql "$DATABASE_URL" -c "
    SELECT tablename, policyname, permissive, roles, cmd
    FROM pg_policies
    WHERE schemaname = 'public'
    ORDER BY tablename, policyname;" 2>/dev/null || echo "  Could not query policies"

  echo ""
  FINDINGS=$((FINDINGS + 1))
else
  echo "  DATABASE_URL not set. Skipping live checks."
  echo "  Set DATABASE_URL to run live RLS verification."
  echo ""
fi

# ─────────────────────────────────────────────────────
# 2. Static scan: migration files
# ─────────────────────────────────────────────────────
echo "── Scanning migration files for RLS statements ──"

# Find migrations
MIGRATION_DIRS=$(find "$ROOT" -type d \( -name "migrations" -o -name "migration" -o -name "db" \) 2>/dev/null | grep -v "node_modules\|\.git\|dist\|build")

if [ -z "$MIGRATION_DIRS" ]; then
  echo "  No migration directories found."
else
  for dir in $MIGRATION_DIRS; do
    echo "  Checking: $dir"

    # Tables created without RLS enablement
    grep -rn "CREATE TABLE" "$dir" 2>/dev/null | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      linenum=$(echo "$line" | cut -d: -f2)
      tablename=$(echo "$line" | grep -oP "CREATE TABLE (IF NOT EXISTS )?['\`]?\K[a-zA-Z_][a-zA-Z0-9_]*")

      if [ -n "$tablename" ]; then
        # Check if this table has ENABLE ROW LEVEL SECURITY anywhere in the same file
        if ! grep -q "ENABLE ROW LEVEL SECURITY" "$file" 2>/dev/null; then
          echo ""
          echo "  ⛔ CRITICAL — Table '$tablename' has no RLS in migration"
          echo "      File: $file:$linenum"
          echo ""
          echo "  FIX: Add to migration file after CREATE TABLE:"
          echo "      ALTER TABLE $tablename ENABLE ROW LEVEL SECURITY;"
          echo ""
          echo "      CREATE POLICY \"${tablename}_user_isolation\" ON $tablename"
          echo "        FOR ALL"
          echo "        USING (user_id = auth.uid());"
          echo ""
          echo "      -- If the table doesn't have user_id, use a join:"
          echo "      CREATE POLICY \"${tablename}_owner_isolation\" ON $tablename"
          echo "        FOR ALL"
          echo "        USING (EXISTS ("
          echo "          SELECT 1 FROM parent_table p"
          echo "          WHERE p.id = ${tablename}.parent_id"
          echo "          AND p.user_id = auth.uid()"
          echo "        ));"
        fi
      fi
    done

    # Explicit disabling
    DISABLED=$(grep -rn "DISABLE ROW LEVEL SECURITY" "$dir" 2>/dev/null)
    if [ -n "$DISABLED" ]; then
      echo ""
      echo "  ⛔ CRITICAL — RLS explicitly disabled"
      echo "$DISABLED" | while IFS= read -r line; do
        echo "      $line"
      done
      FINDINGS=$((FINDINGS + 1))
    fi
  done
fi

# ─────────────────────────────────────────────────────
# 3. Check application code for service role key usage
# ─────────────────────────────────────────────────────
echo ""
echo "── Scanning for service role key outside server context ──"

SERVICE_ROLE_IN_CLIENT=$(grep -rPn "serviceRoleKey|SUPABASE_SERVICE_ROLE" \
  "$ROOT" $EXCLUDE \
  --include="*.tsx" --include="*.jsx" 2>/dev/null | grep -v "server\|api\|route\|backend")

if [ -n "$SERVICE_ROLE_IN_CLIENT" ]; then
  echo ""
  echo "  ⛔ CRITICAL — Service role key in client component"
  echo "$SERVICE_ROLE_IN_CLIENT" | while IFS= read -r line; do
    echo "      $line"
  done
  echo ""
  echo "  FIX: The service role key bypasses ALL RLS policies."
  echo "  Use only in server-side API routes. Never in .tsx or .jsx."
  FINDINGS=$((FINDINGS + 1))
else
  echo "  ✓ No service role key found in client files"
fi

# ─────────────────────────────────────────────────────
# 4. Check for known high-risk table names with no RLS in queries
# ─────────────────────────────────────────────────────
echo ""
echo "── Scanning for high-risk table references without RLS awareness ──"

grep -rPn "FROM\s+($HIGH_RISK_TABLES)\b|INTO\s+($HIGH_RISK_TABLES)\b" \
  "$ROOT" $EXCLUDE \
  --include="*.ts" --include="*.js" --include="*.py" 2>/dev/null \
  | grep -v "migration\|seed\|test\|spec" | head -20

echo ""
echo "  Note: Review each reference above."
echo "  If the table has RLS enabled and a valid policy, this is fine."
echo "  If RLS is disabled or no policy exists, this is a CRITICAL finding."

# ─────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  RLS scan complete"
echo "  Manual verification required:"
echo "  1. Run the live DB check above (requires DATABASE_URL)"
echo "  2. Confirm every table in public schema has:"
echo "     a. ALTER TABLE x ENABLE ROW LEVEL SECURITY;"
echo "     b. At least one policy that enforces user isolation"
echo "  3. Confirm service role key is server-side only"
echo "═══════════════════════════════════════════════════"
echo ""

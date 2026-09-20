#!/usr/bin/env bash
# =============================================================================
# AI Codebase Audit — Triage Script
# Md. Sowad Al-Mughni | Kitalon Labs | https://github.com/sowadalmughni/ai-codebase-audit
#
# USAGE:  bash scripts/triage.sh [root-dir]
# OUTPUT: GREEN / YELLOW / RED health verdict with finding counts by severity
# TIME:   Under 2 minutes on most codebases
# =============================================================================

ROOT="${1:-.}"

# shellcheck source=lib/preflight.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/preflight.sh"
require_gnu_grep
require_dir "$ROOT"
SCORE=100
CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0
declare -a CRITICAL_FINDINGS=()
declare -a HIGH_FINDINGS=()
declare -a MEDIUM_FINDINGS=()

# Exclude noise
EXCLUDE="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=.next --exclude-dir=venv --exclude-dir=__pycache__"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  AI CODEBASE AUDIT — TRIAGE"
echo "  https://github.com/sowadalmughni/ai-codebase-audit"
echo "═══════════════════════════════════════════════════"
echo "  Scanning: $ROOT"
echo "  $(date)"
echo "═══════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────────────
# CRITICAL: Secrets in source code
# ─────────────────────────────────────────────────────
echo "⏳ Scanning secrets..."

SECRET_PATTERNS=(
  "sk_live_[a-zA-Z0-9]{24,}"
  "sk_test_[a-zA-Z0-9]{24,}"
  "sk-[a-zA-Z0-9]{32,}"
  "sk-ant-api[a-zA-Z0-9\-]{20,}"
  "AKIA[A-Z0-9]{16}"
  "ghp_[A-Za-z0-9]{36}"
  "xoxb-[A-Za-z0-9\-]{50,}"
  "SG\.[a-zA-Z0-9\-_]{22}\.[a-zA-Z0-9\-_]{43}"
  "-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"
)

for pat in "${SECRET_PATTERNS[@]}"; do
  HITS=$(grep -rE "$pat" "$ROOT" $EXCLUDE --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.py" --include="*.env" 2>/dev/null | grep -v ".example" | grep -v ".sample" | wc -l)
  if [ "$HITS" -gt 0 ]; then
    CRITICAL=$((CRITICAL + 1))
    SCORE=$((SCORE - 20))
    CRITICAL_FINDINGS+=("Exposed API key pattern: $pat ($HITS occurrences)")
  fi
done

# Check .env tracked in git
if git -C "$ROOT" ls-files 2>/dev/null | grep -qE "^\.env$"; then
  CRITICAL=$((CRITICAL + 1))
  SCORE=$((SCORE - 20))
  CRITICAL_FINDINGS+=(".env file is tracked in git — credentials may be exposed in history")
fi

# Check NEXT_PUBLIC_ exposing server vars
if grep -rE "process\.env\.(OPENAI|ANTHROPIC|STRIPE|AWS|SUPABASE_SERVICE)" "$ROOT" $EXCLUDE --include="*.tsx" --include="*.jsx" 2>/dev/null | grep -q .; then
  CRITICAL=$((CRITICAL + 1))
  SCORE=$((SCORE - 20))
  CRITICAL_FINDINGS+=("Server-side env var referenced in client component — key exposed to browser")
fi

# ─────────────────────────────────────────────────────
# CRITICAL: Row Level Security
# ─────────────────────────────────────────────────────
echo "⏳ Scanning RLS..."

# Static check: tables with no RLS policy in migration files
RLS_DISABLED=$(grep -rE "(?i)DISABLE ROW LEVEL SECURITY" "$ROOT" $EXCLUDE --include="*.sql" --include="*.ts" 2>/dev/null | wc -l)
if [ "$RLS_DISABLED" -gt 0 ]; then
  CRITICAL=$((CRITICAL + 1))
  SCORE=$((SCORE - 20))
  CRITICAL_FINDINGS+=("Row Level Security explicitly disabled ($RLS_DISABLED occurrence(s)) — run scan-rls.sh for details")
fi

# Check for Supabase service role key in client files
if grep -rE "SUPABASE_SERVICE_ROLE_KEY|serviceRoleKey" "$ROOT" $EXCLUDE --include="*.tsx" --include="*.jsx" 2>/dev/null | grep -q .; then
  CRITICAL=$((CRITICAL + 1))
  SCORE=$((SCORE - 20))
  CRITICAL_FINDINGS+=("Supabase service role key found in client-side file — bypasses RLS entirely")
fi

# Live DB check (optional)
if [ -n "$DATABASE_URL" ]; then
  NO_RLS=$(psql "$DATABASE_URL" -t -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public' AND rowsecurity=false;" 2>/dev/null | tr -d ' ')
  if [ -n "$NO_RLS" ] && [ "$NO_RLS" -gt 0 ]; then
    CRITICAL=$((CRITICAL + 1))
    SCORE=$((SCORE - 20))
    CRITICAL_FINDINGS+=("$NO_RLS table(s) in public schema have RLS disabled — run scan-rls.sh for table names")
  fi
fi

# ─────────────────────────────────────────────────────
# HIGH: N+1 Query Patterns
# ─────────────────────────────────────────────────────
echo "⏳ Scanning N+1 patterns..."

N1_PATTERNS=(
  "for.*await.*(find|query|select|fetch|prisma|supabase|db\.)"
  "\.map\(.*async.*await.*(find|query|select|fetch)"
  "forEach.*async.*await"
)

for pat in "${N1_PATTERNS[@]}"; do
  HITS=$(grep -rPn "$pat" "$ROOT" $EXCLUDE --include="*.ts" --include="*.js" --include="*.py" 2>/dev/null | wc -l)
  if [ "$HITS" -gt 0 ]; then
    HIGH=$((HIGH + 1))
    SCORE=$((SCORE - 10))
    HIGH_FINDINGS+=("N+1 query risk: '$pat' ($HITS occurrence(s)) — run scan-n1-queries.sh for file paths")
  fi
done

# Missing pagination
UNPAGED=$(grep -rPn "(findAll|findMany|getAll)\(\{?(?!.*limit|.*take|.*page)" "$ROOT" $EXCLUDE --include="*.ts" 2>/dev/null | wc -l)
if [ "$UNPAGED" -gt 0 ]; then
  HIGH=$((HIGH + 1))
  SCORE=$((SCORE - 10))
  HIGH_FINDINGS+=("Unbounded list queries without pagination ($UNPAGED occurrence(s))")
fi

# ─────────────────────────────────────────────────────
# HIGH: Disconnected Schema (Integration Gaps)
# ─────────────────────────────────────────────────────
echo "⏳ Scanning schema connectivity..."

TODO_INTEGRATIONS=$(grep -rEn "TODO.*(api|backend|database|db|fetch|connect|wire|integrate|supabase|prisma)" "$ROOT" $EXCLUDE --include="*.ts" --include="*.tsx" --include="*.py" 2>/dev/null | wc -l)
if [ "$TODO_INTEGRATIONS" -gt 3 ]; then
  HIGH=$((HIGH + 1))
  SCORE=$((SCORE - 10))
  HIGH_FINDINGS+=("$TODO_INTEGRATIONS TODO comments marking integration gaps — run scan-schema.sh for details")
fi

MOCK_DATA=$(grep -rEn "const (mock|fake|dummy|stub)[A-Z]|// ?mock" "$ROOT" $EXCLUDE --include="*.ts" --include="*.tsx" --include="*.js" 2>/dev/null | wc -l)
if [ "$MOCK_DATA" -gt 0 ]; then
  HIGH=$((HIGH + 1))
  SCORE=$((SCORE - 10))
  HIGH_FINDINGS+=("Hardcoded mock data in $MOCK_DATA location(s) — may be used in production path")
fi

# ─────────────────────────────────────────────────────
# HIGH: Auth Guard Coverage
# ─────────────────────────────────────────────────────
echo "⏳ Scanning auth coverage..."

CLIENT_AUTH=$(grep -rEn "isAdmin|isAuthenticated|hasRole" "$ROOT" $EXCLUDE --include="*.tsx" --include="*.jsx" 2>/dev/null | wc -l)
if [ "$CLIENT_AUTH" -gt 0 ]; then
  HIGH=$((HIGH + 1))
  SCORE=$((SCORE - 10))
  HIGH_FINDINGS+=("$CLIENT_AUTH auth check(s) found in UI layer — ensure API enforces the same — run scan-auth.sh")
fi

# ─────────────────────────────────────────────────────
# MEDIUM: FinOps Patterns
# ─────────────────────────────────────────────────────
echo "⏳ Scanning FinOps patterns..."

RETRY_NOMAX=$(grep -rEn "retry|retryCount|attempts" "$ROOT" $EXCLUDE --include="*.ts" --include="*.js" --include="*.py" 2>/dev/null | grep -Ev "max|limit|[3-9]" | wc -l)
if [ "$RETRY_NOMAX" -gt 0 ]; then
  MEDIUM=$((MEDIUM + 1))
  SCORE=$((SCORE - 5))
  MEDIUM_FINDINGS+=("Retry logic without max attempt cap ($RETRY_NOMAX occurrence(s)) — infinite loop risk")
fi

UPLOAD_NOLIMIT=$(grep -rEn "(upload|multer|formidable|multipart)" "$ROOT" $EXCLUDE --include="*.ts" --include="*.js" 2>/dev/null | grep -Ev "size|limit|maxSize" | wc -l)
if [ "$UPLOAD_NOLIMIT" -gt 0 ]; then
  MEDIUM=$((MEDIUM + 1))
  SCORE=$((SCORE - 5))
  MEDIUM_FINDINGS+=("Upload handler(s) without file size limit ($UPLOAD_NOLIMIT occurrence(s))")
fi

# Floor the score
[ "$SCORE" -lt 0 ] && SCORE=0

# Auto-red conditions
AUTO_RED=false
[ "$CRITICAL" -gt 0 ] && AUTO_RED=true

# ─────────────────────────────────────────────────────
# VERDICT
# ─────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"

if [ "$AUTO_RED" = true ] || [ "$SCORE" -lt 50 ]; then
  echo "  STATUS:  🔴 RED — NOT PRODUCTION READY"
elif [ "$SCORE" -lt 80 ]; then
  echo "  STATUS:  🟡 YELLOW — FIX BEFORE LAUNCH"
else
  echo "  STATUS:  🟢 GREEN — PRODUCTION READY (minor issues)"
fi

echo "  SCORE:   $SCORE / 100"
echo ""
echo "  FINDINGS SUMMARY:"
echo "    CRITICAL : $CRITICAL finding(s)"
echo "    HIGH     : $HIGH finding(s)"
echo "    MEDIUM   : $MEDIUM finding(s)"
echo "    LOW      : (run full audit for LOW findings)"
echo "═══════════════════════════════════════════════════"

if [ "${#CRITICAL_FINDINGS[@]}" -gt 0 ]; then
  echo ""
  echo "  🚨 CRITICAL — STOP AND FIX THESE FIRST:"
  for finding in "${CRITICAL_FINDINGS[@]}"; do
    echo "    ✗ $finding"
  done
fi

if [ "${#HIGH_FINDINGS[@]}" -gt 0 ]; then
  echo ""
  echo "  ⚠️  HIGH — FIX BEFORE FIRST USER:"
  for finding in "${HIGH_FINDINGS[@]}"; do
    echo "    ✗ $finding"
  done
fi

if [ "${#MEDIUM_FINDINGS[@]}" -gt 0 ]; then
  echo ""
  echo "  📋 MEDIUM — FIX IN FIRST TWO SPRINTS:"
  for finding in "${MEDIUM_FINDINGS[@]}"; do
    echo "    ✗ $finding"
  done
fi

echo ""
echo "  NEXT STEPS:"
if [ "$CRITICAL" -gt 0 ]; then
  echo "    → Run: bash scripts/scan-secrets.sh $ROOT   (for secret locations)"
  echo "    → Run: bash scripts/scan-rls.sh $ROOT       (for RLS gaps)"
fi
if [ "$HIGH" -gt 0 ]; then
  echo "    → Run: bash scripts/scan-schema.sh $ROOT    (for disconnected tables)"
  echo "    → Run: bash scripts/scan-n1-queries.sh $ROOT (for query patterns)"
  echo "    → Run: bash scripts/scan-auth.sh $ROOT      (for auth gaps)"
fi
echo "    → For full audit: run all scan scripts, then fill templates/remediation-register.md"
echo ""

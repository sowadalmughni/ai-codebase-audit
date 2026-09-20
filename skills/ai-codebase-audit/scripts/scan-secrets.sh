#!/usr/bin/env bash
# =============================================================================
# AI Codebase Audit — Secrets Scanner
# Md. Sowad Al-Mughni | https://github.com/sowadalmughni/ai-codebase-audit
#
# USAGE:  bash scripts/scan-secrets.sh [root-dir]
# OUTPUT: Every credential exposure with file path, line number, and fix
# =============================================================================

ROOT="${1:-.}"

# shellcheck source=lib/preflight.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/preflight.sh"
require_gnu_grep
require_dir "$ROOT"
EXCLUDE="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=.next --exclude-dir=venv --exclude-dir=__pycache__"
FINDINGS=0

echo ""
echo "═══════════════════════════════════════════════════"
echo "  SECRETS SCAN — CRITICAL"
echo "  $(date)"
echo "═══════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────────────
# 1. Known API key patterns
# ─────────────────────────────────────────────────────
declare -A PATTERNS=(
  ["Stripe Live Secret"]="sk_live_[a-zA-Z0-9]{24,}"
  ["Stripe Test Secret"]="sk_test_[a-zA-Z0-9]{24,}"
  ["OpenAI Key"]="sk-[a-zA-Z0-9]{32,}"
  ["Anthropic Key"]="sk-ant-api[a-zA-Z0-9\-]{20,}"
  ["AWS Access Key"]="AKIA[A-Z0-9]{16}"
  ["GitHub PAT"]="ghp_[A-Za-z0-9]{36}"
  ["GitHub App Token"]="ghs_[A-Za-z0-9]{36}"
  ["Slack Bot Token"]="xoxb-[A-Za-z0-9\-]{50,}"
  ["SendGrid Key"]="SG\.[a-zA-Z0-9\-_]{22}\.[a-zA-Z0-9\-_]{43}"
  ["Private Key Block"]="-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"
  ["Hardcoded Password"]="(password|passwd|pwd)\s*[=:]\s*['\"][^'\"\\s]{6,}['\"]"
)

for name in "${!PATTERNS[@]}"; do
  pat="${PATTERNS[$name]}"
  echo "Checking: $name"
  RESULTS=$(grep -rPn "$pat" "$ROOT" $EXCLUDE \
    --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
    --include="*.py" --include="*.rb" --include="*.go" --include="*.rs" \
    --include="*.env" --include="*.yaml" --include="*.yml" \
    2>/dev/null | grep -v "\.example" | grep -v "\.sample" | grep -v "test\." | grep -v "spec\.")
  if [ -n "$RESULTS" ]; then
    echo ""
    echo "  ⛔  CRITICAL — $name"
    echo "$RESULTS" | while IFS= read -r line; do
      echo "      $line"
    done
    echo ""
    echo "  FIX:"
    echo "    1. Rotate this key immediately at the provider — assume it is compromised"
    echo "    2. Remove from source file and move to environment variable:"
    echo "       export ${name^^// /_}=\"your-key-here\"  # in .env (gitignored)"
    echo "    3. If this was ever committed: rewrite git history with git-filter-repo"
    echo "       pip install git-filter-repo"
    echo "       git filter-repo --path-glob '*' --replace-text <(echo 'COMPROMISED_KEY==>***REMOVED***')"
    echo ""
    FINDINGS=$((FINDINGS + 1))
  fi
done

# ─────────────────────────────────────────────────────
# 2. .env files tracked in git
# ─────────────────────────────────────────────────────
echo "Checking: .env files in git"
TRACKED_ENV=$(git -C "$ROOT" ls-files 2>/dev/null | grep -E "\.env$|\.env\.(local|production|staging|development)$")
if [ -n "$TRACKED_ENV" ]; then
  echo ""
  echo "  ⛔  CRITICAL — .env files tracked in git repository"
  echo "$TRACKED_ENV" | while IFS= read -r file; do
    echo "      $ROOT/$file"
  done
  echo ""
  echo "  FIX:"
  echo "    1. Add to .gitignore immediately:"
  echo "       echo '.env' >> .gitignore"
  echo "       echo '.env.*' >> .gitignore"
  echo "    2. Remove from git tracking without deleting the file:"
  echo "       git rm --cached .env"
  echo "    3. If credentials are in git history, rotate all secrets and rewrite history"
  echo ""
  FINDINGS=$((FINDINGS + 1))
fi

# ─────────────────────────────────────────────────────
# 3. Server-side secrets in client-side files
# ─────────────────────────────────────────────────────
echo "Checking: Server secrets in client components"
CLIENT_EXPOSURE=$(grep -rPn "process\.env\.(OPENAI|ANTHROPIC|STRIPE_SECRET|AWS_SECRET|SUPABASE_SERVICE_ROLE|DATABASE_URL)" \
  "$ROOT" $EXCLUDE --include="*.tsx" --include="*.jsx" 2>/dev/null)
if [ -n "$CLIENT_EXPOSURE" ]; then
  echo ""
  echo "  ⛔  CRITICAL — Server-side env vars in client components"
  echo "$CLIENT_EXPOSURE" | while IFS= read -r line; do
    echo "      $line"
  done
  echo ""
  echo "  FIX:"
  echo "    Server-side env vars must never appear in .tsx or .jsx files."
  echo "    Move the logic to an API route:"
  echo "    // pages/api/action.ts OR app/api/action/route.ts"
  echo "    export async function POST(req: Request) {"
  echo "      const result = await callExternalService(process.env.SECRET_KEY)"
  echo "      return Response.json(result)"
  echo "    }"
  echo ""
  FINDINGS=$((FINDINGS + 1))
fi

# ─────────────────────────────────────────────────────
# 4. Supabase service role key in client code
# ─────────────────────────────────────────────────────
echo "Checking: Supabase service role key in client"
SUPABASE_SERVICE=$(grep -rPn "SUPABASE_SERVICE_ROLE_KEY|serviceRoleKey|service_role" \
  "$ROOT" $EXCLUDE --include="*.tsx" --include="*.jsx" --include="*.ts" --include="*.js" 2>/dev/null \
  | grep -v "server\|api\|route\|backend\|middleware")
if [ -n "$SUPABASE_SERVICE" ]; then
  echo ""
  echo "  ⛔  CRITICAL — Supabase service role key outside server context"
  echo "$SUPABASE_SERVICE" | while IFS= read -r line; do
    echo "      $line"
  done
  echo ""
  echo "  FIX:"
  echo "    The service role key bypasses Row Level Security entirely."
  echo "    It must ONLY be used in server-side code."
  echo "    Replace client usage with the anon key + proper RLS policies."
  echo ""
  FINDINGS=$((FINDINGS + 1))
fi

# ─────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════"
if [ "$FINDINGS" -eq 0 ]; then
  echo "  ✓ No secret exposures detected"
  echo "  Note: This scan uses static pattern matching."
  echo "  Also use: truffleHog, gitleaks, or detect-secrets for deeper git history scanning"
else
  echo "  ⛔ $FINDINGS CRITICAL finding(s) — rotate all identified keys immediately"
  echo "  Do not deploy or share this codebase until all CRITICAL findings are resolved"
fi
echo "═══════════════════════════════════════════════════"
echo ""

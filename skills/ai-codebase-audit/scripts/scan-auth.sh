#!/usr/bin/env bash
# =============================================================================
# AI Codebase Audit — Authentication & Authorization Scanner
# Md. Sowad Al-Mughni | https://github.com/sowadalmughni/ai-codebase-audit
#
# USAGE:  bash scripts/scan-auth.sh [root-dir]
# DETECTS: Routes without auth guards, UI-only auth checks, missing middleware
# =============================================================================

ROOT="${1:-.}"

# shellcheck source=lib/preflight.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/preflight.sh"
require_gnu_grep
require_dir "$ROOT"
EXCLUDE="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=.next --exclude-dir=__pycache__"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  AUTH GUARD SCAN — HIGH"
echo "  $(date)"
echo "═══════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────────────
# 1. NestJS: Controllers without @UseGuards
# ─────────────────────────────────────────────────────
CONTROLLER_FILES=$(find "$ROOT" -name "*.controller.ts" 2>/dev/null | grep -v "node_modules\|dist\|test\|spec")

if [ -n "$CONTROLLER_FILES" ]; then
  echo "── NestJS Controllers ───────────────────────────"
  for file in $CONTROLLER_FILES; do
    HAS_CLASS_GUARD=$(grep -c "@UseGuards" "$file" 2>/dev/null || echo 0)
    ROUTE_COUNT=$(grep -cP "@(Get|Post|Put|Delete|Patch)\(" "$file" 2>/dev/null || echo 0)

    if [ "$HAS_CLASS_GUARD" -eq 0 ] && [ "$ROUTE_COUNT" -gt 0 ]; then
      echo ""
      echo "  ⚠  HIGH — $file"
      echo "     $ROUTE_COUNT route(s) with no @UseGuards at controller or method level"
      grep -Pn "@(Get|Post|Put|Delete|Patch)\(" "$file" | head -10 | while IFS= read -r r; do
        echo "     $r"
      done
      echo ""
      echo "  FIX: Add at controller class level (protects all routes):"
      echo "    @UseGuards(JwtAuthGuard)"
      echo "    @Controller('resource')"
      echo "    export class ResourceController { ... }"
      echo ""
      echo "  Or per route (for mixed public/private controllers):"
      echo "    @Get(':id')"
      echo "    @UseGuards(JwtAuthGuard)"
      echo "    findOne(@Param('id') id: string) { ... }"
    else
      echo "  ✓ $file — guards present"
    fi
  done
fi

# ─────────────────────────────────────────────────────
# 2. FastAPI: Routes without Depends(get_current_user)
# ─────────────────────────────────────────────────────
FASTAPI_FILES=$(find "$ROOT" -name "*.py" 2>/dev/null | grep -v "node_modules\|__pycache__\|test\|spec\|migration")
FASTAPI_ROUTER=$(grep -rl "@app\.\|@router\." $FASTAPI_FILES 2>/dev/null)

if [ -n "$FASTAPI_ROUTER" ]; then
  echo ""
  echo "── FastAPI Routes ───────────────────────────────"
  for file in $FASTAPI_ROUTER; do
    # Find route decorators not followed by a Depends auth check
    grep -Pn "@(app|router)\.(get|post|put|delete|patch)\(" "$file" 2>/dev/null | while IFS= read -r routeline; do
      linenum=$(echo "$routeline" | cut -d: -f1)
      # Check next 15 lines for Depends with auth
      context=$(sed -n "${linenum},$((linenum + 15))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -qP "Depends\(.*current_user|Depends\(.*verify|Depends\(.*auth|Security\("; then
        echo "  ⚠  HIGH — Possible unprotected route in $file:$linenum"
        echo "      $(echo "$routeline" | cut -d: -f2-)"
        echo "  FIX: Add dependency injection:"
        echo "    @router.get('/resource')"
        echo "    def get_resource(current_user: User = Depends(get_current_user)):"
      fi
    done
  done
fi

# ─────────────────────────────────────────────────────
# 3. Express/Next.js API routes without middleware
# ─────────────────────────────────────────────────────
echo ""
echo "── Express / Next.js API Routes ────────────────"

NEXT_API_ROUTES=$(find "$ROOT" -path "*/app/api/*" -o -path "*/pages/api/*" 2>/dev/null | grep -E "\.(ts|js)$" | grep -v "test\|spec\|node_modules\|dist")

if [ -n "$NEXT_API_ROUTES" ]; then
  for file in $NEXT_API_ROUTES; do
    HAS_AUTH=$(grep -cP "(getServerSession|getSession|verifyToken|authenticate|auth\(\)|withAuth|currentUser)" "$file" 2>/dev/null || echo 0)
    if [ "$HAS_AUTH" -eq 0 ]; then
      echo "  ⚠  HIGH — No auth check found in API route: $file"
      echo "  FIX (NextAuth): Add at top of handler:"
      echo "    const session = await getServerSession(authOptions)"
      echo "    if (!session) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 })"
    else
      echo "  ✓ $file"
    fi
  done
fi

# ─────────────────────────────────────────────────────
# 4. Client-side-only auth checks (bypassable)
# ─────────────────────────────────────────────────────
echo ""
echo "── Client-side auth checks (bypassable) ─────────"

CLIENT_AUTH_CHECKS=$(grep -rPn "(isAdmin|isAuthenticated|hasRole|userRole|isOwner)\s*&&" \
  "$ROOT" $EXCLUDE --include="*.tsx" --include="*.jsx" 2>/dev/null \
  | grep -v "test\|spec" | head -20)

if [ -n "$CLIENT_AUTH_CHECKS" ]; then
  echo ""
  echo "  ⚠  HIGH — Auth checks in UI components (bypassable via browser DevTools)"
  echo "$CLIENT_AUTH_CHECKS" | while IFS= read -r line; do
    echo "      $line"
  done
  echo ""
  echo "  FIX: UI auth checks control rendering only — they are not security."
  echo "  Every action these conditions protect must ALSO be protected at the API layer."
  echo "  A user with browser DevTools can remove the condition and call the API directly."
else
  echo "  ✓ No UI-only auth patterns found"
fi

# ─────────────────────────────────────────────────────
# 5. Publicly accessible admin routes
# ─────────────────────────────────────────────────────
echo ""
echo "── Scanning for admin routes ─────────────────────"

ADMIN_ROUTES=$(find "$ROOT" -path "*/api/admin*" -o -path "*/routes/admin*" -o -path "*/admin*controller*" 2>/dev/null | grep -E "\.(ts|js|py)$" | grep -v "node_modules\|dist\|test")

for file in $ADMIN_ROUTES; do
  HAS_ROLE_GUARD=$(grep -cP "(AdminGuard|RolesGuard|role.*admin|ADMIN|isAdmin.*true)" "$file" 2>/dev/null || echo 0)
  if [ "$HAS_ROLE_GUARD" -eq 0 ]; then
    echo "  ⚠  HIGH — Admin route without role guard: $file"
    echo "  FIX: Add role-based guard:"
    echo "    @UseGuards(JwtAuthGuard, RolesGuard)"
    echo "    @Roles('admin')"
    echo "    // or FastAPI: Depends(require_admin_role)"
  else
    echo "  ✓ $file — role guard detected"
  fi
done

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Auth scan complete"
echo "  Add confirmed findings to: templates/remediation-register.md"
echo "═══════════════════════════════════════════════════"
echo ""

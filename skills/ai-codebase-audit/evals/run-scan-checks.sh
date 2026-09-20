#!/usr/bin/env bash
# =============================================================================
# AI Codebase Audit — Scanner Validation Harness
# Md. Sowad Al-Mughni | Kitalon Labs | https://github.com/sowadalmughni/ai-codebase-audit
#
# Runs each scan script against evals/scan-fixtures/planted-issues, a fixture
# with one deliberately planted issue per failure mode, and asserts the
# expected finding actually surfaces. This is what stands behind the claim
# that these scanners work, rather than just look plausible.
#
# USAGE: bash evals/run-scan-checks.sh
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/../scripts"
FIXTURE_SRC="$SCRIPT_DIR/scan-fixtures/planted-issues"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

cp -r "$FIXTURE_SRC"/. "$WORKDIR"/

# Generated here rather than stored as a static fixture file: a contiguous
# string matching Stripe's live-key shape gets flagged by GitHub push
# protection even when it's obviously fake test data. Splitting it across two
# variables keeps the committed source free of anything that pattern-matches
# a real secret, while still producing a real match on disk for the scanner
# to catch at run time.
mkdir -p "$WORKDIR/src/lib"
FAKE_KEY_PREFIX="sk_live_"
FAKE_KEY_BODY="FAKEKEYFORFIXTUREVALIDATIONONLY1234"
cat > "$WORKDIR/src/lib/payments.ts" <<EOF
import Stripe from 'stripe';

// Fixture: intentionally hardcoded key so scan-secrets.sh has something real to catch.
export const stripeClient = new Stripe('${FAKE_KEY_PREFIX}${FAKE_KEY_BODY}');
EOF

# Ephemeral repo, never committed to the real project — exists only so the
# ".env tracked in git" check in scan-secrets.sh has something real to find.
git -C "$WORKDIR" init -q
git -C "$WORKDIR" add .env

PASS=0
FAIL=0

check() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s\n' "$haystack" | grep -qF "$needle"; then
    echo "  ✓ PASS — $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL — $label (expected to find: \"$needle\")"
    FAIL=$((FAIL + 1))
  fi
}

echo "═══════════════════════════════════════════════════"
echo "  Scanner validation — fixture: planted-issues"
echo "═══════════════════════════════════════════════════"

echo ""
echo "== scan-secrets.sh =="
OUT=$(bash "$SCRIPTS_DIR/scan-secrets.sh" "$WORKDIR" 2>&1)
check "hardcoded Stripe key detected" "$OUT" "payments.ts"
check ".env tracked in git detected" "$OUT" ".env files tracked in git"

echo ""
echo "== scan-rls.sh =="
OUT=$(bash "$SCRIPTS_DIR/scan-rls.sh" "$WORKDIR" 2>&1)
check "orders table missing RLS detected" "$OUT" "'orders'"
check "audit_log table missing RLS detected" "$OUT" "'audit_log'"

echo ""
echo "== scan-auth.sh =="
OUT=$(bash "$SCRIPTS_DIR/scan-auth.sh" "$WORKDIR" 2>&1)
check "unguarded controller route detected" "$OUT" "orders.controller.ts"

echo ""
echo "== scan-schema.sh =="
OUT=$(bash "$SCRIPTS_DIR/scan-schema.sh" "$WORKDIR" 2>&1)
check "disconnected audit_log table detected" "$OUT" "'audit_log'"
check "hardcoded mock data detected" "$OUT" "Dashboard.tsx"
check "integration TODO comment detected" "$OUT" "integration gap"

echo ""
echo "== scan-n1-queries.sh =="
OUT=$(bash "$SCRIPTS_DIR/scan-n1-queries.sh" "$WORKDIR" 2>&1)
check "N+1 query-in-loop detected" "$OUT" "reports.service.ts"

echo ""
echo "== triage.sh (aggregate check) =="
OUT=$(bash "$SCRIPTS_DIR/triage.sh" "$WORKDIR" 2>&1)
check "overall verdict is RED given multiple CRITICALs" "$OUT" "RED"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]

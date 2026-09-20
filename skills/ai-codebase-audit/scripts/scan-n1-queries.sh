#!/usr/bin/env bash
# =============================================================================
# AI Codebase Audit — N+1 Query & FinOps Scanner
# Md. Sowad Al-Mughni | https://github.com/sowadalmughni/ai-codebase-audit
#
# USAGE:  bash scripts/scan-n1-queries.sh [root-dir]
# CONTEXT: Single AI-generated admin dashboard caused $12,000/month in database
#          costs from N+1 queries. Unoptimized AI code inflates cloud bills 400%.
# =============================================================================

ROOT="${1:-.}"
EXCLUDE="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=.next --exclude-dir=__pycache__"
FINDINGS=0

echo ""
echo "═══════════════════════════════════════════════════"
echo "  N+1 QUERY & FINOPS SCAN — HIGH"
echo "  $(date)"
echo "═══════════════════════════════════════════════════"
echo "  The '\$500 query' scenario: a single lazy database"
echo "  commit from AI-generated code can add hundreds of"
echo "  dollars per day to your cloud bill."
echo "═══════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────────────
# 1. For loop with query inside
# ─────────────────────────────────────────────────────
echo "── Scanning: query-in-loop patterns ─────────────"

echo ""
echo "  Pattern: for...await query"
HITS=$(grep -rPn "for\s*\(|for\s+\w+" "$ROOT" $EXCLUDE --include="*.ts" --include="*.js" 2>/dev/null -l)
for file in $HITS; do
  grep -Pn "for.*\{" "$file" 2>/dev/null | while IFS= read -r forline; do
    linenum=$(echo "$forline" | cut -d: -f1)
    # Check if next 10 lines contain an await query
    context=$(sed -n "${linenum},$((linenum + 10))p" "$file" 2>/dev/null)
    if echo "$context" | grep -qP "await.*(find|query|select|prisma\.|supabase\.|db\.|\.get|\.fetch)"; then
      echo "  ⚠  HIGH — N+1 risk in $file:$linenum"
      sed -n "${linenum},$((linenum + 8))p" "$file" | head -8 | while IFS= read -r l; do
        echo "      $l"
      done
      echo ""
      FINDINGS=$((FINDINGS + 1))
    fi
  done
done

echo ""
echo "  Pattern: .map() with async/await query"
grep -rPn "\.map\(\s*async" "$ROOT" $EXCLUDE --include="*.ts" --include="*.js" 2>/dev/null | head -20 | while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  linenum=$(echo "$line" | cut -d: -f2)
  context=$(sed -n "${linenum},$((linenum + 5))p" "$file" 2>/dev/null)
  if echo "$context" | grep -qP "await.*(find|query|select|prisma|supabase|db\.)"; then
    echo "  ⚠  HIGH — N+1 via .map() in $file:$linenum"
    echo "      $(echo "$line" | cut -d: -f3-)"
    FINDINGS=$((FINDINGS + 1))
  fi
done

# ─────────────────────────────────────────────────────
# 2. Missing eager loading
# ─────────────────────────────────────────────────────
echo ""
echo "── Scanning: missing eager loading / includes ───"

echo ""
echo "  TypeORM — findOne/find without relations:"
grep -rPn "findOne\(\{(?!.*relations)|find\(\{(?!.*relations)|findAll\(\{(?!.*include)" \
  "$ROOT" $EXCLUDE --include="*.ts" 2>/dev/null | head -15 | while IFS= read -r line; do
  echo "  ⚠  MEDIUM — $line"
  echo "      FIX: add relations: ['relatedEntity'] to the find options"
done

echo ""
echo "  Prisma — findMany without include:"
grep -rPn "findMany\(\{(?!.*include)" \
  "$ROOT" $EXCLUDE --include="*.ts" 2>/dev/null | grep -v "test\|spec" | head -15 | while IFS= read -r line; do
  echo "  ⚠  MEDIUM — $line"
  echo "      FIX: add include: { relatedModel: true } to findMany"
done

echo ""
echo "  SQLAlchemy — query without joinedload:"
grep -rPn "\.query\([A-Z]|session\.exec\(" \
  "$ROOT" $EXCLUDE --include="*.py" 2>/dev/null | grep -v "test\|spec" | head -15 | while IFS= read -r line; do
  echo "  ⚠  MEDIUM — $line"
  echo "      FIX: add .options(joinedload(Model.related)) before .all()"
done

# ─────────────────────────────────────────────────────
# 3. Unbounded list queries (missing pagination)
# ─────────────────────────────────────────────────────
echo ""
echo "── Scanning: unbounded list queries ────────────"

echo ""
echo "  List endpoints without pagination:"
grep -rPn "(findAll|findMany|getAll|listAll)\(\{?(?!.*limit|.*take|.*page|.*skip)" \
  "$ROOT" $EXCLUDE --include="*.ts" --include="*.js" 2>/dev/null \
  | grep -v "test\|spec\|migration" | head -20 | while IFS= read -r line; do
  echo "  ⚠  HIGH — $line"
  echo "      FIX: add take, skip (TypeORM) or limit, offset (Prisma/raw SQL)"
done

echo ""
echo "  SELECT * without LIMIT:"
grep -rPn "(?i)SELECT \* FROM (?!.*LIMIT|.*limit)" \
  "$ROOT" $EXCLUDE --include="*.ts" --include="*.js" --include="*.py" --include="*.sql" 2>/dev/null \
  | grep -v "test\|spec" | head -15 | while IFS= read -r line; do
  echo "  ⚠  HIGH — $line"
  echo "      FIX: Add LIMIT \$1 OFFSET \$2 with pagination parameters"
done

# ─────────────────────────────────────────────────────
# 4. Missing database indexes
# ─────────────────────────────────────────────────────
echo ""
echo "── Scanning: potential missing indexes ─────────"

# Find foreign keys without index
grep -rPn "REFERENCES\s+\w+\s*\(" \
  "$ROOT" $EXCLUDE --include="*.sql" --include="*.ts" 2>/dev/null \
  | grep -v "CREATE INDEX" | head -20 | while IFS= read -r line; do
  echo "  ⚠  MEDIUM — Foreign key without verified index: $line"
  echo "      FIX: CREATE INDEX idx_tablename_columnname ON tablename(columnname);"
done

# ─────────────────────────────────────────────────────
# 5. Fan-out patterns
# ─────────────────────────────────────────────────────
echo ""
echo "── Scanning: accidental fan-out patterns ────────"

echo ""
echo "  Multiple sequential awaits in single handler:"
grep -rPn "await.*\n.*await.*\n.*await.*\n.*await" \
  "$ROOT" $EXCLUDE --include="*.ts" --include="*.js" 2>/dev/null | head -10 | while IFS= read -r line; do
  echo "  ⚠  MEDIUM — Multiple sequential awaits: $line"
  echo "      FIX: Use Promise.all() for independent calls, or queue for external APIs"
done

echo ""
echo "  HTTP call inside database transaction:"
grep -rPzPn "(?s)(BEGIN|transaction|tx\.)(.{0,500})(fetch|axios|http\.|request\.)" \
  "$ROOT" $EXCLUDE --include="*.ts" --include="*.js" 2>/dev/null | head -5 | while IFS= read -r line; do
  echo "  ⚠  HIGH — External call inside DB transaction: holds DB connection"
  echo "      $line"
  echo "      FIX: Move external calls outside transaction boundaries"
done

# ─────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  N+1 / FinOps scan complete"
echo "  Cost impact: Each N+1 pattern above can multiply"
echo "  database costs by 10x-100x at production scale."
echo "  Add confirmed findings to: templates/remediation-register.md"
echo "═══════════════════════════════════════════════════"
echo ""

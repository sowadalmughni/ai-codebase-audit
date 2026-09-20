# Changelog

All notable changes to `ai-codebase-audit` are documented here.

## [1.1.0] — 2026-09-20

### Added

- `scripts/lib/preflight.sh` — every scan script now checks for GNU grep's `-P` (PCRE) support and a valid target directory before scanning, and exits with a clear error instead of silently reporting zero findings when a dependency is missing. A scanner that fails silently and reports a false GREEN is worse than one that crashes.
- `evals/scan-fixtures/planted-issues/` — a synthetic fixture codebase with one deliberately planted issue per failure mode (hardcoded key, table with no RLS, unguarded controller route, N+1 loop, disconnected table, hardcoded mock data), so the detection claims are checked against a known answer instead of taken on faith.
- `evals/run-scan-checks.sh` — runs every scan script against the fixture and asserts each planted issue is actually caught; exits non-zero on any regression. Run this after changing any pattern in `config/audit-vectors.json`.
- `evals/trigger-evals.json` — should-trigger / should-not-trigger phrasing checks used to tighten the `SKILL.md` description.

### Changed

- `SKILL.md` description — explicitly excludes generic/style code review ("not a linter") after the trigger evals showed the bare "review" verb over-matching requests like variable-naming feedback; the "database bill" trigger now anchors to wanting the codebase itself inspected, to avoid over-matching pure cloud-billing/cost-center questions that involve no code.

## [1.0.0] — 2026-09-20

### Added

- `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json` — Claude Code plugin marketplace support (`/plugin marketplace add` + `/plugin install ai-codebase-audit@sowadalmughni`)
- `LICENSE` — MIT
- `SKILL.md` — Four invocation modes: Triage, Full Audit, Deep Dive, Remediation Planning
- `config/audit-vectors.json` — Detection patterns for all six failure modes: secrets (15 key patterns), RLS (live DB + static), auth (NestJS, FastAPI, Express, Next.js), schema connectivity, N+1 queries (TypeORM, Prisma, SQLAlchemy, raw SQL), and FinOps patterns (fan-out, unbounded storage, runaway loops, missing caching)
- `config/severity-matrix.json` — Severity definitions with score deductions, auto-RED conditions, effort estimates, and remediation SLAs
- `scripts/triage.sh` — Fast 2-minute health check outputting GREEN/YELLOW/RED with finding counts
- `scripts/scan-secrets.sh` — Credential detection with exact file paths, lines, and fix snippets including git history remediation guidance
- `scripts/scan-rls.sh` — Row Level Security audit with live Postgres check (when DATABASE_URL available) and static migration scan
- `scripts/scan-auth.sh` — Auth guard audit covering NestJS, FastAPI, Express, and Next.js — including client-side-only auth check detection
- `scripts/scan-schema.sh` — Schema connectivity and integration gap detection including hardcoded mocks, TODO comments, and stub functions
- `scripts/scan-n1-queries.sh` — N+1 pattern detection for TypeORM, Prisma, and SQLAlchemy plus FinOps patterns: fan-out, missing pagination, unbounded queries, missing indexes
- `templates/remediation-register.md` — Structured finding register with one row per finding, severity ordering, effort estimates, and approval gate
- `templates/executive-summary.md` — Client-facing audit report with plain-language finding descriptions and cost-of-inaction framing

### Design Decisions

- Audit and remediation are always separate phases. No inline fix behavior in this skill.
- Scripts are framework-aware: NestJS, FastAPI, Flask, Express, Next.js patterns are all covered.
- Live database check is optional and falls back to static analysis gracefully.
- Every finding in every template requires: file path, line number, evidence snippet, and fix code.
- Auto-RED conditions enforce that any CRITICAL finding overrides the numeric score.
- The triage script is designed as a commercial entry point: fast enough to run during a 45-minute scoping call.

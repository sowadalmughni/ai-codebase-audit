# ai-codebase-audit

A Claude Code skill that audits any AI-generated or AI-assisted codebase for the six failure modes that cause production collapse.

**The problem:** A founder can spend 18 days building with AI tools and end up with a codebase where the database schema exists but is never connected, the frontend pages have no backend integration, the backend modules have no entry points, and there is no shared data flow. The code compiles. The screen renders. The product does not work. Cleanup costs $50,000 to $500,000.

This skill runs a systematic, severity-ranked audit that catches these problems before they become rescue engagements.

---

## Install

**Via Claude Code plugin marketplace (recommended):**
```bash
/plugin marketplace add sowadalmughni/ai-codebase-audit
/plugin install ai-codebase-audit@sowadalmughni
```

**Via npx (works with any agent that supports the open skills format):**
```bash
npx skills add https://github.com/sowadalmughni/ai-codebase-audit
```

**Manually (project-level):**
```bash
git clone https://github.com/sowadalmughni/ai-codebase-audit /tmp/ai-codebase-audit
mkdir -p .claude/skills
cp -r /tmp/ai-codebase-audit/skills/ai-codebase-audit .claude/skills/ai-codebase-audit
```

**Personal (follows you across all projects):**
```bash
git clone https://github.com/sowadalmughni/ai-codebase-audit /tmp/ai-codebase-audit
mkdir -p ~/.claude/skills
cp -r /tmp/ai-codebase-audit/skills/ai-codebase-audit ~/.claude/skills/ai-codebase-audit
```

### Requirements

Scripts are POSIX bash and rely on GNU grep's `-P` (PCRE) flag. They run as-is on Linux, WSL, and Git Bash on Windows. On stock macOS, install GNU grep first (`brew install grep`) — BSD grep does not support `-P`, and every script now checks for this at startup and exits with a clear error rather than silently under-reporting. A live RLS check additionally requires `psql` and a `DATABASE_URL`; without it, `scan-rls.sh` falls back to static analysis only.

### Validating the Scanners

Don't take the detection claims on faith — `evals/scan-fixtures/planted-issues/` is a small synthetic codebase with one deliberately planted issue per failure mode (a hardcoded key, a table with no RLS, an unguarded controller route, an N+1 loop, a disconnected table, hardcoded mock data). Run:

```bash
bash skills/ai-codebase-audit/evals/run-scan-checks.sh
```

This runs every scan script against the fixture and asserts each planted issue is actually caught, printing a PASS/FAIL line per assertion and exiting non-zero if anything regresses. Run this after modifying any detection pattern in `config/audit-vectors.json` or the scripts themselves.

---

## Quick Start — Triage in 2 Minutes

```bash
bash .claude/skills/ai-codebase-audit/scripts/triage.sh .
```

Output:
```
═══════════════════════════════════════════════════
  AI CODEBASE AUDIT — TRIAGE
═══════════════════════════════════════════════════
  STATUS:  🔴 RED — NOT PRODUCTION READY
  SCORE:   32 / 100

  FINDINGS SUMMARY:
    CRITICAL : 3 finding(s)
    HIGH     : 5 finding(s)
    MEDIUM   : 2 finding(s)

  🚨 CRITICAL — STOP AND FIX THESE FIRST:
    ✗ Exposed API key pattern: sk_live_... (1 occurrence)
    ✗ .env file is tracked in git
    ✗ 2 table(s) with RLS disabled

  ⚠️ HIGH — FIX BEFORE FIRST USER:
    ✗ N+1 query risk: for...await query (3 occurrences)
    ✗ 8 integration gap TODO comments
```

Or invoke via Claude:

> *"Audit this codebase for security gaps"*
> *"Triage my AI-generated app before launch"*
> *"Why is my database bill so high?"*
> *"Find what's broken in this project"*

---

## The Six Failure Modes

| # | Failure Mode | Severity | Script |
|---|-------------|---------|--------|
| 1 | Disconnected schema — tables in migrations, never queried | HIGH | `scan-schema.sh` |
| 2 | Unwired frontend — pages with hardcoded mocks, no real API calls | HIGH | `scan-schema.sh` |
| 3 | Incomplete backend wiring — services registered nowhere | HIGH | `scan-auth.sh` |
| 4 | Missing Row Level Security — user data publicly readable | CRITICAL | `scan-rls.sh` |
| 5 | N+1 query explosions — $12K/month database bills | HIGH | `scan-n1-queries.sh` |
| 6 | Exposed secrets + broken auth — credentials in source, UI-only guards | CRITICAL | `scan-secrets.sh` |

---

## What's Included

```
ai-codebase-audit/
├── .claude-plugin/
│   ├── marketplace.json              ← Claude Code plugin marketplace manifest
│   └── plugin.json                   ← Plugin manifest
├── skills/
│   └── ai-codebase-audit/
│       ├── SKILL.md                  ← Skill definition and audit workflow
│       ├── config/
│       │   ├── audit-vectors.json    ← Detection patterns for all six failure modes
│       │   └── severity-matrix.json  ← Severity definitions, score deductions, SLAs
│       ├── templates/
│       │   ├── remediation-register.md  ← Structured output: one row per finding
│       │   └── executive-summary.md     ← Client-facing audit report
│       ├── scripts/
│       │   ├── lib/preflight.sh      ← Shared dependency checks (fails loudly, not silently)
│       │   ├── triage.sh             ← Fast 2-minute health check (GREEN/YELLOW/RED)
│       │   ├── scan-secrets.sh       ← CRITICAL: credentials and API key detection
│       │   ├── scan-rls.sh           ← CRITICAL: Row Level Security audit
│       │   ├── scan-auth.sh          ← HIGH: authentication and authorization gaps
│       │   ├── scan-schema.sh        ← HIGH: disconnected schema and integration gaps
│       │   └── scan-n1-queries.sh    ← HIGH: N+1 patterns and FinOps risks
│       └── evals/
│           ├── run-scan-checks.sh    ← Validates every scanner against known-planted issues
│           ├── scan-fixtures/        ← Fixture codebase, one planted issue per failure mode
│           └── trigger-evals.json    ← Should-trigger / should-not-trigger phrasing checks
├── README.md                         ← This file
├── CHANGELOG.md
└── LICENSE                           ← MIT
```

---

## Invocation Modes

| Mode | Trigger | Output |
|------|---------|--------|
| **Triage** | "quick audit", "triage", "health check" | GREEN/YELLOW/RED score, finding counts |
| **Full Audit** | "audit the codebase", "find all issues" | Complete remediation register |
| **Deep Dive** | "check security", "scan for N+1", "RLS audit" | Single-category focused report |
| **Remediation Planning** | "generate fix tasks for [finding]" | Atomic prompts (SKILL/DEPENDS/TASKS/VERIFY) |

---

## The Audit Principle

**Audit and remediation are always separate phases.**

This is not a preference — it is a discipline. An inline fix during an audit masks deeper structural problems, loses the severity ranking, and breaks the traceability between findings and fixes.

The workflow:

1. Run scans → raw findings
2. Populate `remediation-register.md` → severity-ranked register
3. Get register approved → remediation begins in severity order
4. Generate atomic fix prompts → each finding becomes a verifiable task

---

## Companion Skill

This skill pairs with [spec-driven-dev](https://github.com/sowadalmughni/spec-driven-dev), which prevents these failure modes from occurring in new development by enforcing architecture approval before code generation.

```
Prevention:  spec-driven-dev  →  architecture before code
Remediation: ai-codebase-audit  →  audit before fix
```

---

## About

Built by **Md. Sowad Al-Mughni** — Founder & CEO of [Kitalon Labs](https://www.kitalonlabs.com).

The methodology behind this skill emerged from a systematic audit of AI-generated codebases — including a rescue engagement where a founder spent 18 days building an application with AI tools, then discovered the database schema was never connected, the frontend had no backend integration, and the backend had no entry points. The cleanup was an $8,000 engagement.

These six failure modes are not edge cases. They are the predictable output of AI tools that optimize for visual correctness over architectural coherence.

- Website: [www.kitalonlabs.com](https://www.kitalonlabs.com)
- GitHub: [github.com/sowadalmughni](https://github.com/sowadalmughni)
- Email: [sowad.al.mughni@gmail.com](mailto:sowad.al.mughni@gmail.com)

---

## License

MIT — see [LICENSE](LICENSE). Use freely, attribution appreciated.

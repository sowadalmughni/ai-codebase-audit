#!/usr/bin/env bash
# =============================================================================
# AI Codebase Audit — Preflight Checks
# Md. Sowad Al-Mughni | Kitalon Labs | https://github.com/sowadalmughni/ai-codebase-audit
#
# Sourced by every scan script. A scanner that fails silently and reports
# zero findings is worse than one that crashes — a false GREEN on a security
# audit is the failure mode this file exists to prevent.
# =============================================================================

require_gnu_grep() {
  if ! printf 'test123\n' | grep -P '\d+' >/dev/null 2>&1; then
    echo "" >&2
    echo "  ⛔ ERROR: grep on this system does not support -P (PCRE)." >&2
    echo "     This scanner relies on -P and will silently under-report without it." >&2
    echo "" >&2
    echo "     Fix:" >&2
    echo "       macOS:   brew install grep   (then re-run using ggrep, or put" >&2
    echo "                gnubin on PATH per the brew install notes)" >&2
    echo "       Windows: run under WSL or Git Bash (both ship GNU grep)" >&2
    echo "       Linux:   GNU grep is standard — check your \$PATH" >&2
    echo "" >&2
    exit 1
  fi
}

require_dir() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo "" >&2
    echo "  ⛔ ERROR: directory not found: $dir" >&2
    echo "     Check the path passed as the scan target." >&2
    echo "" >&2
    exit 1
  fi
}

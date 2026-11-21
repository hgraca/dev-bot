#!/usr/bin/env bash
# ---
# description: Run one or more BATS suites in a single call and print only what failed — the assertion blocks and the summary, with a non-zero exit when anything failed
# ---
# =============================================================================
# src/agentic/dev/tools/bats-run.mcp.sh
# Runs the named suite files together and reports failures only.
#
# The corpus showed the same wrapper retyped per file:
#   bats path/x_tests.bats 2>&1 | tail -6
# and the agent then re-read the tail to learn what broke. This runs the files
# in one invocation, prints each failing test with its diagnostic lines, and
# ends with the pass/fail counts.
#
# BATS_LIB_PATH is filled from the global npm root when unset, because raw
# `bats` cannot find bats-assert/bats-support without it.
#
# Usage:
#   bats-run.mcp.sh src/agentic/git/tests/git-report_tests.bats
#   bats-run.mcp.sh bin/tests/commands_tests.bats --verbose
#
# Exit: 0 all passed, 1 something failed, 2 usage, 3 bats missing.
#
# Dependencies: bats, node/npm (for the shared test libraries)
# =============================================================================

set -uo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"bats-run","description":"Run one or more BATS suite files in a single call and print only the failures — each failing test with its diagnostic block, plus the summary counts — exiting non-zero when anything failed. Replaces running one file at a time through `2>&1 | tail -6` and re-reading the tail.","parameters":{"type":"object","properties":{"files":{"type":"array","items":{"type":"string"},"description":"BATS suite files to run (one or more)"},"verbose":{"type":"boolean","description":"Also print passing tests"}},"required":["files"]}}
JSON
    exit 0
    ;;
  -h | --help)
    sed -n '6,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

verbose=0
files=()
for arg in "$@"; do
  case "$arg" in
    --verbose | -v) verbose=1 ;;
    -*) echo "ERROR: unknown flag: $arg" >&2; exit 2 ;;
    *) files+=("$arg") ;;
  esac
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "ERROR: no suite files given — pass one or more .bats paths" >&2
  exit 2
fi
for f in "${files[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: suite file not found: $f" >&2
    exit 2
  fi
done

if ! command -v bats >/dev/null 2>&1; then
  echo "FATAL: bats is not installed or not on PATH" >&2
  exit 3
fi

if [[ -z "${BATS_LIB_PATH:-}" ]]; then
  if command -v npm >/dev/null 2>&1; then
    BATS_LIB_PATH="$(npm root -g 2>/dev/null || true)"
  fi
  export BATS_LIB_PATH
fi

raw="$(mktemp "${TMPDIR:-/tmp}/bats-run.XXXXXX")"
trap 'rm -f "$raw"' EXIT

bats "${files[@]}" >"$raw" 2>&1
status=$?

# Print the failure blocks: from `not ok` up to the next test boundary, plus the
# trailing summary lines. Passing tests are dropped unless --verbose.
awk -v verbose="$verbose" '
  /^not ok /  { inblock = 1; print; next }
  /^ok /      { inblock = 0; if (verbose) print; next }
  inblock     { print; next }
  /^[0-9]+\.\.[0-9]+$/ { next }
  /^[0-9]+ tests?,/ { print; next }
  /^# (failed|tests)/ { print; next }
' "$raw"

failed=$(grep -c '^not ok ' "$raw" || true)
passed=$(grep -c '^ok ' "$raw" || true)
echo ""
echo "$passed passed, $failed failed"

if [[ $status -eq 0 ]]; then
  exit 0
fi
echo "FAILED: $failed test(s) — see the blocks above" >&2
exit 1

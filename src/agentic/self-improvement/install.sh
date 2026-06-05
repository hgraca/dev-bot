#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

# Info/ok/skip helpers
info()  { printf "  [ \033[33mINFO\033[0m ] %s\n" "$*"; }
ok()    { printf "  [  \033[32mOK\033[0m  ] %s\n" "$*"; }
skip()  { printf "  [ \033[36mSKIP\033[0m ] %s\n" "$*"; }

info "self-improvement module — checking dependencies"

# Check shell availability (trivially true for bash scripts)
if command -v bash &>/dev/null; then
    ok "Shell found: bash"
else
    skip "bash not found — this should never happen on a POSIX system."
fi

# Optional: check bats availability for running tests
if command -v bats &>/dev/null; then
    BATS_VER=$(bats --version 2>/dev/null || echo "unknown")
    ok "bats found: $BATS_VER"
else
    skip "bats not found. Install bats via 'npm install -g bats bats-assert bats-support' to run tests."
fi

ok "self-improvement module — all dependencies satisfied"

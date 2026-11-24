#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# Info/ok/skip helpers
info() { printf "  [ \033[33mINFO\033[0m ] %s\n" "$*"; }
ok() { printf "  [  \033[32mOK\033[0m  ] %s\n" "$*"; }
skip() { printf "  [ \033[36mSKIP\033[0m ] %s\n" "$*"; }

info "security module — checking dependencies"

# Check shell availability (trivially true for bash scripts)
if command -v bash >/dev/null 2>&1; then
    ok "Shell found: bash"
else
    skip "bash not found — this should never happen on a POSIX system."
fi

# Optional: check bats availability for running tests
if command -v bats >/dev/null 2>&1; then
    BATS_VER=$(bats --version 2>/dev/null || echo "unknown")
    ok "bats found: $BATS_VER"
else
    skip "bats not found. Install bats via 'npm install -g bats bats-assert bats-support' to run tests."
fi

# FOSS tooling — one façade over four backends. `check` is local and fast, so it
# always runs; provisioning is opt-in because it reaches the network. A partial
# provision must not report the module as satisfied, so the closing line follows
# what actually happened rather than what the script attempted.
TOOLING="${MODULE_DIR}/scripts/tooling.sh"
TOOLS_OK=1
if [ -x "$TOOLING" ]; then
    info "security tooling:"
    "$TOOLING" check || {
        skip "tooling check reported a problem"
        TOOLS_OK=0
    }
    if [ "${SEC_TOOLS_AUTO_INSTALL:-0}" = "1" ]; then
        info "provisioning tooling (SEC_TOOLS_AUTO_INSTALL=1):"
        "$TOOLING" install || {
            skip "some tooling could not be provisioned — see the ledger above"
            TOOLS_OK=0
        }
    else
        skip "set SEC_TOOLS_AUTO_INSTALL=1, or run scripts/tooling.sh install, to provision"
    fi
    # The closing line follows the ledger, not the script's intent: with
    # provisioning left off, absent tools must not read as satisfied.
    MISSING="$("$TOOLING" check | awk 'NR > 1 && NF >= 3 && $3 == "absent" { n++ } END { print n + 0 }')"
    if [ "$MISSING" -gt 0 ]; then
        skip "$MISSING tool(s) absent — see the ledger above"
        TOOLS_OK=0
    fi
else
    skip "scripts/tooling.sh not executable — security tooling not checked"
    TOOLS_OK=0
fi

if [ "$TOOLS_OK" = "1" ]; then
    ok "security module — all dependencies satisfied"
else
    skip "security module — script dependencies are fine; tooling is not fully provisioned"
fi

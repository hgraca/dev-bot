#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/tests/fixtures/langs-edge/badlang/plugin.sh
# Test-only plugin whose plan/apply answers with something that is not JSON.
# Proves the core reports a malformed plugin response rather than crashing.
# =============================================================================

set -euo pipefail

case "${1:-}" in
  meta)
    cat <<'JSON'
{"lang":"badlang","extensions":[".bad"],"ops":["rename"],"map":{"rename":{"*":"rename-x"}}}
JSON
    ;;
  plan|apply)
    cat >/dev/null
    echo 'this is not json'
    ;;
  *)
    echo "ERROR: badlang plugin: unknown subcommand '${1:-}'" >&2
    exit 1
    ;;
esac

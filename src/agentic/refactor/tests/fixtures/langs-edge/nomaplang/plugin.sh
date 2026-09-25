#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/tests/fixtures/langs-edge/nomaplang/plugin.sh
# Test-only plugin that declares an op but no `map`, so the core cannot resolve
# a canonical op to a native one. Proves that path is refused, not guessed.
# =============================================================================

set -euo pipefail

case "${1:-}" in
  meta)
    cat <<'JSON'
{"lang":"nomaplang","extensions":[".nm"],"ops":["rename"]}
JSON
    ;;
  plan|apply)
    cat >/dev/null
    echo '{"ok":true,"engine":"nomaplang 1.0.0","applied":false,"summary":"unreachable"}'
    ;;
  *)
    echo "ERROR: nomaplang plugin: unknown subcommand '${1:-}'" >&2
    exit 1
    ;;
esac

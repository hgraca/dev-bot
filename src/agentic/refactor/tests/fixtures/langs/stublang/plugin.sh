#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/tests/fixtures/langs/stublang/plugin.sh
# Test-only language plugin. Proves the core's plugin seam is additive: pointing
# REFACTOR_LANGS_DIR at this fixture tree is enough to dispatch to a brand-new
# language with zero edits to the core.
#
# It performs no real refactoring — it echoes a canned response, recording the
# request it received so tests can assert the contract (op, class, from, to).
# =============================================================================

set -euo pipefail

request="$(cat)"

case "${1:-}" in
  meta)
    cat <<'JSON'
{"lang":"stublang","extensions":[".stub"],"ops":["rename"],"map":{"rename":{"method":"rename-method"}},"risks":{"rename-method":"rename"}}
JSON
    ;;
  plan|apply)
    applied="false"
    [[ "${1}" == "apply" ]] && applied="true"
    # Echo the request back so the test can assert the contract survives the hop.
    REFACTOR_STUB_APPLIED="${applied}" REFACTOR_STUB_REQUEST="${request}" python3 -c '
import json, os
req = json.loads(os.environ.get("REFACTOR_STUB_REQUEST") or "{}")
print(json.dumps({
    "ok": True,
    "engine": "stub 1.0.0",
    "applied": os.environ.get("REFACTOR_STUB_APPLIED") == "true",
    "summary": "stub %s: %s -> %s" % (req.get("op"), req.get("from"), req.get("to")),
    "files": ["fixture.stub"],
    "warnings": [],
    "echo": req,
}))'
    ;;
  *)
    echo "ERROR: stublang plugin: unknown subcommand '${1:-}'" >&2
    exit 1
    ;;
esac

#!/usr/bin/env bats
# =============================================================================
# src/agentic/graphify/tests/graphify-serve-shim_tests.bats
# Tests for graphify-serve-shim.py (the MCP stdio teardown EPIPE swallow).
#
# The shim wraps `python -m graphify.serve` so that the BrokenPipeError the
# mcp SDK's stdio_server raises when the client closes the pipe at session
# teardown exits cleanly (exit 0, no traceback) instead of crashing (audit-18
# NOTE). Tests are hermetic: a fake graphify.serve package on PYTHONPATH
# raises the exact exceptions the real one hits.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SHIM="$MODULE_DIR/tools/graphify-serve-shim.py"
  WRAPPER="$MODULE_DIR/tools/start-graphify-mcp.sh"

  FAKE_PKG="$(mktemp -d)"
  mkdir -p "${FAKE_PKG}/graphify"
  export PYTHONPATH="${FAKE_PKG}${PYTHONPATH:+:$PYTHONPATH}"
}

teardown() {
  rm -rf "${FAKE_PKG}"
}

# ── Shim behaviour ─────────────────────────────────────────────────────────────

@test "shim: exits 0 when serve.py raises bare BrokenPipeError" {
  cat > "${FAKE_PKG}/graphify/serve.py" <<'EOF'
raise BrokenPipeError(32, "Broken pipe — client closed stdio at teardown")
EOF

  run python3 "${SHIM}" /tmp/whatever-graph.json

  assert_success
}

@test "shim: exits 0 when serve.py raises ExceptionGroup-wrapped BrokenPipeError (py3.11+)" {
  if ! python3 -c 'raise ExceptionGroup("x", [BrokenPipeError()])' 2>/dev/null; then
    skip "Python < 3.11 (no ExceptionGroup)"
  fi

  cat > "${FAKE_PKG}/graphify/serve.py" <<'EOF'
raise ExceptionGroup("stdio server shutdown", [BrokenPipeError(32, "Broken pipe")])
EOF

  run python3 "${SHIM}" /tmp/whatever-graph.json

  assert_success
}

@test "shim: exits 0 when serve.py runs to completion normally" {
  cat > "${FAKE_PKG}/graphify/serve.py" <<'EOF'
print("graphify.serve running normally")
EOF

  run python3 "${SHIM}" /tmp/whatever-graph.json

  assert_success
}

@test "shim: forwards the graph.json argument to serve.py (argv passthrough)" {
  local argfile
  argfile="$(mktemp)"
  cat > "${FAKE_PKG}/graphify/serve.py" <<EOF
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text("received: " + sys.argv[1])
EOF

  run python3 "${SHIM}" "${argfile}"

  assert_success
  assert_equal "$(cat "${argfile}")" "received: ${argfile}"
  rm -f "${argfile}"
}

@test "shim: propagates genuine errors (non-BrokenPipe) with non-zero exit" {
  cat > "${FAKE_PKG}/graphify/serve.py" <<'EOF'
raise RuntimeError("genuine server failure")
EOF

  run python3 "${SHIM}" /tmp/whatever-graph.json

  assert_failure
  assert_output --partial "RuntimeError"
}

# ── Wrapper wiring ────────────────────────────────────────────────────────────

@test "wrapper: execs the shim (not -m graphify.serve) at all launch sites" {
  # The three fallback exec sites (secrets python / uv python / auto-detect)
  # must all route through the shim so every launch path swallows EPIPE.
  run grep -c 'exec "\${[A-Za-z_]*}" "\${GRAPHIFY_SHIM}" "\${GRAPH_FILE}"' "${WRAPPER}"
  assert_equal "$output" "3"

  # ...and the shim must exist on disk next to the wrapper.
  [[ -f "${SHIM}" ]]
}

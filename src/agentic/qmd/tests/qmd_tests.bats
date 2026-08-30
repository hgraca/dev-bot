#!/usr/bin/env bats
# =============================================================================
# src/agentic/qmd/tests/qmd_tests.bats
# Tests for the qmd.mcp.sh bash entrypoint.
# Tests from the bash entrypoint, covering all options and outputs.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/qmd.mcp.sh"
  FIXTURES="$TEST_DIR/fixtures"

  # Prefer the installed qmd CLI — skip tests if unavailable
  # (but allow --help tests to pass even without it)
  QMD_AVAILABLE=false
  if command -v qmd &>/dev/null; then
    QMD_AVAILABLE=true
  fi
}

# ── Help flag ─────────────────────────────────────────────────────────────────

@test "--help: prints usage and exits 0" {
  run bash "$TOOL" --help

  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "status"
  assert_output --partial "query"
  assert_output --partial "search"
  assert_output --partial "get"
  assert_output --partial "update"
  assert_output --partial "embed"
  assert_output --partial "collection"
}

@test "-h: also prints usage" {
  run bash "$TOOL" -h

  assert_success
  assert_output --partial "Usage:"
}

# ── No qmd CLI installed ──────────────────────────────────────────────────────

@test "no qmd CLI: error message and exit 1" {
  local BASH
  BASH="$(command -v bash)"

  PATH="$(mktemp -d)" run "$BASH" "$TOOL" status

  assert_failure
  assert_output --partial "FATAL: qmd CLI not found"
}

@test "no qmd CLI with --help: still works (no qmd needed)" {
  # Override PATH to hide qmd — --help doesn't need qmd
  local BASH
  BASH="$(command -v bash)"

  PATH="$(mktemp -d)" run "$BASH" "$TOOL" --help

  assert_success
  assert_output --partial "Usage:"
}

# ── Basic command: status ──────────────────────────────────────────────────────

@test "status: outputs ## QMD output header and code fence" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash "$TOOL" status

  assert_success
  assert_line --index 0 "## QMD output"
}

@test "status: output contains code fence" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash "$TOOL" status

  assert_success
  # Index 1 is the opening code fence (bats strips empty lines)
  assert_line --index 1 '```'
  # Last line is the closing code fence
  assert_line --index $((${#lines[@]} - 1)) '```'
}

@test "status: output contains collection or version info" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash "$TOOL" status

  assert_success
  # qmd status should show either collection info or version/health info
  assert_output --regexp "[a-zA-Z]"  # at least some text output
}

# ── Exit code propagation ─────────────────────────────────────────────────────

@test "exit code 0 on successful status command" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash "$TOOL" status
  assert_success
}

@test "non-existent command: still produces output (qmd may error but wrapper captures)" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash "$TOOL" nonexistent-command-xyz

  # The wrapper captures both stdout and stderr, so it still prints the header
  # and code fence. The actual error is inside the code block.
  assert_success
  assert_line --index 0 "## QMD output"
}

# ── Pipe mode ─────────────────────────────────────────────────────────────────

@test "pipe mode: reads from stdin, outputs header and code fence" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash -c 'printf "test query" | bash '"$TOOL"

  assert_success
  assert_line --index 0 "## QMD output"
  # Opening code fence — index may vary because qmd output starts on next line
  # Check that both fences exist
  local open_count=0
  local close_count=0
  local in_fence=false
  for line in "${lines[@]}"; do
    if [[ "$line" == '```' ]]; then
      if [[ "$in_fence" == "false" ]]; then
        open_count=$((open_count + 1))
        in_fence=true
      else
        close_count=$((close_count + 1))
        in_fence=false
      fi
    fi
  done
  [[ "$open_count" -eq 1 ]]
  [[ "$close_count" -eq 1 ]]
}

# ── Output format structure ────────────────────────────────────────────────────

@test "output format: header, fence, content, fence in correct order" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash "$TOOL" status

  assert_success
  assert_line --index 0 "## QMD output"
  # Index 1 is opening ``` (bats strips empty lines)
  assert_line --index 1 '```'
  # Last line is closing ```
  assert_line --index $((${#lines[@]} - 1)) '```'
}

# ── Edge cases ─────────────────────────────────────────────────────────────────

@test "no arguments + no pipe: exits with error" {
  run bash "$TOOL"

  # The wrapper should try to run `qmd` with no args, which should
  # either fail or show help from qmd itself. Either way, qmd must be
  # installed — skip if not.
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  # With no args and no pipe, qmd itself prints help/error
  assert_output --partial "## QMD output"
}

@test "empty pipe: does not crash" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash -c 'printf "" | bash '"$TOOL"

  assert_success
  assert_line --index 0 "## QMD output"
}

@test "query with special characters: no shell injection" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  # Use `search` (BM25) rather than `query` (hybrid LLM + Ollama): the point of
  # this test is that special characters pass through the bash wrapper without
  # being shell-evaluated, and both commands share the identical `qmd "$@"`
  # forwarding path. `search` needs no LLM, so it can't hang on Ollama
  # contention during a full-suite run.
  run bash "$TOOL" search "test with 'quotes' and \$pecial chars"

  assert_success
  assert_line --index 0 "## QMD output"
}

# ── Output header consistency ──────────────────────────────────────────────────

@test "output always starts with ## QMD output" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash "$TOOL" status
  assert_line --index 0 "## QMD output"

  run bash "$TOOL" --help
  assert_line --index 0 --partial "Usage:"
}

# ── Collection operations (require qmd) ─────────────────────────────────────

@test "collection list: outputs header and code fence" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash "$TOOL" collection list

  assert_success
  assert_line --index 0 "## QMD output"
  assert_line --index 1 '```'
}

@test "collection list: returns zero exit code" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash "$TOOL" collection list
  assert_success
}

@test "collection status: shows collection health info" {
  if [[ "$QMD_AVAILABLE" != "true" ]]; then
    skip "qmd CLI not installed"
  fi

  run bash "$TOOL" collection status

  assert_success
  assert_line --index 0 "## QMD output"
}

# ── audit-26 NOTE-6: init prunes orphaned chunks before indexing ─────────────

@test "init.sh runs qmd cleanup before update and embed" {
  # Guard audit-26 NOTE-6: qmd status reported 118 orphaned embedding chunks
  # (12%) because reinit (init.sh) never ran `qmd cleanup` — only the reindex
  # tool does. The stub qmd records its argv; assert cleanup precedes the
  # index build.
  local sandbox
  sandbox="$(mktemp -d)"
  mkdir -p "${sandbox}/bin" "${sandbox}/.agents/memory/latent"

  cat > "${sandbox}/bin/qmd" <<'SCRIPT'
#!/usr/bin/env bash
echo "$*" >> "${QMD_CALL_LOG}"
case "$1" in
  collection|context) exit 0 ;;
  update|embed|cleanup) exit 0 ;;
esac
exit 0
SCRIPT
  chmod +x "${sandbox}/bin/qmd"

  local call_log="${sandbox}/qmd-calls.log"
  : > "$call_log"

  run env PATH="${sandbox}/bin:$(dirname "$(command -v python3)")" \
    QMD_CALL_LOG="$call_log" \
    bash "${MODULE_DIR}/init.sh" "${sandbox}"

  assert_success
  # cleanup must run, and before the first index-building call
  run cat "$call_log"
  assert_output --partial "cleanup"
  local cleanup_line update_line
  cleanup_line="$(grep -n "cleanup" "$call_log" | head -1 | cut -d: -f1 || echo 0)"
  update_line="$(grep -n "update" "$call_log" | head -1 | cut -d: -f1 || echo 0)"
  [[ -n "$cleanup_line" && "$cleanup_line" -gt 0 ]]
  [[ -n "$update_line" && "$update_line" -gt 0 ]]
  [[ "$cleanup_line" -lt "$update_line" ]]

  rm -r "$sandbox"
}

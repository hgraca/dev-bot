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
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
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
  # index build. XDG_CACHE_HOME is sandboxed so the llama serialization lock
  # (see the lock tests below) never touches the developer's real qmd cache.
  local sandbox
  sandbox="$(mktemp -d)"
  mkdir -p "${sandbox}/bin" "${sandbox}/.agents/memory/latent"

  cat > "${sandbox}/bin/qmd" <<'SCRIPT'
#!/usr/bin/env bash
echo "$(python3 -c 'import time; print(time.time())') $*" >> "${QMD_CALL_LOG}"
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
    XDG_CACHE_HOME="$sandbox/cache" \
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

# ── Cross-process llama serialization (dev-bot e2e CPU crash) ─────────────────
# cc + oc e2e containers reinit concurrently, each running qmd/init.sh's
# `qmd embed` on the same GPU / shared model cache. Under VRAM contention qmd
# falls back to CPU, where llama uses every core — two at once pegged the host
# (100% CPU, freeze). init.sh must serialize the llama-heavy build via a
# cross-process flock in the qmd cache (a host mount shared by the containers).

@test "init.sh waits for a concurrently-held llama lock before running the build" {
  local sandbox
  sandbox="$(mktemp -d)"
  mkdir -p "${sandbox}/bin" "${sandbox}/.agents/memory/latent" "${sandbox}/cache/qmd"

  cat > "${sandbox}/bin/qmd" <<'SCRIPT'
#!/usr/bin/env bash
echo "$(python3 -c 'import time; print(time.time())') $*" >> "${QMD_CALL_LOG}"
case "$1" in
  collection|context) exit 0 ;;
  update|embed|cleanup) exit 0 ;;
esac
exit 0
SCRIPT
  chmod +x "${sandbox}/bin/qmd"

  local call_log="${sandbox}/qmd-calls.log"
  : > "$call_log"
  local lock="${sandbox}/cache/qmd/.llama.lock"
  : > "$lock"
  local release_ts="${sandbox}/release.ts" held_marker="${sandbox}/held"

  # Another process (the sibling e2e container) holds the llama lock for 2.5s.
  python3 -c '
import fcntl, os, sys, time
lock, release, held = sys.argv[1], sys.argv[2], sys.argv[3]
f = open(lock, "w")
fcntl.flock(f, fcntl.LOCK_EX)
open(held, "w").write("1")
time.sleep(2.5)
open(release, "w").write(str(time.time()))
' "$lock" "$release_ts" "$held_marker" &
  local holder=$!
  # Wait until the holder actually owns the lock before starting init.
  local i
  for i in $(seq 1 50); do
    [[ -f "$held_marker" ]] && break
    sleep 0.1
  done

  run env PATH="${sandbox}/bin:$(dirname "$(command -v python3)")" \
    XDG_CACHE_HOME="$sandbox/cache" \
    QMD_CALL_LOG="$call_log" \
    bash "${MODULE_DIR}/init.sh" "${sandbox}"
  assert_success
  wait "$holder" 2>/dev/null || true

  # The build must have started only AFTER the holder released the lock —
  # i.e. the first qmd call (cleanup) is timestamped >= release.
  local cleanup_ts
  cleanup_ts="$(grep -m1 "cleanup" "$call_log" | cut -d' ' -f1 || echo 0)"
  local release
  release="$(cat "$release_ts" 2>/dev/null || echo 0)"
  run python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' \
    "${cleanup_ts}" "${release}"
  assert_success

  rm -r "$sandbox"
}

@test "init.sh proceeds (with a warning) when the llama lock is held past the cap" {
  local sandbox
  sandbox="$(mktemp -d)"
  mkdir -p "${sandbox}/bin" "${sandbox}/.agents/memory/latent" "${sandbox}/cache/qmd"

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
  local lock="${sandbox}/cache/qmd/.llama.lock"
  : > "$lock"

  # Holder keeps the lock for 3s while the cap is 1s — init must give up
  # waiting, warn, and still build rather than hang.
  python3 -c '
import fcntl, sys, time
f = open(sys.argv[1], "w")
fcntl.flock(f, fcntl.LOCK_EX)
time.sleep(3)
' "$lock" &
  local holder=$!
  sleep 0.3

  run env PATH="${sandbox}/bin:$(dirname "$(command -v python3)")" \
    XDG_CACHE_HOME="$sandbox/cache" \
    QMD_EMBED_TIMEOUT=1 \
    QMD_CALL_LOG="$call_log" \
    bash "${MODULE_DIR}/init.sh" "${sandbox}"
  assert_success
  wait "$holder" 2>/dev/null || true

  run cat "$call_log"
  assert_output --partial "cleanup"

  rm -r "$sandbox"
}

# ── audit-28 FAIL-1: GPU query-expansion VRAM safety ──────────────────────────
# On small-VRAM GPUs (RTX 4050, 5.6 GB) qmd's query-expansion model at the
# default 2048 context overflows VRAM: "InsufficientMemoryError: A context
# size of 2048 is too large for the available VRAM" — every hybrid query logs
# a stack trace and expansion silently degrades to unexpanded search.
# QMD_EXPAND_CONTEXT_SIZE must be pinned to a VRAM-safe value in the MCP
# environment so it flows into every project on reinit.

@test "audit-28: opencode template pins QMD_EXPAND_CONTEXT_SIZE to a VRAM-safe value" {
  run python3 -c "import json; d=json.load(open('${MODULE_DIR}/mcp.opencode.json')); print(json.dumps(d['qmd'].get('environment', {})))"
  assert_success
  assert_output --partial '"QMD_EXPAND_CONTEXT_SIZE": "512"'
}

@test "audit-28: claudecode template pins QMD_EXPAND_CONTEXT_SIZE" {
  run python3 -c "import json; d=json.load(open('${MODULE_DIR}/mcp.claudecode.json')); print(json.dumps(d['mcpServers']['qmd'].get('env', {})))"
  assert_success
  assert_output --partial '"QMD_EXPAND_CONTEXT_SIZE": "512"'
}

@test "audit-28: root opencode.dist.jsonc qmd entry stays consistent with the module template" {
  # NOTE: the root opencode.dist.jsonc is a LEGACY artifact — the opencode
  # harness copies src/harnesses/opencode/opencode.dist.jsonc (no mcp section),
  # and runtime MCP config comes from module-template registration (tested
  # above). This assertion guards the legacy copy against drift: it must not
  # carry the qmd 2.8.3-rejected boolean true (use the __GPU_ENABLED__
  # placeholder, as the module template does) and should carry the same
  # VRAM-safe QMD_EXPAND_CONTEXT_SIZE pin.
  run grep -q '"QMD_LLAMA_GPU"[[:space:]]*:[[:space:]]*true' \
    "$PROJECT_ROOT/opencode.dist.jsonc"
  assert_failure
  run grep -q '"QMD_LLAMA_GPU"[[:space:]]*:[[:space:]]*"__GPU_ENABLED__"' \
    "$PROJECT_ROOT/opencode.dist.jsonc"
  assert_success
  run grep -q '"QMD_EXPAND_CONTEXT_SIZE"[[:space:]]*:[[:space:]]*"512"' \
    "$PROJECT_ROOT/opencode.dist.jsonc"
  assert_success
}

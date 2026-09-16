#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/tui_config_tests.bats
# Guards the TUI config surface. opencode loads TWO separate plugin surfaces:
#   - opencode.jsonc `plugin`     -> SERVER plugins
#   - .opencode/tui.json `plugin` -> TUI plugins
# A TUI plugin listed in opencode.jsonc is schema-invalid (the opencode.json
# schema declares no "tui" key and sets additionalProperties:false), so the two
# must come from different templates and never drift into each other.
#
# Also covers _write_jsonc_from_dist, the shared generator behind both the
# opencode.jsonc and tui.json wrappers.
#
# Sandbox pattern: strip init.sh at the `# ── main` marker so sourcing it only
# defines functions, then stub the progress helpers (see delegate_tests.bats).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
  HARNESS_DIR="${PROJECT_ROOT}/src/harnesses/opencode"
  DIST_TUI="${HARNESS_DIR}/tui.dist.jsonc"
  READER="${PROJECT_ROOT}/src/_shared/read_jsonc.py"

  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

_setup_sandbox() {
  sed '/^# ── main/,$d' "${HARNESS_DIR}/init.sh" > "${SANDBOX_DIR}/init.sh"

  cat > "${SANDBOX_DIR}/functions.sh" <<'FUNCTIONS_EOF'
_info()  { echo "INFO: $*"; }
_ok()    { echo "OK: $*"; }
_skip()  { echo "SKIP: $*"; }
_warn()  { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; exit 1; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
FUNCTIONS_EOF

  mkdir -p "${SANDBOX_DIR}/src/_shared"
  cat > "${SANDBOX_DIR}/src/_shared/functions.sh" <<'SHARED_EOF'
_info()  { echo "INFO: $*"; }
_ok()    { echo "OK: $*"; }
_skip()  { echo "SKIP: $*"; }
_warn()  { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; exit 1; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
# init.sh's opencode.jsonc wrapper resolves the qmd GPU value at write time.
_qmd_gpu_value() { echo "false"; }
SHARED_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode"
  cp "${DIST_TUI}" "${SANDBOX_DIR}/tui.dist.jsonc"
  cp "${HARNESS_DIR}/opencode.dist.jsonc" "${SANDBOX_DIR}/opencode.dist.jsonc"
}

# Source the stripped init.sh with PROJECT_DIR pinned to the sandbox, so
# MODULE_DIR/DIST_CONFIG/OPENCODE_DIR all resolve inside it.
_source_init() {
  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  set -- "${SANDBOX_DIR}"
  source "${SANDBOX_DIR}/init.sh"
}

# ── the template itself ──────────────────────────────────────────────────────

@test "tui.dist.jsonc parses as valid JSONC" {
  run python3 "$READER" "$DIST_TUI"
  assert_success
}

@test "tui.dist.jsonc plugin array carries the TUI plugins" {
  run python3 "$READER" "$DIST_TUI" plugin
  assert_success
  assert_output --partial '"opencode-tabs"'
  assert_output --partial '"opencode-dir-tree-tui"'
}

@test "tui.dist.jsonc disables the duplicate built-in sidebar blocks" {
  # The footer already reports context usage and opencode-dir-tree-tui renders
  # the file tree, so the built-in sidebar equivalents are switched off via
  # plugin_enabled — opencode's slot-level switch for its own TUI blocks.
  run python3 "$READER" "$DIST_TUI" plugin_enabled
  assert_success
  assert_output --partial '"internal:sidebar-context": false'
  assert_output --partial '"internal:sidebar-files": false'
}

@test "tui.dist.jsonc plugin array excludes server plugins" {
  # Mirror of dist_config_tests.bats: server plugins belong in
  # opencode.dist.jsonc, never here.
  run python3 "$READER" "$DIST_TUI" plugin
  assert_success
  refute_output --partial 'opencode-pty'
  refute_output --partial 'plannotator'
  refute_output --partial 'on-hooks'
}

# ── _write_tui_config ────────────────────────────────────────────────────────

@test "_write_tui_config writes .opencode/tui.json with comments stripped" {
  _setup_sandbox
  _source_init

  run _write_tui_config
  assert_success

  local tui="${SANDBOX_DIR}/.opencode/tui.json"
  [[ -f "$tui" ]] || fail ".opencode/tui.json was not written"
  # The template's explanatory comments must not survive into the runtime file.
  # Strict json.load is the precise check here: it rejects // and /* */ comments
  # while accepting the https:// inside $schema — which the string-aware
  # stripper deliberately preserves, so a plain grep for '//' would false-positive.
  if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tui" 2>/dev/null; then
    fail "generated tui.json is not strict JSON — comments survived"
  fi
  run python3 "$READER" "$tui" plugin
  assert_success
  assert_output --partial '"opencode-tabs"'
  assert_output --partial '"opencode-dir-tree-tui"'
  # the built-in-slot switches must survive generation too
  run python3 "$READER" "$tui" plugin_enabled
  assert_success
  assert_output --partial '"internal:sidebar-context": false'
}

@test "_write_tui_config leaves an existing .opencode/tui.json untouched" {
  _setup_sandbox
  _source_init
  printf '{\n  "plugin": ["user-owned"]\n}\n' > "${SANDBOX_DIR}/.opencode/tui.json"

  run _write_tui_config
  assert_success
  assert_output --partial "already exists"

  run cat "${SANDBOX_DIR}/.opencode/tui.json"
  assert_output --partial 'user-owned'
  refute_output --partial 'opencode-tabs'
}

# ── _write_jsonc_from_dist, the shared generator ─────────────────────────────

@test "_write_jsonc_from_dist fails loudly when the template is missing" {
  _setup_sandbox
  _source_init

  run _write_jsonc_from_dist "${SANDBOX_DIR}/absent.jsonc" "${SANDBOX_DIR}/out.jsonc"
  assert_failure
  assert_output --partial "Template not found"
  [[ ! -f "${SANDBOX_DIR}/out.jsonc" ]] || fail "wrote a config from a missing template"
}

@test "_write_opencode_config still generates a valid server-only opencode.jsonc" {
  # Regression net for the shared-generator extraction: opencode.jsonc's
  # generated output and behaviour must be unchanged.
  _setup_sandbox
  _source_init

  run _write_opencode_config
  assert_success

  local cfg="${SANDBOX_DIR}/opencode.jsonc"
  [[ -f "$cfg" ]] || fail "opencode.jsonc was not written"
  run python3 "$READER" "$cfg" plugin
  assert_success
  assert_output --partial 'opencode-pty'
  # and it must never carry TUI plugins — that is the split this file guards
  refute_output --partial 'opencode-tabs'
}

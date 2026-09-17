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
  # _link_tui_plugins farms its source out of DEV_BOT_ROOT (= the sandbox), so the
  # module has to exist there.
  mkdir -p "${SANDBOX_DIR}/src/harnesses/opencode/pty-monitor"
  : > "${SANDBOX_DIR}/src/harnesses/opencode/pty-monitor/index.ts"

  # _ensure_dist_plugins calls the REAL _upsert_opencode_plugin and reads the
  # template with the real read_jsonc.py. Copy both in rather than stubbing them,
  # so these tests exercise the code that actually runs.
  awk '/^_upsert_opencode_plugin\(\)/,/^}/' \
    "${PROJECT_ROOT}/src/_shared/functions.sh" >> "${SANDBOX_DIR}/src/_shared/functions.sh"
  cp "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX_DIR}/src/_shared/read_jsonc.py"
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

@test "tui.dist.jsonc carries the pinned third-party TUI plugins" {
  # Pinned for the same reason opencode-pty is: these are version-sensitive, and
  # an unpinned spec silently follows upstream latest. The assertion matches the
  # pinned form, so it covers both presence and pinning — an unpinned regression
  # fails it.
  run python3 "$READER" "$DIST_TUI" plugin
  assert_success
  assert_output --partial '"opencode-tabs@'
}

@test "tui.dist.jsonc leaves the built-in file tree enabled" {
  # internal:sidebar-files is the ONLY file tree now that opencode-dir-tree-tui
  # has been removed — disabling it (as was once correct, when that plugin drew
  # one) would leave the sidebar with no file tree at all.
  run python3 "$READER" "$DIST_TUI" plugin_enabled
  assert_success
  assert_output --partial '"internal:sidebar-context": false'
  refute_output --partial '"internal:sidebar-files"'
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
  assert_output --partial 'opencode-tabs@'
  assert_output --partial 'tui-plugins/pty-monitor'
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

# ── the dev-bot TUI plugin farm (init.sh / reset.sh / the dist entry) ─────────

@test "tui.dist.jsonc references the PTY monitor by a RELATIVE path" {
  # A shipped template must not bake in an install path: an absolute path (or a
  # file:// URL) would break on every consumer machine.
  run python3 "$READER" "$DIST_TUI" plugin
  assert_success
  assert_output --partial '"./tui-plugins/pty-monitor/index.ts"'
  refute_output --partial 'file://'
  refute_output --partial '/home/'
}

@test "_link_tui_plugins symlinks the module into .opencode/tui-plugins" {
  _setup_sandbox
  _source_init

  run _link_tui_plugins
  assert_success

  local link="${SANDBOX_DIR}/.opencode/tui-plugins/pty-monitor"
  [[ -L "$link" ]] || fail "symlink not created at ${link}"
  assert_equal "$(readlink "$link")" "${SANDBOX_DIR}/src/harnesses/opencode/pty-monitor"
}

@test "_link_tui_plugins is idempotent" {
  _setup_sandbox
  _source_init

  run _link_tui_plugins
  assert_success
  run _link_tui_plugins
  assert_success
  assert_output --partial "already linked"
}

@test "_link_tui_plugins relinks when the target differs" {
  _setup_sandbox
  _source_init
  mkdir -p "${SANDBOX_DIR}/.opencode/tui-plugins"
  ln -sfn /somewhere/else "${SANDBOX_DIR}/.opencode/tui-plugins/pty-monitor"

  run _link_tui_plugins
  assert_success
  assert_output --partial "relinked"
  assert_equal "$(readlink "${SANDBOX_DIR}/.opencode/tui-plugins/pty-monitor")" \
    "${SANDBOX_DIR}/src/harnesses/opencode/pty-monitor"
}

@test "_link_tui_plugins leaves a real directory alone rather than replacing it" {
  _setup_sandbox
  _source_init
  mkdir -p "${SANDBOX_DIR}/.opencode/tui-plugins/pty-monitor"
  : > "${SANDBOX_DIR}/.opencode/tui-plugins/pty-monitor/user-file.ts"

  run _link_tui_plugins
  assert_success
  assert_output --partial "not a symlink"

  local link="${SANDBOX_DIR}/.opencode/tui-plugins/pty-monitor"
  assert [ ! -L "$link" ]
  assert [ -f "${link}/user-file.ts" ]
}

@test "init.sh main wires the tui-plugins farm" {
  run grep -q '^_link_tui_plugins$' "${HARNESS_DIR}/init.sh"
  assert_success
}

@test "reset.sh's subdir loop actually covers tui-plugins" {
  # Deliberately asserts the LOOP LINE, not the file. The first version grepped
  # the whole file, which matched the explanatory comment above the loop — so
  # dropping tui-plugins from the loop left the test green.
  run grep -E '^for subdir in ' "${HARNESS_DIR}/reset.sh"
  assert_success
  assert_output --partial 'tui-plugins'
}

@test "_link_tui_plugins warns loudly when the source is missing" {
  # The dist lists the module unconditionally, so a missing source means a
  # tui.json entry pointing at nothing — that must be visible, not a shrug.
  _setup_sandbox
  _source_init
  rm -rf "${SANDBOX_DIR}/src/harnesses/opencode/pty-monitor"

  run _link_tui_plugins
  assert_success
  assert_output --partial "source missing"
  assert_output --partial "does not exist"
}

# ── _ensure_dist_plugins: reconcile dist entries into an existing config ──────
# Regression guard for the shipped-dependency gap: _write_*_config are seed-once,
# so opencode-pty (required by the PTY monitor) never reached any project seeded
# before it was added to the dist. The panel was wired while its dependency was
# not, and the only symptom was "server unavailable".

@test "_ensure_dist_plugins adds a missing npm-spec entry to an existing config" {
  _setup_sandbox
  _source_init
  # A project seeded before opencode-pty existed.
  printf '{\n  "plugin": [".opencode/plugins/on-hooks.ts"]\n}\n' > "${SANDBOX_DIR}/opencode.jsonc"

  run _ensure_dist_plugins "${SANDBOX_DIR}/opencode.dist.jsonc" "${SANDBOX_DIR}/opencode.jsonc"
  assert_success
  assert_output --partial "added 'opencode-pty@"

  run python3 "$READER" "${SANDBOX_DIR}/opencode.jsonc" plugin
  assert_success
  assert_output --partial '"opencode-pty@0.3.6"'
}

@test "_ensure_dist_plugins is idempotent" {
  _setup_sandbox
  _source_init
  printf '{\n  "plugin": [".opencode/plugins/on-hooks.ts"]\n}\n' > "${SANDBOX_DIR}/opencode.jsonc"

  run _ensure_dist_plugins "${SANDBOX_DIR}/opencode.dist.jsonc" "${SANDBOX_DIR}/opencode.jsonc"
  assert_success
  run _ensure_dist_plugins "${SANDBOX_DIR}/opencode.dist.jsonc" "${SANDBOX_DIR}/opencode.jsonc"
  assert_success
  # second pass reports nothing — the entry is already there
  refute_output --partial "added"

  run python3 -c "
import json, sys
raw = open(sys.argv[1]).read()
print(raw.count('opencode-pty'))
" "${SANDBOX_DIR}/opencode.jsonc"
  assert_output "1"
}

@test "_ensure_dist_plugins skips local paths (owned by the symlink farms)" {
  _setup_sandbox
  _source_init
  printf '{\n  "plugin": []\n}\n' > "${SANDBOX_DIR}/opencode.jsonc"

  run _ensure_dist_plugins "${SANDBOX_DIR}/opencode.dist.jsonc" "${SANDBOX_DIR}/opencode.jsonc"
  assert_success
  refute_output --partial "on-hooks"
}

@test "_ensure_dist_plugins does nothing without a config to reconcile" {
  _setup_sandbox
  _source_init
  run _ensure_dist_plugins "${SANDBOX_DIR}/opencode.dist.jsonc" "${SANDBOX_DIR}/does-not-exist.jsonc"
  assert_success
  [[ ! -f "${SANDBOX_DIR}/does-not-exist.jsonc" ]] || fail "created a config it should not have"
}

@test "init.sh main reconciles both dist surfaces" {
  run grep -c '^_ensure_dist_plugins ' "${HARNESS_DIR}/init.sh"
  assert_success
  assert_output "2"
}

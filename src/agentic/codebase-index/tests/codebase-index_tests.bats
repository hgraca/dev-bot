#!/usr/bin/env bats
# =============================================================================
# src/agentic/codebase-index/tests/codebase-index_tests.bats
# Tests for the codebase-index module (MCP-based, no local tool).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  FIXTURES="$TEST_DIR/fixtures"
}

# ── Module structure ──────────────────────────────────────────────────────────

@test "opencode integration is the plugin (not a redundant MCP entry)" {
  # For opencode the package is integrated as a plugin, which itself spawns the
  # MCP server — registering it as an MCP too would double-load it. The
  # canonical mcp.json therefore serves claudecode only; the opencode
  # registration adapter skips this server (plugin-precedence rule).
  local plugin_config="$MODULE_DIR/plugin.opencode.json"
  [ -f "$plugin_config" ]
  run grep -q 'opencode-codebase-index' "$plugin_config"
  assert_success
  [ -f "$MODULE_DIR/mcp.json" ]
  [ ! -f "$MODULE_DIR/mcp.opencode.json" ]
  [ ! -f "$MODULE_DIR/mcp.claudecode.json" ]
}

@test "canonical mcp.json declares codebase-index with harness tokens" {
  # {harness-dir} resolves the EPIPE wrapper path (.opencode/.claude); {host}
  # resolves the server's config-location arg (opencode/claude).
  local mcp_config="$MODULE_DIR/mcp.json"
  [ -f "$mcp_config" ]
  run grep -q 'codebase-index-mcp' "$mcp_config"
  assert_success
  run grep -c '{harness-dir}/codebase-index-mcp-wrapper.js' "$mcp_config"
  assert_equal "$output" "1"
  run grep -c -- '--host {host}' "$mcp_config"
  assert_equal "$output" "1"
  run grep -c '"enabled"' "$mcp_config"
  assert_equal "$output" "0"
}

@test "claudecode translation routes through the EPIPE wrapper with --host claude" {
  # Translate the canonical manifest and assert the claudecode launch shape.
  PROJECT_ROOT="$(cd "$MODULE_DIR/../../.." && pwd)"
  run python3 "$PROJECT_ROOT/src/_shared/mcp_translate.py" "$MODULE_DIR/mcp.json" claudecode
  assert_success
  assert_output --partial 'node .claude/codebase-index-mcp-wrapper.js npx'
  assert_output --regexp -- '--host claude[" ]'
  refute_output --partial 'claudecode'
}

@test "init.sh: symlinks the shared EPIPE wrapper into .claude" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  printf '{\n  "modules": { "claudecode": true, "opencode": false }\n}\n' \
    > "${tmpdir}/.devbot.project.jsonc"

  run bash "$MODULE_DIR/init.sh" "${tmpdir}"

  assert_success
  [[ -L "${tmpdir}/.claude/codebase-index-mcp-wrapper.js" ]]
  local shared_wrapper
  shared_wrapper="$(cd "$MODULE_DIR/../../.." && pwd)/src/_shared/mcp-stdio-wrapper.js"
  # `readlink` (single level) — `readlink -f` is GNU-only and absent on macOS.
  run readlink "${tmpdir}/.claude/codebase-index-mcp-wrapper.js"
  assert_output "${shared_wrapper}"

  rm -rf "${tmpdir}"
}

# ── Stale-index migration on init ─────────────────────────────────────────────

# Fake `npx` on PATH that records its argv and succeeds — lets the tests assert
# a background reindex was launched without hitting the network.
_install_fake_npx() {
  local bin_dir="$1"
  cat > "${bin_dir}/npx" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NPX_CALL_LOG}"
exit 0
STUB
  chmod +x "${bin_dir}/npx"
}

# Fake package dir carrying the schema-version constants the module greps for.
_install_fake_pkg() {
  local pkg_dir="$1"
  mkdir -p "${pkg_dir}/dist"
  cat > "${pkg_dir}/dist/cli.js" <<'JS'
var CALL_GRAPH_RESOLUTION_VERSION = "9";
var SWIFT_PARSER_VERSION = "2";
var METAL_PARSER_VERSION = "1";
var SYMBOL_EXTRACTOR_VERSION = "1";
JS
}

# Create an index DB whose per-catalog schema metadata is set from the args.
# Usage: _install_index_db <db> <catalog> <callgraph> <swift> <metal> <symbol>
_install_index_db() {
  python3 - "$@" <<'PY'
import sqlite3, sys
db, catalog, callgraph, swift, metal, symbol = sys.argv[1:7]
con = sqlite3.connect(db)
con.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)")
rows = {
    f"index.callGraphResolutionVersion.{catalog}": callgraph,
    f"index.parser.swiftVersion.{catalog}": swift,
    f"index.parser.metalVersion.{catalog}": metal,
    f"index.symbolExtractorVersion.{catalog}": symbol,
}
con.executemany("INSERT INTO metadata (key, value) VALUES (?, ?)", rows.items())
con.commit()
con.close()
PY
}

# Poll briefly for a file a detached process creates (no `seq` — BSD-safe).
_wait_for_file() {
  local f="$1" i=0
  while [[ "${i}" -lt 25 ]]; do
    [[ -f "${f}" ]] && return 0
    sleep 0.2
    i=$((i + 1))
  done
  return 1
}

_setup_index_project() {
  local tmpdir="$1" bin_dir="$2" catalog="$3" callgraph="$4" swift="$5" metal="$6" symbol="$7"
  printf '{\n  "modules": { "opencode": true, "claudecode": false }\n}\n' \
    > "${tmpdir}/.devbot.project.jsonc"
  mkdir -p "${tmpdir}/.opencode/index"
  : > "${tmpdir}/.opencode/index/file-hashes.${catalog}.json"
  _install_index_db "${tmpdir}/.opencode/index/codebase.db" \
    "${catalog}" "${callgraph}" "${swift}" "${metal}" "${symbol}"
  _install_fake_pkg "${tmpdir}/pkg"
  _install_fake_npx "${bin_dir}"
  export DEV_BOT_CODEBASE_INDEX_PKG_DIR="${tmpdir}/pkg"
  export NPX_CALL_LOG="${tmpdir}/npx.log"
  export PATH="${bin_dir}:${PATH}"
}

@test "init.sh reports an up-to-date index without reindexing" {
  local tmpdir bin_dir
  tmpdir="$(mktemp -d)"
  bin_dir="$(mktemp -d)"
  _setup_index_project "${tmpdir}" "${bin_dir}" "d7473cb74ee8d342" "9" "2" "1" "1"

  run bash "$MODULE_DIR/init.sh" "${tmpdir}"

  assert_success
  assert_output --partial "codebase index up to date"
  [ ! -f "${NPX_CALL_LOG}" ]

  rm -rf "${tmpdir}" "${bin_dir}"
}

@test "init.sh reindexes a stale index in the background" {
  local tmpdir bin_dir
  tmpdir="$(mktemp -d)"
  bin_dir="$(mktemp -d)"
  _setup_index_project "${tmpdir}" "${bin_dir}" "d7473cb74ee8d342" "4" "1" "1" "1"

  run bash "$MODULE_DIR/init.sh" "${tmpdir}"

  assert_success
  assert_output --partial "codebase index is out of date"
  assert_output --partial "reindexing in the background as of"
  _wait_for_file "${NPX_CALL_LOG}" || fail "detached reindex did not start within 5s"
  run cat "${NPX_CALL_LOG}"
  assert_output --partial "cbi index --project ${tmpdir} --host opencode"

  rm -rf "${tmpdir}" "${bin_dir}"
}

@test "init.sh detects a symbol-extractor version mismatch as stale" {
  local tmpdir bin_dir
  tmpdir="$(mktemp -d)"
  bin_dir="$(mktemp -d)"
  # callgraph and swift match the package; symbolExtractorVersion does not.
  _setup_index_project "${tmpdir}" "${bin_dir}" "d7473cb74ee8d342" "9" "2" "1" "0"

  run bash "$MODULE_DIR/init.sh" "${tmpdir}"

  assert_success
  assert_output --partial "codebase index is out of date"
  _wait_for_file "${NPX_CALL_LOG}" || fail "detached reindex did not start within 5s"

  rm -rf "${tmpdir}" "${bin_dir}"
}

@test "init.sh falls back to a background reindex when the state is unknown" {
  local tmpdir bin_dir
  tmpdir="$(mktemp -d)"
  bin_dir="$(mktemp -d)"
  # Index dir present but no file-hashes catalog file → state unknown.
  printf '{\n  "modules": { "opencode": true, "claudecode": false }\n}\n' \
    > "${tmpdir}/.devbot.project.jsonc"
  mkdir -p "${tmpdir}/.opencode/index"
  : > "${tmpdir}/.opencode/index/codebase.db"
  _install_fake_npx "${bin_dir}"
  export DEV_BOT_CODEBASE_INDEX_PKG_DIR="${tmpdir}/pkg"
  export NPX_CALL_LOG="${tmpdir}/npx.log"
  export PATH="${bin_dir}:${PATH}"

  run bash "$MODULE_DIR/init.sh" "${tmpdir}"

  assert_success
  assert_output --partial "codebase index status unknown"
  assert_output --partial "reindexing in the background as of"
  _wait_for_file "${NPX_CALL_LOG}" || fail "detached reindex did not start within 5s"

  rm -rf "${tmpdir}" "${bin_dir}"
}

@test "init.sh skips the indexer when no index exists" {
  local tmpdir bin_dir
  tmpdir="$(mktemp -d)"
  bin_dir="$(mktemp -d)"
  printf '{\n  "modules": { "opencode": true, "claudecode": false }\n}\n' \
    > "${tmpdir}/.devbot.project.jsonc"
  _install_fake_npx "${bin_dir}"

  export NPX_CALL_LOG="${tmpdir}/npx.log"
  export PATH="${bin_dir}:${PATH}"
  run bash "$MODULE_DIR/init.sh" "${tmpdir}"

  assert_success
  [ ! -f "${NPX_CALL_LOG}" ]

  rm -rf "${tmpdir}" "${bin_dir}"
}

@test "install script exists" {
  [ -f "$MODULE_DIR/install.sh" ]
}

@test "init script exists" {
  [ -f "$MODULE_DIR/init.sh" ]
}

@test "skill file exists" {
  [ -f "$MODULE_DIR/skills/SKILL.md" ]
}

@test "skill file has frontmatter" {
  run head -1 "$MODULE_DIR/skills/SKILL.md"
  assert_output --partial "---"
}

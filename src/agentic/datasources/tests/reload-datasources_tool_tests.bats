#!/usr/bin/env bats
# Tests for tools/reload-datasources.mcp.sh — the MCP wrapper around the reload.
# The reload itself is stubbed through DATASOURCES_RELOAD_SCRIPT so these run
# without docker, a gateway or a single real datasource.

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/reload-datasources.mcp.sh"

  WORK="$(mktemp -d)"
  mkdir -p "${WORK}/project"
  PROJECT="$(cd "${WORK}/project" && pwd)"
  printf '{"datasources": []}\n' >"${PROJECT}/.devbot.project.jsonc"

  export DATASOURCES_RELOAD_SCRIPT="${WORK}/stub-reload.sh"
  export TOOLS_MCP_PROJECT_DIR="${PROJECT}"
}

teardown() {
  rm -rf "${WORK}"
}

# A reload stand-in: echoes the project it was handed, complains on stderr the
# way a dropped source does, and exits with the requested status.
_write_stub() {
  local status="$1"
  cat >"${DATASOURCES_RELOAD_SCRIPT}" <<SH
#!/usr/bin/env bash
echo "stub reload for \$1"
echo "ERROR: a source is unserved" >&2
exit ${status}
SH
  chmod +x "${DATASOURCES_RELOAD_SCRIPT}"
}

@test "tool reload-datasources: is executable" {
  [ -f "$TOOL" ]
  [ -x "$TOOL" ]
}

@test "tool reload-datasources: mcp-meta declares a name and its own timeout" {
  # The reload outlives the server's 120s default, so it must carry its own
  # bound or a cold run is killed mid-way.
  run bash "$TOOL" mcp-meta
  assert_success
  run python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["name"], d["timeoutMs"])' <<<"$output"
  assert_output "reload-datasources 900000"
}

@test "tool reload-datasources: a complete reload names the project and the outcome" {
  _write_stub 0
  run bash "$TOOL"
  assert_success
  assert_output --partial "project: ${PROJECT}"
  assert_output --partial "stub reload for ${PROJECT}"
  assert_output --partial "reload: complete"
}

@test "tool reload-datasources: an incomplete reload keeps every line and still succeeds" {
  # The MCP server surfaces stderr instead of stdout for a non-zero exit, so the
  # wrapper flattens both streams and exits 0 — otherwise the agent loses every
  # per-source result and sees only the last error line.
  _write_stub 1
  run bash "$TOOL"
  assert_success
  assert_output --partial "stub reload for"
  assert_output --partial "ERROR: a source is unserved"
  assert_output --partial "reload: not complete (exit 1)"
  refute_output --partial "which source is unserved"
}

@test "tool reload-datasources: an aborted reload says nothing was applied" {
  # Exit 2 is a documented result, not a malfunction: the running config is
  # untouched, and calling it "not complete" would report a reload that never ran.
  _write_stub 2
  run bash "$TOOL"
  assert_success
  assert_output --partial "reload: not applied (exit 2)"
}

@test "tool reload-datasources: a reload that cannot run fails the call" {
  # 126 is not a result — bash or the script is broken. The transcript goes to
  # stdout so the server's stdout fallback still carries it.
  _write_stub 126
  run bash "$TOOL"
  assert_output --partial "reload: could not run (exit 126)"
}

@test "tool reload-datasources: --project is handed to the reload" {
  _write_stub 0
  local other="${WORK}/other"
  mkdir -p "${other}"
  printf '{"datasources": []}\n' >"${other}/.devbot.project.jsonc"

  run bash "$TOOL" --project "${other}"
  assert_success
  assert_output --partial "project: ${other}"
  assert_output --partial "stub reload for ${other}"
}

@test "tool reload-datasources: a directory that is not a devbot project fails the call" {
  # Without a project config the selection is empty, so the reload verifies
  # nothing and would report a clean result for the wrong directory.
  _write_stub 0
  run bash "$TOOL" --project "${WORK}"
  assert_failure
  assert_output --partial "not a devbot project"
}

@test "tool reload-datasources: a missing project directory fails the call" {
  _write_stub 0
  run bash "$TOOL" --project "/nonexistent/project"
  assert_failure
  assert_output --partial "no such project directory"
}

@test "tool reload-datasources: a missing reload script fails the call" {
  export DATASOURCES_RELOAD_SCRIPT="${WORK}/absent.sh"
  run bash "$TOOL"
  assert_failure
  assert_output --partial "reload script not found"
}

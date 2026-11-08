#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/project_for_path_tests.bats
# Tests for the project-for-path tool: owner resolution over the global
# `projects` registry and the owner's effective (project-first) config.
# =============================================================================

setup() {
  bats_require_minimum_version 1.5.0
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/tools/devbot-cli/tools/project-for-path.mcp.sh"

  SANDBOX="$(mktemp -d)"
  A="${SANDBOX}/proj-a"
  B="${A}/nested-b"
  UNREGISTERED="${SANDBOX}/outside"
  GLOBAL="${SANDBOX}/global.jsonc"
  mkdir -p "${A}/src" "${B}/src" "${UNREGISTERED}"

  cat > "${GLOBAL}" <<EOF
{
  "commit_memory": true,
  "workflow": "worktrees",
  "datasources": { "catalogue-a": { "type": "mysql" } },
  "modules": { "qmd": false, "signoz": true },
  "projects": ["${A}", "${B}"]
}
EOF

  printf '{ "workflow": "trunk", "datasources": ["db-b"], "modules": { "signoz": false } }\n' \
    > "${B}/.devbot.project.jsonc"
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

run_tool() {
  run bash "${TOOL}" "$@" --global-config "${GLOBAL}"
}

@test "project-for-path: resolves a nested path to the longest registered project" {
  run_tool "${B}/src/file.ts" --json

  assert_success
  assert_equal "$(jq -r .path <<< "${output}")" "${B}"
  assert_equal "$(jq -r .name <<< "${output}")" "nested-b"
}

@test "project-for-path: resolves a path in the parent project to the parent" {
  run_tool "${A}/src/file.ts" --json

  assert_success
  assert_equal "$(jq -r .path <<< "${output}")" "${A}"
}

@test "project-for-path: maps an unregistered path to exit 3" {
  run_tool "${UNREGISTERED}/file.ts" --json

  assert_failure 3
  assert_output --partial "no registered project contains"
}

@test "project-for-path: reports the owner's project-first config with global fallback" {
  run_tool "${B}/src/file.ts" --json

  assert_success
  assert_equal "$(jq -r .config.workflow <<< "${output}")" "trunk"
  assert_equal "$(jq -r .config.commit_memory <<< "${output}")" "true"
  assert_equal "$(jq -r '.config.datasources[0]' <<< "${output}")" "db-b"
  assert_equal "$(jq -r '.config.modules.signoz' <<< "${output}")" "false"
  assert_equal "$(jq -r .config.devbot_dir <<< "${output}")" ".agents"
}

@test "project-for-path: modules merge per key, the project value winning" {
  run_tool "${B}/src/file.ts" --json

  assert_success
  assert_equal "$(jq -r '.config.modules.qmd' <<< "${output}")" "false"
  assert_equal "$(jq -r '.config.modules.signoz' <<< "${output}")" "false"
}

@test "project-for-path: datasources is the owner's selection, never the global catalogue" {
  run_tool "${A}/src/file.ts" --json
  assert_success
  assert_equal "$(jq -c '.config.datasources' <<< "${output}")" "[]"

  printf '{ "datasources": [] }\n' > "${A}/.devbot.project.jsonc"
  run_tool "${A}/src/file.ts" --key datasources
  assert_success
  assert_output "[]"
}

@test "project-for-path: --key prints one resolved value" {
  run_tool "${B}/src/file.ts" --key workflow
  assert_success
  assert_output "trunk"

  run_tool "${B}/src/file.ts" --key commit_memory
  assert_success
  assert_output "true"
}

@test "project-for-path: maps the retired worktrees key until migration runs" {
  printf '{ "worktrees": false, "datasources": ["db-b"] }\n' > "${B}/.devbot.project.jsonc"

  run_tool "${B}/src/file.ts" --key workflow
  assert_success
  assert_output "trunk"

  printf '{ "worktrees": true }\n' > "${B}/.devbot.project.jsonc"

  run_tool "${B}/src/file.ts" --key workflow
  assert_success
  assert_output "worktrees"
}

@test "project-for-path: reports supervisor from the project config, default false" {
  run_tool "${A}/src/file.ts" --key supervisor
  assert_success
  assert_output "false"

  printf '{ "supervisor": true }\n' > "${B}/.devbot.project.jsonc"
  run_tool "${B}/src/file.ts" --key supervisor
  assert_success
  assert_output "true"
}

@test "project-for-path: renders a markdown table by default" {
  run_tool "${B}/src/file.ts"

  assert_success
  assert_output --partial "## Owning project"
  assert_output --partial "| workflow | trunk |"
  assert_output --partial "| datasources | db-b |"
}

@test "project-for-path: fails with usage when no path is given" {
  run_tool

  assert_failure 2
  assert_output --partial "<path> is required"
}

@test "project-for-path: fails on an unknown --key" {
  run_tool "${B}/src/file.ts" --key nope

  assert_failure 2
  assert_output --partial "unknown key"
}

# ── Live MCP server state ────────────────────────────────────────────────────

@test "project-for-path: reports live MCP state from the harness config above the owner" {
  cat > "${A}/opencode.jsonc" <<'JSONC'
{
  // wired but not started
  "mcp": {
    "atlassian": { "type": "remote", "enabled": false },
    "datasources": { "type": "local", "command": ["x"] }
  }
}
JSONC

  run_tool "${B}/src/file.ts" --key mcps
  assert_success
  assert_equal "$(jq -r .atlassian <<< "${output}")" "disabled"
  assert_equal "$(jq -r .datasources <<< "${output}")" "enabled"
}

@test "project-for-path: reports claudecode .mcp.json entries as enabled" {
  printf '{ "mcpServers": { "atlassian": { "type": "http", "url": "x" } } }\n' > "${A}/.mcp.json"

  run_tool "${B}/src/file.ts" --key mcps
  assert_success
  assert_equal "$(jq -r .atlassian <<< "${output}")" "enabled"
}

@test "project-for-path: reports no MCP servers when no harness config exists" {
  run_tool "${A}/src/file.ts" --key mcps
  assert_success
  assert_output "{}"
}

@test "project-for-path: renders the MCP row in the markdown table" {
  cat > "${A}/opencode.jsonc" <<'JSONC'
{ "mcp": { "atlassian": { "enabled": false } } }
JSONC

  run_tool "${B}/src/file.ts"
  assert_success
  assert_output --partial "| mcps | atlassian:disabled |"
}

@test "project-for-path: the nearest config wins and its ancestors do not leak" {
  cat > "${A}/opencode.jsonc" <<'JSONC'
{ "mcp": { "parent-only": { "enabled": true }, "atlassian": { "enabled": false } } }
JSONC
  cat > "${B}/opencode.jsonc" <<'JSONC'
{ "mcp": { "atlassian": { "enabled": true } } }
JSONC

  run_tool "${B}/src/file.ts" --key mcps
  assert_success
  assert_equal "$(jq -r .atlassian <<< "${output}")" "enabled"
  assert_equal "$(jq -r 'has("parent-only")' <<< "${output}")" "false"
}

@test "project-for-path: --session-root reads the live checkout, not the owner's" {
  cat > "${A}/opencode.jsonc" <<'JSONC'
{ "mcp": { "atlassian": { "enabled": false } } }
JSONC
  mkdir -p "${SANDBOX}/session"
  cat > "${SANDBOX}/session/opencode.jsonc" <<'JSONC'
{ "mcp": { "atlassian": { "enabled": true } } }
JSONC

  run bash "${TOOL}" "${A}/src/file.ts" --key mcps \
    --session-root "${SANDBOX}/session" --global-config "${GLOBAL}"
  assert_success
  assert_equal "$(jq -r .atlassian <<< "${output}")" "enabled"
}

@test "project-for-path: reads both harness shapes, opencode authoritative per server" {
  cat > "${A}/opencode.jsonc" <<'JSONC'
{ "mcp": { "atlassian": { "enabled": false } } }
JSONC
  printf '{ "mcpServers": { "atlassian": { "url": "x" }, "claude-only": { "url": "y" } } }\n' \
    > "${A}/.mcp.json"

  run_tool "${A}/src/file.ts" --json
  assert_success
  assert_equal "$(jq -r '.config.mcps.atlassian' <<< "${output}")" "disabled"
  assert_equal "$(jq -r '.config.mcps."claude-only"' <<< "${output}")" "enabled"
  assert_output --partial "opencode.jsonc"
  assert_output --partial ".mcp.json"
}

@test "project-for-path: a malformed config is reported, never collapsed to empty" {
  printf '{ "mcp": ' > "${A}/opencode.jsonc"
  printf '{ "mcpServers": { "atlassian": { "url": "x" } } }\n' > "${A}/.mcp.json"

  run_tool "${A}/src/file.ts" --json
  assert_success
  assert_equal "$(jq -r '.config.mcps.atlassian' <<< "${output}")" "enabled"
  run grep -qF 'opencode.jsonc' <<< "$(jq -r '.config.mcps_errors[0]' <<< "${output}")"
  assert_success
}

@test "project-for-path: the table distinguishes an empty config from a missing one" {
  cat > "${A}/opencode.jsonc" <<'JSONC'
{ "mcp": {} }
JSONC

  run_tool "${A}/src/file.ts"
  assert_success
  assert_output --partial "config found, no MCP servers declared"
  assert_output --partial "| mcps source | ${A}/opencode.jsonc |"
}

@test "project-for-path: --session-root is read directly, never walked upward" {
  mkdir -p "${SANDBOX}/session/empty"
  cat > "${SANDBOX}/session/opencode.jsonc" <<'JSONC'
{ "mcp": { "atlassian": { "enabled": true } } }
JSONC

  # The empty subdir has no config of its own: walking would find the parent's.
  run bash "${TOOL}" "${A}/src/file.ts" --key mcps \
    --session-root "${SANDBOX}/session/empty" --global-config "${GLOBAL}"
  assert_success
  assert_output "{}"
}

@test "project-for-path: a non-object mcp map is reported, not crashed" {
  printf '{ "mcp": ["atlassian"] }\n' > "${A}/opencode.jsonc"

  run_tool "${A}/src/file.ts" --key mcps_errors
  assert_success
  assert_output --partial '`mcp` is not an object'
}

@test "project-for-path: a non-object mcpServers map is reported, not iterated" {
  printf '{ "mcpServers": [{ "atlassian": {} }] }\n' > "${A}/.mcp.json"

  run_tool "${A}/src/file.ts" --key mcps_errors
  assert_success
  assert_output --partial '`mcpServers` is not an object'
}

@test "project-for-path: --key mcps fails loudly when the config is unreadable" {
  printf 'not json at all' > "${A}/opencode.jsonc"

  run_tool "${A}/src/file.ts" --key mcps
  assert_failure 2
  assert_output --partial "cannot read the harness MCP config"
}

@test "project-for-path: --key accepts the dashed alias of a snake_case key" {
  printf '{ "mcp": ["atlassian"] }\n' > "${A}/opencode.jsonc"

  run_tool "${A}/src/file.ts" --key mcps-errors
  assert_success
  assert_output --partial '`mcp` is not an object'
}

@test "project-for-path: a --session-root that is not a directory fails" {
  run bash "${TOOL}" "${A}/src/file.ts" --key mcps \
    --session-root "${SANDBOX}/nope" --global-config "${GLOBAL}"
  assert_failure 2
  assert_output --partial "not a directory"

  run bash "${TOOL}" "${A}/src/file.ts" --key mcps \
    --session-root "${GLOBAL}" --global-config "${GLOBAL}"
  assert_failure 2
}

@test "project-for-path: the table labels a config error as an error" {
  printf '{ "mcp": ["atlassian"] }\n' > "${A}/opencode.jsonc"

  run_tool "${A}/src/file.ts"
  assert_success
  assert_output --partial "| mcps error |"
}

@test "project-for-path: an unknown key error echoes the input as typed" {
  run_tool "${A}/src/file.ts" --key nope-here
  assert_failure 2
  assert_output --partial "unknown key 'nope-here'"
}

@test "project-for-path: mcps keys are sorted regardless of config order" {
  cat > "${A}/opencode.jsonc" <<'JSONC'
{ "mcp": { "zeta": { "enabled": true }, "alpha": { "enabled": true } } }
JSONC

  run_tool "${A}/src/file.ts" --key mcps
  assert_success
  assert_equal "$(jq -r 'keys_unsorted | join(",")' <<< "${output}")" "alpha,zeta"
}

@test "project-for-path: a multi-line parse error stays on one table row" {
  printf '{ "mcp": { "a": } }\n' > "${A}/opencode.jsonc"

  run_tool "${A}/src/file.ts"
  assert_success
  assert_equal "$(grep -c '^| mcps error |' <<< "${output}")" "1"
}

@test "project-for-path: a pipe in a table value is escaped, not breaking the row" {
  mkdir -p "${SANDBOX}/pip|ed"
  printf '{ "mcp": { "a|b": { "enabled": true } } }\n' > "${SANDBOX}/pip|ed/opencode.jsonc"

  run bash "${TOOL}" "${A}/src/file.ts" --session-root "${SANDBOX}/pip|ed" \
    --global-config "${GLOBAL}"
  assert_success
  assert_output --partial 'a\|b:enabled'
}

@test "project-for-path: --json exposes MCP sources and errors as arrays" {
  printf '{ "mcp": { "atlassian": { "enabled": true } } }\n' > "${A}/opencode.jsonc"

  run_tool "${A}/src/file.ts" --json
  assert_success
  assert_equal "$(jq -r '.config.mcps_sources | type' <<< "${output}")" "array"
  assert_equal "$(jq -r '.config.mcps_sources[0]' <<< "${output}")" "${A}/opencode.jsonc"
  assert_equal "$(jq -r '.config.mcps_errors | type' <<< "${output}")" "array"
}

@test "project-for-path: a newline in a table value does not split the row" {
  printf '{ "workflow": "trunk\\nsecond-line", "datasources": [] }\n' > "${A}/.devbot.project.jsonc"

  run_tool "${A}/src/file.ts"
  assert_success
  assert_equal "$(grep -c '^| workflow |' <<< "${output}")" "1"
  assert_output --partial "| workflow | trunk second-line |"
}

@test "project-for-path: the unknown-key error shows the dashed spellings" {
  run_tool "${A}/src/file.ts" --key nope
  assert_failure 2
  assert_output --partial "mcps-errors"
  assert_output --partial "dashes map to underscores"
}

@test "project-for-path: a non-object server entry is reported, not dropped" {
  printf '{ "mcp": { "atlassian": "oops" } }\n' > "${A}/opencode.jsonc"

  run_tool "${A}/src/file.ts" --json
  assert_success
  assert_equal "$(jq -r '.config.mcps | has("atlassian")' <<< "${output}")" "false"
  assert_output --partial 'server `atlassian` is not an object'
}

@test "project-for-path: a null or empty mcp map is an error, not an empty config" {
  for value in 'null' '[]'; do
    printf '{ "mcp": %s }\n' "$value" > "${A}/opencode.jsonc"
    run_tool "${A}/src/file.ts" --key mcps_errors
    assert_success
    assert_output --partial '`mcp` is not an object'
  done
}

@test "project-for-path: a non-boolean enabled value is reported and skipped" {
  printf '{ "mcp": { "atlassian": { "enabled": "false" } } }\n' > "${A}/opencode.jsonc"

  run_tool "${A}/src/file.ts" --json
  assert_success
  assert_equal "$(jq -r '.config.mcps | has("atlassian")' <<< "${output}")" "false"
  assert_output --partial "non-boolean `enabled`"
}

@test "project-for-path: a null mcpServers map is an error, not an empty config" {
  printf '{ "mcpServers": null }\n' > "${A}/.mcp.json"

  run_tool "${A}/src/file.ts" --key mcps_errors
  assert_success
  assert_output --partial '`mcpServers` is not an object'
}

@test "project-for-path: a non-object .mcp.json server entry is reported, not enabled" {
  printf '{ "mcpServers": { "atlassian": false } }\n' > "${A}/.mcp.json"

  run_tool "${A}/src/file.ts" --json
  assert_success
  assert_equal "$(jq -r '.config.mcps | has("atlassian")' <<< "${output}")" "false"
  assert_output --partial 'server `atlassian` is not an object'
}

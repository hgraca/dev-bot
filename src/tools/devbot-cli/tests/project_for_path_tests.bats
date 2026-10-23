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

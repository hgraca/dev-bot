#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/project_memory_tests.bats
# Tests for the project-memory tool: resolve the owning project over the global
# `projects` registry, then print that project's AGENTS.md/CLAUDE.md and
# <devbot_dir>/memory/active/**/*.md, labelled and scoped to that project.
# =============================================================================

setup() {
  bats_require_minimum_version 1.5.0
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/tools/devbot-cli/tools/project-memory.mcp.sh"

  SANDBOX="$(mktemp -d)"
  A="${SANDBOX}/proj-a"
  B="${A}/nested-b"
  C="${SANDBOX}/empty-project"
  D="${SANDBOX}/malformed-dir"
  S="${SANDBOX}/monorepo-root"
  UNREGISTERED="${SANDBOX}/outside"
  GLOBAL="${SANDBOX}/global.jsonc"

  mkdir -p "${A}/.agents/memory/active/sub" "${B}/.devbot-memory/memory/active" "${C}" "${D}/.agents/memory/active" "${S}/.agents/memory/active" "${UNREGISTERED}"

  printf '# Proj A rules\n' > "${A}/AGENTS.md"
  printf '# A claude rules\n' > "${A}/CLAUDE.md"
  printf '# A project facts\n' > "${A}/.agents/memory/active/project.md"
  printf '# A alpha note\n' > "${A}/.agents/memory/active/sub/alpha.md"
  printf '# A zeta note\n' > "${A}/.agents/memory/active/sub/zeta.md"
  printf '# A nested note\n' > "${A}/.agents/memory/active/sub/deep.md"
  printf '# A zeta root note\n' > "${A}/.agents/memory/active/zeta-root.md"
  printf '# Shared rule\n' > "${SANDBOX}/shared-rule.md"
  ln -s "${SANDBOX}/shared-rule.md" "${A}/.agents/memory/active/linked.md"

  printf '# D project facts\n' > "${D}/.agents/memory/active/project.md"
  printf '{ "devbot_dir": 42 }\n' > "${D}/.devbot.project.jsonc"

  printf '# B claude rules\n' > "${B}/CLAUDE.md"
  printf '# B project facts\n' > "${B}/.devbot-memory/memory/active/project.md"
  printf '{ "devbot_dir": ".devbot-memory" }\n' > "${B}/.devbot.project.jsonc"

  printf '# Monorepo coordination rules\n' > "${S}/.agents/memory/active/project.md"
  printf '{ "monorepo": true }\n' > "${S}/.devbot.project.jsonc"

  cat > "${GLOBAL}" <<EOF
{
  "projects": ["${A}", "${B}", "${C}", "${D}", "${S}"]
}
EOF
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

run_tool() {
  run bash "${TOOL}" "$@" --global-config "${GLOBAL}"
}

line_of() {
  printf '%s\n' "${output}" | grep -n -F -x "$1" | cut -d: -f1
}

@test "project-memory: prints the owner's AGENTS.md and active files, each labelled" {
  run_tool "${A}/src/file.ts"

  assert_success
  assert_output --partial "## Active memory for proj-a"
  assert_output --partial "### AGENTS.md"
  assert_output --partial "### .agents/memory/active/project.md"
  assert_output --partial "# Proj A rules"
  assert_output --partial "# A project facts"
}

@test "project-memory: prints AGENTS.md before the active files" {
  run_tool "${A}/src/file.ts"

  assert_success
  [ "$(line_of '### AGENTS.md')" -lt "$(line_of '### .agents/memory/active/project.md')" ]
}

@test "project-memory: prints AGENTS.md before CLAUDE.md when both exist" {
  run_tool "${A}/src/file.ts"

  assert_success
  [ "$(line_of '### AGENTS.md')" -lt "$(line_of '### CLAUDE.md')" ]
}

@test "project-memory: lists active files in sorted path order" {
  run_tool "${A}/src/file.ts"

  assert_success
  [ "$(line_of '### .agents/memory/active/sub/alpha.md')" -lt "$(line_of '### .agents/memory/active/sub/zeta.md')" ]
  [ "$(line_of '### .agents/memory/active/sub/alpha.md')" -lt "$(line_of '### .agents/memory/active/zeta-root.md')" ]
}

@test "project-memory: labels a symlinked memory file with its real path" {
  run_tool "${A}/src/file.ts"

  assert_success
  assert_output --partial "### .agents/memory/active/linked.md -> ${SANDBOX}/shared-rule.md"
  assert_output --partial "# Shared rule"
}

@test "project-memory: includes active memory from nested subdirectories" {
  run_tool "${A}/src/file.ts"

  assert_success
  assert_output --partial "### .agents/memory/active/sub/deep.md"
  assert_output --partial "# A nested note"
}

@test "project-memory: resolves a nested path to the nested project" {
  run_tool "${B}/src/file.ts"

  assert_success
  assert_output --partial "## Active memory for nested-b"
  assert_output --partial "**Path:** ${B}"
}

@test "project-memory: reads the owner's custom devbot_dir" {
  run_tool "${B}/src/file.ts"

  assert_success
  assert_output --partial "### .devbot-memory/memory/active/project.md"
  assert_output --partial "# B project facts"
  refute_output --partial "### .agents/memory/active/"
}

@test "project-memory: falls back to .agents when devbot_dir is not a string" {
  run_tool "${D}/file.ts"

  assert_success
  assert_output --partial "## Active memory for malformed-dir"
  assert_output --partial "### .agents/memory/active/project.md"
  assert_output --partial "# D project facts"
}

@test "project-memory: includes CLAUDE.md when the project has no AGENTS.md" {
  run_tool "${B}/src/file.ts"

  assert_success
  assert_output --partial "### CLAUDE.md"
  assert_output --partial "# B claude rules"
  refute_output --partial "### AGENTS.md"
}

@test "project-memory: never includes a sibling project's memory" {
  run_tool "${B}/src/file.ts"

  assert_success
  refute_output --partial "Proj A"
  refute_output --partial "A project facts"
}

@test "project-memory: states the scope of the memory it prints" {
  run_tool "${A}/src/file.ts"

  assert_success
  assert_output --partial "**Scope:** applies only within this project."
}

@test "project-memory: reports a project with no active memory and exits 0" {
  run_tool "${C}/file.ts"

  assert_success
  assert_output --partial "## Active memory for empty-project"
  assert_output --partial "No active memory:"
  refute_output --partial "###"
}

@test "project-memory: resolves a monorepo project to itself" {
  run_tool "${S}/file.ts"

  assert_success
  assert_output --partial "## Active memory for monorepo-root"
  assert_output --partial "# Monorepo coordination rules"
}

@test "project-memory: fails with exit 3 for an unregistered path" {
  run_tool "${UNREGISTERED}/file.ts"

  assert_failure 3
  assert_output --partial "no registered project contains"
}

@test "project-memory: fails with usage when no path is given" {
  run_tool

  assert_failure 2
  assert_output --partial "<path> is required"
}

@test "project-memory: rejects an unknown argument" {
  run_tool "${A}/src/file.ts" --nope

  assert_failure 2
  assert_output --partial "unknown argument"
}

@test "project-memory: exposes mcp-meta" {
  run bash "${TOOL}" mcp-meta

  assert_success
  [[ "${output}" == *'"name":"project-memory"'* ]] || fail "expected project-memory name in mcp-meta"
}

@test "project-memory: --help prints the usage block" {
  run bash "${TOOL}" --help

  assert_success
  assert_output --partial "project-memory.mcp.sh <path>"
  assert_output --partial "Exit codes"
}

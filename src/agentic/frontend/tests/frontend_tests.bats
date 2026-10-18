#!/usr/bin/env bats
# =============================================================================
# src/agentic/frontend/tests/frontend_tests.bats
# Contract for the Design QA capability: command and skill front matter, the
# docs.md capability manifest, the canonical Figma MCP manifest and its
# translation to each harness shape, and the config-sourced workflow.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PROJECT_ROOT="$(cd "${MODULE}/../../.." && pwd)"
  TRANSLATE="${PROJECT_ROOT}/src/_shared/mcp_translate.py"
}

front_matter() {
  awk 'NR == 1 && /^---$/ { inside = 1; next } inside && /^---$/ { exit } inside { print }' "$1"
}

manifest_flow_list() {
  sed -n "s/^$1:[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p" "${MODULE}/docs.md" |
    tr ',' '\n' |
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//' |
    sed '/^$/d' |
    sort
}

manifest_mcp_keys() {
  sed -n '/^mcps:/,/^[^[:space:]]/p' "${MODULE}/docs.md" |
    sed -n 's/^[[:space:]][[:space:]]*\([A-Za-z0-9_.-]*\):.*/\1/p' |
    sort
}

disk_commands() {
  for path in "${MODULE}"/commands/*.md; do basename "$path" .md; done | sort
}

disk_skills() {
  for path in "${MODULE}"/skills/*/; do basename "$path"; done | sort
}

disk_mcps() {
  python3 -c 'import json,sys; print("\n".join(sorted(json.load(open(sys.argv[1]))["mcp"])))' \
    "${MODULE}/mcp.json"
}

@test "every command declares name: devbot:<filename> and a description" {
  for path in "${MODULE}"/commands/*.md; do
    name="$(basename "$path" .md)"
    run front_matter "$path"
    assert_output --partial "name: devbot:${name}"
    run grep -q '^description: ' "$path"
    assert_success
  done
}

@test "every command delegates to its skill" {
  for path in "${MODULE}"/commands/*.md; do
    name="$(basename "$path" .md)"
    run grep -q "devbot:${name}" "$path"
    assert_success
  done
}

@test "docs.md commands manifest matches the command files" {
  run diff -u <(disk_commands) <(manifest_flow_list commands)
  assert_success
}

@test "every skill declares valid front matter" {
  for path in "${MODULE}"/skills/*/SKILL.md; do
    name="$(basename "$(dirname "$path")")"
    run front_matter "$path"
    assert_output --partial "name: devbot:${name}"
    run grep -q '^description: ' "$path"
    assert_success
  done
}

@test "docs.md skills manifest matches the skill directories" {
  run diff -u <(disk_skills) <(manifest_flow_list skills)
  assert_success
}

@test "docs.md mcps manifest matches the canonical manifest" {
  run diff -u <(disk_mcps) <(manifest_mcp_keys)
  assert_success
}

@test "docs.md front matter stays inside the restricted subset" {
  fm="$(front_matter "${MODULE}/docs.md")"
  run grep -qE '^[[:space:]]*[A-Za-z0-9_-]+:[[:space:]]*[>|]-?[[:space:]]*$' <<<"$fm"
  assert_failure
  run grep -qE '^[[:space:]]+- ' <<<"$fm"
  assert_failure
}

@test "the module README page is produced by the docs gather" {
  run python3 "${PROJECT_ROOT}/src/agentic/docs/tools/gather-module-docs.py" \
    --root "${PROJECT_ROOT}" --out "${BATS_TEST_TMPDIR}/site"
  assert_success
  run grep -q 'design-qa' "${BATS_TEST_TMPDIR}/site/modules/agentic/frontend.md"
  assert_success
}

@test "the figma server ships wired but not started" {
  run python3 - "${MODULE}/mcp.json" <<'PY'
import json, sys
entry = json.load(open(sys.argv[1]))["mcp"]["figma"]
assert entry["type"] == "http", entry
assert entry["url"] == "https://mcp.figma.com/mcp", entry
assert entry["enabled"] is False, entry
PY
  assert_success
}

@test "the opencode translation registers figma with enabled: false" {
  run python3 "${TRANSLATE}" "${MODULE}/mcp.json" opencode
  assert_success
  run python3 -c 'import json,sys; assert json.load(sys.stdin)["figma"] == {"type": "remote", "url": "https://mcp.figma.com/mcp", "enabled": False}' <<<"$output"
  assert_success
}

@test "the claudecode translation carries no per-server enabled key" {
  run python3 "${TRANSLATE}" "${MODULE}/mcp.json" claudecode
  assert_success
  run python3 -c 'import json,sys; e = json.load(sys.stdin)["figma"]; assert e == {"type": "http", "url": "https://mcp.figma.com/mcp"}, e' <<<"$output"
  assert_success
}

@test "the skill documents the unconfigured fallbacks" {
  run grep -q 'http://localhost:3000' "${MODULE}/skills/design-qa/SKILL.md"
  assert_success
  run grep -q 'defaults.tolerancePx' "${MODULE}/skills/design-qa/SKILL.md"
  assert_success
}

@test "the ported workflow carries no consumer-specific literal" {
  run grep -RInE 'hotels\.get-e\.local|src/pages\.ts|src/constants/urlPaths\.ts|#launcher|chmln|MuiSkeleton' \
    "${MODULE}/commands" "${MODULE}/skills/design-qa" "${MODULE}/skills/design-qa-all"
  assert_failure
}

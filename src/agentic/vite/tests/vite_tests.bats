#!/usr/bin/env bats
# =============================================================================
# src/agentic/vite/tests/vite_tests.bats
# Contract for the Vite capability: the docs.md capability manifest, the
# canonical Vite MCP manifest and its translation to each harness shape, the
# opt-in registration, and the vendored skills declared in both places.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  PROJECT_ROOT="$(cd "${MODULE}/../../.." && pwd)"
  TRANSLATE="${PROJECT_ROOT}/src/_shared/mcp_translate.py"
  DIST="${PROJECT_ROOT}/.devbot.global.dist.jsonc"
}

manifest_mcp_keys() {
  sed -n '/^mcps:/,/^[^[:space:]]/p' "${MODULE}/docs.md" |
    sed -n 's/^[[:space:]][[:space:]]*\([A-Za-z0-9_.-]*\):.*/\1/p' |
    sort
}

disk_mcps() {
  python3 -c 'import json,sys; print("\n".join(sorted(json.load(open(sys.argv[1]))["mcp"])))' \
    "${MODULE}/mcp.json"
}

@test "docs.md mcps manifest matches the canonical manifest" {
  run diff -u <(disk_mcps) <(manifest_mcp_keys)
  assert_success
}

@test "the vite MCP is a disabled client for the dev server's endpoint" {
  run python3 - "${MODULE}/mcp.json" <<'PY'
import json, sys
entry = json.load(open(sys.argv[1]))["mcp"]["vite"]
assert entry["type"] == "http", entry
assert entry["enabled"] is False, entry
# Vite's MCP servers are plugins inside the dev server, so the module can only
# be a client for the endpoint the Tidewave plugin serves — never a launcher.
assert entry["url"].endswith("/tidewave/mcp"), entry
PY
  assert_success
}

@test "the opencode translation registers vite with enabled: false" {
  run python3 "${TRANSLATE}" "${MODULE}/mcp.json" opencode
  assert_success
  run python3 -c 'import json,sys; assert json.load(sys.stdin)["vite"]["enabled"] is False' <<<"$output"
  assert_success
}

@test "the opencode-v2 registration inverts enabled into disabled" {
  run python3 "${TRANSLATE}" "${MODULE}/mcp.json" opencode-v2
  assert_success
  # v2 spells per-server enablement inverted; init.sh applies the same
  # inversion to every translated entry before merging it.
  run python3 -c '
import json, sys
entry = json.load(sys.stdin)["vite"]
if "enabled" in entry:
    entry["disabled"] = not entry.pop("enabled")
assert entry["disabled"] is True, entry
' <<<"$output"
  assert_success
}

@test "the claudecode translation carries no per-server enablement key" {
  run python3 "${TRANSLATE}" "${MODULE}/mcp.json" claudecode
  assert_success
  run python3 -c '
import json, sys
entry = json.load(sys.stdin)["vite"]
assert "enabled" not in entry, entry
assert "disabled" not in entry, entry
' <<<"$output"
  assert_success
}

@test "the module ships opt-in, so no existing project gains it" {
  # A module absent from the dist `modules` map is ENABLED, so shipping this
  # one without the entry would wire the vite server into every project.
  run python3 "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${DIST}"
  assert_success
  run python3 -c 'import json,sys; assert json.load(sys.stdin)["modules"]["vite"] is False' <<<"$output"
  assert_success
}

@test "the vendored skills are declared in the module and mirrored in the dist" {
  run python3 - "${MODULE}/external-modules.json" "${DIST}" \
    "${PROJECT_ROOT}/src/_shared/read_jsonc.py" <<'PY'
import json, subprocess, sys

module = json.load(open(sys.argv[1]))
dist, reader = sys.argv[2], sys.argv[3]
dist_modules = json.loads(
    subprocess.check_output(["python3", reader, dist, "external_modules"], text=True)
)

for name, expected_path in (("antfu-vite", "skills/vite"), ("antfu-vitest", "skills/vitest")):
    assert name in module, (name, module)
    assert module[name]["paths"] == {"skills": expected_path}, module[name]
    assert dist_modules[name] == module[name], (name, dist_modules.get(name))
PY
  assert_success
}

@test "the module README page is produced by the docs gather" {
  run python3 "${PROJECT_ROOT}/src/agentic/docs/tools/gather-module-docs.py" \
    --root "${PROJECT_ROOT}" --out "${BATS_TEST_TMPDIR}/site"
  assert_success
  run grep -q 'tidewave' "${BATS_TEST_TMPDIR}/site/modules/agentic/vite.md"
  assert_success
}

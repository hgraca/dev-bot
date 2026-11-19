#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/reset_tests.bats
# Tests for opencode-v2/reset.sh's MCP-key pruning:
#   - a server key dev-bot renamed is retired whatever its module's state
#   - a retired key PREFIX is swept, because that family is unbounded
#
# Runs the REAL reset.sh against a sandbox project dir. The v2 config nests
# servers under mcp.servers, which is the shape every key operation targets.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
  DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
  RESET_SCRIPT="${MODULE_DIR}/reset.sh"
  HELPER="${MODULE_DIR}/lib/v2config.py"

  SANDBOX_DIR="$(mktemp -d)"
  CONFIG="${SANDBOX_DIR}/opencode.jsonc"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v jq &>/dev/null || skip "jq not installed"
  command -v bash &>/dev/null || skip "bash not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

v2() {
  V2_SHARED_DIR="${DEV_BOT_ROOT}/src/_shared" python3 "${HELPER}" "$@"
}

# _write_project_config <modules-json>: opencode-v2 selected, module states set
# explicitly so the test never depends on whatever the machine's global config
# disables.
_write_project_config() {
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "harness": "opencode-v2",
  "modules": ${1}
}
JSONC_EOF
  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"
}

# ── D1: a RETIRED key is pruned whatever the module's state ──────────────────
# A server dev-bot itself renamed leaves an orphan no other sweep can find: the
# module's canonical mcp.json no longer declares the old name, so neither the
# disabled-module prune nor any registration matches it. The ENABLED module is
# the case that used to leak, so react is enabled here.
@test "D1: reset prunes a retired MCP key while its module is enabled" {
  _write_project_config '{"react": true}'

  cat > "${CONFIG}" <<'JSONC_EOF'
{
  "mcp": {
    "servers": {
      "next-devtools": {"type": "local", "command": ["next-devtools-mcp"]},
      "react-nextjs-devtools": {"type": "local", "command": ["npx", "-y", "next-devtools-mcp@latest"], "disabled": true},
      "other": {"type": "local", "command": ["other-mcp"]}
    }
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  servers_json="$(v2 get "${CONFIG}" mcp.servers)"
  run jq -e 'has("next-devtools") | not' <<< "${servers_json}"
  assert_success
  run jq -e 'has("react-nextjs-devtools")' <<< "${servers_json}"
  assert_success
  run jq -e 'has("other")' <<< "${servers_json}"
  assert_success
}

# ── D2: a RETIRED key PREFIX is pruned ───────────────────────────────────────
# datasources' server keys moved from `datasources-<source>` to `ds-<source>`.
# The old family is unbounded, so an exact-key list cannot name it, and the
# disabled-module prune only sweeps it while datasources is DISABLED. It is
# enabled here, so only a prefix sweep can clear the orphans — and it must
# leave the current `ds-` keys and an unrelated server alone.
_write_retired_prefix_fixture() {
  _write_project_config '{"datasources": true}'

  cat > "${CONFIG}" <<'JSONC_EOF'
{
  "mcp": {
    "servers": {
      "datasources-mariadb-dev": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/mariadb-dev"},
      "datasources-legacy": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/legacy"},
      "ds-mariadb-dev": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/mariadb-dev"},
      "other": {"type": "local", "command": ["other-mcp"]}
    }
  }
}
JSONC_EOF
}

@test "D2: reset prunes retired MCP key prefixes and keeps current ones" {
  _write_retired_prefix_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  servers_json="$(v2 get "${CONFIG}" mcp.servers)"
  run jq -e 'has("datasources-mariadb-dev") | not' <<< "${servers_json}"
  assert_success
  run jq -e 'has("datasources-legacy") | not' <<< "${servers_json}"
  assert_success
  run jq -e 'has("ds-mariadb-dev")' <<< "${servers_json}"
  assert_success
  run jq -e 'has("other")' <<< "${servers_json}"
  assert_success
}

@test "D3: second reset is byte-idempotent after retiring keys" {
  _write_retired_prefix_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  local after_first
  after_first="$(cat "${CONFIG}")"

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert_equal "$(cat "${CONFIG}")" "${after_first}"
}

# ── D4: a config-only project is swept too ───────────────────────────────────
# reset exits early when .opencode/ is absent, which is right for the symlink
# cleanup but wrong for config pruning: a project can carry a dev-bot-managed
# opencode.jsonc with no symlink farm, and the retirement must still happen.
@test "D4: reset prunes retired keys without an .opencode directory" {
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode-v2",
  "modules": {
    "react": true
  }
}
JSONC_EOF
  # Deliberately no .opencode/ directory.

  cat > "${CONFIG}" <<'JSONC_EOF'
{
  "mcp": {
    "servers": {
      "next-devtools": {"type": "local", "command": ["next-devtools-mcp"]},
      "other": {"type": "local", "command": ["other-mcp"]}
    }
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  servers_json="$(v2 get "${CONFIG}" mcp.servers)"
  run jq -e 'has("next-devtools") | not' <<< "${servers_json}"
  assert_success
  run jq -e 'has("other")' <<< "${servers_json}"
  assert_success
}

# ── D5: a config mid-upgrade is swept in its legacy shape ───────────────────
# bin/init.sh runs this reset BEFORE init migrates a v1 config to the v2 shape,
# so at reset time the servers still sit directly under `mcp`. Sweeping only
# mcp.servers leaves them to be migrated into the new map and survive forever.
@test "D5: reset prunes retired keys from a not-yet-migrated config" {
  _write_project_config '{"react": true, "datasources": true}'

  cat > "${CONFIG}" <<'JSONC_EOF'
{
  "mcp": {
    "next-devtools": {"type": "local", "command": ["next-devtools-mcp"]},
    "datasources-legacy": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/legacy"},
    "other": {"type": "local", "command": ["other-mcp"]}
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import json, sys
sys.path.insert(0, '${DEV_BOT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${CONFIG}')['mcp']
assert 'next-devtools' not in mcp, mcp
assert 'datasources-legacy' not in mcp, mcp
assert 'other' in mcp, mcp
print('D5-LEGACY-SHAPE:OK')
"
  assert_success
  grep -qF 'D5-LEGACY-SHAPE:OK' <<< "$output" || fail "legacy-shaped retired keys survived"
}

# ── D6: a server key containing a dot is still matched ──────────────────────
# v2config's `get` walks a dotted path, so a dotted lookup silently misses a
# key like `datasources-mariadb.prod`; the sweep must compare literal keys.
@test "D6: reset prunes a retired prefix key containing a dot" {
  _write_project_config '{"datasources": true}'

  cat > "${CONFIG}" <<'JSONC_EOF'
{
  "mcp": {
    "servers": {
      "datasources-mariadb.prod": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/prod"},
      "ds-mariadb.prod": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/prod"},
      "other": {"type": "local", "command": ["other-mcp"]}
    }
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  servers_json="$(v2 get "${CONFIG}" mcp.servers)"
  run jq -e 'has("datasources-mariadb.prod") | not' <<< "${servers_json}"
  assert_success
  run jq -e 'has("ds-mariadb.prod")' <<< "${servers_json}"
  assert_success
  run jq -e 'has("other")' <<< "${servers_json}"
  assert_success
}

# ── D7: a long key list does not defeat the sweep ───────────────────────────
# The retired family is unbounded, so the match commonly sits ahead of many
# other keys. A membership test that exits on the first match would SIGPIPE its
# producer, and `set -o pipefail` would read that as "not found" — pruning
# nothing. This pins the sweep against a list long enough to lose that race.
@test "D7: a retired key is pruned when many keys follow it" {
  _write_project_config '{"datasources": true}'

  python3 - "${CONFIG}" <<'PY'
import json, sys

servers = {"datasources-first": {"type": "remote",
                                "url": "http://127.0.0.1:18510/mcp/first"}}
for i in range(400):
    servers[f"other-{i}"] = {"type": "local", "command": ["x"]}
with open(sys.argv[1], "w") as f:
    json.dump({"mcp": {"servers": servers}}, f, indent=2)
    f.write("\n")
PY

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  servers_json="$(v2 get "${CONFIG}" mcp.servers)"
  run jq -e 'has("datasources-first") | not' <<< "${servers_json}"
  assert_success
  run jq -e 'has("other-399")' <<< "${servers_json}"
  assert_success
}

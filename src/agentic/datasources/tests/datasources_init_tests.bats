#!/usr/bin/env bats
# =============================================================================
# src/agentic/datasources/tests/datasources_init_tests.bats
# init.sh: per-project wiring.
#
# A manifest for each selected datasource, pruning for the deselected, the
# harness gate, and the list-membership helper the wiring relies on.
#
# Split from datasources_tests.bats: bats parallelises across files only, so the
# themes are separate files. Fixtures come from datasources_test_helper.
#
# Run from project root:
#   bats src/agentic/datasources/tests/datasources_init_tests.bats
# =============================================================================

load 'datasources_test_helper'

# ── init.sh ──────────────────────────────────────────────────────────────────

@test "init: a selected datasource gets a harness manifest" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "datasources-mariadb-dev"

  run cat "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"url": "http://127.0.0.1:18510/mcp/mariadb-dev"'
}

@test "init: the opencode manifest ships disabled" {
  # The datasource gateways are optional per project, so the opencode manifest
  # opts the server out by default — one flag turns it on without a reinit.
  _catalogue '{}'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"enabled": false'
  [ ! -e "${PROJECT_DIR}/.claude/datasources-mariadb-dev.mcp.json" ]
}

@test "init: the claude manifest stays wired" {
  # .mcp.json has no per-server on/off, so `wire_disabled` is not translated:
  # the server is wired, without a key the client would reject.
  _catalogue '{}'
  _project_config '["mariadb-dev"]' '' 'claudecode'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run jq -r '.mcpServers."datasources-mariadb-dev" | has("enabled")' \
    "${PROJECT_DIR}/.claude/datasources-mariadb-dev.mcp.json"
  assert_output "false"
  run jq -r '.mcpServers."datasources-mariadb-dev".url' \
    "${PROJECT_DIR}/.claude/datasources-mariadb-dev.mcp.json"
  assert_output "http://127.0.0.1:18510/mcp/mariadb-dev"
  [ ! -e "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json" ]
}

@test "init: the opencode manifest carries the 60s MCP timeout by default" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"timeout": 60000'
}

@test "init: a global config without a datasources key still writes the default timeout" {
  # The catalogue key is optional, so the reader yields nothing. That must not
  # reach the renderer as an empty stdin, which it rejects as "no catalogue".
  printf '{}\n' >"${SANDBOX_DIR}/.devbot.global.jsonc"
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"timeout": 60000'
}

@test "init: a datasource's mcp_timeout_ms overrides the default" {
  _catalogue '{ "mariadb-dev": { "type": "mysql", "env": {}, "mcp_timeout_ms": 300000 } }'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json"
  assert_success
  assert_output --partial '"timeout": 300000'
}

@test "init: the claude manifest carries no timeout" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]' '' 'claudecode'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.claude/datasources-mariadb-dev.mcp.json"
  assert_success
  refute_output --partial '"timeout"'
}

@test "init: an unusable mcp_timeout_ms fails loudly" {
  _catalogue '{ "mariadb-dev": { "type": "mysql", "env": {}, "mcp_timeout_ms": "300000" } }'
  _project_config '["mariadb-dev"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_failure
  assert_output --partial "mcp_timeout_ms"
}

@test "init: selecting nothing prunes the manifest" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  _project_config '[]'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "none selected"
  assert_output --partial "retired datasources-mariadb-dev"

  [ ! -e "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json" ]
}

@test "init: deselecting also unregisters the harness key" {
  # The harness merges manifests append-only, so removing the manifest alone
  # left a live server for a datasource the project had dropped.
  _catalogue '{}'
  _project_config '["mariadb-dev"]'
  # An earlier init is what records the group as dev-bot-owned; only then may
  # the key be removed on the way out.
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  cat > "${PROJECT_DIR}/opencode.jsonc" <<'JSON'
{
  "mcp": {
    "datasources-mariadb-dev": { "type": "remote", "url": "http://127.0.0.1:18510/mcp/mariadb-dev" },
    "mdctx": { "type": "remote", "url": "http://127.0.0.1:18501/mcp" }
  }
}
JSON

  _project_config '[]'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/opencode.jsonc"
  refute_output --partial "datasources-mariadb-dev"
  # A server this module does not own must be left alone.
  assert_output --partial "mdctx"
}

@test "init: the manifest URL follows a DATASOURCES_PORT from .env" {
  # The manifest must point where the gateway will listen. bin/init.sh does not
  # read the repo .env itself, so init has to load it before building the URL —
  # otherwise a configured port leaves every manifest on the default one.
  _sqlite_catalogue
  _project_config '["scratch"]'
  printf 'DATASOURCES_PORT=18600\n' > "${SANDBOX_DIR}/.env"

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-scratch.mcp.json"
  assert_output --partial "127.0.0.1:18600/mcp/scratch"
}

@test "init: a selection absent from the catalogue is warned about" {
  _catalogue '{}'
  _project_config '["typo-db"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success
  assert_output --partial "not declared"
}

@test "init: nothing is written for the unselected harness" {
  _catalogue '{}'
  _project_config '["mariadb-dev"]' '' 'claudecode'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  [ ! -e "${PROJECT_DIR}/.opencode/datasources-mariadb-dev.mcp.json" ]
}

@test "init: a sidecar datasource points at its own listener, not the gateway" {
  # A sidecar is served by its own http container, so its manifest URL carries
  # the port render_compose.py allocated — the same allocation the service uses.
  _catalogue '{"hotels": {"type": "mysql", "env": {}}, "search": {"type": "opensearch", "env": {}}}'
  _project_config '["hotels", "search"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-hotels.mcp.json"
  assert_success
  assert_output --partial '"url": "http://127.0.0.1:18510/mcp/hotels"'

  run cat "${PROJECT_DIR}/.opencode/datasources-search.mcp.json"
  assert_success
  assert_output --partial '"url": "http://127.0.0.1:18520/mcp"'

  _project_config '["hotels", "search"]' '' 'claudecode'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.claude/datasources-search.mcp.json"
  assert_success
  assert_output --partial '"url": "http://127.0.0.1:18520/mcp"'
}

@test "init: deselecting a sidecar prunes its manifest" {
  _catalogue '{"search": {"type": "opensearch", "env": {}}}'
  _project_config '["search"]'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success
  [ -f "${PROJECT_DIR}/.opencode/datasources-search.mcp.json" ]

  _project_config '[]'
  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  [ ! -e "${PROJECT_DIR}/.opencode/datasources-search.mcp.json" ]
}

@test "init: an undemanded sidecar does not shift the demanded one's port" {
  # `alpha` sorts before `search`, so an unfiltered port map would give search
  # 18521 — a URL that does not match the compose, which renders only search.
  _catalogue '{"alpha": {"type": "opensearch", "env": {}}, "search": {"type": "opensearch", "env": {}}}'
  _project_config '["search"]'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT_DIR}"
  assert_success

  run cat "${PROJECT_DIR}/.opencode/datasources-search.mcp.json"
  assert_output --partial '"url": "http://127.0.0.1:18520/mcp"'
}

# ── list membership (pipefail / SIGPIPE) ─────────────────────────────────────

@test "list membership: an early entry in a list past the pipe buffer is found" {
  # The trap this pins: `printf … | grep -q` exits on the match and the writer
  # takes SIGPIPE on its next write, so `pipefail` reports the pipeline failed
  # for a name that IS present — intermittently for short lists, and
  # deterministically for the first entry once the list passes the 64 KiB pipe
  # buffer. That is how the reload flagged a served sidecar as unpublishable.
  local script="${SANDBOX_DIR}/list-membership.sh"
  cat > "${script}" <<SH
set -euo pipefail
source "${MODULE_DIR}/functions.sh"
haystack="\$(seq 1 8000 | sed 's/^/sidecar-/')"
words="\$(tr '\n' ' ' <<< "\${haystack}")"
if printf '%s\n' "\${haystack}" | grep -Fqx sidecar-1; then echo "PIPELINE-OK"; else echo "PIPELINE-FAILED"; fi
_list_has sidecar-1 "\${haystack}" && echo "LINE-FOUND"
_list_has sidecar-99999 "\${haystack}" || echo "LINE-ABSENT"
_list_has_word sidecar-1 "\${words}" && echo "WORD-FOUND"
SH

  run bash "${script}"

  assert_success
  # The fixture must reproduce the trap, or the assertions below pass vacuously.
  assert_output --partial "PIPELINE-FAILED"
  assert_output --partial "LINE-FOUND"
  assert_output --partial "LINE-ABSENT"
  assert_output --partial "WORD-FOUND"
}


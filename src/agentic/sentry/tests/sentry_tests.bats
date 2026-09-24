#!/usr/bin/env bats
# =============================================================================
# src/agentic/sentry/tests/sentry_tests.bats
# Tests for the sentry module (error-monitoring MCP server + agent skills).
#
# Unlike signoz, Sentry's MCP server is not a local service: it is the hosted
# Cloudflare endpoint at https://mcp.sentry.dev/mcp. There is therefore no
# docker gateway, no port allocation and no up.sh readiness probe — this module
# ships the canonical manifest, the fetched agent skills and one command.
#
# Auth is a token header, not OAuth: `Sentry-Bearer {env:SENTRY_ACCESS_TOKEN}`
# (embedded {env:VAR} is a header-only affordance of the canonical manifest).
# `oauth: false` stops opencode racing the token with OAuth discovery.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
}

# ── MCP manifest ─────────────────────────────────────────────────────────────

@test "canonical mcp.json declares sentry as a remote endpoint with a token header" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.json'))
m = d['mcp']['sentry']
assert m['type'] == 'http', m
assert m['url'] == 'https://mcp.sentry.dev/mcp', m
# A token header is the auth path, so OAuth discovery must stay off.
assert m['oauth'] is False, m
# Wired but not started: opencode honors the flag, claudecode drops it.
assert m['enabled'] is False, m
assert m['headers']['Authorization'] == 'Sentry-Bearer {env:SENTRY_ACCESS_TOKEN}', m
assert 'command' not in m, m
assert 'env' not in m, m
print('MCP:OK')
"
  assert_success
  grep -qF 'MCP:OK' <<< "$output" || fail "canonical mcp.json shape wrong"
}

@test "MCP integration is a single canonical mcp.json, not a plugin" {
  [ -f "${MODULE_DIR}/mcp.json" ]
  [ ! -f "${MODULE_DIR}/mcp.opencode.json" ]
  [ ! -f "${MODULE_DIR}/mcp.claudecode.json" ]
  [ ! -f "${MODULE_DIR}/plugin.opencode.json" ]
}

@test "the manifest translates for both harnesses (opencode remote, claudecode http)" {
  local tool="${PROJECT_ROOT}/src/_shared/mcp_translate.py"

  run python3 "$tool" "${MODULE_DIR}/mcp.json" opencode
  assert_success
  assert_output --partial '"type": "remote"'
  assert_output --partial '"https://mcp.sentry.dev/mcp"'
  # opencode interpolates {env:VAR} natively — the token stays unresolved.
  assert_output --partial '"Authorization": "Sentry-Bearer {env:SENTRY_ACCESS_TOKEN}"'

  run python3 "$tool" "${MODULE_DIR}/mcp.json" claudecode
  assert_success
  assert_output --partial '"type": "http"'
  # Claude Code's native spelling: never a registration-resolved secret.
  assert_output --partial '"Authorization": "Sentry-Bearer ${SENTRY_ACCESS_TOKEN}"'
  refute_output --partial '{env:SENTRY_ACCESS_TOKEN}'
}

# ── No local service: no gateway, no port, no readiness probe ────────────────

@test "there is no docker-compose gateway (Sentry's MCP is not a local service)" {
  [ ! -f "${MODULE_DIR}/docker-compose.yml" ]
  [ ! -f "${MODULE_DIR}/up.sh" ]
}

@test "no sentry script references a docker gateway or a per-machine binary" {
  # Mirrors signoz's regression guard: this module must stay a pure
  # manifest + skills + command module.
  run grep -rn 'docker-compose\|signoz-mcp-server\|releases/latest/download' "${MODULE_DIR}" --include='*.sh'
  assert_failure
}

# ── Lifecycle scripts ────────────────────────────────────────────────────────

@test "install/update/pre/init scripts exist and are executable" {
  for s in install.sh update.sh pre.sh init.sh; do
    [ -f "${MODULE_DIR}/$s" ]
    [ -x "${MODULE_DIR}/$s" ]
  done
}

@test "functions.sh sources the shared library" {
  run grep -q '_shared/functions.sh' "${MODULE_DIR}/functions.sh"
  assert_success
}

# ── Skills fetch ─────────────────────────────────────────────────────────────

@test "functions.sh fetches skills from the current Sentry agent-plugin source" {
  # getsentry/agent-plugin is the official, non-deprecated Agent Plugins
  # distribution that sentry-for-ai builds and publishes; the older
  # sentry-agent-skills repo is superseded. Pin the fetch TARGET — not the
  # file's prose, where naming the old repo is documentation, not a bug.
  run grep -qE '^_SENTRY_SKILLS_SOURCE="getsentry/agent-plugin"$' "${MODULE_DIR}/functions.sh"
  assert_success
  run grep -qF 'skills add --yes "${_SENTRY_SKILLS_SOURCE}"' "${MODULE_DIR}/functions.sh"
  assert_success
}

@test "update.sh executes cleanly with a sandboxed DEV_BOT_ROOT" {
  sandbox="$(mktemp -d)"
  mockbin="${sandbox}/mockbin"
  mkdir -p "${mockbin}" "${sandbox}/storage/sentry/skills"

  # Stub npx so the skills step succeeds without touching the network, laying
  # down the .agents/skills layout the real CLI produces.
  cat > "${mockbin}/npx" <<'MOCK'
#!/usr/bin/env bash
mkdir -p .agents/skills/sentry-get-started
: > .agents/skills/sentry-get-started/SKILL.md
exit 0
MOCK
  chmod +x "${mockbin}/npx"

  run env DEV_BOT_ROOT="${sandbox}" PATH="${mockbin}:${PATH}" \
    bash "${MODULE_DIR}/update.sh"

  assert_success
  refute_output --partial "command not found"
  [ -f "${sandbox}/storage/sentry/skills/sentry-get-started/SKILL.md" ]

  rm -rf "${sandbox}"
}

@test "install.sh installs the skills when they are missing" {
  sandbox="$(mktemp -d)"
  mockbin="${sandbox}/mockbin"
  mkdir -p "${mockbin}"

  # Lays down the .agents/skills layout in the temp CWD the real helper `cd`s
  # into — the exact dir _sentry_install_skills then copies from.
  cat > "${mockbin}/npx" <<'MOCK'
#!/usr/bin/env bash
mkdir -p .agents/skills/sentry-instrument
: > .agents/skills/sentry-instrument/SKILL.md
exit 0
MOCK
  chmod +x "${mockbin}/npx"

  run env DEV_BOT_ROOT="${sandbox}" PATH="${mockbin}:${PATH}" \
    bash "${MODULE_DIR}/install.sh"

  assert_success
  [ -f "${sandbox}/storage/sentry/skills/sentry-instrument/SKILL.md" ]
  rm -rf "${sandbox}"
}

@test "install.sh is idempotent — a second run skips the fetch" {
  sandbox="$(mktemp -d)"
  mockbin="${sandbox}/mockbin"
  mkdir -p "${mockbin}" "${sandbox}/storage/sentry/skills/sentry-instrument"
  : > "${sandbox}/storage/sentry/skills/sentry-instrument/SKILL.md"
  # Any npx call here would be a bug: the skills are already present.
  cat > "${mockbin}/npx" <<'MOCK'
#!/usr/bin/env bash
echo "UNEXPECTED npx invocation" >&2
exit 1
MOCK
  chmod +x "${mockbin}/npx"

  run env DEV_BOT_ROOT="${sandbox}" PATH="${mockbin}:${PATH}" \
    bash "${MODULE_DIR}/install.sh"

  assert_success
  refute_output --partial "UNEXPECTED"
  rm -rf "${sandbox}"
}

# ── Per-project init ─────────────────────────────────────────────────────────

@test "init.sh symlinks the fetched skills into .opencode/skills/sentry" {
  sandbox="$(mktemp -d)"
  project="${sandbox}/project"
  mkdir -p "${sandbox}/storage/sentry/skills/sentry-instrument" \
    "${project}/.opencode/skills"
  : > "${sandbox}/storage/sentry/skills/sentry-instrument/SKILL.md"
  echo '{}' > "${sandbox}/.devbot.global.jsonc"
  echo '{}' > "${project}/.devbot.project.jsonc"

  run env DEV_BOT_ROOT="${sandbox}" bash "${MODULE_DIR}/init.sh" "${project}"

  assert_success
  [ -L "${project}/.opencode/skills/sentry" ]
  [ "$(readlink "${project}/.opencode/skills/sentry")" = "${sandbox}/storage/sentry/skills" ]
  rm -rf "${sandbox}"
}

@test "init.sh warns instead of failing when the skills are not installed yet" {
  sandbox="$(mktemp -d)"
  project="${sandbox}/project"
  mkdir -p "${sandbox}" "${project}"
  echo '{}' > "${sandbox}/.devbot.global.jsonc"
  echo '{}' > "${project}/.devbot.project.jsonc"

  run env DEV_BOT_ROOT="${sandbox}" bash "${MODULE_DIR}/init.sh" "${project}"

  assert_success
  [ ! -e "${project}/.opencode/skills/sentry" ]
  rm -rf "${sandbox}"
}

# ── Command ──────────────────────────────────────────────────────────────────

@test "the module ships the find-sentry-issues command with valid frontmatter" {
  [ -f "${MODULE_DIR}/commands/find-sentry-issues.md" ]
  run grep -q '^name: devbot:find-sentry-issues' "${MODULE_DIR}/commands/find-sentry-issues.md"
  assert_success
}

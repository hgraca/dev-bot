#!/usr/bin/env bats
# =============================================================================
# bin/tests/seed_claude_config_tests.bats
# Tests for tests/test-project/seed-claude-config.py.
#
# The cc fixture container runs the project at /app, but Claude Code keys trust
# and onboarding by absolute project path in ~/.claude.json — a sibling of the
# host-mounted ~/.claude/ dir, and so not shared. Every fresh container
# therefore re-asked "Do you trust the files in this folder?". The seeder marks
# /app trusted (seeded from a read-only host copy) without writing the host file.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  TOOL="${REPO_ROOT}/tests/test-project/seed-claude-config.py"

  SANDBOX="$(mktemp -d)"
  mkdir -p "${SANDBOX}/home"
}

teardown() {
  rm -rf "$SANDBOX" 2>/dev/null || true
}

@test "seed: trusts /app, completes onboarding, drops stray MCP servers" {
  cat > "${SANDBOX}/host.json" <<'JSON'
{
  "hasCompletedOnboarding": false,
  "mcpServers": { "phpstorm": { "url": "http://127.0.0.1:64442/stream" } },
  "projects": { "/other": { "hasTrustDialogAccepted": true } }
}
JSON
  run env HOME="${SANDBOX}/home" python3 "$TOOL" /app "${SANDBOX}/host.json"
  assert_success

  # Trust/onboarding carry over; user-scope MCP servers (a host-only phpstorm
  # registration) do not — the container sees only /app's .mcp.json.
  run env HOME="${SANDBOX}/home" python3 -c \
    "import json,os; d=json.load(open(os.path.join(os.environ['HOME'],'.claude.json'))); print(d['hasCompletedOnboarding'], d['projects']['/app']['hasTrustDialogAccepted'], d['projects']['/other']['hasTrustDialogAccepted'], 'mcpServers' in d, 'phpstorm' in json.dumps(d))"
  assert_output "True True True False False"

  # The host config is only read.
  run grep -q 'phpstorm' "${SANDBOX}/host.json"
  assert_success
}

@test "seed: works with no host config" {
  run env HOME="${SANDBOX}/home" python3 "$TOOL" /app ""
  assert_success

  run env HOME="${SANDBOX}/home" python3 -c \
    "import json,os; d=json.load(open(os.path.join(os.environ['HOME'],'.claude.json'))); print(d['hasCompletedOnboarding'], d['projects']['/app']['hasTrustDialogAccepted'])"
  assert_output "True True"
}

@test "seed: tolerates a malformed host config" {
  printf 'not json' > "${SANDBOX}/host.json"
  run env HOME="${SANDBOX}/home" python3 "$TOOL" /app "${SANDBOX}/host.json"
  assert_success

  run env HOME="${SANDBOX}/home" python3 -c \
    "import json,os; d=json.load(open(os.path.join(os.environ['HOME'],'.claude.json'))); print(d['projects']['/app']['hasTrustDialogAccepted'])"
  assert_output "True"
}

@test "seed: the cc launcher mounts the host file read-only and the inner script seeds it" {
  LAUNCHER="${REPO_ROOT}/tests/test-project/test-cc.sh"
  INNER="${REPO_ROOT}/tests/test-project/test-cc-inner.sh"
  run grep -qF '${HOME}/.claude.json:/tmp/host-claude.json:ro' "$LAUNCHER"
  assert_success
  run grep -qF 'seed-claude-config.py /app /tmp/host-claude.json' "$INNER"
  assert_success
}

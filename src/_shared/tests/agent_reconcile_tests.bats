#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/agent_reconcile_tests.bats
# Tests that reconcile_agent_names.py repairs a config seeded before the agents
# were renamed: the harness stores an agent by name, and the dist template is
# seed-once, so an upgraded project would otherwise keep `DevBot` — a name no
# agent registers — and lose its per-agent model overrides.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  RECONCILE="$ROOT/src/_shared/reconcile_agent_names.py"

  TMP="$(mktemp -d)"
}

teardown() {
  rm -r "${TMP}"
}

@test "opencode: renames default_agent and the agent map keys" {
  cat > "${TMP}/opencode.jsonc" <<'EOF'
{
  "default_agent": "DevBot",
  "agent": {
    "DevBot": { "model": "a", "variant": "high" },
    "Architect": { "model": "b" },
    "custom": { "disable": true }
  }
}
EOF

  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" opencode

  assert_success
  assert_output --partial "DevBot -> devbot"
  assert_output --partial "Architect -> architect"
  # The result must still parse: the rename keeps each key's colon.
  run python3 -c "import json; json.load(open('${TMP}/opencode.jsonc'))"
  assert_success
  run grep -c '"DevBot"\|"Architect"' "${TMP}/opencode.jsonc"
  assert_output "0"
  run grep -c '"devbot": {\|"architect": {' "${TMP}/opencode.jsonc"
  assert_output "2"
  run grep -c '"custom": { "disable": true }' "${TMP}/opencode.jsonc"
  assert_output "1"
}

@test "opencode: handles a compact single-line config" {
  printf '{"agent":{"DevBot":{"model":"a"}},"default_agent":"DevBot"}\n' > "${TMP}/opencode.jsonc"

  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" opencode

  assert_success
  assert_output --partial "DevBot -> devbot"
  run python3 -c "
import json
d = json.load(open('${TMP}/opencode.jsonc'))
assert d == {'agent': {'devbot': {'model': 'a'}}, 'default_agent': 'devbot'}, d
"
  assert_success
}

@test "opencode: leaves keys of a sibling top-level object alone" {
  cat > "${TMP}/opencode.jsonc" <<'EOF'
{
  "agent": {
    "Critic": { "model": "c" }
  },
  "permission": {
    "Architect": { "allow": true }
  }
}
EOF

  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" opencode

  assert_success
  run grep -c '"critic": {' "${TMP}/opencode.jsonc"
  assert_output "1"
  run grep -c '"Architect": {' "${TMP}/opencode.jsonc"
  assert_output "1"
}

@test "opencode: leaves a key nested inside an agent entry alone" {
  cat > "${TMP}/opencode.jsonc" <<'EOF'
{
  "agent": {
    "custom": { "Architect": { "x": 1 } },
    "Critic": { "model": "c" }
  }
}
EOF

  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" opencode

  assert_success
  run grep -c '"critic": {' "${TMP}/opencode.jsonc"
  assert_output "1"
  run grep -c '"Architect": {' "${TMP}/opencode.jsonc"
  assert_output "1"
}

@test "opencode: only the root default_agent is rewritten" {
  cat > "${TMP}/opencode.jsonc" <<'EOF'
{
  "default_agent": "DevBot",
  "provider": {
    "default_agent": "DevBot"
  }
}
EOF

  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" opencode

  assert_success
  run grep -c '"default_agent": "devbot"' "${TMP}/opencode.jsonc"
  assert_output "1"
  run grep -c '"default_agent": "DevBot"' "${TMP}/opencode.jsonc"
  assert_output "1"
}

@test "opencode: keeps the legacy entry when its lowercase twin already exists" {
  cat > "${TMP}/opencode.jsonc" <<'EOF'
{
  "agent": {
    "architect": { "model": "new" },
    "Architect": { "model": "old" }
  }
}
EOF

  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" opencode

  assert_success
  assert_output --partial "WARN"
  # No duplicate key is written, and both original entries survive.
  run python3 -c "
import json
d = json.load(open('${TMP}/opencode.jsonc'))
assert d == {'agent': {'architect': {'model': 'new'}, 'Architect': {'model': 'old'}}}, d
"
  assert_success
}

@test "opencode: leaves nested keys and same-named values alone" {
  cat > "${TMP}/opencode.jsonc" <<'EOF'
{
  "default_agent": "DevBot",
  "provider": {
    "litellm": {
      "models": {
        "Architect": { "name": "Architect" }
      }
    }
  }
}
EOF

  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" opencode

  assert_success
  assert_output --partial "DevBot -> devbot"
  run grep -c '"Architect": { "name": "Architect" }' "${TMP}/opencode.jsonc"
  assert_output "1"
}

@test "opencode: an empty agent map is left alone" {
  printf '{\n  "agent": {},\n  "default_agent": "DevBot"\n}\n' > "${TMP}/opencode.jsonc"

  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" opencode

  assert_success
  run grep -c '"agent": {}' "${TMP}/opencode.jsonc"
  assert_output "1"
  run grep -c '"default_agent": "devbot"' "${TMP}/opencode.jsonc"
  assert_output "1"
}

@test "claudecode: renames the settings agent value" {
  printf '{\n  "agent": "DevBot",\n  "hooks": {}\n}\n' > "${TMP}/settings.json"

  run python3 "${RECONCILE}" "${TMP}/settings.json" claudecode

  assert_success
  assert_output --partial "DevBot -> devbot"
  run grep -c '"agent": "devbot"' "${TMP}/settings.json"
  assert_output "1"
  run grep -c '"hooks": {}' "${TMP}/settings.json"
  assert_output "1"
}

@test "claudecode: leaves a nested agent setting alone" {
  cat > "${TMP}/settings.json" <<'EOF'
{
  "agent": "DevBot",
  "hooks": { "agent": "DevBot" }
}
EOF

  run python3 "${RECONCILE}" "${TMP}/settings.json" claudecode

  assert_success
  run grep -c '"agent": "devbot"' "${TMP}/settings.json"
  assert_output "1"
  run grep -c '"agent": "DevBot"' "${TMP}/settings.json"
  assert_output "1"
}

@test "is idempotent" {
  printf '{\n  "agent": {\n    "Reviewer": { "model": "r" }\n  }\n}\n' > "${TMP}/opencode.jsonc"

  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" opencode
  assert_success
  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" opencode
  assert_success
  assert_output ""
}

@test "the harness inits keep the reconciler's warning on stderr" {
  # A discarded stderr hides the collision warning: the user keeps the legacy
  # override without ever learning why it stopped applying.
  run grep -n 'reconcile_agent_names.py' \
    "${ROOT}/src/harnesses/opencode/init.sh" \
    "${ROOT}/src/harnesses/claudecode/init.sh"
  assert_success
  refute_output --partial "2>/dev/null"
}

@test "an absent config is a no-op" {
  run python3 "${RECONCILE}" "${TMP}/missing.jsonc" opencode
  assert_success
  assert_output ""
}

@test "rejects an unknown mode" {
  printf '{}\n' > "${TMP}/opencode.jsonc"
  run python3 "${RECONCILE}" "${TMP}/opencode.jsonc" nope
  assert_failure 2
}

#!/usr/bin/env bats
# Modules declare, the selected harness applies.
#
# A module publishes canonical definitions to <devbot_dir>/mcp-runtime and never
# names a harness; _devbot_apply_runtime_mcps translates them for the selected
# harness and retires the manifests (and insert-only opencode keys) it wrote
# earlier.

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  export DEV_BOT_ROOT="$REPO"
  PROJECT="$(mktemp -d)"
  # The disabled set is read from the global config, and both the developer's
  # copy and CI's seeded copy disable modules — which would skip these groups.
  # An empty one keeps the suite about the pipeline, not about a config.
  GLOBAL_CFG="$(mktemp)"
  printf '{}\n' > "$GLOBAL_CFG"
  export DEV_BOT_GLOBAL_CONFIG="$GLOBAL_CFG"
  source "$REPO/src/_shared/functions.sh"
}

teardown() {
  rm -r "$PROJECT" "$GLOBAL_CFG"
}

set_harness() {
  printf '{"harness": "%s", "devbot_dir": ".agents"}\n' "$1" > "$PROJECT/.devbot.project.jsonc"
}

publish_demo() {
  local def
  def=$(jq -nc '{"aws-demo": {type: "stdio", command: ["bash", "-c", "run {harness-dir}/l.sh"], wire_disabled: true}}')
  _devbot_publish_runtime_mcp "$PROJECT" "aws-demo" "$def"
}

@test "opencode gets its own shape and a disabled start flag" {
  set_harness opencode
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"
  assert [ -f "$PROJECT/.opencode/aws-demo.mcp.json" ]
  run jq -r '."aws-demo".command[2]' "$PROJECT/.opencode/aws-demo.mcp.json"
  assert_output "run .opencode/l.sh"
  run jq -r '."aws-demo".enabled' "$PROJECT/.opencode/aws-demo.mcp.json"
  assert_output "false"
}

@test "claudecode gets the envelope and stays wired" {
  set_harness claudecode
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"
  assert [ -f "$PROJECT/.claude/aws-demo.mcp.json" ]
  run jq -r '.mcpServers."aws-demo".args[1]' "$PROJECT/.claude/aws-demo.mcp.json"
  assert_output "run .claude/l.sh"
  run jq -r '.mcpServers."aws-demo".enabled // "wired"' "$PROJECT/.claude/aws-demo.mcp.json"
  assert_output "wired"
}

@test "a retired group takes its manifest and its opencode key with it" {
  set_harness opencode
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"
  # remove_mcp_key.py is line-oriented: it needs the formatted shape a real
  # opencode.jsonc has, and silently no-ops on compact JSON.
  printf '{\n  "mcp": {\n    "aws-demo": {\n      "type": "local"\n    }\n  }\n}\n' > "$PROJECT/opencode.jsonc"
  _devbot_prune_runtime_mcp "$PROJECT" "aws-"
  _devbot_apply_runtime_mcps "$PROJECT"
  assert [ ! -f "$PROJECT/.opencode/aws-demo.mcp.json" ]
  run jq -r '.mcp | length' "$PROJECT/opencode.jsonc"
  assert_output "0"
}

@test "a manifest dev-bot never generated is left alone" {
  set_harness opencode
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"
  mkdir -p "$PROJECT/.opencode"
  printf '{"hand-written": {"type": "local", "command": ["true"]}}\n' > "$PROJECT/.opencode/hand-written.mcp.json"
  _devbot_apply_runtime_mcps "$PROJECT"
  assert [ -f "$PROJECT/.opencode/hand-written.mcp.json" ]
}

@test "a group whose owning module is disabled is not wired" {
  printf '{"harness": "opencode", "devbot_dir": ".agents", "modules": {"datasources": false}}\n' \
    > "$PROJECT/.devbot.project.jsonc"
  _devbot_publish_runtime_mcp "$PROJECT" "datasources-demo" \
    "$(jq -nc '{"datasources-demo": {type: "http", url: "http://127.0.0.1:1/mcp"}}')"
  _devbot_apply_runtime_mcps "$PROJECT"
  # The module's init never ran, so its canonical file can only be a leftover.
  assert [ ! -e "$PROJECT/.opencode/datasources-demo.mcp.json" ]
}

@test "a canonical manifest that cannot be translated keeps the last good one" {
  set_harness opencode
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"
  assert [ -f "$PROJECT/.opencode/aws-demo.mcp.json" ]

  # An unknown key is a schema mistake the translator rejects. Publish refuses
  # it, so plant it directly — a hand-edited file must not cost a working
  # server either.
  printf '{"mcp": {"aws-demo": {"type": "stdio", "command": ["true"], "bogus": 1}}}\n' \
    > "$PROJECT/.agents/mcp-runtime/aws-demo.json"
  run _devbot_apply_runtime_mcps "$PROJECT"
  assert_success
  run jq -r '."aws-demo".command[2]' "$PROJECT/.opencode/aws-demo.mcp.json"
  assert_output "run .opencode/l.sh"
}

@test "a group with every server disabled leaves no claudecode manifest" {
  set_harness claudecode
  _devbot_publish_runtime_mcp "$PROJECT" "sentry" \
    "$(jq -nc '{"sentry": {type: "http", url: "https://x/mcp"}}')"
  _devbot_apply_runtime_mcps "$PROJECT"
  assert [ -f "$PROJECT/.claude/sentry.mcp.json" ]

  # Flipped to disabled: .mcp.json has no per-server on/off, so nothing is
  # wired — an empty mcpServers file would only be noise.
  _devbot_publish_runtime_mcp "$PROJECT" "sentry" \
    "$(jq -nc '{"sentry": {type: "http", url: "https://x/mcp", enabled: false}}')"
  _devbot_apply_runtime_mcps "$PROJECT"
  assert [ ! -e "$PROJECT/.claude/sentry.mcp.json" ]
}

@test "publishing an invalid entry fails before anything is written" {
  run _devbot_publish_runtime_mcp "$PROJECT" "bad" \
    '{"bad": {"type": "stdio", "command": ["true"], "bogus": 1}}'
  assert_failure
  assert_output --partial "invalid canonical manifest"
  assert [ ! -e "$PROJECT/.agents/mcp-runtime/bad.json" ]
}

@test "a same-named manifest dev-bot did not write is not replaced" {
  set_harness opencode
  mkdir -p "$PROJECT/.opencode"
  printf '{"aws-demo": {"type": "local", "command": ["mine"]}}\n' \
    > "$PROJECT/.opencode/aws-demo.mcp.json"
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"
  run jq -r '."aws-demo".command[0]' "$PROJECT/.opencode/aws-demo.mcp.json"
  assert_output "mine"
}

@test "a user manifest created after a retirement is not deleted" {
  set_harness opencode
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"
  _devbot_prune_runtime_mcp "$PROJECT" "aws-"
  _devbot_apply_runtime_mcps "$PROJECT"
  assert [ ! -e "$PROJECT/.opencode/aws-demo.mcp.json" ]

  # The record is gone, so the name is free for the user to take.
  printf '{"aws-demo": {"type": "local", "command": ["mine"]}}\n' \
    > "$PROJECT/.opencode/aws-demo.mcp.json"
  _devbot_apply_runtime_mcps "$PROJECT"
  run jq -r '."aws-demo".command[0]' "$PROJECT/.opencode/aws-demo.mcp.json"
  assert_output "mine"
}

@test "a manifest changed since dev-bot wrote it is not retired" {
  set_harness opencode
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"
  printf '{"aws-demo": {"type": "local", "command": ["hand-edited"]}}\n' \
    > "$PROJECT/.opencode/aws-demo.mcp.json"

  _devbot_prune_runtime_mcp "$PROJECT" "aws-"
  _devbot_apply_runtime_mcps "$PROJECT"

  run jq -r '."aws-demo".command[0]' "$PROJECT/.opencode/aws-demo.mcp.json"
  assert_output "hand-edited"
}

@test "a manifest edited after dev-bot wrote it is not overwritten" {
  set_harness opencode
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"
  printf '{"aws-demo": {"type": "local", "command": ["mine"]}}\n' \
    > "$PROJECT/.opencode/aws-demo.mcp.json"

  _devbot_apply_runtime_mcps "$PROJECT"

  run jq -r '."aws-demo".command[0]' "$PROJECT/.opencode/aws-demo.mcp.json"
  assert_output "mine"
}

@test "ownership survives a v1 to v2 selection change" {
  # Both generations write .opencode, so the record must belong to the
  # directory: keyed by harness name, the v1 reinit saw every manifest as
  # foreign and refused to touch any of them.
  set_harness opencode
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"

  set_harness opencode-v2
  run _devbot_apply_runtime_mcps "$PROJECT"
  refute_output --partial "not dev-bot's"

  set_harness opencode
  run _devbot_apply_runtime_mcps "$PROJECT"
  refute_output --partial "not dev-bot's"
  refute_output --partial "changed since dev-bot wrote it"
  assert [ ! -e "$PROJECT/.agents/mcp-runtime/.owned.opencode-v2" ]
}

@test "a manifest identical to ours is adopted when the record is lost" {
  set_harness opencode
  publish_demo
  _devbot_apply_runtime_mcps "$PROJECT"
  rm -f "$PROJECT/.agents/mcp-runtime/.owned.opencode"

  run _devbot_apply_runtime_mcps "$PROJECT"
  refute_output --partial "not dev-bot's"
  run grep -c "aws-demo" "$PROJECT/.agents/mcp-runtime/.owned.opencode"
  assert_output "1"
}

@test "a symlinked manifest is neither adopted nor written through" {
  set_harness opencode
  local outside
  outside="$(mktemp)"
  printf '{"aws-demo": {"type": "local", "command": ["outside"]}}\n' > "${outside}"
  mkdir -p "$PROJECT/.opencode"
  ln -sfn "${outside}" "$PROJECT/.opencode/aws-demo.mcp.json"

  publish_demo
  run _devbot_apply_runtime_mcps "$PROJECT"
  assert_output --partial "is a symlink"

  # The link survives and its referent is untouched.
  assert [ -L "$PROJECT/.opencode/aws-demo.mcp.json" ]
  run cat "${outside}"
  assert_output --partial "outside"
}

@test "a symlinked manifest is not retired" {
  set_harness opencode
  local outside
  outside="$(mktemp)"
  printf '{"aws-demo": {"type": "local", "command": ["outside"]}}\n' > "${outside}"
  mkdir -p "$PROJECT/.opencode"
  ln -sfn "${outside}" "$PROJECT/.opencode/aws-demo.mcp.json"
  mkdir -p "$PROJECT/.agents/mcp-runtime"
  printf 'aws-demo\t%s\n' "$(_devbot_file_fingerprint "${outside}")" \
    > "$PROJECT/.agents/mcp-runtime/.owned.opencode"

  _devbot_prune_runtime_mcp "$PROJECT" "aws-"
  run _devbot_apply_runtime_mcps "$PROJECT"

  assert [ -L "$PROJECT/.opencode/aws-demo.mcp.json" ]
  run cat "${outside}"
  assert_output --partial "outside"
}

@test "a group recorded only by the legacy harness is still retired" {
  # The v1 handoff can leave the destination record populated while the
  # name-keyed v2 record holds a group of its own. Dropping that file instead
  # of merging it would leave the stale manifest unretirable.
  set_harness opencode-v2
  mkdir -p "$PROJECT/.agents/mcp-runtime" "$PROJECT/.opencode"
  printf '{"sentry": {"type": "remote", "url": "https://x"}}\n' \
    > "$PROJECT/.opencode/sentry.mcp.json"
  printf 'aws-demo\t111-1\n' > "$PROJECT/.agents/mcp-runtime/.owned.opencode"
  printf 'sentry\t%s\n' "$(cksum "$PROJECT/.opencode/sentry.mcp.json" | awk '{print $1"-"$2}')" \
    > "$PROJECT/.agents/mcp-runtime/.owned.opencode-v2"

  _devbot_apply_runtime_mcps "$PROJECT"

  assert [ ! -e "$PROJECT/.opencode/sentry.mcp.json" ]
  assert [ ! -e "$PROJECT/.agents/mcp-runtime/.owned.opencode-v2" ]
}

@test "the legacy migration never writes through a symlinked record" {
  set_harness opencode-v2
  local outside
  outside="$(mktemp)"
  mkdir -p "$PROJECT/.agents/mcp-runtime"
  ln -sfn "${outside}" "$PROJECT/.agents/mcp-runtime/.owned.opencode"
  printf 'sentry\t222-2\n' > "$PROJECT/.agents/mcp-runtime/.owned.opencode-v2"

  _devbot_apply_runtime_mcps "$PROJECT"

  run cat "${outside}"
  assert_output ""
  assert [ ! -L "$PROJECT/.agents/mcp-runtime/.owned.opencode" ]
}

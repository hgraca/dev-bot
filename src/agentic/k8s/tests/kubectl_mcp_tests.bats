#!/usr/bin/env bats

# src/agentic/k8s/tests/kubectl_mcp_tests.bats
# Split from kubectl_init_tests.bats; setup, stubs and fixtures live in
# kubectl_test_helper.bash so a fixture is never copied into two files.
#
# One server per RENDERED cluster, named `kctl-<cluster>`, published through the
# harness-agnostic runtime manifest. The server name is the scoping: a dropped
# cluster must lose its server too.

setup() {
  load 'kubectl_test_helper'
  kubectl_setup
}

# ── MCP servers ───────────────────────────────────────────────────────────────
# One server per RENDERED cluster, named kctl-<cluster>, published through the
# harness-agnostic runtime manifest. The server name is the scoping: the agent's
# tool list names the target, so a dropped cluster must lose its server too.

# The runtime-manifest GROUP keeps the module's name (`k8s-<cluster>`) — that
# filename is how a disabled module's manifests are recognised — while the
# server KEY is `kctl-<cluster>`, which is what the agent's tool list shows.
@test "publishes one MCP server per rendered cluster" {
  write_config

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert [ -f "$(runtime_manifest k8s-prod)" ]
  assert [ -f "$(runtime_manifest k8s-stg)" ]
  assert [ -f "$(harness_manifest k8s-prod)" ]

  run cat "$(runtime_manifest k8s-prod)"
  assert_output --partial '"kctl-k8s-prod"'
  assert_output --partial "kctl-mcp.sh k8s-prod"

  # Applied through the harness: the server is live in opencode's own shape,
  # carrying the resolved harness dir rather than the translator token.
  run cat "$(harness_manifest k8s-prod)"
  assert_output --partial '"kctl-k8s-prod"'
  assert_output --partial ".opencode/kctl-mcp.sh k8s-prod"
  refute_output --partial "{harness-dir}"
  refute_output --partial "AKIA_TEST_ACCESS"
}

@test "a cluster the render dropped gets no MCP server" {
  write_config
  export STUB_FAIL_CLUSTER="k8s-prod"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  refute [ -e "$(runtime_manifest k8s-prod)" ]
  assert [ -f "$(runtime_manifest k8s-stg)" ]
}

@test "an emptied selection retires the published servers" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert [ -f "$(runtime_manifest k8s-prod)" ]

  printf '{ "project_name": "demo", "kubectl": [] }\n' > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc"
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  refute [ -e "$(runtime_manifest k8s-prod)" ]
  refute [ -e "$(harness_manifest k8s-prod)" ]
}

@test "a selection revision republishes instead of doubling the servers" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert [ -f "$(runtime_manifest k8s-stg)" ]

  printf '{ "project_name": "demo", "kubectl": ["k8s-prod"] }\n' \
    > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc"
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert [ -f "$(runtime_manifest k8s-prod)" ]
  refute [ -e "$(runtime_manifest k8s-stg)" ]
  refute [ -e "$(harness_manifest k8s-stg)" ]
}

@test "a renamed entry publishes kctl-<name> but describes the catalogue key" {
  write_renamed_config

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success

  # The identity is the AWS cluster: both describe queries carry the key.
  assert_equal "$(grep -c -- '--name gete-prd' "$BATS_TEST_TMPDIR/aws-describe.log")" 2

  # The label is what an agent sees and what kctl.sh resolves at call time.
  run jq -r '.mcp | keys[0]' "$(runtime_manifest gete-prd)"
  assert_output "kctl-gete"
  run jq -r '.mcp."kctl-gete".command[2]' "$(runtime_manifest gete-prd)"
  assert_output --partial "kctl-mcp.sh gete-prd"
  refute [ -e "$(harness_manifest gete)" ]
}

@test "a renamed entry renders the label as the kubeconfig cluster object" {
  write_renamed_config

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  run grep -E '^  - name: ' "$KUBECONFIG_FILE"
  assert_output --partial "- name: gete"
  refute_output --partial "- name: gete-prd"
  run grep current-context "$KUBECONFIG_FILE"
  assert_output --partial "current-context: gete-prod-ro"
}

@test "a renamed entry's exec args name the AWS cluster, not the label" {
  # The wrapper turns the second arg into `aws eks get-token --cluster-name`, so a
  # label here authenticates against a cluster that does not exist.
  write_renamed_config

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  run grep -o 'args: \[[^]]*\]' "$KUBECONFIG_FILE"
  assert_output --partial '"eu-central-1", "gete-prd"'
}

@test "a catalogue key that is not a plain name is refused before it is published" {
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": {
      "k8s;echo INJECTED": { "region": "eu-central-1" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s;echo INJECTED"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_output --partial "cluster key 'k8s;echo INJECTED' is not valid"
  refute [ -e "$BATS_TEST_TMPDIR/project/.agents/mcp-runtime/k8s-k8s;echo INJECTED.json" ]
}

@test "a refused catalogue revokes the previous render instead of leaving it live" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success
  assert [ -n "$(generated_files)" ]

  # Same project, now with a key that cannot be rendered safely.
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": { "k8s;echo INJECTED": { "region": "eu-central-1" } }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s;echo INJECTED"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_equal "$(generated_files | wc -l)" 0
  refute [ -e "$(runtime_manifest k8s-prod)" ]
}

@test "a label that cannot name a kubeconfig object is refused, not skipped" {
  # Skipping it would be worse than refusing: when it is the only selected entry
  # the render ends up empty and the previous access stays live.
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success
  assert [ -n "$(generated_files)" ]

  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": { "gete-prd": { "name": "team: prod", "region": "eu-central-1" } }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["gete-prd"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_output --partial "cluster name 'team: prod' is not valid"
  assert_equal "$(generated_files | wc -l)" 0
}

@test "two entries sharing an effective context are refused" {
  # Both would resolve to one context, so `kctl exec` could target the wrong
  # cluster while every name in the file looks distinct.
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": {
      "alpha": { "context": "shared-ctx", "region": "eu-central-1" },
      "beta": { "context": "shared-ctx", "region": "eu-central-1" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["alpha", "beta"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_output --partial "share the context 'shared-ctx'"
  assert_equal "$(generated_files | wc -l)" 0
}

@test "a label that is also another entry's key is refused as ambiguous" {
  # Labels stay distinct here, so only the key/label collision is in play:
  # `devbot kctl exec beta` means one entry's label and another's key.
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": {
      "alpha": { "name": "beta", "region": "eu-central-1" },
      "beta": { "name": "gamma", "region": "eu-central-1" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["alpha", "beta"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_output --partial "is also another entry's catalogue key"
  assert_equal "$(generated_files | wc -l)" 0
}

@test "a context that falls back to another entry's label is refused" {
  # `context` is only used when it is a plain name; otherwise the render falls
  # back to the label. Comparing raw values misses the collision that remains.
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": {
      "alpha": { "name": "alpha-label", "context": "bad/name", "region": "eu-central-1" },
      "beta": { "name": "beta-label", "context": "alpha-label", "region": "eu-central-1" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["alpha", "beta"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_output --partial "share the context 'alpha-label'"
  assert_equal "$(generated_files | wc -l)" 0
}

@test "a renamed entry is revoked even when AWS cannot describe it" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success
  assert [ -n "$(generated_files)" ]

  # Same key, new label, and a describe failure: the early "leave the existing
  # kubeconfig untouched" return must not keep the old name live.
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": { "k8s-prod": { "name": "renamed", "region": "eu-central-1" } }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-prod"] }
JSONC
  export STUB_FAIL_CLUSTER="k8s-prod"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_equal "$(generated_files | wc -l)" 0
}

@test "a non-string name is refused instead of aborting with stale access" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success
  assert [ -n "$(generated_files)" ]

  # `test()` on a number is a jq type error, which under set -e aborted init
  # before the prune. It has to be a controlled refusal that revokes.
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": { "k8s-prod": { "name": 123, "region": "eu-central-1" } }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-prod"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_output --partial "has a name that is not a string"
  assert_equal "$(generated_files | wc -l)" 0
}

@test "a non-string context is refused the same way" {
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": { "k8s-prod": { "context": 123, "region": "eu-central-1" } }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-prod"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_output --partial "has a context that is not a string"
  refute_output --partial "Traceback"
  assert_equal "$(generated_files | wc -l)" 0
}

@test "a cluster entry that is not an object is refused before field checks" {
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": { "k8s-prod": "eu-central-1" }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-prod"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_output --partial "cluster 'k8s-prod' is not an object"
  refute_output --partial "Traceback"
  assert_equal "$(generated_files | wc -l)" 0
}

@test "a static kubeconfig user named like a generated one is not misread" {
  # The recorded labels manifest, not a `devbot-<label>` name heuristic, decides
  # which objects this module rendered.
  write_static_kubeconfig "$BATS_TEST_TMPDIR/static.yaml"
  write_static_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "kosmos", "kubectl": ["kosmos"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  local first="$KUBECONFIG_FILE"
  local labels="${KUBECONFIG_FILE%.yaml}.labels"
  assert [ -f "$labels" ]
  run cat "$labels"
  assert_output "kosmos"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  refute_output --partial "reached outside the selection"
  assert [ -f "$first" ]
}

@test "a render with no label record is invalidated before the AWS gate" {
  # Rendered by a build that predates the record: a renamed entry cannot be
  # detected from the sidecar, so the old render must not survive an AWS outage.
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  assert [ -f "$KUBECONFIG_FILE" ]

  rm -f "${KUBECONFIG_FILE%.yaml}.labels"
  printf '{ "project_name": "demo", "kubectl": ["k8s-prod"] }\n' \
    >"$BATS_TEST_TMPDIR/project/.devbot.project.jsonc"
  export STUB_FAIL_CLUSTER="k8s-prod"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_output --partial "predates the label record"
  assert_equal "$(generated_files | wc -l)" 0
}

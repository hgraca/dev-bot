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

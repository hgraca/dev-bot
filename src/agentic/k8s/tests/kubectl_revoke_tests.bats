#!/usr/bin/env bats

# src/agentic/k8s/tests/kubectl_revoke_tests.bats
# Split from kubectl_init_tests.bats; setup, stubs and fixtures live in
# kubectl_test_helper.bash so a fixture is never copied into two files.
#
# A shrunken selection must revoke what it no longer grants: a cluster dropped
# from the project's list loses its context, its credential and its MCP server,
# and a kubeconfig that reaches outside the current selection is pruned rather
# than left answering for a cluster nobody asked for.

setup() {
  load 'kubectl_test_helper'
  kubectl_setup
}

@test "the longest matching cluster name wins" {
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": {
      "AWS_ACCESS_KEY_ID": "${AWS_KEY}",
      "AWS_SECRET_ACCESS_KEY": "${AWS_SECRET}"
    },
    "clusters": {
      "dev": { "context": "dev-ro", "region": "eu-central-1" },
      "gete-dev": { "context": "gete-staging-rw", "region": "eu-central-1" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "k8s-gete-dev", "kubectl": ["dev", "gete-dev"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  run grep current-context "$KUBECONFIG_FILE"
  assert_output --partial "current-context: gete-staging-rw"
}

@test "a name match outside the project's selection is ignored" {
  write_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "k8s-stg", "kubectl": ["k8s-prod"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  # Falling back to production must not happen silently: the name said staging.
  assert_output --partial "names cluster 'k8s-stg', which this project does not select"
  run grep current-context "$KUBECONFIG_FILE"
  assert_output --partial "current-context: k8s-prod-ro"
}

@test "the project name falls back to the directory basename" {
  write_config
  mkdir -p "$BATS_TEST_TMPDIR/k8s-stg"
  cat > "$BATS_TEST_TMPDIR/k8s-stg/.devbot.project.jsonc" <<'JSONC'
{ "kubectl": ["k8s-prod", "k8s-stg"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/k8s-stg"
  resolve_paths

  assert_success
  run grep current-context "$KUBECONFIG_FILE"
  assert_output --partial "current-context: k8s-stg-rw"
}

@test "a name match on a cluster that cannot be described falls back" {
  write_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "k8s-stg", "kubectl": ["k8s-prod", "k8s-stg"] }
JSONC
  export STUB_FAIL_CLUSTER="k8s-stg"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  run grep current-context "$KUBECONFIG_FILE"
  assert_output --partial "current-context: k8s-prod-ro"
  refute_output --partial "k8s-stg-rw"
}

@test "an unknown cluster name is reported and skipped" {
  write_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-prod", "ghost"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "cluster 'ghost' is not in the global kubectl catalogue"
  run cat "$KUBECONFIG_FILE"
  assert_output --partial "k8s-prod-ro"
  refute_output --partial "ghost"
}

@test "an empty selection prunes that project's files" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  assert [ -f "$KUBECONFIG_FILE" ]

  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": [] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "no clusters selected"
  assert_equal "$(generated_files)" ""
}

@test "two projects render separate kubeconfigs and neither overwrites the other" {
  write_config
  mkdir -p "$BATS_TEST_TMPDIR/other"
  cat > "$BATS_TEST_TMPDIR/other/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "other", "kubectl": ["k8s-stg"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  local first="$KUBECONFIG_FILE"

  run bash "$INIT" "$BATS_TEST_TMPDIR/other"
  resolve_paths
  assert_success
  local other="$KUBECONFIG_FILE"

  assert [ -f "$first" ]
  assert [ -f "$other" ]
  assert [ "$first" != "$other" ]

  run cat "$first"
  assert_output --partial "k8s-prod-ro"
  run cat "$other"
  assert_output --partial "k8s-stg-rw"
  refute_output --partial "k8s-prod-ro"

  run cat "${other%.yaml}.env"
  assert_output --partial "KUBECONFIG=\"${other}\""
}

# `devbot init` defaults project_name to the directory basename, so the readable
# part of the slug collides for two checkouts both called `demo`. The path hash
# is what keeps their kubeconfigs apart.
@test "two projects with the same name do not share a kubeconfig" {
  write_config
  mkdir -p "$BATS_TEST_TMPDIR/a/demo" "$BATS_TEST_TMPDIR/b/demo"
  printf '{ "project_name": "demo", "kubectl": ["k8s-prod"] }\n' \
    > "$BATS_TEST_TMPDIR/a/demo/.devbot.project.jsonc"
  printf '{ "project_name": "demo", "kubectl": ["k8s-stg"] }\n' \
    > "$BATS_TEST_TMPDIR/b/demo/.devbot.project.jsonc"

  run bash "$INIT" "$BATS_TEST_TMPDIR/a/demo"
  assert_success
  run bash "$INIT" "$BATS_TEST_TMPDIR/b/demo"
  assert_success

  assert_equal "$(generated_files | grep -c '\.yaml$')" "2"

  run bash -c 'grep -l "k8s-prod-ro" "$HOME"/.kube/devbot/*.yaml | wc -l'
  assert_output "1"
  run bash -c 'grep -l "k8s-stg-rw" "$HOME"/.kube/devbot/*.yaml | wc -l'
  assert_output "1"
}

@test "a selection that matches no catalogue entry prunes the previous file" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  local previous="$KUBECONFIG_FILE"
  assert [ -f "$previous" ]

  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["ghost"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success
  assert_output --partial "no selected cluster is in the global catalogue"
  refute [ -e "$previous" ]
}

@test "the legacy machine-wide kubeconfig is removed after a scoped render" {
  write_config
  mkdir -p "$HOME/.kube"
  printf 'apiVersion: v1\nkind: Config\nusers:\n  - name: devbot-k8s-prod\n    user:\n      exec:\n        command: %s\n' \
    "$HOME/.kube/devbot/exec-credential.sh" > "$HOME/.kube/devbot.yaml"
  printf 'export KUBECONFIG="%s"\n' "$HOME/.kube/devbot.yaml" > "$HOME/.kube/devbot.env"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success
  assert_output --partial "removed the legacy machine-wide kubeconfig"
  refute [ -e "$HOME/.kube/devbot.yaml" ]
  refute [ -e "$HOME/.kube/devbot.env" ]
}

@test "a legacy kubeconfig that is not ours is left alone" {
  write_config
  mkdir -p "$HOME/.kube"
  printf 'apiVersion: v1\nkind: Config\nclusters: []\n' > "$HOME/.kube/devbot.yaml"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success
  refute_output --partial "removed the legacy"
  assert [ -f "$HOME/.kube/devbot.yaml" ]
}

@test "a describe failure prunes a kubeconfig that reaches outside the selection" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  local previous="$KUBECONFIG_FILE"

  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-stg"] }
JSONC
  export STUB_FAIL_CLUSTER="k8s-stg"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "reached outside the selection"
  refute [ -e "$previous" ]
}

@test "a describe failure keeps a kubeconfig that is still within the selection" {
  write_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-prod"] }
JSONC
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  local previous="$KUBECONFIG_FILE"
  assert [ -f "$previous" ]

  export STUB_FAIL_CLUSTER="k8s-prod"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "leaving the existing kubeconfig untouched"
  assert [ -f "$previous" ]
}

@test "an all-unknown selection prunes even when the credentials are unusable" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  local previous="$KUBECONFIG_FILE"

  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["ghost"] }
JSONC
  export STUB_IDENTITY="user"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "no selected cluster is in the global catalogue"
  refute_output --partial "not a role session"
  refute [ -e "$previous" ]
}

@test "the legacy kubeconfig is removed even when this project does not opt in" {
  write_config
  mkdir -p "$HOME/.kube"
  printf 'apiVersion: v1\nkind: Config\nusers:\n  - name: devbot-k8s-prod\n    user:\n      exec:\n        command: %s\n' \
    "$HOME/.kube/devbot/exec-credential.sh" > "$HOME/.kube/devbot.yaml"
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo" }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "removed the legacy machine-wide kubeconfig"
  refute [ -e "$HOME/.kube/devbot.yaml" ]
}

@test "a shrunken selection is revoked before the AWS checks run" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  local previous="$KUBECONFIG_FILE"

  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-stg"] }
JSONC
  export STUB_IDENTITY="user"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "reached outside the selection"
  refute [ -e "$previous" ]
}

@test "a catalogue-unknown name in the selection does not protect a stale cluster" {
  write_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-prod"] }
JSONC
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  local previous="$KUBECONFIG_FILE"
  sed -i 's/k8s-prod/removed-cluster/g' "$previous"

  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["removed-cluster", "k8s-stg"] }
JSONC
  export STUB_FAIL_CLUSTER="k8s-stg"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "reached outside the selection"
  refute [ -e "$previous" ]
}

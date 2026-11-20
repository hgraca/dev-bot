#!/usr/bin/env bats

# src/agentic/k8s/tests/kubectl_static_tests.bats
# Split from kubectl_init_tests.bats; setup, stubs and fixtures live in
# kubectl_test_helper.bash so a fixture is never copied into two files.
#
# A `type: "static"` entry names a kubeconfig instead of describing an EKS
# cluster: the render must work with no AWS at all, and the merged file must
# carry the static cluster's own auth — a k3d cluster authenticates with a
# client certificate that cannot be reconstructed from a describe call.

setup() {
  load 'kubectl_test_helper'
  kubectl_setup
}

# ── static clusters ───────────────────────────────────────────────────────────
# A `type: "static"` entry names a kubeconfig instead of describing an EKS
# cluster. The property that matters: the render must work with no AWS at all,
# and the merged file must carry the static cluster's own auth — a k3d cluster
# authenticates with a client certificate, which cannot be reconstructed from an
# EKS describe call.

# Args: <path> [context name]
# Cluster and user names derive from the context so two fixtures never collide:
# the render refuses a static entry whose object names are already taken.
@test "a static cluster renders without any AWS access" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/static.yaml"
  write_static_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "kosmos", "kubectl": ["kosmos"] }
JSONC

  # Any use of the AWS CLI would mean the static path leaked into the EKS one.
  rm -f "$BATS_TEST_TMPDIR/bin/aws"
  cat > "$BATS_TEST_TMPDIR/bin/aws" <<'STUB'
#!/usr/bin/env bash
touch "$AWS_WAS_CALLED"
exit 1
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/aws"
  export AWS_WAS_CALLED="$BATS_TEST_TMPDIR/aws-called"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  refute_output --partial "aws CLI"
  refute_output --partial "AWS profile"
  refute [ -e "$AWS_WAS_CALLED" ]
  # The wrapper exists to mint EKS tokens; a certificate-authenticated cluster
  # has no use for it.
  refute [ -e "$HOME/.kube/devbot/exec-credential.sh" ]

  run cat "$KUBECONFIG_FILE"
  assert_output --partial "name: cluster-k3d-kosmos"
  assert_output --partial "https://127.0.0.2:6443"
  assert_output --partial "client-certificate-data: Y2xpZW50LWNlcnQ="
  assert_output --partial "current-context: k3d-kosmos"
}

@test "a static cluster whose kubeconfig is missing is left out" {
  write_static_config "$BATS_TEST_TMPDIR/absent.yaml"
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "kosmos", "kubectl": ["kosmos"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "is not readable"
  assert_equal "$(generated_files)" ""
}

@test "a static cluster whose context is absent is left out" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/static.yaml" "some-other-context"
  write_static_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "kosmos", "kubectl": ["kosmos"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "context 'k3d-kosmos' is not in"
  assert_equal "$(generated_files)" ""
}

@test "a static and an EKS cluster render together" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/static.yaml"
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<JSONC
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": {
      "AWS_ACCESS_KEY_ID": "\${AWS_KEY}",
      "AWS_SECRET_ACCESS_KEY": "\${AWS_SECRET}"
    },
    "clusters": {
      "k8s-prod": { "name": "k8s-prod", "context": "k8s-prod-ro", "region": "eu-central-1" },
      "kosmos": { "name": "kosmos", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/static.yaml", "context": "k3d-kosmos" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-prod", "kosmos"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  run cat "$KUBECONFIG_FILE"
  assert_output --partial "k8s-prod-ro"
  assert_output --partial "name: cluster-k3d-kosmos"
  assert_output --partial "k3d-kosmos"
  assert_output --partial "client-certificate-data"
  # The AWS cluster keeps its exec user; the static one keeps its certificate.
  assert_output --partial "devbot-k8s-prod"
  assert [ -x "$HOME/.kube/devbot/exec-credential.sh" ]
}

@test "a static cluster dropped from the selection stops being usable" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/s1.yaml" "ctx-1"
  write_static_kubeconfig "$BATS_TEST_TMPDIR/s2.yaml" "ctx-2"
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<JSONC
{
  "kubectl": {
    "clusters": {
      "s1": { "name": "s1", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s1.yaml", "context": "ctx-1" },
      "s2": { "name": "s2", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s2.yaml", "context": "ctx-2" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["s1", "s2"] }
JSONC
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  run cat "$KUBECONFIG_FILE"
  assert_output --partial "ctx-2"

  # s2 is no longer selected and s1 can no longer be rendered, so the render
  # produces nothing — the stale context must not survive on disk.
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["s1"] }
JSONC
  rm -f "$BATS_TEST_TMPDIR/s1.yaml"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "reached outside the selection"
  assert_equal "$(generated_files)" ""
}

# ── review findings: what a static entry may expose ───────────────────────────

@test "only the selected context leaves a static kubeconfig" {
  cat > "$BATS_TEST_TMPDIR/static.yaml" <<'YAML'
apiVersion: v1
kind: Config
clusters:
  - name: cluster-selected
    cluster:
      server: https://127.0.0.1:6443
      certificate-authority-data: Y2E=
  - name: cluster-other
    cluster:
      server: https://127.0.0.2:6443
      certificate-authority-data: Y2E=
users:
  - name: user-selected
    user:
      token: selected
  - name: user-other
    user:
      token: other
contexts:
  - name: ctx-selected
    context:
      cluster: cluster-selected
      user: user-selected
  - name: ctx-other
    context:
      cluster: cluster-other
      user: user-other
current-context: ctx-selected
YAML
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<JSONC
{
  "kubectl": {
    "clusters": {
      "kosmos": { "name": "kosmos", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/static.yaml", "context": "ctx-selected" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "kosmos", "kubectl": ["kosmos"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  run cat "$KUBECONFIG_FILE"
  assert_output --partial "ctx-selected"
  refute_output --partial "ctx-other"
  refute_output --partial "cluster-other"
  refute_output --partial "user-other"
}

@test "a static entry whose object names collide is left out" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/s1.yaml" "ctx-1"
  # Same cluster name as s1's, under a different context: merging both would
  # let one silently win, so the second must be refused.
  cat > "$BATS_TEST_TMPDIR/s2.yaml" <<'YAML'
apiVersion: v1
kind: Config
clusters:
  - name: cluster-ctx-1
    cluster:
      server: https://127.0.0.2:6443
      certificate-authority-data: Y2E=
users:
  - name: user-two
    user:
      token: two
contexts:
  - name: ctx-2
    context:
      cluster: cluster-ctx-1
      user: user-two
current-context: ctx-2
YAML
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<JSONC
{
  "kubectl": {
    "clusters": {
      "s1": { "name": "s1", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s1.yaml", "context": "ctx-1" },
      "s2": { "name": "s2", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s2.yaml", "context": "ctx-2" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["s1", "s2"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "collides"
  run cat "$KUBECONFIG_FILE"
  assert_output --partial "ctx-1"
  refute_output --partial "ctx-2"
}

@test "a static entry removed from the catalogue is still revoked" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/s1.yaml" "ctx-1"
  write_static_kubeconfig "$BATS_TEST_TMPDIR/s2.yaml" "ctx-2"
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<JSONC
{
  "kubectl": {
    "clusters": {
      "s1": { "name": "s1", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s1.yaml", "context": "ctx-1" },
      "s2": { "name": "s2", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s2.yaml", "context": "ctx-2" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["s1", "s2"] }
JSONC
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success

  # s2 disappears from the catalogue entirely, and s1 can no longer render:
  # nothing but the recorded manifest can still name ctx-2.
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<JSONC
{
  "kubectl": {
    "clusters": {
      "s1": { "name": "s1", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s1.yaml", "context": "ctx-1" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["s1"] }
JSONC
  rm -f "$BATS_TEST_TMPDIR/s1.yaml"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "reached outside the selection"
  assert_equal "$(generated_files)" ""
}

@test "a static-only project runs without the AWS credential variables" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/static.yaml"
  write_static_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "kosmos", "kubectl": ["kosmos"] }
JSONC
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success

  # record what kubectl was asked to do, and never fail
  cat > "$BATS_TEST_TMPDIR/bin/kubectl" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/kubectl-called"
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/kubectl"

  unset AWS_KEY AWS_SECRET
  run bash "$MODULE_DIR/kctl.sh" run "$BATS_TEST_TMPDIR/project" -- get nodes

  assert_success
  run cat "$BATS_TEST_TMPDIR/kubectl-called"
  assert_output --partial "get nodes"
}

@test "swapping a static entry for an EKS one prunes the old render" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/static.yaml"
  write_static_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "kosmos", "kubectl": ["kosmos"] }
JSONC
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success

  # The same name now resolves to an EKS entry, and AWS is unusable: the old
  # static render must not survive that.
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<JSONC
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "\${AWS_KEY}" },
    "clusters": {
      "kosmos": { "name": "kosmos", "context": "k3d-kosmos", "region": "eu-central-1" }
    }
  }
}
JSONC
  unset AWS_KEY

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "is no longer a static entry"
  assert_equal "$(generated_files)" ""
}

@test "a deleted static source prunes the previous render" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/static.yaml"
  write_static_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "kosmos", "kubectl": ["kosmos"] }
JSONC
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  assert [ -f "$KUBECONFIG_FILE" ]

  rm -f "$BATS_TEST_TMPDIR/static.yaml"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "could not be rendered"
  assert_equal "$(generated_files)" ""
}

@test "kctl env does not label an unknown context static" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/static.yaml"
  write_static_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "kosmos", "kubectl": ["kosmos"] }
JSONC
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success

  # The catalogue no longer knows the context: it cannot be called static.
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{ "kubectl": { "clusters": [] } }
JSONC

  run bash "$MODULE_DIR/kctl.sh" env "$BATS_TEST_TMPDIR/project"

  assert_success
  refute_output --partial "static context"
  assert_output --partial "must be set"
}

@test "revocation still works when the generated file cannot be read" {
  write_static_kubeconfig "$BATS_TEST_TMPDIR/s1.yaml" "ctx-1"
  write_static_kubeconfig "$BATS_TEST_TMPDIR/s2.yaml" "ctx-2"
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<JSONC
{
  "kubectl": {
    "clusters": {
      "s1": { "name": "s1", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s1.yaml", "context": "ctx-1" },
      "s2": { "name": "s2", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s2.yaml", "context": "ctx-2" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["s1", "s2"] }
JSONC
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success

  # Corrupt the generated file so the kubectl probe cannot read it, then drop s2
  # from the selection: the manifest must still drive revocation.
  printf 'not: [valid\n' > "$KUBECONFIG_FILE"
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["s1"] }
JSONC
  rm -f "$BATS_TEST_TMPDIR/s1.yaml"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "reached outside the selection"
  assert_equal "$(generated_files)" ""
}

@test "a dropped cluster's server key is retired even when its manifest is gone" {
  write_config
  # The key is registered by the harness; stand in for it here, since this
  # suite runs init.sh without a harness.
  cat > "$BATS_TEST_TMPDIR/project/opencode.jsonc" <<'JSON'
{
  "mcp": {
    "kctl-k8s-prod": {"type": "local", "command": ["bash", "-c", "true"]},
    "kctl-k8s-stg": {"type": "local", "command": ["bash", "-c", "true"]}
  }
}
JSON
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert [ -f "$(harness_manifest k8s-prod)" ]

  # Keep the generated file in step with the new selection: this exercises the
  # retirement path alone, not the wider-than-selection prune (which revokes
  # everything and lets the harness re-register the survivors).
  cat > "$KUBECONFIG_FILE" <<'EOF'
apiVersion: v1
kind: Config
current-context: k8s-stg-rw
contexts:
- context: {cluster: k8s-stg, user: devbot-k8s-stg}
  name: k8s-stg-rw
clusters: []
users: []
EOF
  # The rendered-label record must move with it: a label set that no longer
  # matches the selection is out-of-selection content and is pruned wholesale.
  printf 'k8s-stg\n' > "${KUBECONFIG_FILE%.yaml}.rendered"
  # A rebuilt or tidied .opencode/ can lose the manifest while the merged key
  # stays. Retirement must not fall back to the group name (k8s-<cluster>) and
  # leave the live key (kctl-<key>) behind.
  rm -f "$(harness_manifest k8s-prod)"
  printf '{ "project_name": "demo", "kubectl": ["k8s-stg"] }\n' \
    > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc"
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  refute [ -e "$(runtime_manifest k8s-prod)" ]
  run grep -q '"kctl-k8s-prod"' "$BATS_TEST_TMPDIR/project/opencode.jsonc"
  assert_failure
  run grep -q '"kctl-k8s-stg"' "$BATS_TEST_TMPDIR/project/opencode.jsonc"
  assert_success
}

@test "a static render is not treated as stale on the next reinit" {
  # A static entry brings its own cluster objects (`cluster-k3d-kosmos`), which
  # are not catalogue labels. Scanning them as labels marked every static
  # project stale and deleted a working render on each reinit.
  write_static_kubeconfig "$BATS_TEST_TMPDIR/static.yaml"
  write_static_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "kosmos", "kubectl": ["kosmos"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  local first="$KUBECONFIG_FILE"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  refute_output --partial "reached outside the selection"
  assert [ -f "$first" ]
  run grep current-context "$first"
  assert_output --partial "k3d-kosmos"
}

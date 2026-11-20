#!/usr/bin/env bats

# src/agentic/k8s/tests/kubectl_render_tests.bats
# Split from kubectl_init_tests.bats; setup, stubs and fixtures live in
# kubectl_test_helper.bash so a fixture is never copied into two files.
#
# `k8s/init.sh` generates a kubeconfig and an exec credential wrapper from the
# `kubectl` node of the global config. The property a reviewer cannot see by
# reading the YAML: the wrapper must carry the ${VAR} *reference*, and the value
# must only ever exist in the environment of the process kubectl spawns. A
# regression here writes a live credential to disk while every generated file
# still looks correct.
#
# The wrapper is executed directly here, not through `bash`, so the shebang is
# exercised: /bin/sh is dash on Ubuntu and Fedora, and a bash-only body would
# fail there while passing a test that names the interpreter.

setup() {
  load 'kubectl_test_helper'
  kubectl_setup
}

@test "no kubectl node writes nothing" {
  printf '{ "version": "test" }\n' > "$DEV_BOT_GLOBAL_CONFIG"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "no 'kubectl' node"
  assert_equal "$(generated_files)" ""
  refute [ -e "$HOME/.kube/devbot/exec-credential.sh" ]
}

@test "generates both contexts and never writes a credential" {
  write_config

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert [ -f "$KUBECONFIG_FILE" ]
  assert [ -x "$HOME/.kube/devbot/exec-credential.sh" ]

  run cat "$KUBECONFIG_FILE"
  assert_output --partial "k8s-prod-ro"
  assert_output --partial "k8s-stg-rw"
  assert_output --partial "https://example.eks.amazonaws.com"
  refute_output --partial "AKIA_TEST_ACCESS"
  refute_output --partial "test-secret-value"

  run cat "$HOME/.kube/devbot/exec-credential.sh"
  assert_output --partial 'AWS_ACCESS_KEY_ID="${AWS_KEY}"'
  assert_output --partial '--profile "devbot-agent"'
  refute_output --partial "AKIA_TEST_ACCESS"
  refute_output --partial "test-secret-value"
}

@test "the wrapper resolves the reference at call time" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success

  # Replace the stub: this one records what the wrapper hands the AWS CLI.
  cat > "$BATS_TEST_TMPDIR/bin/aws" <<'STUB'
#!/usr/bin/env bash
echo "ARGS=$*"
echo "KEY=${AWS_ACCESS_KEY_ID:-unset}"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/aws"

  # Executed directly so the generated shebang is honoured, not bypassed.
  run "$HOME/.kube/devbot/exec-credential.sh" eu-central-1 k8s-prod

  assert_success
  assert_output --partial "KEY=AKIA_TEST_ACCESS"
  assert_output --partial "get-token"
  assert_output --partial "--cluster-name k8s-prod"
}

@test "an unset credential source skips instead of writing a broken config" {
  write_config
  unset AWS_KEY

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "which is not set"
  assert_equal "$(generated_files)" ""
}

@test "a missing AWS profile skips" {
  write_config "absent-profile"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "is not configured"
  assert_equal "$(generated_files)" ""
}

@test "a literal credential value is refused rather than written to the wrapper" {
  write_config "devbot-agent" "AKIA_LITERAL_VALUE"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "must be a \${VAR} reference"
  refute [ -e "$HOME/.kube/devbot/exec-credential.sh" ]
  assert_equal "$(generated_files)" ""
}

@test "an empty clusters list prunes the generated files" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths
  assert_success
  assert [ -f "$KUBECONFIG_FILE" ]

  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": {}
  }
}
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "removed the generated kubeconfig"
  assert_equal "$(generated_files)" ""
  assert_equal "$(generated_files)" ""
  # The wrapper is shared by every project on the machine, so pruning one
  # project's selection must not take it away from the others.
  assert [ -x "$HOME/.kube/devbot/exec-credential.sh" ]
}

@test "a cluster that cannot be described gets no user and no context" {
  write_config
  export STUB_FAIL_CLUSTER="k8s-stg"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "cannot describe cluster k8s-stg"

  run cat "$KUBECONFIG_FILE"
  assert_output --partial "k8s-prod-ro"
  refute_output --partial "k8s-stg-rw"
  refute_output --partial "devbot-k8s-stg"
  refute_output --partial "name: k8s-stg"
}

@test "writes an env file so kubectl actually reads the generated config" {
  write_config

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "KUBECONFIG="

  run cat "$ENV_FILE"
  assert_output --partial 'export KUBECONFIG="'"$KUBECONFIG_FILE"'"'
}

@test "an invalid context name falls back to the cluster name" {
  write_config "devbot-agent" "" "team: prod"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "is not a valid kubeconfig name"

  run cat "$KUBECONFIG_FILE"
  refute_output --partial "team: prod"
  assert_output --partial "name: k8s-prod"
}

@test "refuses to render when the profile does not resolve to a role session" {
  write_config
  export STUB_IDENTITY="user"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "not a role session"
  assert_equal "$(generated_files)" ""
  refute [ -e "$HOME/.kube/devbot/exec-credential.sh" ]
}

@test "a project that does not opt in writes nothing" {
  write_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo" }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  assert_output --partial "no 'kubectl' selection"
  assert_equal "$(generated_files)" ""
}

@test "only the clusters the project selects are rendered" {
  write_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-stg"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  run cat "$KUBECONFIG_FILE"
  assert_output --partial "k8s-stg-rw"
  refute_output --partial "k8s-prod-ro"
  refute_output --partial "name: k8s-prod"
}

@test "a project whose name matches no cluster opens on the first selected one" {
  write_config
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "demo", "kubectl": ["k8s-stg", "k8s-prod"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  run grep current-context "$KUBECONFIG_FILE"
  assert_output --partial "current-context: k8s-stg-rw"
}

# The project name, not the list position, says which environment the project
# is about: every project on a machine lists the same clusters in the same
# order, so position 1 is a copy-paste artefact. `k8s-gete-dev` reading
# production by default is how a prod answer gets reported as staging.
@test "the project name decides the default context, not the selection order" {
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": {
      "AWS_ACCESS_KEY_ID": "${AWS_KEY}",
      "AWS_SECRET_ACCESS_KEY": "${AWS_SECRET}"
    },
    "clusters": {
      "gete": { "name": "gete", "context": "gete-prod-ro", "region": "eu-central-1" },
      "gete-dev": { "name": "gete-dev", "context": "gete-staging-rw", "region": "eu-central-1" }
    }
  }
}
JSONC
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{ "project_name": "k8s-gete-dev", "kubectl": ["gete", "gete-dev"] }
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  resolve_paths

  assert_success
  # The default is also announced, so a reinit says which cluster it chose.
  assert_output --partial "context gete-staging-rw (default)"
  run grep current-context "$KUBECONFIG_FILE"
  assert_output --partial "current-context: gete-staging-rw"
}

@test "an array-shaped catalogue is refused by name, not read as empty" {
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "clusters": [ { "name": "k8s-prod", "region": "eu-central-1" } ]
  }
}
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_output --partial "must be an object keyed by cluster name"
  assert_output --partial "devbot update"
}

@test "a legacy array catalogue revokes the previous render when refused" {
  # A half-finished migration must not leave the old credentials reachable.
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success
  assert [ -n "$(generated_files)" ]

  printf '{ "kubectl": { "clusters": [ { "name": "k8s-prod" } ] } }\n' >"$DEV_BOT_GLOBAL_CONFIG"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_failure
  assert_output --partial "must be an object keyed by cluster name"
  assert_equal "$(generated_files | wc -l)" 0
}


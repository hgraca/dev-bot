#!/usr/bin/env bats

# src/agentic/k8s/tests/kubectl_init_tests.bats
# `k8s/init.sh` generates a kubeconfig and an exec credential wrapper from the
# `kubectl` node of the global config. The property a reviewer cannot see by
# reading the YAML: the wrapper must carry the ${VAR} *reference*, and the value
# must only ever exist in the environment of the process kubectl spawns. A
# regression here writes a live credential to disk while every generated file
# still looks correct.
#
# The wrapper is executed directly in the tests, not through `bash`, so the
# shebang is exercised: /bin/sh is dash on Ubuntu and Fedora, and a bash-only
# body would fail there while passing a test that names the interpreter.

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  INIT="$MODULE_DIR/init.sh"

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/project"
  export DEV_BOT_GLOBAL_CONFIG="$BATS_TEST_TMPDIR/global.jsonc"
  unset STUB_FAIL_CLUSTER STUB_IDENTITY

  # Stub the AWS CLI: `init.sh` only needs the profile list and the two
  # describe-cluster queries, and a real call would need real credentials.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/aws" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "configure list-profiles") echo devbot-agent ;;
  *get-caller-identity*)
    if [[ "${STUB_IDENTITY:-role}" == "user" ]]; then
      echo "arn:aws:iam::599001845632:user/devbot-readonly-herberto"
    else
      echo "arn:aws:sts::599001845632:assumed-role/devbot-agent/session"
    fi
    ;;
  *describe-cluster*)
    if [[ -n "${STUB_FAIL_CLUSTER:-}" && "$*" == *"--name ${STUB_FAIL_CLUSTER}"* ]]; then
      exit 1
    fi
    case "$*" in
      *certificateAuthority.data*) echo "Y2VydGlmaWNhdGUtYXV0aG9yaXR5" ;;
      *) echo "https://example.eks.amazonaws.com" ;;
    esac
    ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/aws"
  export PATH="$BATS_TEST_TMPDIR/bin:${PATH}"

  export AWS_KEY="AKIA_TEST_ACCESS"
  export AWS_SECRET="test-secret-value"
}

# Args: [profile] [credential value for AWS_ACCESS_KEY_ID] [context for the first cluster]
write_config() {
  local profile="${1:-devbot-agent}"
  local key_value="${2:-}"
  local context="${3:-k8s-prod-ro}"
  if [[ -z "${key_value}" ]]; then
    key_value='${AWS_KEY}'
  fi

  cat > "$DEV_BOT_GLOBAL_CONFIG" <<JSONC
{
  "kubectl": {
    "profile": "${profile}",
    "credential_env": {
      "AWS_ACCESS_KEY_ID": "${key_value}",
      "AWS_SECRET_ACCESS_KEY": "\${AWS_SECRET}"
    },
    "clusters": [
      { "name": "k8s-prod", "context": "${context}", "region": "eu-central-1" },
      { "name": "k8s-stg", "context": "k8s-stg-rw", "region": "eu-central-1" }
    ]
  }
}
JSONC
}

@test "no kubectl node writes nothing" {
  printf '{ "version": "test" }\n' > "$DEV_BOT_GLOBAL_CONFIG"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "no 'kubectl' node"
  refute [ -e "$HOME/.kube/devbot.yaml" ]
  refute [ -e "$HOME/.kube/devbot/exec-credential.sh" ]
}

@test "generates both contexts and never writes a credential" {
  write_config

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert [ -f "$HOME/.kube/devbot.yaml" ]
  assert [ -x "$HOME/.kube/devbot/exec-credential.sh" ]

  run cat "$HOME/.kube/devbot.yaml"
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

  assert_success
  assert_output --partial "which is not set"
  refute [ -e "$HOME/.kube/devbot.yaml" ]
}

@test "a missing AWS profile skips" {
  write_config "absent-profile"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "is not configured"
  refute [ -e "$HOME/.kube/devbot.yaml" ]
}

@test "a literal credential value is refused rather than written to the wrapper" {
  write_config "devbot-agent" "AKIA_LITERAL_VALUE"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "must be a \${VAR} reference"
  refute [ -e "$HOME/.kube/devbot/exec-credential.sh" ]
  refute [ -e "$HOME/.kube/devbot.yaml" ]
}

@test "an empty clusters list prunes the generated files" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert_success
  assert [ -f "$HOME/.kube/devbot.yaml" ]

  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": { "AWS_ACCESS_KEY_ID": "${AWS_KEY}" },
    "clusters": []
  }
}
JSONC

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "removed the generated kubeconfig"
  refute [ -e "$HOME/.kube/devbot.yaml" ]
  refute [ -e "$HOME/.kube/devbot/exec-credential.sh" ]
}

@test "a cluster that cannot be described gets no user and no context" {
  write_config
  export STUB_FAIL_CLUSTER="k8s-stg"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "cannot describe cluster k8s-stg"

  run cat "$HOME/.kube/devbot.yaml"
  assert_output --partial "k8s-prod-ro"
  refute_output --partial "k8s-stg-rw"
  refute_output --partial "devbot-k8s-stg"
  refute_output --partial "name: k8s-stg"
}

@test "writes an env file so kubectl actually reads the generated config" {
  write_config

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "KUBECONFIG="

  run cat "$HOME/.kube/devbot.env"
  assert_output --partial 'export KUBECONFIG="'"$HOME"'/.kube/devbot.yaml"'
}

@test "an invalid context name falls back to the cluster name" {
  write_config "devbot-agent" "" "team: prod"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "is not a valid kubeconfig name"

  run cat "$HOME/.kube/devbot.yaml"
  refute_output --partial "team: prod"
  assert_output --partial "name: k8s-prod"
}

@test "refuses to render when the profile does not resolve to a role session" {
  write_config
  export STUB_IDENTITY="user"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "not a role session"
  refute [ -e "$HOME/.kube/devbot.yaml" ]
  refute [ -e "$HOME/.kube/devbot/exec-credential.sh" ]
}

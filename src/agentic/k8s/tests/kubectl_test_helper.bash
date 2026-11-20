#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154  # the suites consume these, not this file
# src/agentic/k8s/tests/kubectl_test_helper.bash
# Shared fixtures for the k8s kubectl suites: the sandbox, the AWS stub and
# the kubeconfig/env render helpers. Sourced through `load`, never run.
#
# `kubectl_setup` is what each suite's setup() calls.
kubectl_setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  INIT="$MODULE_DIR/init.sh"

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/project"
  export DEV_BOT_GLOBAL_CONFIG="$BATS_TEST_TMPDIR/global.jsonc"

  # Cluster access is opt-in per project: the global `kubectl.clusters` is the
  # catalogue, and the project names the clusters it may use.
  cat > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc" <<'JSONC'
{
  "project_name": "demo",
  "kubectl": ["k8s-prod", "k8s-stg"]
}
JSONC
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

# The generated filename carries a hash of the project path, so read the paths
# from init's own output instead of duplicating that derivation in the test.
resolve_paths() {
  KUBECONFIG_FILE="$(printf '%s\n' "$output" \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | sed -n 's/.*kubectl — \(.*\.yaml\)[[:space:]]*$/\1/p' \
    | head -1)"
  ENV_FILE="${KUBECONFIG_FILE%.yaml}.env"
}

generated_files() {
  local f
  for f in "$HOME"/.kube/devbot/*.yaml "$HOME"/.kube/devbot/*.env; do
    [[ -e "$f" ]] && printf '%s\n' "$f"
  done
}

memory_file() {
  printf '%s\n' "$BATS_TEST_TMPDIR/project/.agents/memory/active/modules/k8s.md"
}

# The runtime-manifest GROUP keeps the module's name (`k8s-<cluster>`) — that
# filename is how a disabled module's manifests are recognised — while the
# server KEY is `kctl-<cluster>`, which is what the agent's tool list shows.
runtime_manifest() {
  printf '%s\n' "$BATS_TEST_TMPDIR/project/.agents/mcp-runtime/k8s-$1.json"
}

harness_manifest() {
  printf '%s\n' "$BATS_TEST_TMPDIR/project/.opencode/k8s-$1.mcp.json"
}

# Args: <path> [context name]
# Cluster and user names derive from the context so two fixtures never collide:
# the render refuses a static entry whose object names are already taken.
write_static_kubeconfig() {
  local path="$1" context="${2:-k3d-kosmos}"
  local cluster="cluster-${context}" user="admin@${context}"
  cat > "$path" <<YAML
apiVersion: v1
kind: Config
clusters:
  - name: ${cluster}
    cluster:
      server: https://127.0.0.2:6443
      certificate-authority-data: Y2VydGlmaWNhdGUtYXV0aG9yaXR5
users:
  - name: ${user}
    user:
      client-certificate-data: Y2xpZW50LWNlcnQ=
      client-key-data: Y2xpZW50LWtleQ==
contexts:
  - name: ${context}
    context:
      cluster: ${cluster}
      user: ${user}
current-context: ${context}
YAML
}

# A catalogue holding one static cluster. No profile and no credential_env: a
# static render must not need either.
write_static_config() {
  local path="${1:-$BATS_TEST_TMPDIR/static.yaml}"
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<JSONC
{
  "kubectl": {
    "clusters": [
      { "name": "kosmos", "type": "static", "kubeconfig": "${path}", "context": "k3d-kosmos" }
    ]
  }
}
JSONC
}


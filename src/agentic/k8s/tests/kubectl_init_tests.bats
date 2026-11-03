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
    | sed -n 's/.*kubectl — \(.*\.yaml\).*/\1/p' \
    | head -1)"
  ENV_FILE="${KUBECONFIG_FILE%.yaml}.env"
}

# Every kubeconfig and env file the module has generated, for any project.
generated_files() {
  local f
  for f in "$HOME"/.kube/devbot/*.yaml "$HOME"/.kube/devbot/*.env; do
    [[ -e "$f" ]] && printf '%s\n' "$f"
  done
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
    "clusters": []
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

@test "the first selected cluster becomes the current context" {
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

# ── Module memory ─────────────────────────────────────────────────────────────
# The module's always-on instructions live in the project's vault, written by
# this module rather than hand-copied into project.md. reinit clears the folder
# and every enabled module rewrites its own file, so the text has one source.

memory_file() {
  printf '%s\n' "$BATS_TEST_TMPDIR/project/.agents/memory/active/modules/k8s.md"
}

@test "writes the module memory file when the project opts in" {
  write_config

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert [ -f "$(memory_file)" ]
  run cat "$(memory_file)"
  assert_output --partial "devbot kube run"
  assert_output --partial "pods/exec"
}

@test "a project that does not opt in gets no module memory file" {
  write_config
  printf '{ "project_name": "demo" }\n' > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  refute [ -e "$(memory_file)" ]
}

@test "an empty selection gets no module memory file" {
  write_config
  printf '{ "project_name": "demo", "kubectl": [] }\n' > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  refute [ -e "$(memory_file)" ]
}

@test "no kubectl node in the global config gets no module memory file" {
  printf '{ "version": "test" }\n' > "$DEV_BOT_GLOBAL_CONFIG"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  refute [ -e "$(memory_file)" ]
}

@test "the module memory file survives a failed identity check" {
  write_config
  export STUB_IDENTITY=user

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "not a role session"
  assert [ -f "$(memory_file)" ]
}

@test "the module memory file survives a cluster that cannot be described" {
  write_config
  export STUB_FAIL_CLUSTER="k8s-prod"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "cannot describe cluster k8s-prod"
  assert [ -f "$(memory_file)" ]
}

@test "does not write through a symlinked module memory file" {
  write_config
  local outside
  outside="$(mktemp -d)"
  printf 'untouched\n' > "${outside}/victim.md"
  mkdir -p "$BATS_TEST_TMPDIR/project/.agents/memory/active/modules"
  ln -s "${outside}/victim.md" "$(memory_file)"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  run cat "${outside}/victim.md"
  assert_output "untouched"
  refute [ -L "$(memory_file)" ]
  run cat "$(memory_file)"
  assert_output --partial "devbot kube run"
  rm -r "${outside}"
}

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
    | sed -n 's/.*kubectl — \(.*\.yaml\)[[:space:]]*$/\1/p' \
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
    "clusters": [
      { "name": "gete", "context": "gete-prod-ro", "region": "eu-central-1" },
      { "name": "gete-dev", "context": "gete-staging-rw", "region": "eu-central-1" }
    ]
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

@test "the longest matching cluster name wins" {
  cat > "$DEV_BOT_GLOBAL_CONFIG" <<'JSONC'
{
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": {
      "AWS_ACCESS_KEY_ID": "${AWS_KEY}",
      "AWS_SECRET_ACCESS_KEY": "${AWS_SECRET}"
    },
    "clusters": [
      { "name": "dev", "context": "dev-ro", "region": "eu-central-1" },
      { "name": "gete-dev", "context": "gete-staging-rw", "region": "eu-central-1" }
    ]
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

# ── Module memory ─────────────────────────────────────────────────────────────
# The module's always-on instructions live in the project's vault, written by
# this module rather than hand-copied into project.md. reinit clears the folder
# and every enabled module rewrites its own file, so the text has one source.
#
# The rule is the module's, not the render's: the file is written whenever the
# module is enabled — including a project with no selection and a machine whose
# AWS is unusable — because that is exactly when a fallback to plain kubectl
# looks tempting.

memory_file() {
  printf '%s\n' "$BATS_TEST_TMPDIR/project/.agents/memory/active/modules/k8s.md"
}

@test "writes the module memory file when the project opts in" {
  write_config

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert [ -f "$(memory_file)" ]
  run cat "$(memory_file)"
  assert_output --partial "NEVER run \`kubectl\` in any shell"
  assert_output --partial "kctl-<cluster>"
  assert_output --partial "pods/exec"
}

@test "a project that does not opt in still gets the prohibition" {
  write_config
  printf '{ "project_name": "demo" }\n' > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert [ -f "$(memory_file)" ]
  run cat "$(memory_file)"
  assert_output --partial "NEVER run \`kubectl\` in any shell"
}

@test "an empty selection still gets the prohibition" {
  write_config
  printf '{ "project_name": "demo", "kubectl": [] }\n' > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert [ -f "$(memory_file)" ]
}

@test "no kubectl node in the global config still gets the prohibition" {
  printf '{ "version": "test" }\n' > "$DEV_BOT_GLOBAL_CONFIG"

  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert [ -f "$(memory_file)" ]
}

@test "a disabled k8s module gets no memory file and loses its access" {
  write_config
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"
  assert [ -f "$(runtime_manifest k8s-prod)" ]

  # A direct run with the module off must revoke what the enabled run created:
  # the prohibition would otherwise outlive the access it describes, and the
  # servers would outlive the kubeconfig they point at.
  printf '{\n  "project_name": "demo",\n  "kubectl": ["k8s-prod"],\n  "modules": { "k8s": false }\n}\n' \
    > "$BATS_TEST_TMPDIR/project/.devbot.project.jsonc"
  run bash "$INIT" "$BATS_TEST_TMPDIR/project"

  assert_success
  assert_output --partial "module disabled"
  refute [ -e "$(memory_file)" ]
  refute [ -e "$(runtime_manifest k8s-prod)" ]
  assert_equal "$(generated_files)" ""
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
  assert_output --partial "NEVER run \`kubectl\` in any shell"
  rm -r "${outside}"
}

# ── MCP servers ───────────────────────────────────────────────────────────────
# One server per RENDERED cluster, named kctl-<cluster>, published through the
# harness-agnostic runtime manifest. The server name is the scoping: the agent's
# tool list names the target, so a dropped cluster must lose its server too.

# The runtime-manifest GROUP keeps the module's name (`k8s-<cluster>`) — that
# filename is how a disabled module's manifests are recognised — while the
# server KEY is `kctl-<cluster>`, which is what the agent's tool list shows.
runtime_manifest() {
  printf '%s\n' "$BATS_TEST_TMPDIR/project/.agents/mcp-runtime/k8s-$1.json"
}

harness_manifest() {
  printf '%s\n' "$BATS_TEST_TMPDIR/project/.opencode/k8s-$1.mcp.json"
}

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

# ── static clusters ───────────────────────────────────────────────────────────
# A `type: "static"` entry names a kubeconfig instead of describing an EKS
# cluster. The property that matters: the render must work with no AWS at all,
# and the merged file must carry the static cluster's own auth — a k3d cluster
# authenticates with a client certificate, which cannot be reconstructed from an
# EKS describe call.

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
    "clusters": [
      { "name": "k8s-prod", "context": "k8s-prod-ro", "region": "eu-central-1" },
      { "name": "kosmos", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/static.yaml", "context": "k3d-kosmos" }
    ]
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
    "clusters": [
      { "name": "s1", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s1.yaml", "context": "ctx-1" },
      { "name": "s2", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s2.yaml", "context": "ctx-2" }
    ]
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
    "clusters": [
      { "name": "kosmos", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/static.yaml", "context": "ctx-selected" }
    ]
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
    "clusters": [
      { "name": "s1", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s1.yaml", "context": "ctx-1" },
      { "name": "s2", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s2.yaml", "context": "ctx-2" }
    ]
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
    "clusters": [
      { "name": "s1", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s1.yaml", "context": "ctx-1" },
      { "name": "s2", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s2.yaml", "context": "ctx-2" }
    ]
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
    "clusters": [
      { "name": "s1", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s1.yaml", "context": "ctx-1" }
    ]
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
    "clusters": [
      { "name": "kosmos", "context": "k3d-kosmos", "region": "eu-central-1" }
    ]
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
    "clusters": [
      { "name": "s1", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s1.yaml", "context": "ctx-1" },
      { "name": "s2", "type": "static", "kubeconfig": "$BATS_TEST_TMPDIR/s2.yaml", "context": "ctx-2" }
    ]
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
  # A rebuilt or tidied .opencode/ can lose the manifest while the merged key
  # stays. Retirement must not fall back to the group name (k8s-<cluster>) and
  # leave the live key (kctl-<cluster>) behind.
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

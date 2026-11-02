#!/usr/bin/env bats
# =============================================================================
# bin/tests/kube_tests.bats
# `devbot kube` resolves the kubeconfig the k8s module generated for a project.
# The point of the command is that neither the hashed filename nor the context
# name has to be reconstructed, so the tests pin: the usage/error surface, that
# `contexts` reflects the generated file (not the catalogue — init.sh skips a
# cluster it cannot describe), and that `run` announces and honours its target.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"

  export HOME="${SANDBOX}/home"
  mkdir -p "${HOME}/.kube/devbot" "${SANDBOX}/bin"

  PROJECT="${SANDBOX}/proj"
  mkdir -p "${PROJECT}"
  cat > "${PROJECT}/.devbot.project.jsonc" <<'EOF'
{
  "project_name": "demo",
  "kubectl": ["gete", "gete-dev"]
}
EOF

  export DEV_BOT_GLOBAL_CONFIG="${SANDBOX}/global.jsonc"
  cat > "${DEV_BOT_GLOBAL_CONFIG}" <<'EOF'
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
EOF

  # A fake kubectl so `run` and `contexts` can be observed without a cluster.
  cat > "${SANDBOX}/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"config get-contexts -o name"*) printf 'gete-staging-rw\n' ;;
  *) printf 'ARGS: %s\n' "$*" ;;
esac
EOF
  chmod +x "${SANDBOX}/bin/kubectl"
  export PATH="${SANDBOX}/bin:${PATH}"

  # The catalogue's credential_env refers to these; `run` preflights them.
  export AWS_KEY="test-key" AWS_SECRET="test-secret"

  DEVBOT="${PROJECT_ROOT}/bin/devbot"
}

teardown() {
  rm -r "${SANDBOX}"
}

# The slug mirrors _project_slug: project_name plus the first 8 hex of the
# absolute path's sha256.
kubeconfig_for() {
  local slug
  slug="$(printf '%s' "${PROJECT}" \
    | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:8])')"
  printf '%s/.kube/devbot/demo-%s.yaml' "${HOME}" "${slug}"
}

# Only the staging context is present: the catalogue also lists production, and
# `contexts` must report the file, not the catalogue.
write_kubeconfig() {
  cat > "$(kubeconfig_for)" <<'EOF'
apiVersion: v1
kind: Config
current-context: gete-staging-rw
contexts:
- context:
    cluster: gete-dev
    user: devbot-gete-dev
  name: gete-staging-rw
clusters: []
users: []
EOF
}

@test "bare 'kube' prints usage and fails" {
  run "${DEVBOT}" kube
  assert_failure
  assert_output --partial "Usage:"
  assert_output --partial "devbot kube run"
}

@test "unknown kube subcommand is refused, not guessed" {
  run "${DEVBOT}" kube nonsense
  assert_failure
  assert_output --partial "unknown 'kube' subcommand: nonsense"
}

@test "a missing generated kubeconfig names the reinit fix" {
  run "${DEVBOT}" kube env "${PROJECT}"
  assert_failure
  assert_output --partial "no generated kubeconfig"
  assert_output --partial "devbot reinit"
}

@test "contexts reports the generated file, not the whole catalogue" {
  write_kubeconfig

  run "${DEVBOT}" kube contexts "${PROJECT}"
  assert_success
  assert_output --partial "gete-staging-rw"
  refute_output --partial "gete-prod-ro"

  local expected
  expected="$(printf '%-10s %-18s %s' "gete-dev" "gete-staging-rw" "eu-central-1")"
  assert_output --partial "${expected}"
}

@test "env prints the path and the context, and only credential names" {
  write_kubeconfig
  local kubeconfig
  kubeconfig="$(kubeconfig_for)"

  run "${DEVBOT}" kube env "${PROJECT}"
  assert_success
  assert_output --partial "export KUBECONFIG=${kubeconfig}"
  assert_output --partial "# current-context: gete-staging-rw"
  assert_output --partial "AWS_KEY AWS_SECRET"
  refute_output --partial '${AWS_KEY}'
}

@test "run announces the default current-context" {
  write_kubeconfig

  run "${DEVBOT}" kube run "${PROJECT}" -- get namespaces
  assert_success
  assert_output --partial "kubectl context: gete-staging-rw"
  assert_output --partial "ARGS: --kubeconfig"
  assert_output --partial "get namespaces"
}

@test "run honours --context <name> in its banner" {
  write_kubeconfig

  run "${DEVBOT}" kube run "${PROJECT}" -- --context gete-prod-ro get pods
  assert_success
  assert_output --partial "kubectl context: gete-prod-ro"
}

@test "run honours --context=<name> in its banner" {
  write_kubeconfig

  run "${DEVBOT}" kube run "${PROJECT}" -- --context=gete-prod-ro get pods
  assert_success
  assert_output --partial "kubectl context: gete-prod-ro"
}

@test "run forwards the arguments after -- unchanged" {
  write_kubeconfig

  run "${DEVBOT}" kube run "${PROJECT}" -- logs -n core deploy/api --tail=5
  assert_success
  assert_output --partial "ARGS: --kubeconfig $(kubeconfig_for) logs -n core deploy/api --tail=5"
}

@test "contexts fails loudly when kubectl cannot read the kubeconfig" {
  write_kubeconfig
  cat > "${SANDBOX}/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "error: failed to load kubeconfig" >&2
exit 1
EOF
  chmod +x "${SANDBOX}/bin/kubectl"

  run "${DEVBOT}" kube contexts "${PROJECT}"
  assert_failure
  assert_output --partial "could not read contexts"
  assert_output --partial "$(kubeconfig_for)"
}

@test "run fails clearly when a credential_env variable is unset" {
  write_kubeconfig
  unset AWS_KEY

  run "${DEVBOT}" kube run "${PROJECT}" -- get namespaces
  assert_failure
  assert_output --partial "AWS_KEY is not set"
}

@test "run refuses arguments that would override the kubeconfig" {
  write_kubeconfig

  run "${DEVBOT}" kube run "${PROJECT}" -- --server https://example.com get pods
  assert_failure
  assert_output --partial "refusing '--server'"

  run "${DEVBOT}" kube run "${PROJECT}" -- --cluster other get pods
  assert_failure
  assert_output --partial "refusing '--cluster'"

  run "${DEVBOT}" kube run "${PROJECT}" -- --user other get pods
  assert_failure
  assert_output --partial "refusing '--user'"

  run "${DEVBOT}" kube run "${PROJECT}" -- -s https://example.com get pods
  assert_failure
  assert_output --partial "refusing '-s'"

  run "${DEVBOT}" kube run "${PROJECT}" -- --token secret get pods
  assert_failure
  assert_output --partial "refusing '--token'"
}

@test "help advertises the kube command" {
  run "${DEVBOT}" help
  assert_success
  assert_output --partial "kube"
}

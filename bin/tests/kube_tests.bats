#!/usr/bin/env bats
# =============================================================================
# bin/tests/kube_tests.bats
# `devbot kube` resolves the kubeconfig the k8s module generated for a project.
# The point of the command is that neither the hashed filename nor the context
# name has to be reconstructed, so the tests pin: the usage/error surface, and
# that `contexts` shows exactly the project's opt-in selection.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"

  export HOME="${SANDBOX}/home"
  mkdir -p "${HOME}/.kube/devbot"

  PROJECT="${SANDBOX}/proj"
  mkdir -p "${PROJECT}"
  cat > "${PROJECT}/.devbot.project.jsonc" <<'EOF'
{
  "project_name": "demo",
  "kubectl": ["gete-dev"]
}
EOF

  export DEV_BOT_GLOBAL_CONFIG="${SANDBOX}/global.jsonc"
  cat > "${DEV_BOT_GLOBAL_CONFIG}" <<'EOF'
{
  "kubectl": {
    "profile": "devbot-agent",
    "clusters": [
      { "name": "gete", "context": "gete-prod-ro", "region": "eu-central-1" },
      { "name": "gete-dev", "context": "gete-staging-rw", "region": "eu-central-1" }
    ]
  }
}
EOF

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

@test "contexts lists only the clusters the project opted into" {
  local kubeconfig
  kubeconfig="$(kubeconfig_for)"
  printf 'current-context: gete-staging-rw\n' > "${kubeconfig}"

  run "${DEVBOT}" kube contexts "${PROJECT}"
  assert_success
  assert_output --partial "gete-staging-rw"
  refute_output --partial "gete-prod-ro"
}

@test "env prints the kubeconfig path and never a credential" {
  local kubeconfig
  kubeconfig="$(kubeconfig_for)"
  printf 'current-context: gete-staging-rw\n' > "${kubeconfig}"
  printf 'AWS_ACCESS_KEY_ID=AKIASECRET\n' > "${HOME}/.kube/devbot/demo-credential.env"

  run "${DEVBOT}" kube env "${PROJECT}"
  assert_success
  assert_output --partial "export KUBECONFIG=${kubeconfig}"
  assert_output --partial "export KUBE_CONTEXT=gete-staging-rw"
  refute_output --partial "AKIASECRET"
}

@test "help advertises the kube command" {
  run "${DEVBOT}" help
  assert_success
  assert_output --partial "kube"
}

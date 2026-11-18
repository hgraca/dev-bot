#!/usr/bin/env bats
# =============================================================================
# bin/tests/kctl_tests.bats
# `devbot kctl` resolves the kubeconfig the k8s module generated for a project.
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

@test "bare 'kctl' prints usage and fails" {
  run "${DEVBOT}" kctl
  assert_failure
  assert_output --partial "Usage:"
  assert_output --partial "devbot kctl run"
}

@test "unknown kctl subcommand is refused, not guessed" {
  run "${DEVBOT}" kctl nonsense
  assert_failure
  assert_output --partial "unknown 'kctl' subcommand: nonsense"
}

@test "a missing generated kubeconfig names the reinit fix" {
  run "${DEVBOT}" kctl env "${PROJECT}"
  assert_failure
  assert_output --partial "no generated kubeconfig"
  assert_output --partial "devbot reinit"
}

@test "contexts reports the generated file, not the whole catalogue" {
  write_kubeconfig

  run "${DEVBOT}" kctl contexts "${PROJECT}"
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

  run "${DEVBOT}" kctl env "${PROJECT}"
  assert_success
  assert_output --partial "export KUBECONFIG=${kubeconfig}"
  assert_output --partial "# current-context: gete-staging-rw (gete-dev)"
  assert_output --partial "AWS_KEY AWS_SECRET"
  refute_output --partial '${AWS_KEY}'
}

@test "run announces the default current-context" {
  write_kubeconfig

  run "${DEVBOT}" kctl run "${PROJECT}" -- get namespaces
  assert_success
  assert_output --partial "kubectl context: gete-staging-rw (gete-dev)"
  assert_output --partial "ARGS: --kubeconfig"
  assert_output --partial "get namespaces"
}

@test "run honours --context <name> in its banner" {
  write_kubeconfig

  run "${DEVBOT}" kctl run "${PROJECT}" -- --context gete-prod-ro get pods
  assert_success
  assert_output --partial "kubectl context: gete-prod-ro (gete)"
}

@test "run honours --context=<name> in its banner" {
  write_kubeconfig

  run "${DEVBOT}" kctl run "${PROJECT}" -- --context=gete-prod-ro get pods
  assert_success
  assert_output --partial "kubectl context: gete-prod-ro (gete)"
}

@test "run forwards the arguments after -- unchanged" {
  write_kubeconfig

  run "${DEVBOT}" kctl run "${PROJECT}" -- logs -n core deploy/api --tail=5
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

  run "${DEVBOT}" kctl contexts "${PROJECT}"
  assert_failure
  assert_output --partial "could not read contexts"
  assert_output --partial "$(kubeconfig_for)"
}

@test "run fails clearly when a credential_env variable is unset" {
  write_kubeconfig
  unset AWS_KEY

  run "${DEVBOT}" kctl run "${PROJECT}" -- get namespaces
  assert_failure
  assert_output --partial "AWS_KEY is not set"
}

@test "run refuses arguments that would override the kubeconfig" {
  write_kubeconfig

  run "${DEVBOT}" kctl run "${PROJECT}" -- --server https://example.com get pods
  assert_failure
  assert_output --partial "refusing '--server'"

  run "${DEVBOT}" kctl run "${PROJECT}" -- --cluster other get pods
  assert_failure
  assert_output --partial "refusing '--cluster'"

  run "${DEVBOT}" kctl run "${PROJECT}" -- --user other get pods
  assert_failure
  assert_output --partial "refusing '--user'"

  run "${DEVBOT}" kctl run "${PROJECT}" -- -s https://example.com get pods
  assert_failure
  assert_output --partial "refusing '-s'"

  run "${DEVBOT}" kctl run "${PROJECT}" -- --token secret get pods
  assert_failure
  assert_output --partial "refusing '--token'"
}

@test "run refuses an attached -s endpoint override" {
  write_kubeconfig

  # pflag accepts a shorthand's value attached as well as after `=`.
  run "${DEVBOT}" kctl run "${PROJECT}" -- -shttps://other.example get pods
  assert_failure
  assert_output --partial "refusing '-shttps://other.example'"
  refute_output --partial "ARGS:"
}

@test "help advertises the kctl command" {
  run "${DEVBOT}" help
  assert_success
  assert_output --partial "kctl"
}

@test "run refuses a leading 'kubectl' and names the correct form" {
  write_kubeconfig

  # The mistake: the arguments are kubectl's own, so the binary must not be
  # repeated. Without the guard kubectl reads it as a plugin name and fails with
  # "flags cannot be placed before plugin name: --kubeconfig".
  run "${DEVBOT}" kctl run "${PROJECT}" -- kubectl get ns default
  assert_failure
  assert_output --partial "drop the leading 'kubectl'"
  assert_output --partial "get ns default"
  refute_output --partial "ARGS:"
}

@test "run refuses a leading 'kubectl' before resolving the kubeconfig" {
  # No generated kubeconfig in this test: the guard must fire first, so the
  # message names the real mistake instead of the missing file.
  run "${DEVBOT}" kctl run "${PROJECT}" -- kubectl get ns default
  assert_failure
  assert_output --partial "drop the leading 'kubectl'"
  refute_output --partial "no generated kubeconfig"
}

@test "run still forwards a command whose first argument is not kubectl" {
  write_kubeconfig

  # The guard is exact-match on the first argument only: `k` inside other
  # words, and subcommands that merely mention kubectl, are untouched.
  run "${DEVBOT}" kctl run "${PROJECT}" -- get ns default
  assert_success
  assert_output --partial "ARGS: --kubeconfig $(kubeconfig_for) get ns default"

  run "${DEVBOT}" kctl run "${PROJECT}" -- get pods -l app=kubectl-operator
  assert_success
  assert_output --partial "get pods -l app=kubectl-operator"
}

@test "help explains that the arguments are kubectl's own" {
  run "${DEVBOT}" kctl --help
  assert_success
  assert_output --partial "drop the leading"
}

# ── exec — the cluster-scoped form the kctl MCP servers call ─────────────────
# `exec` takes the cluster, resolves its context from the catalogue and applies
# it. The property that matters: a caller cannot retarget the call, and a
# cluster the render dropped is refused instead of falling back to another
# context — so one cluster's MCP server can never answer for another's.

@test "exec applies the named cluster's context" {
  write_kubeconfig

  run "${DEVBOT}" kctl exec gete-dev "${PROJECT}" -- get pods
  assert_success
  assert_output --partial "kubectl context: gete-staging-rw (gete-dev)"
  assert_output --partial "ARGS: --kubeconfig $(kubeconfig_for) --context gete-staging-rw get pods"
}

@test "exec takes the cluster from the catalogue, not from the current-context" {
  write_kubeconfig
  # The generated file's current-context is staging; a second context here
  # proves exec follows the cluster argument rather than the file default.
  cat > "$(kubeconfig_for)" <<'EOF'
apiVersion: v1
kind: Config
current-context: gete-staging-rw
contexts:
- context: { cluster: gete-dev, user: devbot-gete-dev }
  name: gete-staging-rw
- context: { cluster: gete, user: devbot-gete }
  name: gete-prod-ro
clusters: []
users: []
EOF
  # The shared stub answers `config get-contexts` with one fixed name; this
  # call needs both contexts read back from the file.
  cat > "${SANDBOX}/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"config get-contexts -o name"*) printf 'gete-staging-rw\ngete-prod-ro\n' ;;
  *) printf 'ARGS: %s\n' "$*" ;;
esac
EOF
  chmod +x "${SANDBOX}/bin/kubectl"

  run "${DEVBOT}" kctl exec gete "${PROJECT}" -- get namespaces
  assert_success
  assert_output --partial "kubectl context: gete-prod-ro (gete)"
  assert_output --partial "--context gete-prod-ro get namespaces"
}

@test "exec refuses a caller --context" {
  write_kubeconfig

  run "${DEVBOT}" kctl exec gete-dev "${PROJECT}" -- --context gete-prod-ro get pods
  assert_failure
  assert_output --partial "bound to one cluster"
  refute_output --partial "ARGS:"

  run "${DEVBOT}" kctl exec gete-dev "${PROJECT}" -- --context=gete-prod-ro get pods
  assert_failure
  assert_output --partial "bound to one cluster"
}

@test "exec refuses a cluster the catalogue does not declare" {
  write_kubeconfig

  run "${DEVBOT}" kctl exec nope "${PROJECT}" -- get pods
  assert_failure
  assert_output --partial "cluster 'nope' is not in the global kubectl catalogue"
}

@test "exec refuses a declared cluster the render left out" {
  write_kubeconfig

  # gete is in the catalogue, but only staging rendered into the file.
  run "${DEVBOT}" kctl exec gete "${PROJECT}" -- get pods
  assert_failure
  assert_output --partial "is not in $(kubeconfig_for)"
  assert_output --partial "devbot reinit"
}

@test "exec keeps run's override refusals" {
  write_kubeconfig

  run "${DEVBOT}" kctl exec gete-dev "${PROJECT}" -- --kubeconfig /tmp/other get pods
  assert_failure
  assert_output --partial "refusing '--kubeconfig'"

  run "${DEVBOT}" kctl exec gete-dev "${PROJECT}" -- kubectl get pods
  assert_failure
  assert_output --partial "drop the leading 'kubectl'"
}

#!/usr/bin/env bats

# src/agentic/k8s/tests/kubectl_memory_tests.bats
# Split from kubectl_init_tests.bats; setup, stubs and fixtures live in
# kubectl_test_helper.bash so a fixture is never copied into two files.
#
# The module's always-on instructions live in the project's vault, written by
# this module rather than hand-copied into project.md. The rule is the module's,
# not the render's: the file is written whenever the module is enabled.

setup() {
  load 'kubectl_test_helper'
  kubectl_setup
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

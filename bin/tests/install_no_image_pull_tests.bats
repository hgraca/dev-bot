#!/usr/bin/env bats
# =============================================================================
# bin/tests/install_no_image_pull_tests.bats
# Install must stay cheap. `bin/install.sh` runs every module's install.sh with
# `--all` (machine-wide provisioning), so an eager `docker pull` there downloads
# a multi-GB image for a module the machine may never enable — the ollama image
# alone is 4.8 GB. Images are pulled lazily by `docker compose up` on the first
# run that needs them.
#
# The announcement and the run-time behaviour are covered elsewhere:
# bin/tests/up_compose_opts_tests.bats (missing-image notice) and
# src/agentic/datasources/tests (install pulls nothing, declared or not).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  command -v grep >/dev/null 2>&1 || skip "grep not installed"
}

@test "no module install script ensures ollama models" {
  # `_ensure_ollama_models_detached` boots the ollama container through compose
  # when the API is down, which pulls the 4.8 GB image — the install-time
  # download this policy forbids. The model is ensured by module up.sh scripts.
  run grep -rn '_ensure_ollama_models_detached' \
    --include='install.sh' "${PROJECT_ROOT}/src"
  assert_failure
  [ -z "${output}" ]
}

@test "no module install script pulls a docker image" {
  run grep -rnE '(^|[[:space:];&|])docker pull([[:space:]]|$)' \
    --include='install.sh' "${PROJECT_ROOT}/src"
  assert_failure
  [ -z "${output}" ]
}

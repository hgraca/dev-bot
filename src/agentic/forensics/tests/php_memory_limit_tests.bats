#!/usr/bin/env bats
# =============================================================================
# src/agentic/forensics/tests/php_memory_limit_tests.bats
# The PHP plugin's PDepend memory limit: PDepend holds the whole project in
# memory, so the container image's 128M default OOMs on a large tree.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  PHP_PLUGIN="${MODULE_DIR}/langs/php/plugin.sh"
}

# The plugin prefers the project's own PDepend, so a stub vendor/ keeps this
# independent of the shared scratch engine; a stub `docker` keeps it Docker-free.
_fake_project() {
  local project="$1"
  mkdir -p "${project}/vendor/pdepend/pdepend"
  : >"${project}/vendor/autoload.php"
  printf '{"require":{"php":"^8.4"}}\n' >"${project}/composer.json"
  printf '<?php\nclass A {}\n' >"${project}/A.php"
  printf '{"project":"%s","files":["A.php"]}' "${project}" >"${project}/req.json"
}

# Echoes its argv, so the test sees the `php -d` flags the plugin actually builds.
_stub_docker() {
  local bin="$1"
  mkdir -p "${bin}"
  cat >"${bin}/docker" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "$@"
STUB
  chmod +x "${bin}/docker"
}

@test "php plugin units: the default limit is 1024M and reaches php -d" {
  local project bin
  project="$(mktemp -d)"
  bin="$(mktemp -d)"
  _fake_project "$project"
  _stub_docker "$bin"

  run env PATH="${bin}:${PATH}" bash "${PHP_PLUGIN}" units <"${project}/req.json"
  assert_success
  assert_output --partial "memory_limit=1024M"

  rm -rf "$project" "$bin"
}

@test "php plugin units: FORENSICS_PHP_MEMORY_LIMIT overrides the default" {
  local project bin
  project="$(mktemp -d)"
  bin="$(mktemp -d)"
  _fake_project "$project"
  _stub_docker "$bin"

  run env PATH="${bin}:${PATH}" FORENSICS_PHP_MEMORY_LIMIT=2G bash "${PHP_PLUGIN}" units <"${project}/req.json"
  assert_success
  assert_output --partial "memory_limit=2G"

  rm -rf "$project" "$bin"
}

@test "php plugin units: -1 lifts the limit entirely" {
  local project bin
  project="$(mktemp -d)"
  bin="$(mktemp -d)"
  _fake_project "$project"
  _stub_docker "$bin"

  run env PATH="${bin}:${PATH}" FORENSICS_PHP_MEMORY_LIMIT=-1 bash "${PHP_PLUGIN}" units <"${project}/req.json"
  assert_success
  assert_output --partial "memory_limit=-1"

  rm -rf "$project" "$bin"
}

@test "php plugin units: an invalid FORENSICS_PHP_MEMORY_LIMIT is an ERROR" {
  local project
  project="$(mktemp -d)"
  _fake_project "$project"

  run env FORENSICS_PHP_MEMORY_LIMIT=1QQ bash "${PHP_PLUGIN}" units <"${project}/req.json"
  assert_failure
  assert_output --partial "FORENSICS_PHP_MEMORY_LIMIT"

  rm -rf "$project"
}

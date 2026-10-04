#!/usr/bin/env bats
# Split from refactor_tests.bats — shared setup()/helpers come from the load.
load 'refactor_test_helper'

# ── Safety gates (T12) ─────────────────────────────────────────────────────────


@test "safety: refuses --apply on a dirty working tree" {
  command -v git >/dev/null 2>&1 || skip "git not installed"

  local repo
  repo="$(mktemp -d)"
  _make_repo "${repo}" dirty

  run bash -c "cd '${repo}' && REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang rename --class X --method a --to b --apply"
  rm -rf "${repo}"

  assert_failure
  assert_output --partial "working tree is dirty"
}

@test "safety: --force overrides the dirty-tree refusal" {
  command -v git >/dev/null 2>&1 || skip "git not installed"

  local repo
  repo="$(mktemp -d)"
  _make_repo "${repo}" dirty

  run bash -c "cd '${repo}' && REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang rename --class X --method a --to b --apply --force"
  rm -rf "${repo}"

  assert_success
}

@test "safety: a dry run is allowed on a dirty working tree" {
  command -v git >/dev/null 2>&1 || skip "git not installed"

  local repo
  repo="$(mktemp -d)"
  _make_repo "${repo}" dirty

  run bash -c "cd '${repo}' && REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang rename --class X --method a --to b"
  rm -rf "${repo}"

  assert_success
}

@test "end-to-end: the tool itself renames through the real php plugin" {
  _e2e_ready || skip "docker + scratch Rector not available"

  # The full user path: core (registry, guard, mapping) -> php plugin -> Rector.
  # The other end-to-end tests call the plugin directly; this one does not.
  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  git -C "${work}" init -q

  run bash -c "cd '${work}' && bash '${TOOL}' --lang php rename --class 'Demo\\Greeter' --method greet --to salute --apply"

  local decl call
  decl="$(grep -c 'function salute' "${work}/src/Greeter.php" || true)"
  call="$(grep -c '\->salute(' "${work}/src/UseGreeter.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "## refactor: rename"
  assert_output --partial "Renamed greet -> salute"
  [ "${decl}" = "1" ]
  [ "${call}" = "1" ]
}

@test "end-to-end: a vendor/ decoy outside the composer roots is never rewritten" {
  _e2e_ready || skip "docker + scratch Rector not available"

  # Regression guard: Rector is scoped to the composer autoload roots precisely
  # so it never descends into vendor/, which it does not exclude by default and
  # would otherwise rewrite. The decoy carries a same-named method. It is created
  # here rather than committed because the repo gitignores vendor/.
  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  mkdir -p "${work}/vendor/acme"
  cat > "${work}/vendor/acme/Decoy.php" <<'PHP'
<?php

declare(strict_types=1);

namespace Acme;

final class Decoy
{
    public function greet(): string
    {
        return 'decoy';
    }
}
PHP

  _req rename-method 'Demo\Greeter' greet salute > "${work}/request.json"
  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local decoy decl
  decoy="$(grep -c 'function greet' "${work}/vendor/acme/Decoy.php" || true)"
  decl="$(grep -c 'function salute' "${work}/src/Greeter.php" || true)"
  rm -rf "${work}"

  assert_success
  # The dependency keeps its name; the in-scope declaration moved.
  [ "${decoy}" = "1" ]
  [ "${decl}" = "1" ]
}

@test "end-to-end: composer autoload-dev brings tests/ into scope" {
  _e2e_ready || skip "docker + scratch Rector not available"

  # Regression guard for the scope gap: renaming an interface method must also
  # rewrite the implementor declared under tests/ (the fatal case), not just the
  # call sites the src/-only scope used to reach.
  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/scope-demo/." "${work}/"
  _req rename-method 'Demo\Port' emit publish > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local port adapter double call
  port="$(grep -c 'function publish' "${work}/src/Port.php" || true)"
  adapter="$(grep -c 'function publish' "${work}/src/Adapter.php" || true)"
  double="$(grep -c 'function publish' "${work}/tests/AdapterDouble.php" || true)"
  call="$(grep -c '\->publish(' "${work}/tests/PortTest.php" || true)"
  rm -rf "${work}"

  assert_success
  [ "${port}" = "1" ]
  [ "${adapter}" = "1" ]
  [ "${double}" = "1" ]
  [ "${call}" = "1" ]
}

@test "end-to-end: a short --class resolves to its FQCN and renames" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-method 'Greeter' greet salute > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local decl call
  decl="$(grep -c 'function salute' "${work}/src/Greeter.php" || true)"
  call="$(grep -c '\->salute(' "${work}/src/UseGreeter.php" || true)"
  rm -rf "${work}"

  assert_success
  [ "${decl}" = "1" ]
  [ "${call}" = "1" ]
}

@test "end-to-end: a rename that matches nothing reports a notice and exits 0" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-method 'Demo\Greeter' nope yep > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  assert_output --partial "no occurrences"
}

@test "end-to-end: the core report states a rename that matched nothing" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  git -C "${work}" init -q

  run bash -c "cd '${work}' && bash '${TOOL}' --lang php rename --class 'Demo\\Greeter' --method nope --to yep"
  rm -rf "${work}"

  assert_success
  assert_output --partial "Notice:"
  assert_output --partial "no occurrences"
}

@test "end-to-end: an apply reports the doc-block reference it did not rewrite" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/scope-demo/." "${work}/"
  _req rename-method 'Demo\Port' emit publish > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local doc
  doc="$(grep -c 'Port::emit' "${work}/tests/PortTest.php" || true)"
  rm -rf "${work}"

  assert_success
  [ "${doc}" = "1" ]
  assert_output --partial "unrewritten_references"
  assert_output --partial "@see Port::emit"
}


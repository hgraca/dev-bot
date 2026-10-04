#!/usr/bin/env bats
# Split from refactor_tests.bats — shared setup()/helpers come from the load.
load 'refactor_test_helper'

# ── S1: string references ──────────────────────────────────────────────────────

@test "ops.py string-refs: finds the old name inside a quoted string" {
  run bash -c "printf '%s' '{\"op\":\"rename-class\",\"from\":\"Widget\",\"to\":\"Gadget\",\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' string-refs"

  assert_success
  assert_output --partial "StringRegistry.php"
  assert_output --partial "Widget"
}

@test "ops.py string-refs: nothing to report when the name appears in no string" {
  run bash -c "printf '%s' '{\"op\":\"rename-class\",\"from\":\"NoSuchClass\",\"to\":\"Gadget\",\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' string-refs"

  assert_success
  assert_output --partial '"hits": []'
}

@test "end-to-end: a class rename reports the string reference it cannot rewrite" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-class '' Widget Gadget > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local leftover
  leftover="$(grep -c "'Widget'" "${work}/src/StringRegistry.php" || true)"
  rm -rf "${work}"

  assert_success
  # The class and its file moved, and the string no rule can rewrite is reported
  # rather than silently left behind.
  assert_output --partial '"string_references"'
  assert_output --partial "StringRegistry.php"
  [ "${leftover}" = "1" ]
}

# ── S2: idempotence ────────────────────────────────────────────────────────────

@test "end-to-end: an apply verifies itself and a re-plan finds nothing left" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-function '' demoHelper assistHelper > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  assert_success
  # The post-apply verification pass found nothing left over.
  refute_output --partial "remaining_changes"

  # A re-plan finds nothing either — which also proves the namespace still
  # resolves after the declaration was renamed.
  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  assert_output --partial "in 0 file(s)"
}

# ── R1: rename-string and rename-class-constant ────────────────────────────────

@test "ops.py render: rename-string is a bare map with no declaration step" {
  run bash -c "printf '%s' '{\"op\":\"rename-string\",\"from\":\"demo_max_key\",\"to\":\"demo_ceiling_key\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render 0"

  assert_success
  assert_output --partial "RenameStringRector::class"
  assert_output --partial "'demo_max_key' => 'demo_ceiling_key'"
  # A literal has no declaration, so the usages rule is complete.
  refute_output --partial "RenameDeclarationRector"
}

@test "end-to-end: rename-string rewrites the literal" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-string '' demo_max_key demo_ceiling_key > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local gone now
  gone="$(grep -c 'demo_max_key' "${work}/src/LimitHolder.php" || true)"
  now="$(grep -c 'demo_ceiling_key' "${work}/src/LimitHolder.php" || true)"
  rm -rf "${work}"

  assert_success
  [ "${gone}" = "0" ]
  [ "${now}" = "1" ]
}

@test "ops.py render: rename-class-constant adds the declaration step" {
  run bash -c "printf '%s' '{\"op\":\"rename-class-constant\",\"class\":\"Demo\\\\LimitHolder\",\"from\":\"DEMO_MAX\",\"to\":\"DEMO_CEILING\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render 1"

  assert_success
  assert_output --partial "RenameDeclarationRector::class"
  assert_output --partial "'kind' => 'class-constant'"
}

@test "end-to-end: rename-class-constant rewrites the declaration and the fetch" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-class-constant 'Demo\LimitHolder' DEMO_MAX DEMO_CEILING > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local decl fetch stale
  decl="$(grep -c 'const DEMO_CEILING' "${work}/src/LimitHolder.php" || true)"
  fetch="$(grep -c 'self::DEMO_CEILING' "${work}/src/LimitHolder.php" || true)"
  stale="$(grep -c 'DEMO_MAX' "${work}/src/LimitHolder.php" || true)"
  rm -rf "${work}"

  assert_success
  # The fetch rule rewrites the usage; the declaration step is ours.
  [ "${decl}" = "1" ]
  [ "${fetch}" = "1" ]
  [ "${stale}" = "0" ]
}

# ── C1: the risk class ─────────────────────────────────────────────────────────

@test "ops.py meta: every op declares a risk class" {
  run python3 "${MODULE_DIR}/langs/php/ops.py" meta
  assert_success

  printf '%s' "${output}" | python3 -c '
import json, sys
m = json.load(sys.stdin)
natives = {native for kinds in m["map"].values() for native in kinds.values()}
assert set(m["risks"]) == natives, "every native op needs a risk"
assert set(m["requires"]) == natives, "every native op declares its inputs"
assert m["risks"]["rename-method"] == "rename", m
assert m["risks"]["privatize-final-class-constants"] == "cleanup", m
# Dropping a constructor parameter changes the callable, not just its body.
assert m["risks"]["remove-unused-constructor-params"] == "signature", m
assert set(m["risks"].values()) <= {"rename", "cleanup", "signature"}, m
'
}

@test "ops.py render: a signature-risk op still uses withRules" {
  run bash -c "printf '%s' '{\"op\":\"remove-unused-constructor-params\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render 0"

  assert_success
  assert_output --partial "withRules("
  assert_output --partial "RemoveUnusedConstructorParamRector::class"
}

@test "end-to-end: remove-unused-private-class-constants deletes only the unused one" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"remove-unused-private-class-constants","scope":["/app/src"]}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local gone kept
  gone="$(grep -c 'UNUSED_CONST' "${work}/src/CleanupTarget.php" || true)"
  kept="$(grep -c 'PROMOTABLE_CONST' "${work}/src/CleanupTarget.php" || true)"
  rm -rf "${work}"

  assert_success
  [ "${gone}" = "0" ]
  [ "${kept}" = "1" ]
}


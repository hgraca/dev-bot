#!/usr/bin/env bats
# Split from refactor_tests.bats — shared setup()/helpers come from the load.
load 'refactor_test_helper'

# ── Tier 2: cleanup ops (C1 + C2) ──────────────────────────────────────────────

@test "ops.py render: a cleanup op emits withRules and takes no from/to" {
  run bash -c "printf '%s' '{\"op\":\"remove-unused-private-methods\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render 0"

  assert_success
  assert_output --partial "withRules("
  assert_output --partial "RemoveUnusedPrivateMethodRector::class"
  refute_output --partial "withConfiguredRule"
}

@test "ops.py meta: declares per-op requirements" {
  run python3 "${MODULE_DIR}/langs/php/ops.py" meta
  assert_success

  printf '%s' "${output}" | python3 -c '
import json, sys
m = json.load(sys.stdin)
assert m["requires"]["rename-method"] == ["class", "from", "to"], m
assert m["requires"]["rename-function"] == ["from", "to"], m
assert m["requires"]["remove-unused-private-methods"] == [], m
'
}

@test "core: an op missing a required input is rejected before dispatch" {
  run bash "${TOOL}" --lang php rename --class 'Demo\Greeter' --method greet

  assert_failure
  assert_output --partial "requires --to"
}

@test "end-to-end: remove-unused-private-methods deletes only the unused one" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"remove-unused-private-methods","scope":["/app/src"]}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local gone kept
  gone="$(grep -c 'unusedMethod' "${work}/src/CleanupTarget.php" || true)"
  kept="$(grep -c 'function used' "${work}/src/CleanupTarget.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"ok": true'
  [ "${gone}" = "0" ]
  [ "${kept}" = "1" ]
}

@test "end-to-end: remove-unused-private-properties deletes only the unused one" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"remove-unused-private-properties","scope":["/app/src"]}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local gone kept
  gone="$(grep -c 'unusedProperty' "${work}/src/CleanupTarget.php" || true)"
  kept="$(grep -c 'promotable' "${work}/src/CleanupTarget.php" || true)"
  rm -rf "${work}"

  assert_success
  [ "${gone}" = "0" ]
  [ "${kept}" = "2" ]
}

@test "end-to-end: privatize-final-class-properties tightens visibility" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"privatize-final-class-properties","scope":["/app/src"]}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local tightened
  tightened="$(grep -c 'private string \$promotable' "${work}/src/CleanupTarget.php" || true)"
  rm -rf "${work}"

  assert_success
  [ "${tightened}" = "1" ]
}

# ── D3: rename-constant ────────────────────────────────────────────────────────

@test "ops.py render: rename-constant step 0 is a bare map" {
  run bash -c "printf '%s' '{\"op\":\"rename-constant\",\"from\":\"DEMO_LIMIT\",\"to\":\"RENAMED_LIMIT\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render 0"

  assert_success
  assert_output --partial "RenameConstantRector::class"
  assert_output --partial "'DEMO_LIMIT' => 'RENAMED_LIMIT'"
  # A qualified key is rejected by the rule outright, so it must stay bare.
  refute_output --partial "Demo\\\\DEMO_LIMIT"
  refute_output --partial "RenameDeclarationRector"
}

@test "ops.py render: rename-constant step 1 is the constant declaration" {
  run bash -c "printf '%s' '{\"op\":\"rename-constant\",\"from\":\"DEMO_LIMIT\",\"to\":\"RENAMED_LIMIT\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render 1"

  assert_success
  assert_output --partial "RenameDeclarationRector::class"
  assert_output --partial "'kind' => 'constant'"
}

@test "end-to-end: rename-constant rewrites the declaration and the usage" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-constant '' DEMO_LIMIT RENAMED_LIMIT > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local decl stale used
  decl="$(grep -c 'const RENAMED_LIMIT' "${work}/src/Constants.php" || true)"
  stale="$(grep -c 'const DEMO_LIMIT' "${work}/src/Constants.php" || true)"
  used="$(grep -c 'RENAMED_LIMIT' "${work}/src/UsesConstant.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"ok": true'
  [ "${decl}" = "1" ]
  [ "${stale}" = "0" ]
  [ "${used}" = "1" ]
}

# ── D4: rename-class (declaration + references + file move) ────────────────────

@test "ops.py render: rename-class step 0 is the qualified reference map" {
  run bash -c "printf '%s' '{\"op\":\"rename-class\",\"from\":\"Widget\",\"to\":\"Gadget\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render 0"

  assert_success
  assert_output --partial "RenameClassRector::class"
  assert_output --partial "Gadget"
  refute_output --partial "RenameDeclarationRector"
}

@test "ops.py move-target: reports the file a class rename must move" {
  run bash -c "printf '%s' '{\"op\":\"rename-class\",\"from\":\"Widget\",\"to\":\"Gadget\",\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"

  assert_success
  assert_output --partial "Widget.php"
  assert_output --partial "Gadget.php"
}

@test "ops.py move-target: silent for an op that moves no files" {
  run bash -c "printf '%s' '{\"op\":\"rename-method\",\"from\":\"greet\",\"to\":\"salute\",\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"

  assert_success
  [ -z "${output}" ]
}

@test "end-to-end: rename-class renames the declaration, references and file" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-class '' Widget Gadget > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local decl ref newfile oldfile
  decl="$(grep -c 'final class Gadget' "${work}/src/Gadget.php" 2>/dev/null || true)"
  ref="$(grep -c 'Gadget::make()' "${work}/src/UsesWidget.php" || true)"
  newfile="$(test -f "${work}/src/Gadget.php" && echo 1 || echo 0)"
  oldfile="$(test -f "${work}/src/Widget.php" && echo 1 || echo 0)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"file_move": "moved src/Widget.php -> src/Gadget.php"'
  # All three halves of a class rename: declaration, reference, and the file.
  [ "${decl}" = "1" ]
  [ "${ref}" = "1" ]
  [ "${newfile}" = "1" ]
  [ "${oldfile}" = "0" ]
}

# ── D5: move-class (namespace + file move) ─────────────────────────────────────

@test "ops.py move-target: a class move reports the namespaces and the new directory" {
  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"

  assert_success
  assert_output --partial '"namespace_from": "Demo"'
  assert_output --partial "Frontend"
  assert_output --partial "src/Frontend/Widget.php"
}

@test "end-to-end: move-class moves the file and re-namespaces only that file" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req move-class '' 'Demo\Widget' 'Demo\Frontend\Widget' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local moved oldgone ns others ref
  moved="$(test -f "${work}/src/Frontend/Widget.php" && echo 1 || echo 0)"
  oldgone="$(test -f "${work}/src/Widget.php" && echo 0 || echo 1)"
  ns="$(grep -c '^namespace Demo\\Frontend;' "${work}/src/Frontend/Widget.php" || true)"
  others="$(grep -c '^namespace Demo;' "${work}/src/Greeter.php" || true)"
  ref="$(grep -c 'Demo\\Frontend\\Widget::make()' "${work}/src/UsesWidget.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial 'moved src/Widget.php -> src/Frontend/Widget.php'
  # The moved file gains the new namespace...
  [ "${moved}" = "1" ]
  [ "${oldgone}" = "1" ]
  [ "${ns}" = "1" ]
  # ...and every other file in the namespace keeps the old one.
  [ "${others}" = "1" ]
  [ "${ref}" = "1" ]
  # A move keeps the class short name, so it cannot leave a reference behind.
  refute_output --partial "unrewritten_references"
}

@test "end-to-end: a move with no references reports no no-match notice" {
  _e2e_ready || skip "docker + scratch Rector not available"

  # Rector rewrites only references, so a class nothing refers to yields an empty
  # `files` while the move still succeeds — the no-match notice must not fire.
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Lonely {}' > "${work}/src/Lonely.php"

  _req move-class '' 'Demo\Lonely' 'Demo\Frontend\Lonely' > "${work}/request.json"
  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  assert_output --partial "would move"
  refute_output --partial "no occurrences"
}

@test "end-to-end: a successful rename carries no notice" {
  _e2e_ready || skip "docker + scratch Rector not available"

  # The declaration carries an inline attribute, which the resolution scan does
  # not recognise, so it reports "no declaration". Rector still parses and renames
  # it — a run that changed files needs no such notice.
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' '#[\Attribute] final class Holder' '{' '    public function old(): void {}' '}' > "${work}/src/Holder.php"
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Caller' '{' '    public function run(Holder $h): void { $h->old(); }' '}' > "${work}/src/Caller.php"

  _req rename-method 'Demo\Holder' old new > "${work}/request.json"
  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local decl call
  decl="$(grep -c 'function new' "${work}/src/Holder.php" || true)"
  call="$(grep -c '\->new(' "${work}/src/Caller.php" || true)"
  rm -rf "${work}"

  assert_success
  [ "${decl}" = "1" ]
  [ "${call}" = "1" ]
  refute_output --partial '"notice"'
}


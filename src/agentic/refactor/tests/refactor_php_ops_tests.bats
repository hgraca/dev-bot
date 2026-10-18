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

@test "end-to-end: --file picks the namespace for a same-short-name rename" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/A" "${work}/src/B"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo\A;' '' 'final class Caller {}' > "${work}/src/A/Caller.php"
  printf '%s\n' '<?php' '' 'namespace Demo\B;' '' 'final class Caller {}' > "${work}/src/B/Caller.php"

  run bash -c "cd '${work}' && bash '${TOOL}' rename --file src/A/Caller.php --kind class --from 'Caller' --to 'Runner' --apply --force --json"

  local renamed other
  renamed="$(grep -c 'final class Runner' "${work}/src/A/Runner.php" 2>/dev/null || true)"
  other="$(grep -c 'final class Caller' "${work}/src/B/Caller.php" 2>/dev/null || true)"
  rm -rf "${work}"

  assert_success
  [ "${renamed}" = "1" ]
  [ "${other}" = "1" ]
}

@test "ops.py move-target: a class move reports the namespaces and the new directory" {
  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"

  assert_success
  assert_output --partial '"namespace_from": "Demo"'
  assert_output --partial "Frontend"
  assert_output --partial "src/Frontend/Widget.php"
}

@test "ops.py move-target: a class move refuses an ambiguous declaration" {
  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  mkdir -p "${work}/src/Duplicate"
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/src/Duplicate/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_failure
  assert_output --partial '"error"'
  assert_output --partial 'ambiguous'
  refute_output --partial '"from"'
}

@test "ops.py move-target: overlapping roots do not duplicate a declaration" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/Sub"
  printf '%s\n' '<?php' '' 'namespace Demo\Sub;' '' 'final class Widget {}' > "${work}/src/Sub/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Sub\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\",\"src/Sub\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_success
  assert_output --partial 'src/Frontend/Widget.php'
  refute_output --partial 'ambiguous'
}

@test "ops.py move-target: a qualified from wins over a namesake in another namespace" {
  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  mkdir -p "${work}/src/Legacy"
  printf '%s\n' '<?php' '' 'namespace Demo\Legacy;' '' 'final class Widget {}' > "${work}/src/Legacy/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_success
  refute_output --partial '"error"'
  assert_output --partial 'src/Widget.php'
  assert_output --partial '"namespace_from": "Demo"'
  refute_output --partial 'src/Legacy/Widget.php'
}

@test "ops.py move-target: --file picks the declaration when from is unqualified" {
  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  mkdir -p "${work}/src/Legacy"
  printf '%s\n' '<?php' '' 'namespace Demo\Legacy;' '' 'final class Widget {}' > "${work}/src/Legacy/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"file\":\"src/Widget.php\",\"project\":\"${work}\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_success
  refute_output --partial '"error"'
  assert_output --partial 'src/Widget.php'
  assert_output --partial '"fqcn": "Demo\\Widget"'
  assert_output --partial '"namespace_from": "Demo"'
  refute_output --partial 'src/Legacy/Widget.php'
}

@test "ops.py move-target: a nested --file derives the root from the resolved FQCN" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/Legacy"
  printf '%s\n' '<?php' '' 'namespace Demo\Legacy;' '' 'final class Widget {}' > "${work}/src/Legacy/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"file\":\"src/Legacy/Widget.php\",\"project\":\"${work}\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_success
  assert_output --partial 'src/Frontend/Widget.php'
  assert_output --partial '"namespace_from": "Demo\\Legacy"'
  refute_output --partial 'src/Legacy/Frontend/Widget.php'
}

@test "ops.py move-target: a move resolves the target through composer's psr-4 map" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/lib"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/","Acme\\":"lib/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/src/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Acme\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\",\"lib\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_success
  assert_output --partial 'lib/Widget.php'
  assert_output --partial '"namespace_from": "Demo"'
  assert_output --partial '"namespace_to": "Acme"'
}

@test "ops.py move-target: a target with no psr-4 mapping is refused" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/lib"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/","Acme\\":"lib/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/src/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Other\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\",\"lib\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'PSR-4'
  refute_output --partial '"from"'
}

@test "ops.py move-target: a psr-4 prefix with several bases keeps the source base" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/legacy"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":["src/","legacy/"]}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/legacy/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\",\"legacy\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_success
  assert_output --partial 'legacy/Frontend/Widget.php'
  assert_output --partial '"namespace_from": "Demo"'
  refute_output --partial 'src/Frontend/Widget.php'
}

@test "ops.py move-target: a shadowing target in an earlier base is refused" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/Frontend" "${work}/legacy"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":["src/","legacy/"]}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/legacy/Widget.php"
  printf '%s\n' '<?php' '' 'namespace Demo\Frontend;' '' 'final class Other {}' > "${work}/src/Frontend/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\",\"legacy\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'destination already exists'
  refute_output --partial '"from"'
}

@test "ops.py move-target: a global source resolves a namespaced target mapping" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/lib"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Acme\\":"lib/"}}}
JSON
  printf '%s\n' '<?php' '' 'final class GlobalWidget {}' > "${work}/src/GlobalWidget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"GlobalWidget\",\"to\":\"Acme\\\\GlobalWidget\",\"project\":\"${work}\",\"roots\":[\"src\",\"lib\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_success
  assert_output --partial 'lib/GlobalWidget.php"'
  assert_output --partial '"namespace_to": "Acme"'
}

@test "ops.py move-target: a classmap source falls back to the legacy layout" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/legacy"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"},"classmap":["legacy/"]}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class LegacyWidget {}' > "${work}/legacy/LegacyWidget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\LegacyWidget\",\"to\":\"Demo\\\\Frontend\\\\LegacyWidget\",\"project\":\"${work}\",\"roots\":[\"src\",\"legacy\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_success
  assert_output --partial 'legacy/Frontend/LegacyWidget.php'
  assert_output --partial '"namespace_from": "Demo"'
}

@test "ops.py move-target: a global source with an unmapped target is refused" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/lib"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/","Acme\\":"lib/"}}}
JSON
  printf '%s\n' '<?php' '' 'final class GlobalWidget {}' > "${work}/src/GlobalWidget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"GlobalWidget\",\"to\":\"Other\\\\GlobalWidget\",\"project\":\"${work}\",\"roots\":[\"src\",\"lib\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'PSR-4'
  refute_output --partial '"from"'
}

@test "ops.py move-target: a source path that misses its psr-4 mapping is refused" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/Extra"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/src/Extra/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'PSR-4'
  refute_output --partial '"from"'
}

@test "ops.py move-target: a move to the global namespace clears namespace_to" {
  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Widget\",\"project\":\"${PHP_FIXTURES}/rename-demo\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"

  assert_success
  assert_output --partial '"namespace_from": "Demo"'
  assert_output --partial '"namespace_to": ""'
  assert_output --partial 'src/Widget.php'
  refute_output --partial 'src/Frontend'
}

@test "ops.py move-target: a class move refuses a changed short name" {
  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Gadget\",\"project\":\"${PHP_FIXTURES}/rename-demo\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"

  assert_failure
  assert_output --partial 'keeps the class name'
  refute_output --partial '"from"'
}

@test "ops.py move-target: a qualified from with no declaration refuses a namesake" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/Legacy"
  printf '%s\n' '<?php' '' 'namespace Demo\Legacy;' '' 'final class Widget {}' > "${work}/src/Legacy/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'no declaration'
  refute_output --partial 'Legacy/Widget.php'
  refute_output --partial '"from"'
}

@test "ops.py move-target: a class move refuses a missing declaration" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src"
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Other {}' > "${work}/src/Other.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_failure
  assert_output --partial '"error"'
  assert_output --partial 'no declaration of'
  refute_output --partial '"from"'
}

@test "ops.py move-target: a class move refuses a namespace that does not mirror the directory" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src"
  printf '%s\n' '<?php' '' 'namespace Demo\Wrong;' '' 'final class Widget {}' > "${work}/src/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Wrong\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_failure
  assert_output --partial '"error"'
  assert_output --partial 'PSR-4'
}

@test "ops.py move-target: a class move refuses an existing destination" {
  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  mkdir -p "${work}/src/Frontend"
  printf '%s\n' '<?php' '' 'namespace Demo\Frontend;' '' 'final class Other {}' > "${work}/src/Frontend/Widget.php"

  run bash -c "printf '%s' '{\"op\":\"move-class\",\"from\":\"Demo\\\\Widget\",\"to\":\"Demo\\\\Frontend\\\\Widget\",\"project\":\"${work}\",\"roots\":[\"src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' move-target"
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'destination already exists'
  refute_output --partial '"from"'
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

@test "end-to-end: a plan for a move with references still reports the move" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req move-class '' 'Demo\Widget' 'Demo\Frontend\Widget' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  assert_output --partial 'would move src/Widget.php -> src/Frontend/Widget.php'
}

@test "end-to-end: move --kind class moves the class across namespaces" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Demo\\Frontend\\Widget' --apply --force --json"

  local moved oldgone ns ref
  moved="$(test -f "${work}/src/Frontend/Widget.php" && echo 1 || echo 0)"
  oldgone="$(test -f "${work}/src/Widget.php" && echo 0 || echo 1)"
  ns="$(grep -c '^namespace Demo\\Frontend;' "${work}/src/Frontend/Widget.php" || true)"
  ref="$(grep -c 'Demo\\Frontend\\Widget::make()' "${work}/src/UsesWidget.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"file_move": "moved src/Widget.php -> src/Frontend/Widget.php"'
  [ "${moved}" = "1" ]
  [ "${oldgone}" = "1" ]
  [ "${ns}" = "1" ]
  [ "${ref}" = "1" ]
}

@test "end-to-end: move --kind class refuses a changed short name" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Demo\\Frontend\\Gadget' --apply --force --json 2>&1"

  local source gone
  source="$(test -f "${work}/src/Widget.php" && echo 1 || echo 0)"
  gone="$(test -f "${work}/src/Frontend/Gadget.php" && echo 1 || echo 0)"
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'keeps the class name'
  [ "${source}" = "1" ]
  [ "${gone}" = "0" ]
}

@test "end-to-end: a nested --file move derives the PSR-4 root from the resolved FQCN" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/Legacy"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo\Legacy;' '' 'final class Widget {}' > "${work}/src/Legacy/Widget.php"
  printf '%s\n' '<?php' '' 'namespace Demo\Legacy;' '' 'final class Caller' '{' '    public function run(Widget $widget): void' '    {' '    }' '}' > "${work}/src/Legacy/Caller.php"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Legacy/Widget.php --kind class --from 'Widget' --to 'Demo\\Frontend\\Widget' --apply --force --json"

  local moved nested oldgone ns ref
  moved="$(test -f "${work}/src/Frontend/Widget.php" && echo 1 || echo 0)"
  nested="$(test -f "${work}/src/Legacy/Frontend/Widget.php" && echo 1 || echo 0)"
  oldgone="$(test -f "${work}/src/Legacy/Widget.php" && echo 0 || echo 1)"
  ns="$(grep -c '^namespace Demo\\Frontend;' "${work}/src/Frontend/Widget.php" 2>/dev/null || true)"
  ref="$(grep -c 'Demo\\Frontend\\Widget' "${work}/src/Legacy/Caller.php" 2>/dev/null || true)"
  rm -rf "${work}"

  assert_success
  [ "${moved}" = "1" ]
  [ "${nested}" = "0" ]
  [ "${oldgone}" = "1" ]
  [ "${ns}" = "1" ]
  [ "${ref}" = "1" ]
}

@test "end-to-end: a class move resolves the target root from composer's psr-4 map" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/lib"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/","Acme\\":"lib/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/src/Widget.php"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Acme\\Widget' --apply --force --json"

  local moved oldgone ns
  moved="$(test -f "${work}/lib/Widget.php" && echo 1 || echo 0)"
  oldgone="$(test -f "${work}/src/Widget.php" && echo 0 || echo 1)"
  ns="$(grep -c '^namespace Acme;' "${work}/lib/Widget.php" 2>/dev/null || true)"
  rm -rf "${work}"

  assert_success
  [ "${moved}" = "1" ]
  [ "${oldgone}" = "1" ]
  [ "${ns}" = "1" ]
}

@test "end-to-end: a move to the global namespace removes the declaration" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Widget' --apply --force --json"

  local ns cls moved
  moved="$(test -f "${work}/src/Widget.php" && echo 1 || echo 0)"
  ns="$(grep -c '^namespace' "${work}/src/Widget.php" || true)"
  cls="$(grep -c 'final class Widget' "${work}/src/Widget.php" || true)"
  rm -rf "${work}"

  assert_success
  [ "${moved}" = "1" ]
  [ "${ns}" = "0" ]
  [ "${cls}" = "1" ]
}

@test "end-to-end: a move to global preserves multiline string contents" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"}}}
JSON
  cat > "${work}/src/Widget.php" <<'PHP'
<?php

namespace Demo;

final class Widget
{
    public function text(): string
    {
        return <<<'TXT'
a


b
TXT;
    }
}
PHP

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Widget' --apply --force --json"

  local preserved ns
  preserved="$(python3 -c 'import sys; print(1 if "a\n\n\nb" in open(sys.argv[1]).read() else 0)' "${work}/src/Widget.php")"
  ns="$(grep -c '^namespace' "${work}/src/Widget.php" || true)"
  rm -rf "${work}"

  assert_success
  [ "${preserved}" = "1" ]
  [ "${ns}" = "0" ]
}

@test "end-to-end: a move from the global namespace inserts the declaration" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"}}}
JSON
  printf '%s\n' '<?php' '' '// kept comment' 'declare(strict_types=1);' '' 'final class GlobalWidget {}' > "${work}/src/GlobalWidget.php"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/GlobalWidget.php --kind class --from 'GlobalWidget' --to 'Demo\\Frontend\\GlobalWidget' --apply --force --json"

  local moved oldgone ns cls order
  moved="$(test -f "${work}/src/Frontend/GlobalWidget.php" && echo 1 || echo 0)"
  oldgone="$(test -f "${work}/src/GlobalWidget.php" && echo 0 || echo 1)"
  ns="$(grep -c '^namespace Demo\\Frontend;' "${work}/src/Frontend/GlobalWidget.php" 2>/dev/null || true)"
  cls="$(grep -c 'final class GlobalWidget' "${work}/src/Frontend/GlobalWidget.php" 2>/dev/null || true)"
  order="$(python3 -c 'import sys; t = open(sys.argv[1]).read(); print(1 if t.index("// kept comment") < t.index("declare") < t.index("namespace") else 0)' "${work}/src/Frontend/GlobalWidget.php" 2>/dev/null || true)"
  rm -rf "${work}"

  assert_success
  [ "${moved}" = "1" ]
  [ "${oldgone}" = "1" ]
  [ "${ns}" = "1" ]
  [ "${cls}" = "1" ]
  [ "${order}" = "1" ]
}

@test "end-to-end: a global source moves to its mapped namespaced root" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/lib"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/","Acme\\":"lib/"}}}
JSON
  printf '%s\n' '<?php' '' 'final class GlobalWidget {}' > "${work}/src/GlobalWidget.php"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/GlobalWidget.php --kind class --from 'GlobalWidget' --to 'Acme\\GlobalWidget' --apply --force --json"

  local moved oldgone ns
  moved="$(test -f "${work}/lib/GlobalWidget.php" && echo 1 || echo 0)"
  oldgone="$(test -f "${work}/src/GlobalWidget.php" && echo 0 || echo 1)"
  ns="$(grep -c '^namespace Acme;' "${work}/lib/GlobalWidget.php" 2>/dev/null || true)"
  rm -rf "${work}"

  assert_success
  [ "${moved}" = "1" ]
  [ "${oldgone}" = "1" ]
  [ "${ns}" = "1" ]
}

@test "end-to-end: an ambiguous class move aborts before rewriting references" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  mkdir -p "${work}/src/Duplicate"
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/src/Duplicate/Widget.php"

  local uses_before widget_before
  uses_before="$(cat "${work}/src/UsesWidget.php")"
  widget_before="$(cat "${work}/src/Widget.php")"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Demo\\Frontend\\Widget' --apply --force --json 2>&1"

  local oldfile newfile unchanged
  oldfile="$(test -f "${work}/src/Widget.php" && echo 1 || echo 0)"
  newfile="$(test -f "${work}/src/Frontend/Widget.php" && echo 1 || echo 0)"
  unchanged=1
  [ "$(cat "${work}/src/UsesWidget.php" 2>/dev/null)" = "${uses_before}" ] || unchanged=0
  [ "$(cat "${work}/src/Widget.php" 2>/dev/null)" = "${widget_before}" ] || unchanged=0
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'ambiguous'
  # Nothing was rewritten: both files are byte-identical to their pre-run state.
  [ "${oldfile}" = "1" ]
  [ "${newfile}" = "0" ]
  [ "${unchanged}" = "1" ]
}

@test "end-to-end: a move with no declaration aborts and leaves the tree untouched" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Missing.php --kind class --from 'Demo\\Missing' --to 'Demo\\Frontend\\Missing' --apply --force --json 2>&1"

  local oldfile newfile
  oldfile="$(test -f "${work}/src/Widget.php" && echo 1 || echo 0)"
  newfile="$(test -f "${work}/src/Frontend/Missing.php" && echo 1 || echo 0)"
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'no declaration'
  [ "${oldfile}" = "1" ]
  [ "${newfile}" = "0" ]
}

@test "end-to-end: a move refuses to overwrite an existing destination" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  mkdir -p "${work}/src/Frontend"
  printf '%s\n' '<?php' '' 'namespace Demo\Frontend;' '' 'final class Other {}' > "${work}/src/Frontend/Widget.php"

  local source_before uses_before dest_before
  source_before="$(cat "${work}/src/Widget.php")"
  uses_before="$(cat "${work}/src/UsesWidget.php")"
  dest_before="$(cat "${work}/src/Frontend/Widget.php")"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Demo\\Frontend\\Widget' --apply --force --json 2>&1"

  local unchanged
  unchanged=1
  [ "$(cat "${work}/src/Widget.php" 2>/dev/null)" = "${source_before}" ] || unchanged=0
  [ "$(cat "${work}/src/UsesWidget.php" 2>/dev/null)" = "${uses_before}" ] || unchanged=0
  [ "$(cat "${work}/src/Frontend/Widget.php" 2>/dev/null)" = "${dest_before}" ] || unchanged=0
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'destination already exists'
  [ "${unchanged}" = "1" ]
}

@test "end-to-end: a failed Rector step never relocates the file" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"

  local source_before uses_before
  source_before="$(cat "${work}/src/Widget.php")"
  uses_before="$(cat "${work}/src/UsesWidget.php")"

  # localhost:1 refuses the connection, so every Rector step exits non-zero.
  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Demo\\Frontend\\Widget' --image 'localhost:1/never:1' --apply --force --json 2>&1"

  local moved unchanged
  moved="$(test -f "${work}/src/Frontend/Widget.php" && echo 1 || echo 0)"
  unchanged=1
  [ "$(cat "${work}/src/Widget.php" 2>/dev/null)" = "${source_before}" ] || unchanged=0
  [ "$(cat "${work}/src/UsesWidget.php" 2>/dev/null)" = "${uses_before}" ] || unchanged=0
  rm -rf "${work}"

  assert_failure
  assert_output --partial 'ERROR:'
  [ "${moved}" = "0" ]
  [ "${unchanged}" = "1" ]
  refute_output --partial 'moved src/Widget.php'
}

@test "end-to-end: a Rector document with errors blocks relocation" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/vendor/bin"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/src/Widget.php"
  cat > "${work}/vendor/bin/rector" <<'PHP'
<?php
echo '{"totals":{"errors":1}}';
PHP
  chmod +x "${work}/vendor/bin/rector"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Demo\\Frontend\\Widget' --image php:8.5-cli --apply --force --json 2>&1"

  local moved ns
  moved="$(test -f "${work}/src/Frontend/Widget.php" && echo 1 || echo 0)"
  ns="$(grep -c '^namespace Demo;' "${work}/src/Widget.php" 2>/dev/null || true)"
  rm -rf "${work}"

  assert_failure
  [ "${moved}" = "0" ]
  [ "${ns}" = "1" ]
}

@test "end-to-end: malformed Rector output blocks relocation" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/vendor/bin"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/src/Widget.php"
  cat > "${work}/vendor/bin/rector" <<'PHP'
<?php
echo 'not json';
PHP
  chmod +x "${work}/vendor/bin/rector"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Demo\\Frontend\\Widget' --image php:8.5-cli --apply --force --json 2>&1"

  local moved ns
  moved="$(test -f "${work}/src/Frontend/Widget.php" && echo 1 || echo 0)"
  ns="$(grep -c '^namespace Demo;' "${work}/src/Widget.php" 2>/dev/null || true)"
  rm -rf "${work}"

  assert_failure
  [ "${moved}" = "0" ]
  [ "${ns}" = "1" ]
}

@test "plugin: a failed apply reports ok false and exits non-zero" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"move-class","from":"Demo\\Widget","to":"Demo\\Frontend\\Widget","image":"localhost:1/never:1"}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"
  rm -rf "${work}"

  assert_failure
  assert_output --partial '"ok": false'
}

@test "end-to-end: a failed later step rolls the earlier step back" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/vendor/bin"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Caller {}' > "${work}/src/Caller.php"
  cat > "${work}/vendor/bin/rector" <<'PHP'
<?php
$counter = '/app/.rector-calls';
$calls = is_file($counter) ? (int) file_get_contents($counter) : 0;
$calls++;
file_put_contents($counter, (string) $calls);
if ($calls >= 2) {
    fwrite(STDERR, "second step failed\n");
    exit(1);
}
file_put_contents('/app/src/Caller.php', "<?php\n\nnamespace Demo;\n\n// rewritten by step 1\n");
echo '{"changed_files":["src/Caller.php"]}';
PHP
  chmod +x "${work}/vendor/bin/rector"

  local original
  original="$(cat "${work}/src/Caller.php")"

  run bash -c "cd '${work}' && bash '${TOOL}' rename --file src/Caller.php --kind class --from 'Demo\\Caller' --to 'Demo\\Gadget' --image php:8.5-cli --apply --force --json 2>&1"

  local restored
  restored="$(cat "${work}/src/Caller.php")"
  rm -rf "${work}"

  assert_failure
  [ "${restored}" = "${original}" ]
}

@test "end-to-end: rollback with overlapping roots keeps one snapshot" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/Sub" "${work}/vendor/bin"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\Sub\\":"src/Sub/","Demo\\":"src/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo\Sub;' '' 'final class Caller {}' > "${work}/src/Sub/Caller.php"
  cat > "${work}/vendor/bin/rector" <<'PHP'
<?php
$counter = '/app/.rector-calls';
$calls = is_file($counter) ? (int) file_get_contents($counter) : 0;
$calls++;
file_put_contents($counter, (string) $calls);
if ($calls >= 2) {
    fwrite(STDERR, "second step failed\n");
    exit(1);
}
file_put_contents('/app/src/Sub/Caller.php', "<?php\n\nnamespace Demo\\Sub;\n\n// rewritten by step 1\n");
echo '{"changed_files":["src/Sub/Caller.php"]}';
PHP
  chmod +x "${work}/vendor/bin/rector"

  local original
  original="$(cat "${work}/src/Sub/Caller.php")"

  run bash -c "cd '${work}' && bash '${TOOL}' rename --file src/Sub/Caller.php --kind class --from 'Caller' --to 'Runner' --image php:8.5-cli --apply --force --json 2>&1"

  local restored nested
  restored="$(cat "${work}/src/Sub/Caller.php")"
  nested="$(test -d "${work}/src/src" && echo 1 || echo 0)"
  rm -rf "${work}"

  assert_failure
  [ "${restored}" = "${original}" ]
  [ "${nested}" = "0" ]
}

@test "end-to-end: a failed relocation rolls the namespace rewrite back" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/lib"
  chmod 555 "${work}/lib"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Demo\\":"src/","Acme\\":"lib/"}}}
JSON
  printf '%s\n' '<?php' '' 'namespace Demo;' '' 'final class Widget {}' > "${work}/src/Widget.php"

  run bash -c "cd '${work}' && bash '${TOOL}' move --file src/Widget.php --kind class --from 'Demo\\Widget' --to 'Acme\\Widget' --image php:8.5-cli --apply --force --json 2>&1"

  local restored moved ns
  restored="$(test -f "${work}/src/Widget.php" && echo 1 || echo 0)"
  moved="$(test -f "${work}/lib/Widget.php" && echo 1 || echo 0)"
  ns="$(grep -c '^namespace Demo;' "${work}/src/Widget.php" 2>/dev/null || true)"
  chmod 755 "${work}/lib"
  rm -rf "${work}"

  assert_failure
  [ "${restored}" = "1" ]
  [ "${moved}" = "0" ]
  [ "${ns}" = "1" ]
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


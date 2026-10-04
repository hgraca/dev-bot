#!/usr/bin/env bats
# Split from refactor_tests.bats — shared setup()/helpers come from the load.
load 'refactor_test_helper'


@test "end-to-end (ts): privatize-members keeps an accessor pair together" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts privatize --class Base --apply"

  local getter setter
  # Only the setter is referenced, but the pair shares one accessibility.
  getter="$(grep -c 'private get accessor' "${work}/src/base.ts" || true)"
  setter="$(grep -c 'private set accessor' "${work}/src/base.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${getter}" = "1" ]
  [ "${setter}" = "1" ]
}

@test "end-to-end (ts): privatize-members reports an unused member and an exported class" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts privatize --class Base --apply"
  rm -rf "${work}"

  assert_success
  assert_output --partial "has no references in the project"
  assert_output --partial "may be consumed outside the project"
}

@test "end-to-end (ts): a privatize-members plan writes nothing" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts privatize --class Base"

  local still
  still="$(grep -cE '^  helper' "${work}/src/base.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "Would make"
  [ "${still}" = "1" ]
}

@test "end-to-end (ts): privatize-members sweeps the project when no class is named" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts privatize --apply"

  local base sub
  base="$(grep -c 'private internalOnly' "${work}/src/base.ts" || true)"
  # Sub.touch is unreferenced too, and a project-wide sweep reaches it.
  sub="$(grep -c 'private touch' "${work}/src/sub.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${base}" = "1" ]
  [ "${sub}" = "1" ]
}

@test "end-to-end (ts): privatize-members narrows every signature of an overloaded method" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts privatize --class Overloaded --apply"

  local signatures
  # Narrowing only the body leaves the overload signatures public, and TypeScript
  # requires a method's signatures to share one accessibility.
  signatures="$(grep -c 'private format' "${work}/src/overloaded.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${signatures}" = "3" ]
}

@test "end-to-end (ts): privatize-members leaves a member a merged interface also declares" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts privatize --class Merged --apply"

  local narrowed
  # The interface's signature sits outside the class, so narrowing only the class
  # half would leave the member half-public.
  narrowed="$(grep -c 'private describe' "${work}/src/merged.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${narrowed}" = "0" ]
}

@test "end-to-end (ts): privatize-members narrows a constructor parameter property" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts privatize --class Params --apply"

  local narrowed
  # getProperties() does not list a parameter property, but it is a class member.
  narrowed="$(grep -c 'constructor(private seed: number)' "${work}/src/params.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${narrowed}" = "1" ]
}

@test "end-to-end (ts): a privatize-members apply leaves the project compiling" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work tsc compiled
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"
  # The compiler the op is judged by, from the engine's own toolchain. A narrowed
  # member that is half-public only shows up here — the source looks fine.
  tsc="${MODULE_DIR}/../../../storage/refactor/ts/node_modules/typescript/bin/tsc"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts privatize --apply"
  compiled="$(cd "${work}" && node "${tsc}" --noEmit -p tsconfig.json >/dev/null 2>&1 && echo 0 || echo 1)"
  rm -rf "${work}"

  assert_success
  [ "${compiled}" = "0" ]
}

@test "end-to-end (ts): remove-unused-locals removes an unused declaration" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file src/locals.ts --apply"

  local removed kept shared
  removed="$(grep -c 'const removed' "${work}/src/locals.ts" || true)"
  kept="$(grep -c 'const used' "${work}/src/locals.ts" || true)"
  # A declaration sharing its statement must not take the statement with it.
  shared="$(grep -c 'const live' "${work}/src/locals.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${removed}" = "0" ]
  [ "${kept}" = "1" ]
  [ "${shared}" = "1" ]
}

@test "end-to-end (ts): remove-unused-locals keeps a declaration whose initialiser has effects" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file src/locals.ts --apply"

  local effects
  # Dropping the binding would drop the call with it.
  effects="$(grep -c 'const effects' "${work}/src/locals.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "may have side effects"
  [ "${effects}" = "1" ]
}

@test "end-to-end (ts): remove-unused-locals leaves a loop binding and an underscore name" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file src/locals.ts --apply"

  local binding ignored
  # A for-of binding is part of the loop, and `_` marks a binding as deliberately
  # unused.
  binding="$(grep -c 'for (const entry of values)' "${work}/src/locals.ts" || true)"
  ignored="$(grep -c 'const _ignored' "${work}/src/locals.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${binding}" = "1" ]
  [ "${ignored}" = "1" ]
}

@test "end-to-end (ts): remove-unused-locals keeps a declarator sharing its statement" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file src/mixed.ts --apply"

  local removed kept
  removed="$(grep -cE 'first|second' "${work}/src/mixed.ts" || true)"
  # Dropping the two unused declarators must leave the used one intact — re-reading
  # a statement's length after each removal makes it look fully removable.
  kept="$(grep -c 'kept' "${work}/src/mixed.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${removed}" = "0" ]
  [ "${kept}" = "2" ]
}

@test "end-to-end (ts): remove-unused-locals keeps a container whose contents have effects" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file src/purity.ts --apply"

  local container plain
  # A container is only as pure as what it holds.
  container="$(grep -cE 'const array|const object' "${work}/src/purity.ts" || true)"
  plain="$(grep -cE 'plainArray|plainObject' "${work}/src/purity.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${container}" = "2" ]
  [ "${plain}" = "0" ]
}

@test "end-to-end (ts): remove-unused-locals leaves a destructuring declaration" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file src/destructured.ts --apply"

  local kept
  # The declaration has no references of its own, but the names it binds are used.
  kept="$(grep -c 'const { first, second }' "${work}/src/destructured.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${kept}" = "1" ]
}

@test "end-to-end (ts): remove-unused-locals keeps a container with a computed key" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file src/computed.ts --apply"

  local kept removable
  kept="$(grep -c 'const computed' "${work}/src/computed.ts" || true)"
  removable="$(grep -c 'const plain' "${work}/src/computed.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "may have side effects"
  [ "${kept}" = "1" ]
  [ "${removable}" = "0" ]
}

@test "end-to-end (ts): remove-unused-locals leaves a using declaration" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/using-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file src/held.ts --apply"

  local kept
  # The disposal is the effect, whatever the initialiser looks like.
  kept="$(grep -c 'using res' "${work}/src/held.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${kept}" = "1" ]
}

@test "end-to-end (ts): a remove-unused-locals plan writes nothing" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file src/locals.ts"

  local still
  still="$(grep -c 'const removed' "${work}/src/locals.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "Would remove"
  [ "${still}" = "1" ]
}

@test "end-to-end (ts): remove-unused-params removes a parameter no caller supplies" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind param --file src/params.ts --apply"

  local removed kept
  removed="$(grep -c 'spare' "${work}/src/params.ts" || true)"
  # Every caller already omits the argument, so no signature anyone relies on moves.
  kept="$(grep -c 'punctuation' "${work}/src/params.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${removed}" = "0" ]
  [ "${kept}" = "1" ]
}

@test "end-to-end (ts): remove-unused-params removes it from every overload signature" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind param --file src/params.ts --apply"

  local flag
  # Both signatures and the implementation carry the parameter; leaving any behind
  # does not compile.
  flag="$(grep -c 'flag' "${work}/src/params.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${flag}" = "0" ]
}

@test "end-to-end (ts): remove-unused-params leaves an underscore parameter and a value-position function" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind param --file src/params.ts --apply"

  local ignored value
  # `_` marks a parameter as deliberately unused; a function held as a value has an
  # arity no call site constrains.
  ignored="$(grep -c '_second' "${work}/src/params.ts" || true)"
  value="$(grep -c 'solo' "${work}/src/params.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "used as a value"
  [ "${ignored}" = "1" ]
  [ "${value}" = "1" ]
}

@test "end-to-end (ts): remove-unused-params handles an arrow function" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind param --file src/arrows.ts --apply"

  local arrow expression
  # An arrow has no name in the engine's API; reading one must not crash the op.
  arrow="$(grep -c 'unused' "${work}/src/arrows.ts" || true)"
  expression="$(grep -c 'spare' "${work}/src/arrows.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${arrow}" = "0" ]
  [ "${expression}" = "0" ]
}

@test "end-to-end (ts): remove-unused-params leaves a parameter bind can still supply" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind param --file src/bound.ts --apply"

  local kept
  # `rebound` decides the arguments, so this reference says nothing about `spare`.
  kept="$(grep -c 'spare' "${work}/src/bound.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "used as a value"
  [ "${kept}" = "1" ]
}

@test "end-to-end (ts): remove-unused-params warns when an exported surface changes" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind param --file src/arrows.ts --apply"
  rm -rf "${work}"

  assert_success
  # `viaArrow` is an exported const, so its signature is a public surface even
  # though the export sits on the declaration rather than the function.
  assert_output --partial "may be called outside the project"
  assert_output --partial "viaArrow"
}

@test "end-to-end (ts): remove-unused-params keeps a parameter whose default has effects" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind param --file src/defaults.ts --apply"

  local kept removable
  kept="$(grep -c 'spare' "${work}/src/defaults.ts" || true)"
  # A default that can only produce a value still goes.
  removable="$(grep -c 'unused' "${work}/src/defaults.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "may have side effects"
  [ "${kept}" = "1" ]
  [ "${removable}" = "0" ]
}

@test "end-to-end (ts): a T8 removal leaves the project compiling" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work tsc compiled
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"
  tsc="${MODULE_DIR}/../../../storage/refactor/ts/node_modules/typescript/bin/tsc"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file src/locals.ts --apply && bash '${TOOL}' --lang ts remove-unused --kind param --file src/params.ts --apply"
  compiled="$(cd "${work}" && node "${tsc}" --noEmit -p tsconfig.json >/dev/null 2>&1 && echo 0 || echo 1)"
  rm -rf "${work}"

  assert_success
  [ "${compiled}" = "0" ]
}

@test "end-to-end (ts): a T8 removal refuses a file outside the project" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  # The project is mounted at /app in the container, so anything else is not ours.
  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file /etc/hosts --apply"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "outside the project"
}

@test "end-to-end (ts): a T8 removal accepts an absolute path inside the project" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind local --file /app/src/mixed.ts --apply"

  local removed
  removed="$(grep -cE 'first|second' "${work}/src/mixed.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${removed}" = "0" ]
}

@test "end-to-end (ts): a remove-unused-params plan writes nothing" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts remove-unused --kind param --file src/params.ts"

  local still
  still="$(grep -c 'spare' "${work}/src/params.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "Would remove"
  [ "${still}" = "1" ]
}

@test "end-to-end (ts): promote-readonly makes a constructor-only property readonly" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/readonly-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts promote-readonly --apply"

  local ctor initialised promoted untouched
  ctor="$(grep -c 'readonly ctorOnly' "${work}/src/base.ts" || true)"
  # Never written at all is still immutable.
  initialised="$(grep -c 'readonly initialised' "${work}/src/base.ts" || true)"
  # A constructor parameter property is a member too.
  promoted="$(grep -c 'readonly promoted' "${work}/src/base.ts" || true)"
  untouched="$(grep -c 'readonly already' "${work}/src/base.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${ctor}" = "1" ]
  [ "${initialised}" = "1" ]
  [ "${promoted}" = "1" ]
  [ "${untouched}" = "1" ]
}

@test "end-to-end (ts): promote-readonly leaves a property written outside the constructor" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/readonly-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts promote-readonly --apply"

  local method nested
  method="$(grep -c 'readonly methodWritten' "${work}/src/base.ts" || true)"
  # The arrow inside the constructor runs later; a readonly field cannot be
  # assigned there.
  nested="$(grep -c 'readonly nested' "${work}/src/base.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "methodWritten"
  [ "${method}" = "0" ]
  [ "${nested}" = "0" ]
}

@test "end-to-end (ts): promote-readonly leaves a property a subclass writes or redeclares" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/readonly-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts promote-readonly --apply"

  local written redeclared
  written="$(grep -c 'readonly subclassWritten' "${work}/src/base.ts" || true)"
  # Sub re-declares the property, and that declaration keeps it mutable.
  redeclared="$(grep -c 'readonly subclassRedeclared' "${work}/src/base.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${written}" = "0" ]
  [ "${redeclared}" = "0" ]
}

@test "end-to-end (ts): a promote-readonly plan writes nothing" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/readonly-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts promote-readonly"

  local still
  still="$(grep -c 'readonly ctorOnly' "${work}/src/base.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "Would make"
  [ "${still}" = "0" ]
}

@test "end-to-end (ts): a promote-readonly apply leaves the project compiling" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work tsc compiled
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/readonly-demo/." "${work}/"
  tsc="${MODULE_DIR}/../../../storage/refactor/ts/node_modules/typescript/bin/tsc"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts promote-readonly --apply"
  compiled="$(cd "${work}" && node "${tsc}" --noEmit -p tsconfig.json >/dev/null 2>&1 && echo 0 || echo 1)"
  rm -rf "${work}"

  assert_success
  [ "${compiled}" = "0" ]
}

@test "end-to-end (ts): promote-readonly narrows to a named class" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/readonly-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts promote-readonly --class Base --apply"

  local promoted
  promoted="$(grep -c 'readonly ctorOnly' "${work}/src/base.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${promoted}" = "1" ]
}

@test "end-to-end (ts): a promote-readonly apply refuses what the compiler rejects" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/readonly-break-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts promote-readonly --apply"

  local promoted
  # The reference check cannot see an element access, a delete, or a write to a
  # static from the instance constructor; the compiler can, so the apply refuses.
  promoted="$(grep -c 'readonly' "${work}/src/breaking.ts" || true)"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "would introduce"
  [ "${promoted}" = "0" ]
}

@test "end-to-end (ts): an apply reports the string reference and leaves it" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"greet","to":"salute"}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'"

  local decl call leftover
  decl="$(grep -c 'salute(name: string)' "${work}/src/Greeter.ts" || true)"
  call="$(grep -c '\.salute(' "${work}/src/UseGreeter.ts" || true)"
  leftover="$(grep -c '"greet"' "${work}/src/Registry.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"string_references"'
  assert_output --partial "Registry.ts"
  [ "${decl}" = "1" ]
  [ "${call}" = "1" ]
  # The string the compiler cannot reach is reported, never rewritten.
  [ "${leftover}" = "1" ]
}

@test "end-to-end (ts): a re-plan after a clean apply finds nothing left" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"greet","to":"salute"}' > "${work}/request.json"

  bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'" >/dev/null 2>&1

  # `from` is gone and its target is declared, so a second run is a clean
  # idempotence check — not an error about a missing declaration.
  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  refute_output --partial "remaining_changes"
  assert_output --partial "already renamed"
}

@test "end-to-end (ts): a name that was never declared is an error" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"nosuchname","to":"alsonotdeclared"}' > "${work}/request.json"

  # Neither name exists, so this is a typo, not a completed rename.
  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "no declaration of 'nosuchname'"
}

@test "end-to-end (ts): a residual call site is reported as remaining_changes" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"greet","to":"salute"}' > "${work}/request.json"

  bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'" >/dev/null 2>&1

  # Hand-revert one call site: the declaration is renamed, so this is a dangling
  # usage the next run must surface rather than hide behind "no declaration".
  printf '%s\n' \
    'import { Greeter } from "./Greeter";' \
    '' \
    'export function run(): string {' \
    '  return new Greeter().greet("world");' \
    '}' > "${work}/src/UseGreeter.ts"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"remaining_changes"'
}


#!/usr/bin/env bats
# Split from refactor_tests.bats — shared setup()/helpers come from the load.
load 'refactor_test_helper'

# ── L1: the TypeScript plugin ──────────────────────────────────────────────────

@test "ts plugin: meta declares the language, extensions and its op" {
  run bash "${TS_PLUGIN}" meta
  assert_success

  printf '%s' "${output}" | python3 -c '
import json, sys
m = json.load(sys.stdin)
assert m["lang"] == "ts", m
assert ".ts" in m["extensions"], m
assert m["ops"] == ["rename", "move", "remove-unused", "privatize", "promote-readonly"], m
assert m["map"]["move"] == {"file": "move-file", "member": "move-member"}, m
assert m["map"]["remove-unused"] == {"local": "remove-unused-locals", "param": "remove-unused-params"}, m
assert m["map"]["privatize"] == {"members": "privatize-members"}, m
# `*` means the op has one native form and any kind is passed through, because
# the TypeScript driver reads `kind` as a declaration kind.
assert m["map"]["rename"] == {"*": "rename-symbol"}, m
assert m["requires"]["rename-symbol"] == ["from", "to"], m
assert m["requires"]["move-file"] == ["file", "to"], m
assert m["requires"]["move-member"] == ["class", "from", "to"], m
assert m["requires"]["privatize-members"] == [], m
assert m["requires"]["remove-unused-locals"] == ["file"], m
assert m["requires"]["remove-unused-params"] == ["file"], m
assert m["requires"]["promote-readonly"] == [], m
assert m["risks"]["rename-symbol"] == "rename", m
assert m["risks"]["move-file"] == "move", m
assert m["risks"]["move-member"] == "move", m
assert m["risks"]["privatize-members"] == "cleanup", m
assert m["risks"]["remove-unused-locals"] == "cleanup", m
assert m["risks"]["remove-unused-params"] == "signature", m
assert m["risks"]["promote-readonly"] == "signature", m
'
}

@test "core: a second language needs no core change" {

  # The core knows no op names: it validates against whatever the plugin declares,
  # which is what makes `langs/<lang>/` additive.
  run bash "${TOOL}" --lang ts rename --from greet

  assert_failure
  assert_output --partial "requires --to"
}

@test "end-to-end (ts): rename-symbol renames the declaration and the reference" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/rename-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts rename --from greet --to salute --apply"

  local decl call stale
  decl="$(grep -c 'salute(name: string)' "${work}/src/Greeter.ts" || true)"
  call="$(grep -c '\.salute(' "${work}/src/UseGreeter.ts" || true)"
  stale="$(grep -c 'greet' "${work}/src/Greeter.ts" || true)"
  rm -rf "${work}"

  assert_success
  # ts-morph resolves the symbol through the TypeScript compiler, so the
  # declaration and the cross-file reference both move.
  [ "${decl}" = "1" ]
  [ "${call}" = "1" ]
  [ "${stale}" = "0" ]
}

# ── S1/S2 (ts): string references and post-apply verification ─────────────────

@test "end-to-end (ts): a plan reports the string reference it cannot rewrite" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"greet","to":"salute"}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"

  # A plan writes nothing: the old name is still on the declaration.
  local stale
  stale="$(grep -c 'greet' "${work}/src/Greeter.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"string_references"'
  assert_output --partial "Registry.ts"
  [ "${stale}" = "1" ]
}

@test "end-to-end (ts): a name held in JSX text is reported too" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/rename-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"greet","to":"salute"}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  # Literal text inside JSX is as invisible to the rename as a quoted string.
  assert_output --partial "Banner.tsx"
}

@test "end-to-end (ts): an ambiguous name is refused, naming the candidates" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/ambiguous-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"greet","to":"salute"}' > "${work}/request.json"

  # Two declarations of the same name: renaming either one silently could touch
  # the wrong symbol, so both are named for the caller to choose between.
  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "declared in 2 places"
  assert_output --partial "First.ts"
  assert_output --partial "Second.ts"
}

@test "end-to-end (ts): --file picks one of several same-named methods" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/ambiguous-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"greet","to":"salute","file":"src/First.ts"}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'"

  local picked other
  picked="$(grep -c 'salute(name: string)' "${work}/src/First.ts" || true)"
  other="$(grep -c 'greet(name: string)' "${work}/src/Second.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${picked}" = "1" ]
  # The declaration in the other file is left alone.
  [ "${other}" = "1" ]
}

@test "end-to-end (ts): --kind class picks the class over a same-named method" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/ambiguous-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"Marker","to":"Tag","kind":"class"}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'"

  local klass method
  klass="$(grep -c 'class Tag' "${work}/src/Marker.ts" || true)"
  method="$(grep -c 'Marker(): string' "${work}/src/User.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${klass}" = "1" ]
  # The same-named method is not the one that was renamed.
  [ "${method}" = "1" ]
}

@test "end-to-end (ts): --kind method picks the method over a same-named class" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/ambiguous-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"Marker","to":"Tag","kind":"method"}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'"

  local klass method
  klass="$(grep -c 'class Marker' "${work}/src/Marker.ts" || true)"
  method="$(grep -c 'Tag(): string' "${work}/src/User.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${klass}" = "1" ]
  [ "${method}" = "1" ]
}

@test "end-to-end (ts): an unknown --kind is refused" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/ambiguous-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"Marker","to":"Tag","kind":"widget"}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "unknown --kind 'widget'"
}

@test "end-to-end (ts): --kind method covers interface members" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/interface-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"greet","to":"salute","kind":"method"}' > "${work}/request.json"

  # An interface member is a MethodSignature, not a MethodDeclaration — it must
  # still count, so the class method is never renamed silently in its place.
  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "declared in 2 places"
  assert_output --partial "Port.ts"
  assert_output --partial "Impl.ts"
}

@test "end-to-end (ts): --file picks an interface member over a class method" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/interface-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"greet","to":"salute","kind":"method","file":"src/Port.ts"}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'"

  local port impl
  port="$(grep -c 'salute(name: string)' "${work}/src/Port.ts" || true)"
  impl="$(grep -c 'greet(name: string)' "${work}/src/Impl.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${port}" = "1" ]
  # The class method in the other file is left alone.
  [ "${impl}" = "1" ]
}

@test "end-to-end (ts): a declaration inside a namespace is not missed" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/namespace-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"Marker","to":"Tag"}' > "${work}/request.json"

  # A namespaced class is a real second declaration; missing it would rename the
  # top-level one silently instead of asking which was meant.
  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "declared in 2 places"
  assert_output --partial "ns.ts"
  assert_output --partial "top.ts"
}

@test "end-to-end (ts): a scoped re-plan does not report the other declaration" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/interface-demo/." "${work}/"
  printf '%s' '{"op":"rename-symbol","from":"greet","to":"salute","kind":"method","file":"src/Port.ts"}' > "${work}/request.json"

  bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'" >/dev/null 2>&1

  # The class method in the other file was deliberately out of scope, so it is
  # not residue of this rename.
  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  refute_output --partial "remaining_changes"
  assert_output --partial "already renamed"
}

@test "end-to-end (ts): move-file relocates a file and rewrites its importers" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/move-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind file --file src/a.ts --to src/sub --apply"

  local moved gone rewritten owned
  moved="$(test -f "${work}/src/sub/a.ts" && echo 1 || echo 0)"
  gone="$(test -f "${work}/src/a.ts" && echo 1 || echo 0)"
  rewritten="$(grep -c 'from "./sub/a"' "${work}/src/use.ts" || true)"
  # A moved file is a new path: it must belong to the caller, not the container.
  owned="$(test -O "${work}/src/sub/a.ts" && echo 1 || echo 0)"
  rm -rf "${work}"

  assert_success
  [ "${moved}" = "1" ]
  [ "${gone}" = "0" ]
  [ "${rewritten}" = "1" ]
  [ "${owned}" = "1" ]
}

@test "end-to-end (ts): a move-file plan writes nothing" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/move-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind file --file src/a.ts --to src/sub"

  local still spec
  still="$(test -f "${work}/src/a.ts" && echo 1 || echo 0)"
  spec="$(grep -c 'from "./a"' "${work}/src/use.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "Would move"
  [ "${still}" = "1" ]
  [ "${spec}" = "1" ]
}

@test "end-to-end (ts): move-file refuses a destination that does not exist" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/move-demo/." "${work}/"
  printf '%s' '{"op":"move-file","file":"src/a.ts","to":"src/nope"}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "no such destination folder"
}

@test "end-to-end (ts): move-file refuses the file's own folder" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/move-demo/." "${work}/"
  printf '%s' '{"op":"move-file","file":"src/a.ts","to":"src"}' > "${work}/request.json"

  # Nothing would change, so reporting a move would be a false success.
  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "already in 'src'"
}

@test "end-to-end (ts): an unsupported op is refused" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/move-demo/." "${work}/"
  printf '%s' '{"op":"frobnicate","file":"src/a.ts","to":"src/sub"}' > "${work}/request.json"

  # The core rejects an op the plugin does not declare; this covers a direct
  # plugin invocation, where nothing else would.
  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' plan < '${work}/request.json'"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "unsupported op 'frobnicate'"
}

@test "end-to-end (ts): move-file warns about an alias specifier it cannot rewrite" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/alias-demo/." "${work}/"
  printf '%s' '{"op":"move-file","file":"src/a.ts","to":"src/sub","apply":true}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'"

  local moved alias
  moved="$(test -f "${work}/src/sub/a.ts" && echo 1 || echo 0)"
  alias="$(grep -c 'from "@/a"' "${work}/src/use.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${moved}" = "1" ]
  # move() rewrites relative specifiers only, so the alias survives — and is
  # reported rather than counted as an importer that was updated.
  assert_output --partial "(0 importer(s) updated)"
  assert_output --partial "not a relative specifier"
  [ "${alias}" = "1" ]
}

@test "end-to-end (ts): move-member relocates a static method and rewrites its call sites" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from make --to New --apply"

  local moved removed rewritten dropped imported
  moved="$(grep -c 'static make' "${work}/src/new.ts" || true)"
  removed="$(grep -c 'make(' "${work}/src/old.ts" || true)"
  rewritten="$(grep -c 'New.make(1)' "${work}/src/use.ts" || true)"
  # use.ts no longer references Old, so its import must be gone and New's must arrive.
  dropped="$(grep -c 'import { Old }' "${work}/src/use.ts" || true)"
  imported="$(grep -c 'import { New }' "${work}/src/use.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "Moved static Old.make -> New.make"
  assert_output --partial "2 call site(s) rewritten"
  # The response's file list reaches the report, not just the summary.
  assert_output --partial "src/new.ts"
  [ "${moved}" = "1" ]
  [ "${removed}" = "0" ]
  [ "${rewritten}" = "1" ]
  [ "${dropped}" = "0" ]
  [ "${imported}" = "1" ]
}

@test "end-to-end (ts): move-member refuses an instance member, listing its call sites" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"
  printf '%s' '{"op":"move-member","class":"Old","from":"instanceOnly","to":"New","apply":true}' > "${work}/request.json"

  # An instance member's receiver needs a new owner the tool cannot supply, so the
  # op refuses and names where the member is used.
  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'"
  local untouched
  untouched="$(grep -c 'instanceOnly' "${work}/src/old.ts" || true)"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "not static"
  assert_output --partial "mixed.ts"
  [ "${untouched}" = "1" ]
}

@test "end-to-end (ts): move-member keeps an import the file still uses" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from make --to New --apply"

  local kept call
  # mixed.ts still constructs Old, so its import must survive the move.
  kept="$(grep -c 'import { Old }' "${work}/src/mixed.ts" || true)"
  call="$(grep -c 'New.make(3)' "${work}/src/mixed.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${kept}" = "1" ]
  [ "${call}" = "1" ]
}

@test "end-to-end (ts): a move-member plan writes nothing" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from make --to New"

  local still spec
  still="$(grep -c 'static make' "${work}/src/old.ts" || true)"
  spec="$(grep -c 'Old.make(1)' "${work}/src/use.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "Would move"
  [ "${still}" = "1" ]
  [ "${spec}" = "1" ]
}

@test "end-to-end (ts): move-member lists candidates when the target class name is ambiguous" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"
  printf 'export class New {\n  other(): number {\n    return 2;\n  }\n}\n' > "${work}/src/dup.ts"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from make --to New --apply"

  local untouched
  untouched="$(grep -c 'static make' "${work}/src/old.ts" || true)"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "declared in 2 places"
  assert_output --partial "dup.ts"
  assert_output --partial "new.ts"
  [ "${untouched}" = "1" ]
}

@test "end-to-end (ts): move-member fails when the member does not exist" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"
  printf '%s' '{"op":"move-member","class":"Old","from":"missing","to":"New","apply":true}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "no member 'missing'"
}

@test "end-to-end (ts): move-member preserves the destination file's indentation" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from make --to New --apply"

  local two four
  # member-demo is two-space indented; the pasted member must match the file, not
  # the engine's four-space default.
  two="$(grep -c '^  static make' "${work}/src/new.ts" || true)"
  four="$(grep -c '^    static make' "${work}/src/new.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${two}" = "1" ]
  [ "${four}" = "0" ]
}

@test "end-to-end (ts): move-member does not reformat the members it did not touch" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from make --to Loose --apply"

  local intact
  # The destination's own spacing is not the engine's to normalise.
  intact="$(grep -cF 'existing() : number { return 1 ; }' "${work}/src/loose.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${intact}" = "1" ]
}

@test "end-to-end (ts): move-member survives a one-line destination class" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from make --to Slim --apply"

  local intact over moved
  intact="$(grep -cF 'existing(): number { return 1; }' "${work}/src/one-line.ts" || true)"
  # A one-line class has no sibling indent to copy; the fallback must not corrupt
  # the class with a bogus indentation string.
  over="$(grep -cE '^ {10,}' "${work}/src/one-line.ts" || true)"
  moved="$(grep -c 'static make' "${work}/src/one-line.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${intact}" = "1" ]
  [ "${over}" = "0" ]
  [ "${moved}" = "1" ]
}

@test "end-to-end (ts): move-member carries the member's docblock with it" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from ping --to New --apply"

  local arrived left
  # The member's documentation travels with it, and does not stay behind.
  arrived="$(grep -c 'Return the input unchanged.' "${work}/src/new.ts" || true)"
  left="$(grep -c 'Return the input unchanged.' "${work}/src/old.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${arrived}" = "1" ]
  [ "${left}" = "0" ]
}

@test "end-to-end (ts): move-member rewrites a call site reached through an import alias" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-alias-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from make --to New --apply"

  local rewritten dropped imported
  # The receiver resolves to the class through the alias, so it must be repointed
  # and the alias import dropped, not left pointing at the moved member.
  rewritten="$(grep -c 'New.make(7)' "${work}/src/aliased.ts" || true)"
  dropped="$(grep -c 'Legacy' "${work}/src/aliased.ts" || true)"
  imported="$(grep -c 'import { New }' "${work}/src/aliased.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${rewritten}" = "1" ]
  [ "${dropped}" = "0" ]
  [ "${imported}" = "1" ]
}

@test "end-to-end (ts): move-member drops a namespace import the rewrite left unused" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-alias-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from make --to New --apply"

  local rewritten namespace
  rewritten="$(grep -c 'New.make(9)' "${work}/src/namespace.ts" || true)"
  # The namespace binding only existed to reach the class; nothing uses it now.
  namespace="$(grep -c 'import \* as lib' "${work}/src/namespace.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${rewritten}" = "1" ]
  [ "${namespace}" = "0" ]
}

@test "end-to-end (ts): move-member warns instead of colliding with a default import" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-alias-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from make --to New --apply"

  local duplicates
  # collide.ts already binds `New` as a default import; a named import of the same
  # name would be a duplicate identifier, so it is reported instead of added.
  duplicates="$(grep -c 'import { New }' "${work}/src/collide.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "is already bound in the file"
  [ "${duplicates}" = "0" ]
}

@test "end-to-end (ts): move-member follows a body self-reference to the new class" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from ping --to New --apply"

  local followed stale
  # `Old.ping` stops existing once the member moves, so the body's own call has to
  # follow it.
  followed="$(grep -c 'New.ping(n - 1)' "${work}/src/new.ts" || true)"
  stale="$(grep -c 'Old.ping' "${work}/src/new.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${followed}" = "1" ]
  [ "${stale}" = "0" ]
}

@test "end-to-end (ts): move-member keeps a body reference to the old class and imports it" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from ping --to New --apply"

  local kept imported
  # `_v` stayed on Old, so the reference keeps working only if the class is in scope.
  kept="$(grep -c 'Old._v' "${work}/src/new.ts" || true)"
  imported="$(grep -c 'import { Old }' "${work}/src/new.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${kept}" = "1" ]
  [ "${imported}" = "1" ]
}

@test "end-to-end (ts): move-member warns about a body reference that does not travel" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from measured --to New --apply"
  rm -rf "${work}"

  assert_success
  # `scale()` is declared beside the class, not on it, so it does not come along —
  # the move names it rather than leaving an unresolved call.
  assert_output --partial "does not travel with the member"
  assert_output --partial "scale"
}

@test "end-to-end (ts): move-member does not import the old class for a body self-reference" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from countdown --to New --apply"

  local followed imported
  followed="$(grep -c 'New.countdown(n - 1)' "${work}/src/new.ts" || true)"
  # The only reference was to the member itself, and it followed the member — so
  # the old class is not left imported and unused.
  imported="$(grep -c 'import { Old }' "${work}/src/new.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${followed}" = "1" ]
  [ "${imported}" = "0" ]
}

@test "end-to-end (ts): move-member moves a static property" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts move --kind member --class Old --from _v --to New --apply"

  local moved rewritten imported
  moved="$(grep -c 'static _v' "${work}/src/new.ts" || true)"
  # The references that stayed behind in Old are repointed, and the class that now
  # owns the property is imported there.
  rewritten="$(grep -c 'New._v' "${work}/src/old.ts" || true)"
  imported="$(grep -c 'import { New }' "${work}/src/old.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${moved}" = "1" ]
  [ "${rewritten}" -ge 1 ]
  [ "${imported}" = "1" ]
}

@test "end-to-end (ts): move-member refuses a name that resolves to a get/set pair" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/member-demo/." "${work}/"
  printf '%s' '{"op":"move-member","class":"Old","from":"size","to":"New","apply":true}' > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${TS_PLUGIN}' apply < '${work}/request.json'"
  local untouched
  untouched="$(grep -c 'get size' "${work}/src/old.ts" || true)"
  rm -rf "${work}"

  assert_failure
  assert_output --partial "resolves to 2 members"
  [ "${untouched}" = "1" ]
}

@test "end-to-end (ts): privatize-members makes an internally-used member private" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts privatize --class Base --apply"

  local method property unused kept external
  method="$(grep -c 'private internalOnly' "${work}/src/base.ts" || true)"
  property="$(grep -c 'private value' "${work}/src/base.ts" || true)"
  unused="$(grep -c 'private unusedHere' "${work}/src/base.ts" || true)"
  kept="$(grep -c 'private alreadyPrivate' "${work}/src/base.ts" || true)"
  # Reachable from another module, so it is not used only by its own class.
  external="$(grep -c 'private usedBySubclass' "${work}/src/base.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${method}" = "1" ]
  [ "${property}" = "1" ]
  [ "${unused}" = "1" ]
  [ "${kept}" = "1" ]
  [ "${external}" = "0" ]
}

@test "end-to-end (ts): privatize-members leaves members a subclass reaches" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts privatize --class Base --apply"

  local reached overridden
  # Sub.touch() calls the first and Sub overrides the second; neither may be
  # narrowed, or the subclass stops compiling.
  reached="$(grep -cE '^  usedBySubclass' "${work}/src/base.ts" || true)"
  overridden="$(grep -cE '^  overriddenBySubclass' "${work}/src/base.ts" || true)"
  rm -rf "${work}"

  assert_success
  [ "${reached}" = "1" ]
  [ "${overridden}" = "1" ]
}

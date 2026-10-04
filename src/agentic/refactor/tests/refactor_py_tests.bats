#!/usr/bin/env bats
# Split from refactor_tests.bats — shared setup()/helpers come from the load.
load 'refactor_test_helper'

# ── L2: the Python plugin ──────────────────────────────────────────────────────

@test "py plugin: meta declares the language, extensions and its op" {
  run bash "${PY_PLUGIN}" meta
  assert_success

  printf '%s' "${output}" | python3 -c '
import json, sys
m = json.load(sys.stdin)
assert m["lang"] == "py", m
assert m["extensions"] == [".py"], m
assert m["ops"] == ["rename", "move", "extract", "inline", "encapsulate", "add-parameter", "remove-parameter", "remove-unused", "privatize"], m
assert m["map"]["extract"] == {"method": "extract-method", "variable": "extract-variable"}, m
assert m["map"]["add-parameter"] == {"*": "add-argument"}, m
assert m["map"]["remove-parameter"] == {"*": "remove-argument"}, m
assert m["map"]["privatize"] == {"*": "privatise"}, m
assert m["requires"]["rename-symbol"] == ["from", "to"], m
assert m["requires"]["extract-method"] == ["file", "start", "end", "to"], m
assert m["requires"]["inline"] == ["from"], m
assert m["requires"]["encapsulate-field"] == ["file", "from"], m
assert m["requires"]["add-argument"] == ["file", "from", "to", "index"], m
assert m["requires"]["remove-argument"] == ["file", "from", "index"], m
assert m["requires"]["move-module"] == ["file", "to"], m
assert m["requires"]["remove-unused-imports"] == ["file"], m
assert m["requires"]["privatise"] == ["file", "from"], m
assert m["risks"]["rename-symbol"] == "rename", m
assert m["risks"]["extract-method"] == "extract", m
assert m["risks"]["inline"] == "inline", m
assert m["risks"]["encapsulate-field"] == "cleanup", m
assert m["risks"]["add-argument"] == "signature", m
assert m["risks"]["remove-argument"] == "signature", m
assert m["risks"]["move-module"] == "move", m
assert m["risks"]["remove-unused-imports"] == "cleanup", m
assert m["risks"]["privatise"] == "cleanup", m
'
}

@test "end-to-end (py): rename-symbol renames the definition and the reference" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PY_FIXTURES}/rename-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang py rename --from greet --to salute --apply"

  local decl call stray
  decl="$(grep -c 'def salute' "${work}/src/greeter.py" || true)"
  call="$(grep -c '\.salute(' "${work}/src/use_greeter.py" || true)"
  # rope writes a .ropeproject/ by default; it must not reach the caller's tree.
  stray="$(test -e "${work}/.ropeproject" && echo 1 || echo 0)"
  rm -rf "${work}"

  assert_success
  [ "${decl}" = "1" ]
  [ "${call}" = "1" ]
  [ "${stray}" = "0" ]
}

@test "py plugin: string-refs reports a name held in a string, not code or a comment" {
  local req
  req="$(mktemp)"
  printf '{"project":"%s","from":"greet"}' "${PY_FIXTURES}/rename-demo" > "${req}"

  run bash -c "python3 '${MODULE_DIR}/langs/py/scan.py' < '${req}'"
  rm -f "${req}"

  assert_success
  printf '%s' "${output}" | python3 -c '
import json, sys
hits = [h for h in json.load(sys.stdin)["hits"] if h["file"] == "src/registry.py"]
lines = sorted(h["line"] for h in hits)
assert lines == [4, 8, 9], hits
assert all("comment" not in h["text"] for h in hits), hits
'
}

@test "end-to-end (py): a rename reports the string reference it cannot rewrite" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/rename-demo/." "${work}/"
  printf '{"op":"rename-symbol","from":"greet","to":"salute"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  # rope rewrites the definition and the call, but not a name held in a string.
  local untouched
  untouched="$(grep -c 'getattr(Greeter(), "greet")' "${work}/src/registry.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  assert_output --partial '"string_references"'
  assert_output --partial 'registry.py'
  [ "${untouched}" = "1" ]
}

@test "py plugin: the names scan counts identifiers and ignores strings" {
  local req
  req="$(mktemp)"
  printf '{"project":"%s","from":"greet","kind":"names"}' "${PY_FIXTURES}/rename-demo" > "${req}"

  run bash -c "python3 '${MODULE_DIR}/langs/py/scan.py' < '${req}'"
  rm -f "${req}"

  assert_success
  printf '%s' "${output}" | python3 -c '
import json, sys
hits = json.load(sys.stdin)["hits"]
# The definition and the call are identifiers; the registry holds only strings.
assert sorted(h["file"] for h in hits) == ["src/greeter.py", "src/use_greeter.py"], hits
assert all(h["text"] == "greet" for h in hits), hits
'
}

@test "end-to-end (py): a clean apply verifies itself" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/rename-demo/." "${work}/"
  printf '{"op":"rename-symbol","from":"greet","to":"salute"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"
  rm -rf "${work}" "${req}"

  assert_success
  # Nothing the rename could reach is left: the verification pass is silent.
  refute_output --partial "remaining_changes"
}

@test "py plugin: ops.py finds every definition of a name, not just the first" {
  local probe
  probe="$(mktemp)"
  cat > "${probe}" <<PY
import sys
sys.path.insert(0, "${MODULE_DIR}/langs/py")
import ops

text = "def greet():\n    pass\n\ndef greet():\n    pass\n"
found = ops.definition_offsets(text, "greet")
assert found == [4, 27], found
PY
  run python3 "${probe}"
  rm -f "${probe}"

  assert_success
}

@test "end-to-end (py): an ambiguous name is refused, naming the candidates" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/ambiguous-demo/." "${work}/"
  printf '{"op":"rename-symbol","from":"greet","to":"salute"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local a b
  a="$(grep -c 'def greet' "${work}/src/a.py" || true)"
  b="$(grep -c 'def greet' "${work}/src/b.py" || true)"
  rm -rf "${work}" "${req}"

  [ "${status}" -ne 0 ]
  assert_output --partial 'a.py'
  assert_output --partial 'b.py'
  # Refused, so neither definition was rewritten.
  [ "${a}" = "1" ]
  [ "${b}" = "1" ]
}

@test "end-to-end (py): --file picks one of several same-named definitions" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/ambiguous-demo/." "${work}/"
  printf '{"op":"rename-symbol","from":"greet","to":"salute","file":"src/a.py"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local a b
  a="$(grep -c 'def salute' "${work}/src/a.py" || true)"
  b="$(grep -c 'def greet' "${work}/src/b.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  [ "${a}" = "1" ]
  # The definition in the other file was left alone.
  [ "${b}" = "1" ]
}

@test "end-to-end (py): extract-method moves a block into a new method" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/extract-demo/." "${work}/"
  printf '{"op":"extract-method","file":"src/calc.py","start":"2","end":"3","to":"compute"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local method call
  method="$(grep -c 'def compute' "${work}/src/calc.py" || true)"
  call="$(grep -c 'scaled = compute(width, height)' "${work}/src/calc.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  [ "${method}" = "1" ]
  [ "${call}" = "1" ]
}

@test "end-to-end (py): extract-variable replaces a sub-expression with a name" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/extract-demo/." "${work}/"
  printf '{"op":"extract-variable","file":"src/pricing.py","start":"2:12","end":"2:22","to":"subtotal"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local assign use
  assign="$(grep -c 'subtotal = price \* qty' "${work}/src/pricing.py" || true)"
  use="$(grep -c 'return subtotal \* 2' "${work}/src/pricing.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  [ "${assign}" = "1" ]
  [ "${use}" = "1" ]
}

@test "end-to-end (py): inline replaces a call with the body and drops the definition" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/inline-demo/." "${work}/"
  printf '{"op":"inline","from":"double"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local call def
  call="$(grep -c 'return 21 \* 2' "${work}/src/use_mathx.py" || true)"
  # remove=True inlines every call and deletes the now-unused definition.
  def="$(grep -c 'def double' "${work}/src/mathx.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  [ "${call}" = "1" ]
  [ "${def}" = "0" ]
}

@test "end-to-end (py): encapsulate-field adds accessors and rewrites access" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/field-demo/." "${work}/"
  printf '{"op":"encapsulate-field","file":"src/counter.py","from":"value"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local getter setter call
  getter="$(grep -c 'def get_value' "${work}/src/counter.py" || true)"
  setter="$(grep -c 'def set_value' "${work}/src/counter.py" || true)"
  call="$(grep -c 'return self.get_value()' "${work}/src/counter.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  [ "${getter}" = "1" ]
  [ "${setter}" = "1" ]
  [ "${call}" = "1" ]
}

@test "end-to-end (py): remove-argument drops a parameter and fixes call sites" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/signature-demo/." "${work}/"
  printf '{"op":"remove-argument","file":"src/greeter.py","from":"greet","index":"2"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local def call
  def="$(grep -c 'def greet(name):' "${work}/src/greeter.py" || true)"
  call="$(grep -c 'greet("world")' "${work}/src/call.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  [ "${def}" = "1" ]
  [ "${call}" = "1" ]
}

@test "end-to-end (py): add-argument appends a parameter with a default" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/signature-demo/." "${work}/"
  cat > "${req}" <<'JSON'
{"op":"add-argument","file":"src/greeter.py","from":"greet","to":"suffix","index":"3","default":"\".\""}
JSON

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local def
  def="$(grep -c 'def greet(name, punctuation, suffix=".")' "${work}/src/greeter.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  [ "${def}" = "1" ]
}

@test "end-to-end (py): move-module relocates a module and rewrites imports" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/move-demo/." "${work}/"
  printf '{"op":"move-module","file":"pkg/helpers.py","to":"pkg/other"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local moved gone rewritten
  moved="$(test -f "${work}/pkg/other/helpers.py" && echo 1 || echo 0)"
  gone="$(test -f "${work}/pkg/helpers.py" && echo 1 || echo 0)"
  rewritten="$(grep -c 'from pkg.other.helpers import area' "${work}/pkg/main.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  [ "${moved}" = "1" ]
  [ "${gone}" = "0" ]
  [ "${rewritten}" = "1" ]
  # The report names where the module landed, not only the path it left.
  assert_output --partial 'pkg/other/helpers.py'
}

@test "end-to-end (py): remove-unused-imports drops only provably-unused names" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/unused-demo/." "${work}/"
  printf '{"op":"remove-unused-imports","file":"src/mod.py"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local kept dropped
  kept="$(grep -c '^import sys' "${work}/src/mod.py" || true)"
  dropped="$(grep -cE '^import os|OrderedDict' "${work}/src/mod.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  # `sys` is used; `os` and `OrderedDict` are not.
  [ "${kept}" = "1" ]
  [ "${dropped}" = "0" ]
}

@test "end-to-end (py): privatise prefixes a module-internal name" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/privatise-demo/." "${work}/"
  printf '{"op":"privatise","file":"src/util.py","from":"helper"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local def call
  def="$(grep -c 'def _helper()' "${work}/src/util.py" || true)"
  call="$(grep -c 'return _helper()' "${work}/src/util.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  [ "${def}" = "1" ]
  [ "${call}" = "1" ]
}

@test "end-to-end (py): privatise refuses a name used outside its module" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/privatise-exposed-demo/." "${work}/"
  printf '{"op":"privatise","file":"src/util.py","from":"helper"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local unchanged
  unchanged="$(grep -c 'def helper()' "${work}/src/util.py" || true)"
  rm -rf "${work}" "${req}"

  [ "${status}" -ne 0 ]
  assert_output --partial 'main.py'
  # Refused, so the definition is untouched.
  [ "${unchanged}" = "1" ]
}

@test "end-to-end (py): move-module refuses a destination that does not exist" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/move-demo/." "${work}/"
  printf '{"op":"move-module","file":"pkg/helpers.py","to":"pkg/nope"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local intact
  intact="$(test -f "${work}/pkg/helpers.py" && echo 1 || echo 0)"
  rm -rf "${work}" "${req}"

  [ "${status}" -ne 0 ]
  assert_output --partial 'no such destination folder'
  # Refused, so the module was not deleted.
  [ "${intact}" = "1" ]
}

@test "end-to-end (py): encapsulate-field refuses a field shared by two classes" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/field-ambiguous-demo/." "${work}/"
  printf '{"op":"encapsulate-field","file":"src/two.py","from":"value"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local unchanged
  unchanged="$(grep -c 'self.value = 0' "${work}/src/two.py" || true)"
  rm -rf "${work}" "${req}"

  [ "${status}" -ne 0 ]
  assert_output --partial '2 classes'
  [ "${unchanged}" = "1" ]
}

@test "end-to-end (py): encapsulate-field tolerates a parameter shadowing the field" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/field-shadow-demo/." "${work}/"
  printf '{"op":"encapsulate-field","file":"src/counter.py","from":"value"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local getter
  getter="$(grep -c 'def get_value' "${work}/src/counter.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  [ "${getter}" = "1" ]
}

@test "end-to-end (py): a rename ignores a function-local with the same name" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work req
  work="$(mktemp -d)"
  req="$(mktemp)"
  cp -r "${PY_FIXTURES}/local-shadow-demo/." "${work}/"
  printf '{"op":"rename-symbol","file":"src/mod.py","from":"greet","to":"salute"}' > "${req}"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PY_PLUGIN}' apply < '${req}'"

  local def local_var
  def="$(grep -c 'def salute()' "${work}/src/mod.py" || true)"
  local_var="$(grep -c 'greet = 5' "${work}/src/mod.py" || true)"
  rm -rf "${work}" "${req}"

  assert_success
  # The module-level function renamed; the function-local binding did not.
  [ "${def}" = "1" ]
  [ "${local_var}" = "1" ]
}


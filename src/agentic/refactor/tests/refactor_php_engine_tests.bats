#!/usr/bin/env bats
# Split from refactor_tests.bats — shared setup()/helpers come from the load.
load 'refactor_test_helper'

# ── PHP plugin: engine resolution (T5) ─────────────────────────────────────────

@test "php plugin: meta declares php, the .php extension and its canonical ops" {
  run bash "${PHP_PLUGIN}" meta
  assert_success
  # Parse rather than match raw text: json.dumps spacing must not matter.
  printf '%s' "${output}" | python3 -c '
import json, sys
m = json.load(sys.stdin)
assert m["lang"] == "php", m
assert ".php" in m["extensions"], m
assert sorted(m["ops"]) == ["move", "privatize", "remove-unused", "rename"], m
assert m["map"]["rename"]["method"] == "rename-method", m
assert m["map"]["rename"]["class"] == "rename-class", m
assert m["map"]["privatize"]["constant"] == "privatize-final-class-constants", m
# A canonical op another language alone declares is not invented here.
assert "extract" not in m["ops"], m
assert "promote-readonly" not in m["ops"], m
'
}

@test "php plugin: doctor prefers the project's own Rector" {
  run bash "${PHP_PLUGIN}" doctor --project "${PHP_FIXTURES}/with-rector"
  assert_success
  assert_output --partial '"via": "project"'
  assert_output --partial '"version": "2.6.4"'
  assert_output --partial '"php_version": "8.4"'
}

@test "php plugin: doctor reads .php-version ahead of composer.json" {
  local project
  project="$(mktemp -d)"
  mkdir -p "${project}/vendor/bin"
  printf '8.5.1\n' > "${project}/.php-version"
  printf '{"require":{"php":"^8.1"}}' > "${project}/composer.json"
  printf '#!/usr/bin/env bash\necho stub\n' > "${project}/vendor/bin/rector"
  chmod +x "${project}/vendor/bin/rector"

  run bash "${PHP_PLUGIN}" doctor --project "${project}"
  rm -rf "${project}"

  assert_success
  assert_output --partial '"php_version": "8.5.1"'
}

@test "php plugin: doctor reports an actionable error when no engine exists" {
  local empty_storage
  empty_storage="$(mktemp -d)"

  run env REFACTOR_STORAGE_DIR="${empty_storage}" bash "${PHP_PLUGIN}" doctor --project "${PHP_FIXTURES}/bare"
  rm -rf "${empty_storage}"

  assert_failure
  assert_output --partial "no Rector engine found"
  # Parse rather than match the raw text: json.dumps spacing must not matter.
  printf '%s' "${output}" | python3 -c 'import json,sys; sys.exit(json.load(sys.stdin)["ok"] is not False)'
}

@test "php plugin: doctor rejects a missing project directory" {
  run bash "${PHP_PLUGIN}" doctor --project "/nonexistent/project"
  assert_failure
  assert_output --partial "project directory not found"
}

# ── PHP plugin: container runner (T6) ──────────────────────────────────────────

@test "php plugin: doctor resolves the image from the project's compose file" {
  local project
  project="$(mktemp -d)"
  mkdir -p "${project}/vendor/bin"
  printf '#!/usr/bin/env bash\necho stub\n' > "${project}/vendor/bin/rector"
  chmod +x "${project}/vendor/bin/rector"
  printf '{"require":{"php":"^8.2"}}' > "${project}/composer.json"
  printf 'services:\n  app:\n    image: gete/php-runtime:8.2\n' > "${project}/docker-compose.yml"

  run bash "${PHP_PLUGIN}" doctor --project "${project}"
  rm -rf "${project}"

  assert_success
  assert_output --partial '"image": "gete/php-runtime:8.2"'
}

@test "php plugin: doctor falls back to php:<version>-cli without a compose file" {
  run bash "${PHP_PLUGIN}" doctor --project "${PHP_FIXTURES}/with-rector"
  assert_success
  assert_output --partial '"image": "php:8.4-cli"'
}

@test "php plugin: --image overrides the resolved image" {
  run bash "${PHP_PLUGIN}" doctor --project "${PHP_FIXTURES}/with-rector" --image custom/php:9.9
  assert_success
  assert_output --partial '"image": "custom/php:9.9"'
}

@test "php plugin: the runner argv mounts the project and pins the rule" {
  run bash "${PHP_PLUGIN}" doctor --project "${PHP_FIXTURES}/with-rector" --command
  assert_success
  assert_output --partial "${PHP_FIXTURES}/with-rector:/app"
  assert_output --partial '"--only"'
  assert_output --partial "RenameMethodRector"
  assert_output --partial '"--clear-cache"'
  assert_output --partial '"--dry-run"'
}

@test "php plugin: the scratch engine is mounted at /refactor-engine" {
  local scratch engine
  scratch="$(mktemp -d)"
  engine="${scratch}/rector/2.6.4"
  mkdir -p "${engine}/vendor/bin"
  printf '#!/usr/bin/env bash\necho stub\n' > "${engine}/vendor/bin/rector"
  chmod +x "${engine}/vendor/bin/rector"
  printf '{"packages-dev":[{"name":"rector/rector","version":"2.6.4"}]}' > "${engine}/composer.lock"

  run env REFACTOR_STORAGE_DIR="${scratch}" bash "${PHP_PLUGIN}" doctor \
    --project "${PHP_FIXTURES}/bare" --command
  rm -rf "${scratch}"

  assert_success
  assert_output --partial '"via": "scratch"'
  assert_output --partial "/refactor-engine"
}

@test "php plugin: the resolved image runs php against the mounted project" {
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker info >/dev/null 2>&1 || skip "docker daemon not reachable"

  local image
  image="$(bash "${PHP_PLUGIN}" doctor --project "${PHP_FIXTURES}/with-rector" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["image"])')"

  run docker run --rm -v "${PHP_FIXTURES}/with-rector:/app" -w /app "${image}" \
    php -r 'echo file_exists("composer.json") ? "mounted" : "missing";'

  assert_success
  assert_output --partial "mounted"
}

# ── PHP plugin: config rendering + the real rename (T7) ────────────────────────



@test "ops.py render: emits exactly one configured rule" {
  run bash -c "printf '%s' '{\"op\":\"rename-method\",\"class\":\"Demo\\\\Greeter\",\"from\":\"greet\",\"to\":\"salute\",\"scope\":[\"/app/src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' render"

  assert_success
  assert_output --partial "RenameMethodRector::class"
  assert_output --partial "new MethodCallRename("
  assert_output --partial "withPaths(['/app/src'])"
  # Our config must never carry the project's rule sets.
  refute_output --partial "withPreparedSets"
  refute_output --partial "SetList"
}

@test "ops.py render: rejects an unsupported op" {
  run bash -c "printf '%s' '{\"op\":\"rename-everything\",\"from\":\"a\",\"to\":\"b\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render"

  assert_failure
  assert_output --partial "unsupported op"
}

@test "ops.py meta: declares the language, extension and current op set" {
  run python3 "${MODULE_DIR}/langs/php/ops.py" meta

  assert_success
  assert_output --partial '"lang": "php"'
  assert_output --partial '".php"'
  assert_output --partial '"rename-method"'
  assert_output --partial '"rename-static-method"'
  assert_output --partial '"rename-property"'
}

@test "ops.py rules: resolves the rule classes for an op" {
  run python3 "${MODULE_DIR}/langs/php/ops.py" rules rename-property

  assert_success
  assert_output --partial "RenamePropertyRector"
}

@test "ops.py rules: rejects an unknown op" {
  run python3 "${MODULE_DIR}/langs/php/ops.py" rules rename-everything

  assert_failure
  assert_output --partial "unsupported op"
}

@test "ops.py roots: reads the roots from composer autoload and autoload-dev" {
  run python3 "${MODULE_DIR}/langs/php/ops.py" roots "${PHP_FIXTURES}/scope-demo"

  assert_success
  assert_output '["src", "tests"]'
}

@test "ops.py roots: falls back to src/ when composer declares no autoload" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src"
  run python3 "${MODULE_DIR}/langs/php/ops.py" roots "${work}"
  rm -rf "${work}"

  assert_success
  assert_output '["src"]'
}

@test "ops.py roots: never includes a vendor-declared path" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/vendor/acme"
  printf '%s' '{"autoload":{"psr-4":{"Acme\\":"vendor/acme/"}}}' > "${work}/composer.json"
  run python3 "${MODULE_DIR}/langs/php/ops.py" roots "${work}"
  rm -rf "${work}"

  assert_success
  assert_output '["src"]'
}

@test "ops.py roots: rejects ./vendor and an escaping ../.. spelling" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src" "${work}/vendor/acme"
  cat > "${work}/composer.json" <<'JSON'
{"autoload":{"psr-4":{"Acme\\":"./vendor/acme/","Up\\":"../.."}}}
JSON
  run python3 "${MODULE_DIR}/langs/php/ops.py" roots "${work}"
  rm -rf "${work}"

  assert_success
  assert_output '["src"]'
}

@test "ops.py string-refs: a nested root does not duplicate a hit" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/Sub"
  printf '%s\n' '<?php' '' 'namespace Demo;' '' "final class Registry { public const NAME = 'Widget'; }" > "${work}/src/Sub/Registry.php"
  python3 - "${work}" > "${work}/request.json" <<'PY'
import json, sys
print(json.dumps({"op": "rename-class", "from": "Widget", "to": "Gadget",
                  "project": sys.argv[1], "roots": ["src", "src/Sub"]}))
PY
  run bash -c "python3 '${MODULE_DIR}/langs/php/ops.py' string-refs < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  local count
  count="$(printf '%s' "${output}" | grep -o 'Sub/Registry.php' | wc -l | tr -d ' ')"
  [ "${count}" = "1" ]
}

@test "ops.py resolve-class: a unique short name resolves to its FQCN" {
  run bash -c "printf '%s' '{\"op\":\"rename-method\",\"class\":\"Port\",\"from\":\"emit\",\"to\":\"publish\",\"project\":\"${PHP_FIXTURES}/scope-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' resolve-class"

  assert_success
  assert_output --partial '"class": "Demo\\Port"'
}

@test "ops.py resolve-class: an unknown class keeps the request and explains" {
  run bash -c "printf '%s' '{\"op\":\"rename-method\",\"class\":\"Nope\",\"from\":\"a\",\"to\":\"b\",\"project\":\"${PHP_FIXTURES}/scope-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' resolve-class"

  assert_success
  assert_output --partial "no declaration"
  assert_output --partial '"class": "Nope"'
}

@test "ops.py resolve-class: an ambiguous short name is explained, not guessed" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/A" "${work}/src/B"
  printf '%s\n' '<?php' '' 'namespace Demo\A;' '' 'class Thing {}' > "${work}/src/A/Thing.php"
  printf '%s\n' '<?php' '' 'namespace Demo\B;' '' 'class Thing {}' > "${work}/src/B/Thing.php"
  run bash -c "printf '%s' '{\"op\":\"rename-method\",\"class\":\"Thing\",\"from\":\"a\",\"to\":\"b\",\"project\":\"${work}\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' resolve-class"
  rm -rf "${work}"

  assert_success
  assert_output --partial "ambiguous"
  assert_output --partial 'Demo\\A\\Thing'
}

@test "ops.py resolve-class: a fully-qualified name is never retargeted" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/A" "${work}/src/B"
  printf '%s\n' '<?php' '' 'namespace Demo\A;' '' 'class Thing {}' > "${work}/src/A/Thing.php"
  printf '%s\n' '<?php' '' 'namespace Demo\B;' '' 'class Thing {}' > "${work}/src/B/Thing.php"
  python3 - "${work}" > "${work}/request.json" <<'PY'
import json, sys
print(json.dumps({"op": "rename-method", "class": "Demo\\A\\Thing", "from": "a", "to": "b", "project": sys.argv[1]}))
PY
  run bash -c "python3 '${MODULE_DIR}/langs/php/ops.py' resolve-class < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"class": "Demo\\A\\Thing"'
  refute_output --partial "notice"
}

@test "ops.py resolve-class: an FQCN with no declaration is not swapped for a namesake" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src/B"
  printf '%s\n' '<?php' '' 'namespace Demo\B;' '' 'class Thing {}' > "${work}/src/B/Thing.php"
  python3 - "${work}" > "${work}/request.json" <<'PY'
import json, sys
print(json.dumps({"op": "rename-method", "class": "Demo\\C\\Thing", "from": "a", "to": "b", "project": sys.argv[1]}))
PY
  run bash -c "python3 '${MODULE_DIR}/langs/php/ops.py' resolve-class < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"class": "Demo\\C\\Thing"'
  assert_output --partial "no declaration"
}

@test "ops.py text-refs: reports doc-block and code mentions but not quoted ones" {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/src"
  cat > "${work}/src/Thing.php" <<'PHP'
<?php

namespace Demo;

/** @see Thing::old() */
final class Thing
{
    public function old(): void
    {
        $name = 'old';
    }
}
PHP
  python3 - "${work}" > "${work}/request.json" <<'PY'
import json, sys
print(json.dumps({"op": "rename-method", "class": "Demo\\Thing", "from": "old", "to": "new", "project": sys.argv[1]}))
PY
  run bash -c "python3 '${MODULE_DIR}/langs/php/ops.py' text-refs < '${work}/request.json'"
  rm -rf "${work}"

  assert_success
  assert_output --partial "@see Thing::old"
  assert_output --partial "function old"
  refute_output --partial "\$name"
}

@test "end-to-end: plan reports both sites and writes nothing" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-method 'Demo\Greeter' greet salute > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' plan < '${work}/request.json'"

  local leaked
  leaked="$({ grep -rho salute "${work}/src" || true; } | wc -l | tr -d ' ')"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"ok": true'
  assert_output --partial "Would rename greet -> salute in 2 file(s)"
  # A dry run must not have touched the tree.
  [ "${leaked}" = "0" ]
}

@test "end-to-end: apply renames the declaration and the call site" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-method 'Demo\Greeter' greet salute > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local decl call
  decl="$(grep -c 'function salute' "${work}/src/Greeter.php" || true)"
  call="$(grep -c '\->salute(' "${work}/src/UseGreeter.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"ok": true'
  assert_output --partial "Renamed greet -> salute in 2 file(s)"
  # The declaration AND the call site must both have moved.
  [ "${decl}" = "1" ]
  [ "${call}" = "1" ]
}

@test "end-to-end: rename-static-method rewrites the declaration too" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-static-method 'Demo\Widget' make build > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local decl leftover call
  decl="$(grep -c 'function build' "${work}/src/Widget.php" || true)"
  leftover="$(grep -c 'function make' "${work}/src/Widget.php" || true)"
  call="$(grep -c 'Widget::build()' "${work}/src/UsesWidget.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"ok": true'
  # A call-site-only rename would leave 'function make' behind — broken code.
  [ "${decl}" = "1" ]
  [ "${leftover}" = "0" ]
  [ "${call}" = "1" ]
}

@test "end-to-end: rename-property rewrites the declaration and the access" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-property 'Demo\Widget' label caption > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local decl access
  decl="$(grep -c '\$caption' "${work}/src/Widget.php" || true)"
  access="$(grep -c '\->caption' "${work}/src/UsesWidget.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"ok": true'
  [ "${decl}" = "1" ]
  [ "${access}" = "1" ]
}


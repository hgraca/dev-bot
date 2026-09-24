#!/usr/bin/env bats
# =============================================================================
# src/agentic/refactor/tests/refactor_tests.bats
# Tests for the refactor module: lifecycle skeleton (T1) and, as it lands, the
# tool contract (mcp-meta, plugin registry, PHP plan/apply, safety gates).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="${MODULE_DIR}/tools/refactor/refactor.mcp.sh"
  FIXTURE_LANGS="${TEST_DIR}/fixtures/langs"
  PHP_PLUGIN="${MODULE_DIR}/langs/php/plugin.sh"
  PHP_FIXTURES="${TEST_DIR}/fixtures/php"
  TS_PLUGIN="${MODULE_DIR}/langs/ts/plugin.sh"
  TS_FIXTURES="${TEST_DIR}/fixtures/ts"
  PY_PLUGIN="${MODULE_DIR}/langs/py/plugin.sh"
  PY_FIXTURES="${TEST_DIR}/fixtures/py"
}

# True when the TypeScript plugin can run for real.
_ts_e2e_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
  bash "${TS_PLUGIN}" doctor --project "${TS_FIXTURES}/rename-demo" >/dev/null 2>&1
}

# True when the Python plugin can run for real.
_py_e2e_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
  bash "${PY_PLUGIN}" doctor --project "${PY_FIXTURES}/rename-demo" >/dev/null 2>&1
}

# ── Skeleton ───────────────────────────────────────────────────────────────────

@test "functions.sh: sources cleanly and exposes shared helpers" {
  run bash -c "source '${MODULE_DIR}/functions.sh' && declare -F _info >/dev/null && declare -F _warn >/dev/null"
  assert_success
}

@test "pre.sh: exits 0" {
  run bash "${MODULE_DIR}/pre.sh"
  assert_success
}

@test "install.sh: is idempotent (second run succeeds)" {
  run bash "${MODULE_DIR}/install.sh"
  assert_success

  run bash "${MODULE_DIR}/install.sh"
  assert_success
}

# ── Tool contract: mcp-meta + CLI surface (T2) ─────────────────────────────────

@test "mcp-meta: emits valid JSON with name=refactor" {
  run bash "${TOOL}" mcp-meta
  assert_success

  local name
  name="$(printf '%s' "${output}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')"
  [ "${name}" = "refactor" ]
}

@test "mcp-meta: declares a single required args array" {
  run bash "${TOOL}" mcp-meta
  assert_success

  local ok
  ok="$(printf '%s' "${output}" | python3 -c 'import json,sys; p=json.load(sys.stdin)["parameters"]; print("yes" if p["properties"]["args"]["type"]=="array" and p.get("required")==["args"] else "no")')"
  [ "${ok}" = "yes" ]
}

@test "--version: prints the tool version and exits 0" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"

  run bash "${TOOL}" --version
  assert_success
  assert_output --regexp "^refactor [0-9]+\.[0-9]+\.[0-9]+$"
}

@test "--help: prints usage and exits 0" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"

  run bash "${TOOL}" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "no args: reports an ERROR and exits non-zero" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"

  run bash "${TOOL}"
  assert_failure
  assert_output --partial "ERROR:"
}

# ── Plugin seam: registry + dispatch (T3) ──────────────────────────────────────
#
# The stublang fixture is a language the core has never heard of, discovered
# purely because it sits under REFACTOR_LANGS_DIR. These tests are the
# additivity proof: a new language needs no edit to refactor.ts.

@test "plugin seam: dispatches to a language discovered from REFACTOR_LANGS_DIR" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang stublang --op rename-method \
    --class 'App\Foo' --method old --to new

  assert_success
  assert_output --partial "## refactor: rename-method"
  assert_output --partial "**Engine:** stub 1.0.0"
  assert_output --partial "old -> new"
}

@test "plugin seam: forwards --apply to the plugin" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  command -v git >/dev/null 2>&1 || skip "git not installed"

  # Inside a clean throwaway repo: the core refuses --apply on a dirty tree, and
  # this test must not depend on the surrounding checkout's state.
  local repo
  repo="$(mktemp -d)"
  git -C "${repo}" init -q

  run bash -c "cd '${repo}' && REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang --op rename-method --class X --method old --to new --apply --json"
  rm -rf "${repo}"

  assert_success
  assert_output --partial '"applied": true'
}

@test "plugin seam: the request contract survives the hop" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang stublang --op rename-method \
    --class 'App\Foo' --method old --to new --json

  assert_success
  assert_output --partial '"op": "rename-method"'
  assert_output --partial '"from": "old"'
  assert_output --partial '"to": "new"'
}

@test "plugin seam: unknown language lists what is available" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang nope --op rename-method --class X --method a --to b

  assert_failure
  assert_output --partial "unknown language 'nope'"
  assert_output --partial "available: stublang"
}

@test "plugin seam: an op the plugin does not declare is rejected" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang stublang --op rename-class --class X --to b

  assert_failure
  assert_output --partial "does not support op 'rename-class'"
}

@test "plugin seam: an empty langs dir yields no available languages" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"

  local empty
  empty="$(mktemp -d)"
  export REFACTOR_LANGS_DIR="${empty}"

  run bash "${TOOL}" --lang php --op rename-method --class X --method a --to b
  rm -rf "${empty}"

  assert_failure
  assert_output --partial "unknown language 'php'"
  assert_output --partial "available: none"
}

# ── PHP plugin: engine resolution (T5) ─────────────────────────────────────────

@test "php plugin: meta declares php, the .php extension and all renamer ops" {
  run bash "${PHP_PLUGIN}" meta
  assert_success
  # Parse rather than match raw text: json.dumps spacing must not matter.
  printf '%s' "${output}" | python3 -c '
import json, sys
m = json.load(sys.stdin)
assert m["lang"] == "php", m
assert ".php" in m["extensions"], m
for op in ("rename-method", "rename-static-method", "rename-property"):
    assert op in m["ops"], m
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

# Build a request JSON via python — avoids nested shell-quoting entirely.
_req() {
  python3 - "$@" <<'PY'
import json, sys
args = (sys.argv[1:] + ["", "", "", ""])[:4]
op, klass, old, new = args
print(json.dumps({"op": op, "class": klass or None, "from": old, "to": new,
                  "apply": False, "scope": ["/app/src"]}))
PY
}

# True when a real end-to-end run is possible.
_e2e_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
  bash "${PHP_PLUGIN}" doctor --project "${PHP_FIXTURES}/bare" 2>/dev/null |
    grep -q '"via": "scratch"'
}

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

# ── Safety gates (T12) ─────────────────────────────────────────────────────────

# A throwaway git repo, optionally dirtied, for the working-tree guard.
_make_repo() {
  local repo="$1" dirty="$2"
  git -C "${repo}" init -q
  git -C "${repo}" config user.email t@example.com
  git -C "${repo}" config user.name tester
  printf 'clean\n' > "${repo}/a.txt"
  git -C "${repo}" add a.txt
  git -C "${repo}" commit -qm init
  [[ "${dirty}" == "dirty" ]] && printf 'dirty\n' >> "${repo}/a.txt"
  return 0
}

@test "safety: refuses --apply on a dirty working tree" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  command -v git >/dev/null 2>&1 || skip "git not installed"

  local repo
  repo="$(mktemp -d)"
  _make_repo "${repo}" dirty

  run bash -c "cd '${repo}' && REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang --op rename-method --class X --method a --to b --apply"
  rm -rf "${repo}"

  assert_failure
  assert_output --partial "working tree is dirty"
}

@test "safety: --force overrides the dirty-tree refusal" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  command -v git >/dev/null 2>&1 || skip "git not installed"

  local repo
  repo="$(mktemp -d)"
  _make_repo "${repo}" dirty

  run bash -c "cd '${repo}' && REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang --op rename-method --class X --method a --to b --apply --force"
  rm -rf "${repo}"

  assert_success
}

@test "safety: a dry run is allowed on a dirty working tree" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  command -v git >/dev/null 2>&1 || skip "git not installed"

  local repo
  repo="$(mktemp -d)"
  _make_repo "${repo}" dirty

  run bash -c "cd '${repo}' && REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang --op rename-method --class X --method a --to b"
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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang php --op rename-method --class 'Demo\\Greeter' --method greet --to salute --apply"

  local decl call
  decl="$(grep -c 'function salute' "${work}/src/Greeter.php" || true)"
  call="$(grep -c '\->salute(' "${work}/src/UseGreeter.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "## refactor: rename-method"
  assert_output --partial "Renamed greet -> salute"
  [ "${decl}" = "1" ]
  [ "${call}" = "1" ]
}

@test "end-to-end: files outside app/ and src/ are never rewritten" {
  _e2e_ready || skip "docker + scratch Rector not available"

  # Regression guard: Rector is scoped to app/ and src/ precisely so it never
  # descends into vendor/, which it does not exclude by default and would
  # otherwise rewrite. The decoy carries a same-named method. It is created here
  # rather than committed because the repo gitignores vendor/.
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

# ── Tier 1: rename-annotation (B3) ─────────────────────────────────────────────

@test "ops.py render: rename-annotation renders the by-type value object" {
  run bash -c "printf '%s' '{\"op\":\"rename-annotation\",\"class\":\"Demo\\\\AnnotatedCase\",\"from\":\"test\",\"to\":\"scenario\",\"scope\":[\"/app/src\"]}' | python3 '${MODULE_DIR}/langs/php/ops.py' render"

  assert_success
  assert_output --partial "RenameAnnotationRector::class"
  assert_output --partial "new RenameAnnotationByType("
}

@test "end-to-end: rename-annotation rewrites the docblock annotations" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-annotation 'Demo\AnnotatedCase' test scenario > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local added removed
  added="$(grep -c '@scenario' "${work}/src/AnnotatedCase.php" || true)"
  removed="$(grep -c '@test' "${work}/src/AnnotatedCase.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"ok": true'
  # Both annotated methods moved, and no stale annotation remains.
  [ "${added}" = "2" ]
  [ "${removed}" = "0" ]
}

# ── D1: the custom declaration-rename rule ─────────────────────────────────────
#
# Rector's own renaming rules are usages-only; this rule supplies the missing
# declaration half. It is exercised directly here, mounted alongside a config,
# because it is a shipped PHP artifact rather than a rule Rector already has.

@test "declaration rule: renames a function declaration" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work cfg rules scratch
  work="$(mktemp -d)"
  cfg="$(mktemp)"
  rules="${MODULE_DIR}/langs/php/rules"
  scratch="${MODULE_DIR}/../../../storage/refactor/rector"

  mkdir -p "${work}/src"
  cat > "${work}/src/Helpers.php" <<'SRC'
<?php

declare(strict_types=1);

namespace Demo;

function oldHelper(string $value): string
{
    return $value;
}
SRC

  cat > "${cfg}" <<'CFG'
<?php

declare(strict_types=1);

use Devbot\Refactor\RenameDeclarationRector;
use Rector\Config\RectorConfig;

require_once '/refactor/rules/RenameDeclarationRector.php';

return RectorConfig::configure()
    ->withPaths(['/app/src'])
    ->withConfiguredRule(RenameDeclarationRector::class, [
        'kind' => 'function',
        'from' => 'oldHelper',
        'to' => 'newHelperDecl',
    ]);
CFG

  run docker run --rm \
    -v "${work}:/app" \
    -v "${cfg}:/refactor/rector.php:ro" \
    -v "${rules}:/refactor/rules:ro" \
    -v "${scratch}:/refactor-engine" \
    -w /app php:8.4-cli \
    php /refactor-engine/vendor/bin/rector process \
    --config /refactor/rector.php --clear-cache --no-progress-bar --output-format=json

  local renamed stale
  renamed="$(grep -c 'function newHelperDecl' "${work}/src/Helpers.php" || true)"
  stale="$(grep -c 'function oldHelper' "${work}/src/Helpers.php" || true)"
  rm -rf "${work}" "${cfg}"

  assert_success
  [ "${renamed}" = "1" ]
  [ "${stale}" = "0" ]
}

# ── D2: rename-function (usages rule + declaration rule) ───────────────────────

@test "ops.py render: rename-function step 0 is the qualified usages rule" {
  run bash -c "printf '%s' '{\"op\":\"rename-function\",\"from\":\"demoHelper\",\"to\":\"assistHelper\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render 0"

  assert_success
  assert_output --partial "RenameFunctionRector::class"
  assert_output --partial "assistHelper"
  refute_output --partial "RenameDeclarationRector"
}

@test "ops.py render: rename-function step 1 is the declaration rule" {
  run bash -c "printf '%s' '{\"op\":\"rename-function\",\"from\":\"demoHelper\",\"to\":\"assistHelper\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render 1"

  assert_success
  assert_output --partial "RenameDeclarationRector::class"
  assert_output --partial "'kind' => 'function'"
  assert_output --partial "require_once"
}

@test "ops.py rules: rename-function registers two rules" {
  run python3 "${MODULE_DIR}/langs/php/ops.py" rules rename-function

  assert_success
  assert_output --partial "RenameFunctionRector"
  assert_output --partial "RenameDeclarationRector"
}

@test "ops.py render: a missing declaration errors with a hint" {
  run bash -c "printf '%s' '{\"op\":\"rename-function\",\"from\":\"nope\",\"to\":\"x\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render"

  assert_failure
  assert_output --partial "could not find a declaration of 'nope'"
}

@test "ops.py render: every generated step is valid PHP" {
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker info >/dev/null 2>&1 || skip "docker daemon not reachable"

  # Substring assertions cannot catch a structurally broken config — an earlier
  # renderer bug emitted unbalanced parentheses that passed them. Lint each step.
  local step cfg
  for step in 0 1; do
    cfg="$(mktemp)"
    printf '%s' "{\"op\":\"rename-function\",\"from\":\"demoHelper\",\"to\":\"assistHelper\",\"scope\":[\"/app/src\"],\"project\":\"${PHP_FIXTURES}/rename-demo\"}" |
      python3 "${MODULE_DIR}/langs/php/ops.py" render "${step}" > "${cfg}"

    run docker run --rm -v "${cfg}:/r/rector.php:ro" php:8.4-cli php -l /r/rector.php
    rm -rf "${cfg}"

    assert_success
    assert_output --partial "No syntax errors"
  done
}

@test "end-to-end: rename-function rewrites the declaration and the call" {
  _e2e_ready || skip "docker + scratch Rector not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PHP_FIXTURES}/rename-demo/." "${work}/"
  _req rename-function '' demoHelper assistHelper > "${work}/request.json"

  run bash -c "REFACTOR_PROJECT='${work}' bash '${PHP_PLUGIN}' apply < '${work}/request.json'"

  local decl call stale
  decl="$(grep -c 'function assistHelper' "${work}/src/Helpers.php" || true)"
  stale="$(grep -c 'function demoHelper' "${work}/src/Helpers.php" || true)"
  call="$(grep -c 'assistHelper(' "${work}/src/UsesHelper.php" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"ok": true'
  # Both halves: the declaration and the call site.
  [ "${decl}" = "1" ]
  [ "${stale}" = "0" ]
  [ "${call}" = "1" ]
}

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
  command -v bun >/dev/null 2>&1 || skip "bun not installed"

  run bash "${TOOL}" --lang php --op rename-method --class 'Demo\Greeter' --method greet

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
}

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
assert set(m["risks"]) == set(m["ops"]), "every op needs a risk"
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

# ── L1: the TypeScript plugin ──────────────────────────────────────────────────

@test "ts plugin: meta declares the language, extensions and its op" {
  run bash "${TS_PLUGIN}" meta
  assert_success

  printf '%s' "${output}" | python3 -c '
import json, sys
m = json.load(sys.stdin)
assert m["lang"] == "ts", m
assert ".ts" in m["extensions"], m
assert m["ops"] == ["rename-symbol"], m
assert m["requires"]["rename-symbol"] == ["from", "to"], m
assert m["risks"]["rename-symbol"] == "rename", m
'
}

@test "core: a second language needs no core change" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"

  # The core knows no op names: it validates against whatever the plugin declares,
  # which is what makes `langs/<lang>/` additive.
  run bash "${TOOL}" --lang ts --op rename-symbol --from greet

  assert_failure
  assert_output --partial "requires --to"
}

@test "end-to-end (ts): rename-symbol renames the declaration and the reference" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/rename-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op rename-symbol --from greet --to salute --apply"

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

# ── L2: the Python plugin ──────────────────────────────────────────────────────

@test "py plugin: meta declares the language, extensions and its op" {
  run bash "${PY_PLUGIN}" meta
  assert_success

  printf '%s' "${output}" | python3 -c '
import json, sys
m = json.load(sys.stdin)
assert m["lang"] == "py", m
assert m["extensions"] == [".py"], m
assert m["ops"] == ["rename-symbol"], m
assert m["requires"]["rename-symbol"] == ["from", "to"], m
assert m["risks"]["rename-symbol"] == "rename", m
'
}

@test "end-to-end (py): rename-symbol renames the definition and the reference" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PY_FIXTURES}/rename-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang py --op rename-symbol --from greet --to salute --apply"

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

  run bash -c "python3 '${MODULE_DIR}/langs/py/string_refs.py' < '${req}'"
  rm -f "${req}"

  assert_success
  printf '%s' "${output}" | python3 -c '
import json, sys
hits = [h for h in json.load(sys.stdin)["hits"] if h["file"].endswith("registry.py")]
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

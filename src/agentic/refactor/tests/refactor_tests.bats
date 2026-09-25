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
assert m["ops"] == ["rename-symbol", "move-file", "move-member", "privatize-members", "remove-unused-locals", "remove-unused-params"], m
assert m["requires"]["rename-symbol"] == ["from", "to"], m
assert m["requires"]["move-file"] == ["file", "to"], m
assert m["requires"]["move-member"] == ["class", "from", "to"], m
assert m["requires"]["privatize-members"] == [], m
assert m["requires"]["remove-unused-locals"] == ["file"], m
assert m["requires"]["remove-unused-params"] == ["file"], m
assert m["risks"]["rename-symbol"] == "rename", m
assert m["risks"]["move-file"] == "move", m
assert m["risks"]["move-member"] == "move", m
assert m["risks"]["privatize-members"] == "cleanup", m
assert m["risks"]["remove-unused-locals"] == "cleanup", m
assert m["risks"]["remove-unused-params"] == "signature", m
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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-file --file src/a.ts --to src/sub --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-file --file src/a.ts --to src/sub"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from make --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from make --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from make --to New"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from make --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from make --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from make --to Loose --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from make --to Slim --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from ping --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from make --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from make --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from make --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from ping --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from ping --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from measured --to New --apply"
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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from countdown --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op move-member --class Old --from _v --to New --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op privatize-members --class Base --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op privatize-members --class Base --apply"

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

@test "end-to-end (ts): privatize-members keeps an accessor pair together" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/privatize-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op privatize-members --class Base --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op privatize-members --class Base --apply"
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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op privatize-members --class Base"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op privatize-members --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op privatize-members --class Overloaded --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op privatize-members --class Merged --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op privatize-members --class Params --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op privatize-members --apply"
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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-locals --file src/locals.ts --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-locals --file src/locals.ts --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-locals --file src/locals.ts --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-locals --file src/mixed.ts --apply"

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

@test "end-to-end (ts): a remove-unused-locals plan writes nothing" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-locals --file src/locals.ts"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-params --file src/params.ts --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-params --file src/params.ts --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-params --file src/params.ts --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-params --file src/arrows.ts --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-params --file src/bound.ts --apply"

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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-params --file src/arrows.ts --apply"
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

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-params --file src/defaults.ts --apply"

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

@test "end-to-end (ts): a remove-unused-params plan writes nothing" {
  _ts_e2e_ready || skip "docker + ts-morph engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${TS_FIXTURES}/unused-demo/." "${work}/"

  run bash -c "cd '${work}' && bash '${TOOL}' --lang ts --op remove-unused-params --file src/params.ts"

  local still
  still="$(grep -c 'spare' "${work}/src/params.ts" || true)"
  rm -rf "${work}"

  assert_success
  assert_output --partial "Would remove"
  [ "${still}" = "1" ]
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

# ── L2: the Python plugin ──────────────────────────────────────────────────────

@test "py plugin: meta declares the language, extensions and its op" {
  run bash "${PY_PLUGIN}" meta
  assert_success

  printf '%s' "${output}" | python3 -c '
import json, sys
m = json.load(sys.stdin)
assert m["lang"] == "py", m
assert m["extensions"] == [".py"], m
assert m["ops"] == ["rename-symbol", "extract-method", "extract-variable", "inline", "encapsulate-field", "add-argument", "remove-argument", "move-module", "remove-unused-imports", "privatise"], m
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

@test "plugin seam: the core forwards --file to the plugin" {
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"
  run bash -c "REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang --op rename-method --class X --from a --to b --file stub/x.stub --json"

  assert_success
  assert_output --partial '"file": "stub/x.stub"'
}

@test "plugin seam: the core forwards --kind to the plugin" {
  run bash -c "REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang --op rename-method --class X --from a --to b --kind class --json"

  assert_success
  assert_output --partial '"kind": "class"'
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

@test "plugin seam: the core forwards --start/--end/--index/--default" {
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"
  run bash -c "REFACTOR_LANGS_DIR='${FIXTURE_LANGS}' bash '${TOOL}' --lang stublang --op rename-method --class X --from a --to b --start 2:3 --end 9 --index 4 --default 'z' --json"

  assert_success
  assert_output --partial '"start": "2:3"'
  assert_output --partial '"end": "9"'
  assert_output --partial '"index": "4"'
  assert_output --partial '"default": "z"'
}

@test "plugin seam: an extract op drives through the core to the py plugin" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PY_FIXTURES}/extract-demo/." "${work}/"

  run bash -c "cd '${work}' && REFACTOR_LANGS_DIR='${MODULE_DIR}/langs' bash '${TOOL}' --lang py --op extract-method --file src/calc.py --start 2 --end 3 --to compute --json"
  rm -rf "${work}"

  assert_success
  assert_output --partial '"ok": true'
}

@test "plugin seam: the markdown report shows the references a rename cannot reach" {
  _py_e2e_ready || skip "docker + rope engine not available"

  local work
  work="$(mktemp -d)"
  cp -r "${PY_FIXTURES}/rename-demo/." "${work}/"

  run bash -c "cd '${work}' && REFACTOR_LANGS_DIR='${MODULE_DIR}/langs' bash '${TOOL}' --lang py --op rename-symbol --from greet --to salute"
  rm -rf "${work}"

  assert_success
  # Default (markdown), not --json: the residual string references must show.
  assert_output --partial 'String references'
}

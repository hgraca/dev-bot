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

@test "ops.py render: rename-class is not supported yet" {
  # RenameClassRector rewrites references but not the class declaration, so a
  # class rename would emit broken code. Refuse rather than half-rename.
  run bash -c "printf '%s' '{\"op\":\"rename-class\",\"from\":\"App\\\\Old\",\"to\":\"App\\\\New\"}' | python3 '${MODULE_DIR}/langs/php/ops.py' render"

  assert_failure
  assert_output --partial "unsupported op"
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

@test "ops.py rule: resolves the rule class for an op" {
  run python3 "${MODULE_DIR}/langs/php/ops.py" rule rename-property

  assert_success
  assert_output --partial "RenamePropertyRector"
}

@test "ops.py rule: rejects an unknown op" {
  run python3 "${MODULE_DIR}/langs/php/ops.py" rule rename-everything

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

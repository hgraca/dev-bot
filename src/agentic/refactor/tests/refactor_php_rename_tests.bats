#!/usr/bin/env bats
# Split from refactor_tests.bats — shared setup()/helpers come from the load.
load 'refactor_test_helper'

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


#!/usr/bin/env bats
# =============================================================================
# src/agentic/docs/tests/gather-module-docs_tests.bats
# Tests for the module-owned docs gather script.
#
# Verifies the core invariant of the module-owned docs model: the site is built
# from src/<area>/<module>/docs.md — one page per module — and a module without
# a docs.md produces no page and appears in no reference.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../../.." && pwd)"
  GATHER="${PROJECT_ROOT}/src/agentic/docs/tools/gather-module-docs.sh"

  FIXTURE="${BATS_TEST_TMPDIR}/repo"
  OUT="${BATS_TEST_TMPDIR}/site"
  mkdir -p "${FIXTURE}/src/agentic/alpha" \
    "${FIXTURE}/src/agentic/beta/tools" \
    "${FIXTURE}/src/tools/gamma" \
    "${FIXTURE}/src/harnesses/delta"

  cat >"${FIXTURE}/src/agentic/alpha/docs.md" <<'EOF'
---
title: Alpha Module
description: Does alpha things.
---

Alpha body line.
EOF

  cat >"${FIXTURE}/src/tools/gamma/docs.md" <<'EOF'
---
description: Does gamma things.
---

Gamma body line.
EOF
}

@test "emits one page per module that has docs.md, none for modules without" {
  run "$GATHER" --root "$FIXTURE" --out "$OUT"
  [ "$status" -eq 0 ]
  [ -f "${OUT}/modules/agentic/alpha.md" ]
  [ -f "${OUT}/modules/tools/gamma.md" ]
  [ ! -e "${OUT}/modules/agentic/beta.md" ]
  [ ! -e "${OUT}/modules/harnesses/delta.md" ]
}

@test "generated page carries site front matter and the module body" {
  run "$GATHER" --root "$FIXTURE" --out "$OUT"
  [ "$status" -eq 0 ]
  grep -q '^layout: page' "${OUT}/modules/agentic/alpha.md"
  grep -q '^nav_section: docs' "${OUT}/modules/agentic/alpha.md"
  grep -q 'Does alpha things' "${OUT}/modules/agentic/alpha.md"
  grep -q 'Alpha body line' "${OUT}/modules/agentic/alpha.md"
}

@test "title defaults to a humanized module name when front matter omits it" {
  run "$GATHER" --root "$FIXTURE" --out "$OUT"
  [ "$status" -eq 0 ]
  grep -q 'title: "Gamma"' "${OUT}/modules/tools/gamma.md"
}

@test "data file lists documented modules only" {
  run "$GATHER" --root "$FIXTURE" --out "$OUT"
  [ "$status" -eq 0 ]
  grep -q 'name: "alpha"' "${OUT}/_data/modules.yml"
  grep -q 'name: "gamma"' "${OUT}/_data/modules.yml"
  ! grep -q 'beta' "${OUT}/_data/modules.yml"
}

@test "modules index links documented modules with baseurl-safe urls" {
  run "$GATHER" --root "$FIXTURE" --out "$OUT"
  [ "$status" -eq 0 ]
  [ -f "${OUT}/modules/index.md" ]
  grep -q 'relative_url' "${OUT}/modules/index.md"
  grep -q 'Alpha Module' "${OUT}/modules/index.md"
  grep -q 'Does gamma things' "${OUT}/modules/index.md"
}

@test "stale generated pages are pruned on re-run" {
  run "$GATHER" --root "$FIXTURE" --out "$OUT"
  [ "$status" -eq 0 ]
  mkdir -p "${OUT}/modules/agentic"
  echo stale >"${OUT}/modules/agentic/stale.md"
  run "$GATHER" --root "$FIXTURE" --out "$OUT"
  [ "$status" -eq 0 ]
  [ ! -e "${OUT}/modules/agentic/stale.md" ]
}

@test "a docs.md without the required description fails" {
  cat >"${FIXTURE}/src/agentic/beta/docs.md" <<'EOF'
---
title: Beta Module
---

Beta body.
EOF
  run "$GATHER" --root "$FIXTURE" --out "$OUT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'ERROR'
  echo "$output" | grep -q 'description'
}

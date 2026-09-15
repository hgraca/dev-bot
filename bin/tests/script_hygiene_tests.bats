#!/usr/bin/env bats
# =============================================================================
# bin/tests/script_hygiene_tests.bats
# Tree-wide conventions for every shell script in src/ and bin/.
#
# These are repo-level guards (like docs_install_url_tests.bats), not behavioural
# tests: they keep a convention from silently drifting back after it has been
# aligned once.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

# Every shell script in the repo, as paths relative to PROJECT_ROOT.
_all_scripts() {
  (cd "${PROJECT_ROOT}" && find src bin -name '*.sh' -type f 2>/dev/null | sort)
}

@test "every script resolves its own directory from BASH_SOURCE, never \$0" {
  # docs/create-a-module.md documents MODULE_DIR="$(cd "$(dirname
  # "${BASH_SOURCE[0]}")" && pwd)". $0 works when a script is executed but
  # resolves to the CALLER when it is sourced — so a sourced script would look
  # for its siblings in the wrong place. Aligned tree-wide; this keeps it that
  # way.
  local f found=0
  while IFS= read -r f; do
    if grep -q 'dirname "\$0"' "${PROJECT_ROOT}/${f}" 2>/dev/null; then
      echo "${f}: resolves its directory from \$0 instead of \${BASH_SOURCE[0]}"
      found=1
    fi
  done < <(_all_scripts)
  [ "${found}" -eq 0 ]
}

@test "every script ends with a newline" {
  local f found=0
  while IFS= read -r f; do
    if [[ -n "$(tail -c 1 "${PROJECT_ROOT}/${f}" 2>/dev/null)" ]]; then
      echo "${f}: does not end with a newline"
      found=1
    fi
  done < <(_all_scripts)
  [ "${found}" -eq 0 ]
}

@test "the scan actually sees the scripts (guards a stale glob)" {
  local n
  n="$(_all_scripts | wc -l)"
  [ "${n}" -gt 50 ] || fail "only ${n} scripts found — the scan is not seeing the tree"
}

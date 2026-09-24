#!/usr/bin/env bats
# =============================================================================
# bin/tests/docs_readme_toc_tests.bats
# Tests for the README documentation-TOC invariant.
#
# devbot:documentation-rules requires the root README.md to carry a TOC
# pointing at every committed doc under docs/. The module pages, the /modules
# index and the aggregate pages are *generated* by the docs module's gather
# script and are gitignored, so they never appear in `git ls-files docs` and
# are not part of this TOC.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  README="${PROJECT_ROOT}/README.md"
}

# docs/index.md is the docs frontpage; the README links the site root instead.
docs_page_is_toc_excluded() {
  case "$1" in
    docs/index.md) return 0 ;;
    *) return 1 ;;
  esac
}

@test "README TOC links every committed docs page" {
  local missing=()
  while IFS= read -r doc; do
    docs_page_is_toc_excluded "$doc" && continue
    grep -qF "(${doc})" "$README" || missing+=("$doc")
  done < <(git -C "$PROJECT_ROOT" ls-files docs | grep '\.md$')

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'docs pages missing from the README TOC:\n' >&2
    printf '  %s\n' "${missing[@]}" >&2
    return 1
  fi
}

@test "every docs link in the README resolves to a file" {
  local broken=()
  while IFS= read -r target; do
    [[ -f "${PROJECT_ROOT}/${target}" ]] || broken+=("$target")
  done < <(grep -oE '\]\(docs/[^) ]+\)' "$README" | sed -E 's/^\]\(//; s/\)$//')

  if [[ ${#broken[@]} -gt 0 ]]; then
    printf 'README links pointing at missing files:\n' >&2
    printf '  %s\n' "${broken[@]}" >&2
    return 1
  fi
}

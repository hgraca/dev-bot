#!/usr/bin/env bats
# =============================================================================
# bin/tests/docs_readme_toc_tests.bats
# Tests for the README documentation-TOC invariant.
#
# devbot:documentation-rules requires the root README.md to carry a TOC
# pointing at every text doc under docs/. Nothing enforced it, so the TOC
# drifted down to 2 of 31 pages. These tests close that gap: add a docs page
# without linking it, or link a page that no longer exists, and the suite fails.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  README="${PROJECT_ROOT}/README.md"
}

# Pages deliberately left out of the README TOC:
#   docs/opencode/*, docs/claudecode/* — excluded from the Jekyll build
#     (docs/_config.yml `exclude:`), so they are not published documentation.
#   docs/index.md — the docs frontpage itself; the README links the site root.
doc_is_toc_excluded() {
  case "$1" in
    docs/opencode/* | docs/claudecode/* | docs/index.md) return 0 ;;
    *) return 1 ;;
  esac
}

@test "README TOC links every published docs page" {
  local missing=()
  while IFS= read -r doc; do
    doc_is_toc_excluded "$doc" && continue
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

#!/usr/bin/env bats
# =============================================================================
# src/agentic/forensics/tests/pr_metrics_tests.bats
# Tests for `forensics prs`: the interval cache (only fetch what is missing) and
# the per-author + total metrics. A fake `gh` on PATH logs its calls, so the
# cache behaviour is asserted without any network.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="${MODULE_DIR}/tools/forensics.sh"
}

# A git repo whose origin points at GitHub, so the adapter can resolve the slug.
_init_repo_with_remote() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "git@github.com:GET-E/core.git"
}

# An offline `gh` stub: logs every call to $2 and answers `api` with one merged PR.
_write_fake_gh() {
  local bin="$1" log="$2"
  cat >"${bin}/gh" <<SH
#!/usr/bin/env bash
echo "\$*" >> "${log}"
case "\${1:-}" in
  api)
    cat <<'JSON'
{"data":{"search":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"number":4819,"author":{"login":"hgraca"},"createdAt":"2026-09-25T14:13:33Z","mergedAt":"2026-09-25T14:36:11Z","additions":749,"deletions":179,"changedFiles":32,"url":"https://github.com/GET-E/core/pull/4819","commits":{"totalCount":7}}]}}}
JSON
    ;;
  *) exit 1 ;;
esac
SH
  chmod +x "${bin}/gh"
}

# Run `prs` for $1 repo with the fake gh first on PATH. Args after repo are passed.
_run_prs() {
  local repo="$1" bin="$2"
  shift 2
  run env PATH="${bin}:${PATH}" bash "${TOOL}" prs "$repo" "$@"
}

@test "prs: fetches on the first run and reports the merged PRs" {
  local repo bin log
  repo="$(mktemp -d)"
  bin="$(mktemp -d)"
  log="${bin}/calls.log"
  _init_repo_with_remote "$repo"
  _write_fake_gh "$bin" "$log"

  _run_prs "$repo" "$bin" --since 2026-09-21 --until 2026-09-25 --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
total = doc["total"]
assert total["prs"] == 1, total
assert total["median_commits_per_pr"] == 7, total
assert total["median_changes_per_pr"] == 928, total
assert total["median_time_to_merge_hours"] == 0.38, total
assert total["prs_per_day"] == 0.2, total
assert [a["author"] for a in doc["authors"]] == ["hgraca"], doc["authors"]
'
  rm -rf "$repo" "$bin"
}

@test "prs: a repeat run is served from the cache with no remote call" {
  local repo bin log
  repo="$(mktemp -d)"
  bin="$(mktemp -d)"
  log="${bin}/calls.log"
  _init_repo_with_remote "$repo"
  _write_fake_gh "$bin" "$log"

  _run_prs "$repo" "$bin" --since 2026-09-21 --until 2026-09-25 --format json
  assert_success
  _run_prs "$repo" "$bin" --since 2026-09-21 --until 2026-09-25 --format json
  assert_success

  run grep -c "api" "$log"
  assert_output "1"
  rm -rf "$repo" "$bin"
}

@test "prs: a widened window fetches only the missing span" {
  local repo bin log
  repo="$(mktemp -d)"
  bin="$(mktemp -d)"
  log="${bin}/calls.log"
  _init_repo_with_remote "$repo"
  _write_fake_gh "$bin" "$log"

  _run_prs "$repo" "$bin" --since 2026-09-21 --until 2026-09-25 --format json
  assert_success
  _run_prs "$repo" "$bin" --since 2026-09-21 --until 2026-09-30 --format json
  assert_success

  run grep -c "api" "$log"
  assert_output "2"
  run grep -F "merged:2026-09-25..2026-09-30" "$log"
  assert_success
  rm -rf "$repo" "$bin"
}

@test "prs: --refresh forces a fetch of the whole window" {
  local repo bin log
  repo="$(mktemp -d)"
  bin="$(mktemp -d)"
  log="${bin}/calls.log"
  _init_repo_with_remote "$repo"
  _write_fake_gh "$bin" "$log"

  _run_prs "$repo" "$bin" --since 2026-09-21 --until 2026-09-25 --format json
  assert_success
  _run_prs "$repo" "$bin" --since 2026-09-21 --until 2026-09-25 --refresh --format json
  assert_success

  run grep -c "api" "$log"
  assert_output "2"
  rm -rf "$repo" "$bin"
}

@test "prs: a missing gh fails with an ERROR" {
  local repo bin empty
  repo="$(mktemp -d)"
  bin="$(mktemp -d)"
  empty="$(mktemp -d)"
  _init_repo_with_remote "$repo"
  _write_fake_gh "$bin" "${bin}/calls.log"

  run env FORENSICS_GH="${empty}/gh" PATH="${bin}:${PATH}" bash "${TOOL}" prs "$repo" --since 2026-09-21 --until 2026-09-25
  assert_failure
  assert_output --partial "ERROR"
  rm -rf "$repo" "$bin" "$empty"
}

@test "prs --format json: emits a total row and the per-author breakdown" {
  local repo bin
  repo="$(mktemp -d)"
  bin="$(mktemp -d)"
  _init_repo_with_remote "$repo"
  _write_fake_gh "$bin" "${bin}/calls.log"

  _run_prs "$repo" "$bin" --since 2026-09-21 --until 2026-09-25 --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert set(("total", "authors", "since", "until", "source")).issubset(doc), doc
assert doc["authors"][0]["prs"] == 1, doc["authors"]
'
  rm -rf "$repo" "$bin"
}

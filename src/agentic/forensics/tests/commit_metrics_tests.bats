#!/usr/bin/env bats
# =============================================================================
# src/agentic/forensics/tests/commit_metrics_tests.bats
# Tests for `forensics commits`: per-author commit metrics boxed to a window,
# with identities folded through the repo's .mailmap.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="${MODULE_DIR}/tools/forensics.sh"
  GM="${MODULE_DIR}/lib/gitmine.py"
}

# Three commits in 2026-09-22..24: two share one person by .mailmap, one is a
# second person. A file's size sets the churn: a.txt=2, b.txt=3, c.txt=1.
_build_mailmap_repo() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.name "Bot"
  git -C "$dir" config user.email "bot@example.com"
  git -C "$dir" config commit.gpgsign false

  printf '1\n2\n' >"${dir}/a.txt"
  git -C "$dir" add a.txt
  GIT_AUTHOR_NAME="Alice" GIT_AUTHOR_EMAIL="alice@example.com" \
    GIT_AUTHOR_DATE="2026-09-22T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-22T10:00:00+00:00" \
    git -C "$dir" commit -q -m "feat: a"

  printf '1\n2\n3\n' >"${dir}/b.txt"
  git -C "$dir" add b.txt
  GIT_AUTHOR_NAME="Alice Old" GIT_AUTHOR_EMAIL="alice.old@example.com" \
    GIT_AUTHOR_DATE="2026-09-23T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-23T10:00:00+00:00" \
    git -C "$dir" commit -q -m "feat: b"

  printf '1\n' >"${dir}/c.txt"
  git -C "$dir" add c.txt
  GIT_AUTHOR_NAME="Bob" GIT_AUTHOR_EMAIL="bob@example.com" \
    GIT_AUTHOR_DATE="2026-09-24T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-24T10:00:00+00:00" \
    git -C "$dir" commit -q -m "feat: c"

  cat >"${dir}/.mailmap" <<'MAP'
Alice <alice@example.com> <alice.old@example.com>
MAP
}

# ── gitmine: mailmap-aware author identity ─────────────────────────────────────

@test "gitmine log --mailmap: folds a commit email into the canonical identity" {
  local repo
  repo="$(mktemp -d)"
  _build_mailmap_repo "$repo"

  run python3 "${GM}" log --repo "$repo" --mailmap --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
emails = {c["author_email"] for c in doc["commits"]}
assert emails == {"alice@example.com", "bob@example.com"}, emails
'
  rm -rf "$repo"
}

@test "gitmine log: without --mailmap keeps the raw commit emails" {
  local repo
  repo="$(mktemp -d)"
  _build_mailmap_repo "$repo"

  run python3 "${GM}" log --repo "$repo" --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
emails = {c["author_email"] for c in doc["commits"]}
assert "alice.old@example.com" in emails, emails
'
  rm -rf "$repo"
}

# ── commits command ────────────────────────────────────────────────────────────

@test "commits: reports per author with .mailmap folding and a total" {
  local repo
  repo="$(mktemp -d)"
  _build_mailmap_repo "$repo"

  run bash "${TOOL}" commits "$repo" --since 2026-09-21 --until 2026-09-25 --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
total = doc["total"]
assert total["commits"] == 3, total
assert total["median_changes_per_commit"] == 2.0, total
assert total["commits_per_day"] == 0.6, total

authors = {a["author_email"]: a for a in doc["authors"]}
assert set(authors) == {"alice@example.com", "bob@example.com"}, list(authors)
assert authors["alice@example.com"]["commits"] == 2, authors
assert authors["alice@example.com"]["median_changes_per_commit"] == 2.5, authors
assert authors["bob@example.com"]["commits"] == 1, authors
'
  rm -rf "$repo"
}

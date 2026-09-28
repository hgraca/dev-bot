#!/usr/bin/env bats
# =============================================================================
# src/agentic/forensics/tests/sources_tests.bats
# Tests for the forensics provider-source adapters (sources/<name>/plugin.sh):
# discovery via `forensics sources` and the github adapter's `meta|doctor|fetch`.
# A fake `gh` on PATH keeps every test offline.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="${MODULE_DIR}/tools/forensics.sh"
  GITHUB_PLUGIN="${MODULE_DIR}/sources/github/plugin.sh"
}

# A git repo whose origin points at GitHub, so the adapter can resolve the slug.
_init_repo_with_remote() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "git@github.com:GET-E/core.git"
}

# Write an offline `gh` stub into $1/gh that answers the adapter's calls.
_write_fake_gh() {
  local bin="$1"
  cat >"${bin}/gh" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  auth) exit 0 ;;
  --version) echo "gh version 2.86.0" ;;
  api)
    cat <<'JSON'
{"data":{"repository":{"nameWithOwner":"GET-E/core"},"search":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"number":4819,"author":{"login":"hgraca"},"createdAt":"2026-09-25T14:13:33Z","mergedAt":"2026-09-25T14:36:11Z","additions":749,"deletions":179,"changedFiles":32,"url":"https://github.com/GET-E/core/pull/4819","commits":{"totalCount":7}}]}}}
JSON
    ;;
  *) exit 1 ;;
esac
SH
  chmod +x "${bin}/gh"
}

# ── Adapter contract (meta) ────────────────────────────────────────────────────

@test "sources/github meta: declares the pull-requests capability" {
  run bash "${GITHUB_PLUGIN}" meta
  assert_success
  echo "${output}" | python3 -c '
import json, sys
meta = json.load(sys.stdin)
assert meta["source"] == "github", meta
assert "pull-requests" in meta["capabilities"], meta
'
}

# ── Discovery (`forensics sources`) ────────────────────────────────────────────

@test "forensics sources: lists the github adapter" {
  run bash "${TOOL}" sources
  assert_success
  assert_output --partial "github"
}

@test "forensics sources --format json: emits the adapter metadata" {
  run bash "${TOOL}" sources --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
assert any(p["source"] == "github" for p in doc["sources"]), doc
'
}

@test "forensics sources: a fixture dir lists only its adapters" {
  run env FORENSICS_SOURCES_DIR="${TEST_DIR}/fixtures/sources-fixture" bash "${TOOL}" sources --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert [p["source"] for p in doc["sources"]] == ["fixture"], doc
'
}

# ── fetch ──────────────────────────────────────────────────────────────────────

@test "sources/github fetch: returns the merged PRs for the window" {
  local repo bin
  repo="$(mktemp -d)"
  bin="$(mktemp -d)"
  _init_repo_with_remote "$repo"
  _write_fake_gh "$bin"
  printf '{"project":"%s","since":"2026-09-21T00:00:00+00:00","until":"2026-09-25T23:59:59+00:00"}' "$repo" >"${bin}/payload.json"

  run bash -c "PATH=\"${bin}:\${PATH}\" bash '${GITHUB_PLUGIN}' fetch < '${bin}/payload.json'"
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
prs = doc["pull_requests"]
assert len(prs) == 1, prs
assert prs[0]["number"] == 4819, prs
assert prs[0]["author"] == "hgraca", prs
assert prs[0]["commits"] == 7, prs
assert prs[0]["added"] == 749 and prs[0]["deleted"] == 179, prs
assert prs[0]["merged_at"] == "2026-09-25T14:36:11Z", prs
'
  rm -rf "$repo" "$bin"
}

@test "sources/github fetch: a non-github origin fails" {
  local repo bin
  repo="$(mktemp -d)"
  bin="$(mktemp -d)"
  git -C "$repo" init -q
  git -C "$repo" remote add origin "git@gitlab.com:acme/widget.git"
  _write_fake_gh "$bin"
  printf '{"project":"%s","since":"2026-09-21T00:00:00+00:00","until":"2026-09-25T23:59:59+00:00"}' "$repo" >"${bin}/payload.json"

  run bash -c "PATH=\"${bin}:\${PATH}\" bash '${GITHUB_PLUGIN}' fetch < '${bin}/payload.json'"
  assert_failure
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is False, doc
assert "github.com" in doc["error"], doc
'
  rm -rf "$repo" "$bin"
}

# ── doctor ─────────────────────────────────────────────────────────────────────

@test "sources/github doctor: reports an authenticated gh as ok" {
  local bin
  bin="$(mktemp -d)"
  _write_fake_gh "$bin"

  run env FORENSICS_GH="${bin}/gh" bash "${GITHUB_PLUGIN}" doctor
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
assert doc["source"] == "github", doc
'
  rm -rf "$bin"
}

@test "sources/github doctor: reports a missing gh as not ok" {
  local missing
  missing="$(mktemp -d)"

  run env FORENSICS_GH="${missing}/gh" bash "${GITHUB_PLUGIN}" doctor
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is False, doc
'
  rm -rf "$missing"
}

# ── doctor (adapter reachability) ──────────────────────────────────────────────

@test "forensics sources doctor: reports an authenticated gh as ok" {
  local bin
  bin="$(mktemp -d)"
  _write_fake_gh "$bin"

  run env FORENSICS_GH="${bin}/gh" bash "${TOOL}" sources doctor
  assert_success
  assert_output --partial "github: ok"
  rm -rf "$bin"
}

@test "forensics sources doctor: a missing gh fails" {
  local missing
  missing="$(mktemp -d)"

  run env FORENSICS_GH="${missing}/gh" bash "${TOOL}" sources doctor
  assert_failure
  assert_output --partial "MISSING"
  rm -rf "$missing"
}

#!/usr/bin/env bats
# =============================================================================
# src/agentic/github/tests/gh-configure-repo_tests.bats
# Tests for tools/gh-configure-repo.mcp.sh — the repository reset tool.
# `gh` is stubbed and stateful: once a ruleset write succeeds, the effective
# rules endpoint reports the new rules, so the apply ordering is observable.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TOOL="${TEST_DIR}/../tools/gh-configure-repo.mcp.sh"

  BIN="$(mktemp -d)"
  GH_STATE="$(mktemp -d)"
  export GH_STATE
  export GH_LOG="$(mktemp)"
  export GH_SETTINGS="$(mktemp)"
  export GH_RULESET_BODY="$(mktemp)"
  export GH_REPO="GET-E/small-repo"
  export GH_BRANCH="main"
  export GH_ADMIN="true"
  export GH_CLASSIC="false"
  export GH_CLASSIC_JSON='{"enforce_admins":{"enabled":false}}'
  export GH_RULESETS_JSON='[]'
  export GH_RULESET_JSON=''
  export GH_PRE_RULES_JSON='[]'
  export GH_FAIL_WRITE="false"
  export GH_BYPASS_ROLE_ID="4"
  export GH_BYPASS_ROLE_NAME="write"

  _write_fake_gh
}

teardown() {
  rm -rf "$BIN" "$GH_STATE" "$GH_LOG" "$GH_SETTINGS" "$GH_RULESET_BODY"
}

_write_fake_gh() {
  cat >"${BIN}/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"

[[ "${1:-}" != "api" ]] && { echo "fake gh: only 'api' is supported" >&2; exit 1; }
shift

method="GET"
if [[ "${1:-}" == "--method" ]]; then method="$2"; shift 2; fi

endpoint=""
want_input=false
jq_filter=""
slurp=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) want_input=true; shift 2 ;;
    --jq) jq_filter="$2"; shift 2 ;;
    --slurp) slurp=true; shift ;;
    -F|-f|--field|--raw-field) shift 2 ;;
    -*) shift ;;
    *)
      [[ -z "$endpoint" ]] && endpoint="$1"
      shift
      ;;
  esac
done

stdin_body=""
[[ "$want_input" == true ]] && stdin_body="$(cat)"
if [[ -n "$stdin_body" ]]; then
  if [[ "$method" == "PATCH" ]]; then
    printf '%s' "$stdin_body" >"$GH_SETTINGS"
  else
    printf '%s' "$stdin_body" >"$GH_RULESET_BODY"
  fi
fi

admin="true"
[[ "${GH_ADMIN}" == "false" ]] && admin="false"

# A successful ruleset write makes the endpoint report the new state.
ruleset_id=""
if [[ "$method" == "POST" && "$endpoint" == *"/rulesets" ]]; then
  [[ "$GH_FAIL_WRITE" == "true" ]] && { echo '{"message":"Validation Failed","status":"422"}'; exit 1; }
  ruleset_id=77
  printf '%s' "$ruleset_id" >"$GH_STATE/id"
elif [[ "$method" == "PUT" && "$endpoint" == *"/rulesets/"* ]]; then
  [[ "$GH_FAIL_WRITE" == "true" ]] && { echo '{"message":"Validation Failed","status":"422"}'; exit 1; }
  ruleset_id="${endpoint##*/}"
  printf '%s' "$ruleset_id" >"$GH_STATE/id"
fi

response=""
case "$method $endpoint" in
  "GET repos/${GH_REPO}")
    response="$(printf '{"default_branch":"%s","permissions":{"admin":%s}}' "$GH_BRANCH" "$admin")"
    ;;
  "GET repos/${GH_REPO}/branches/"*/protection)
    if [[ "$GH_CLASSIC" == "true" ]]; then
      response="$GH_CLASSIC_JSON"
    else
      # Real `gh api` prints the 404 error body to stdout as well as stderr.
      echo '{"message":"Branch not found","status":"404"}'
      echo "gh: Branch not found (HTTP 404)" >&2
      exit 1
    fi
    ;;
  "GET repos/${GH_REPO}/branches/"*)
    response="$(printf '{"name":"%s"}' "${endpoint##*/}")"
    ;;
  "GET repos/${GH_REPO}/rulesets?per_page=100&includes_parents=false")
    response="$GH_RULESETS_JSON"
    ;;
  "GET repos/${GH_REPO}/rulesets/"*)
    response="$GH_RULESET_JSON"
    ;;
  "GET repos/${GH_REPO}/rules/branches/"*)
    if [[ -f "$GH_STATE/id" ]]; then
      id="$(cat "$GH_STATE/id")"
      # Echo the ruleset body the tool just wrote — the most faithful stand-in
      # for what the API would return.
      response="$(jq -c --argjson id "$id" --arg repo "$GH_REPO" --argjson bad "${GH_BAD_PARAMS:-false}" '
        [ .rules[]
          | (if $bad and .type == "pull_request"
             then .parameters.required_approving_review_count = 0 else . end)
          | . + {ruleset_id: $id, ruleset_source_type: "Repository", ruleset_source: $repo} ]' "$GH_RULESET_BODY")"
    else
      response="$GH_PRE_RULES_JSON"
    fi
    ;;
  "PATCH repos/${GH_REPO}")
    response='{}'
    ;;
  "DELETE repos/${GH_REPO}/branches/${GH_BRANCH}/protection")
    response='{}'
    ;;
  "DELETE repos/${GH_REPO}/rulesets/"*)
    if [[ "${GH_FAIL_ROLLBACK:-false}" == "true" ]]; then
      echo '{"message":"Server Error","status":"500"}'
      exit 1
    fi
    response='{}'
    ;;
  "POST repos/${GH_REPO}/rulesets")
    response='{"id":77}'
    ;;
  "PUT repos/${GH_REPO}/rulesets/"*)
    response='{"id":42}'
    ;;
  "GET graphql")
    if [[ "${GH_GRAPHQL_EMPTY:-false}" == "true" ]]; then
      response='{}'
    else
      response="$(printf '{"data":{"repository":{"ruleset":{"bypassActors":{"nodes":[{"repositoryRoleDatabaseId":%s,"repositoryRoleName":"%s"}]}}}}}' "$GH_BYPASS_ROLE_ID" "$GH_BYPASS_ROLE_NAME")"
    fi
    ;;
  *)
    echo "fake gh: unhandled call: $method $endpoint" >&2
    exit 1
    ;;
esac

[[ "$slurp" == true ]] && response="[$response]"

if [[ -n "$jq_filter" ]]; then
  printf '%s' "$response" | jq -r "$jq_filter"
else
  printf '%s\n' "$response"
fi
STUB
  chmod +x "${BIN}/gh"
}

_run() {
  run env PATH="${BIN}:${PATH}" bash "$TOOL" "GET-E/small-repo" "$@"
}

# ── Safety ───────────────────────────────────────────────────────────────────

@test "dry run is the default and writes nothing" {
  _run

  assert_success
  assert_output --partial "DRY RUN"
  # Positive control: the log is being read, and it holds GETs.
  grep -q "^api repos/${GH_REPO}" "$GH_LOG"
  ! grep -qE -- "--method (PATCH|POST|PUT|DELETE)" "$GH_LOG"
}

@test "dry run --json emits a parseable plan" {
  _run --json

  assert_success
  echo "$output" | jq -e '.mode == "dry-run" and .ruleset.name == "default-branch"' >/dev/null
  ! grep -qE -- "--method (PATCH|POST|PUT|DELETE)" "$GH_LOG"
}

@test "apply --json emits a machine-readable result" {
  _run --apply --json

  assert_success
  echo "$output" | jq -e '(.mode == "applied") and (.effective_rules | test("pull_request"))' >/dev/null
  echo "$output" | jq -e '.override.check == "confirmed role write (id 4)"' >/dev/null
}

# ── Repository settings ──────────────────────────────────────────────────────

@test "apply writes exactly the standard pull-request and merge settings" {
  _run --apply

  assert_success
  run jq -r 'keys | sort | join(",")' "$GH_SETTINGS"
  assert_output "allow_auto_merge,allow_merge_commit,allow_rebase_merge,allow_squash_merge,allow_update_branch,delete_branch_on_merge,has_pull_requests,merge_commit_message,merge_commit_title,pull_request_creation_policy,squash_merge_commit_message,squash_merge_commit_title"

  run jq -r '[.has_pull_requests, .pull_request_creation_policy, .merge_commit_title,
              .merge_commit_message, .squash_merge_commit_title, .squash_merge_commit_message,
              .allow_update_branch, .allow_auto_merge, .delete_branch_on_merge] | @tsv' "$GH_SETTINGS"
  assert_output "$(printf 'true\tall\tPR_TITLE\tPR_BODY\tPR_TITLE\tBLANK\ttrue\ttrue\ttrue')"
}

@test "feature toggles are never sent" {
  _run --apply

  assert_success
  run jq -r '[has("has_issues"), has("has_wiki"), has("has_projects"), has("has_discussions")] | any' "$GH_SETTINGS"
  assert_output "false"
}

# ── Ruleset ──────────────────────────────────────────────────────────────────

@test "apply creates the ruleset with the standard rules" {
  _run --apply

  assert_success
  run jq -r '[.rules[].type] | sort | join(",")' "$GH_RULESET_BODY"
  assert_output "deletion,non_fast_forward,pull_request"

  run jq -r '.rules[] | select(.type=="pull_request") | [.parameters.required_approving_review_count, .parameters.required_review_thread_resolution, .parameters.dismiss_stale_reviews_on_push, .parameters.require_last_push_approval] | @tsv' "$GH_RULESET_BODY"
  assert_output "$(printf '1\ttrue\tfalse\tfalse')"

  run jq -r '.conditions.ref_name.include[0]' "$GH_RULESET_BODY"
  assert_output "~DEFAULT_BRANCH"
}

@test "the default override is the write role in pull-request mode" {
  _run --apply

  assert_success
  assert_output --partial "override: confirmed role write (id 4)"
  run jq -c '.bypass_actors' "$GH_RULESET_BODY"
  assert_output '[{"actor_type":"RepositoryRole","actor_id":4,"bypass_mode":"pull_request"}]'
}

@test "--bypass-role admin maps to role id 5" {
  export GH_BYPASS_ROLE_ID="5" GH_BYPASS_ROLE_NAME="admin"

  _run --apply --bypass-role admin

  assert_success
  run jq -r '.bypass_actors[0].actor_id' "$GH_RULESET_BODY"
  assert_output "5"
}

@test "--bypass none writes no bypass actors" {
  _run --apply --bypass none

  assert_success
  run jq -r '.bypass_actors | length' "$GH_RULESET_BODY"
  assert_output "0"
}

@test "read and triage cannot be bypass actors" {
  _run --apply --bypass-role read

  assert_failure 2
  assert_output --partial "write permission"
}

@test "an unknown option is a usage error" {
  _run --nope

  assert_failure 2
  assert_output --partial "unknown option"
}

@test "a non-admin repository is refused" {
  export GH_ADMIN="false"

  _run --apply

  assert_failure
  assert_output --partial "admin permission"
}

# ── Status checks ────────────────────────────────────────────────────────────

@test "status checks are carried from classic contexts and app-pinned checks" {
  export GH_CLASSIC="true"
  export GH_EXPECT_CHECKS="true"
  export GH_CLASSIC_JSON='{"enforce_admins":{"enabled":false},"required_status_checks":{"strict":false,"contexts":["phpstan"],"checks":[{"context":"php (8.4)","app_id":15368}]}}'

  _run --apply

  assert_success
  run jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks | map(.context) | sort | join(",")' "$GH_RULESET_BODY"
  assert_output "php (8.4),phpstan"

  # The app-pinned check keeps its integration; the unpinned one carries none.
  run jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks
              | map(select(.context=="php (8.4)") | .integration_id) | @tsv' "$GH_RULESET_BODY"
  assert_output "15368"

  run jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks
              | map(select(.context=="phpstan") | has("integration_id")) | @tsv' "$GH_RULESET_BODY"
  assert_output "false"
}

@test "strict is carried from classic protection instead of forced on" {
  export GH_CLASSIC="true"
  export GH_EXPECT_CHECKS="true"
  export GH_CLASSIC_JSON='{"enforce_admins":{"enabled":false},"required_status_checks":{"strict":false,"contexts":["phpstan"]}}'

  _run --apply

  assert_success
  run jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.strict_required_status_checks_policy' "$GH_RULESET_BODY"
  assert_output "false"
}

@test "status checks are carried from an existing ruleset" {
  export GH_RULESETS_JSON='[{"id":42,"name":"default-branch","source_type":"Repository","target":"branch"}]'
  export GH_RULESET_JSON='{"name":"default-branch","target":"branch","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"phpstan","integration_id":15368}]}}]}'
  export GH_EXPECT_CHECKS="true"

  _run --apply

  assert_success
  run jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks | map(.context) | join(",")' "$GH_RULESET_BODY"
  assert_output "phpstan"

  run jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[0].integration_id' "$GH_RULESET_BODY"
  assert_output "15368"
}

@test "--required-check adds a check and merges with the carried ones" {
  export GH_CLASSIC="true"
  export GH_EXPECT_CHECKS="true"
  export GH_CLASSIC_JSON='{"enforce_admins":{"enabled":false},"required_status_checks":{"strict":true,"contexts":["phpstan"]}}'

  _run --apply --required-check "integration"

  assert_success
  run jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks | map(.context) | sort | join(",")' "$GH_RULESET_BODY"
  assert_output "integration,phpstan"
}

@test "no status-check rule is added when none already exist" {
  _run --apply

  assert_success
  run jq -r '[.rules[].type] | index("required_status_checks") // "absent"' "$GH_RULESET_BODY"
  assert_output "absent"
}

@test "an unverifiable override rolls a newly created ruleset back" {
  export GH_CLASSIC="true"
  export GH_GRAPHQL_EMPTY="true"

  _run --apply --remove-classic-protection

  assert_failure
  assert_output --partial "removed the newly created ruleset"
  grep -q "DELETE repos/${GH_REPO}/rulesets/77" "$GH_LOG"
  ! grep -q "DELETE repos/${GH_REPO}/branches/${GH_BRANCH}/protection" "$GH_LOG"
}

@test "a failed rollback is reported instead of claiming restoration" {
  export GH_GRAPHQL_EMPTY="true"
  export GH_FAIL_ROLLBACK="true"

  _run --apply

  assert_failure
  assert_output --partial "ROLLBACK FAILED"
  assert_output --partial "delete it manually"
}

@test "an unverifiable override restores an updated ruleset" {
  export GH_RULESETS_JSON='[{"id":42,"name":"default-branch","source_type":"Repository","target":"branch"}]'
  export GH_RULESET_JSON='{"name":"default-branch","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"}],"bypass_actors":[]}'
  export GH_GRAPHQL_EMPTY="true"

  _run --apply

  assert_failure
  assert_output --partial "restored the previous ruleset definition"
  [ "$(grep -c "PUT repos/${GH_REPO}/rulesets/42" "$GH_LOG")" -ge 2 ]
}

@test "a same-name tag ruleset is refused instead of retargeted" {
  export GH_RULESETS_JSON='[{"id":55,"name":"default-branch","source_type":"Repository","target":"tag"}]'

  _run --apply

  assert_failure
  assert_output --partial "names a non-branch ruleset"
  ! grep -q "PUT repos/${GH_REPO}/rulesets" "$GH_LOG"
}

@test "an existing ruleset strict status-check policy is preserved" {
  export GH_RULESETS_JSON='[{"id":42,"name":"default-branch","source_type":"Repository","target":"branch"}]'
  export GH_RULESET_JSON='{"name":"default-branch","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"required_status_checks":[{"context":"phpstan"}]}}]}'

  _run --apply

  assert_success
  run jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.strict_required_status_checks_policy' "$GH_RULESET_BODY"
  assert_output "false"
}

@test "an enterprise ruleset is never deleted" {
  export GH_PRE_RULES_JSON='[{"type":"non_fast_forward","ruleset_id":88,"ruleset_source_type":"Enterprise","ruleset_source":"acme"}]'

  _run --apply --reset-other-rulesets

  assert_success
  assert_output --partial "enterprise ruleset"
  ! grep -q "DELETE repos/${GH_REPO}/rulesets/88" "$GH_LOG"
}

@test "stored rule parameters are validated before cleanup" {
  export GH_CLASSIC="true"
  export GH_BAD_PARAMS="true"

  _run --apply --remove-classic-protection

  assert_failure
  assert_output --partial "pull_request parameters differ"
  ! grep -q "DELETE repos/${GH_REPO}/branches/${GH_BRANCH}/protection" "$GH_LOG"
}

@test "--default-branch protects the branch the caller named" {
  _run --apply --default-branch release

  assert_success
  run jq -r '.conditions.ref_name.include[0]' "$GH_RULESET_BODY"
  assert_output "refs/heads/release"
}

@test "checks from a ruleset being reset are carried before it is deleted" {
  export GH_PRE_RULES_JSON='[{"type":"required_status_checks","ruleset_id":99,"ruleset_source_type":"Repository","ruleset_source":"GET-E/small-repo","parameters":{"required_status_checks":[{"context":"legacy-ci","integration_id":15368}]}}]'
  export GH_EXPECT_CHECKS="true"

  _run --apply --reset-other-rulesets

  assert_success
  grep -q "DELETE repos/${GH_REPO}/rulesets/99" "$GH_LOG"
  run jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks
              | map(select(.context=="legacy-ci") | .integration_id) | @tsv' "$GH_RULESET_BODY"
  assert_output "15368"
}

# ── Classic protection: kept by default, removed on request ─────────────────

@test "classic protection is kept by default" {
  export GH_CLASSIC="true"

  _run --apply

  assert_success
  ! grep -q "DELETE repos/${GH_REPO}/branches/${GH_BRANCH}/protection" "$GH_LOG"
  assert_output --partial "legacy classic branch protection remains"
}

@test "--remove-classic-protection deletes it" {
  export GH_CLASSIC="true"

  _run --apply --remove-classic-protection

  assert_success
  grep -q "DELETE repos/${GH_REPO}/branches/${GH_BRANCH}/protection" "$GH_LOG"
  assert_output --partial "removed legacy classic protection"
}

@test "a 404 on the protection endpoint is not mistaken for classic protection" {
  _run --apply --remove-classic-protection

  assert_success
  assert_output --partial "legacy classic protection: none"
  ! grep -q "DELETE repos/${GH_REPO}/branches/${GH_BRANCH}/protection" "$GH_LOG"
}

# ── Ordering: protection first, deletions after ─────────────────────────────

@test "the ruleset is written before classic protection is deleted" {
  export GH_CLASSIC="true"

  _run --apply --remove-classic-protection

  assert_success
  local post put del
  post=$(grep -n -- "method POST repos/${GH_REPO}/rulesets\|method PUT repos/${GH_REPO}/rulesets" "$GH_LOG" | head -1 | cut -d: -f1)
  del=$(grep -n -- "DELETE repos/${GH_REPO}/branches/${GH_BRANCH}/protection" "$GH_LOG" | head -1 | cut -d: -f1)
  [ -n "$post" ] && [ -n "$del" ] && [ "$post" -lt "$del" ]
}

@test "a failed ruleset write leaves classic protection in place" {
  export GH_CLASSIC="true"
  export GH_FAIL_WRITE="true"

  _run --apply --remove-classic-protection

  assert_failure
  assert_output --partial "failed to create ruleset"
  ! grep -q "DELETE repos/${GH_REPO}/branches/${GH_BRANCH}/protection" "$GH_LOG"
}

# ── Other rulesets ──────────────────────────────────────────────────────────

@test "another repository ruleset on the branch is kept by default" {
  export GH_PRE_RULES_JSON='[{"type":"non_fast_forward","ruleset_id":99,"ruleset_source_type":"Repository","ruleset_source":"GET-E/small-repo"}]'

  _run --apply

  assert_success
  assert_output --partial "left alone"
  ! grep -q "DELETE repos/${GH_REPO}/rulesets/99" "$GH_LOG"
}

@test "--reset-other-rulesets deletes another repository ruleset" {
  export GH_PRE_RULES_JSON='[{"type":"non_fast_forward","ruleset_id":99,"ruleset_source_type":"Repository","ruleset_source":"GET-E/small-repo"}]'

  _run --apply --reset-other-rulesets

  assert_success
  grep -q "DELETE repos/${GH_REPO}/rulesets/99" "$GH_LOG"
}

@test "an organization ruleset is reported and never deleted" {
  export GH_PRE_RULES_JSON='[{"type":"non_fast_forward","ruleset_id":55,"ruleset_source_type":"Organization","ruleset_source":"GET-E"}]'

  _run --apply --reset-other-rulesets

  assert_success
  assert_output --partial "organization ruleset"
  assert_output --partial "cannot be changed from this repository"
  ! grep -q "DELETE repos/${GH_REPO}/rulesets/55" "$GH_LOG"
}

@test "a tag ruleset is not treated as a branch ruleset" {
  # A tag ruleset never appears in the branch's effective rules.
  export GH_PRE_RULES_JSON='[]'

  _run --apply --reset-other-rulesets

  assert_success
  ! grep -q "DELETE repos/${GH_REPO}/rulesets/" "$GH_LOG"
}

# ── Idempotency ─────────────────────────────────────────────────────────────

@test "a second run updates in place with an identical body" {
  _run --apply
  assert_success
  cp "$GH_SETTINGS" "${BIN}/settings.first"
  cp "$GH_RULESET_BODY" "${BIN}/ruleset.first"
  ! grep -q "PUT repos/${GH_REPO}/rulesets" "$GH_LOG"

  export GH_RULESETS_JSON='[{"id":42,"name":"default-branch","source_type":"Repository","target":"branch"}]'
  export GH_RULESET_JSON='{"name":"default-branch","target":"branch","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"copilot_code_review"}]}'

  _run --apply
  assert_success
  grep -q "PUT repos/${GH_REPO}/rulesets/42" "$GH_LOG"
  diff "${BIN}/settings.first" "$GH_SETTINGS"
  diff "${BIN}/ruleset.first" "$GH_RULESET_BODY"
}

@test "reset drops rules the tool does not manage" {
  export GH_RULESETS_JSON='[{"id":42,"name":"default-branch","source_type":"Repository","target":"branch"}]'
  export GH_RULESET_JSON='{"name":"default-branch","target":"branch","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"copilot_code_review"}]}'

  _run --apply

  assert_success
  run jq -r '[.rules[].type] | sort | join(",")' "$GH_RULESET_BODY"
  assert_output "deletion,non_fast_forward,pull_request"
}

@test "an existing ruleset targeting another ref is retargeted at the default branch" {
  export GH_RULESETS_JSON='[{"id":42,"name":"default-branch","source_type":"Repository","target":"branch"}]'
  export GH_RULESET_JSON='{"name":"default-branch","target":"branch","conditions":{"ref_name":{"include":["refs/heads/other"],"exclude":[]}},"rules":[{"type":"deletion"}]}'

  _run --apply

  assert_success
  run jq -r '.conditions.ref_name.include[0]' "$GH_RULESET_BODY"
  assert_output "~DEFAULT_BRANCH"
}

@test "the commit-comments setting is reported as manual" {
  _run --apply

  assert_success
  assert_output --partial "Allow comments on individual commits"
}

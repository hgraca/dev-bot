#!/usr/bin/env bash
# ---
# description: Reset an existing GitHub repository to the devbot standard — pull-request merge settings, merged-branch cleanup, and a single default-branch ruleset (PR + 1 approval with an override, conversation resolution, carried-over status checks, no force push, no deletion). Keeps legacy classic protection by default. Dry-run by default; pass --apply to write.
# ---
# =============================================================================
# src/agentic/github/tools/gh-configure-repo.mcp.sh
# Reset an existing GitHub repository to the devbot standard, idempotently.
#
# Usage:
#   gh-configure-repo.mcp.sh <owner/repo> [--apply] [options]
#
# Options:
#   --apply                        write the changes (default: dry run)
#   --default-branch <name>        branch to protect (default: detected)
#   --ruleset-name <name>          ruleset name (default: default-branch)
#   --bypass <pull-request|always|none>
#                                  how the override works (default: pull-request)
#   --bypass-role <write|maintain|admin|N>
#                                  role allowed to override (default: write)
#   --required-check <context>     extra required status check; repeatable
#   --remove-classic-protection    delete legacy protection (default: keep it)
#   --reset-other-rulesets         delete other repository rulesets on the branch
#   --json                         machine-readable summary
#   -h, --help                     show this help
#
# Legacy classic protection is KEPT by default: it layers with the ruleset and
# the most restrictive rule wins, so the override will not take effect until it
# is removed. Pass --remove-classic-protection to delete it.
#
# Not settable through the API: "Allow comments on individual commits"
# (Settings → Commits). The tool reports it as a manual step.
# =============================================================================

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: gh-configure-repo.mcp.sh <owner/repo> [--apply] [options]

  --apply                        write the changes (default: dry run)
  --dry-run                      explicit dry run (the default)
  --default-branch <name>        branch to protect (default: detected)
  --ruleset-name <name>          ruleset name (default: default-branch)
  --bypass <pull-request|always|none>
                                 how the override works (default: pull-request)
  --bypass-role <write|maintain|admin|N>
                                 role allowed to override (default: write)
                                 (alias: --bypass-role-id)
  --required-check <context>     extra required status check; repeatable
  --remove-classic-protection    delete legacy classic protection
                                 (default: keep it — the override won't apply)
  --reset-other-rulesets         delete other repository rulesets on the branch
  --json                         machine-readable summary
  -h, --help                     show this help
USAGE
}

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"gh-configure-repo","description":"Reset an existing GitHub repository to the devbot standard: pull-request merge settings, merged-branch cleanup, and a single default-branch ruleset (PR + approving review with an override, conversation resolution, carried-over status checks, no force push, no deletion). Keeps legacy classic protection unless --remove-classic-protection. Dry-run by default; pass --apply to write. Idempotent.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: <owner/repo> [--apply|--dry-run] [--default-branch <name>] [--ruleset-name <name>] [--bypass pull-request|always|none] [--bypass-role write|maintain|admin|N] [--required-check <context>] [--remove-classic-protection] [--reset-other-rulesets] [--json]"}},"required":["args"]}}
JSON
    exit 0
    ;;
  -h|--help)
    usage
    exit 0
    ;;
esac

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage_error() { printf 'ERROR: %s\n' "$*" >&2; usage >&2; exit 2; }

_require_value() {
  local flag="$1" value="${2:-}"
  if [[ -z "$value" || "$value" == -* ]]; then
    usage_error "$flag requires a value"
  fi
}

# ── Parse args ───────────────────────────────────────────────────────────────
REPO=""
APPLY=false
DEFAULT_BRANCH=""
BRANCH_EXPLICIT=false
RULESET_NAME="default-branch"
BYPASS="pull-request"
BYPASS_ROLE="write"
EXTRA_CHECKS=()
REMOVE_CLASSIC=false
RESET_OTHER=false
JSON_OUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    --dry-run) APPLY=false; shift ;;
    --default-branch) _require_value "$1" "${2:-}"; DEFAULT_BRANCH="$2"; BRANCH_EXPLICIT=true; shift 2 ;;
    --ruleset-name) _require_value "$1" "${2:-}"; RULESET_NAME="$2"; shift 2 ;;
    --bypass) _require_value "$1" "${2:-}"; BYPASS="$2"; shift 2 ;;
    --bypass-role|--bypass-role-id) _require_value "$1" "${2:-}"; BYPASS_ROLE="$2"; shift 2 ;;
    --required-check) _require_value "$1" "${2:-}"; EXTRA_CHECKS+=("$2"); shift 2 ;;
    --remove-classic-protection) REMOVE_CLASSIC=true; shift ;;
    --reset-other-rulesets) RESET_OTHER=true; shift ;;
    --json) JSON_OUT=true; shift ;;
    --help|-h) usage; exit 0 ;;
    -*) usage_error "unknown option: $1" ;;
    *)
      [[ -z "$REPO" ]] || usage_error "only one repository may be given"
      REPO="$1"; shift
      ;;
  esac
done

[[ -n "$REPO" ]] || usage_error "a repository (<owner/repo>) is required"
[[ "$REPO" == */* ]] || usage_error "repository must be <owner/repo>, got: $REPO"

case "$BYPASS" in
  none|pull-request|always) ;;
  *) usage_error "--bypass must be none, pull-request or always (got: $BYPASS)" ;;
esac

# Repository-role ids, measured against the live API: 2 maintain, 4 write,
# 5 admin. Read and triage cannot be bypass actors at all — GitHub rejects a
# bypass actor whose base role lacks write permission.
BYPASS_ROLE_ID=""
BYPASS_ROLE_NAME=""
if [[ "$BYPASS" != "none" ]]; then
  case "$BYPASS_ROLE" in
    write) BYPASS_ROLE_ID=4; BYPASS_ROLE_NAME="write" ;;
    maintain) BYPASS_ROLE_ID=2; BYPASS_ROLE_NAME="maintain" ;;
    admin) BYPASS_ROLE_ID=5; BYPASS_ROLE_NAME="admin" ;;
    read|triage)
      usage_error "$BYPASS_ROLE cannot bypass a ruleset — GitHub requires the actor's role to have write permission (use write, maintain or admin)"
      ;;
    *[!0-9]*) usage_error "--bypass-role must be write, maintain, admin or a numeric id (got: $BYPASS_ROLE)" ;;
    *) BYPASS_ROLE_ID="$BYPASS_ROLE" ;;
  esac
fi

command -v gh >/dev/null 2>&1 || die "gh CLI not found"
command -v jq >/dev/null 2>&1 || die "jq not found — install it with your package manager before using this tool"

# ── Read the repository ──────────────────────────────────────────────────────
repo_json="$(gh api "repos/$REPO" 2>/dev/null)" ||
  die "cannot read $REPO (missing, or the token cannot see it)"

if [[ "$(jq -r '.permissions.admin // false' <<<"$repo_json")" != "true" ]]; then
  die "admin permission on $REPO is required to change these settings"
fi

current_default="$(jq -r '.default_branch // ""' <<<"$repo_json")"
[[ -n "$current_default" ]] ||
  die "$REPO is empty — push a first commit so a default branch exists"

[[ -n "$DEFAULT_BRANCH" ]] || DEFAULT_BRANCH="$current_default"
# A default branch may contain '/', so it must be encoded for the URL path.
BRANCH_PATH="$(jq -rn --arg b "$DEFAULT_BRANCH" '$b|@uri')"

branch_exists="$(gh api "repos/$REPO/branches/$BRANCH_PATH" >/dev/null 2>&1 && echo true || echo false)"
[[ "$branch_exists" == "true" ]] || die "$REPO has no branch '$DEFAULT_BRANCH' to protect"

# ── Legacy classic protection ────────────────────────────────────────────────
# A classic rule layers with the ruleset and the most restrictive rule wins, so
# a leftover one silently defeats the override. It is KEPT unless the caller
# asks for --remove-classic-protection; its required status checks are carried
# into the ruleset either way.
classic_json="$(gh api "repos/$REPO/branches/$BRANCH_PATH/protection" 2>/dev/null || true)"
classic_protection=false
# A 404 makes `gh api` print the error body to stdout as well as stderr, so a
# non-empty capture alone does not mean protection exists. A real protection
# object always carries enforce_admins.
if [[ -n "$classic_json" ]] && jq -e 'has("enforce_admins")' <<<"$classic_json" >/dev/null 2>&1; then
  classic_protection=true
else
  classic_json=""
fi

# ── Rules currently in force on the branch ──────────────────────────────────
# The effective-rules endpoint already resolves layering, wildcards and
# inheritance, which is more reliable than re-deriving each ruleset's ref
# conditions. Any rule whose ruleset_id is not ours comes from another ruleset.
pre_rules="$(gh api "repos/$REPO/rules/branches/$BRANCH_PATH" 2>/dev/null || echo '[]')"

# ── Repository rulesets only (includes_parents=false) ───────────────────────
# --paginate --slurp collects every page; per_page alone truncates at 100 and
# would make a later ruleset look absent (and be duplicated on create).
rulesets_json="$(gh api --paginate --slurp "repos/$REPO/rulesets?per_page=100&includes_parents=false" 2>/dev/null |
  jq -c 'add // [] | [.[] | select((.source_type // "Repository") == "Repository")]')" ||
  die "cannot list rulesets for $REPO"

# Only a branch ruleset of this name is ours to reset. A same-name tag ruleset
# would be silently retargeted by a PUT, destroying its tag protection.
if [[ "$(jq -r --arg n "$RULESET_NAME" '[.[] | select(.name == $n and .target != "branch")] | length' <<<"$rulesets_json")" != "0" ]]; then
  die "'$RULESET_NAME' already names a non-branch ruleset in $REPO — pass --ruleset-name to use another name"
fi
existing_id="$(jq -r --arg n "$RULESET_NAME" '[.[] | select(.name == $n and .target == "branch")][0].id // ""' <<<"$rulesets_json")"
current_ruleset='{}'
if [[ -n "$existing_id" ]]; then
  current_ruleset="$(gh api "repos/$REPO/rulesets/$existing_id" 2>/dev/null)" ||
    die "cannot read ruleset $existing_id"
fi

others_json="$(jq -c --argjson own "${existing_id:-0}" '
  [ .[] | select((.ruleset_id // 0) != $own) ]
  | group_by(.ruleset_id)
  | map({id: .[0].ruleset_id,
         source: .[0].ruleset_source,
         source_type: (.[0].ruleset_source_type // "Repository"),
         rules: (map(.type) | unique | join(", "))})
' <<<"$pre_rules")"

# ── Collect the status checks that are already enforced ─────────────────────
# "Require status checks" is only meaningful when checks already exist; carry
# over whatever classic protection or the current ruleset already requires.
checks_json='[]'
strict_checks=true
if [[ "$classic_protection" == "true" ]]; then
  # `checks` carries the pinned integration; `contexts` is the legacy unpinned
  # list. Both become {context} or {context, integration_id} entries, so a check
  # restricted to one app stays restricted after the migration.
  checks_json="$(jq -c '[
    ((.required_status_checks.checks // [])[]?
      | if .app_id then {context: .context, integration_id: .app_id} else {context: .context} end),
    ((.required_status_checks.contexts // [])[]? | {context: .})
  ]' <<<"$classic_json")"
  # `// true` would coerce a legitimate `false` back to true, since jq's //
  # treats false as absent.
  strict_checks="$(jq -r 'if (.required_status_checks.strict | type) == "boolean"
                          then .required_status_checks.strict else true end' <<<"$classic_json")"
fi
if [[ -n "$existing_id" ]]; then
  # Classic protection wins when present; otherwise keep what the ruleset
  # already enforced, so a rerun cannot silently tighten it.
  if [[ "$classic_protection" != "true" ]]; then
    ex_strict="$(jq -r '[.rules[]? | select(.type == "required_status_checks")
                         | .parameters.strict_required_status_checks_policy]
                        | if length > 0 then .[0] else empty end' <<<"$current_ruleset")"
    [[ -n "$ex_strict" ]] && strict_checks="$ex_strict"
  fi
  checks_json="$(jq -c -n --argjson a "$checks_json" --argjson b "$current_ruleset" '
    $a + [ $b.rules[]? | select(.type == "required_status_checks")
           | .parameters.required_status_checks[]?
           | if .integration_id then {context, integration_id} else {context} end ]')"
fi
if [[ ${#EXTRA_CHECKS[@]} -gt 0 ]]; then
  checks_json="$(jq -c -n --argjson a "$checks_json" --argjson b "$(printf '%s\n' "${EXTRA_CHECKS[@]}" | jq -R '{context: .}' | jq -s .)" '
    $a + $b')"
fi

# A repository ruleset that --reset-other-rulesets will delete may be the only
# source of an enforced check; carry its checks into the new ruleset so deleting
# it cannot remove a gate that was already in force.
if [[ "$RESET_OTHER" == "true" ]]; then
  checks_json="$(jq -c -n --argjson a "$checks_json" --argjson pre "$pre_rules" --argjson own "${existing_id:-0}" '
    $a + [ $pre[]?
           | select((.ruleset_id // 0) != $own)
           | select((.ruleset_source_type // "Repository") == "Repository")
           | select(.type == "required_status_checks")
           | .parameters.required_status_checks[]?
           | if .integration_id then {context, integration_id} else {context} end ]')"
fi

# One entry per context; an app-pinned entry wins over an unpinned duplicate.
checks_json="$(jq -c '
  group_by(.context)
  | map(if any(has("integration_id")) then (map(select(has("integration_id")))[0]) else .[0] end)
' <<<"$checks_json")"

# ── Build the ruleset body ──────────────────────────────────────────────────
rules_json="$(jq -n --argjson checks "$checks_json" --arg strict "$strict_checks" '[
  {type: "deletion"},
  {type: "non_fast_forward"},
  {type: "pull_request", parameters: {
    required_approving_review_count: 1,
    dismiss_stale_reviews_on_push: false,
    require_code_owner_review: false,
    require_last_push_approval: false,
    required_review_thread_resolution: true,
    allowed_merge_methods: ["merge", "squash", "rebase"]
  }}
] | if ($checks | length) > 0 then
      . + [{type: "required_status_checks", parameters: {
        strict_required_status_checks_policy: ($strict == "true"),
        required_status_checks: [$checks[]
          | if has("integration_id") then {context, integration_id} else {context} end]
      }}]
    else . end')"

bypass_json='[]'
if [[ "$BYPASS" != "none" ]]; then
  bypass_mode="pull_request"
  [[ "$BYPASS" == "always" ]] && bypass_mode="always"
  bypass_json="$(jq -n --argjson id "$BYPASS_ROLE_ID" --arg mode "$bypass_mode" \
    '[{actor_type: "RepositoryRole", actor_id: $id, bypass_mode: $mode}]')"
fi

# The ruleset targets the default branch. An explicitly requested branch is
# spelled out, because ~DEFAULT_BRANCH always resolves to the repository's own
# default and would silently protect a different branch than the caller named.
if [[ "$BRANCH_EXPLICIT" == "true" ]]; then
  ref_include="refs/heads/$DEFAULT_BRANCH"
else
  ref_include="~DEFAULT_BRANCH"
fi

body="$(jq -n \
  --arg name "$RULESET_NAME" \
  --arg ref "$ref_include" \
  --argjson rules "$rules_json" \
  --argjson bypass "$bypass_json" \
  '{name: $name, target: "branch", enforcement: "active",
    conditions: {ref_name: {include: [$ref], exclude: []}},
    rules: $rules, bypass_actors: $bypass}')"
ruleset_action="create"
[[ -n "$existing_id" ]] && ruleset_action="update (id $existing_id)"

# ── Repository settings ─────────────────────────────────────────────────────
settings_json="$(jq -n '{
  has_pull_requests: true,
  pull_request_creation_policy: "all",
  allow_merge_commit: true,
  merge_commit_title: "PR_TITLE",
  merge_commit_message: "PR_BODY",
  allow_squash_merge: true,
  squash_merge_commit_title: "PR_TITLE",
  squash_merge_commit_message: "BLANK",
  allow_rebase_merge: true,
  allow_update_branch: true,
  allow_auto_merge: true,
  delete_branch_on_merge: true
}')"

# ── Plan ─────────────────────────────────────────────────────────────────────
plan_classic="none"
if [[ "$classic_protection" == "true" ]]; then
  if [[ "$REMOVE_CLASSIC" == "true" ]]; then
    plan_classic="present — will be removed"
  else
    plan_classic="present — kept (the override will not apply; use --remove-classic-protection)"
  fi
fi

others_lines="$(jq -r '.[] | "\(.id)\t\(.source_type)\t\(.source)\t\(.rules)"' <<<"$others_json")"

print_plan() {
  local phase="${1:-plan}"
  echo "repo:            $REPO"
  echo "default branch:  $DEFAULT_BRANCH"
  echo "ruleset:         $RULESET_NAME ($ruleset_action)"
  echo "override:        $BYPASS${BYPASS_ROLE_ID:+ (role id $BYPASS_ROLE_ID)}"
  echo "legacy classic protection: $plan_classic"
  while IFS=$'\t' read -r oid otype osource orules; do
    [[ -z "$oid" ]] && continue
    if [[ "$otype" != "Repository" ]]; then
      echo "$(printf '%s' "$otype" | tr '[:upper:]' '[:lower:]') ruleset: $osource — applies here ($orules); cannot be changed from this repository"
    elif [[ "$RESET_OTHER" == "true" ]]; then
      echo "other ruleset:   $osource ($oid) — deleting ($orules)"
    else
      echo "other ruleset:   $osource ($oid) — also applies ($orules); left alone (use --reset-other-rulesets)"
    fi
  done <<<"$others_lines"
  if [[ "$phase" == "after" ]]; then
    [[ "$REMOVE_CLASSIC" == "true" && "$classic_protection" == "true" ]] &&
      echo "removed legacy classic protection on $DEFAULT_BRANCH"
    [[ "$RESET_OTHER" == "true" ]] && while IFS=$'\t' read -r oid otype osource orules; do
      [[ -z "$oid" || "$otype" != "Repository" ]] && continue
      echo "removed ruleset $osource ($oid)"
    done <<<"$others_lines"
  fi
  echo
  echo "repository settings:"
  echo "$settings_json" | jq .
  echo
  echo "ruleset body:"
  echo "$body" | jq .
}

if [[ "$APPLY" != "true" ]]; then
  if [[ "$JSON_OUT" == "true" ]]; then
    jq -n \
      --arg repo "$REPO" --arg branch "$DEFAULT_BRANCH" \
      --arg ruleset "$RULESET_NAME" --arg action "$ruleset_action" \
      --arg override "$BYPASS" --arg role_id "$BYPASS_ROLE_ID" \
      --arg classic "$classic_protection" --arg remove_classic "$REMOVE_CLASSIC" \
      --arg reset_other "$RESET_OTHER" \
      --argjson settings "$settings_json" --argjson ruleset_body "$body" \
      --argjson others "$others_json" \
      '{mode: "dry-run", repo: $repo, default_branch: $branch,
        ruleset: {name: $ruleset, action: $action, body: $ruleset_body},
        override: {mode: $override, role_id: $role_id},
        repository_settings: $settings,
        classic_protection: {present: ($classic == "true"), remove: ($remove_classic == "true")},
        other_rulesets: $others, reset_other_rulesets: ($reset_other == "true")}'
  else
    echo "DRY RUN — nothing written. Re-run with --apply to apply."
    echo
    print_plan
    echo
    echo "manual step: 'Allow comments on individual commits' has no API — set it under"
    echo "             Settings → Commits if it should be disabled."
  fi
  exit 0
fi

# ── Apply ────────────────────────────────────────────────────────────────────
# Order matters: the replacement protection is written and verified BEFORE
# anything is deleted, so a failure anywhere leaves the repository at least as
# protected as it was.
gh api --method PATCH "repos/$REPO" --input - <<<"$settings_json" >/dev/null ||
  die "failed to apply the repository settings"

ruleset_created=false
if [[ -n "$existing_id" ]]; then
  gh api --method PUT "repos/$REPO/rulesets/$existing_id" --input - <<<"$body" >/dev/null ||
    die "failed to update ruleset $existing_id"
else
  existing_id="$(gh api --method POST "repos/$REPO/rulesets" --input - <<<"$body" |
    jq -r '.id // ""')" || die "failed to create ruleset"
  [[ -n "$existing_id" ]] || die "ruleset created but no id returned"
  ruleset_created=true
fi

# A verification failure must not leave the write in place: a new ruleset is
# deleted, and an updated one is restored from the definition read earlier.
# Otherwise an unverified override would stay active while the tool reports
# failure, which is the opposite of failing closed.
_fail_after_write() {
  local msg="$1" restore
  if [[ "$ruleset_created" == "true" ]]; then
    if gh api --method DELETE "repos/$REPO/rulesets/$existing_id" >/dev/null 2>&1; then
      die "$msg — removed the newly created ruleset; previous protections untouched"
    fi
    # Claiming recovery here would be a false guarantee: the ruleset is live.
    die "$msg — ROLLBACK FAILED: ruleset $existing_id is still active with the unverified configuration; delete it manually"
  fi
  restore="$(jq -c '{name, target, enforcement, conditions, rules, bypass_actors}' \
    <<<"$current_ruleset" 2>/dev/null || true)"
  if [[ -z "$restore" || "$restore" == "null" ]]; then
    die "$msg — ROLLBACK NOT POSSIBLE: the previous definition of ruleset $existing_id is unavailable; review it manually"
  fi
  if gh api --method PUT "repos/$REPO/rulesets/$existing_id" --input - <<<"$restore" >/dev/null 2>&1; then
    die "$msg — restored the previous ruleset definition; previous protections untouched"
  fi
  die "$msg — ROLLBACK FAILED: ruleset $existing_id still carries the unverified configuration; restore it manually"
}

# The rules are the product of this tool, so assert they are actually in force —
# and that they are ours, with the parameters we asked for.
effective_json="$(gh api "repos/$REPO/rules/branches/$BRANCH_PATH" 2>/dev/null)" ||
  _fail_after_write "ruleset written but the effective rules could not be read"
effective="$(jq -r '[.[].type] | unique | join(", ")' <<<"$effective_json")"

assert_effective() {
  local json="$1" label="$2" mode="${3:-rollback}"
  local effective_types want msg bad=""

  fail() {
    if [[ "$mode" == "plain" ]]; then die "$1"; fi
    _fail_after_write "$1"
  }

  effective_types="$(jq -r '[.[].type] | unique | join(", ")' <<<"$json")"
  for want in deletion non_fast_forward pull_request; do
    if ! jq -e --arg w "$want" --argjson id "$existing_id" \
         'map(select(.type == $w)) | map(.ruleset_id) | index($id)' <<<"$json" >/dev/null; then
      fail "$label: '$want' is not in force from ruleset $existing_id (got: $effective_types)"
    fi
  done
  if [[ "$(jq 'length' <<<"$checks_json")" -gt 0 ]]; then
    if ! jq -e --argjson id "$existing_id" \
         'map(select(.type == "required_status_checks")) | map(.ruleset_id) | index($id)' \
         <<<"$json" >/dev/null; then
      fail "$label: required_status_checks is not in force from ruleset $existing_id (got: $effective_types)"
    fi
  fi

  # Types are not enough: the stored parameters are what actually gate merges.
  jq -e --argjson id "$existing_id" '
    map(select(.type == "pull_request" and .ruleset_id == $id))[0].parameters
    | .required_approving_review_count == 1
      and .required_review_thread_resolution == true
      and .dismiss_stale_reviews_on_push == false
      and .require_last_push_approval == false
  ' <<<"$json" >/dev/null || bad="pull_request parameters differ from the requested ones"
  if [[ "$(jq 'length' <<<"$checks_json")" -gt 0 ]]; then
    jq -e --argjson id "$existing_id" --argjson want "$checks_json" '
      (map(select(.type == "required_status_checks" and .ruleset_id == $id))[0]
        .parameters.required_status_checks
       | map("\(.context):\(.integration_id // "")") | sort)
      == ($want | map("\(.context):\(.integration_id // "")") | sort)
    ' <<<"$json" >/dev/null || bad="${bad:+$bad; }required status checks differ"
  fi
  [[ -z "$bad" ]] || fail "$label: $bad"
}

assert_effective "$effective_json" "ruleset written"

# Verify the override mapping before deleting anything: the numeric role ids are
# not documented, so read back what GitHub actually stored.
bypass_verified="unverified"
if [[ "$BYPASS" != "none" ]]; then
  owner="${REPO%%/*}"
  name="${REPO##*/}"
  applied_role="$(gh api graphql -f query="{
    repository(owner: \"$owner\", name: \"$name\") {
      ruleset(databaseId: $existing_id) {
        bypassActors(first: 20) {
          nodes { repositoryRoleDatabaseId repositoryRoleName }
        }
      }
    }
  }" --jq '.data.repository.ruleset.bypassActors.nodes[0] | "\(.repositoryRoleDatabaseId):\(.repositoryRoleName)"' 2>/dev/null || true)"
  if [[ -z "$applied_role" || "$applied_role" == "null:null" ]]; then
    # Proceeding here would delete protections while the actual override is
    # unknown, so fail closed and undo the write.
    _fail_after_write "the override role could not be read back"
  fi
  applied_role_id="${applied_role%%:*}"
  applied_role_name="${applied_role##*:}"
  [[ "$applied_role_id" == "$BYPASS_ROLE_ID" ]] ||
    _fail_after_write "the override actor is role id $applied_role_id, not the requested $BYPASS_ROLE_ID"
  if [[ -n "$BYPASS_ROLE_NAME" && "$applied_role_name" != "$BYPASS_ROLE_NAME" ]]; then
    _fail_after_write "role id $BYPASS_ROLE_ID resolved to '$applied_role_name', not '$BYPASS_ROLE_NAME'"
  fi
  bypass_verified="confirmed role $applied_role_name (id $applied_role_id)"
fi

# Only now remove what the ruleset supersedes.
removed_classic=false
if [[ "$classic_protection" == "true" && "$REMOVE_CLASSIC" == "true" ]]; then
  gh api --method DELETE "repos/$REPO/branches/$BRANCH_PATH/protection" >/dev/null ||
    die "ruleset is in place, but removing legacy branch protection failed"
  removed_classic=true
fi

removed_other=()
if [[ "$RESET_OTHER" == "true" ]]; then
  while IFS=$'\t' read -r oid otype osource orules; do
    [[ -z "$oid" ]] && continue
    # Organization and enterprise rulesets are not addressable from the
    # repository endpoint; only repository-owned ones can be deleted.
    [[ "$otype" != "Repository" ]] && continue
    gh api --method DELETE "repos/$REPO/rulesets/$oid" >/dev/null ||
      die "ruleset is in place, but deleting ruleset $osource ($oid) failed"
    removed_other+=("$osource")
  done <<<"$others_lines"
fi

# Deleting other protections can remove rules that were also enforcing the
# branch, so confirm the intended rules survived the deletions too.
final_json="$(gh api "repos/$REPO/rules/branches/$BRANCH_PATH" 2>/dev/null)" ||
  die "could not re-read the effective rules after removing protections"
assert_effective "$final_json" "after removing other protections" plain
effective="$(jq -r '[.[].type] | unique | join(", ")' <<<"$final_json")"

if [[ "$JSON_OUT" == "true" ]]; then
  jq -n \
    --arg repo "$REPO" --arg branch "$DEFAULT_BRANCH" \
    --arg ruleset "$RULESET_NAME" --arg id "$existing_id" \
    --arg effective "$effective" --arg override "$BYPASS" \
    --arg override_check "$bypass_verified" \
    --argjson removed_other "$(printf '%s\n' "${removed_other[@]}" | jq -R . | jq -s 'map(select(length>0))')" \
    --argjson classic "$classic_protection" \
    --argjson removed_classic "$removed_classic" \
    '{mode: "applied", repo: $repo, default_branch: $branch,
      ruleset: {name: $ruleset, id: $id}, effective_rules: $effective,
      override: {mode: $override, check: $override_check},
      classic_protection_present: $classic,
      classic_protection_removed: $removed_classic,
      other_rulesets_removed: $removed_other}'
else
  echo "APPLIED — summary:"
  echo
  print_plan after | sed '/^repository settings:$/,$d'
  echo "effective rules: $effective"
  [[ "$bypass_verified" != "unverified" ]] && echo "override: $bypass_verified"
  if [[ "$classic_protection" == "true" && "$REMOVE_CLASSIC" != "true" ]]; then
    echo "
WARNING: legacy classic branch protection remains on $DEFAULT_BRANCH. It layers
with the ruleset and the most restrictive rule wins, so the override will not
take effect until it is removed (--remove-classic-protection)."
  fi
  echo
  echo "manual step: 'Allow comments on individual commits' has no API — set it under"
  echo "             Settings → Commits if it should be disabled."
fi

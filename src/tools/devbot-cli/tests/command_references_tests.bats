#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/command_references_tests.bats
# Every command a doc names must be spelled so it resolves on the host.
#
# A command's id is host-derived, and the farm names it so both hosts agree:
# the flat file `commands/devbot:commit.md` is `/devbot:commit` on opencode v2
# (path segments joined with `/`, prefix inside the filename) and on claudecode
# (`<dir>:<file>`). The old `commands/devbot/commit.md` farm read `/devbot/commit`
# on v2 and is retired, so that spelling now names nothing. A BARE one (`/rfp`,
# `/create-jira-issue`) resolves on neither. The same drift reaches code:
# AutoBot builds its start prompt from a constant, so a rename leaves it
# invoking a command that no longer exists (test 3).
#
# Run from project root:
#   bats src/tools/devbot-cli/tests/command_references_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
  COMMAND_FILES=("${ROOT}"/src/*/*/commands/*.md)
  # Host built-ins a doc may name without it being ours to check.
  BUILTINS="init review mcp modules help"
  DOC_SOURCES=("${ROOT}/src" "${ROOT}/docs" "${ROOT}/README.md")
}

# The bare name of every shipped command: `devbot:commit` → `commit`.
shipped_commands() {
  local f name
  for f in "${COMMAND_FILES[@]}"; do
    [[ -f "${f}" ]] || continue
    name="$(sed -n 's/^name:[[:space:]]*//p' "${f}" | head -1 | tr -d '"')"
    name="${name#devbot:}"
    [[ -n "${name}" ]] && printf '%s\n' "${name}"
  done | sort -u
}

is_shipped() {
  grep -Fxq -- "$1" <<< "$(shipped_commands)"
}

# A leading boundary of whitespace/quote/bracket keeps filesystem paths out:
# `~/.kube/devbot/exec-credential` and `${XDG_CONFIG_HOME:-~/.config}/devbot/x`
# are paths, not commands.
@test "a /devbot reference names a shipped command" {
  local unknown=""
  while IFS=: read -r file line match; do
    local name="${match##*/devbot[:/]}"
    is_shipped "${name}" && continue
    unknown+="  ${name}\t${file#"${ROOT}"/}:${line}"$'\n'
  done < <(grep -rnoE '(^|[[:space:]`"'"'"'([])/devbot[:/][A-Za-z0-9][A-Za-z0-9-]*' \
    "${DOC_SOURCES[@]}" --include='*.md' --include='*.tpl' 2>/dev/null)

  [ -z "${unknown}" ] || {
    echo "references to commands we do not ship:"
    printf '%b' "${unknown}"
    return 1
  }
}

@test "no /devbot/<name> reference — that spelling resolves on no host" {
  # The pre-colon farm rendered `/devbot/commit` on opencode v2 only; the flat
  # colon farm is the single name both hosts resolve, so the path form is stale
  # in a doc even though the command it meant still ships.
  local stale=""
  while IFS=: read -r file line match; do
    stale+="  ${match}\t${file#"${ROOT}"/}:${line}"$'\n'
  done < <(grep -rnoE '(^|[[:space:]`"'"'"'([])/devbot/[A-Za-z0-9][A-Za-z0-9-]*' \
    "${DOC_SOURCES[@]}" --include='*.md' --include='*.tpl' 2>/dev/null)

  [ -z "${stale}" ] || {
    echo "stale /devbot/<name> references (use /devbot:<name>):"
    printf '%b' "${stale}"
    return 1
  }
}

@test "a bare /<name> is not a shipped command spelled without devbot" {
  local name bare=""
  for name in $(shipped_commands); do
    grep -Fxq -- "${name}" <<< "${BUILTINS// /$'\n'}" && continue
    while IFS=: read -r file line _match; do
      bare+="  /${name}\t${file#"${ROOT}"/}:${line}"$'\n'
    done < <(grep -rnoE "(^|[[:space:]\`\"'([(])/${name}([^A-Za-z0-9-]|\$)" \
      "${DOC_SOURCES[@]}" --include='*.md' --include='*.tpl' 2>/dev/null)
  done

  [ -z "${bare}" ] || {
    echo "bare command references (no host resolves these):"
    printf '%b' "${bare}"
    return 1
  }
}

@test "full-audit-and-fix-loop: gates on unattended auth before any work" {
  local cmd="${ROOT}/src/tools/devbot-cli/commands/full-audit-and-fix-loop.md"
  # The gate exists and names the failure it prevents (an interactive login
  # cannot be renewed headlessly, so an autonomous loop dies hours in).
  grep -qF 'claude auth status' "${cmd}"
  grep -qF 'oauth_token' "${cmd}"
  grep -qF 'claude setup-token' "${cmd}"
  # It stops, rather than working around the credential.
  grep -qiE 'stop before anything else|never substitute' "${cmd}"
}

@test "full-audit-and-fix-loop: worktree from local main, then the full loop" {
  local cmd="${ROOT}/src/tools/devbot-cli/commands/full-audit-and-fix-loop.md"
  grep -qF 'worktree.sh" create' "${cmd}"
  grep -qF -- '--base main' "${cmd}"
  local needle
  for needle in '/devbot:audit' '/devbot:audit-fix' 'devbot:review-implementation' 'devbot:gh-create-pr' 'devbot:gh-review-loop'; do
    grep -qF -- "$needle" "${cmd}"
  done
}

@test "full-audit-and-fix-loop: audits on sonnet by default" {
  local cmd="${ROOT}/src/tools/devbot-cli/commands/full-audit-and-fix-loop.md"
  # The audit dominates the loop's wall clock, so its model is chosen, not
  # inherited — and the override is named.
  grep -qiF 'sonnet' "${cmd}"
  grep -qF 'DEVBOT_TEST_CLAUDE_MODEL' "${cmd}"
}

@test "full-audit-and-fix-loop: both harnesses audit in parallel before a fix" {
  local cmd="${ROOT}/src/tools/devbot-cli/commands/full-audit-and-fix-loop.md"
  # A harness-specific defect shows in one report and not the other, so the fix
  # step waits for the pair.
  grep -qF 'make audit' "${cmd}"
  grep -qiF 'both reports' "${cmd}"
}

@test "full-audit-and-fix-loop: the 70% budget stops rounds, not the delivery" {
  local cmd="${ROOT}/src/tools/devbot-cli/commands/full-audit-and-fix-loop.md"
  # Running out of context mid-fix is what the budget prevents; reaching it still
  # opens the PR, works the review loop and hands off.
  grep -qF '70%' "${cmd}"
  grep -qiF 'hand off' "${cmd}"
  grep -qiF 'what the last reports still named' "${cmd}"
}

@test "full-audit-and-fix-loop: frontmatter name matches the filename" {
  local cmd="${ROOT}/src/tools/devbot-cli/commands/full-audit-and-fix-loop.md"
  grep -qx 'name: devbot:full-audit-and-fix-loop' "${cmd}"
  grep -qE '^description: .+' "${cmd}"
}

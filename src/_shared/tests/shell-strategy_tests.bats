#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/shell-strategy_tests.bats
# The bash-vs-PTY channel rule is a single shared skill, not a paragraph copied
# into each agent. This suite guards the wiring: every agent that can run a
# shell command must load `devbot:shell-strategy`, and the rule's detail must
# not leak back into agent files.
#
# "Shell-capable" is derived from each agent's frontmatter permission, not
# hardcoded: an agent whose `bash` permission is `deny` cannot run commands and
# needs neither the skill nor the PTY tools; every other agent can, and does. A
# new agent is therefore covered the moment it is added.
#
# The frontmatter is read structurally rather than regexed, so the scalar form
# (`bash: deny`), the quoted form (`bash: "deny"`), and the structured form
# (`bash:` then `"*": deny`) all classify the same way. The reader is
# dependency-free on purpose — PyYAML is not a declared dependency of the repo,
# and a skipped guard is not a guard.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="${PROJECT_ROOT}/src/agentic/dev/skills/shell-strategy/SKILL.md"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

# Emit "<path>\t<bash action>" for every first-party agent file, where the
# action is the normalised `permission.bash` value: deny | ask | allow | "".
_agents() {
  python3 - "${PROJECT_ROOT}" <<'PYEOF'
import glob, os, re, sys

_DENY_SCALAR = re.compile(r"^(\s*)bash:\s*(.*?)\s*$")


def _scalar(value):
    """Normalise a YAML scalar: strip quotes, trailing comment, and case."""
    return value.split("#", 1)[0].strip().strip("\"'").strip().lower()


def bash_action(frontmatter):
    """Return the normalised `permission.bash` action.

    Handles the three frontmatter shapes the agents use: `bash: deny`,
    `bash: "deny"`, and a structured block (`bash:` followed by an indented
    `"*": deny`). Anything else — an absent key, a partial structured rule with
    no catch-all — reads as "" (not denied).
    """
    lines = frontmatter.splitlines()
    for index, line in enumerate(lines):
        match = _DENY_SCALAR.match(line)
        if not match:
            continue
        indent, value = len(match.group(1)), match.group(2)
        if value:
            return _scalar(value)
        for following in lines[index + 1:]:
            if not following.strip():
                continue
            if len(following) - len(following.lstrip()) <= indent:
                break
            entry = re.match(r"^\s*[\"']?\*[\"']?\s*:\s*(.*?)\s*$", following)
            if entry:
                return _scalar(entry.group(1))
        return ""
    return ""


root = sys.argv[1]
for f in sorted(glob.glob(os.path.join(root, "src/agentic/*/agents/*.md"))):
    text = open(f, encoding="utf-8", errors="replace").read()
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    print(f"{os.path.relpath(f, root)}\t{bash_action(m.group(1) if m else '')}")
PYEOF
}

@test "every shell-capable agent loads the shell-strategy skill" {
  local violations="" rel action
  while IFS=$'\t' read -r rel action; do
    [[ "$action" != "deny" ]] || continue
    grep -q "devbot:shell-strategy" "${PROJECT_ROOT}/${rel}" || violations+="${rel}\n"
  done < <(_agents)
  if [[ -n "${violations}" ]]; then
    printf 'Shell-capable agents not referencing devbot:shell-strategy:\n%b' "${violations}" >&2
    fail "a shell-capable agent must load the shell-strategy skill"
  fi
}

@test "the scan finds shell-capable agents (guards against an empty glob)" {
  local capable
  capable="$(_agents | grep -vc $'\tdeny$')"
  (( capable >= 5 )) || fail "expected at least 5 shell-capable agents, scanned ${capable}"
}

# The sentences that carry the PTY rules. Checking one exact string lets a
# reworded copy slip back into an agent file; any of these appearing outside the
# skill means the detail has been restated.
_DUPLICATED_PHRASES=(
  "Never redirect a PTY command"
  "background it with"
  "Wire stdin from"
  "Commit through bash"
)

@test "the PTY rules are not duplicated back into agent files" {
  local hits="" rel phrase
  while IFS=$'\t' read -r rel _; do
    for phrase in "${_DUPLICATED_PHRASES[@]}"; do
      if grep -qF "$phrase" "${PROJECT_ROOT}/${rel}"; then
        hits+="${rel}: ${phrase}\n"
      fi
    done
  done < <(_agents)
  if [[ -n "${hits}" ]]; then
    printf 'Agent files restating the PTY rules:\n%b' "${hits}" >&2
    fail "the PTY rules live in the shell-strategy skill, not in each agent"
  fi
}

@test "the shell-strategy skill carries the channel decision" {
  [[ -f "$SKILL" ]] || fail "missing skill at ${SKILL}"
  grep -q "pty_spawn" "$SKILL" || fail "skill must name the PTY tools"
  grep -q "bash" "$SKILL" || fail "skill must name the bash channel"
  grep -q "/dev/null" "$SKILL" || fail "skill must carry the stdin rule"
}

@test "the scan finds at least one agent that cannot shell" {
  # architect/critic/po deny bash. If the reader stopped recognising the deny,
  # every agent would silently classify as shell-capable and this suite would
  # still pass while checking nothing.
  local denied
  denied="$(_agents | grep -c $'\tdeny$')"
  (( denied >= 1 )) || fail "expected at least one bash-denied agent, scanned ${denied}"
}

# `permission.bash: deny` blocks only the bash tool. opencode-pty gates its own
# tools against the GLOBAL permission.bash only — never the per-agent
# permission — so an agent-level bash deny leaves it a full shell. A per-agent
# `action: deny` removes the tool from the registry instead.
@test "an agent denied bash is also denied the PTY tool family" {
  run python3 - "${PROJECT_ROOT}" <<'PYEOF'
import glob, os, re, sys

REQUIRED = ("pty_spawn", "pty_write", "pty_read", "pty_kill", "pty_list")
_DENY_SCALAR = re.compile(r"^(\s*)bash:\s*(.*?)\s*$")


def _scalar(value):
    return value.split("#", 1)[0].strip().strip("\"'").strip().lower()


def denies_bash(frontmatter):
    lines = frontmatter.splitlines()
    for index, line in enumerate(lines):
        match = _DENY_SCALAR.match(line)
        if not match:
            continue
        indent, value = len(match.group(1)), match.group(2)
        if value:
            return _scalar(value) == "deny"
        for following in lines[index + 1:]:
            if not following.strip():
                continue
            if len(following) - len(following.lstrip()) <= indent:
                break
            entry = re.match(r"^\s*[\"']?\*[\"']?\s*:\s*(.*?)\s*$", following)
            if entry:
                return _scalar(entry.group(1)) == "deny"
        return False
    return False


old_root = sys.argv[1]
problems = []
for f in sorted(glob.glob(os.path.join(old_root, "src/agentic/*/agents/*.md"))):
    text = open(f, encoding="utf-8", errors="replace").read()
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    frontmatter = m.group(1) if m else ""
    if not denies_bash(frontmatter):
        continue
    for tool in REQUIRED:
        entry = re.search(rf"^\s*{tool}:\s*(.*?)\s*$", frontmatter, re.M)
        value = _scalar(entry.group(1)) if entry else ""
        if value != "deny":
            problems.append(f"{os.path.relpath(f, old_root)}: {tool}")
if problems:
    print("MISSING PTY DENY:\n" + "\n".join(problems))
    sys.exit(1)
print("PTY-DENY:OK")
PYEOF
  assert_success
  grep -qF 'PTY-DENY:OK' <<< "$output" || fail "bash-denied agents must also deny the PTY tools"
}

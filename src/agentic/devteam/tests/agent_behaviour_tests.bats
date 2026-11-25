#!/usr/bin/env bats
# =============================================================================
# src/agentic/devteam/tests/agent_behaviour_tests.bats
# The collaboration stance is duplicated *by design* into every agent file: it
# has to be unmissable, so it cannot live only in a skill. Duplication that no
# test guards is drift — one file gets reworded, a 13th agent ships without the
# block, and the suite stays green.
#
# This suite asserts the property the duplication buys: the block is present
# exactly once, byte-identical, and under a Behaviour heading in every
# first-party agent. A new agent is covered the moment it is added.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

# Emit "<path>\t<hits>\t<sha>\t<lines>\t<heading>" for every path matching the
# given globs (default: every first-party agent): how many times the block's
# opening line appears, the sha of the block as written, its line count, and
# whether a Behaviour heading immediately precedes it.
_blocks() {
  python3 - "${PROJECT_ROOT}" "$@" <<'PYEOF'
import glob, hashlib, os, re, sys

OPENING = "Act as an independent technical collaborator, not a source of validation."
LAST = "- Be direct and respectful, not adversarial. Critique the work, not me."
HEADING = re.compile(r"^(##\s+Behaviour|\*\*Behaviour\*\*)\s*$")

root = sys.argv[1]
targets = sys.argv[2:] or ["src/agentic/*/agents/*.md"]

paths = []
for target in targets:
    if any(c in target for c in "*?["):
        paths.extend(glob.glob(os.path.join(root, target)))
    else:
        paths.append(os.path.join(root, target))

for f in sorted(set(paths)):
    lines = open(f, encoding="utf-8", errors="replace").read().splitlines()
    hits = [i for i, line in enumerate(lines) if line.strip() == OPENING]
    block = ""
    if hits:
        start = hits[0]
        for j in range(start + 1, len(lines)):
            if lines[j].strip() == LAST:
                block = "\n".join(lines[start:j + 1])
                break
    sha = hashlib.sha256(block.encode()).hexdigest()[:12] if block else "-"
    size = len(block.splitlines()) if block else 0
    above = [l for l in lines[:hits[0]] if l.strip()] if hits else []
    heading = "yes" if above and HEADING.match(above[-1]) else "no"
    print(f"{os.path.relpath(f, root)}\t{len(hits)}\t{sha}\t{size}\t{heading}")
PYEOF
}

# The canonical copy lives in the create-agent rule library — one home for the
# wording, asserted against rather than copied a thirteenth time.
_CANONICAL="src/agentic/self-improvement/skills/create-agent/SKILL.md"

@test "every agent carries the collaboration stance exactly once" {
  local missing="" rel hits _rest
  while IFS=$'\t' read -r rel hits _rest; do
    [[ "$hits" == "1" ]] || missing+="${rel} (${hits} hits)\n"
  done < <(_blocks)
  if [[ -n "${missing}" ]]; then
    printf 'Agents without exactly one stance block:\n%b' "${missing}" >&2
    fail "every agent must carry the collaboration stance exactly once"
  fi
}

@test "the stance block is byte-identical in every agent" {
  local shas distinct
  shas="$(_blocks | cut -f3 | sort -u)"
  distinct="$(printf '%s\n' "${shas}" | grep -c . || true)"
  [[ "${shas}" != "-" ]] || fail "an agent carries no extractable stance block"
  [[ "${distinct}" == "1" ]] || fail "expected one distinct block, found ${distinct}: ${shas//$'\n'/, }"
}

@test "the stance block matches the canonical copy in the create-agent spec" {
  local canonical actual
  canonical="$(_blocks "${_CANONICAL}" | cut -f3)"
  actual="$(_blocks | cut -f3 | sort -u)"
  [[ -n "${canonical}" && "${canonical}" != "-" ]] || fail "${_CANONICAL} carries no canonical block"
  [[ "${actual}" == "${canonical}" ]] || fail "agents diverge from canonical (${actual} vs ${canonical})"
}

@test "the stance block carries the whole block, not a truncated copy" {
  local short="" rel _a _b size _c
  while IFS=$'\t' read -r rel _a _b size _c; do
    [[ "$size" == "11" ]] || short+="${rel} (${size} lines)\n"
  done < <(_blocks)
  if [[ -n "${short}" ]]; then
    printf 'Agents with a truncated stance block:\n%b' "${short}" >&2
    fail "the block is the opening line, a blank, and nine bullets"
  fi
}

@test "the stance sits under a Behaviour heading" {
  local loose="" rel _a _b _c heading
  while IFS=$'\t' read -r rel _a _b _c heading; do
    [[ "$heading" == "yes" ]] || loose+="${rel}\n"
  done < <(_blocks)
  if [[ -n "${loose}" ]]; then
    printf 'Agents with no Behaviour heading above the stance:\n%b' "${loose}" >&2
    fail "the stance is a Behaviour rule, not loose prose"
  fi
}

@test "the scan covers the whole first-party fleet (guards against an empty glob)" {
  local scanned files
  files="$(cd "${PROJECT_ROOT}" && ls -1 src/agentic/*/agents/*.md | wc -l)"
  scanned="$(_blocks | wc -l)"
  [[ "${scanned}" == "${files}" ]] || fail "scanned ${scanned} of ${files} agent files — the reader stopped early"
  _blocks | grep -q '^src/agentic/devbot/agents/devbot.md	' || fail "scan missed devbot.md"
  _blocks | grep -q '^src/agentic/devteam/agents/reviewer.md	' || fail "scan missed reviewer.md"
}

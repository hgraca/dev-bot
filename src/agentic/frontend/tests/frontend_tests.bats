#!/usr/bin/env bats
# =============================================================================
# src/agentic/frontend/tests/frontend_tests.bats
# Contract for the Design QA capability: command and skill front matter, the
# docs.md capability manifest, the canonical Figma MCP manifest and its
# translation to each harness shape, and the config-sourced workflow.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PROJECT_ROOT="$(cd "${MODULE}/../../.." && pwd)"
  TRANSLATE="${PROJECT_ROOT}/src/_shared/mcp_translate.py"
}

front_matter() {
  awk 'NR == 1 && /^---$/ { inside = 1; next } inside && /^---$/ { exit } inside { print }' "$1"
}

manifest_flow_list() {
  sed -n "s/^$1:[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p" "${MODULE}/docs.md" |
    tr ',' '\n' |
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//' |
    sed '/^$/d' |
    sort
}

manifest_mcp_keys() {
  sed -n '/^mcps:/,/^[^[:space:]]/p' "${MODULE}/docs.md" |
    sed -n 's/^[[:space:]][[:space:]]*\([A-Za-z0-9_.-]*\):.*/\1/p' |
    sort
}

disk_commands() {
  for path in "${MODULE}"/commands/*.md; do basename "$path" .md; done | sort
}

disk_skills() {
  for path in "${MODULE}"/skills/*/; do basename "$path"; done | sort
}

disk_mcps() {
  python3 -c 'import json,sys; print("\n".join(sorted(json.load(open(sys.argv[1]))["mcp"])))' \
    "${MODULE}/mcp.json"
}

@test "every command declares name: devbot:<filename> and a description" {
  for path in "${MODULE}"/commands/*.md; do
    name="$(basename "$path" .md)"
    run grep -qx "name: devbot:${name}" "$path"
    assert_success
    run grep -q '^description: ' "$path"
    assert_success
  done
}

@test "every command delegates to its skill" {
  for path in "${MODULE}"/commands/*.md; do
    name="$(basename "$path" .md)"
    body="$(awk 'NR == 1 && /^---$/ { inside = 1; next } inside && /^---$/ { inside = 0; next } !inside' "$path")"
    run grep -qF "following the \`devbot:${name}\` skill" <<<"$body"
    assert_success
  done
}

@test "docs.md commands manifest matches the command files" {
  run diff -u <(disk_commands) <(manifest_flow_list commands)
  assert_success
}

@test "every skill declares valid front matter" {
  for path in "${MODULE}"/skills/*/SKILL.md; do
    name="$(basename "$(dirname "$path")")"
    run front_matter "$path"
    assert_output --partial "name: devbot:${name}"
    run grep -q '^description: ' "$path"
    assert_success
  done
}

@test "docs.md skills manifest matches the skill directories" {
  run diff -u <(disk_skills) <(manifest_flow_list skills)
  assert_success
}

@test "docs.md mcps manifest matches the canonical manifest" {
  run diff -u <(disk_mcps) <(manifest_mcp_keys)
  assert_success
}

@test "docs.md front matter stays inside the restricted subset" {
  fm="$(front_matter "${MODULE}/docs.md")"
  run grep -qE '^[[:space:]]*[A-Za-z0-9_-]+:[[:space:]]*[>|]-?[[:space:]]*$' <<<"$fm"
  assert_failure
  run grep -qE '^[[:space:]]+- ' <<<"$fm"
  assert_failure
}

@test "the module README page is produced by the docs gather" {
  run python3 "${PROJECT_ROOT}/src/agentic/docs/tools/gather-module-docs.py" \
    --root "${PROJECT_ROOT}" --out "${BATS_TEST_TMPDIR}/site"
  assert_success
  run grep -q 'design-qa' "${BATS_TEST_TMPDIR}/site/modules/agentic/frontend.md"
  assert_success
}

@test "the figma server ships wired but not started" {
  run python3 - "${MODULE}/mcp.json" <<'PY'
import json, sys
entry = json.load(open(sys.argv[1]))["mcp"]["figma"]
assert entry["type"] == "http", entry
assert entry["url"] == "https://mcp.figma.com/mcp", entry
assert entry["enabled"] is False, entry
PY
  assert_success
}

@test "the opencode translation registers figma with enabled: false" {
  run python3 "${TRANSLATE}" "${MODULE}/mcp.json" opencode
  assert_success
  run python3 -c 'import json,sys; assert json.load(sys.stdin)["figma"] == {"type": "remote", "url": "https://mcp.figma.com/mcp", "enabled": False}' <<<"$output"
  assert_success
}

@test "the claudecode translation carries no per-server enabled key" {
  run python3 "${TRANSLATE}" "${MODULE}/mcp.json" claudecode
  assert_success
  run python3 -c 'import json,sys; e = json.load(sys.stdin)["figma"]; assert e == {"type": "http", "url": "https://mcp.figma.com/mcp"}, e' <<<"$output"
  assert_success
}

@test "external-modules.json declares the design skill packs" {
  run python3 - "${MODULE}/external-modules.json" <<'PY'
import json, sys

declared = json.load(open(sys.argv[1]))

expected = {
    "anthropic-frontend-design": ("https://github.com/anthropics/skills.git", "skills/frontend-design"),
    "impeccable": ("https://github.com/pbakaus/impeccable.git", ".agent/skills/impeccable"),
}
for name, (url, path) in expected.items():
    entry = declared[name]
    assert entry["url"] == url, entry
    assert entry["paths"] == {"skills": path}, entry

emil_skills = {
    "emil-design-eng": "emil-design-eng",
    "emil-animate": "animate",
    "emil-review-animations": "review-animations",
    "emil-improve-animations": "improve-animations",
}
emil = {name: entry for name, entry in declared.items() if name.startswith("emil-")}
assert sorted(emil) == sorted(emil_skills), sorted(emil)
for name, entry in emil.items():
    assert entry["url"] == "https://github.com/emilkowalski/skills.git", entry
    assert entry["paths"] == {"skills": "skills/" + emil_skills[name]}, entry

# Every declaration wires whole skill directories — one skill, or a pack of them.
for name, entry in declared.items():
    assert set(entry["paths"]) == {"skills"}, (name, entry)

print("OK")
PY
  assert_success
  assert_output "OK"
}

@test "docs.md documents the vendored design skill packs" {
  run grep -qF 'github.com/anthropics/skills' "${MODULE}/docs.md"
  assert_success
  run grep -qF 'github.com/pbakaus/impeccable' "${MODULE}/docs.md"
  assert_success
  run grep -qF 'github.com/emilkowalski/skills' "${MODULE}/docs.md"
  assert_success
}

@test "the skill documents the unconfigured fallbacks" {
  run grep -q 'http://localhost:3000' "${MODULE}/skills/design-qa/SKILL.md"
  assert_success
  run grep -q 'defaults.tolerancePx' "${MODULE}/skills/design-qa/SKILL.md"
  assert_success
  run grep -q '`src/`' "${MODULE}/skills/design-qa/SKILL.md"
  assert_success
}

@test "the single-page workflow never handles credentials or forces flags" {
  run grep -qF 'Never log in yourself and never handle credentials' \
    "${MODULE}/skills/design-qa/SKILL.md"
  assert_success
  run grep -qF 'force or stub feature flags' "${MODULE}/skills/design-qa/SKILL.md"
  assert_success
}

@test "the batch workflow stays report-only" {
  run grep -qF 'Report-only. Never edit files, never use --fix.' \
    "${MODULE}/skills/design-qa-all/SKILL.md"
  assert_success
  run grep -qF 'never pass `--fix`' "${MODULE}/skills/design-qa-all/SKILL.md"
  assert_success
}

@test "the ported workflow carries no consumer-specific literal" {
  local dir
  for dir in commands skills/design-qa skills/design-qa-all; do
    [[ -d "${MODULE}/${dir}" ]] || fail "missing workflow directory: ${dir}"
  done
  run grep -RInE 'hotels\.get-e\.local|backoffice|customer|hotel|develop|pnpm|src/pages|theme\.ts|COLORS|sign-in|Pusher|LaunchDarkly|MuiSkeleton|#launcher|chmln' \
    "${MODULE}/commands" "${MODULE}/skills/design-qa" "${MODULE}/skills/design-qa-all"
  assert_failure
  # 1 = no match; 2 means grep failed (missing path, bad pattern) — not evidence.
  [[ "$status" -eq 1 ]] || fail "grep exited ${status}: ${output}"
}

# ── Design detector hook ─────────────────────────────────────────────────────
# The hook is the module's own file.edited dispatch (hooks.json →
# tools/impeccable-hook.sh), not the upstream provider install: that install
# knows Claude Code/Codex/Cursor/Copilot/Grok/Gemini but not opencode, and it
# looks for the skill outside <devbot_dir>/skills. These tests pin the wiring,
# the project-config seed, and the gates that keep the engine from running where
# the project has not opted in.

HOOK_TOOL() { echo "${MODULE}/tools/impeccable-hook.sh"; }
INIT() { echo "${MODULE}/init.sh"; }

# A project directory with a .git dir (so init writes .gitignore) and no config.
hook_project() {
  local dir="$1"
  mkdir -p "${dir}/.git"
  printf '%s' "${dir}"
}

# A stub launcher at the path the hook resolves first: the linked skill.
# It reports findings in the engine's format and exits 2, so the tests never
# touch the real engine (no download, no network).
stub_launcher() {
  local project="$1" findings="${2:-2}" chars="${3:-40}"
  local dir="${project}/.agents/skills/impeccable/scripts"
  mkdir -p "${dir}"
  cat > "${dir}/impeccable" <<EOF
#!/usr/bin/env bash
# argv: detect <file>
i=0
while [[ \${i} -lt ${findings} ]]; do
  printf '  line %d: [gradient-text] bg-clip-text + bg-gradient\n' "\$((i + 2))"
  printf '    → %s\n' "\$(printf 'x%.0s' \$(seq 1 ${chars}))"
  i=\$((i + 1))
done
echo "${findings} anti-patterns found."
exit 2
EOF
  chmod +x "${dir}/impeccable"
}

# Seed the project config the way init.sh does, optionally overriding the hook.
seed_config() {
  local project="$1" body="${2:-}"
  mkdir -p "${project}/.impeccable"
  if [[ -n "${body}" ]]; then
    printf '%s\n' "${body}" >"${project}/.impeccable/config.json"
  else
    printf '{\n  "hook": {\n    "enabled": true,\n    "limits": { "maxFindings": 5, "maxChars": 8000 }\n  }\n}\n' \
      >"${project}/.impeccable/config.json"
  fi
}

@test "hooks.json declares the design detector on file.edited" {
  run python3 - "${MODULE}/hooks.json" <<'PY'
import json, re, sys

hooks = json.load(open(sys.argv[1]))["hooks"]
assert len(hooks) == 1, hooks
hook = hooks[0]
assert hook["id"] == "impeccable-detector", hook
assert hook["event"] == "file.edited", hook
assert hook["run"][:2] == ["bash", "{module}/tools/impeccable-hook.sh"], hook
assert "{worktree}" in hook["run"] and "{file}" in hook["run"], hook
assert hook["log"].endswith("impeccable.log"), hook
# The findings must reach the agent, not only a log an agent has to remember to
# read: adapters with a mutable tool result (opencode v1 and v2) fold the
# stdout into it.
assert hook["surface"] == "tool-result", hook

pattern = re.compile(hook["match"]["file"])
for ext in (".tsx", ".jsx", ".html", ".vue", ".svelte", ".astro", ".css", ".scss", ".sass", ".less"):
    assert pattern.search("src/a" + ext), ext
# Plain scripts stay out: the engine would then run on every TS edit.
for name in ("src/a.ts", "src/a.js", "src/a.md", "src/a.json"):
    assert not pattern.search(name), name
print("OK")
PY
  assert_success
  assert_output "OK"
}

@test "docs.md declares the hook in its capability manifest" {
  run diff -u <(printf 'impeccable-detector\n') <(manifest_flow_list hooks)
  assert_success
}

@test "init writes .impeccable/config.json with the hook enabled" {
  local project
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"

  run bash "$(INIT)" "${project}"
  assert_success

  run python3 - "${project}/.impeccable/config.json" <<'PY'
import json, sys

cfg = json.load(open(sys.argv[1]))
assert cfg["hook"]["enabled"] is True, cfg
assert cfg["hook"]["limits"]["maxFindings"] == 5, cfg
assert cfg["hook"]["limits"]["maxChars"] == 8000, cfg
print("OK")
PY
  assert_success
  assert_output "OK"
}

@test "init never rewrites an existing config (hooks off stays off)" {
  local project
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"
  seed_config "${project}" '{
  "hook": { "enabled": false },
  "detector": { "ignoreRules": ["overused-font"] }
}'
  before="$(cat "${project}/.impeccable/config.json")"

  run bash "$(INIT)" "${project}"
  assert_success

  # Same bytes: a project that turned the hook off, and its ignore rules, survive
  # a reinit.
  [[ "$(cat "${project}/.impeccable/config.json")" == "${before}" ]]
}

@test "init keeps the machine-local consent file out of git" {
  local project
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"

  run bash "$(INIT)" "${project}"
  assert_success

  grep -qx '.impeccable/config.local.json' "${project}/.gitignore"
  # dev-bot does not write the consent file itself — that is the developer's.
  [[ ! -e "${project}/.impeccable/config.local.json" ]]
}

@test "init does not write the consent file even on a second run" {
  local project
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"

  run bash "$(INIT)" "${project}"
  assert_success
  run bash "$(INIT)" "${project}"
  assert_success

  [[ ! -e "${project}/.impeccable/config.local.json" ]]
  [[ "$(grep -c 'DEVBOT - frontend' "${project}/.gitignore")" -eq 2 ]]
}

@test "the hook stays silent when the project has no config" {
  local project file
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"
  file="${project}/Card.tsx"
  echo 'export const Card = () => <div />' >"${file}"
  stub_launcher "${project}"

  run bash "$(HOOK_TOOL)" "${project}" "${file}"
  assert_success
  assert_output ""
}

@test "the hook stays silent when the config disables it" {
  local project file
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"
  file="${project}/Card.tsx"
  echo 'export const Card = () => <div />' >"${file}"
  stub_launcher "${project}"
  seed_config "${project}" '{ "hook": { "enabled": false } }'

  run bash "$(HOOK_TOOL)" "${project}" "${file}"
  assert_success
  assert_output ""
}

@test "IMPECCABLE_HOOK_DISABLED turns the hook off for one shell" {
  local project file
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"
  file="${project}/Card.tsx"
  echo 'export const Card = () => <div />' >"${file}"
  stub_launcher "${project}"
  seed_config "${project}"

  IMPECCABLE_HOOK_DISABLED=1 run bash "$(HOOK_TOOL)" "${project}" "${file}"
  assert_success
  assert_output ""
}

@test "the hook reports findings and succeeds (a finding is not a failure)" {
  local project file
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"
  file="${project}/Card.tsx"
  echo 'export const Card = () => <div />' >"${file}"
  stub_launcher "${project}" 2 10
  seed_config "${project}"

  run bash "$(HOOK_TOOL)" "${project}" "${file}"
  assert_success
  assert_output --partial "[gradient-text]"
  assert_output --partial "2 anti-patterns found."
}

@test "the hook caps findings to hook.limits.maxFindings" {
  local project file
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"
  file="${project}/Card.tsx"
  echo 'export const Card = () => <div />' >"${file}"
  stub_launcher "${project}" 6 4
  seed_config "${project}" '{ "hook": { "enabled": true, "limits": { "maxFindings": 2 } } }'

  run bash "$(HOOK_TOOL)" "${project}" "${file}"
  assert_success
  [[ "$(grep -c '\[gradient-text\]' <<<"${output}")" -eq 2 ]]
  assert_output --partial "4 more finding(s) not shown"
}

@test "the hook caps the entry to hook.limits.maxChars" {
  local project file
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"
  file="${project}/Card.tsx"
  echo 'export const Card = () => <div />' >"${file}"
  stub_launcher "${project}" 4 40
  seed_config "${project}" '{ "hook": { "enabled": true, "limits": { "maxChars": 80 } } }'

  run bash "$(HOOK_TOOL)" "${project}" "${file}"
  assert_success
  assert_output --partial "output truncated at 80 characters"
}

@test "the hook refuses a devbot_dir that escapes the project" {
  # devbot_dir comes from project config and is joined onto a path that is then
  # executed. A `..` escape (or an absolute path) must not aim that at a script
  # outside the project — the same predicate guards it elsewhere.
  local project file outside
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"
  file="${project}/Card.tsx"
  echo 'export const Card = () => <div />' >"${file}"
  seed_config "${project}"

  outside="${BATS_TEST_TMPDIR}/outside/skills/impeccable/scripts"
  mkdir -p "${outside}"
  printf '#!/usr/bin/env bash\ntouch "%s/PWNED"\n' "${BATS_TEST_TMPDIR}" >"${outside}/impeccable"
  chmod +x "${outside}/impeccable"
  printf '{ "project_name": "evil", "devbot_dir": "../outside" }\n' >"${project}/.devbot.project.jsonc"

  DEV_BOT_ROOT="${BATS_TEST_TMPDIR}/no-devbot" run bash "$(HOOK_TOOL)" "${project}" "${file}"
  assert_success
  assert_output --partial "not a plain relative path"
  assert_output --partial "no launcher found"
  [[ ! -e "${BATS_TEST_TMPDIR}/PWNED" ]] || fail "a launcher outside the project was executed"
}

@test "the hook says so when no launcher is linked" {
  local project file
  project="$(hook_project "${BATS_TEST_TMPDIR}/app")"
  file="${project}/Card.tsx"
  echo 'export const Card = () => <div />' >"${file}"
  seed_config "${project}"

  # No .agents/skills link, and DEV_BOT_ROOT points at a fixture with no vendor
  # clone — so neither launcher candidate resolves.
  DEV_BOT_ROOT="${BATS_TEST_TMPDIR}/no-devbot" run bash "$(HOOK_TOOL)" "${project}" "${file}"
  assert_success
  assert_output --partial "no launcher found"
}

# ── Skill routing (design system vs component tiers) ─────────────────────────
# A design-system request used to load nothing: atomic-design buried "design
# tokens" in a trailing list and no skill owned creating a token system at all.
# The eval sets are the contract now — devbot:design-system owns the contract,
# the themes, the scales and the contrast gate; atomic-design owns the tiers.
# The check is deterministic rather than an LLM run: every eval names the skill
# that must fire and the literal trigger phrases that must route to it, and no
# two skills in this module may claim the same phrase.

# Run a python snippet over every skills/<name>/evals/evals.json in the module.
# Prints "OK" and a summary, or raises with the failing detail.
_route_evals() {
  python3 - "${MODULE}" "$1" <<'PY'
import json, glob, os, re, sys

module, mode = sys.argv[1], sys.argv[2]
skills_dir = os.path.join(module, "skills")


def description(path):
    """The front-matter description of a SKILL.md, or None."""
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None
    d = re.search(r'^description:\s*"?(.*?)"?\s*$', m.group(1), re.M)
    return d.group(1) if d else None


descriptions = {}
for path in glob.glob(os.path.join(skills_dir, "*", "SKILL.md")):
    name = os.path.basename(os.path.dirname(path))
    raw = open(path, encoding="utf-8").read()
    m = re.search(r"^name:\s*(.+)$", raw, re.M)
    descriptions[name] = {
        "declared": m.group(1).strip() if m else "",
        "description": description(path) or "",
    }

files = sorted(glob.glob(os.path.join(skills_dir, "*", "evals", "evals.json")))
assert files, "no evals/evals.json found in " + skills_dir

problems = []
prompts = 0
owners = set()

for path in files:
    data = json.load(open(path, encoding="utf-8"))
    skill_name = data["skill_name"]
    assert skill_name in descriptions, f"{path}: unknown skill_name {skill_name!r}"
    assert data["evals"], f"{path}: no evals"

    for ev in data["evals"]:
        prompts += 1
        where = f"{path} eval {ev['id']} ({ev['name']})"
        for key in ("id", "name", "prompt", "expected_skill", "trigger_phrases", "assertions"):
            assert key in ev, f"{where}: missing {key!r}"
        assert ev["assertions"], f"{where}: no assertions"

        owner = ev["expected_skill"].split(":", 1)[1]
        owners.add(owner)
        assert owner in descriptions, f"{where}: unknown expected_skill {ev['expected_skill']!r}"
        assert descriptions[owner]["declared"] == ev["expected_skill"], (
            f"{where}: SKILL.md declares {descriptions[owner]['declared']!r}"
        )

        for phrase in ev["trigger_phrases"]:
            low = phrase.lower()
            if low not in ev["prompt"].lower():
                problems.append(f"{where}: trigger phrase {phrase!r} is not in the prompt")
            claiming = [
                name
                for name, meta in descriptions.items()
                if low in meta["description"].lower()
            ]
            if owner not in claiming:
                problems.append(
                    f"{where}: {owner}'s description does not carry {phrase!r}"
                )
            if len(claiming) > 1:
                problems.append(
                    f"{where}: {phrase!r} is claimed by {sorted(claiming)} — ownership overlaps"
                )

    if mode == "list":
        print(f"{skill_name}: {len(data['evals'])} eval(s)")

if problems:
    sys.exit("\n".join(problems))

# The design-system boundary needs a real set, not one happy path: create,
# dark mode, variant, reorganise, audit.
ds = json.load(open(os.path.join(skills_dir, "design-system", "evals", "evals.json")))
assert len(ds["evals"]) >= 5, f"design-system needs at least 5 evals, has {len(ds['evals'])}"

# Both sides of the boundary are exercised.
assert {"design-system", "atomic-design"} <= owners, sorted(owners)

# The owning descriptions lead with their trigger (create-skill convention: a
# 'Use when …' clause), so routing is not buried in a trailing list.
for name in ("design-system", "atomic-design"):
    desc = descriptions[name]["description"]
    assert desc.startswith("Use when "), f"{name}: description must open with 'Use when …': {desc[:40]!r}"

print(f"OK: {prompts} prompt(s) routed across {len(owners)} skill(s)")
PY
}

@test "evals/evals.json exist for the design skills and route to their owner" {
  run _route_evals check
  assert_success
  assert_output --partial "OK:"
}

@test "the design-system eval set covers create, dark mode, variant, reorganise and audit" {
  run _route_evals list
  assert_success
  assert_output --partial "design-system: 5 eval(s)"
  assert_output --partial "atomic-design: 2 eval(s)"
}

@test "a design-system request has one owner and no other module skill claims it" {
  # The failure this fixes: the phrase set was split (atomic-design listed
  # 'design tokens', nothing owned creating the system) so no skill fired.
  run grep -q "'design tokens'" "${MODULE}/skills/design-system/SKILL.md"
  assert_success
  run grep -q "'design tokens'" "${MODULE}/skills/atomic-design/SKILL.md"
  assert_failure
  # And the tier skill still leads with its own trigger, pointing at the owner.
  run grep -q 'Use when structuring frontend components by atomic design' \
    "${MODULE}/skills/atomic-design/SKILL.md"
  assert_success
  run grep -q 'devbot:design-system' "${MODULE}/skills/atomic-design/SKILL.md"
  assert_success
}

@test "docs.md lists the design-system skill and states the ownership boundary" {
  run diff -u <(printf 'atomic-design\ndesign-qa\ndesign-qa-all\ndesign-system\nshow-ui-in-browser\nstorybook\n') \
    <(manifest_flow_list skills)
  assert_success
  run grep -qF 'devbot:design-system' "${MODULE}/docs.md"
  assert_success
  run grep -qiF 'harvest' "${MODULE}/docs.md"
  assert_success
}

@test "both opencode adapters fold a surface hook into the tool result" {
  # The manifest asks for surfacing; an adapter that ignores the field would
  # leave the detector log-only and nobody would notice from the manifest alone.
  run grep -q "surfaceFindings" "${PROJECT_ROOT}/src/harnesses/opencode/hooks/on-hooks.ts"
  assert_success
  run grep -q "surfaceFindings" "${PROJECT_ROOT}/src/harnesses/opencode-v2/hooks/on-hooks.ts"
  assert_success
  # …and both skip the debounced file.edited dispatch, or every edit would run
  # the detector twice.
  run grep -q "if (hook.surface) continue" "${PROJECT_ROOT}/src/harnesses/opencode/hooks/on-hooks.ts"
  assert_success
  run grep -q "if (hook.surface) continue" "${PROJECT_ROOT}/src/harnesses/opencode-v2/hooks/on-hooks.ts"
  assert_success
  # The shared append helper lives in each adapter's utils, because the two
  # harnesses carry separate copies (decision 3 of the v2 adapter backlog).
  run grep -q "export function appendToToolResult" "${PROJECT_ROOT}/src/harnesses/opencode/on-hooks-utils.ts"
  assert_success
  run grep -q "export function appendToToolResult" "${PROJECT_ROOT}/src/harnesses/opencode-v2/on-hooks-utils.ts"
  assert_success
}

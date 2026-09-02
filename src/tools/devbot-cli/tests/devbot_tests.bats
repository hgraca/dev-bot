#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
}

@test "devbot init scaffolds a project directory from the test template" {
  local test_project="$PROJECT_ROOT/storage/test"
  local template_dir="$TEST_DIR/_test-template"

  # Clean up any previous test run
  rm -rf "$test_project"
  mkdir -p "$(dirname "$test_project")"

  # Copy template to test location
  cp -r "$template_dir" "$test_project"

  # Run devbot init in the test project directory.
  # Note: cmd_init calls install.sh which has its own env dependencies (docker, ollama).
  # The scaffolding (steps 1-5) completes before install.sh runs (step 6),
  # so we verify scaffolding files directly rather than coupling to install.sh's exit code.
  run bash "$PROJECT_ROOT/bin/devbot" init "$test_project"
  # BW01: no exit-code assert — install.sh (step 6) may fail in envs missing ollama.
  # Test verifies scaffolding files directly. Warning is harmless.

  # ── Verify vault root ──────────────────────────────────────────────────
  [ -d "$test_project/.agents" ]

  # ── Verify bootstrap files ─────────────────────────────────────────────
  [ -f "$test_project/.agents/memory/active/ignore.md" ]
  [ -f "$test_project/.agents/memory/active/preemptive-skill-loading-list.md" ]
  [ -f "$test_project/.agents/memory/active/memory.md" ]

  # ── Verify latent subdirectories with .gitkeep ─────────────────────────
  [ -d "$test_project/.agents/memory/latent/ADRs" ]
  [ -f "$test_project/.agents/memory/latent/ADRs/.gitkeep" ]
  [ -d "$test_project/.agents/memory/latent/PDRs" ]
  [ -f "$test_project/.agents/memory/latent/PDRs/.gitkeep" ]
  [ -d "$test_project/.agents/memory/latent/learnings" ]
  [ -f "$test_project/.agents/memory/latent/learnings/.gitkeep" ]

  # ── Verify global symlink ──────────────────────────────────────────────
  [ -L "$test_project/.agents/memory/latent/global" ]
  [ "$(readlink "$test_project/.agents/memory/latent/global")" \
    = "$PROJECT_ROOT/storage/global-memories" ]

  # ── Verify work directories with .gitkeep ──────────────────────────────
  [ -d "$test_project/.agents/memory/work/active" ]
  [ -f "$test_project/.agents/memory/work/active/.gitkeep" ]
  [ -d "$test_project/.agents/memory/work/archive" ]
  [ -f "$test_project/.agents/memory/work/archive/.gitkeep" ]

  # ── Verify reference and thinking with .gitkeep ────────────────────────
  [ -d "$test_project/.agents/memory/reference" ]
  [ -f "$test_project/.agents/memory/reference/.gitkeep" ]
  [ -d "$test_project/.agents/memory/thinking" ]
  [ -f "$test_project/.agents/memory/thinking/.gitkeep" ]

  # ── Verify config files ────────────────────────────────────────────────
  [ -f "$test_project/.devbot.project.jsonc" ]
  [ -f "$test_project/opencode.jsonc" ]
  grep -qF '"plugin"' "$test_project/opencode.jsonc" || fail "opencode.jsonc missing plugin key"
  grep -qF '"agent"' "$test_project/opencode.jsonc" || fail "opencode.jsonc missing agent key"
  grep -qF '"permission"' "$test_project/opencode.jsonc" || fail "opencode.jsonc missing permission key"

  # ── Verify .git/info/exclude was updated with .ai/ entry ───────────────
  [ -f "$test_project/.git/info/exclude" ]
  grep -qF "# >>> DEVBOT - memory" "$test_project/.git/info/exclude"

  # ── Verify .opencode directory created by opencode init ────────────────
  [ -d "$test_project/.opencode" ]
  [ -d "$test_project/.opencode/agents" ]
  [ -d "$test_project/.opencode/commands" ]
  [ -d "$test_project/.opencode/plugins" ]
  [ -d "$test_project/.opencode/tools" ]

  # ── Verify agents match source ─────────────────────────────────────────
  MODULES_WITH_AGENTS=(devbot devteam)
  for MODULE in "${MODULES_WITH_AGENTS[@]}"; do
    local source_agents="$PROJECT_ROOT/src/agentic/${MODULE}/agents"
    local linked_agents="$test_project/.opencode/agents/${MODULE}"
    [ -L "$linked_agents" ] || fail "agents/${MODULE} is not a symlink"
    [ "$(readlink "$linked_agents")" = "$source_agents" ] || fail "agents/${MODULE} points wrong target"
    # Compare file listings
    diff <(ls "$source_agents" | sort) <(ls "$linked_agents" | sort) \
      || fail "agents mismatch between source and symlink"
  done

  # ── Verify commands match source ───────────────────────────────────────
  # Commands are linked individually under .opencode/commands/devbot/ NAMED
  # after their frontmatter name (devbot:audit → devbot/audit.md), so both
  # harnesses expose the same slash command. No per-module category symlinks.
  local MODULES_WITH_COMMANDS=(dev devteam explore git github memory)
  local linked_commands_dir="$test_project/.opencode/commands/devbot"
  [ -d "$linked_commands_dir" ] || fail "commands/devbot/ is missing"
  for MODULE in "${MODULES_WITH_COMMANDS[@]}"; do
    local source_commands="$PROJECT_ROOT/src/agentic/${MODULE}/commands"
    [ -L "$test_project/.opencode/commands/${MODULE}" ] \
      && fail "old per-module command symlink commands/${MODULE} should not exist"
    for cmd_file in "$source_commands"/*.md; do
      [ -f "$cmd_file" ] || continue
      local cmd_name bare
      cmd_name="$(sed -n 's/^name:[[:space:]]*//p' "$cmd_file" | head -1 | tr -d '"')"
      bare="${cmd_name#devbot:}"
      local linked="$linked_commands_dir/${bare}.md"
      [ -L "$linked" ] || fail "commands/${bare}.md is not a symlink"
      [ "$(readlink "$linked")" = "$cmd_file" ] || fail "commands/${bare}.md points wrong target"
    done
  done

  # ── Verify skills match source ─────────────────────────────────────────
  local source_skills_dir="$PROJECT_ROOT/src/agentic"
  # Skills live in .agents/skills (not .opencode/skills — the opencode harness
  # skips the skills delegation since opencode loads .agents/skills directly).
  local linked_skills="$test_project/.agents/skills/devbot"
  [ -d "$linked_skills" ] || fail "skills/devbot/ is missing"
  # Build expected module list: modules that have a skills/ directory (non-disabled)
  local expected_skills=""
  for mod_dir in "$source_skills_dir/"*/; do
    [[ -d "${mod_dir}skills" ]] || continue
    # Skip disabled modules (react, svelte are disabled in devbot config)
    local mod_name=$(basename "$mod_dir")
    [[ "$mod_name" == "react" || "$mod_name" == "svelte" ]] && continue
    expected_skills="$expected_skills$mod_name\n"
  done
  # Compare against what's actually linked
  local actual_skills=""
  for link in "$linked_skills/"*; do
    [[ -L "$link" ]] || continue
    actual_skills="$actual_skills$(basename "$link")\n"
  done
  diff <(printf "$expected_skills" | sort) <(printf "$actual_skills" | sort) \
    || fail "skills mismatch between source and symlink"

  # ── Verify external module symlinks (from devbot root config) ────────────
  # addyosmani module configured in .devbot.jsonc should be cloned and wired.
  # This only applies when running from the real devbot install (not CI without vendor).
  # External artifacts wire into the DEVBOT DIR (.agents/<type>/<name>), not
  # .opencode/ — harness-agnostic (commit 75dd8883). Skills are never delegated
  # to .opencode/skills (the opencode harness loads .agents/skills directly), so
  # .agents/ is the authoritative location to assert.
  if [[ -d "$PROJECT_ROOT/vendor/addyosmani/agent-skills" ]]; then
    # agents symlink — namespaced name nests under .agents/<type>/<org>/<repo>.
    local addy_agents="$test_project/.agents/agents/addyosmani/agent-skills"
    [ -L "$addy_agents" ] || fail "agents/addyosmani/agent-skills is not a symlink"
    [ "$(readlink "$addy_agents")" = "$PROJECT_ROOT/vendor/addyosmani/agent-skills/agents" ] \
      || fail "agents/addyosmani/agent-skills points wrong target"
    [ -d "$(readlink "$addy_agents")" ] || fail "agents/addyosmani/agent-skills target missing"

    # skills symlink
    local addy_skills="$test_project/.agents/skills/addyosmani/agent-skills"
    [ -L "$addy_skills" ] || fail "skills/addyosmani/agent-skills is not a symlink"
    [ "$(readlink "$addy_skills")" = "$PROJECT_ROOT/vendor/addyosmani/agent-skills/skills" ] \
      || fail "skills/addyosmani/agent-skills points wrong target"
    [ -d "$(readlink "$addy_skills")" ] || fail "skills/addyosmani/agent-skills target missing"
  fi

  # ── Verify plugins are symlinked and trigger correct tools ──────────────
  # Convention: plugin files named on-<event>-<module>.<ext> in hooks/opencode/
  # should have corresponding tool files in the module's tools/ directory.
  # Verify by checking the symlink target resolves to a real hook file,
  # and that the same module has at least one tool in .opencode/tools/.
  for plugin in "$test_project/.opencode/plugins/"*; do
    [ -f "$plugin" ] || continue
    # graphify.js is installed as a regular file by `graphify install --platform opencode --project`
    # (external tool), so skip it — the other plugins are symlinked from module hooks/opencode/
    [[ "$(basename "$plugin")" == "graphify.js" ]] && continue
    # Should be a symlink to a real hook file
    [ -L "$plugin" ] || fail "Plugin $plugin is not a symlink"
    [ -e "$plugin" ] || fail "Plugin $plugin symlink is broken (target: $(readlink "$plugin"))"
  done

  # Specific checks for key plugins — the generic adapter and the manifest-
  # declared auto-recover hooks (loaded via on-hooks, not standalone).
  grep -qF "hooks.json" "$test_project/.opencode/plugins/on-hooks.ts" \
    || fail "generic on-hooks adapter missing"

  grep -qF "auto-recover" "$PROJECT_ROOT/src/agentic/auto-recover/hooks.json" \
    || fail "auto-recover manifest missing"
  grep -qF "watchdog-silent-stall" "$PROJECT_ROOT/src/agentic/auto-recover/hooks.json" \
    || fail "watchdog manifest missing"

  # Manifest-declared hooks must not be registered standalone (double-fire).
  [ ! -e "$test_project/.opencode/plugins/on-session_error-auto-recover.ts" ] \
    || fail "auto-recover hook double-registered as standalone plugin"
  [ ! -e "$test_project/.opencode/plugins/on-watchdog-silent-stall.ts" ] \
    || fail "watchdog hook double-registered as standalone plugin"

  # ── Verify module files created by init scripts ────────────────────────
  [ -f "$test_project/.graphifyignore" ]
  [ -f "$test_project/repomix.config.json" ]

  # ── Verify git hooks created by graphify (optional, requires graphify binary) ──
  if [ -f "$test_project/.git/hooks/post-checkout" ]; then
    [ -f "$test_project/.git/hooks/post-checkout" ]
    grep -qF "DEVBOT GRAPHIFY" "$test_project/.git/hooks/post-checkout"
    [ -f "$test_project/.git/hooks/post-merge" ]
    grep -qF "DEVBOT GRAPHIFY" "$test_project/.git/hooks/post-merge"
    [ -f "$test_project/.git/hooks/post-rewrite" ]
    grep -qF "DEVBOT GRAPHIFY" "$test_project/.git/hooks/post-rewrite"

    # ── Verify git hooks created by remember-session + graphify ────────────
    [ -f "$test_project/.git/hooks/post-commit" ]
    grep -qF "DEVBOT GRAPHIFY" "$test_project/.git/hooks/post-commit"
    grep -qF "DEVBOT remember-session START" "$test_project/.git/hooks/post-commit"
  fi
  # ── Cleanup ────────────────────────────────────────────────────────────
#  rm -rf "$test_project"
}

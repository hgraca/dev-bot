#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/link_agents_tests.bats
# _link_agents farms ONE LINK PER AGENT, named after the agent's frontmatter
# `name`:
#   .agents/agents/<name>.md  ->  <module>/agents/<file>.md
#
# The link name IS the agent id on an OpenCode 2 host, which derives it from the
# path below `.opencode/agents`; a module-directory link registered every agent
# as `<module>/<name>`, so the config's bare `agents.<name>` entries and
# `default_agent` matched nothing and the session ran a prompt-less agent (no
# persona, no session-start rules, no worktree workflow).
#
# It must also convert the old module-directory link without touching user
# content, and prune what a module no longer ships.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"

  SANDBOX="$(mktemp -d)"
  export DEV_BOT_ROOT="${SANDBOX}/devbot"
  AGENT_MODULE="${DEV_BOT_ROOT}/src/agentic/devbot/agents"
  mkdir -p "${AGENT_MODULE}"
  printf -- '---\nname: devbot\n---\n' > "${AGENT_MODULE}/devbot.md"
  printf -- '---\nname: scout\n---\n' > "${AGENT_MODULE}/scout.md"

  # shellcheck source=../functions.sh
  source "${MODULE_DIR}/functions.sh"
  AGENTS_DIR="${SANDBOX}/project/.agents"
  mkdir -p "${AGENTS_DIR}/agents"
}

teardown() {
  rm -r -f "${SANDBOX}"
}

@test "_link_agents: links each agent flat, at its frontmatter name" {
  _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"

  [ -L "${AGENTS_DIR}/agents/devbot.md" ]
  [ -L "${AGENTS_DIR}/agents/scout.md" ]
  [ "$(readlink "${AGENTS_DIR}/agents/devbot.md")" = "${AGENT_MODULE}/devbot.md" ]
  # No module-directory entry: that is what namespaced the id.
  [ ! -e "${AGENTS_DIR}/agents/devbot" ]
}

@test "_link_agents: the old module-directory link is converted, not kept" {
  ln -s "${AGENT_MODULE}" "${AGENTS_DIR}/agents/devbot"

  _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"

  [ ! -e "${AGENTS_DIR}/agents/devbot" ]
  [ -L "${AGENTS_DIR}/agents/devbot.md" ]
}

@test "_link_agents: a user's own link named after the module is left alone" {
  local foreign="${SANDBOX}/user-agents"
  mkdir -p "${foreign}"
  ln -s "${foreign}" "${AGENTS_DIR}/agents/devbot"

  run _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"

  assert_output --partial "links outside this module"
  [ -L "${AGENTS_DIR}/agents/devbot" ]
  [ "$(readlink "${AGENTS_DIR}/agents/devbot")" = "${foreign}" ]
  # The flat links are still created, so the configured names resolve.
  [ -L "${AGENTS_DIR}/agents/devbot.md" ]
}

@test "_link_agents: a real directory named after the module does not block the farm" {
  mkdir -p "${AGENTS_DIR}/agents/devbot"

  run _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"

  assert_output --partial "is not our link"
  [ -d "${AGENTS_DIR}/agents/devbot" ]
  [ -L "${AGENTS_DIR}/agents/devbot.md" ]
  [ -L "${AGENTS_DIR}/agents/scout.md" ]
}

@test "_link_agents: an agent a module no longer ships is pruned" {
  _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"
  rm "${AGENT_MODULE}/scout.md"

  _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"

  [ ! -L "${AGENTS_DIR}/agents/scout.md" ]
  [ -L "${AGENTS_DIR}/agents/devbot.md" ]
}

@test "_link_agents: a module that drops its agents dir leaves no dangling link" {
  _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"
  rm -r "${AGENT_MODULE}"

  _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"

  [ ! -L "${AGENTS_DIR}/agents/devbot.md" ]
  [ ! -L "${AGENTS_DIR}/agents/scout.md" ]
}

@test "_link_agents: a user's file is never replaced by a link" {
  printf 'mine\n' > "${AGENTS_DIR}/agents/devbot.md"

  run _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"

  assert_output --partial "exists but is not a symlink"
  [ ! -L "${AGENTS_DIR}/agents/devbot.md" ]
  [ "$(cat "${AGENTS_DIR}/agents/devbot.md")" = "mine" ]
  [ -L "${AGENTS_DIR}/agents/scout.md" ]
}

@test "_link_modules: disabling a module takes its agent links back out" {
  project="${SANDBOX}/project"
  export DEV_BOT_GLOBAL_CONFIG="${SANDBOX}/global.jsonc"
  printf '{}\n' > "${DEV_BOT_GLOBAL_CONFIG}"
  PROJECT_DIR="${project}"

  printf '{ "modules": {} }\n' > "${project}/.devbot.project.jsonc"
  _link_modules >/dev/null
  [ -L "${AGENTS_DIR}/agents/devbot.md" ]
  [ -L "${AGENTS_DIR}/agents/scout.md" ]

  # Reinit after `modules.devbot: false` — the module is skipped, so its links
  # must be reconciled away by the disabled branch instead.
  printf '{ "modules": { "devbot": false } }\n' > "${project}/.devbot.project.jsonc"
  _link_modules >/dev/null
  [ ! -L "${AGENTS_DIR}/agents/devbot.md" ]
  [ ! -L "${AGENTS_DIR}/agents/scout.md" ]
}

@test "_link_agents: a user's own symlink at the flat entry is preserved" {
  foreign="${SANDBOX}/user-devbot.md"
  printf -- '---\nname: mine\n---\n' > "${foreign}"
  ln -s "${foreign}" "${AGENTS_DIR}/agents/devbot.md"

  run _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"

  assert_output --partial "links outside this module"
  [ "$(readlink "${AGENTS_DIR}/agents/devbot.md")" = "${foreign}" ]
  [ -L "${AGENTS_DIR}/agents/scout.md" ]
}

@test "_link_agents: our own stale link is re-pointed at the shipped file" {
  ln -s "${AGENT_MODULE}/old-name.md" "${AGENTS_DIR}/agents/devbot.md"

  _link_agents "${DEV_BOT_ROOT}/src/agentic/devbot/"

  [ "$(readlink "${AGENTS_DIR}/agents/devbot.md")" = "${AGENT_MODULE}/devbot.md" ]
}

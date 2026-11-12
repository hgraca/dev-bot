#!/usr/bin/env bats
# =============================================================================
# src/agentic/autobot/tests/autobot_install_tests.bats
# Cron registration for the tick: idempotent, user-level, nothing duplicated.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  SANDBOX="$(mktemp -d)"

  export DEV_BOT_ROOT="${SANDBOX}/dev-bot"
  export HOME="${SANDBOX}/home"
  export XDG_STATE_HOME="${SANDBOX}/state"
  export XDG_CONFIG_HOME="${SANDBOX}/config"
  export CRONTAB_STORE="${SANDBOX}/crontab.store"
  export DEV_BOT_AUTOBOT_ALLOW_ROOT=1
  unset DEV_BOT_AUTOBOT

  mkdir -p "${DEV_BOT_ROOT}/bin" "${HOME}"
  printf '#!/usr/bin/env bash\nexit 0\n' >"${DEV_BOT_ROOT}/bin/devbot"
  chmod +x "${DEV_BOT_ROOT}/bin/devbot"

  cat >"${SANDBOX}/crontab" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  -l)
    if [[ -f "${CRONTAB_STORE}" ]]; then cat "${CRONTAB_STORE}"; else exit 1; fi
    ;;
  *)
    cp "${1}" "${CRONTAB_STORE}"
    ;;
esac
SH
  chmod +x "${SANDBOX}/crontab"
  export DEV_BOT_CRONTAB="${SANDBOX}/crontab"
}

teardown() {
  rm -rf "${SANDBOX}"
}

@test "registers one cron entry pointing at the devbot tool" {
  run bash "${MODULE_DIR}/install.sh"
  assert_success
  run cat "${CRONTAB_STORE}"
  assert_output --partial "# >>> devbot:autobot >>>"
  assert_output --partial "${DEV_BOT_ROOT}/bin/devbot"
  assert_output --partial "tool autobot tick"
  assert_output --partial "tool autobot cleanup"
  assert_output --partial "${XDG_STATE_HOME}/devbot/autobot.log"
  assert_output --partial "autobot.env"
}

@test "is idempotent across runs" {
  bash "${MODULE_DIR}/install.sh" >/dev/null
  bash "${MODULE_DIR}/install.sh" >/dev/null
  run grep -c '^# >>> devbot:autobot >>>$' "${CRONTAB_STORE}"
  assert_output "1"
  run grep -c '^# <<< devbot:autobot <<<$' "${CRONTAB_STORE}"
  assert_output "1"
}

@test "keeps unrelated entries" {
  printf '0 3 * * * /usr/bin/something\n' >"${CRONTAB_STORE}"
  run bash "${MODULE_DIR}/install.sh"
  assert_success
  run cat "${CRONTAB_STORE}"
  assert_output --partial "/usr/bin/something"
  assert_output --partial "tool autobot tick"
}

@test "replaces a stale block rather than appending to it" {
  cat >"${CRONTAB_STORE}" <<EOF
# >>> devbot:autobot >>>
* * * * * /old/path/devbot tool autobot tick
# <<< devbot:autobot <<<
EOF
  run bash "${MODULE_DIR}/install.sh"
  assert_success
  run grep -c '/old/path/devbot' "${CRONTAB_STORE}"
  assert_output "0"
  run grep -c 'tool autobot tick' "${CRONTAB_STORE}"
  assert_output "1"
}

@test "refuses a credentials file that is not mode 600" {
  mkdir -p "${XDG_CONFIG_HOME}/devbot"
  printf 'export JIRA_API_TOKEN=x\n' >"${XDG_CONFIG_HOME}/devbot/autobot.env"
  chmod 644 "${XDG_CONFIG_HOME}/devbot/autobot.env"

  run bash "${MODULE_DIR}/install.sh"
  assert_failure
  assert_output --partial "chmod 600"
  assert [ ! -f "${CRONTAB_STORE}" ]
}

@test "refuses a path that cannot be written safely into a crontab" {
  DEV_BOT_ROOT="${SANDBOX}/dev bot"
  mkdir -p "${DEV_BOT_ROOT}/bin"
  cp "${DEV_BOT_ROOT}/../dev-bot/bin/devbot" "${DEV_BOT_ROOT}/bin/devbot" 2>/dev/null || true
  printf '#!/usr/bin/env bash\nexit 0\n' >"${DEV_BOT_ROOT}/bin/devbot"
  chmod +x "${DEV_BOT_ROOT}/bin/devbot"
  export DEV_BOT_ROOT

  run bash "${MODULE_DIR}/install.sh"
  assert_failure
  assert_output --partial "unsafe path"
  assert [ ! -f "${CRONTAB_STORE}" ]
}

@test "does nothing when switched off" {
  export DEV_BOT_AUTOBOT=off
  run bash "${MODULE_DIR}/install.sh"
  assert_success
  assert [ ! -f "${CRONTAB_STORE}" ]
}

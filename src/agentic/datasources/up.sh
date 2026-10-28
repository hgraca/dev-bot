#!/usr/bin/env bash
# src/agentic/datasources/up.sh
# Brings the datasource gateway up: re-renders the artifacts, then starts the
# module-generated compose file.
#
# The compose file is rendered into storage/datasources/ rather than shipped in
# the module dir because the gateway must receive the env var names declared in
# .devbot.global.jsonc, and those names are dynamic. bin/up.sh discovers compose
# files by scanning src/{tools,agentic,harnesses}, so it does not see this one —
# the module brings its own compose up (and down.sh takes it back down).
#
# Non-fatal by design: a gateway that will not start must not fail the boot.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# The project this boot serves, passed by bin/up.sh. It decides which sidecars
# are demanded, both at render time (render.sh) and at start time (the demand
# reconcile below).
PROJECT_DIR="${1:-}"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# Take the gateway down before rendering. render.sh verifies a publish against
# a RUNNING gateway by waiting a reload interval — twice, if the first read
# looks like a rejection — so a container left over from the previous session
# would add that wait to every boot. Rendering cold also guarantees the
# container comes back up on the config just validated, rather than depending
# on toolbox to hot-reload it.
_stop_gateway() {
  [[ -f "${COMPOSE_FILE}" ]] || return 0
  (
    cd "${RUNTIME_DIR}" &&
      TOOLBOX_IMAGE="${TOOLBOX_IMAGE}" TOOLBOX_VERSION="${TOOLBOX_VERSION}" \
        docker compose -f "${COMPOSE_FILE}" down
  ) >/dev/null 2>&1 || true
}

main() {
  _info "datasources — up"

  # Docker first: rendering now validates the candidate by running the pinned
  # toolbox, so a machine without docker cannot render — and has no gateway to
  # render for.
  if ! command -v docker >/dev/null 2>&1; then
    _warn "docker not found — datasources gateway not started."
    return 0
  fi

  # One lifecycle run at a time: this stops the gateway before rendering, which
  # would otherwise pull the floor out from under a concurrent `datasources
  # reload` verifying what it just rendered.
  #
  # A boot WAITS rather than skipping. It is the authoritative convergence for
  # its own project: a session registers before it invokes this script, so once
  # the lock is had the sidecar-demand snapshot below sees it. Skipping would
  # let a session start with a sidecar its project selected and nothing serving
  # it — the very outage this module refuses to leave silent. The cap is
  # generous because a reload is bounded (canary + gateway wait + probes); only
  # a genuinely stuck run hits it, and then the boot says so instead of hiding it.
  if ! DATASOURCES_LOCK_WAIT="${DATASOURCES_BOOT_LOCK_WAIT:-180}" _datasources_lock; then
    _warn "datasources — another lifecycle run is still in progress; your datasources may not answer until the next start"
    return 0
  fi

  # Both must be gone before render.sh runs: the legacy poller would race it,
  # and a running gateway would make it pay the reload-verification wait.
  _stop_legacy_poller
  _stop_gateway

  # Rendering validates the candidate against the real toolbox, which can fail
  # (an unreadable catalogue, docker down, or an inconclusive run). Keep going
  # with the config already on disk: a gateway up on the last good config beats
  # no gateway at all, and the next `devbot up` re-renders.
  if ! DATASOURCES_LIFECYCLE_HELD=1 bash "${MODULE_DIR}/render.sh" "${PROJECT_DIR}"; then
    _warn "datasources — render failed; starting the gateway with the previous config."
  fi

  # ...but there has to be something to serve. An empty catalogue — no
  # datasources declared, or every one rejected — means zero tools: starting the
  # gateway is pure cost, and on macOS/Windows Docker Desktop it is cost with no
  # upside, because host networking is a Linux capability and the container comes
  # up answering nobody.
  #
  # Keyed on the artifacts, never on the render's exit status: the two disagree
  # exactly when it matters. A failed render over a stale EMPTY catalogue would
  # otherwise start the zero-tool gateway this guard exists to prevent.
  # Which sidecars the live sessions actually demand: a sidecar is rendered from
  # the static project set but STARTED only for a project someone has open. The
  # project being booted counts too, in case it is not yet in the registry.
  #
  # The snapshot and the STOP run under the registry lock, which a session
  # release also holds for its reconcile — so a stop it applies cannot land
  # between this snapshot and its apply. The lock also serialises the registry
  # read against a session registering. A catalogue read that FAILS leaves the
  # running set untouched (never "stop everything"), and an unavailable lock
  # only skips the stop — starting is the benign direction.
  local sidecars="" has_sources="false" wanted=""
  local registry_dir
  registry_dir="$(_devbot_sessions_dir)"
  if mkdir -p "${registry_dir}" 2>/dev/null &&
    _devbot_lock_wait "${registry_dir}" 30 \
      "session registry lock held — sidecars left as they are"; then
    # shellcheck disable=SC2046  # project paths are space-free; split on purpose
    if wanted="$(_wanted_sidecars $(_devbot_live_session_projects) "${PROJECT_DIR}")"; then
      _reconcile_sidecars "${wanted}"
    else
      wanted=""
      _warn "datasources — could not read the catalogue; leaving the running sidecars untouched"
    fi
    { exec 200>&-; } 2>/dev/null || true
  else
    _warn "datasources — session registry lock unavailable; not reconciling sidecars"
    # shellcheck disable=SC2046  # project paths are space-free; split on purpose
    wanted="$(_wanted_sidecars $(_devbot_live_session_projects) "${PROJECT_DIR}")" || wanted=""
  fi

  sidecars="$(_sidecar_services)"
  _catalogue_has_sources && has_sources="true"

  if [[ "${has_sources}" != "true" && -z "${sidecars}" ]]; then
    _skip "datasources — no usable datasources; gateway not started"
    return 0
  fi

  _devbot_load_env

  # Each service is brought up ON ITS OWN. `docker compose up` fails as a unit
  # when any service's image or build context cannot be prepared — which would
  # let a broken sidecar take the gateway down with it, the exact coupling a
  # sidecar is supposed to be isolated from. --no-deps keeps the gateway
  # independent of the sidecars in the same project.
  local gateway_started="false"
  if [[ "${has_sources}" == "true" ]]; then
    if _start_gateway; then
      gateway_started="true"
    else
      _warn "datasources gateway failed to start — continuing without it."
    fi
  else
    _skip "datasources — no toolbox sources; gateway not started"
  fi

  # Only a RENDERED service that is also demanded runs: a live project absent
  # from the configured project list can demand a sidecar the render gate never
  # emitted, and `up --build` on that would fail every boot.
  local service
  for service in ${sidecars}; do
    _list_has_word "${service}" "${wanted}" || continue
    if _start_sidecar "${service}"; then
      _ok "datasources — sidecar '${service}' started"
    else
      _warn "datasources — sidecar '${service}' failed to start; its manifest will not answer"
    fi
  done

  # Nothing more to wait on when the gateway itself was not started.
  if [[ "${gateway_started}" != "true" ]]; then
    return 0
  fi

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort the boot.
  # The container name lets the wait stop as soon as the gateway has exited,
  # instead of retrying a URL nothing can answer.
  local gateway_url
  gateway_url="$(_datasources_gateway_url)"
  if _devbot_wait_for_mcp_gateway datasources "${gateway_url}" "" "$(_gateway_container_name)"; then
    _ok "datasources gateway reachable at ${gateway_url}"
  fi

  return 0
}

main "$@"

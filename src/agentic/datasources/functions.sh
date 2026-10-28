#!/usr/bin/env bash
# src/agentic/datasources/functions.sh
# Thin wrapper: sources the root shared library, plus the module's helpers that
# the lifecycle scripts (up.sh, reload.sh, reconcile.sh) share.
set -euo pipefail
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MODULE_DIR
source "${MODULE_DIR}/../../_shared/functions.sh"
# shellcheck source=./versions.env
source "${MODULE_DIR}/versions.env"

# ── Rendered artifacts ───────────────────────────────────────────────────────
#
# Every script in this module agrees on where the render writes and what the
# gateway answers on. Derived, never configured.
RUNTIME_DIR="${RUNTIME_DIR:-${DEV_BOT_ROOT}/storage/datasources}"
COMPOSE_FILE="${COMPOSE_FILE:-${RUNTIME_DIR}/docker-compose.yml}"
CONF_FILE="${CONF_FILE:-${RUNTIME_DIR}/conf/tools.yaml}"

# ── Membership tests ─────────────────────────────────────────────────────────
#
# Never `writer | grep -q`: grep exits on the first match, the writer takes
# SIGPIPE on its next write, and `pipefail` reports the pipeline as failed — so
# a name that IS in a long list reads as absent. It flagged a served sidecar as
# unpublishable in CI (the first entry of a multi-line list, intermittently).
# A here-string is not a pipeline, so there is nothing to report failure for.

# Is <needle> one whole line of <haystack>?
_list_has() {
  local needle="$1" haystack="$2"
  grep -Fqx -- "${needle}" <<< "${haystack}"
}

# Is <needle> one space-separated word of <haystack>?
_list_has_word() {
  local needle="$1" haystack="$2"
  grep -Fq -- " ${needle} " <<< " ${haystack} "
}

# Resolved at CALL time, never at source time: DATASOURCES_PORT may arrive with
# the .env each entry point loads after it sources this file.
_datasources_gateway_url() {
  printf 'http://127.0.0.1:%s/mcp' "${DATASOURCES_PORT:-18510}"
}

# ── Environment ──────────────────────────────────────────────────────────────

# Compose interpolates ${VAR} from THIS process's environment, and it only
# auto-reads a .env beside the compose file — which is storage/, not the repo
# root. The availability filter must see the same values, so every entry point
# loads it explicitly.
_devbot_load_env() {
  [[ -f "${DEV_BOT_ROOT}/.env" ]] || return 0
  set -a
  # shellcheck disable=SC1091
  source "${DEV_BOT_ROOT}/.env"
  set +a
}

# Run a command with a hard cap. A wedged docker socket must not block the boot,
# and GNU `timeout` is absent on macOS, so this is a portable bash watchdog (the
# same pattern as bin/update.sh's tag fetch). Returns 124 when the cap is hit —
# callers treat that as "inconclusive", never as "the image is absent".
_docker_bounded() {
  local cap="${DATASOURCES_DOCKER_PROBE_TIMEOUT:-10}"
  "$@" >/dev/null 2>&1 &
  local pid=$! waited=0
  while kill -0 "${pid}" 2>/dev/null; do
    if [[ "${waited}" -ge "${cap}" ]]; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "${pid}" 2>/dev/null
}

# The toolbox image is a multi-hundred-MB download, and this compose is rendered
# into storage/ where bin/up.sh's discovery — and so its centralized
# _announce_missing_images notice — cannot see it. Say it here, before compose
# starts pulling, for the same reason: a silent multi-minute wait reads as a
# hang. Best effort: a failed probe just means no notice.
_announce_missing_toolbox_image() {
  # `docker image inspect` fails for an unreachable daemon just as it does for a
  # missing image, and only the latter downloads anything. Probe the daemon
  # first: a broken docker gets its real error from compose a moment later, not
  # a "downloading now" that cannot happen. A probe that times out is
  # inconclusive and stays silent for the same reason.
  local rc=0
  _docker_bounded docker info || rc=$?
  [[ ${rc} -eq 0 ]] || return 0

  rc=0
  _docker_bounded docker image inspect "${TOOLBOX_IMAGE}:${TOOLBOX_VERSION}" || rc=$?
  [[ ${rc} -ne 0 ]] || return 0 # image present

  # A timed-out probe is inconclusive: say nothing rather than promise a
  # download that may not be happening. An `if`, not `&&` — under `set -e` a
  # short-circuited `&&` would abort the caller.
  if [[ ${rc} -eq 124 ]]; then
    return 0
  fi

  _warn "datasources — image ${TOOLBOX_IMAGE}:${TOOLBOX_VERSION} not present locally"
  _warn "  downloading now (this can take a few minutes) before the gateway starts"
}

# The datasource names a project opts into (a JSON array in its config). The one
# reader for every script that needs it: init wires a manifest per name, reload
# uses them to tell a source it cannot serve from one it simply does not serve.
_datasources_selected() {
  local project_dir="$1" config="${1}/.devbot.project.jsonc"
  [[ -f "${config}" ]] || return 0
  python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${config}" datasources 2>/dev/null |
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = None
print(" ".join(data) if isinstance(data, list) else "")
' 2>/dev/null || true
}

# Is a harness module turned off for this project? A manifest that init would not
# write belongs to a harness this project does not consume, and must not be held
# against a reload. Mirrors how the jetbrains module gates its manifests.
_datasources_harness_disabled() {
  local project_dir="$1" module="$2"
  _devbot_get_disabled_modules "${project_dir}" |
    jq -e --arg m "${module}" 'index($m) != null' >/dev/null 2>&1
}

# The datasource names the machine declares (keys of the global catalogue). A
# selected name absent from here is a typo: init warns about it, and no render
# can ever publish it.
_datasources_declared() {
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ -f "${config}" ]] || return 0
  python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${config}" datasources 2>/dev/null |
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = None
print(" ".join(data) if isinstance(data, dict) else "")
' 2>/dev/null || true
}

# ── Rendered state ───────────────────────────────────────────────────────────

# The gateway's container name, read from the template so compose.tpl.yml stays
# the single source of truth for it.
_gateway_container_name() {
  grep -m1 '^[[:space:]]*container_name:' "${MODULE_DIR}/compose.tpl.yml" | awk '{print $2}'
}

# True when the gateway container is up and serving. A stopped or absent
# container is "not running": docker inspect fails for both.
_gateway_running() {
  local container
  container="$(_gateway_container_name)"
  [[ -n "${container}" ]] || return 1
  [[ "$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null)" == "true" ]]
}

# The rendered catalogue holds one `kind: source` document per usable
# datasource. The empty catalogue is a single comment line, so a missing file
# and a placeholder both count as "nothing to serve".
_catalogue_has_sources() {
  [[ -f "${CONF_FILE}" ]] && grep -q '^kind: source' "${CONF_FILE}"
}

# The sidecar SERVICE names, read from the rendered compose rather than
# re-derived from the config: the answer must describe what is actually on disk,
# the same discipline `_catalogue_has_sources` follows. The gateway's own
# container is excluded — a service name is the datasource name.
_sidecar_services() {
  [[ -f "${COMPOSE_FILE}" ]] || return 0
  grep -oE 'container_name: dev-bot-datasources-[a-z0-9-]+' "${COMPOSE_FILE}" 2>/dev/null |
    sed 's/^container_name: dev-bot-datasources-//' |
    grep -vx 'mcp' || true
}

# The sidecar name -> port map, straight from the renderer that allocates the
# ports. The catalogue is filtered by the SAME static demand rule render.sh
# applies, so a manifest URL and the service's listener cannot drift. An
# unreadable catalogue degrades to "no sidecars" rather than aborting the
# caller — the toolbox path then applies exactly as before.
_datasources_sidecar_ports() {
  local project_dir="$1" global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc" ports=""
  [[ -f "${global_config}" ]] || { echo "{}"; return 0; }
  ports="$(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${global_config}" datasources 2>/dev/null |
    python3 "${MODULE_DIR}/demand.py" --static-filter "${global_config}" "${project_dir}" 2>/dev/null |
    python3 "${MODULE_DIR}/render_compose.py" --sidecar-ports 2>/dev/null)" || true
  # An explicit branch, not ${ports:-{}} — the closing brace of the expansion
  # would be read as a literal, appending a stray '}' to valid JSON.
  if [[ -z "${ports}" ]]; then
    echo "{}"
  else
    echo "${ports}"
  fi
}

# A poller left behind by an older dev-bot. Refresh is no longer backgrounded —
# datasources are evaluated once, and then only when a lifecycle script asks —
# so the only poller that can exist is one an older install started and never
# stopped. It is detached, so it would outlive the upgrade and keep rewriting
# the config under any render that follows: reap it before rendering.
_stop_legacy_poller() {
  local pid_file="${RUNTIME_DIR}/refresh.pid" previous
  [[ -f "${pid_file}" ]] || return 0
  previous="$(cat "${pid_file}")"
  if [[ -n "${previous}" ]]; then
    kill "${previous}" 2>/dev/null || true
  fi
  rm -f "${pid_file}"
}

# ── Lifecycle serialisation ──────────────────────────────────────────────────
#
# The render publishes tools.yaml + compose, and the entry points then start and
# probe containers against them. render.sh's own lock serialises the PUBLISH,
# but not the start/verify steps that follow: a concurrent `devbot up` could
# tear the gateway down (it stops it before rendering) between this render and
# its verification. One lock across the whole lifecycle run closes that window,
# so a reload can never verify a catalogue another run has already replaced.
LIFECYCLE_LOCK="${RUNTIME_DIR}/lifecycle.lock"

# Takes the lock on a descriptor of its own for the caller's lifetime — the
# kernel releases it on exit, including a kill. It must NOT be fd 200: up.sh
# takes the session-registry lock on 200 later in the same process, and reusing
# that descriptor would silently release this one. Returns non-zero when another
# run holds it past the cap; the caller decides whether that is fatal (reload,
# down) or a skip (boot).
_datasources_lock() {
  mkdir -p "$(dirname "${LIFECYCLE_LOCK}")" 2>/dev/null || return 1
  # A literal, module-owned descriptor (never 200): bash 3.2 has no dynamic fd
  # allocation, and eval'ing the path would execute shell syntax from a
  # DEV_BOT_ROOT name. Holding a second lock is what makes up.sh safe — it takes
  # the session-registry lock on 200 later in the same process.
  { exec 201>"${LIFECYCLE_LOCK}"; } 2>/dev/null || return 1
  _devbot_lock_acquire 201 "${DATASOURCES_LOCK_WAIT:-60}" \
    "datasources — another lifecycle run is in progress"
}

# ── Starting containers ──────────────────────────────────────────────────────

# Bring the gateway up on the rendered config. No --no-recreate (unlike the
# other gateways): the whole point of this container is the credentials it is
# handed, so rotating a value in .env must take effect on the next start.
# Prints the pre-pull notice itself; returns non-zero when compose fails.
_start_gateway() {
  _announce_missing_toolbox_image
  _gateway_compose
}

# Reconcile a gateway that is already running with the rendered compose. `up`
# recreates the container exactly when the rendered definition differs — a port
# from DATASOURCES_PORT, a changed env list — and is a no-op otherwise, so a
# healthy gateway is not restarted on every reload.
_update_gateway() {
  _gateway_compose
}

_gateway_compose() {
  (
    cd "${RUNTIME_DIR}" &&
      DEV_UID="${DEV_UID:-$(id -u)}" DEV_GID="${DEV_GID:-$(id -g)}" \
      TOOLBOX_IMAGE="${TOOLBOX_IMAGE}" TOOLBOX_VERSION="${TOOLBOX_VERSION}" \
        docker compose -f "${COMPOSE_FILE}" up -d --no-deps datasources-mcp
  ) || return 1
}

# Start one sidecar, on its own. `up --build` so a changed server or re-pinned
# package rebuilds here rather than silently reusing a stale image; the caller
# keeps a failure local to that source instead of letting it fail a shared unit.
_start_sidecar() {
  _sidecar_compose "$1" --build
}

# Reconcile a sidecar that is already running with the rendered service, without
# rebuilding its image. `up` recreates the container exactly when the rendered
# definition differs — a re-allocated port, a changed env list — and is a no-op
# otherwise, so a healthy sidecar is not restarted for nothing.
_update_sidecar() {
  _sidecar_compose "$1"
}

_sidecar_compose() {
  local service="$1"
  shift
  (
    cd "${RUNTIME_DIR}" &&
      DEV_UID="${DEV_UID:-$(id -u)}" DEV_GID="${DEV_GID:-$(id -g)}" \
      TOOLBOX_IMAGE="${TOOLBOX_IMAGE}" TOOLBOX_VERSION="${TOOLBOX_VERSION}" \
        docker compose -f "${COMPOSE_FILE}" up -d "$@" "${service}"
  ) || return 1
}

# ── Sidecar reconcile ────────────────────────────────────────────────────────
#
# A sidecar is rendered from the static project set but RUNS only while a live
# session wants it. up.sh applies this on boot; reconcile.sh applies it on a
# session's exit. Both converge to the same answer, derived from the live session
# registry, so they are last-writer-safe rather than lock-ordered.

# _running_sidecars — the sidecar names currently RUNNING. Read from docker
#   rather than from the rendered compose: a leftover started before a config
#   change may no longer be a compose service, and the reconcile must reclaim it
#   too. The gateway's own container is excluded — its name is not a datasource.
_running_sidecars() {
  docker ps --filter 'name=dev-bot-datasources-' --format '{{.Names}}' 2>/dev/null |
    sed 's/^dev-bot-datasources-//' | grep -vx 'mcp' || true
}

# _wanted_sidecars <project-dir>... — the sidecars those projects demand,
#   space-joined. A project with no config, or one that opted into no sidecar,
#   contributes nothing.
#
#   A FAILED catalogue read is not an empty catalogue: returning empty demand for
#   it would read as "stop everything" and take down sidecars live sessions are
#   using. It returns non-zero instead, and the caller leaves the running set
#   untouched — the discipline render.sh follows for the same reason.
_wanted_sidecars() {
  local catalogue
  if ! catalogue="$(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" \
    "${DEV_BOT_ROOT}/.devbot.global.jsonc" datasources 2>/dev/null)"; then
    return 1
  fi
  [[ -n "${catalogue}" ]] || catalogue="{}"
  printf '%s' "${catalogue}" | python3 "${MODULE_DIR}/demand.py" \
    --projects-names "$@" 2>/dev/null
}

# _reconcile_sidecars <wanted> — stop every running sidecar not in <wanted>.
_reconcile_sidecars() {
  local wanted="$1" svc
  for svc in $(_running_sidecars); do
    if ! _list_has_word "${svc}" "${wanted}"; then
      if docker stop "dev-bot-datasources-${svc}" >/dev/null 2>&1; then
        _ok "datasources — sidecar '${svc}' stopped (no live session wants it)"
      else
        _warn "datasources — could not stop sidecar '${svc}'"
      fi
    fi
  done
}

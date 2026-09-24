#!/usr/bin/env bash
# =============================================================================
# src/agentic/refactor/langs/php/plugin.sh
# PHP language plugin for the refactor tool.
#
# Subcommands:
#   meta    — plugin descriptor for the core's registry (lang, extensions, ops)
#   doctor  — report the resolved Rector engine, PHP version and container image
#   plan    — dry-run the requested refactor                        (T7)
#   apply   — perform the requested refactor                        (T7)
#
# Engine policy (ADR-4): the project's own `vendor/bin/rector` is preferred —
# right version, right vendor/autoload.php. A pinned scoped Composer install in
# the dev-bot scratch dir is the fallback. Never a phar: upstream abandoned that
# distribution because it broke on absolute paths and Docker mounts.
#
# Rector runs in the project's own PHP image when one can be detected, else the
# curated php:<version>-cli image. `--php-image` / REFACTOR_PHP_IMAGE override.
# =============================================================================

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFACTOR_DIR="$(cd "${PLUGIN_DIR}/../.." && pwd)"
# Overridable for tests, and to relocate the scratch install.
STORAGE_DIR="${REFACTOR_STORAGE_DIR:-${REFACTOR_DIR}/../../../storage/refactor}"

# The op table — including each op's rule class (`meta` and the `--only` value) —
# lives in ops.py, the single source of truth shared with the config renderer.
# Adding an op is one entry there, not edits across this file and the renderer.

# ── Engine resolution ─────────────────────────────────────────────────────────

# Rector version straight out of a composer.lock — deterministic, needs no PHP.
_rector_version_from_lock() {
  local lock="$1"
  [[ -f "${lock}" ]] || { echo "unknown"; return 0; }
  python3 - "${lock}" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("unknown"); raise SystemExit
for pkg in data.get("packages", []) + data.get("packages-dev", []):
    if pkg.get("name") == "rector/rector":
        print(pkg.get("version", "unknown")); raise SystemExit
print("unknown")
PY
}

# The project's declared PHP version: .php-version wins, then composer.json.
_project_php_version() {
  local project="$1"
  if [[ -f "${project}/.php-version" ]]; then
    tr -d '[:space:]' < "${project}/.php-version"
    return 0
  fi
  if [[ -f "${project}/composer.json" ]]; then
    python3 - "${project}/composer.json" <<'PY'
import json, re, sys
try:
    req = json.load(open(sys.argv[1])).get("require", {}).get("php", "")
except Exception:
    req = ""
m = re.search(r"(\d+\.\d+)", req or "")
print(m.group(1) if m else "")
PY
    return 0
  fi
  echo ""
}

# The scratch engine root — the directory CONTAINING vendor/bin/rector, so that
# <root>/vendor/bin/rector resolves once mounted.
_scratch_root() {
  local root="${STORAGE_DIR}/rector"
  [[ -d "${root}" ]] || return 1

  # The canonical layout created by `provision`.
  if [[ -x "${root}/vendor/bin/rector" ]]; then
    echo "${root}"
    return 0
  fi

  # A versioned/nested layout. Exclude a package's own nested vendor.
  local bin
  bin="$(find "${root}" -maxdepth 6 -type f -path '*/vendor/bin/rector' \
    ! -path '*/vendor/rector/*' 2>/dev/null | sort | head -1 || true)"
  [[ -n "${bin}" ]] || return 1
  echo "${bin%/vendor/bin/rector}"
}

# Resolve the engine. Echoes tab-separated: <via> <path> <version>.
# `via` is "project" or "scratch"; for scratch, <path> points into STORAGE_DIR.
_resolve_engine() {
  local project="$1"

  # 1. The project's own Rector.
  if [[ -x "${project}/vendor/bin/rector" ]]; then
    printf 'project\t%s\t%s\n' \
      "${project}/vendor/bin/rector" \
      "$(_rector_version_from_lock "${project}/composer.lock")"
    return 0
  fi

  # 2. A pinned scoped install in the scratch dir.
  local root
  if root="$(_scratch_root)"; then
    printf 'scratch\t%s\t%s\n' \
      "${root}/vendor/bin/rector" \
      "$(_rector_version_from_lock "${root}/composer.lock")"
    return 0
  fi

  return 1
}

# ── Container runner ──────────────────────────────────────────────────────────

# The Rector rule classes an op registers, in step order.
_rules_for_op() {
  python3 "${PLUGIN_DIR}/ops.py" rules "$1"
}

# An op's first rule — used for the doctor's example command.
_first_rule() {
  python3 "${PLUGIN_DIR}/ops.py" rules "$1" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)[0])'
}

# Resolve the PHP container image.
# Precedence: explicit > REFACTOR_PHP_IMAGE > the project's compose image >
# php:<php-version>-cli
_resolve_image() {
  local project="$1" explicit="${2:-}"

  if [[ -n "${explicit}" ]]; then echo "${explicit}"; return 0; fi
  if [[ -n "${REFACTOR_PHP_IMAGE:-}" ]]; then echo "${REFACTOR_PHP_IMAGE}"; return 0; fi

  local compose="" f
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${project}/${f}" ]]; then compose="${project}/${f}"; break; fi
  done
  if [[ -n "${compose}" ]]; then
    local img
    img="$(python3 - "${compose}" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"^\s*image:\s*[\"']?([^\"'\s]+)", text, re.M)
print(m.group(1) if m else "")
PY
)"
    if [[ -n "${img}" ]]; then echo "${img}"; return 0; fi
  fi

  local ver
  ver="$(_project_php_version "${project}")"
  if [[ -n "${ver}" ]]; then echo "php:${ver}-cli"; else echo "php:cli"; fi
}

# Build the `docker run` argv for a Rector run and print it as a JSON array.
#
# args: <via> <project> <image> <config-host-path> <dry> <op> [paths...]
#
# The project is mounted at /app; a scratch engine is mounted at /refactor-engine.
# The generated config is mounted read-only at /refactor/rector.php. Since the
# config registers exactly one rule, `--only` is a belt-and-braces guarantee that
# nothing else in the run can change code.
_build_argv() {
  local via="$1" project="$2" image="$3" config="$4" dry="$5" rule="$6"

  local engine_host="${project}" engine_in_container="/app"
  if [[ "${via}" == "scratch" ]]; then
    engine_host="$(_scratch_root)"
    engine_in_container="/refactor-engine"
  fi

  python3 - "${project}" "${image}" "${engine_host}" "${engine_in_container}" \
    "${config}" "${dry}" "${rule}" "${PLUGIN_DIR}/rules" <<'PY'
import json, sys
project, image, engine_host, engine_in_container, config, dry, rule, rules_dir = sys.argv[1:]

# A dry run must not be able to write, so the project is mounted read-only then;
# Rector's cache lives in the container, not the project.
mount_suffix = "" if dry == "false" else ":ro"
argv = ["docker", "run", "--rm",
        "-v", f"{project}:/app{mount_suffix}",
        "-v", f"{config}:/refactor/rector.php:ro",
        "-v", f"{rules_dir}:/refactor/rules:ro"]
if engine_in_container != "/app":
    argv += ["-v", f"{engine_host}:{engine_in_container}"]
argv += ["-w", "/app", image,
         "php", f"{engine_in_container}/vendor/bin/rector", "process",
         "--config", "/refactor/rector.php"]
argv += ["--only", rule]
argv += ["--clear-cache", "--no-progress-bar", "--output-format=json"]
if dry == "true":
    argv.append("--dry-run")
print(json.dumps(argv))
PY
}

# ── Subcommands ───────────────────────────────────────────────────────────────

cmd_meta() {
  python3 "${PLUGIN_DIR}/ops.py" meta
}

cmd_doctor() {
  local project="${PWD}" image="" want_command="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --image)   image="$2"; shift 2 ;;
      --command) want_command="true"; shift ;;
      *) shift ;;
    esac
  done

  if [[ ! -d "${project}" ]]; then
    printf '{"ok":false,"error":"project directory not found: %s"}\n' "${project}"
    exit 1
  fi

  local resolved_image
  resolved_image="$(_resolve_image "${project}" "${image}")"

  local engine
  if ! engine="$(_resolve_engine "${project}")"; then
    python3 - "${project}" "${resolved_image}" <<'PY'
import json, sys
project, image = sys.argv[1:3]
print(json.dumps({
    "ok": False,
    "lang": "php",
    "project": project,
    "image": image,
    "error": "no Rector engine found",
    "hint": "add rector/rector to the project, or provision the scratch install",
}))
PY
    exit 1
  fi

  local via path version
  IFS=$'\t' read -r via path version <<<"${engine}"

  local command=""
  if [[ "${want_command}" == "true" ]]; then
    command="$(_build_argv "${via}" "${project}" "${resolved_image}" \
      "/tmp/rector.php" "true" "$(_first_rule rename-method)")"
  fi

  python3 - "${project}" "${via}" "${path}" "${version}" \
    "$(_project_php_version "${project}")" "${resolved_image}" "${command}" <<'PY'
import json, sys
project, via, path, version, php_version, image, command = sys.argv[1:8]
out = {
    "ok": True,
    "lang": "php",
    "project": project,
    "php_version": php_version or None,
    "image": image,
    "engine": {"via": via, "path": path, "version": version},
}
if command:
    out["command"] = json.loads(command)
print(json.dumps(out))
PY
}

# Provision a pinned, scoped Rector into the scratch dir. Composer is the official
# distribution channel — there is no official phar.
cmd_provision() {
  local version="${1:-^2.6}"
  local dir="${STORAGE_DIR}/rector"

  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is required to provision the scratch Rector" >&2
    exit 1
  fi

  mkdir -p "${dir}"
  if ! docker run --rm -v "${dir}:/app" -w /app composer:2 \
    require "rector/rector:${version}" --no-interaction --no-progress -q >&2; then
    echo "ERROR: composer could not install rector/rector:${version}" >&2
    exit 1
  fi

  printf '{"ok":true,"scratch":"%s","version":"%s"}\n' "${dir}" "${version}"
}

# Run a refactor: render the single-rule config, execute Rector, map its JSON
# output onto the plugin response contract.
#
#   $1    = plan (dry-run) | apply
#   stdin = the request JSON
cmd_run() {
  local mode="$1" request op klass from to req_image
  request="$(cat)"

  # Split on the ASCII unit separator, not a tab: tab counts as IFS whitespace,
  # so bash would collapse the empty `class` field rename-class legitimately has.
  IFS=$'\x1f' read -r op klass from to req_image < <(printf '%s' "${request}" | python3 -c '
import json, sys
r = json.load(sys.stdin)
print("\x1f".join([str(r.get("op") or ""), str(r.get("class") or ""),
                   str(r.get("from") or ""), str(r.get("to") or ""),
                   str(r.get("image") or "")]))')

  if [[ -z "${op}" ]]; then
    echo '{"ok":false,"error":"op is required"}' >&2
    exit 1
  fi

  local project="${REFACTOR_PROJECT:-${PWD}}"

  # Scope Rector to the project's source roots. `app/` (Laravel) and `src/`
  # (library) are mutually exclusive, so at most one exists. Scoping at the mount
  # root instead would descend into vendor/ — which Rector does not exclude by
  # default, and would happily rewrite.
  local -a roots=()
  local d
  for d in app src; do
    [[ -d "${project}/${d}" ]] && roots+=("/app/${d}")
  done
  if [[ ${#roots[@]} -eq 0 ]]; then
    echo '{"ok":false,"error":"no source root found — expected app/ or src/ at the project root"}' >&2
    exit 1
  fi
  local scope_json
  scope_json="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${roots[@]}")"
  # Carry the scope and the host project dir into the request: the renderer needs
  # the project to derive a namespace when none was given.
  request="$(SCOPE="${scope_json}" PROJECT="${project}" python3 -c '
import json, os, sys
r = json.load(sys.stdin)
r["scope"] = json.loads(os.environ["SCOPE"])
r["project"] = os.environ["PROJECT"]
print(json.dumps(r))' <<<"${request}")"

  local engine
  if ! engine="$(_resolve_engine "${project}")"; then
    echo '{"ok":false,"error":"no Rector engine found","hint":"run: plugin.sh provision"}' >&2
    exit 1
  fi
  local via _path version
  IFS=$'\t' read -r via _path version <<<"${engine}"

  local image cfg
  image="$(_resolve_image "${project}" "${req_image}")"
  # A malformed ref would go straight to docker as an argument.
  if [[ -z "${image}" || "${image}" =~ [[:space:]] ]]; then
    echo "ERROR: invalid container image reference '${image}'" >&2
    exit 1
  fi
  local dry="true"
  [[ "${mode}" == "apply" ]] && dry="false"

  # Resolve the file move BEFORE the rules run: afterwards the old declaration
  # name is gone from the file, so it can no longer be found by it.
  local move_json mv_from="" mv_to=""
  move_json="$(printf '%s' "${request}" | python3 "${PLUGIN_DIR}/ops.py" move-target 2>/dev/null || true)"
  local mv_from_rel="" mv_to_rel=""
  if [[ -n "${move_json}" ]]; then
    mv_from="$(printf '%s' "${move_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["from"])')"
    mv_to="$(printf '%s' "${move_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["to"])')"
    mv_from_rel="${mv_from#"${project}"/}"
    mv_to_rel="${mv_to#"${project}"/}"
  fi

  # One Rector run per rule. A single config carrying both a usages rule and the
  # declaration rule does not compose: the declaration rename invalidates the
  # reflection the usages rule resolves calls through, so the calls silently stay
  # put. One rule per run also matches the --only posture used everywhere else.
  local -a rules
  mapfile -t rules < <(python3 "${PLUGIN_DIR}/ops.py" rules "${op}" |
    python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)))')

  local outfile errfile rcfile rc step
  outfile="$(mktemp)"
  errfile="$(mktemp)"
  rcfile="$(mktemp)"

  for ((step = 0; step < ${#rules[@]}; step++)); do
    local cfg step_out step_err
    cfg="$(mktemp)"
    step_out="$(mktemp)"
    step_err="$(mktemp)"

    if ! printf '%s' "${request}" | python3 "${PLUGIN_DIR}/ops.py" render "${step}" > "${cfg}"; then
      rm -f "${cfg}" "${step_out}" "${step_err}" "${outfile}" "${errfile}" "${rcfile}"
      echo '{"ok":false,"error":"could not render the Rector config"}' >&2
      exit 1
    fi

    local -a cmd
    mapfile -d '' -t cmd < <(_build_argv "${via}" "${project}" "${image}" "${cfg}" "${dry}" "${rules[$step]}" |
      python3 -c 'import json,sys; sys.stdout.write("\0".join(json.load(sys.stdin)))')

    set +e
    "${cmd[@]}" >"${step_out}" 2>"${step_err}"
    rc=$?
    set -e
    rm -f "${cfg}"

    cat "${step_out}" >> "${outfile}"
    printf '\n' >> "${outfile}"
    cat "${step_err}" >> "${errfile}"
    printf '%s\n' "${rc}" >> "${rcfile}"
    rm -f "${step_out}" "${step_err}"
  done

  # Relocate the file resolved before the rules ran. Rector rewrites the
  # declaration and the references but moves no files, and a PSR-4 autoloader
  # keys on the file name — leaving it produces a class that no longer loads.
  local move_note=""
  if [[ -n "${mv_to}" ]]; then
    if [[ "${mode}" == "apply" ]]; then
      if mv "${mv_from}" "${mv_to}"; then
        move_note="moved $(basename "${mv_from}") -> $(basename "${mv_to}")"
      else
        rm -f "${outfile}" "${errfile}" "${rcfile}"
        echo "ERROR: could not move ${mv_from} to ${mv_to}" >&2
        exit 1
      fi
    else
      move_note="would move $(basename "${mv_from}") -> $(basename "${mv_to}")"
    fi
  fi

  REFACTOR_MOVE_NOTE="${move_note}" REFACTOR_MOVE_FROM_REL="${mv_from_rel}" REFACTOR_MOVE_TO_REL="${mv_to_rel}" python3 - "${outfile}" "${errfile}" "${rcfile}" "${via}" "${version}" "${mode}" "${from}" "${to}" <<'PY'
import json, os, sys

outfile, errfile, rcfile, via, version, mode, old, new = sys.argv[1:9]

def _read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except Exception:
        return ""

raw = _read(outfile)
err = _read(errfile)
rcs = [int(line) for line in _read(rcfile).split()]

warnings = [line for line in err.splitlines() if line.strip()]

# Each step printed one JSON document; parse them in sequence.
decoder = json.JSONDecoder()
docs = []
index = 0
while index < len(raw):
    while index < len(raw) and raw[index] in " \t\r\n":
        index += 1
    if index >= len(raw):
        break
    try:
        doc, index = decoder.raw_decode(raw, index)
    except Exception as exc:
        print(json.dumps({"ok": False, "error": "unparseable Rector output: %s" % exc, "warnings": warnings}))
        raise SystemExit
    docs.append(doc)

if not docs:
    print(json.dumps({"ok": False, "error": "no output from Rector", "warnings": warnings}))
    raise SystemExit

# Rector reports config failures as stdout {"fatal_errors":[...]} with exit 1.
# Without this the agent sees only "exited 1 with 0 error(s)", which says nothing.
fatal = [str(message) for doc in docs for message in (doc.get("fatal_errors") or [])]
if fatal:
    print(json.dumps({
        "ok": False,
        "error": "Rector could not build its config: %s" % "; ".join(fatal),
        "warnings": warnings,
    }))
    raise SystemExit

files = []
errors = 0
for doc in docs:
    for path in doc.get("changed_files") or []:
        if path not in files:
            files.append(path)
    errors += (doc.get("totals") or {}).get("errors") or 0

# Rector exits 2 when --dry-run finds changes to make (0 = nothing to do,
# 1 = error). A plan that found changes is a success, not a failure.
hard_fail = any(rc not in (0, 2) for rc in rcs)
ok = not hard_fail and errors == 0
result = {
    "ok": ok,
    "engine": "rector %s (%s)" % (version, via),
    "applied": mode == "apply",
    "summary": "%s %s -> %s in %d file(s)" % (
        "Renamed" if mode == "apply" else "Would rename", old, new, len(files)),
    "files": files,
    # On success Rector's stderr is noise (docker pull progress, notices) that
    # says nothing the agent can act on. On failure it is the diagnosis.
    "warnings": [] if ok else warnings,
}
if not ok:
    result["error"] = "rector exit codes %s with %d error(s)" % (rcs, errors)

move_note = os.environ.get("REFACTOR_MOVE_NOTE", "").strip()
if move_note:
    result["file_move"] = move_note
    # Report the file under its new path — the reported old one no longer exists.
    old_rel = os.environ.get("REFACTOR_MOVE_FROM_REL", "").strip()
    new_rel = os.environ.get("REFACTOR_MOVE_TO_REL", "").strip()
    if new_rel and old_rel in files:
        files[files.index(old_rel)] = new_rel

print(json.dumps(result))
PY
  rm -f "${outfile}" "${errfile}" "${rcfile}"
}

case "${1:-}" in
  meta)      cmd_meta ;;
  doctor)    shift; cmd_doctor "$@" ;;
  provision) shift; cmd_provision "$@" ;;
  plan)      shift; cmd_run plan ;;
  apply)     shift; cmd_run apply ;;
  *)
    echo "ERROR: php plugin: unsupported subcommand '${1:-}' (expected meta|doctor|plan|apply)" >&2
    exit 1
    ;;
esac

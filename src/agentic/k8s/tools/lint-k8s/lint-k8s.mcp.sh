#!/usr/bin/env bash
# ---
# description: Audit Kubernetes, Kustomize, or Helm manifests using kubeconform (schema validation) and kube-linter (best practices)
# ---
# =============================================================================
# src/agentic/k8s/tools/lint-k8s/lint-k8s.mcp.sh
# Audit Kubernetes, Kustomize, or Helm manifests using kubeconform
# (schema validation) and kube-linter (best practices).
#
# Usage:
#   lint-k8s.mcp.sh <path>                    # file or directory
#   lint-k8s.mcp.sh --json <path>             # JSON output
#   lint-k8s.mcp.sh --schema <location> <path> # kubeconform schema override
#
# Parameters:
# - path (string, required): file or directory path containing YAML/YML manifests
# - schema (string, optional): kubeconform schema location override (e.g., 'default', 'kubernetes')
# - format (string, optional): 'text' (default), 'json' or 'markdown'
# - changed (flag): lint only manifests changed against --base (default HEAD)
#
# CRDs and other kinds without a bundled schema are skipped, not failed: they
# were the dominant source of false errors on real repositories.
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"lint-k8s","description":"Audit Kubernetes, Kustomize, or Helm manifests using kubeconform (schema validation) and kube-linter (best practices). Skips kinds with no bundled schema (CRDs) unless --schema is explicit.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: <path> [--json] [--format text|json|markdown] [--schema <location>] [--changed] [--base <ref>]"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

# ── Find binary ──────────────────────────────────────────────────────────────

_find_bin() {
  local name="$1"
  for dir in "$HOME/.local/bin" "/usr/local/bin" "/usr/bin"; do
    [[ -x "$dir/$name" ]] && echo "$dir/$name" && return 0
  done
  command -v "$name" 2>/dev/null || true
}

# _run_with_timeout <seconds> <cmd...>
# `timeout` is GNU coreutils and is not available on macOS by default — fall
# back to `gtimeout` (coreutils) and finally to running without a timeout.
_run_with_timeout() {
  local seconds="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
  else
    "$@"
  fi
}

# ── Gather manifests ─────────────────────────────────────────────────────────

# True when the file looks like a Kubernetes manifest — it contains an
# `apiVersion` key and a `kind` key (tolerating JSON's quoted keys). Directory
# sweeps gather only manifest-looking files; anything else (config files,
# editor/tool caches) would otherwise make kubeconform report a "missing
# 'kind' key" error for every non-manifest file (audit-48 N5). An explicitly
# passed file is still linted as-is — a mistaken explicit target stays loud.
_is_manifest() {
  local file="$1"
  grep -Eq '(^|[^[:alnum:]_-])apiVersion"?[[:space:]]*:' "$file" 2>/dev/null \
    && grep -Eq '(^|[^[:alnum:]_-])kind"?[[:space:]]*:' "$file" 2>/dev/null
}

_gather_files() {
  local path="$1"
  if [[ -f "$path" ]]; then
    [[ "$path" =~ \.(ya?ml|json)$ ]] && echo "$path"
  elif [[ -d "$path" ]]; then
    local f
    while IFS= read -r f; do
      [[ -n "$f" ]] && _is_manifest "$f" && echo "$f"
    done < <(find "$path" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) \
      ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/.terraform/*" 2>/dev/null)
  fi
}

# ── Parse args ───────────────────────────────────────────────────────────────

FORMAT="text"
SCHEMA=""
CHANGED=false
BASE="HEAD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json|-j)   FORMAT="json"; shift ;;
    --markdown)  FORMAT="markdown"; shift ;;
    --schema|-s) SCHEMA="$2"; shift 2 ;;
    --changed)   CHANGED=true; shift ;;
    --base)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --base requires a git ref" >&2
        exit 2
      fi
      BASE="$2"; shift 2
      ;;
    --base=*)    BASE="${1#--base=}"; shift ;;
    --*)         shift ;; # unknown flags passed through
    -*)          shift ;;
    *)           if [[ -z "${TARGET:-}" ]]; then TARGET="$1"; fi; shift ;;
  esac
done
TARGET="${TARGET:-.}"

if [[ ! -e "$TARGET" ]]; then
  echo "lint-k8s: path not found: $TARGET" >&2
  exit 1
fi

# ── Find tools ───────────────────────────────────────────────────────────────

KUBECONFORM=$(_find_bin "kubeconform")
KUBELINTER=$(_find_bin "kube-linter")

if [[ -z "$KUBECONFORM" || -z "$KUBELINTER" ]]; then
  echo "lint-k8s: kubeconform or kube-linter not found. Install them:" >&2
  echo "  brew install kubeconform kube-linter" >&2
  exit 1
fi

# kubeconform args shared by both output modes. The --schema CLI flag maps to
# kubeconform's -schema-location (shellcheck SC2034: SCHEMA was parsed above
# but never reached kubeconform).
# Missing schema is the normal state for CRDs (ArgoCD Applications,
# ExternalSecrets, ...). Failing on it buried the schema the repo actually has.
# An explicit --schema is different: the operator named a schema set, so a
# manifest that cannot resolve against it stays loud.
KC_ARGS=(-summary)
if [[ -n "$SCHEMA" ]]; then
  KC_ARGS+=(-schema-location "$SCHEMA")
else
  KC_ARGS+=(-ignore-missing-schemas)
fi

# ── Run linters ──────────────────────────────────────────────────────────────

FILES=()
while IFS= read -r f; do
  [[ -n "$f" ]] && FILES+=("$f")
done < <(_gather_files "$TARGET")

if [[ "$CHANGED" == "true" ]]; then
  # Resolve the repository from the target (a file targets its directory).
  repo_dir="$TARGET"
  [[ -f "$repo_dir" ]] && repo_dir="$(dirname "$repo_dir")"
  repo_root="$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$repo_root" ]]; then
    echo "ERROR: --changed requires a target inside a git repository" >&2
    exit 2
  fi
  if [[ "$BASE" == -* ]] || ! git -C "$repo_root" rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
    echo "ERROR: --base does not name a commit: $BASE" >&2
    exit 2
  fi
  changed_list="$(mktemp)"
  {
    git -C "$repo_root" -c core.quotepath=false diff --name-only --diff-filter=ACMRT "$BASE" -- 2>/dev/null || true
    git -C "$repo_root" -c core.quotepath=false ls-files --others --exclude-standard 2>/dev/null || true
  } | sort -u > "$changed_list"
  filtered=()
  for f in "${FILES[@]}"; do
    f_abs="$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")"
    rel="${f_abs#"$repo_root"/}"
    rel="${rel#./}"
    while IFS= read -r changed; do
      [[ -z "$changed" ]] && continue
      if [[ "$rel" == "$changed" ]]; then
        filtered+=("$f")
        break
      fi
    done < "$changed_list"
  done
  rm -f "$changed_list"
  FILES=("${filtered[@]}")
  if [[ ${#FILES[@]} -eq 0 ]]; then
    if [[ "$FORMAT" == "json" ]]; then
      printf '{"path":"%s","files":0,"changed":true,"kubeconform":{"valid":true,"summary":"all valid"},"kubelinter":{"report":{"Reports":[],"Summary":{"TotalViolations":0,"FilesWithViolations":0,"TotalFilesScanned":0}}}}\n' "$TARGET"
    else
      echo "lint-k8s: no changed Kubernetes manifests against $BASE in $TARGET"
    fi
    exit 0
  fi
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "lint-k8s: no Kubernetes manifests found in $TARGET (sweeps gather only YAML/JSON files containing an apiVersion and a kind key)" >&2
  exit 1
fi

if [[ "$FORMAT" == "json" ]]; then
  # JSON output
  echo "{"
  echo '  "path": "'"$TARGET"'",'
  echo '  "files": '"${#FILES[@]}"','
  echo '  "changed": '"$CHANGED"','
  echo '  "kubeconform": {'

  KC_VALID=true
  KC_OUTPUT=""
  for f in "${FILES[@]}"; do
    result=$(_run_with_timeout 30 "$KUBECONFORM" "${KC_ARGS[@]}" "$f" 2>&1) || { KC_VALID=false; KC_OUTPUT+="$result"$'\n'; }
  done
  if [[ -z "$KC_OUTPUT" ]]; then
    KC_SUMMARY="all valid"
  else
    KC_SUMMARY="found issues"
  fi
  echo '    "valid": '$KC_VALID','
  echo '    "summary": "'"$KC_SUMMARY"'"'
  echo '  },'
  echo '  "kubelinter": {'

  KL_OUTPUT=$("$KUBELINTER" lint "${FILES[@]}" --format json 2>/dev/null || echo '{"Reports":[],"Summary":{"TotalViolations":0,"FilesWithViolations":0,"TotalFilesScanned":0}}')
  echo '    "report": '"$KL_OUTPUT"
  echo '  }'
  echo "}"
else
  # Text/markdown output
  manifest_note=""
  [[ "$CHANGED" == "true" ]] && manifest_note=" changed against $BASE"
  echo "lint-k8s: ${#FILES[@]} manifest(s)${manifest_note}"
  if [[ "$FORMAT" == "markdown" ]]; then
    echo "## kubeconform"
    echo '```'
  else
    echo "--- kubeconform ---"
  fi

  KC_ERRORS=0
  for f in "${FILES[@]}"; do
    "$KUBECONFORM" "${KC_ARGS[@]}" "$f" 2>&1 || { KC_ERRORS=$((KC_ERRORS + 1)); }
  done
  [[ $KC_ERRORS -eq 0 ]] && echo "All valid"

  if [[ "$FORMAT" == "markdown" ]]; then
    echo '```'
    echo "## kube-linter"
    echo '```'
  else
    echo "--- kube-linter ---"
  fi

  "$KUBELINTER" lint "${FILES[@]}" 2>&1 || true

  if [[ "$FORMAT" == "markdown" ]]; then
    echo '```'
  fi
fi

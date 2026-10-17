#!/usr/bin/env bash
# ---
# description: Display directory structure as a tree. Accepts one or more paths. Returns output in markdown or plain text.
# ---
# =============================================================================
# src/agentic/tree/tools/tree.mcp.sh
# Run `tree` on directories and return output (markdown or plain text).
#
# Usage:
#   tree.mcp.sh [--markdown|--json|--format <fmt>] [--max-depth <n>|-L <n>] <dir> [<dir> ...]
#
# Accepts single path, JSON array, comma-separated, or space-separated paths.
#
# Parameters:
# - paths (string, required): directory path or multiple paths. Accepts: single path 'src', JSON array '["src","lib"]', comma-separated 'src,lib', or space-separated 'src lib'
# - format (string, optional): 'markdown' (default) or 'json'
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"tree","description":"Display directory structure as a tree. Accepts one or more paths. Skips VCS/dependency/cache directories and limits depth to 3 by default; pass --all to include hidden entries and --exclude <pattern> to add exclusions.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: [--markdown|--json|--format <fmt>] [--max-depth <n>|-L <n>] [--all] [--exclude <pattern>] <dir> [<dir> ...]"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

# ── Resolve multiple path formats into a flat list ────────────────────────────
_resolve_paths() {
  local raw="$1"
  # Try JSON array first
  if [[ "$raw" == '['* ]] && command -v jq &>/dev/null && echo "$raw" | jq -r '.[]' 2>/dev/null; then
    return
  fi
  # Fallback: comma-separated or single path
  echo "$raw" | tr ',' '\n' | while IFS= read -r p; do
    [[ -n "$p" ]] && echo "$p"
  done
}

# ── Parse args ───────────────────────────────────────────────────────────────
FMT="markdown"
MAX_DEPTH="3"
ALL=false
EXCLUDE_EXTRA=""
# These are the noise directories every repository has. They are excluded by
# default so a repository-wide map stays readable; --all opts back in.
DEFAULT_EXCLUDES='.git|.hg|.svn|node_modules|vendor|__pycache__|.venv|graphify-out|.cache|.pytest_cache'
PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FMT="json"; shift ;;
    --markdown) FMT="markdown"; shift ;;
    --all|-a) ALL=true; shift ;;
    --exclude)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Option --exclude requires a pattern" >&2
        echo "Usage: tree.mcp.sh [--markdown|--json|--format <fmt>] [--max-depth <n>|-L <n>] [--all] [--exclude <pattern>] <dir> [<dir> ...]" >&2
        exit 1
      fi
      EXCLUDE_EXTRA="$2"; shift 2
      ;;
    --exclude=*)
      EXCLUDE_EXTRA="${1#--exclude=}"
      if [[ -z "$EXCLUDE_EXTRA" ]]; then
        echo "Option --exclude requires a pattern" >&2
        echo "Usage: tree.mcp.sh [--markdown|--json|--format <fmt>] [--max-depth <n>|-L <n>] [--all] [--exclude <pattern>] <dir> [<dir> ...]" >&2
        exit 1
      fi
      shift
      ;;
    --format) FMT="$2"; shift 2 ;;
    --format=*) FMT="${1#--format=}"; shift ;;
    --max-depth|-L)
      # audit-28 NOTE-4: real `tree` supports -L level; accept --max-depth N
      # and -L N and pass through as -L N so callers can limit output depth.
      if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
        echo "Option $1 requires a positive integer value" >&2
        echo "Usage: tree.mcp.sh [--markdown|--json|--format <fmt>] [--max-depth <n>|-L <n>] [--all] [--exclude <pattern>] <dir> [<dir> ...]" >&2
        exit 1
      fi
      MAX_DEPTH="$2"; shift 2
      ;;
    --max-depth=*)
      local_value="${1#--max-depth=}"
      if [[ ! "$local_value" =~ ^[1-9][0-9]*$ ]]; then
        echo "Option --max-depth requires a positive integer value" >&2
        echo "Usage: tree.mcp.sh [--markdown|--json|--format <fmt>] [--max-depth <n>|-L <n>] [--all] [--exclude <pattern>] <dir> [<dir> ...]" >&2
        exit 1
      fi
      MAX_DEPTH="$local_value"; shift
      ;;
    --*)
      # Unknown flag (e.g. --depth): reject with a usage error instead of
      # silently treating it as a path (audit-26 NOTE-4).
      echo "Unknown option: $1" >&2
      echo "Usage: tree.mcp.sh [--markdown|--json|--format <fmt>] [--max-depth <n>|-L <n>] [--all] [--exclude <pattern>] <dir> [<dir> ...]" >&2
      exit 1
      ;;
    *) PATHS+=("$1"); shift ;;
  esac
done

if [[ ${#PATHS[@]} -eq 0 ]]; then
  echo "Usage: tree.mcp.sh [--markdown|--json|--format <fmt>] [--max-depth <n>|-L <n>] [--all] [--exclude <pattern>] <dir> [<dir> ...]" >&2
  exit 1
fi

# ── Resolve and validate paths ───────────────────────────────────────────────
RESOLVED=()
SKIPPED=()
for p in "${PATHS[@]}"; do
  while IFS= read -r sub; do
    [[ -z "$sub" ]] && continue
    abs="$(cd -P "$(dirname "$sub")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$sub")")" || abs=""
    if [[ -n "$abs" && -e "$abs" ]]; then
      RESOLVED+=("$abs")
    else
      SKIPPED+=("$sub")
    fi
  done < <(_resolve_paths "$p")
done

if [[ ${#RESOLVED[@]} -eq 0 ]]; then
  echo "tree: none of the given paths exist: ${PATHS[*]}" >&2
  exit 1
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "> skipped non-existent paths: ${SKIPPED[*]}"
  echo
fi

# ── Run tree ─────────────────────────────────────────────────────────────────
OUTPUT=""
SEPARATOR=""
TREE_ARGS=(-L "$MAX_DEPTH" --dirsfirst --charset=ASCII)
if [[ "$ALL" == "true" ]]; then
  TREE_ARGS+=(-a)
  [[ -n "$EXCLUDE_EXTRA" ]] && TREE_ARGS+=(-I "$EXCLUDE_EXTRA")
else
  exclude_pattern="$DEFAULT_EXCLUDES"
  [[ -n "$EXCLUDE_EXTRA" ]] && exclude_pattern="${exclude_pattern}|${EXCLUDE_EXTRA}"
  TREE_ARGS+=(-I "$exclude_pattern")
fi
for ((i = 0; i < ${#RESOLVED[@]}; i++)); do
  dir="${RESOLVED[$i]}"

  if ! stdout=$(tree "${TREE_ARGS[@]}" "$dir" 2>/dev/null); then
    echo "tree failed for $dir" >&2
    exit 1
  fi

  if [[ "$FMT" == "markdown" ]]; then
    OUTPUT+="${SEPARATOR}## Tree structure\n\n\`\`\`text\n${stdout}\n\`\`\`\n"
  else
    OUTPUT+="${SEPARATOR}${stdout}\n"
  fi
  SEPARATOR="\n"
done

echo -e "$OUTPUT"

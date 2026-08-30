#!/usr/bin/env bash
# =============================================================================
# src/tools/devbot-cli/completion.sh
# Bash completion for the `devbot` CLI.
#
# Installed by src/tools/devbot-cli/install.sh.
#
# Usage (sourced by bash-completion framework):
#   complete -F _devbot_complete devbot
# =============================================================================

if ! type -t _init_completion >/dev/null 2>&1 && ! type -t compgen >/dev/null 2>&1; then
  return 0
fi

_devbot_complete() {
  local cur prev words cword
  if type -t _init_completion >/dev/null 2>&1; then
    _init_completion || return
  else
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
  fi

  # ── Level 1 commands ──────────────────────────────────────────────────────
  local -a L1_COMMANDS=(help install update models tool init)

  # ── Determine which word index we're completing ───────────────────────────
  local word_idx=${COMP_CWORD}
  local cmd="${COMP_WORDS[1]:-}"

  # ── Level 1: no command yet ───────────────────────────────────────────────
  if [[ ${word_idx} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "${L1_COMMANDS[*]}" -- "${cur}"))
    return 0
  fi

  # ── Level 2+: dispatch by command ─────────────────────────────────────────
  case "${cmd}" in

    # ── Commands with no subcommands ────────────────────────────────────────
    help|install|update)
      COMPREPLY=()
      return 0
      ;;

    # ── models: subcommands ─────────────────────────────────────────────────
    models)
      local subcmd="${COMP_WORDS[2]:-}"
      local sub_idx=$((word_idx - 1))

      if [[ ${sub_idx} -eq 1 ]]; then
        local -a LM_SUBCMDS=(pull list-local list-remote remove)
        COMPREPLY=($(compgen -W "${LM_SUBCMDS[*]}" -- "${cur}"))
        return 0
      fi

      case "${subcmd}" in
        pull|remove)
          if [[ "${subcmd}" == "remove" ]]; then
            _devbot_complete_local_models
          else
            local -a COMMON_MODELS=(
              llama3.2:3b llama3.2:1b llama3.3:70b
              qwen2.5:7b qwen2.5:32b qwen2.5-coder:7b qwen2.5-coder:32b
              deepseek-r1:8b deepseek-r1:14b deepseek-r1:32b
              mistral:7b mixtral:8x7b
              codellama:7b codellama:13b codellama:34b
              nomic-embed-text
            )
            COMPREPLY=($(compgen -W "${COMMON_MODELS[*]}" -- "${cur}"))
          fi
          return 0
          ;;
        list-local|list-remote)
          COMPREPLY=()
          return 0
          ;;
      esac
      ;;

    # ── tool: dynamic tool names ────────────────────────────────────────────
    tool)
      local sub_idx=$((word_idx - 1))
      if [[ ${sub_idx} -eq 1 ]]; then
        _devbot_complete_tool_names
        return 0
      fi
      COMPREPLY=()
      return 0
      ;;

    # ── init: directory path ────────────────────────────────────────────────
    init)
      COMPREPLY=($(compgen -A directory -- "${cur}"))
      return 0
      ;;

    *)
      COMPREPLY=()
      return 0
      ;;
  esac
}

# ── Helper: complete tool names from src/agentic/ ──────────────────────
_devbot_complete_tool_names() {
  local root="${DEV_BOT_ROOT:-${PWD}}"
  local names=()
  while IFS= read -r -d '' sh; do
    local base
    base="$(basename "${sh}" .sh)"
    names+=("${base}")
  done < <(find "${root}/src/agentic" -path '*/tools/*' -name '*.sh' -type f -print0 2>/dev/null)
  if [[ ${#names[@]} -gt 0 ]]; then
    COMPREPLY=($(compgen -W "${names[*]}" -- "${cur}"))
  else
    COMPREPLY=()
  fi
}

# ── Helper: complete local Ollama model names ─────────────────────────────────
_devbot_complete_local_models() {
  if command -v docker >/dev/null 2>&1; then
    local models
    models="$(docker exec dev-bot-ollama ollama list 2>/dev/null | awk 'NR>1 {print $1}')"
    if [[ -n "${models}" ]]; then
      COMPREPLY=($(compgen -W "${models}" -- "${cur}"))
      return 0
    fi
  fi
  COMPREPLY=()
}

# ── Register the completion function ──────────────────────────────────────────
complete -F _devbot_complete devbot

#!/usr/bin/env bun
// =============================================================================
// src/agentic/guards/tools/guards.ts
// Harness-agnostic guards engine — the single home of guard-rule logic.
//
// Evaluates a bash command against guard rules merged from a global config
// (`.devbot.global.jsonc`) and a project config (`.devbot.project.jsonc`).
//
// Two entry points:
//   1. Imported by the opencode plugin (direct function call — no subprocess).
//   2. Run as a CLI by the claudecode hook: `bun guards.ts --command ...`.
//
// CLI outputs a single JSON line `{"blocked": bool, "message": string}`.
// =============================================================================

import fs from "fs"

interface GuardRule {
  regex: string
  message: string
  agent?: string
}

interface GuardResult {
  blocked: boolean
  message?: string
}

/** Strip `//` and `/* *\/` comments from JSONC so it can be parsed as JSON. */
function stripJsoncComments(text: string): string {
  const result: string[] = []
  let i = 0
  while (i < text.length) {
    if (text[i] === '"') {
      let j = i + 1
      while (j < text.length) {
        if (text[j] === "\\") {
          j += 2
        } else if (text[j] === '"') {
          j += 1
          break
        } else {
          j += 1
        }
      }
      result.push(text.slice(i, j))
      i = j
    } else if (text[i] === "/" && text[i + 1] === "/") {
      const j = text.indexOf("\n", i)
      i = j !== -1 ? j : text.length
    } else if (text[i] === "/" && text[i + 1] === "*") {
      const j = text.indexOf("*/", i + 2)
      i = j !== -1 ? j + 2 : text.length
    } else {
      result.push(text[i])
      i += 1
    }
  }
  return result.join("")
}

/** Load guard rules from a JSONC config file. Returns [] on missing/malformed. */
function loadGuards(configPath: string | undefined): GuardRule[] {
  if (!configPath || !fs.existsSync(configPath)) return []
  try {
    const raw = fs.readFileSync(configPath, "utf8")
    const parsed = JSON.parse(stripJsoncComments(raw))
    return Array.isArray(parsed?.guards) ? parsed.guards : []
  } catch {
    return []
  }
}

// Split on shell command separators so each segment is one command invocation.
const SEGMENT_SPLIT = /\s*(?:;|&&|\|\||\|&?|\n|\(|\)|>>?|<<?)\s*/

// Commands that can RUN other commands from their arguments (bash -c, xargs,
// find -exec, sudo ...): a guard pattern inside their arguments is genuinely
// dangerous, so they keep the substring match (fail closed).
const COMMAND_RUNNERS = new Set([
  "bash", "sh", "dash", "zsh", "ksh", "ash", "eval", "xargs", "find", "env",
  "sudo", "su", "nohup", "timeout", "ssh", "docker", "podman", "unshare",
  "nsenter", "chroot",
])

/** Evaluate a command against guard rules. First matching rule wins. */
function evaluate(command: string, guards: GuardRule[], agent: string): GuardResult {
  // A raw substring match blocks ANY command whose TEXT contains the pattern —
  // including a safe `echo "rm -rf"` (the pattern is an argument, not an
  // invocation). That is fail-closed (never lets a real danger through) but
  // noisy. Anchor the regex to the START of each command segment so the
  // dangerous command must actually be the one being invoked; keep the
  // substring test when the segment's command is a command-runner or uses
  // command substitution ($( ), ` `), where the danger hides in arguments.
  const segments = command.split(SEGMENT_SPLIT)
  for (const g of guards) {
    if (typeof g !== "object" || !g?.regex || !g?.message) continue
    if (g.agent !== undefined && g.agent !== agent) continue
    try {
      const anchored = new RegExp("^" + (g.regex.startsWith("^") ? g.regex.slice(1) : g.regex))
      for (const seg of segments) {
        const trimmed = seg.trim()
        if (!trimmed) continue
        const name = trimmed.split(/\s+/)[0]
        const substring = COMMAND_RUNNERS.has(name) || /\$\(|`/.test(trimmed)
        if ((substring ? new RegExp(g.regex) : anchored).test(trimmed)) {
          return { blocked: true, message: g.message }
        }
      }
    } catch {
      // Invalid regex — skip the rule.
    }
  }
  return { blocked: false }
}

/** Merge global + project guards and evaluate the command. */
export function checkCommand(
  command: string,
  globalConfig?: string,
  projectConfig?: string,
  agent = "",
): GuardResult {
  const guards = [...loadGuards(globalConfig), ...loadGuards(projectConfig)]
  return evaluate(command, guards, agent)
}

// ── CLI entry (for shell hooks, e.g. claudecode) ────────────────────────────
if (import.meta.main) {
  const args = process.argv.slice(2)
  const get = (name: string): string | undefined => {
    const i = args.indexOf(name)
    return i !== -1 ? args[i + 1] : undefined
  }

  const command = get("--command") ?? ""
  if (!command) {
    console.error("Error: --command is required")
    process.exit(1)
  }

  const result = checkCommand(
    command,
    get("--global-config"),
    get("--project-config"),
    get("--agent") ?? "",
  )
  console.log(JSON.stringify(result))
}

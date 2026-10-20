#!/usr/bin/env bun
// =============================================================================
// src/agentic/guards/tools/guards.ts
// Harness-agnostic guards engine — the single home of guard-rule logic.
//
// Evaluates a shell command against guard rules merged from a global config
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

// Shell whitespace only: Bash does not treat a nonbreaking space (or other
// Unicode spaces) as a word separator, and neither may the guard.
const SHELL_SPACE = /[ \t\n\r]/

// Shell word splitting: quotes group and are removed, a backslash escapes the
// next character (outside single quotes). The guard matches an argument vector,
// not the literal quoting, so `git "-C" /tmp` and `git -C /tmp` are equivalent.
function shellWords(segment: string): string[] {
  const words: string[] = []
  let word = ""
  let inWord = false
  let quote: '"' | "'" | null = null

  for (let i = 0; i < segment.length; i++) {
    const ch = segment[i]
    if (quote === "'") {
      if (ch === "'") quote = null
      else {
        word += ch
        inWord = true
      }
      continue
    }
    if (quote === '"') {
      if (ch === '"') quote = null
      else if (ch === "\\" && i + 1 < segment.length) {
        word += segment[++i]
        inWord = true
      } else {
        word += ch
        inWord = true
      }
      continue
    }
    if (ch === '"' || ch === "'") {
      quote = ch
      inWord = true
      continue
    }
    if (ch === "\\" && i + 1 < segment.length) {
      word += segment[++i]
      inWord = true
      continue
    }
    if (SHELL_SPACE.test(ch)) {
      if (inWord) {
        words.push(word)
        word = ""
        inWord = false
      }
      continue
    }
    word += ch
    inWord = true
  }
  if (inWord) words.push(word)
  return words
}

// Re-encode one shell word as a single regex subject: a space inside the word
// (quoted or escaped) becomes a sentinel so it is not a token boundary, and a
// literal quote/backslash is escaped so the rule's backslash branch consumes it.
function encodeWord(word: string): string {
  if (word === "") return "\x1f" // an empty quoted argument is still a token
  let out = ""
  for (const ch of word) {
    if (SHELL_SPACE.test(ch)) out += "\x1f"
    else if (ch === "\\" || ch === '"' || ch === "'") out += "\\" + ch
    else out += ch
  }
  return out
}

const FORCE_PUSH_MESSAGE = "force push is prohibited"
const INLINE_ALIAS_MESSAGE = "inline git aliases are prohibited — run the command directly"

// A token scan, not a regex: `push` followed by a force flag is a force-push
// regardless of options, quoting, expansions or backticks. Quoted prose stays
// one token (sentinel-encoded), so `-m "… push --force"` is not misread.
function hasForcePush(words: string[]): boolean {
  for (let i = 0; i < words.length; i++) {
    if (words[i] !== "push") continue
    for (let j = i + 1; j < words.length; j++) {
      const w = words[j]
      if (
        w === "-f" ||
        w === "--force" ||
        w === "--force-with-lease" ||
        w.startsWith("--force-with-lease=")
      ) {
        return true
      }
    }
  }
  return false
}

// Inline aliases are prohibited outright: alias values may be shell bodies or
// use Git config quoting, so resolving a force-push hidden in one is unsafe.
// Only global options before the subcommand count — `git grep -c alias.x` is a
// read-only search, not an alias definition.
function hasInlineAlias(words: string[]): boolean {
  if (words[0] !== "git") return false
  const valueOptions = new Set([
    "-C",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--exec-path",
    "--config-env",
  ])
  for (let i = 1; i < words.length; i++) {
    const w = words[i]
    if (w === "-c") {
      if (i + 1 < words.length && /^alias\./i.test(words[i + 1])) return true
      i++
      continue
    }
    if (/^-c[Aa][Ll][Ii][Aa][Ss]\./.test(w)) return true
    if (valueOptions.has(w)) {
      i++
      continue
    }
    if (w.startsWith("-")) continue
    break
  }
  return false
}

// The word vector starting at the git invocation: the segment itself, or the
// first `git` argument of a supported runner (`env git …`).
function gitWords(words: string[]): string[] | null {
  if (words[0] === "git") return words
  if (COMMAND_RUNNERS.has(words[0])) {
    const at = words.indexOf("git")
    if (at > 0) return words.slice(at)
  }
  return null
}

/** Evaluate a command against guard rules. First matching rule wins. */
function evaluate(command: string, guards: GuardRule[]): GuardResult {
  // A raw substring match blocks ANY command whose TEXT contains the pattern —
  // including a safe `echo "rm -rf"` (the pattern is an argument, not an
  // invocation). That is fail-closed (never lets a real danger through) but
  // noisy. Anchor the regex to the START of each command segment so the
  // dangerous command must actually be the one being invoked; keep the
  // substring test when the segment's command is a command-runner or uses
  // command substitution ($( ), ` `), where the danger hides in arguments.
  const segments = command.split(SEGMENT_SPLIT)
  // Bash expansions and ANSI-C quoting are not fully modelled by the
  // tokenizer; when present, fall back to a text check for a git force-push.
  const shellSyntax = /\$\(|`|\$'/.test(command)
  const parsed: Array<{ raw: string; words: string[]; canonical: string; runner: boolean }> = []
  for (const seg of segments) {
    const raw = seg.trim()
    if (!raw) continue
    const words = shellWords(raw)
    if (words.length === 0) continue
    parsed.push({
      raw,
      words,
      canonical: words.map(encodeWord).join(" "),
      runner: COMMAND_RUNNERS.has(words[0]) || /\$\(|`/.test(raw),
    })
  }

  // Configured rules first: they own the message, including a customized
  // force-push rule.
  for (const g of guards) {
    if (typeof g !== "object" || !g?.regex || !g?.message) continue
    try {
      const anchored = new RegExp("^" + (g.regex.startsWith("^") ? g.regex.slice(1) : g.regex))
      for (const p of parsed) {
        if (p.runner) {
          const re = new RegExp(g.regex)
          if (re.test(p.raw) || re.test(p.canonical)) {
            return { blocked: true, message: g.message }
          }
          // A runner carries a command as an argument (`bash -c "git push …"`).
          // Re-parse each argument that contains whitespace as a nested command.
          for (const word of p.words) {
            if (!SHELL_SPACE.test(word)) continue
            const inner = shellWords(word).map(encodeWord).join(" ")
            if (re.test(inner)) return { blocked: true, message: g.message }
          }
        } else if (anchored.test(p.raw) || anchored.test(p.canonical)) {
          return { blocked: true, message: g.message }
        }
      }
    } catch {
      // Invalid regex — skip the rule.
    }
  }

  // Built-in git safety: deterministic token scans, independent of the config.
  for (const p of parsed) {
    const git = gitWords(p.words)
    if (git) {
      if (hasInlineAlias(git)) return { blocked: true, message: INLINE_ALIAS_MESSAGE }
      if (hasForcePush(git)) return { blocked: true, message: FORCE_PUSH_MESSAGE }
    }
    // Only a runner's arguments are nested commands; a quoted argument of an
    // ordinary command (`echo "git push --force"`) is prose, not an invocation.
    if (p.runner) {
      for (const word of p.words) {
        if (!SHELL_SPACE.test(word)) continue
        const innerGit = gitWords(shellWords(word))
        if (!innerGit) continue
        if (hasInlineAlias(innerGit)) return { blocked: true, message: INLINE_ALIAS_MESSAGE }
        if (hasForcePush(innerGit)) return { blocked: true, message: FORCE_PUSH_MESSAGE }
      }
    }
    if (
      shellSyntax &&
      p.raw.includes("push") &&
      (p.raw.includes("--force") || /(?:^|[ \t\n\r])-f(?:[ \t\n\r]|$)/.test(p.raw)) &&
      (gitWords(p.words) || COMMAND_RUNNERS.has(p.words[0]))
    ) {
      return { blocked: true, message: FORCE_PUSH_MESSAGE }
    }
  }

  return { blocked: false }
}

/** Merge global + project guards and evaluate the command. */
export function checkCommand(
  command: string,
  globalConfig?: string,
  projectConfig?: string,
): GuardResult {
  // Project guards come FIRST so they override global defaults on first match
  // (audit-59 FAIL-1): a project rule reusing a global regex — typically to
  // customize the message — was previously unreachable because the global copy
  // always matched first. This mirrors how .devbot.project.jsonc overrides
  // .devbot.global.jsonc everywhere else.
  //
  // Guards are deny-only: a rule either blocks or is ignored — there is no
  // allow/negate action. The blocked set is therefore the UNION of all matching
  // rules, and order only decides WHICH message is reported. A project rule can
  // add rules or reword a match, never weaken a global guard.
  const guards = [...loadGuards(projectConfig), ...loadGuards(globalConfig)]
  return evaluate(command, guards)
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
  )
  console.log(JSON.stringify(result))
}

// on-tool_execute_after-git_commit-graphify-update.ts
// Two-phase design to avoid running graphify mid-workflow:
//   1. tool.execute.after — detects successful git commit, writes trigger file
//   2. event (session.idle) — reads trigger, spawns graphify update in background
//
// Safety:
//   - Dedup by commit hash prevents double-fire
//   - flock-based mutex in graphify-update-bg.sh prevents concurrent updates
//   - Trigger TTL: 5 min — stale triggers discarded
//   - Fail-open: all errors silently caught
//
// Thin trigger — all logic delegated to tools/graphify-update-bg.sh.

import type { Plugin } from "@opencode-ai/plugin"
import { existsSync, readFileSync, writeFileSync, mkdirSync, unlinkSync } from "fs"
import { join } from "path"
import { execSync } from "child_process"

// ─── Constants ──────────────────────────────────────────────────────────────

const TRIGGER_TTL_MS = 5 * 60 * 1000 // 5 minutes

// ─── Dedup guard (module-level) ──────────────────────────────────────────────

const processedCommits = new Set<string>()

// ─── Trigger file ──────────────────────────────────────────────────────────────
// Path: graphify-out/.graphify-commit-trigger.json

function triggerFilePath(directory: string): string {
  return join(directory, "graphify-out", ".graphify-commit-trigger.json")
}

function writeTrigger(directory: string, hash: string): void {
  try {
    const path = triggerFilePath(directory)
    mkdirSync(join(directory, "graphify-out"), { recursive: true })
    writeFileSync(path, JSON.stringify({ hash, committedAt: new Date().toISOString() }, null, 2), "utf8")
  } catch {
    // Fail open
  }
}

function readTrigger(directory: string): { hash: string; committedAt: string } | null {
  try {
    const path = triggerFilePath(directory)
    if (!existsSync(path)) return null
    const raw = readFileSync(path, "utf8")
    if (!raw.trim()) return null
    const data = JSON.parse(raw)
    // Discard stale triggers
    const age = Date.now() - new Date(data.committedAt).getTime()
    if (age > TRIGGER_TTL_MS) {
      try { unlinkSync(path) } catch {}
      return null
    }
    return data
  } catch {
    return null
  }
}

function clearTrigger(directory: string): void {
  try {
    const path = triggerFilePath(directory)
    if (existsSync(path)) unlinkSync(path)
  } catch {
    // Fail open
  }
}

// ─── Is commit successful? ───────────────────────────────────────────────────

function isCommitSuccessful(output: any): boolean {
  const ec = output?.metadata?.exitCode
  if (typeof ec === "number") return ec === 0
  const outStr = String(output?.output ?? "")
  if (/fatal:/i.test(outStr)) return false
  if (/Aborting/i.test(outStr)) return false
  return true
}

// ─── Plugin factory ───────────────────────────────────────────────────────────

export const OnGitCommitGraphifyUpdate: Plugin = async ({ project }) => {
  const directory = project.worktree
  const bgRunner = join(import.meta.dir, "../../tools/graphify-update-bg.sh")

  // ── Phase 1: Detect commit, write trigger ────────────────────────────────

  const onToolAfter = async (input: any, output: any) => {
    let commitHash = ""
    try {
      // Tool filter
      const tool = String(input?.tool ?? "").toLowerCase()
      if (tool !== "bash" && tool !== "shell") return

      // Command must contain "git commit"
      const command = String(input?.args?.command ?? "")
      if (!/git\s+commit/.test(command)) return

      // Check if commit was successful
      if (!isCommitSuccessful(output)) return

      // Extract commit hash
      try {
        const gitOut = execSync('git log -1 --format="%H"', {
          cwd: directory,
          encoding: "utf8",
          timeout: 5000,
        })
        commitHash = gitOut.trim()
      } catch {
        return
      }
      if (!commitHash) return

      // Dedup
      if (processedCommits.has(commitHash)) return
      processedCommits.add(commitHash)

      // Write trigger
      writeTrigger(directory, commitHash)
    } catch {
      if (commitHash) processedCommits.delete(commitHash)
    }
  }

  // ── Phase 2: Read trigger on idle, spawn update ──────────────────────────

  const onEvent = async ({ event }: { event: any }) => {
    let commitHash = ""
    try {
      if (event?.type !== "session.idle") return

      const trigger = readTrigger(directory)
      if (!trigger) return
      commitHash = trigger.hash

      // Spawn graphify update in background
      const proc = Bun.spawn(["bash", bgRunner, directory], {
        cwd: directory,
        stdio: ["ignore", "ignore", "ignore"],
        detached: true,
      })
      proc.unref()

      clearTrigger(directory)
    } catch {
      if (commitHash) processedCommits.delete(commitHash)
      try { clearTrigger(directory) } catch {}
    }
  }

  return {
    "tool.execute.after": onToolAfter,
    event: onEvent,
  }
}

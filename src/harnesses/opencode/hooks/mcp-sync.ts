// src/harnesses/opencode/hooks/mcp-sync.ts
// Writes a runtime MCP toggle back to the project
// config, so project-for-path reports reality.

import type { Plugin } from "@opencode-ai/plugin"
import {
  appendFileSync,
  chmodSync,
  mkdirSync,
  readFileSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { acquireLock, releaseLock } from "../mcp-sync-lock"
import {
  configTarget,
  globalConfigCandidates,
  insertServer,
  planWrites,
  serverEnabledFrom,
  serverObjectFrom,
  setServerEnabled,
  type StatusMap,
  type Write,
} from "../mcp-sync-utils"

const POLL_MS = 2000

function message(err: unknown): string {
  return err instanceof Error ? err.message : String(err)
}

function summary(map: StatusMap): string {
  return Object.entries(map)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, state]) => `${name}=${state.status}`)
    .join(", ")
}

export const McpSync: Plugin = async ({ client, worktree, directory }) => {
  const root = worktree || directory || process.cwd()
  const logFile = join(root, ".agents", "logs", "mcp-sync.log")
  const globalCandidates = globalConfigCandidates(homedir(), process.env.XDG_CONFIG_HOME)
  let prev: StatusMap | null = null
  let busy = false
  let lastError = ""
  let tmpSeq = 0
  const warned = new Set<string>()

  const log = (line: string) => {
    try {
      mkdirSync(dirname(logFile), { recursive: true })
      appendFileSync(logFile, `${new Date().toISOString()} [mcp-sync] ${line}\n`)
    } catch {
      // Logging must never break the harness.
    }
  }

  const warn = (key: string, reason: string) => {
    if (warned.has(key)) return
    warned.add(key)
    log(`WARN: ${key}: ${reason}`)
  }

  const read = (path: string): string | null => {
    try {
      return readFileSync(path, "utf8")
    } catch {
      return null
    }
  }

  // In force now: project config, then global.
  const effectiveEnabled = (server: string): boolean | null | undefined => {
    const text = read(configTarget(root))
    if (text !== null) {
      const value = serverEnabledFrom(text, server)
      if (value !== undefined) return value
    }
    for (const path of globalCandidates) {
      const global = read(path)
      if (global === null) continue
      const value = serverEnabledFrom(global, server)
      if (value !== undefined) return value
    }
    return undefined
  }

  // Raw, unexpanded: no secrets in the file.
  const globalDefinition = (server: string): string | null => {
    for (const path of globalCandidates) {
      const text = read(path)
      if (text === null) continue
      const raw = serverObjectFrom(text, server)
      if (raw !== null) return raw
    }
    return null
  }

  const writeAtomic = (path: string, expected: string, text: string): boolean => {
    const lock = `${path}.mcp-sync.lock`
    const token = acquireLock(lock)
    if (!token) {
      warn(path, "locked by another session — retrying")
      return false
    }
    tmpSeq += 1
    const tmp = `${path}.mcp-sync.${process.pid}.${tmpSeq}.tmp`
    try {
      // Under the lock: revalidate, then write.
      // (a reinit) is retried, not overwritten.
      if (read(path) !== expected) {
        warn(path, "changed while syncing — retrying")
        return false
      }
      writeFileSync(tmp, text, "utf8")
      try {
        chmodSync(tmp, statSync(path).mode & 0o777)
      } catch {
        // Mode preservation is best-effort.
      }
      renameSync(tmp, path)
      return true
    } catch (err) {
      log(`ERROR: ${path}: ${message(err)}`)
      try {
        unlinkSync(tmp)
      } catch {
        // Nothing to clean up.
      }
      return false
    } finally {
      releaseLock(lock, token)
    }
  }

  const apply = (write: Write): boolean => {
    const target = configTarget(root)
    const text = read(target)
    if (text === null) {
      warn(write.server, `cannot read ${target}`)
      return false
    }

    let applied = setServerEnabled(text, write.server, write.enabled)
    if (serverObjectFrom(text, write.server) === null) {
      const raw = globalDefinition(write.server)
      if (raw === null) {
        warn(write.server, "not declared in the project or global config")
        return false
      }
      applied = insertServer(text, write.server, raw, write.enabled)
    }
    if (!applied.changed) {
      warned.delete(write.server)
      return true
    }
    if (!writeAtomic(target, text, applied.text)) return false
    warned.delete(write.server)
    log(`${write.server}: enabled=${String(write.enabled)} → ${target}`)
    return true
  }

  const poll = async () => {
    if (busy) return
    busy = true
    try {
      const { data, error } = await client.mcp.status({ query: { directory: root } })
      if (error || !data) {
        const failure = error ? message(error) : "no status returned"
        if (failure !== lastError) {
          lastError = failure
          log(`WARN: mcp.status failed: ${failure}`)
        }
        return
      }
      lastError = ""
      const next = data as StatusMap

      if (prev === null) {
        prev = next
        log(`baseline: ${summary(next)}`)
        return
      }

      // Only changed servers need the config read.
      const configured: Record<string, boolean | null> = {}
      for (const name of Object.keys(next)) {
        if (prev[name] !== undefined && prev[name].status === next[name].status) continue
        const value = effectiveEnabled(name)
        if (value !== undefined) configured[name] = value
      }

      const writes = planWrites(prev, next, configured)
      const advanced: StatusMap = { ...next }
      for (const write of writes) {
        if (apply(write)) continue
        // Keep it so the next poll retries.
        if (prev[write.server]) advanced[write.server] = prev[write.server]
        else delete advanced[write.server]
      }
      prev = advanced
    } catch (err) {
      const failure = message(err)
      if (failure !== lastError) {
        lastError = failure
        log(`ERROR: poll failed: ${failure}`)
      }
    } finally {
      busy = false
    }
  }

  const timer = setInterval(() => {
    void poll()
  }, POLL_MS)
  ;(timer as unknown as { unref?: () => void }).unref?.()

  void poll()

  return {}
}

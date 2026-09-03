// src/harnesses/opencode/hooks/on-hooks.ts
// Generic harness adapter: reads every module's `hooks.json` manifest and wires
// its declared hooks into opencode's plugin API. Business logic stays in each
// module's `tools/` entry; this adapter maps events → commands (or delegates
// `plugin:` hooks).
//
// IMPORTANT: this module must export ONLY the OnHooks plugin factory. opencode
// invokes every function export of a registered plugin as a plugin factory, so
// any helper export crashes or corrupts the plugin — helpers live in the
// sibling ../on-hooks-utils.ts (outside hooks/, so the harness init never
// registers it as a plugin).

import type { Plugin } from "@opencode-ai/plugin"
import { readFileSync, readdirSync, existsSync } from "fs"
import { join } from "path"
import { execSync } from "child_process"
import { createLogger } from "../../../_shared/logger.ts"
import { defaultHookLog, createFileEditGate, guardDecision, resolveGlobalConfigPath, routeHookOutput, type HookDecl } from "../on-hooks-utils"

const DEV_BOT_ROOT = join(import.meta.dir, "../../../..") // repo root

function loadManifests(): { moduleDir: string; hooks: HookDecl[] }[] {
  const base = join(DEV_BOT_ROOT, "src", "agentic")
  if (!existsSync(base)) return []
  const out: { moduleDir: string; hooks: HookDecl[] }[] = []
  for (const dir of readdirSync(base)) {
    const manifest = join(base, dir, "hooks.json")
    if (!existsSync(manifest)) continue
    try {
      const parsed = JSON.parse(readFileSync(manifest, "utf8"))
      if (Array.isArray(parsed?.hooks)) out.push({ moduleDir: join(base, dir), hooks: parsed.hooks })
    } catch {
      // Skip malformed manifest.
    }
  }
  return out
}

function resolve(run: string[], ctx: Record<string, string>): string[] {
  return run.map((part) => part.replace(/\{(\w[\w-]*)\}/g, (_, key: string) => ctx[key] ?? ""))
}

async function runCommand(cmd: string[], cwd: string): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const proc = Bun.spawn(cmd, { cwd, stdout: "pipe", stderr: "pipe" })
  // Drain both streams concurrently — an undrained stderr pipe fills up and
  // blocks the child hook once the buffer exceeds ~64KB.
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ])
  const exitCode = await proc.exited
  return { stdout, stderr, exitCode }
}

// (appendLog, defaultHookLog and routeHookOutput live in ../on-hooks-utils.ts
// — see the header note about why this module cannot export them.)

export const OnHooks: Plugin = async ({ directory, worktree, project, client }) => {
  const root = worktree || project?.worktree || directory
  const logger = createLogger({
    module: "hooks",
    // audit-24 NOTE-2: route logger output to the hooks log file so hook
    // failures are captured even when plugin stderr is not.
    logFile: join(root, defaultHookLog()),
  })
  const manifests = loadManifests()
  // Per-file gate for file.edited hooks (audit-32: burst-edit race).
  const fileEditGate = createFileEditGate()

  // Plugin-type hooks declared in module manifests: import each factory and
  // merge the handlers it returns into this adapter's dispatch. This is how
  // client-using hooks (auto-recover prompt injection, the stall watchdog)
  // stay module-owned while being wired for the opencode harness.
  const pluginHandlers: Record<string, Array<(input: any, output?: any) => Promise<void>>> = {}
  for (const { moduleDir, hooks } of manifests) {
    for (const hook of hooks) {
      if (!hook.plugin) continue
      const pluginPath = resolve([hook.plugin], { module: moduleDir })[0]
      const abs = pluginPath.startsWith("/") ? pluginPath : join(DEV_BOT_ROOT, pluginPath)
      try {
        const mod = await import(abs)
        const factory = mod?.default
        if (typeof factory !== "function") {
          logger.debug(`plugin hook ${hook.id}: no default export at ${abs}`)
          continue
        }
        const handlers = await factory({ directory, worktree, project, client })
        if (!handlers) continue
        for (const [eventName, fn] of Object.entries(handlers)) {
          if (typeof fn !== "function") continue
          ;(pluginHandlers[eventName] ??= []).push(fn as any)
        }
        logger.info(`loaded plugin hook ${hook.id} from ${abs}`)
      } catch (e) {
        logger.debug(`plugin hook ${hook.id} failed to load: ${e instanceof Error ? e.message : String(e)}`)
      }
    }
  }

  // Non-blocking event dispatch (file.edited, session.*).
  async function dispatch(eventName: string, matchFile: string | undefined, ctx: Record<string, string>) {
    for (const { moduleDir, hooks } of manifests) {
      for (const hook of hooks) {
        if (hook.event !== eventName || !hook.run) continue
        const re = hook.match?.file
        if (re && matchFile !== undefined && !new RegExp(re).test(matchFile)) continue
        const contentRe = hook.match?.content
        if (contentRe && matchFile !== undefined) {
          try {
            const head = readFileSync(matchFile, "utf-8").slice(0, 4096)
            if (!new RegExp(contentRe).test(head)) continue
          } catch {
            continue
          }
        }
        const cmd = resolve(hook.run, { module: moduleDir, worktree: root, ...ctx })
        try {
          const out = await runCommand(cmd, root)
          routeHookOutput(out, hook, root)
        } catch (e) {
          logger.debug(`${hook.id} hook failed: ${e instanceof Error ? e.message : String(e)}`)
        }
      }
    }
  }

  return {
    event: async ({ event }: { event: any }) => {
      for (const fn of pluginHandlers.event ?? []) await fn({ event })
      const type = event?.type
      if (type === "file.edited") {
        const file: string = (event as any).properties?.file ?? ""
        if (file) {
          // audit-32 FAIL: format-yml burst race — two file.edited events
          // within ~1s ran two concurrent format hooks whose read-modify-write
          // interleaves corrupted the file. Serialize + coalesce per file: a
          // burst collapses into one in-flight run plus one trailing re-run.
          fileEditGate(file, () => dispatch("file.edited", file, { file }))
        }
      } else if (type === "session.created") {
        await dispatch("session.created", undefined, {})
      } else if (type === "session.idle") {
        const id = event?.properties?.sessionID || event?.properties?.info?.id || event?.properties?.id || ""
        await dispatch("session.idle", undefined, { "session-id": id })
      } else if (type === "session.error") {
        const id = event?.properties?.sessionID || event?.properties?.info?.id || event?.properties?.id || ""
        const err = event?.properties?.error?.message || event?.properties?.error?.data?.message || event?.properties?.message || ""
        await dispatch("session.error", undefined, { "session-id": id, error: err })
      }
    },

    "tool.execute.before": async (input: any, output: any) => {
      for (const fn of pluginHandlers["tool.execute.before"] ?? []) await fn(input, output)
      const tool = String(input?.tool ?? "").toLowerCase()
      const command = String((output?.args as any)?.command ?? (input?.args as any)?.command ?? "")
      for (const { moduleDir, hooks } of manifests) {
        for (const hook of hooks) {
          if (hook.event !== "command.before" || !hook.run) continue
          if (hook.match?.tool && !hook.match.tool.includes(tool)) continue

          const agent = process.env.OPENCODE_AGENT ?? ""
          // audit-32 FAIL: guards silently disabled — env is DEV_BOT_ROOT, not
          // DEVBOT_ROOT. Resolve from the plugin's own root (realpath, already
          // used for manifest loading above) so guards run with rules.
          const globalConfig = resolveGlobalConfigPath(DEV_BOT_ROOT, process.env)
          const projectConfig = join(root, ".devbot.project.jsonc")
          const cmd = resolve(hook.run, {
            module: moduleDir,
            worktree: root,
            command,
            agent,
            "global-config": globalConfig,
            "project-config": projectConfig,
          })
          try {
            const out = await runCommand(cmd, root)
            const decision = guardDecision(out, hook.blocking)
            if (decision.blocked) {
              throw new Error(`[${hook.id}] Command blocked: ${decision.message}`)
            }
          } catch (e) {
            if (e instanceof Error && e.message.startsWith(`[${hook.id}]`)) throw e
            // The guard tool failed to execute (missing interpreter/script).
            // A blocking guard that cannot run must fail CLOSED, not silently
            // let the command through (audit-31 §2) — opencode treats an
            // exception from tool.execute.before as a block.
            if (hook.blocking) {
              throw new Error(`[${hook.id}] Command blocked: guard temporarily unavailable (failed to execute)`)
            }
            logger.debug(`${hook.id} hook failed: ${e instanceof Error ? e.message : String(e)}`)
          }
        }
      }
    },

    "tool.execute.after": async (input: any, output: any) => {
      for (const fn of pluginHandlers["tool.execute.after"] ?? []) await fn(input, output)
      const tool = String(input?.tool ?? "").toLowerCase()
      if (tool !== "bash" && tool !== "shell") return
      const command = String(input?.args?.command ?? "")

      // Fire only on successful commands.
      const ec = output?.metadata?.exitCode
      if (typeof ec === "number" && ec !== 0) return
      const outStr = String(output?.output ?? "")
      if (/fatal:/i.test(outStr) || /Aborting/i.test(outStr)) return

      let hash = ""
      try {
        hash = execSync('git log -1 --format="%H"', { cwd: root, encoding: "utf8", timeout: 5000 }).trim()
      } catch {
        // No commit hash available.
      }

      for (const { moduleDir, hooks } of manifests) {
        for (const hook of hooks) {
          if (hook.event !== "command.after" || !hook.run) continue
          if (hook.match?.command && !new RegExp(hook.match.command).test(command)) continue
          const cmd = resolve(hook.run, { module: moduleDir, worktree: root, command, hash })
          try {
            const out = await runCommand(cmd, root)
            // Route output like dispatch() does — a command.after hook that
            // declares a "log" field must not have its output silently
            // discarded (mirrors the claudecode post-bash fix, audit-31 §5).
            routeHookOutput(out, hook, root)
          } catch (e) {
            logger.debug(`${hook.id} hook failed: ${e instanceof Error ? e.message : String(e)}`)
          }
        }
      }
    },
  }
}

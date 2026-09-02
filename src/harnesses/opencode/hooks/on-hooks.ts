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
import { appendHooksLog, defaultHookLog, deletedFileFromWatcher, routeHookOutput, type HookDecl } from "../on-hooks-utils"

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

async function runCommand(cmd: string[], cwd: string): Promise<{ stdout: string; stderr: string }> {
  const proc = Bun.spawn(cmd, { cwd, stdout: "pipe", stderr: "pipe" })
  // Drain both streams concurrently — an undrained stderr pipe fills up and
  // blocks the child hook once the buffer exceeds ~64KB.
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ])
  await proc.exited
  return { stdout, stderr }
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
        if (file) await dispatch("file.edited", file, { file })
      } else if (type === "file.watcher.updated") {
        // audit-28 NOTE-8: a delete arrives as a watcher "unlink" event (the
        // SDK has no file.deleted type). Map it to a "file.deleted" hook event
        // so modules can react to removals — e.g. reindexing memory to prune
        // the stale index entries of deleted notes.
        const deleted = deletedFileFromWatcher(event)
        if (deleted) {
          await dispatch("file.deleted", deleted, { file: deleted })
        } else {
          // audit-29 FAIL: bash-deleted memory notes never dispatched
          // file.deleted in opencode 1.18.26, leaving stale search entries.
          // Record rejected watcher payloads that look delete-related (or
          // touch the memory vault) so a live session captures the real event
          // shape — then the matcher is adapted, or the idle-prune self-heal
          // hook remains the answer.
          const props = (event as any)?.properties
          const ev = String(props?.event ?? "")
          const file = String(props?.file ?? "")
          const deleteLike = ["unlink", "remove", "delete", "deleted"].includes(ev)
          const memoryPath = file.includes("/memory/") && ev !== "edit" && ev !== "create"
          if (deleteLike || memoryPath) {
            appendHooksLog(root, `watcher.rejected type=${type} event=${ev} file=${file} props=${JSON.stringify(props ?? {})}`)
          }
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
          const globalConfig = process.env.DEVBOT_ROOT
            ? join(process.env.DEVBOT_ROOT, ".devbot.global.jsonc")
            : ""
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
            let parsed: any = {}
            try {
              parsed = JSON.parse(out.stdout)
            } catch {
              // Non-JSON output — not blocked.
            }
            if (parsed?.blocked) {
              throw new Error(`[${hook.id}] Command blocked: ${parsed.message ?? "guard rule"}`)
            }
          } catch (e) {
            if (e instanceof Error && e.message.startsWith(`[${hook.id}]`)) throw e
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
            await runCommand(cmd, root)
          } catch (e) {
            logger.debug(`${hook.id} hook failed: ${e instanceof Error ? e.message : String(e)}`)
          }
        }
      }
    },
  }
}

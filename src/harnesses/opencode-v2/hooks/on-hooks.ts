// src/harnesses/opencode-v2/hooks/on-hooks.ts
// Generic harness adapter for OpenCode 2.x: reads every module's `hooks.json`
// manifest and wires its declared hooks into the V2 plugin API. Business logic
// stays in each module's `tools/` entry; this adapter maps events → commands.
//
// V2 difference: a plugin is `Plugin.define({ id, setup(ctx) })` and registers
// each hook on the domain that owns it, receiving ONE mutable event instead of
// v1's (input, output) pair. Helpers still live in ../on-hooks-utils.ts so this
// module exports nothing but its definition.

import { Plugin } from "@opencode/plugin"
import { readFileSync, readdirSync, existsSync } from "fs"
import { createHash } from "crypto"
import { join } from "path"
import { execSync } from "child_process"
import { createLogger } from "../../../_shared/logger.ts"
import { commandString, createFileEditGate, createKindResolver, createRewriteEchoTracker, defaultHookLog, guardDecision, hasCommand, disabledModules, injectSessionId, ptySubagentGuard, rememberAgent, resolveGlobalConfigPath, routeHookOutput, sessionEnvVars, type HookDecl } from "../on-hooks-utils"

const DEV_BOT_ROOT = join(import.meta.dir, "../../../..") // repo root

function loadManifests(projectRoot: string): { moduleDir: string; hooks: HookDecl[] }[] {
  const base = join(DEV_BOT_ROOT, "src", "agentic")
  if (!existsSync(base)) return []
  const disabled = disabledModules(projectRoot, DEV_BOT_ROOT)
  const out: { moduleDir: string; hooks: HookDecl[] }[] = []
  for (const dir of readdirSync(base)) {
    const manifest = join(base, dir, "hooks.json")
    if (!existsSync(manifest)) continue
    // A module disabled for this project must not run its hooks.
    if (disabled.has(dir)) continue
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

// Tool.Result carries `content` (string | Content[]) and `metadata`; v1's
// `output.output` and `output.metadata` have no direct equivalent.
function resultText(result: any): string {
  const content = result?.content
  if (typeof content === "string") return content
  if (Array.isArray(content)) {
    return content.map((c: any) => (typeof c === "string" ? c : c?.text ?? "")).join("\n")
  }
  return typeof result?.output === "string" ? result.output : ""
}

export default Plugin.define({
  id: "devbot-hooks",
  async setup(ctx: any) {
    // The project canonical root is the honest equivalent of v1's `worktree`:
    // hook commands and manifests resolve against the checkout, not a subdir.
    const root: string = ctx.location?.project?.canonical || ctx.location?.directory || process.cwd()
    const logger = createLogger({
      module: "hooks",
      logFile: join(root, defaultHookLog()),
    })
    const manifests = loadManifests(root)
    // Per-file gate for file.edited hooks (burst-edit race).
    const fileEditGate = createFileEditGate()
    // Rewrite-echo suppression (formatter ping-pong).
    const rewriteEcho = createRewriteEchoTracker()
    // Create-vs-edit classification (format-on-create corrupts).
    const kindResolver = createKindResolver()
    const EDIT_DEBOUNCE_MS = 400
    const debounceTimers = new Map<string, ReturnType<typeof setTimeout>>()
    // The shell hook carries no session id, so the env attach follows the most
    // recent session that ran a model request — the only session that can be
    // mid-step when a shell is created.
    let lastSessionID = ""

    // Content signature of a file — the echo of a hook's own rewrite has the
    // same signature as the state recorded after dispatch; a real edit differs.
    function contentSig(file: string): string {
      try {
        return createHash("sha1").update(readFileSync(file)).digest("hex")
      } catch {
        return ""
      }
    }

    // Module hooks declared with a `plugin:` factory are V1 plugin
    // implementations, which do not run on a V2 host. Report them once rather
    // than silently dropping their behaviour.
    const v1PluginHooks = manifests.flatMap(({ hooks }) => hooks.filter((h) => h.plugin))
    if (v1PluginHooks.length > 0) {
      logger.info(
        `skipping ${v1PluginHooks.length} manifest-declared V1 plugin hook(s): ${v1PluginHooks.map((h) => h.id).join(", ")}`,
      )
    }

    // Non-blocking event dispatch (file.edited, session.*).
    async function dispatch(eventName: string, matchFile: string | undefined, vars: Record<string, string>, opts: { create?: boolean } = {}) {
      for (const { moduleDir, hooks } of manifests) {
        for (const hook of hooks) {
          if (hook.event !== eventName || !hook.run) continue
          // A rewrite hook (formatter) must not run on the file.edited of a
          // file *create* — normalizing before the agent's next edit makes the
          // fuzzy edit tool splice stale-indentation hunks into it.
          if (opts.create && hook.skipOnCreate) continue
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
          const cmd = resolve(hook.run, { module: moduleDir, worktree: root, ...vars })
          try {
            const out = await runCommand(cmd, root)
            routeHookOutput(out, hook, root)
          } catch (e) {
            logger.debug(`${hook.id} hook failed: ${e instanceof Error ? e.message : String(e)}`)
          }
        }
      }
    }

    async function handleEvent(event: any) {
      // V2 events carry their payload under `properties`, like v1.
      const type = event?.type
      const props = event?.properties ?? {}

      if (type === "file.edited") {
        const file: string = props.file ?? ""
        if (!file) return
        const sig = contentSig(file)
        if (rewriteEcho.isEcho(file, sig)) {
          // The watcher echo of a rewrite our own hooks just performed —
          // content is unchanged since the hook wrote it, so re-dispatching
          // would run every matching hook again.
          return
        }
        // file.edited carries no create-vs-edit flag; the companion
        // file.watcher.updated does. Buffer until it arrives so skipOnCreate
        // hooks can avoid normalizing a freshly-written file.
        kindResolver.onEdited(file, (kind) => {
          // Debounce: a burst of rapid edits resets the timer so one run
          // happens after the burst has quiesced, never between two edits.
          const existing = debounceTimers.get(file)
          if (existing !== undefined) clearTimeout(existing)
          debounceTimers.set(
            file,
            setTimeout(() => {
              debounceTimers.delete(file)
              // Serialize + coalesce per file: two concurrent format hooks
              // interleaving read-modify-write corrupts the file.
              fileEditGate(file, async () => {
                const before = contentSig(file)
                await dispatch("file.edited", file, { file }, { create: kind === "add" })
                const after = contentSig(file)
                if (before && after && before !== after && kind !== "add") {
                  logger.info(`file.edited hooks rewrote ${file} (format normalization?) — re-read the file before your next edit`)
                }
                rewriteEcho.record(file, after)
              })
            }, EDIT_DEBOUNCE_MS),
          )
        })
      } else if (type === "file.watcher.updated") {
        const file: string = props.file ?? ""
        const kind: string = props.event ?? ""
        if (file && (kind === "add" || kind === "change" || kind === "unlink")) {
          kindResolver.onWatcher(file, kind)
        }
      } else if (type === "session.created") {
        await dispatch("session.created", undefined, {})
      } else if (type === "session.idle") {
        const id = props.sessionID || props.info?.id || props.id || ""
        await dispatch("session.idle", undefined, { "session-id": id })
      } else if (type === "session.error") {
        const id = props.sessionID || props.info?.id || props.id || ""
        const err = props.error?.message || props.error?.data?.message || props.message || ""
        await dispatch("session.error", undefined, { "session-id": id, error: err })
      }
    }

    const controller = new AbortController()
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          try {
            await handleEvent(event)
          } catch (e) {
            logger.debug(`event ${(event as any)?.type} failed: ${e instanceof Error ? e.message : String(e)}`)
          }
        }
      } catch {
        // Aborted on unload.
      }
    })()

    await ctx.tool.hook("execute.before", async (event: any) => {
      const tool = String(event?.tool ?? "").toLowerCase()
      const args = event?.input
      // Name the caller for tools that read the session's own state — the MCP
      // server's process cannot know which session invoked it.
      injectSessionId(tool, event?.sessionID, args)
      // PTYs are top-level only: a `task` subagent's child session cannot
      // surface a PTY's exit notification, so a notifyOnExit PTY there hangs
      // the task. Fails open on a lookup error.
      const ptyReason = await ptySubagentGuard(ctx, tool, event?.sessionID)
      if (ptyReason) throw new Error(`[pty-subagent] ${ptyReason}`)
      // Every shell channel must reach the guards.
      const command = commandString(tool, args)
      // Nothing to evaluate — the guards tool would exit non-zero on an empty
      // command, which a blocking guard reads as "blocked".
      if (!hasCommand(command)) return

      for (const { moduleDir, hooks } of manifests) {
        for (const hook of hooks) {
          if (hook.event !== "command.before" || !hook.run) continue
          if (hook.match?.tool && !hook.match.tool.includes(tool)) continue

          const globalConfig = resolveGlobalConfigPath(DEV_BOT_ROOT, process.env)
          const projectConfig = join(root, ".devbot.project.jsonc")
          const cmd = resolve(hook.run, {
            module: moduleDir,
            worktree: root,
            command,
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
            // A blocking guard that cannot run must fail CLOSED — a v2 host
            // treats a thrown execute.before as a block.
            if (hook.blocking) {
              throw new Error(`[${hook.id}] Command blocked: guard temporarily unavailable (failed to execute)`)
            }
            logger.debug(`${hook.id} hook failed: ${e instanceof Error ? e.message : String(e)}`)
          }
        }
      }
    })

    await ctx.tool.hook("execute.after", async (event: any) => {
      const tool = String(event?.tool ?? "").toLowerCase()
      if (tool !== "bash" && tool !== "shell") return
      // Fire only on successful commands.
      if (event?.status === "error") return
      const command = String(event?.input?.command ?? "")
      const exitCode = event?.result?.metadata?.exitCode
      if (typeof exitCode === "number" && exitCode !== 0) return
      const outStr = resultText(event?.result)
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
            routeHookOutput(out, hook, root)
          } catch (e) {
            logger.debug(`${hook.id} hook failed: ${e instanceof Error ? e.message : String(e)}`)
          }
        }
      }
    })

    // The context hook carries the running agent; v1 read it from chat.params.
    await ctx.session.hook("context", (event: any) => {
      const sessionID = String(event?.sessionID ?? "")
      if (sessionID) lastSessionID = sessionID
      rememberAgent(sessionID || event?.sessionID, event?.agent)
    })

    // v1's shell.env hook has no v2 equivalent: ShellCreateBefore carries env
    // but no session, so the env is scoped to the last session that ran a
    // model request.
    await ctx.shell.hook("create.before", (event: any) => {
      Object.assign(event.env, sessionEnvVars(lastSessionID))
    })

    return () => {
      controller.abort()
      for (const timer of debounceTimers.values()) clearTimeout(timer)
      debounceTimers.clear()
    }
  },
})

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
import { appendToToolResult, commandString, createFileEditGate, createKindResolver, createRewriteEchoTracker, defaultHookLog, guardDecision, hasCommand, disabledModules, injectSessionId, rememberAgent, resolveGlobalConfigPath, routeHookOutput, sessionEnvVars, canonicalToolName, eventPayload, toolFileTargets, type HookDecl, type FileChangeKind } from "../on-hooks-utils"

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

    // Project-relative tool paths (`edit`/`write`/`patch` take `path`) become
    // absolute so every downstream consumer — matchers, hooks, the gate — keys
    // on one identity.
    function absolute(file: string): string {
      return file.startsWith("/") ? file : join(root, file)
    }

    // add-vs-change for TOOL-mediated writes. A V2 host publishes no
    // file.edited for a tool write (audit-01 FAIL-1), so the adapter derives
    // the edit from the tool hooks that do fire, and records the file's
    // existence just before the write to classify it exactly like a watcher
    // "add". Keyed per session so two sessions editing one file cannot
    // mis-attribute the kind.
    const pendingCreates = new Map<string, boolean>()
    const MAX_PENDING_CREATES = 1024
    function createKey(sessionID: unknown, file: string): string {
      return `${String(sessionID ?? "")}\u0000${file}`
    }
    function rememberPendingCreate(key: string, value: boolean) {
      pendingCreates.delete(key)
      pendingCreates.set(key, value)
      // A long-lived server never drops a session; bound the map so an
      // after-hook that never fires cannot accumulate one entry per write.
      if (pendingCreates.size > MAX_PENDING_CREATES) {
        const oldest = pendingCreates.keys().next()
        if (!oldest.done) pendingCreates.delete(oldest.value)
      }
    }

    // Dispatch one file edit after the burst settles. Shared by the event
    // stream and the tool hooks so the debounce, the per-file gate and the
    // rewrite-echo suppression cannot diverge between the two.
    function scheduleFileEdit(file: string, kind: FileChangeKind) {
      const sig = contentSig(file)
      if (rewriteEcho.isEcho(file, sig)) {
        // The echo of a rewrite our own hooks just performed — content is
        // unchanged since the hook wrote it, so re-dispatching would run every
        // matching hook again.
        return
      }
      // Debounce: a burst of rapid edits resets the timer so one run happens
      // after the burst has quiesced, never between two edits.
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

    // Run the `surface` file hooks inline, while the tool result is still in
    // hand, and fold their findings into it. Inline is the point: the debounced
    // file.edited dispatch fires after the tool has already returned, so a hook
    // that wants the agent to read its output in this turn cannot wait for it.
    async function surfaceFindings(targets: string[], event: any): Promise<void> {
      const files = targets.map((target) => absolute(target))
      for (const { moduleDir, hooks } of manifests) {
        for (const hook of hooks) {
          if (!hook.surface || hook.event !== "file.edited" || !hook.run) continue
          const re = hook.match?.file
          // Every matching target, not the first: one patch can edit two UI
          // files, and both are scheduled as edited — running the hook for one
          // would silently skip the other.
          const matched = re ? files.filter((candidate) => new RegExp(re).test(candidate)) : files
          for (const file of matched) {
            const cmd = resolve(hook.run, { module: moduleDir, worktree: root, file })
            let out: { stdout: string; stderr: string; exitCode?: number }
            try {
              out = await runCommand(cmd, root)
            } catch (e) {
              logger.debug(`${hook.id} surface hook failed: ${e instanceof Error ? e.message : String(e)}`)
              continue
            }
            routeHookOutput(out, hook, root)
            if (hook.surface === "tool-result" && out.stdout.trim()) {
              if (!appendToToolResult(event?.result, out.stdout)) {
                logger.debug(`${hook.id}: tool result shape carried no text field — findings are in the log only`)
              }
            }
          }
        }
      }
    }

    // Non-blocking event dispatch (file.edited, session.*).
    async function dispatch(eventName: string, matchFile: string | undefined, vars: Record<string, string>, opts: { create?: boolean } = {}) {
      for (const { moduleDir, hooks } of manifests) {
        for (const hook of hooks) {
          if (hook.event !== eventName || !hook.run) continue
          // A surface hook is driven from the tool hook, where the result is
          // still mutable; running it here as well would run the command twice
          // per edit and log it twice.
          if (hook.surface) continue
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

    // Only the first event of each type is logged, so a dead stream is visible
    // in hooks.log without one line per delta.
    const seenEventTypes = new Set<string>()

    async function handleEvent(event: any) {
      const type = event?.type
      // V2 payloads live under `data`; V1 used `properties` (audit-01 FAIL-1 —
      // reading only `properties` made every V2 event look empty).
      const props = eventPayload(event)

      if (type && !seenEventTypes.has(type)) {
        seenEventTypes.add(type)
        logger.info(`event stream: first ${type}`)
      }

      if (type === "file.edited") {
        const file: string = props.file ? absolute(String(props.file)) : ""
        if (!file) {
          // A payload without a file means the event shape changed under us —
          // silently returning is what hid this failure for a whole audit.
          logger.warn("file.edited event carried no file path — ignoring")
          return
        }
        // file.edited carries no create-vs-edit flag; the companion watcher
        // event does. Buffer until it arrives so skipOnCreate hooks can avoid
        // normalizing a freshly-written file.
        kindResolver.onEdited(file, (kind) => scheduleFileEdit(file, kind))
      } else if (type === "filesystem.changed" || type === "file.watcher.updated") {
        // V2 publishes `filesystem.changed` (add|change|unlink); V1 published
        // `file.watcher.updated`. On a V2 host this is the only file event that
        // exists, so it dispatches on its own instead of only pairing.
        const file: string = props.file ? absolute(String(props.file)) : ""
        const kind: string = String(props.event ?? "")
        if (!file) {
          logger.warn(`${type} event carried no file path — ignoring`)
          return
        }
        if (kind === "unlink") {
          // A deleted file has nothing to format or index.
          kindResolver.onWatcher(file, "unlink")
          return
        }
        if (kind !== "add" && kind !== "change") return
        kindResolver.onWatcher(file, kind)
        scheduleFileEdit(file, kind)
      } else if (type === "session.created") {
        await dispatch("session.created", undefined, {})
      } else if (type === "session.idle") {
        const id = props.sessionID || props.info?.id || props.id || ""
        await dispatch("session.idle", undefined, { "session-id": id })
      } else if (type === "session.error" || type === "session.execution.failed") {
        // V2 names this `session.execution.failed`; V1 named it `session.error`.
        const id = props.sessionID || props.info?.id || props.id || ""
        const err = props.error?.message || props.error?.data?.message || props.message || ""
        await dispatch("session.error", undefined, { "session-id": id, error: String(err) })
      }
    }

    const controller = new AbortController()
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          try {
            await handleEvent(event)
          } catch (e) {
            logger.error(`event ${(event as any)?.type} failed: ${e instanceof Error ? e.message : String(e)}`)
          }
        }
      } catch (e) {
        // An abort is the normal unload path; anything else means the adapter is
        // now blind, which must be visible rather than looking like an idle
        // session (audit-01 FAIL-1).
        if (!controller.signal.aborted) {
          logger.error(`event subscription ended: ${e instanceof Error ? e.message : String(e)}`)
        }
      }
    })()

    await ctx.tool.hook("execute.before", async (event: any) => {
      const rawTool = String(event?.tool ?? "").toLowerCase()
      const args = event?.input
      // One normalised name for every downstream matcher: the host supplies the
      // tool name as the model sees it, and a manifest match must not depend on
      // its casing. canonicalToolName() is the single place that normalises it.
      const tool = canonicalToolName(rawTool, args)
      // Name the caller for tools that read the session's own state — the MCP
      // server's process cannot know which session invoked it.
      injectSessionId(tool, event?.sessionID, args)
      // Remember whether each write target exists, so the after-hook can tell a
      // create from an edit without a watcher event.
      for (const target of toolFileTargets(tool, args)) {
        const file = absolute(target)
        rememberPendingCreate(createKey(event?.sessionID, file), !existsSync(file))
      }
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
      const rawTool = String(event?.tool ?? "").toLowerCase()
      const tool = canonicalToolName(rawTool, event?.input)
      const args = event?.input

      // File writes: the V2 host publishes no file event for a tool-mediated
      // edit, so the edit event is derived here from the tool call itself
      // (audit-01 FAIL-1). Dispatching only on a completed call keeps a failed
      // or rejected write from reformatting a file the agent never changed.
      const targets = toolFileTargets(tool, args)
      if (targets.length > 0) {
        if (event?.status !== "error") {
          await surfaceFindings(targets, event)
          for (const target of targets) {
            const file = absolute(target)
            const key = createKey(event?.sessionID, file)
            const wasNew = pendingCreates.get(key) ?? false
            pendingCreates.delete(key)
            scheduleFileEdit(file, wasNew ? "add" : "change")
          }
        } else {
          for (const target of targets) pendingCreates.delete(createKey(event?.sessionID, absolute(target)))
        }
        // File tools never reach command.after —
        // commandString is empty for them.
        return
      }

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

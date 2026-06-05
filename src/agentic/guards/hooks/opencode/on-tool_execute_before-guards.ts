import type { Plugin } from "@opencode-ai/plugin"
import fs from "fs"
import path from "path"
import { createLogger } from "../../../../_shared/logger.ts"

const logger = createLogger({ module: "guards" });

function stripJsoncComments(text: string): string {
  const result: string[] = []
  let i = 0
  while (i < text.length) {
    if (text[i] === '"') {
      let j = i + 1
      while (j < text.length) {
        if (text[j] === "\\") { j += 2 }
        else if (text[j] === '"') { j += 1; break }
        else { j += 1 }
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

interface GuardRule { regex: string; message: string; agent?: string }

function loadConfig(configPath: string): GuardRule[] | null {
  try {
    const raw = fs.readFileSync(configPath, "utf8")
    const stripped = stripJsoncComments(raw)
    const parsed = JSON.parse(stripped)
    return Array.isArray(parsed?.guards) ? parsed.guards : null
  } catch (e) { logger.debug(`guards config load failed: ${e instanceof Error ? e.message : String(e)} — falling through`); return null; }
}

function evaluateGuards(command: string, guards: GuardRule[], currentAgent: string): { blocked: boolean; message?: string } {
  for (const g of guards) {
    if (typeof g !== "object" || !g?.regex || !g?.message) continue
    if (g.agent !== undefined && g.agent !== currentAgent) continue
    try {
      if (new RegExp(g.regex).test(command)) {
        return { blocked: true, message: g.message }
      }
    } catch (e) { logger.debug(`guards regex evaluation failed: ${e instanceof Error ? e.message : String(e)} — skipping rule`); }
  }
  return { blocked: false }
}

function readDevbotDir(directory: string): string {
  try {
    const cfgPath = path.join(directory, ".devbot.project.jsonc")
    if (!fs.existsSync(cfgPath)) return ".agents"
    const raw = fs.readFileSync(cfgPath, "utf8")
    const stripped = stripJsoncComments(raw)
    return JSON.parse(stripped)?.devbot_dir ?? ".agents"
  } catch { return ".agents" }
}

export const GuardsPlugin: Plugin = async ({ directory }) => {
  return {
    "tool.execute.before": async (input, output) => {
      try {
        const tool = String(input?.tool ?? "").toLowerCase()
        if (tool !== "bash" && tool !== "shell") return

        const args = output?.args
        if (!args || typeof args !== "object") return

        const command = (args as Record<string, unknown>).command
        if (typeof command !== "string" || !command) return

        const agent = process.env.OPENCODE_AGENT ?? ""

        // Load guards from global and project config
        const globalPath = process.env.DEVBOT_ROOT
          ? path.join(process.env.DEVBOT_ROOT, ".devbot.global.jsonc")
          : null
        const projectPath = path.join(directory, readDevbotDir(directory), "devbot.jsonc")

        const globalGuards = globalPath && fs.existsSync(globalPath) ? loadConfig(globalPath) : null
        const projectGuards = fs.existsSync(projectPath) ? loadConfig(projectPath) : null

        const merged = [...(globalGuards ?? []), ...(projectGuards ?? [])]
        if (merged.length === 0) return

        const result = evaluateGuards(command, merged, agent)
        if (result.blocked) {
          throw new Error(`[guards] Command blocked: ${result.message}`)
        }
      } catch (err) {
        if (err instanceof Error && err.message.startsWith("[guards]")) throw err
        logger.error(`[guards] Error: ${err instanceof Error ? err.message : String(err)}`)
      }
    },
  }
}

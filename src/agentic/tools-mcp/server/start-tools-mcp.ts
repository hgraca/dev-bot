#!/usr/bin/env bun

import * as fs from "node:fs";
import * as path from "node:path";

const PROJECT_DIR = process.env.TOOLS_MCP_PROJECT_DIR || process.cwd();

function getDevbotDir(): string {
  try {
    const configPath = path.join(PROJECT_DIR, ".devbot.project.jsonc");
    const raw = fs.readFileSync(configPath, "utf-8");
    // Strip JSONC comments
    const stripped = raw.replace(/\/\/.*$/gm, "").replace(/\/\*[\s\S]*?\*\//g, "");
    const config = JSON.parse(stripped);
    return config.devbot_dir || ".agents";
  } catch {
    return ".agents";
  }
}

const devbotDir = getDevbotDir();

const TOOLS_DIRS = [
  path.join(PROJECT_DIR, devbotDir, "tools"),
].filter((d) => {
  try { return fs.statSync(d).isDirectory(); } catch { return false; }
});

const SERVER_NAME = "devbot-tools";
const SERVER_VERSION = "0.2.0";

// Per-tool wall-clock bound. When the MCP client gives up waiting, nothing else
// stops the tool subprocess — a hung or slow tool (and its children, e.g.
// qmd/llama.cpp holding GPU memory) would keep running indefinitely (orphan).
const DEFAULT_TOOL_TIMEOUT_MS = 120_000;

function toolTimeoutMs(): number {
    const raw = Number(process.env.TOOLS_MCP_TIMEOUT_MS);
    return Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_TOOL_TIMEOUT_MS;
}

interface ToolDef {
  name: string;
  description: string;
  inputSchema: {
    type: "object";
    properties: Record<string, unknown>;
    required?: string[];
  };
  scriptPath: string;
}

async function runMcpMeta(scriptPath: string): Promise<{ name: string; description: string; parameters?: object } | null> {
  const proc = Bun.spawn(["bash", scriptPath, "mcp-meta"], {
    stdout: "pipe",
    stderr: "pipe",
  });

  const chunks: Uint8Array[] = [];
  const reader = proc.stdout.getReader();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
  }

  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    log(`mcp-meta failed for ${scriptPath} (exit ${exitCode})`);
    return null;
  }

  const totalLength = chunks.reduce((sum, c) => sum + c.length, 0);
  const joined = new Uint8Array(totalLength);
  let offset = 0;
  for (const c of chunks) { joined.set(c, offset); offset += c.length; }
  const raw = new TextDecoder().decode(joined).trim();

  try {
    const data = JSON.parse(raw);
    if (typeof data === "object" && data !== null && typeof data.name === "string") {
      return data;
    }
    log(`mcp-meta for ${scriptPath} returned JSON without a "name" field`);
  } catch {
    log(`mcp-meta for ${scriptPath} returned invalid JSON: ${raw.slice(0, 200)}`);
  }
  return null;
}

async function discoverTools(): Promise<ToolDef[]> {
  const tools: ToolDef[] = [];

  for (const toolsDir of TOOLS_DIRS) {
    let entries: string[];
    try { entries = fs.readdirSync(toolsDir); } catch { continue; }

    for (const entry of entries) {
      if (!entry.endsWith(".mcp.sh")) continue;
      const scriptPath = path.join(toolsDir, entry);

      let stat: fs.Stats;
      try {
        stat = fs.statSync(scriptPath);
        if (!stat.isFile()) continue;
      } catch { continue; }

      const meta = await runMcpMeta(scriptPath);

      if (meta && meta.name && meta.description) {
        tools.push({
          name: meta.name,
          description: meta.description,
          inputSchema: (meta.parameters as ToolDef["inputSchema"]) ?? { type: "object", properties: {} },
          scriptPath,
        });
      } else {
        log(`skipping ${entry}: mcp-meta missing name/description`);
      }
    }
  }

  if (tools.length === 0) {
    log(`WARNING: no tools discovered in ${TOOLS_DIRS.join(", ") || "(no tools dirs)"}`);
  } else {
    log(`discovered ${tools.length} tool(s)`);
  }

  return tools;
}

// Discovery is expensive (one mcp-meta subprocess per tool) and its result is
// stable for the server's lifetime, so it is memoized: the first request builds
// the list (and logs once), every later `tools/list` and `tools/call` reuses
// the cache. Without this, the server re-discovered and re-logged on every
// round-trip — log spam plus 12 subprocess spawns per call (audit-18 NOTE).
let toolsCache: ToolDef[] | null = null;

async function getTools(): Promise<ToolDef[]> {
  if (toolsCache === null) {
    toolsCache = await discoverTools();
  }
  return toolsCache;
}

function toMCPTool(tool: ToolDef) {
  return {
    name: tool.name,
    description: tool.description,
    inputSchema: tool.inputSchema,
  };
}

function sendJSON(data: unknown) {
  process.stdout.write(JSON.stringify(data) + "\n");
}

function log(msg: string) {
  // [YYYY-MM-DD HH:MM:SS] prefix — matches the shell _log_file format used
  // by the other dev-bot file logs (e.g. .agents/logs/graphify-mcp.log).
  const ts = new Date().toISOString().replace("T", " ").replace(/\.\d+Z$/, "")
  process.stderr.write(`[${ts}] [tools-mcp] ${msg}\n`)
}

function bufferToString(buf: Uint8Array[]): string {
  const totalLength = buf.reduce((sum, chunk) => sum + chunk.length, 0);
  const joined = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of buf) {
    joined.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder().decode(joined);
}

async function callTool(tool: ToolDef, args: Record<string, unknown>): Promise<string> {
  const scriptArgs: string[] = [];

  if (Array.isArray(args.args)) {
    scriptArgs.push(...args.args.map(String));
  }

  return new Promise((resolve, reject) => {
    const proc = Bun.spawn(["bash", tool.scriptPath, ...scriptArgs], {
      stdout: "pipe",
      stderr: "pipe",
      detached: true, // own process group so a timeout can kill the whole tree
    });

    const chunks: Uint8Array[] = [];
    const errChunks: Uint8Array[] = [];
    let timedOut = false;

    const killTree = (signal: "SIGTERM" | "SIGKILL") => {
      try {
        process.kill(-proc.pid, signal); // negative pid = whole group (detached)
      } catch {
        try {
          proc.kill(signal);
        } catch {
          /* already exited */
        }
      }
    };

    const timeoutMs = toolTimeoutMs();
    const termTimer = setTimeout(() => {
      timedOut = true;
      killTree("SIGTERM");
    }, timeoutMs);
    const killTimer = setTimeout(() => killTree("SIGKILL"), timeoutMs + 5_000);
    for (const timer of [termTimer, killTimer]) (timer as { unref?: () => void }).unref?.();

    const reader = proc.stdout.getReader();
    const errReader = proc.stderr.getReader();

    function readLoop() {
      reader.read().then(({ done, value }) => {
        if (done) return;
        chunks.push(value);
        readLoop();
      });
    }
    readLoop();

    function readErrLoop() {
      errReader.read().then(({ done, value }) => {
        if (done) return;
        errChunks.push(value);
        readErrLoop();
      });
    }
    readErrLoop();

    proc.exited.then((exitCode) => {
      clearTimeout(termTimer);
      clearTimeout(killTimer);
      const output = bufferToString(chunks);
      const errOutput = bufferToString(errChunks);

      if (timedOut) {
        reject(new Error(
          `Tool '${tool.name}' timed out after ${timeoutMs}ms and was killed.\n${errOutput || output}`.trim()
        ));
        return;
      }

      if (exitCode !== 0) {
        reject(new Error(
          `Script exited with code ${exitCode}\n${errOutput || output}`.trim()
        ));
      } else {
        resolve(output.trim() || `Tool '${tool.name}' completed successfully.`);
      }
    }).catch(reject);
  });
}

async function handleRequest(msg: string): Promise<void> {
  let req: { jsonrpc?: string; id?: unknown; method?: string; params?: Record<string, unknown> };
  try {
    req = JSON.parse(msg);
  } catch {
    log(`Failed to parse request: ${msg.slice(0, 200)}`);
    return;
  }

  if (!req || req.jsonrpc !== "2.0") return;

  const { id, method, params } = req;

  if (method === "initialize") {
    sendJSON({
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
      },
    });
    return;
  }

  if (method === "notifications/initialized") {
    return;
  }

  if (method === "tools/list") {
    const tools = await getTools();
    sendJSON({
      jsonrpc: "2.0",
      id,
      result: { tools: tools.map(toMCPTool) },
    });
    return;
  }

  if (method === "tools/call") {
    const toolName = params?.name as string | undefined;
    const toolArgs = (params?.arguments as Record<string, unknown>) ?? {};

    if (!toolName) {
      sendJSON({
        jsonrpc: "2.0",
        id,
        error: { code: -32602, message: "Missing tool name" },
      });
      return;
    }

    const tools = await getTools();
    const tool = tools.find((t) => t.name === toolName);
    if (!tool) {
      sendJSON({
        jsonrpc: "2.0",
        id,
        error: { code: -32601, message: `Unknown tool: ${toolName}` },
      });
      return;
    }

    try {
      const result = await callTool(tool, toolArgs);
      sendJSON({
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: result }],
        },
      });
    } catch (err) {
      sendJSON({
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: `Error: ${(err as Error).message}` }],
          isError: true,
        },
      });
    }
    return;
  }

  if (method === "ping") {
    sendJSON({ jsonrpc: "2.0", id, result: {} });
    return;
  }

  sendJSON({
    jsonrpc: "2.0",
    id,
    error: { code: -32601, message: `Method not found: ${method}` },
  });
}

async function main() {
  log(`Starting (project: ${PROJECT_DIR}, tools dirs: ${TOOLS_DIRS.join(", ") || "(none)"})`);

  const decoder = new TextDecoder();
  let buffer = "";

  const reader = Bun.stdin.stream().getReader();

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      await handleRequest(trimmed);
    }
  }
}

main().catch((err) => {
  log(`Fatal error: ${err.message}`);
  process.exit(1);
});

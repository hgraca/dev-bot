#!/usr/bin/env bun
/**
 * src/agentic/refactor/tools/refactor/refactor.ts
 * Authoritative logic for the refactor tool.
 *
 * The core is language-agnostic: it discovers `langs/<lang>/plugin.sh`, checks
 * the plugin declares the requested op, and dispatches `plan` / `apply` with a
 * JSON request on stdin and a JSON response on stdout. Adding a language means
 * adding a directory under `langs/` — this file never changes.
 *
 * See langs/README.md for the plugin contract.
 */

import * as fs from "node:fs";
import * as path from "node:path";

const VERSION = "0.1.0";

type Format = "markdown" | "json";

interface Args {
  format: Format;
  help: boolean;
  version: boolean;
  lang: string | null;
  op: string | null;
  klass: string | null;
  method: string | null;
  property: string | null;
  to: string | null;
  apply: boolean;
  force: boolean;
}

interface PluginMeta {
  lang: string;
  extensions: string[];
  ops: string[];
}

interface RefactorRequest {
  op: string;
  class: string | null;
  from: string;
  to: string;
  apply: boolean;
}

interface PluginResponse {
  ok: boolean;
  engine?: string;
  applied?: boolean;
  summary?: string;
  files?: string[];
  warnings?: string[];
  error?: string;
}

const USAGE = `refactor — deterministic, agent-callable refactoring

Usage:
  refactor --lang <lang> --op <rename-method|rename-class|rename-static-method|rename-property> \\
           [--class <FQCN>] [--method <old> | --property <old>] \\
           --to <new> [--apply] [--json] [--force]

Options:
  --lang <lang>  target language plugin (e.g. php)
  --op <op>      refactoring to perform
  --to <new>     new name
  --apply        write changes (default: dry-run plan only)
  --json         machine-readable output
  --force        proceed despite a dirty working tree
  --help, -h     show this help
  --version      show version
`;

function parse(argv: string[]): Args {
  const a: Args = {
    format: "markdown",
    help: false,
    version: false,
    lang: null,
    op: null,
    klass: null,
    method: null,
    property: null,
    to: null,
    apply: false,
    force: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = (): string | null => (i + 1 < argv.length ? argv[++i] : null);
    if (arg === "--json") a.format = "json";
    else if (arg === "--markdown") a.format = "markdown";
    else if (arg === "--help" || arg === "-h") a.help = true;
    else if (arg === "--version") a.version = true;
    else if (arg === "--apply") a.apply = true;
    else if (arg === "--force") a.force = true;
    else if (arg === "--lang") a.lang = next();
    else if (arg === "--op") a.op = next();
    else if (arg === "--class") a.klass = next();
    else if (arg === "--method") a.method = next();
    else if (arg === "--property") a.property = next();
    else if (arg === "--to") a.to = next();
  }
  return a;
}

function langsDir(): string {
  return (
    process.env.REFACTOR_LANGS_DIR ??
    path.join(import.meta.dir, "..", "..", "langs")
  );
}

async function runPlugin(
  dir: string,
  sub: string,
  request: unknown | null,
): Promise<{ code: number; stdout: string; stderr: string }> {
  const proc = Bun.spawn(["bash", path.join(dir, "plugin.sh"), sub], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });

  if (request !== null) proc.stdin.write(JSON.stringify(request));
  proc.stdin.end();

  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);

  return { code: await proc.exited, stdout, stderr };
}

async function readMeta(dir: string): Promise<PluginMeta | null> {
  const r = await runPlugin(dir, "meta", null);
  if (r.code !== 0) return null;
  try {
    const meta = JSON.parse(r.stdout) as PluginMeta;
    return meta && typeof meta.lang === "string" ? meta : null;
  } catch {
    return null;
  }
}

interface Plugin {
  dir: string;
  meta: PluginMeta;
}

async function discoverPlugins(): Promise<Map<string, Plugin>> {
  const plugins = new Map<string, Plugin>();
  const root = langsDir();
  if (!fs.existsSync(root)) return plugins;

  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const dir = path.join(root, entry.name);
    if (!fs.existsSync(path.join(dir, "plugin.sh"))) continue;

    const meta = await readMeta(dir);
    if (!meta) {
      process.stderr.write(
        `WARN: langs/${entry.name} exposes no valid meta — skipped\n`,
      );
      continue;
    }
    plugins.set(meta.lang, { dir, meta });
  }
  return plugins;
}

function render(res: PluginResponse, format: Format, op: string): string {
  if (format === "json") return `${JSON.stringify(res, null, 2)}\n`;

  const lines: string[] = [`## refactor: ${op}`, ""];
  lines.push(`**Engine:** ${res.engine ?? "unknown"}`);
  lines.push(`**Applied:** ${res.applied ? "yes" : "no"}`);
  lines.push("");
  if (res.summary) {
    lines.push(res.summary);
    lines.push("");
  }
  if (res.files && res.files.length > 0) {
    lines.push("### Files");
    for (const f of res.files) lines.push(`- ${f}`);
    lines.push("");
  }
  return `${lines.join("\n")}\n`;
}

async function main(): Promise<number> {
  const args = parse(process.argv.slice(2));

  if (args.version) {
    process.stdout.write(`refactor ${VERSION}\n`);
    return 0;
  }
  if (args.help) {
    process.stdout.write(USAGE);
    return 0;
  }

  if (!args.op) {
    process.stderr.write(`ERROR: --op is required\n${USAGE}`);
    return 1;
  }
  if (!args.to) {
    process.stderr.write("ERROR: --to is required\n");
    return 1;
  }

  const plugins = await discoverPlugins();
  const available = [...plugins.keys()].sort().join(", ");

  if (!args.lang) {
    process.stderr.write(
      `ERROR: --lang is required (available: ${available || "none"})\n`,
    );
    return 1;
  }
  const plugin = plugins.get(args.lang);
  if (!plugin) {
    process.stderr.write(
      `ERROR: unknown language '${args.lang}' (available: ${available || "none"})\n`,
    );
    return 1;
  }
  if (!plugin.meta.ops.includes(args.op)) {
    process.stderr.write(
      `ERROR: ${args.lang} does not support op '${args.op}' (supports: ${plugin.meta.ops.join(", ") || "none"})\n`,
    );
    return 1;
  }

  // The op-specific selector: a method/property name, or the class itself for a
  // class rename. The core stays op-agnostic; the plugin interprets `from`.
  const from = args.method ?? args.property ?? args.klass;
  if (!from) {
    process.stderr.write(
      "ERROR: one of --class, --method or --property is required\n",
    );
    return 1;
  }

  const request: RefactorRequest = {
    op: args.op,
    class: args.klass,
    from,
    to: args.to,
    apply: args.apply,
  };

  const result = await runPlugin(
    plugin.dir,
    args.apply ? "apply" : "plan",
    request,
  );

  if (result.code !== 0) {
    process.stderr.write(
      result.stderr ||
        `ERROR: plugin '${args.lang}' failed (exit ${result.code})\n`,
    );
    return 1;
  }

  let response: PluginResponse;
  try {
    response = JSON.parse(result.stdout) as PluginResponse;
  } catch {
    process.stderr.write(
      `ERROR: plugin '${args.lang}' returned invalid JSON\n`,
    );
    return 1;
  }

  if (!response.ok) {
    process.stderr.write(`ERROR: ${response.error ?? "refactor failed"}\n`);
    return 1;
  }

  for (const warning of response.warnings ?? []) {
    process.stderr.write(`WARN: ${warning}\n`);
  }

  process.stdout.write(render(response, args.format, args.op));
  return 0;
}

process.exit(await main());

#!/usr/bin/env bun
/**
 * src/agentic/refactor/tools/refactor/refactor.ts
 * Authoritative logic for the refactor tool.
 *
 * T2 skeleton: argument parsing, `--help` / `--version`. Operation dispatch
 * (T7) and the language-plugin seam (T3) land on top of this.
 */

const VERSION = "0.1.0";

type Format = "markdown" | "json";

interface Parsed {
  format: Format;
  help: boolean;
  version: boolean;
}

const USAGE = `refactor — deterministic, agent-callable refactoring

Usage:
  refactor --op <rename-method|rename-class|rename-static-method|rename-property> \\
           [--class <FQCN>] [--method <old> | --property <old>] \\
           --to <new> [--apply] [--json] [--force]

Options:
  --op <op>     refactoring to perform
  --to <new>    new name
  --apply       write changes (default: dry-run plan only)
  --json        machine-readable output
  --force       proceed despite a dirty working tree
  --help, -h    show this help
  --version     show version
`;

function parse(argv: string[]): Parsed {
  const p: Parsed = { format: "markdown", help: false, version: false };
  for (const arg of argv) {
    if (arg === "--json") p.format = "json";
    else if (arg === "--markdown") p.format = "markdown";
    else if (arg === "--help" || arg === "-h") p.help = true;
    else if (arg === "--version") p.version = true;
  }
  return p;
}

function main(): number {
  const args = parse(process.argv.slice(2));

  if (args.version) {
    process.stdout.write(`refactor ${VERSION}\n`);
    return 0;
  }

  if (args.help) {
    process.stdout.write(USAGE);
    return 0;
  }

  process.stderr.write("ERROR: no operation given\n");
  process.stderr.write(USAGE);
  return 1;
}

process.exit(main());

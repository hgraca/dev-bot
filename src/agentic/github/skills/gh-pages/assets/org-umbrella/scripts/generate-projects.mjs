#!/usr/bin/env node
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { collectProjects } from "./lib/collect.mjs";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outFile = path.join(repoRoot, "docs", "_data", "projects.json");
const org = process.env.UMBRELLA_ORG || "your-org";
const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;

function warn(message) {
  process.stderr.write(`WARN: ${message}\n`);
}

if (!token) {
  process.stderr.write("FATAL: no GitHub token — set GH_TOKEN or GITHUB_TOKEN\n");
  process.exit(1);
}

try {
  const projects = await collectProjects({ org, fetchFn: fetch, token, warn });
  await mkdir(path.dirname(outFile), { recursive: true });
  await writeFile(outFile, `${JSON.stringify(projects, null, 2)}\n`);
  process.stderr.write(`Wrote ${projects.length} project(s) for ${org} to docs/_data/projects.json\n`);
} catch (error) {
  process.stderr.write(`FATAL: ${error.message}\n`);
  process.exit(1);
}

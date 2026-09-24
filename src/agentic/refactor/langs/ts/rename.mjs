#!/usr/bin/env node
/**
 * ts-morph driver for the refactor tool's TypeScript plugin.
 *
 * Reads a refactor request as JSON on stdin and writes a response as JSON on
 * stdout, in the same shape the PHP plugin uses:
 *   {ok, engine, applied, summary, files, warnings}
 *
 * A dry run reports the declaration and every reference without saving. An apply
 * calls ts-morph's rename(), which is type-aware — the TypeScript compiler
 * resolves the symbol — and updates every reference across the project.
 */
import { Project } from "ts-morph";
import fs from "node:fs";
import path from "node:path";

const PROJECT_DIR = process.env.REFACTOR_PROJECT_DIR || "/app";
const ENGINE = process.env.REFACTOR_TS_ENGINE || "ts-morph";

function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => (data += chunk));
    process.stdin.on("end", () => resolve(data));
  });
}

function createProject() {
  const tsconfig = path.join(PROJECT_DIR, "tsconfig.json");
  if (fs.existsSync(tsconfig)) {
    return new Project({ tsConfigFilePath: tsconfig });
  }
  const project = new Project({ skipAddingFilesFromTsConfig: true });
  for (const root of ["src", "app"]) {
    const dir = path.join(PROJECT_DIR, root);
    if (fs.existsSync(dir)) {
      project.addSourceFilesAtPaths(path.join(dir, "**/*.{ts,tsx,js,jsx}"));
    }
  }
  return project;
}

function candidates(sourceFile) {
  return ["Class", "Interface", "Function", "TypeAlias", "Enum", "VariableDeclaration"];
}

function findDeclaration(project, name, file) {
  const files = file
    ? [project.getSourceFile(path.join(PROJECT_DIR, file))]
    : project.getSourceFiles();

  for (const sourceFile of files) {
    if (!sourceFile) continue;

    for (const kind of candidates(sourceFile)) {
      const getter = "get" + kind;
      const node = typeof sourceFile[getter] === "function" ? sourceFile[getter](name) : undefined;
      if (node) return node;
    }

    for (const container of [...sourceFile.getClasses(), ...sourceFile.getInterfaces()]) {
      const member = container.getMethod(name) || container.getProperty(name);
      if (member) return member;
    }
  }
  return null;
}

function relative(filePath) {
  return path.relative(PROJECT_DIR, filePath);
}

function fail(message) {
  process.stderr.write("ERROR: " + message + "\n");
  process.exitCode = 1;
  return 1;
}

async function main() {
  const request = JSON.parse((await readStdin()) || "{}");
  const from = request.from || "";
  const to = request.to || "";
  const file = request.file || null;
  const apply = Boolean(request.apply);

  if (!from || !to) {
    return fail("from and to are required");
  }

  const project = createProject();
  const node = findDeclaration(project, from, file);
  if (!node) {
    return fail("no declaration of '" + from + "' found" + (file ? " in " + file : ""));
  }

  const files = new Set([relative(node.getSourceFile().getFilePath())]);
  const references = node.findReferencesAsNodes().map((reference) => {
    const sourceFile = reference.getSourceFile();
    files.add(relative(sourceFile.getFilePath()));
    return { file: relative(sourceFile.getFilePath()), line: reference.getStartLineNumber() };
  });

  if (apply) {
    node.rename(to);
    await project.save();
  }

  const result = {
    ok: true,
    engine: ENGINE,
    applied: apply,
    summary: `${apply ? "Renamed" : "Would rename"} ${from} -> ${to} in ${files.size} file(s)`,
    files: [...files].sort(),
    warnings: [],
  };
  if (references.length) {
    result.references = references;
  }

  process.stdout.write(JSON.stringify(result) + "\n");
  return 0;
}

main().catch((error) => {
  process.stderr.write("ERROR: " + (error && error.message ? error.message : String(error)) + "\n");
  process.exit(1);
});

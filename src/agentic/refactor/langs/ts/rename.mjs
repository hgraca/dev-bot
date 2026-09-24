#!/usr/bin/env node
/**
 * ts-morph driver for the refactor tool's TypeScript plugin.
 *
 * Reads a refactor request as JSON on stdin and writes a response as JSON on
 * stdout, in the same shape the PHP plugin uses:
 *   {ok, engine, applied, summary, files, warnings}
 * plus optional extras: `references`, `string_references` (literal occurrences
 * the rename cannot reach) and `remaining_changes` (files still holding the old
 * name — where PHP counts the files that would still change).
 *
 * A dry run reports the declaration and every reference without saving. An apply
 * calls ts-morph's rename(), which is type-aware — the TypeScript compiler
 * resolves the symbol — and updates every reference across the project. That
 * rename is atomic, so there is nothing to re-verify within the apply: the
 * verification is a re-run, which reports `remaining_changes` when a reference
 * was left behind, and treats a declaration whose target is now declared as an
 * already-completed rename rather than an error.
 */
import { Project, SyntaxKind } from "ts-morph";
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

// The node kinds that carry literal text, and how to read each one. The template
// parts are the text segments of an interpolated template; JsxText is literal
// text inside JSX.
const LITERAL_READERS = new Map([
  [SyntaxKind.StringLiteral, (node) => node.getLiteralValue()],
  [SyntaxKind.NoSubstitutionTemplateLiteral, (node) => node.getLiteralValue()],
  [SyntaxKind.TemplateHead, (node) => node.getLiteralText()],
  [SyntaxKind.TemplateMiddle, (node) => node.getLiteralText()],
  [SyntaxKind.TemplateTail, (node) => node.getLiteralText()],
  [SyntaxKind.JsxText, (node) => node.getText()],
]);

// Literal occurrences of `name`. A reference held in a string is invisible to the
// type-aware rename, so it is reported rather than silently left behind. One
// traversal filtered by kind: getDescendantsOfKind rebuilds the whole descendant
// list on each call, so a pass per kind would walk every file six times.
function findStringReferences(project, name) {
  const hits = [];
  for (const sourceFile of project.getSourceFiles()) {
    const file = relative(sourceFile.getFilePath());
    for (const node of sourceFile.getDescendants()) {
      const read = LITERAL_READERS.get(node.getKind());
      if (!read) continue;
      const text = read(node);
      if (!text || !text.includes(name)) continue;
      hits.push({ file, line: node.getStartLineNumber(), text: text.trim() });
    }
  }
  return hits.sort((a, b) => (a.file === b.file ? a.line - b.line : a.file < b.file ? -1 : 1));
}

// Identifiers still named `name` — the residue of a rename that could not reach
// every reference. Restricted to `scope` when given: after an apply only the
// files the rename touched matter, and a same-named symbol elsewhere is not this
// rename's business.
function findResidualReferences(project, name, scope) {
  const files = new Set();
  for (const sourceFile of project.getSourceFiles()) {
    const file = relative(sourceFile.getFilePath());
    if (scope && !scope.has(file)) continue;
    for (const identifier of sourceFile.getDescendantsOfKind(SyntaxKind.Identifier)) {
      if (identifier.getText() === name) {
        files.add(file);
        break;
      }
    }
  }
  return [...files].sort();
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
    // A re-run after a rename: `from` is gone, but if the target is now declared
    // the rename happened, so report whatever still holds the old name rather
    // than claiming the symbol never existed. With neither name declared the
    // name was simply wrong, which stays an error.
    if (!findDeclaration(project, to, null)) {
      return fail("no declaration of '" + from + "' found" + (file ? " in " + file : ""));
    }
    const residual = findResidualReferences(project, from, null);
    const result = {
      ok: true,
      engine: ENGINE,
      applied: false,
      summary: residual.length
        ? `'${from}' is renamed to '${to}', but ${residual.length} file(s) still reference '${from}'`
        : `'${from}' is already renamed to '${to}' — nothing left to do`,
      files: [],
      warnings: [],
    };
    if (residual.length) {
      result.remaining_changes = residual.length;
    }
    process.stdout.write(JSON.stringify(result) + "\n");
    return 0;
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

  const stringReferences = findStringReferences(project, from);
  if (stringReferences.length) {
    result.string_references = stringReferences;
  }

  process.stdout.write(JSON.stringify(result) + "\n");
  return 0;
}

main().catch((error) => {
  process.stderr.write("ERROR: " + (error && error.message ? error.message : String(error)) + "\n");
  process.exit(1);
});

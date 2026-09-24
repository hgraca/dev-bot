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

// The plural getters that expose a source file's top-level declarations, and how
// to read each one's name.
const DECLARATION_KINDS = [
  ["getClasses", (node) => node.getName()],
  ["getInterfaces", (node) => node.getName()],
  ["getFunctions", (node) => node.getName()],
  ["getTypeAliases", (node) => node.getName()],
  ["getEnums", (node) => node.getName()],
  ["getVariableDeclarations", (node) => node.getName()],
];

// The `--kind` values a caller can target, mapped to the node kinds each selects —
// a family, because a class member and its interface counterpart are different
// node kinds (`method` is both MethodDeclaration and MethodSignature).
const KINDS_BY_FLAG = new Map([
  ["class", [SyntaxKind.ClassDeclaration]],
  ["interface", [SyntaxKind.InterfaceDeclaration]],
  ["function", [SyntaxKind.FunctionDeclaration]],
  ["type", [SyntaxKind.TypeAliasDeclaration]],
  ["enum", [SyntaxKind.EnumDeclaration]],
  ["variable", [SyntaxKind.VariableDeclaration]],
  ["method", [SyntaxKind.MethodDeclaration, SyntaxKind.MethodSignature]],
  ["property", [SyntaxKind.PropertyDeclaration, SyntaxKind.PropertySignature]],
]);

// The nodes whose direct children are declarations: the file itself plus each
// namespace/module body. Deliberately not a full descendant walk — a declaration
// inside a function shadows rather than competes, and counting every local would
// make common names ambiguous.
function declarationScopes(sourceFile) {
  const scopes = [sourceFile];
  for (const module of sourceFile.getDescendantsOfKind(SyntaxKind.ModuleDeclaration)) {
    const body = module.getBody();
    if (body) scopes.push(body);
  }
  return scopes;
}

// Every declaration of `name` in the project, or in `file` when given, of the
// node kind `kind` selects (every kind when it is omitted). A list, because more
// than one is ambiguous: renaming an arbitrary one would touch the wrong symbol,
// so the caller is asked to pick with --file or --kind.
function findDeclarations(project, name, file, kind) {
  const files = file
    ? [project.getSourceFile(path.join(PROJECT_DIR, file))]
    : project.getSourceFiles();

  const found = [];
  for (const sourceFile of files) {
    if (!sourceFile) continue;

    for (const scope of declarationScopes(sourceFile)) {
      for (const [getter, read] of DECLARATION_KINDS) {
        for (const node of scope[getter]()) {
          if (read(node) === name) found.push(node);
        }
      }

      for (const container of [...scope.getClasses(), ...scope.getInterfaces()]) {
        for (const member of [...container.getMethods(), ...container.getProperties()]) {
          if (member.getName() === name) found.push(member);
        }
      }
    }
  }

  const unique = [...new Set(found)];
  return kind ? unique.filter((node) => KINDS_BY_FLAG.get(kind).includes(node.getKind())) : unique;
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
// every reference. Restricted to `scope` when given (the request's --file): a
// rename asked to touch one file must not report the same name elsewhere as its
// residue.
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

// Move a source file into an existing folder, rewriting its own imports and every
// importer's path. SourceFile.move() does the rewriting; this adds the contract's
// destination check and the report.
async function moveFile(project, file, to, apply) {
  if (!file || !to) {
    return fail("file and to (the destination folder) are required");
  }

  const source = project.getSourceFile(path.join(PROJECT_DIR, file));
  if (!source) {
    return fail("no such file: " + file);
  }

  const destination = path.join(PROJECT_DIR, to);
  if (!fs.existsSync(destination) || !fs.statSync(destination).isDirectory()) {
    return fail("no such destination folder: " + to);
  }

  const target = path.join(destination, path.basename(file));
  // move() returns early when the path is unchanged, so a same-folder move would
  // otherwise report success without having done anything.
  if (path.resolve(target) === path.resolve(source.getFilePath())) {
    return fail(`'${file}' is already in '${to}'`);
  }

  // Report from the literals move() acts on — the only set that matches what
  // changes. move() rewrites relative specifiers only, so a non-relative one (a
  // tsconfig paths alias) survives the move and is named rather than counted as
  // updated. Collected before the move: afterwards the rewritten specifiers no
  // longer resolve to the moved file.
  const referencing = source.getReferencingLiteralsInOtherSourceFiles();
  const rewritten = referencing.filter((literal) => literal.getLiteralText().startsWith("."));
  const importers = [
    ...new Set(rewritten.map((literal) => relative(literal.getSourceFile().getFilePath()))),
  ];
  const unrewritten = referencing
    .filter((literal) => !literal.getLiteralText().startsWith("."))
    .map(
      (literal) =>
        `${relative(literal.getSourceFile().getFilePath())}:${literal.getStartLineNumber()}: '${literal.getLiteralText()}' is not a relative specifier and was not rewritten`,
    );

  source.move(target);
  if (apply) {
    await project.save();
  }

  process.stdout.write(
    JSON.stringify({
      ok: true,
      engine: ENGINE,
      applied: apply,
      summary: `${apply ? "Moved" : "Would move"} ${file} -> ${relative(target)} (${importers.length} importer(s) updated)`,
      files: [relative(target), ...importers].sort(),
      warnings: unrewritten,
    }) + "\n",
  );
  return 0;
}

async function main() {
  const request = JSON.parse((await readStdin()) || "{}");
  const op = request.op || "rename-symbol";
  const from = request.from || "";
  const to = request.to || "";
  const file = request.file || null;
  const kind = request.kind || null;
  const apply = Boolean(request.apply);

  if (op !== "rename-symbol" && op !== "move-file") {
    return fail(`unsupported op '${op}' (expected rename-symbol|move-file)`);
  }

  const project = createProject();

  if (op === "move-file") {
    return moveFile(project, file, to, apply);
  }

  if (!from || !to) {
    return fail("from and to are required");
  }
  if (kind && !KINDS_BY_FLAG.has(kind)) {
    return fail(`unknown --kind '${kind}' (expected ${[...KINDS_BY_FLAG.keys()].join("|")})`);
  }

  const declarations = findDeclarations(project, from, file, kind);

  // Several declarations of the same name: picking one silently would rename the
  // wrong symbol, so name the candidates and let the caller choose.
  if (declarations.length > 1) {
    const listing = declarations
      .map((node) => `  ${relative(node.getSourceFile().getFilePath())}:${node.getStartLineNumber()}`)
      .sort()
      .join("\n");
    return fail(
      `'${from}' is declared in ${declarations.length} places — pass --file or --kind to pick one:\n${listing}`,
    );
  }

  const node = declarations[0];
  if (!node) {
    // A re-run after a rename: `from` is gone, but if the target is now declared
    // the rename happened, so report whatever still holds the old name rather
    // than claiming the symbol never existed. With neither name declared the
    // name was simply wrong, which stays an error.
    if (findDeclarations(project, to, null, kind).length === 0) {
      return fail("no declaration of '" + from + "' found" + (file ? " in " + file : ""));
    }
    const residual = findResidualReferences(project, from, file ? new Set([file]) : null);
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

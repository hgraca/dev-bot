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
import { Project, Node, Scope, SyntaxKind } from "ts-morph";
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

// True when a receiver resolves to the class itself — through a plain, aliased or
// namespace import. A string comparison cannot see through an alias, so the
// compiler's own resolution is used.
function resolvesToClass(node, cls) {
  const symbol = node.getSymbol();
  const declarations = [
    ...(symbol?.getDeclarations() ?? []),
    ...(symbol?.getAliasedSymbol?.()?.getDeclarations() ?? []),
    ...(node.getType()?.getSymbol()?.getDeclarations() ?? []),
  ];
  return declarations.includes(cls);
}

// Whether `node` sits inside `ancestor`.
function isInside(node, ancestor) {
  for (let parent = node.getParent(); parent; parent = parent.getParent()) {
    if (parent === ancestor) return true;
  }
  return false;
}

// What the member's body reaches on its own class, read while the member still
// lives in its module so every reference resolves: a reference to another member
// keeps working once the class is in scope, while one to anything else declared
// beside the class does not travel with the member. The member's references to
// itself are handled at the paste, by name, so they need nothing in scope.
function bodyDependencies(member, owner, from) {
  let keptRefs = 0;
  for (const access of member.getDescendantsOfKind(SyntaxKind.PropertyAccessExpression)) {
    if (!resolvesToClass(access.getExpression(), owner)) continue;
    if (access.getName() !== from) keptRefs += 1;
  }

  const foreign = new Set();
  for (const identifier of member.getDescendantsOfKind(SyntaxKind.Identifier)) {
    for (const declaration of identifier.getSymbol()?.getDeclarations() ?? []) {
      if (declaration === owner) continue;
      if (declaration.getSourceFile() !== owner.getSourceFile()) continue;
      if (isInside(declaration, owner)) continue;
      foreign.add(identifier.getText());
    }
  }
  return { keptRefs, foreign: [...foreign] };
}

// The moved body's references to the member itself, repointed at the new class:
// `Old.m` cannot survive the member's departure.
function rewriteSelfReferences(pasted, name, klass, to) {
  for (const access of pasted.getDescendantsOfKind(SyntaxKind.PropertyAccessExpression)) {
    if (access.getName() !== name) continue;
    if (access.getExpression().getText() === klass) access.getExpression().replaceWithText(to);
  }
}

// Move a class member to another class. A static member's receiver is the class
// itself, so its call sites can be repointed; an instance member's receiver is
// whatever owns the object, which this tool cannot supply, so that case refuses
// and names where the member is used.
async function moveMember(project, klass, from, to, file, apply) {
  if (!klass || !from || !to) {
    return fail("class, from and to are required");
  }

  const owners = findDeclarations(project, klass, file, "class");
  if (owners.length === 0) {
    return fail(`no class '${klass}' found${file ? " in " + file : ""}`);
  }
  if (owners.length > 1) {
    const listing = owners
      .map((node) => `  ${relative(node.getSourceFile().getFilePath())}:${node.getStartLineNumber()}`)
      .sort()
      .join("\n");
    return fail(`'${klass}' is declared in ${owners.length} places — pass --file to pick one:\n${listing}`);
  }
  const owner = owners[0];

  // A bare class name can be declared in several modules; picking one silently
  // would move the member into the wrong class.
  const targets = findDeclarations(project, to, null, "class");
  if (targets.length === 0) {
    return fail(`no class '${to}' found`);
  }
  if (targets.length > 1) {
    const listing = targets
      .map((node) => `  ${relative(node.getSourceFile().getFilePath())}:${node.getStartLineNumber()}`)
      .sort()
      .join("\n");
    return fail(`target class '${to}' is declared in ${targets.length} places:\n${listing}`);
  }
  const target = targets[0];

  // The member getters take no name argument, so the name filter is explicit. A
  // name resolving to more than one member (a get/set pair) is ambiguous.
  const members = [
    ...owner.getMethods(),
    ...owner.getProperties(),
    ...owner.getGetAccessors(),
    ...owner.getSetAccessors(),
  ].filter((member) => member.getName() === from);

  if (members.length === 0) {
    return fail(`no member '${from}' in class '${klass}'`);
  }
  if (members.length > 1) {
    const listing = members.map((member) => `  ${member.getKindName()}`).join("\n");
    return fail(`'${from}' resolves to ${members.length} members in '${klass}':\n${listing}`);
  }
  const member = members[0];

  if (!member.isStatic()) {
    const uses = member
      .findReferencesAsNodes()
      .map((ref) => `  ${relative(ref.getSourceFile().getFilePath())}:${ref.getStartLineNumber()}`)
      .sort()
      .join("\n");
    return fail(
      `'${klass}.${from}' is not static — its receiver would need a new owner${uses ? ":\n" + uses : ""}`,
    );
  }

  // Collected before the move, and only from outside the member: a reference the
  // member's own body makes is not a call site to repoint, and its node is
  // forgotten once the member is removed.
  const receivers = member
    .findReferencesAsNodes()
    .filter((ref) => !isInside(ref, member))
    .map((ref) => (Node.isPropertyAccessExpression(ref.getParent()) ? ref.getParent().getExpression() : null))
    .filter(Boolean);

  const warnings = [];
  const rewritable = [];
  for (const receiver of receivers) {
    // A static call's receiver is the class, however it is named locally — a
    // plain, aliased or namespace import all resolve to the same declaration.
    if (resolvesToClass(receiver, owner)) {
      rewritable.push(receiver);
    } else {
      warnings.push(
        `${relative(receiver.getSourceFile().getFilePath())}:${receiver.getStartLineNumber()}: receiver '${receiver.getText()}' does not resolve to '${klass}' and was not rewritten`,
      );
    }
  }

  const body = bodyDependencies(member, owner, from);
  for (const name of body.foreign) {
    warnings.push(
      `${klass}.${from}: the body references '${name}', declared beside the class, which does not travel with the member`,
    );
  }

  const touched = new Set(rewritable.map((receiver) => relative(receiver.getSourceFile().getFilePath())));
  const files = new Set([
    relative(owner.getSourceFile().getFilePath()),
    relative(target.getSourceFile().getFilePath()),
    ...receivers.map((receiver) => relative(receiver.getSourceFile().getFilePath())),
  ]);

  if (apply) {
    // addMember indents the pasted text itself, and formatText would reformat
    // every member of the destination class, so the moved text is re-based here.
    project.manipulationSettings.set({ indentationText: destinationIndent(target) });
    const pasted = target.addMember(rebase(memberText(member), member, target));
    member.remove();

    // A body that still reaches another member of its old class needs that class
    // in scope; its references to itself follow the member.
    if (body.keptRefs > 0) {
      const collision = addNamedImport(
        target.getSourceFile(),
        klass,
        specifierFor(target.getSourceFile(), owner.getSourceFile()),
      );
      if (collision) warnings.push(collision);
    }
    rewriteSelfReferences(pasted, from, klass, to);

    for (const receiver of rewritable) {
      const sourceFile = receiver.getSourceFile();
      const namespaceBinding = Node.isPropertyAccessExpression(receiver) ? rootBinding(receiver) : null;
      receiver.replaceWithText(to);
      // A namespace import that existed only to reach the class is now unused.
      if (namespaceBinding) {
        pruneUnusedImport(sourceFile, namespaceBinding);
      }
    }

    maintainImports(project, owner, target, files, touched, klass, to, warnings);

    await project.save();
  }

  process.stdout.write(
    JSON.stringify({
      ok: true,
      engine: ENGINE,
      applied: apply,
      summary: `${apply ? "Moved" : "Would move"} static ${klass}.${from} -> ${to}.${from} (${rewritable.length} call site(s) rewritten)`,
      files: [...files].sort(),
      warnings,
    }) + "\n",
  );
  return 0;
}

// The whitespace a node's line carries before it, or "" when that span is not
// whitespace — a member sharing its line with the class opening has no indent of
// its own to read.
function leadingIndent(node) {
  const text = node.getSourceFile().getFullText();
  const lineStart = text.lastIndexOf("\n", node.getStart()) + 1;
  const prefix = text.slice(lineStart, node.getStart());
  return /^[ \t]*$/.test(prefix) ? prefix : "";
}

// The indentation the destination class's own members use. A one-line or empty
// class offers no sibling to read, so two spaces stands in.
function destinationIndent(cls) {
  const anchor = [...cls.getMethods(), ...cls.getProperties()][0];
  return (anchor && leadingIndent(anchor)) || "  ";
}

// The member's full text, docblock included, minus the newline its own line
// starts with — getFullText() would otherwise paste as a leading blank line.
function memberText(member) {
  return member.getFullText().replace(/^\s*\n/, "");
}

// How many times `unit` prefixes the line.
function indentDepth(line, unit) {
  let depth = 0;
  while (line.startsWith(unit, depth * unit.length)) depth += 1;
  return depth;
}

// Re-base a member's text onto the destination's indentation unit. addMember adds
// one level to every line, so each line is emitted one level shallower than it
// should land — and in the destination's unit, so a tab-indented class does not
// receive a space-indented body. A docblock's own lines carry the same offset, so
// there is no first-line special case. Only the moved text is touched; formatText
// would rewrite every member of the class.
function rebase(text, member, target) {
  const from = leadingIndent(member);
  const to = destinationIndent(target);
  if (!from) return text;
  return text
    .split("\n")
    .map((line) => {
      const depth = indentDepth(line, from);
      return depth === 0 ? line : to.repeat(depth - 1) + line.slice(depth * from.length);
    })
    .join("\n");
}

// Point each affected file's imports at the destination class. A file keeps the
// old class's import while it still refers to the class for another reason; only
// a file whose last reference was a moved call site drops it. The destination is
// imported only where a receiver was rewritten, so no file gains an unused import.
function maintainImports(project, owner, target, files, touched, oldName, newName, warnings) {
  const targetFile = relative(target.getSourceFile().getFilePath());
  // The import specifier is itself a reference, so counting it would keep every
  // import alive and nothing would ever be dropped.
  const stillUsed = new Set(
    owner
      .findReferencesAsNodes()
      .filter((ref) => !Node.isImportSpecifier(ref.getParent()))
      .map((ref) => relative(ref.getSourceFile().getFilePath())),
  );

  for (const file of files) {
    const sourceFile = project.getSourceFile(path.join(PROJECT_DIR, file));
    if (!sourceFile) continue;

    if (!stillUsed.has(file)) {
      dropNamedImport(sourceFile, oldName);
    }
    // The destination class needs no import in its own file.
    if (touched.has(file) && file !== targetFile) {
      const collision = addNamedImport(sourceFile, newName, specifierFor(sourceFile, target.getSourceFile()));
      if (collision) warnings.push(collision);
    }
  }
}

// The module specifier that reaches `toFile` from `fromFile`, extensionless and
// relative — what TypeScript's own import rewriting produces.
function specifierFor(fromFile, toFile) {
  const relativePath = path.relative(path.dirname(fromFile.getFilePath()), toFile.getFilePath());
  const withoutExtension = relativePath.replace(/\.[^.]+$/, "").split(path.sep).join("/");
  return withoutExtension.startsWith(".") ? withoutExtension : "./" + withoutExtension;
}

// Remove one named binding from a file's imports, and the whole declaration when
// it was the last thing in it.
function dropNamedImport(sourceFile, name) {
  for (const declaration of sourceFile.getImportDeclarations()) {
    const specifier = declaration.getNamedImports().find((named) => named.getName() === name);
    if (!specifier) continue;
    specifier.remove();
    if (
      declaration.getNamedImports().length === 0 &&
      !declaration.getDefaultImport() &&
      !declaration.getNamespaceImport()
    ) {
      declaration.remove();
    }
    return;
  }
}

// Whether the file's default or namespace imports already bind a local name.
function isNameBound(sourceFile, name) {
  return sourceFile.getImportDeclarations().some((declaration) => {
    return declaration.getDefaultImport()?.getText() === name || declaration.getNamespaceImport()?.getText() === name;
  });
}

// The local binding a receiver was written through: `Old` is its own binding,
// while `lib.Old` is reached through `lib`.
function rootBinding(receiver) {
  let node = receiver;
  while (Node.isPropertyAccessExpression(node)) node = node.getExpression();
  return Node.isIdentifier(node) ? node.getText() : null;
}

// Drop a namespace import whose local name the rewrite left with nothing to
// reach — the replace took the only expression that used it.
function pruneUnusedImport(sourceFile, localName) {
  for (const declaration of sourceFile.getImportDeclarations()) {
    const namespace = declaration.getNamespaceImport();
    if (!namespace || namespace.getText() !== localName) continue;
    const stillUsed = sourceFile
      .getDescendantsOfKind(SyntaxKind.Identifier)
      .some(
        (identifier) =>
          identifier.getText() === localName && !identifier.getFirstAncestorByKind(SyntaxKind.ImportDeclaration),
      );
    if (stillUsed) continue;
    declaration.remove();
    return;
  }
}

// Bind `name` to the destination class in `sourceFile`, unless the file already
// binds that local name — a duplicate binding is a compile error, so it is
// reported instead of added. Returns a warning message, or null.
function addNamedImport(sourceFile, name, moduleSpecifier) {
  const declarations = sourceFile.getImportDeclarations();
  if (declarations.some((declaration) => declaration.getNamedImports().some((named) => named.getName() === name))) {
    return null;
  }
  if (isNameBound(sourceFile, name)) {
    return `${relative(sourceFile.getFilePath())}: '${name}' is already bound in the file and was not imported`;
  }
  const sameModule = declarations.find((declaration) => declaration.getModuleSpecifierValue() === moduleSpecifier);
  if (sameModule) {
    sameModule.addNamedImport(name);
    return null;
  }
  sourceFile.addImportDeclaration({ namedImports: [name], moduleSpecifier });
  return null;
}

// Every class in the project, including ones declared inside a namespace body.
function allClasses(project) {
  const classes = [];
  for (const sourceFile of project.getSourceFiles()) {
    for (const scope of declarationScopes(sourceFile)) {
      classes.push(...scope.getClasses());
    }
  }
  return classes;
}

// A class's members as one unit each: methods and properties on their own, and a
// get/set pair together — TypeScript gives a pair one accessibility, so narrowing
// only half of it would not compile.
function memberUnits(cls) {
  const units = [];
  const accessors = new Map();
  for (const accessor of [...cls.getGetAccessors(), ...cls.getSetAccessors()]) {
    const name = accessor.getName();
    if (!accessors.has(name)) {
      const unit = [];
      accessors.set(name, unit);
      units.push(unit);
    }
    accessors.get(name).push(accessor);
  }
  // A method carries every signature it overloads: TypeScript requires them all to
  // share one accessibility, so narrowing the body alone would not compile.
  units.push(...cls.getMethods().map((method) => [method, ...method.getOverloads()]));
  units.push(...cls.getProperties().map((property) => [property]));
  // A constructor parameter property is a class member too, though getProperties()
  // does not list it.
  for (const constructor of cls.getConstructors()) {
    for (const parameter of constructor.getParameters()) {
      if (parameter.isParameterProperty()) units.push([parameter]);
    }
  }
  return units;
}

// Narrow a class's public members to private where nothing but the class itself
// refers to them; with no class named, every class in the project is swept. A
// member a subclass or another module reaches is left alone — the compiler
// resolves those references, and a narrowed member would stop compiling.
async function privatizeMembers(project, klass, file, apply) {
  let classes;
  if (klass) {
    classes = findDeclarations(project, klass, file, "class");
    if (classes.length === 0) {
      return fail(`no class '${klass}' found${file ? " in " + file : ""}`);
    }
    if (classes.length > 1) {
      const listing = classes
        .map((node) => `  ${relative(node.getSourceFile().getFilePath())}:${node.getStartLineNumber()}`)
        .sort()
        .join("\n");
      return fail(`'${klass}' is declared in ${classes.length} places — pass --file to pick one:\n${listing}`);
    }
  } else {
    classes = allClasses(project);
  }

  const warnings = [];
  const files = new Set();
  let narrowed = 0;

  for (const cls of classes) {
    const where = relative(cls.getSourceFile().getFilePath());
    let inClass = 0;

    for (const unit of memberUnits(cls)) {
      // Only a public member can be narrowed: a protected one is an extension
      // contract, and a private one is already there.
      if (unit.some((member) => member.getScope() !== Scope.Public)) continue;

      // Every declaration of the member has to sit in this class. A declaration
      // outside it — a merged interface's signature — would stay public while the
      // class half was narrowed.
      const declarations = unit.flatMap((member) => member.getSymbol()?.getDeclarations() ?? []);
      if (declarations.some((declaration) => !isInside(declaration, cls))) continue;

      const references = unit.flatMap((member) => member.findReferencesAsNodes());
      if (references.some((reference) => !isInside(reference, cls))) continue;

      // Unused is not the same as used only here, so it is named as well — with
      // the caveat that a reference the compiler cannot resolve is not a reference
      // it reports.
      if (references.length === 0) {
        warnings.push(
          `${where}: '${cls.getName()}.${unit[0].getName()}' has no references in the project (dynamic access is not detected)`,
        );
      }
      if (apply) {
        for (const member of unit) member.setScope(Scope.Private);
      }
      inClass += 1;
    }

    if (inClass > 0) {
      files.add(where);
      narrowed += inClass;
      // The reference check only sees this project, so an exported class's public
      // surface is not the whole story.
      if (cls.isExported()) {
        warnings.push(`${where}: '${cls.getName()}' is exported, so its public surface may be consumed outside the project`);
      }
    }
  }

  if (apply) {
    await project.save();
  }

  process.stdout.write(
    JSON.stringify({
      ok: true,
      engine: ENGINE,
      applied: apply,
      summary: `${apply ? "Made" : "Would make"} ${narrowed} member(s) private in ${files.size} class file(s)`,
      files: [...files].sort(),
      warnings,
    }) + "\n",
  );
  return 0;
}

// The function-like nodes whose body is a scope of its own: a declaration inside
// one is a local, while a module-level one belongs to the module's surface.
const FUNCTION_LIKES = new Set([
  SyntaxKind.FunctionDeclaration,
  SyntaxKind.FunctionExpression,
  SyntaxKind.ArrowFunction,
  SyntaxKind.MethodDeclaration,
  SyntaxKind.Constructor,
  SyntaxKind.GetAccessor,
  SyntaxKind.SetAccessor,
]);

// Initialisers whose evaluation can only produce a value, so dropping the binding
// drops nothing else. A call, `new`, `await` or an assignment can, so a binding
// holding one is reported instead of removed.
const PURE_INITIALIZERS = new Set([
  SyntaxKind.NumericLiteral,
  SyntaxKind.StringLiteral,
  SyntaxKind.NoSubstitutionTemplateLiteral,
  SyntaxKind.TrueKeyword,
  SyntaxKind.FalseKeyword,
  SyntaxKind.NullKeyword,
  SyntaxKind.ArrayLiteralExpression,
  SyntaxKind.ObjectLiteralExpression,
  SyntaxKind.ArrowFunction,
  SyntaxKind.FunctionExpression,
  SyntaxKind.Identifier,
]);

function isInsideFunctionLike(node) {
  for (let parent = node.getParent(); parent; parent = parent.getParent()) {
    if (FUNCTION_LIKES.has(parent.getKind())) return true;
  }
  return false;
}

// A declaration that is a loop's own binding: it cannot be dropped on its own.
function isLoopBinding(declaration) {
  const owner = declaration.getParent()?.getParent()?.getKind();
  return (
    owner === SyntaxKind.ForStatement || owner === SyntaxKind.ForOfStatement || owner === SyntaxKind.ForInStatement
  );
}

function initializerIsPure(declaration) {
  const initializer = declaration.getInitializer();
  return !initializer || PURE_INITIALIZERS.has(initializer.getKind());
}

// Drop the declarations in one file that nothing refers to and whose initialiser
// cannot do anything else. A module-level declaration is left alone — it is part
// of the module's own surface — and a `_`-prefixed name is the convention for a
// binding kept on purpose.
async function removeUnusedLocals(project, file, apply) {
  if (!file) {
    return fail("file is required");
  }
  const sourceFile = project.getSourceFile(path.join(PROJECT_DIR, file));
  if (!sourceFile) {
    return fail("no such file: " + file);
  }

  const warnings = [];
  const removable = [];
  const statements = new Map();

  for (const declaration of sourceFile.getDescendantsOfKind(SyntaxKind.VariableDeclaration)) {
    if (declaration.findReferencesAsNodes().length > 0) continue;
    if (!isInsideFunctionLike(declaration)) continue;
    if (declaration.getName().startsWith("_")) continue;
    if (isLoopBinding(declaration)) continue;

    if (!initializerIsPure(declaration)) {
      warnings.push(
        `${file}: '${declaration.getName()}' has no references, but its initialiser may have side effects and it was kept`,
      );
      continue;
    }

    removable.push(declaration);
    const statement = declaration.getVariableStatement();
    if (statement) {
      const entry = statements.get(statement) ?? { total: statement.getDeclarations().length, removable: 0 };
      entry.removable += 1;
      statements.set(statement, entry);
    }
  }

  if (apply) {
    // Decided from the pre-removal counts: as declarators are dropped a statement
    // shrinks, so re-reading its length would start matching by accident and take
    // a declarator that is still in use with it.
    const wholeStatements = new Set();
    const individually = [];
    for (const declaration of removable) {
      const statement = declaration.getVariableStatement();
      const entry = statement && statements.get(statement);
      if (entry && entry.total === entry.removable) {
        wholeStatements.add(statement);
      } else {
        individually.push(declaration);
      }
    }

    for (const declaration of individually) {
      declaration.remove();
    }
    for (const statement of wholeStatements) {
      statement.remove();
    }
    await project.save();
  }

  process.stdout.write(
    JSON.stringify({
      ok: true,
      engine: ENGINE,
      applied: apply,
      summary: `${apply ? "Removed" : "Would remove"} ${removable.length} unused local(s) from ${file}`,
      files: removable.length > 0 ? [file] : [],
      warnings,
    }) + "\n",
  );
  return 0;
}

// The function-likes whose parameter list a caller's argument count constrains. An
// overload signature declares no body; its parameters travel with the
// implementation's, which reaches them through getOverloads().
function parameterisedFunctions(sourceFile) {
  const nodes = [
    ...sourceFile.getDescendantsOfKind(SyntaxKind.FunctionDeclaration),
    ...sourceFile.getDescendantsOfKind(SyntaxKind.FunctionExpression),
    ...sourceFile.getDescendantsOfKind(SyntaxKind.ArrowFunction),
    ...sourceFile.getDescendantsOfKind(SyntaxKind.MethodDeclaration),
    ...sourceFile.getDescendantsOfKind(SyntaxKind.Constructor),
  ];
  return nodes.filter((node) => {
    const kind = node.getKind();
    if (kind === SyntaxKind.FunctionDeclaration || kind === SyntaxKind.MethodDeclaration) {
      return Boolean(node.getBody());
    }
    return true;
  });
}

// A name a message can use for a function-like. An arrow has no name in the API at
// all, and a function expression can be anonymous, so the binding it is assigned
// to stands in.
function functionLabel(fn) {
  if (fn.getKind() === SyntaxKind.Constructor) return "constructor";
  if (typeof fn.getName === "function" && fn.getName()) return fn.getName();
  const declaration = fn.getFirstAncestorByKind(SyntaxKind.VariableDeclaration);
  const nameNode = declaration?.getNameNode();
  if (nameNode && Node.isIdentifier(nameNode) && declaration.getInitializer() === fn) {
    return nameNode.getText();
  }
  return "(anonymous)";
}

// Whether a caller outside this project could reach the function: an exported
// declaration, a method of an exported class, or a function assigned to an
// exported const. The reference check only sees this project, so a narrowed
// signature is not the whole story.
function isOnExportedSurface(fn) {
  if (fn.isExported?.()) return true;
  const parent = fn.getParent();
  if (parent && parent.getKind() === SyntaxKind.ClassDeclaration) return parent.isExported();
  const statement = fn.getFirstAncestorByKind(SyntaxKind.VariableStatement);
  return Boolean(statement?.getModifiers().some((modifier) => modifier.getKind() === SyntaxKind.ExportKeyword));
}

// The node whose references stand for calls to `fn`: the function itself, or — for
// an arrow or function expression bound to a name — that binding, which is what a
// caller's identifier resolves to. An arrow has no reference API of its own.
function referenceSource(fn) {
  const declaration = fn.getFirstAncestorByKind(SyntaxKind.VariableDeclaration);
  const nameNode = declaration?.getNameNode();
  if (nameNode && Node.isIdentifier(nameNode) && declaration.getInitializer() === fn) {
    return nameNode;
  }
  return typeof fn.findReferencesAsNodes === "function" ? fn : null;
}

// The Function methods that decide a call's arguments somewhere other than the
// call site.
const FUNCTION_FORWARDERS = new Set(["bind", "call", "apply"]);

// The call that invokes this reference, or null when it is not the callee — a
// value-position use leaves the arity unconstrained, and so does handing the
// function to bind/call/apply, which decides the arguments elsewhere.
function invokedCall(reference) {
  for (let node = reference.getParent(); node; node = node.getParent()) {
    const kind = node.getKind();
    if (kind !== SyntaxKind.CallExpression && kind !== SyntaxKind.NewExpression) continue;
    const callee = node.getExpression();
    if (callee !== reference && callee !== reference.getParent()) return null;
    if (Node.isPropertyAccessExpression(callee) && FUNCTION_FORWARDERS.has(callee.getName())) return null;
    return node;
  }
  return null;
}

// Drop a parameter nothing refers to and no caller fills, taking the matching
// parameter of every overload signature with it. A parameter a caller still
// supplies stays: removing it would break that call. A `_`-prefixed name is the
// convention for one kept on purpose, and a rest or destructured parameter is
// left alone.
async function removeUnusedParams(project, file, apply) {
  if (!file) {
    return fail("file is required");
  }
  const sourceFile = project.getSourceFile(path.join(PROJECT_DIR, file));
  if (!sourceFile) {
    return fail("no such file: " + file);
  }

  const warnings = new Set();
  const removable = [];

  for (const fn of parameterisedFunctions(sourceFile)) {
    const parameters = fn.getParameters();
    if (parameters.length === 0) continue;

    const label = functionLabel(fn);
    const signatures = fn.getOverloads?.() ?? [];
    const source = referenceSource(fn);
    if (!source) continue;

    // A function's own declaration is reported alongside its uses — and so is each
    // overload signature's — so only the uses count.
    const references = source.findReferencesAsNodes().filter((reference) => {
      if (reference === source) return false;
      const kind = reference.getParent().getKind();
      return kind !== SyntaxKind.FunctionDeclaration && kind !== SyntaxKind.MethodDeclaration;
    });
    const unbounded = references.some((reference) => !invokedCall(reference));

    for (let index = 0; index < parameters.length; index += 1) {
      const parameter = parameters[index];
      const name = parameter.getName();
      if (name.startsWith("_")) continue;
      if (!Node.isIdentifier(parameter.getNameNode())) continue;
      if (parameter.isRestParameter()) continue;

      const unit = [parameter, ...signatures.map((signature) => signature.getParameters()[index])].filter(Boolean);
      if (unit.some((member) => member.findReferencesAsNodes().length > 0)) continue;

      // Dropping the parameter would drop the default with it.
      if (parameter.getInitializer() && !isPureExpression(parameter.getInitializer())) {
        warnings.add(`${file}: '${name}' of '${label}' has no references, but its default may have side effects and it was kept`);
        continue;
      }

      if (unbounded) {
        warnings.add(`${file}: '${label}' is used as a value, so '${name}' was kept`);
        continue;
      }

      const supplied = references.some((reference) => {
        const args = invokedCall(reference).getArguments();
        return args.some((argument) => argument.getKind() === SyntaxKind.SpreadElement) || args.length > index;
      });
      if (supplied) continue;

      if (isOnExportedSurface(fn)) {
        warnings.add(`${file}: '${label}' is exported, so its signature may be called outside the project`);
      }
      removable.push(unit);
    }
  }

  if (apply) {
    for (const unit of removable) {
      for (const parameter of unit) parameter.remove();
    }
    await project.save();
  }

  process.stdout.write(
    JSON.stringify({
      ok: true,
      engine: ENGINE,
      applied: apply,
      summary: `${apply ? "Removed" : "Would remove"} ${removable.length} unused parameter(s) from ${file}`,
      files: removable.length > 0 ? [file] : [],
      warnings: [...warnings],
    }) + "\n",
  );
  return 0;
}

async function main() {
  const request = JSON.parse((await readStdin()) || "{}");
  const op = request.op || "rename-symbol";
  const from = request.from || "";
  const to = request.to || "";
  const klass = request.class || "";
  const file = request.file || null;
  const kind = request.kind || null;
  const apply = Boolean(request.apply);

  if (
    op !== "rename-symbol" &&
    op !== "move-file" &&
    op !== "move-member" &&
    op !== "privatize-members" &&
    op !== "remove-unused-locals" &&
    op !== "remove-unused-params"
  ) {
    return fail(
      `unsupported op '${op}' (expected rename-symbol|move-file|move-member|privatize-members|remove-unused-locals|remove-unused-params)`,
    );
  }

  const project = createProject();

  if (op === "move-file") {
    return moveFile(project, file, to, apply);
  }

  if (op === "move-member") {
    return moveMember(project, klass, from, to, file, apply);
  }

  if (op === "privatize-members") {
    return privatizeMembers(project, klass, file, apply);
  }

  if (op === "remove-unused-locals") {
    return removeUnusedLocals(project, file, apply);
  }

  if (op === "remove-unused-params") {
    return removeUnusedParams(project, file, apply);
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

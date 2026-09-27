'use strict';

/**
 * src/agentic/forensics/langs/ts/metrics.cjs
 *
 * TypeScript/JavaScript unit collector for the forensics tool. Uses the
 * TypeScript compiler API (no extra deps) to emit code units — classes,
 * methods, accessors, constructors, functions and function-valued
 * declarations — with cyclomatic complexity and line spans.
 *
 * Request (stdin):  {"project": "/app", "files": ["src/Foo.ts", ...]}
 * Response (stdout): {"ok": true, "units": [...], "errors": []}
 */

const fs = require('fs');
const path = require('path');
const ts = require('typescript');

const DECISION_KINDS = new Set([
  ts.SyntaxKind.IfStatement,
  ts.SyntaxKind.ForStatement,
  ts.SyntaxKind.ForInStatement,
  ts.SyntaxKind.ForOfStatement,
  ts.SyntaxKind.WhileStatement,
  ts.SyntaxKind.DoStatement,
  ts.SyntaxKind.CaseClause,
  ts.SyntaxKind.DefaultClause,
  ts.SyntaxKind.CatchClause,
  ts.SyntaxKind.ConditionalExpression,
]);

const FUNCTION_LIKE = new Set([
  ts.SyntaxKind.FunctionDeclaration,
  ts.SyntaxKind.FunctionExpression,
  ts.SyntaxKind.ArrowFunction,
  ts.SyntaxKind.MethodDeclaration,
  ts.SyntaxKind.GetAccessor,
  ts.SyntaxKind.SetAccessor,
  ts.SyntaxKind.Constructor,
]);

function isFunctionLike(node) {
  return Boolean(node) && FUNCTION_LIKE.has(node.kind);
}

function isMemberFunction(member) {
  return (
    member.kind === ts.SyntaxKind.MethodDeclaration ||
    member.kind === ts.SyntaxKind.GetAccessor ||
    member.kind === ts.SyntaxKind.SetAccessor ||
    member.kind === ts.SyntaxKind.Constructor
  );
}

/** Cyclomatic complexity of one unit — nested functions are not counted. */
function complexityOf(node) {
  let complexity = 1;
  const walk = (n, isRoot) => {
    if (!isRoot && FUNCTION_LIKE.has(n.kind)) {
      return;
    }
    if (DECISION_KINDS.has(n.kind)) {
      complexity += 1;
    } else if (n.kind === ts.SyntaxKind.BinaryExpression && n.operatorToken) {
      const op = n.operatorToken.kind;
      if (op === ts.SyntaxKind.AmpersandAmpersandToken || op === ts.SyntaxKind.BarBarToken) {
        complexity += 1;
      }
    }
    ts.forEachChild(n, (child) => walk(child, false));
  };
  walk(node, true);
  return complexity;
}

/** Weighted method count: the sum of a class' direct members' complexity. */
function classWmc(node) {
  let wmc = 0;
  for (const member of node.members) {
    if (isMemberFunction(member)) {
      wmc += complexityOf(member);
    } else if (member.kind === ts.SyntaxKind.PropertyDeclaration && isFunctionLike(member.initializer)) {
      wmc += complexityOf(member.initializer);
    }
  }
  return wmc;
}

function span(node, sourceFile) {
  const start = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line + 1;
  const end = sourceFile.getLineAndCharacterOfPosition(node.getEnd()).line + 1;
  return { start, end };
}

function makeUnit(relative, name, kind, node, complexity, parent, sourceFile) {
  const lines = span(node, sourceFile);
  return {
    path: relative,
    name,
    kind,
    start_line: lines.start,
    end_line: lines.end,
    complexity,
    loc: lines.end - lines.start + 1,
    parent,
  };
}

function collect(node, sourceFile, relative, units, enclosing) {
  let childEnclosing = enclosing;

  if (node.kind === ts.SyntaxKind.ClassDeclaration && node.name) {
    childEnclosing = node.name.text;
    units.push(makeUnit(relative, childEnclosing, 'class', node, classWmc(node), '', sourceFile));
  } else if (node.kind === ts.SyntaxKind.MethodDeclaration || node.kind === ts.SyntaxKind.Constructor) {
    const name = node.kind === ts.SyntaxKind.Constructor ? 'constructor' : node.name && node.name.getText(sourceFile);
    if (name) {
      const display = enclosing ? enclosing + '::' + name : name;
      units.push(makeUnit(relative, display, enclosing ? 'method' : 'function', node, complexityOf(node), enclosing || '', sourceFile));
    }
  } else if (node.kind === ts.SyntaxKind.GetAccessor || node.kind === ts.SyntaxKind.SetAccessor) {
    if (node.name) {
      const suffix = node.kind === ts.SyntaxKind.GetAccessor ? ' (get)' : ' (set)';
      const name = node.name.getText(sourceFile) + suffix;
      const display = enclosing ? enclosing + '::' + name : name;
      units.push(makeUnit(relative, display, 'method', node, complexityOf(node), enclosing || '', sourceFile));
    }
  } else if (node.kind === ts.SyntaxKind.FunctionDeclaration && node.name) {
    units.push(makeUnit(relative, node.name.text, 'function', node, complexityOf(node), '', sourceFile));
  } else if (node.kind === ts.SyntaxKind.VariableDeclaration && node.name && isFunctionLike(node.initializer)) {
    units.push(makeUnit(relative, node.name.getText(sourceFile), 'function', node.initializer, complexityOf(node.initializer), '', sourceFile));
  } else if (node.kind === ts.SyntaxKind.PropertyDeclaration && node.name && isFunctionLike(node.initializer)) {
    const name = node.name.getText(sourceFile);
    const display = enclosing ? enclosing + '::' + name : name;
    units.push(makeUnit(relative, display, 'method', node.initializer, complexityOf(node.initializer), enclosing || '', sourceFile));
  } else if (node.kind === ts.SyntaxKind.PropertyAssignment && node.name && isFunctionLike(node.initializer)) {
    units.push(makeUnit(relative, node.name.getText(sourceFile), 'function', node.initializer, complexityOf(node.initializer), '', sourceFile));
  }

  ts.forEachChild(node, (child) => collect(child, sourceFile, relative, units, childEnclosing));
}

function main() {
  let request;
  try {
    request = JSON.parse(fs.readFileSync(0, 'utf8'));
  } catch (error) {
    process.stderr.write('ERROR: invalid JSON request\n');
    process.exit(2);
  }

  const project = request.project || '.';
  const files = Array.isArray(request.files) ? request.files : [];
  const units = [];
  const errors = [];

  for (const relative of files) {
    let text;
    try {
      text = fs.readFileSync(path.join(project, relative), 'utf8');
    } catch (error) {
      errors.push(String(relative) + ': ' + error.message);
      continue;
    }
    const sourceFile = ts.createSourceFile(path.join(project, relative), text, ts.ScriptTarget.Latest, true);
    collect(sourceFile, sourceFile, relative, units, null);
  }

  process.stdout.write(JSON.stringify({ ok: true, units, errors }));
}

main();

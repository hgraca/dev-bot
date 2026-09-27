'use strict';

/**
 * src/agentic/forensics/langs/ts/metrics.cjs
 *
 * TypeScript/JavaScript unit collector for the forensics tool. Uses the
 * TypeScript compiler API (no extra deps) to emit code units — classes,
 * methods and functions — with cyclomatic complexity and line spans.
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
  ts.SyntaxKind.CatchClause,
  ts.SyntaxKind.ConditionalExpression,
]);

function complexityOf(node) {
  let complexity = 1;
  const walk = (n) => {
    if (DECISION_KINDS.has(n.kind)) {
      complexity += 1;
    } else if (n.kind === ts.SyntaxKind.BinaryExpression && n.operatorToken) {
      const op = n.operatorToken.kind;
      if (op === ts.SyntaxKind.AmpersandAmpersandToken || op === ts.SyntaxKind.BarBarToken) {
        complexity += 1;
      }
    }
    ts.forEachChild(n, walk);
  };
  ts.forEachChild(node, walk);
  return complexity;
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

function collect(node, sourceFile, relative, units) {
  if (node.kind === ts.SyntaxKind.ClassDeclaration && node.name) {
    const className = node.name.text;
    let wmc = 0;
    for (const member of node.members) {
      if (member.kind === ts.SyntaxKind.MethodDeclaration && member.name) {
        const complexity = complexityOf(member);
        wmc += complexity;
        units.push(makeUnit(relative, className + '::' + member.name.getText(sourceFile), 'method', member, complexity, className, sourceFile));
      }
    }
    units.push(makeUnit(relative, className, 'class', node, wmc, '', sourceFile));
  } else if (node.kind === ts.SyntaxKind.FunctionDeclaration && node.name) {
    units.push(makeUnit(relative, node.name.text, 'function', node, complexityOf(node), '', sourceFile));
  }
  ts.forEachChild(node, (child) => collect(child, sourceFile, relative, units));
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
    collect(sourceFile, sourceFile, relative, units);
  }

  process.stdout.write(JSON.stringify({ ok: true, units, errors }));
}

main();

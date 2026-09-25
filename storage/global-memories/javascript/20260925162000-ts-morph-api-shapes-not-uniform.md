---
date: 2026-09-25
keywords: ["javascript", "ts-morph", "typescript", "refactor", "modifiers"]
trigger-on: ["ts-morph-api", "typescript-refactor-op"]
---

## ts-morph's node APIs are not uniform — probe each one rather than inferring from a sibling

ts-morph 28 is inconsistent in ways that break code written by analogy, so every entry point has to be probed before it is used. The visibility API is per-keyword: `PropertyDeclaration.setIsReadonly()` exists — on properties **and** on constructor parameter declarations — while `setIsPrivate()` does **not**; visibility is `getScope()`/`setScope(Scope.Private)`. The member getters take **no name argument**: `getMethods("m")` silently returns every method instead of filtering, so the filter must be explicit (`getMethods().filter((m) => m.getName() === "m")`), and overloads collapse to one entry per name (the body-bearing declaration, with the signatures reachable via `getOverloads()`). `getOperatorToken()` returns a **Token node** on a `BinaryExpression` but a bare **SyntaxKind number** on a `PrefixUnaryExpression`/`PostfixUnaryExpression`, so `.getKind()` works on one and throws on the other. An `ArrowFunction` has neither `getName()` nor `findReferencesAsNodes()` — its callers are only reachable through the variable it is assigned to — while a `FunctionExpression` has both. `ImportDeclaration.removeNamedImport()` does not exist; `ImportSpecifier.remove()` is the API. And `VariableDeclarationList.getDeclarationKind()` returns `"using"` for a disposal binding, which is not exposed as a modifier. Rule: probe each call with a throwaway script; never assume a sibling's shape.

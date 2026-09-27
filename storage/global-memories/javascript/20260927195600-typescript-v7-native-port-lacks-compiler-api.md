---
date: 2026-09-27
keywords: ["javascript", "typescript", "compiler-api", "npm"]
trigger-on: ["typescript-version-pin", "typescript-compiler-api"]
---

## The TypeScript 7 native port ships no JS compiler API — pin `typescript@5`

`npm install typescript` now resolves to the 7.x native port, whose CommonJS export carries only `version`/`versionMajorMinor` — `require('typescript').SyntaxKind` and `createSourceFile` are `undefined`, so any driver that parses with the compiler API (`ts.createSourceFile` + `ts.forEachChild`, or ts-morph) dies with `Cannot read properties of undefined`. Pin `typescript@5` when installing a metrics/refactor engine, and guard at runtime (`if (!ts.SyntaxKind || typeof ts.createSourceFile !== 'function')` → clear error, no stack trace). Gate a version floor on `major >= 6`, not `!= 5`: that rejects the native port while still accepting a project's own 3.x/4.x.

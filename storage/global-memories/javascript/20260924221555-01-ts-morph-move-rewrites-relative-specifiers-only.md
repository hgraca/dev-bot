---
date: 2026-09-24
keywords: ["javascript", "ts-morph", "typescript", "module-specifier"]
trigger-on: ["ts-morph-file-move", "relative-specifier-rewrite"]
---

## SourceFile.move() rewrites relative specifiers only, and getEditsForFileRename is gone

ts-morph 28 has no `languageService.getEditsForFileRename` (the VS Code API for a file rename); `SourceFile.move(newPath)` is what exists, and it does rewrite importers itself — but only literals whose text starts with `.`. A tsconfig `paths` alias (`import { v } from "@/a"`) resolves to the moved file yet is left untouched, so deriving the affected set from import declarations (`getImportDeclarations()` + `getModuleSpecifierSourceFile()`) reports the alias file as updated while its import is now dangling. The same container also holds `import x = require("./a")` and dynamic `import("./a")`, which the declaration scan misses entirely. Derive the set from `source.getReferencingLiteralsInOtherSourceFiles()` — the container `move()` acts on — filter it to the relative literals for the "rewritten" list, and report the non-relative ones as warnings so a dangling alias is never silent. A bare `require("./a")` call is rewritten by neither and reported by neither.

---
date: 2026-08-06
keywords: ["shell", "refactoring", "bash"]
---

## Function definition dropped when replacing code block — caller still referenced it

When using `edit(oldString, newString)` to replace a block containing function definitions, verify that all functions called in the replacement code still have definitions elsewhere. During `uninstall.sh` refactoring, `_uninstall_tools()` and `_uninstall_modules()` were replaced with calls to `_uninstall_modules`, but `_cleanup_config()` (defined between them in the original) was also dropped. The new `main()` still called `_cleanup_config`, causing a runtime failure. Fix: add the missing function definition back. Prevention: after any multi-function replacement edit, grep for all function calls inside the new block and confirm they have definitions.

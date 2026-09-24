---
date: 2026-09-24
keywords: ["python", "rope", "get_folder", "resources", "refactoring"]
trigger-on: ["rope-refactoring", "rope-resource-existence"]
---

## rope `Project.get_folder()` never fails — `is_folder()` is always True

`Project.get_folder(path)` returns a `Folder` object even when the directory does not exist, and `Folder.is_folder()` is unconditionally `True`, so a guard like `if not dest.is_folder(): raise "no such folder"` is dead code. `MoveModule(project, source).get_changes(missing_folder)` then builds a change set that **removes the source module and rewrites imports for the new path without ever creating the destination file**, and `changes.do()` reports success — silent data loss. Use `resource.exists()` (optionally `and resource.is_folder()`) to test the real filesystem fact before acting on a resource. The same trap applies to `get_file()`.

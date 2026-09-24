---
date: 2026-09-24
keywords: ["python", "rope", "MoveMethod", "move", "refactoring"]
trigger-on: ["rope-refactoring", "rope-move-method"]
---

## rope `MoveMethod` moves to a *self-attribute*, not to a target class

`MoveMethod(project, resource, offset).get_changes(dest_attr, new_name=None)` does not take a destination class — `dest_attr` must be an attribute **of the source class** (`old_pyclass[dest_attr]`, whose object type must be a `PyClass`), and rope rewrites the old body to delegate via `self.<dest_attr>.<new_name>(...)`. An "extract a class attribute holding the collaborator, then move the method onto it" pattern. A CLI that maps `--to <SomeClass>` onto `dest_attr` is therefore wrong and will raise `Destination attribute <X> not found` (or move to a surprising place); either expose it as `--to <self-attribute>` explicitly or build the target-class resolution yourself.

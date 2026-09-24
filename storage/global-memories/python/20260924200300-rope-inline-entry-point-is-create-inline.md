---
date: 2026-09-24
keywords: ["python", "rope", "inline", "create_inline", "refactoring"]
trigger-on: ["rope-refactoring", "rope-inline"]
---

## rope inline has no `Inline` class — the entry point is `create_inline()`

`rope.refactor.inline` exports `create_inline(project, resource, offset)`, not an `Inline` class (importing `Inline` raises `ImportError: cannot import name 'Inline'`). It dispatches on the pyname at the offset and returns `InlineMethod`, `InlineVariable` or `InlineParameter`; the offset may sit on the definition or a call site. `get_changes()` defaults to `remove=True`, which deletes the definition once every call is inlined — for a method whose body contains an f-string, the inlined call can end up with nested same-type quotes (`f"Hello {"world"}"`), which only Python 3.12+ parses (PEP 701).

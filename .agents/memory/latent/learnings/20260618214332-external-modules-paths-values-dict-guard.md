---
date: 2026-06-18
keywords: ["devbot", "external-modules", "python", "bash", "heredoc"]
---

# paths.values() in external-modules config can yield dicts — type guard required

The paths config for external modules (e.g. `andrej-karpathy-skills`) mixes string
values (directory paths like `"skills"`) and dict values (file-level mappings like
`{"CLAUDE.md": "bootstrap/karpathy-instructions.md"}`). When iterating
`paths.values()` in Python code, a dict value gets passed to `os.path.join()`, which
only accepts strings — causing `TypeError: join() argument must be str, bytes, or
os.PathLike object, not 'dict'`.

Fix: add `if not isinstance(rel_path, str): continue` after the loop header, before
any path-joining operation. See `_remove_readme_from_paths` in
`src/agentic/external-modules/functions.sh` for an example. The same pattern applies
to any function that iterates `paths.values()` — `_setup_external_module_storage`
already handles this correctly with `if isinstance(value, str)` / `elif isinstance(value, dict)`.

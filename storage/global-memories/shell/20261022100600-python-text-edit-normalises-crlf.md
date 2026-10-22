---
date: 2026-10-22
keywords: ["shell", "crlf", "python", "line-endings", "diff"]
trigger-on: ["file-editing", "line-endings"]
---

## Python text-mode read/write silently rewrites CRLF as LF

`pathlib.Path.read_text()` and `write_text()` use universal newlines: a file with CRLF endings is read as `\n` and written back as `\n`. A one-line edit to such a file therefore rewrites every line, which shows up as a whole-file diff (a 109-line change for a single deleted line in a CRLF Dockerfile).

Use `read_bytes()` / `write_bytes()` with a byte-level replacement when editing files of unknown or mixed line endings:

```python
b = p.read_bytes()
assert old_bytes in b
p.write_bytes(b.replace(old_bytes, new_bytes, 1))
```

Check `git diff --stat` immediately afterwards — an expected 1-line change that reports dozens of lines means the endings were flattened.

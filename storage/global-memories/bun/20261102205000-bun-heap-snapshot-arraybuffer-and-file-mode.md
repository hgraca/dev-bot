---
date: 2026-11-02
keywords: ["bun", "heap-snapshot", "generateHeapSnapshot", "file-mode"]
---

## Bun heap snapshots: use the ArrayBuffer overload and an exclusive 0600 create

`Bun.generateHeapSnapshot("v8")` returns the snapshot as a JavaScript string, while `Bun.generateHeapSnapshot("v8", "arraybuffer")` returns an `ArrayBuffer` and avoids materialising a second full copy — the overload to use when the heap being measured is large, since the point of the tool is exactly that heap. `Bun.write()` ignores its `mode` option (verified on Bun 1.3.13: the file lands `0664` under umask `0002`), so an owner-only artifact must be created with `fs.openSync(path, "wx", 0o600)` followed by `fs.fchmodSync(fd, 0o600)`; `"wx"` doubles as symlink safety, refusing a pre-existing file or symlink at the path, which matters in a shared `/tmp`. Report the size from `byteLength`, not the UTF-16 `.length` of the string.

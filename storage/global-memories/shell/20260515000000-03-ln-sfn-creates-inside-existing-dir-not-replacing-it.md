---
date: 2026-05-15
keywords: [shell, symlink, rmdir, directory]
---

`ln -sfn <target> <path>` creates a symlink named `<path>`. If `<path>` is an existing directory (even empty), the symlink is created _inside_ it instead of replacing it. Must `rmdir` the directory first, then create the symlink.

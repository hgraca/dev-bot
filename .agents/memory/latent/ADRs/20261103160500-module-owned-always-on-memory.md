---
date: 2026-11-03
keywords: ["devbot", "module-memory", "active-modules", "reinit", "generated-memory"]
---

## Modules own their always-on instructions in memory/active/modules/

A dev-bot module that needs always-on agent instructions writes them to `<devbot_dir>/memory/active/modules/<module-name>.md` from its own `init.sh`, instead of a human hand-copying a section into each project's `memory/active/project.md`. The k8s module's `## Kubernetes access` block had been copied verbatim into 21 project vaults plus the polyrepo root with nothing regenerating it, so the copies could only drift.

The contract is: `devbot reinit` deletes the whole `active/modules/` folder (and the two pre-move file locations) before running init, every enabled module rewrites its own file, and `devbot init` adds `active/modules/` to the project's `.gitignore` ahead of the first module init — the output is machine-generated, never project source. `devbot reinit` also accepts a positional project path, which the docs and skills had been recommending all along.

Two constraints are load-bearing. A module writes its file **before** any environment-dependent early return: the text describes the module, not the state of this machine, so an unreachable AWS or a missing graphify CLI must not drop it after reinit cleared the folder. And the write is **contained**: `devbot_dir` comes from project config and the vault may hold symlinks, so `_devbot_module_memory_path` (`src/_shared/functions.sh`) validates the value against `[A-Za-z0-9._-]+(/…)*` and rejects a symlink on any path component before `mkdir -p` or `cp` runs. Without that, a project could aim a generated write — or reinit's delete — outside itself. graphify and aws moved into the same folder; aws's `.git/info/exclude` workaround was deleted because the `.gitignore` rule now covers it.

---
date: 2026-11-03
keywords: ["prettier", "prettierignore", "ignore-path", "stdin-filepath", "cli"]
aliases: ["prettier ignores prettierignore", "ignore filtering stdin", "prettier --ignore-path"]
trigger-on: ["prettier-cli-invocation", "prettier-ignore-rules"]
---

## `--ignore-path` replaces prettier's defaults, and the rules apply to stdin input too

Prettier 3's documented default is `--ignore-path` = `[.gitignore, .prettierignore]`. Passing the flag — even once — **replaces** that list rather than adding to it, which is the lever for two opposite needs: pass the project's `.prettierignore` alone to honour it without also honouring `.gitignore`, and pass `/dev/null` to disable ignore filtering entirely (useful when a tool decides for itself what to format and must reach gitignored paths).

The rules are not limited to file arguments: in `--stdin-filepath` mode prettier applies them too and returns the input **unchanged** with exit 0 when the path is ignored — it does not error and does not print a warning. A tool that pipes content and writes the result back must therefore detect "skipped" as `output == input`; a separate ignore check is unnecessary. Verified on 3.9.4 with an absolute ignore file and an absolute `--stdin-filepath` from an unrelated cwd, and with a relative stdin path.

One `--ignore-path` covers a whole invocation, so batch runs over files belonging to projects with different ignore files must be partitioned by ignore file, not just by config.

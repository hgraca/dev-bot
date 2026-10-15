---
date: 2026-10-15
keywords: ["git", "gitignore", "template", "scaffold"]
aliases: ["shipped .gitignore hides files", "template gitignore becomes active"]
trigger-on: ["shipping-template-files", "vendoring-a-scaffold"]
---

## A `.gitignore` shipped inside a repo subtree is a live ignore file for that subtree

Copying a scaffold into a repository preserves its `.gitignore` as an **active** ignore file scoped to the directory it lands in — not inert template data. Two consequences. First, a file you drop beside it can be silently ignored: a scaffold's `.gitignore` listing `.bundle/` hid a `docs/.bundle/config` that had just been copied, so `git status` never listed it and a plain `git add` skipped it — the file simply was not in the commit. Second, a pre-existing rule can shadow files you intend to track. Decide deliberately which case you are in: if the shipped file is meant to be live, verify every non-obvious path with `git check-ignore -v <path>` (it prints the rule and the file that supplied it) and force-add anything that must be tracked; if it is a template rather than a config, ship it under a non-dot name (e.g. `gitignore`) so the host repo's rules are untouched. The same reasoning applies to any vendored directory, and `git check-ignore -v` is the cheap check that says which rule is in play.

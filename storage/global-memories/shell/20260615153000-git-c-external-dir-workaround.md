---
date: 2026-06-15
keywords: ["bash", "git", "symlink", "external_directory", "opencode"]
---

## Git -C works when workdir on symlinked external dir fails permission check

When running `git` commands on an external symlinked repo, `bash` tool with `workdir` set to the external path may fail with permission rules even when the path is allow-listed. Workaround: use `git -C <absolute-external-path>` from within the workspace directory instead of setting `workdir`. Example: `git -C /home/user/external-repo diff --stat` run from the project root.

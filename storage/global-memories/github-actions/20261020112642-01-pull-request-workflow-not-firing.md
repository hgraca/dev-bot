---
date: 2026-10-20
keywords: ["github-actions", "pull-request", "workflow-dispatch", "ci"]
trigger-on: ["github-actions-pull-request-not-firing"]
---

## A pull_request workflow can stop firing mid-PR; dispatch or reopen

On a long-lived private-repo PR the `pull_request` workflow stopped creating runs after a base change and several pushes, while `workflow_dispatch` runs and a separate Copilot workflow kept working. Closing and reopening the PR restored the Copilot review but not the CI workflow; a later merge/push eventually re-triggered it. When a PR's checks are empty but the workflow file is valid (`gh workflow view`, `gh run list --branch`), do not assume the workflow is broken: `gh workflow run <workflow>.yml --ref <branch>` runs the same jobs for verification (the run is not attached to the PR's checks), `gh run view <id> --log-failed` confirms the jobs ran, and closing/reopening or a fresh push may restore the event. Use a manual run to verify the commit meanwhile rather than merging on an empty check set.

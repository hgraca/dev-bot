---
date: 2026-10-29
keywords: ["argocd", "repository", "ssh", "repoURL", "credentials"]
trigger-on: ["argocd-application-repo-url"]
---

## An ArgoCD Application with an SSH `repoURL` fails unless that repo has stored credentials

Creating an Application with `repoURL: git@github.com:org/repo.git` fails `InvalidSpecError: repository not accessible ... error creating SSH agent: "SSH_AUTH_SOCK not-specified"`. ArgoCD's repo-server has no ssh-agent — that error means no credential exists for the URL, not that the network is unreachable. Two fixes: use the **HTTPS** URL that is already registered under Settings → Repositories (with a token), or store a deploy key for the SSH URL. Copy the URL verbatim from the repository list rather than from the git remote, and keep any Application manifest committed in Git in sync with whatever ArgoCD actually accepted, or the file becomes a misleading record.

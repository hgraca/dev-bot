---
date: 2026-06-18
keywords: ["docker", "composer", "github", "private-repos", "ssh-agent"]
---

## composer fails with private GitHub repos inside Docker containers

When `composer.json` declares private GitHub repositories (`git@github.com:ORG/*`) and `preferred-install: dist` with source fallback disabled, running `composer update` or `composer install` inside a Docker container fails because: (1) dist downloads hit GitHub API zipball endpoints that return 404 without a `github-oauth` token, and (2) source clones via SSH need the SSH agent socket (`$SSH_AUTH_SOCK`) and `known_hosts` file mounted into the container. Fix: either mount `-v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent -v ~/.ssh/known_hosts:/root/.ssh/known_hosts`, or pass a GitHub token via `-e COMPOSER_AUTH='{"github-oauth":{"github.com":"<token>"}}'` for dist downloads. Also run `git config --global --add safe.directory /app` to avoid dubious ownership errors when the repo is bind-mounted from the host at a different UID.

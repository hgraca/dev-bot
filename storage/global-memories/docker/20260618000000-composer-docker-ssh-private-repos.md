---
date: 2026-06-18
keywords: ["docker", "composer", "ssh", "github"]
trigger-on: ["docker-composer-private-repos"]
---

## Composer in Docker: SSH agent + host keys for private VCS repos

When running `composer require/install` via the `composer:latest` Docker image for a project with private GitHub repositories (VCS type in composer.json), two errors must be handled: (1) "Host key verification failed" — fix by running `ssh-keyscan github.com >> ~/.ssh/known_hosts` before composer; (2) "requirements could not be resolved" due to missing PHP extensions (mongodb, rdkafka, etc.) — fix by passing `--ignore-platform-reqs`. Full invocation: `docker run --rm -v "$(pwd):/app" -v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent -w /app composer:latest sh -c 'git config --global --add safe.directory /app && mkdir -p ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null && composer require ... --ignore-platform-reqs'`. If dist downloads for private repos fail (no GitHub API token), add `--no-install` to update only json and lock files.

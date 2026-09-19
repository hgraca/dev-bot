---
layout: page
title: Guards
description: Prevent dangerous commands from being executed by agents.
nav_section: docs
---

Guards evaluate shell commands against configurable regex patterns before they run — blocking dangerous operations before execution. Every shell channel is covered: the bash tool, and the PTY tools that carry a command (`pty_spawn`'s executable plus argument array, and `pty_write`'s typed input).

## What it does

- **Regex-based rules**: match commands against patterns you define
- **Global + project config**: shared defaults in `.devbot.global.jsonc`, project overrides in `.devbot.jsonc`
- **Agent filtering**: (future) restrict rules to specific agents
- **First match wins**: rules evaluated in order, first matching pattern blocks the command

## Configuration

```jsonc
{
  "guards": [
    { "regex": "rm -rf", "message": "rm -rf is blocked" },
    { "regex": "sudo .*", "message": "sudo requires approval" },
    { "regex": "git push --force", "message": "force push is prohibited" },
  ],
}
```

## How it works

The `command.before` hook fires before every shell command. Guards checks the normalised command against all configured patterns and blocks it if a match is found.

## See also

- [Configuration](/configuration) — full devbot.jsonc reference

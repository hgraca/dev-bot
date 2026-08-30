---
layout: page
title: Guards
description: Prevent dangerous commands from being executed by agents.
nav_section: docs
---

Guards evaluate bash commands against configurable regex patterns before they run — blocking dangerous operations before execution.

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

The `on-tool_execute_before` hook fires before every bash command. Guards checks the command against all configured patterns and blocks it if a match is found.

## See also

- [Configuration](/configuration) — full devbot.jsonc reference

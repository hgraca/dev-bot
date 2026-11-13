---
title: AutoBot
description: Scheduled agent prompts plus deterministic follow-up polling for Jira and GitHub.
commands: ["autobot-work"]
tools:
  autobot: Runs one tick, or deletes orphaned sessions
---

Scheduled agent work for the projects a devbot harness is running in. A single system crontab line
wakes the module; every project declares its own prompts in `.devbot.project.jsonc` under `autobot`.

## What it does

Two independent halves, in this order:

1. **Follow-ups** — a deterministic poll of Jira and GitHub. It compares what a human did against the
   stored watermark and produces a list of actions. When there is nothing to do, the list is empty
   and no model is invoked.
2. **Scheduled prompts** — per-project `{schedule, prompt}` entries that are due at this tick,
   serialised, one lock per tick.

A ticket carrying the `auto-bot` label is worked to an open pull request, with a human answering
questions in Jira and merging. The `[repo]` prefix pins the checkout; without one, the session starts
at the workspace root and resolves the owning project itself. Every comment AutoBot writes ends with `authored by AutoBot` — that
signature is how it tells its own replies from a human's, so no separate bot identity is needed. Each ticket carries its session in the `Autobot session` field
(`customfield_10877`), so a continuation resumes the same opencode session rather than starting over.

## Configuration

A project either names a profile declared once in the global config, or configures itself inline. A
project is one or the other — there are no profile-plus-overrides.

```jsonc
// .devbot.global.jsonc — declare the configuration once
{
  "autobot": {
    "gete-jira": {
      "poll_jira": true,
      "poll_github": true,
      "jira_base_url": "https://getinfo.atlassian.net",
      "jira_email": "you@example.com",
      "jira_api_token": "${JIRA_API_TOKEN}",
      "jira_assignees": ["you@example.com"],
      "poll_slack": true,
      "slack_user_email": "you@example.com",
      "slack_bot_token": "${SLACK_BOT_TOKEN}",
      "prompts": []
    }
  }
}

// <project>/.devbot.project.jsonc — name it…
{
  "autobot": "gete-jira"
}

// …or configure this project inline
{
  "autobot": {
    "poll_jira": false, // deterministic Jira follow-up poll
    "poll_github": false, // deterministic GitHub follow-up poll
    "jira_base_url": "https://getinfo.atlassian.net",
    "jira_email": "you@example.com",
    // this is needed in the cron job: set JIRA_API_TOKEN in ~/.config/devbot/autobot.env
    // (export JIRA_API_TOKEN=paste-the-token-here) or put the token directly here
    "jira_api_token": "${JIRA_API_TOKEN}",
    // Required. Only pick up tickets assigned to these people; [] picks up nothing.
    "jira_assignees": ["you@example.com"],
    // Talk to one person over Slack. Both or neither; both when poll_slack is on.
    "poll_slack": false,
    "slack_user_email": "you@example.com",
    "slack_bot_token": "${SLACK_BOT_TOKEN}",
    "prompts": [
      // { "schedule": "*/5 * * * *", "prompt": "/devbot:autobot-work ARC-1017" }
    ]
  }
}
```

Every switch defaults to off, and the block is inert until one is enabled. A project is skipped unless
a devbot harness is running there — the watch is the one lock file per PID the harness start script
writes under `<devbot_dir>/state/devbot/`.

`jira_assignees` is required and narrows the pickup to tickets assigned to those people. `[]` means
pick up nothing — a deliberate pause that keeps the labels in place — so a project always says which
it wants rather than inheriting a default by omission. Projects sharing a connection union their lists,
and the filter never applies to cleanup, which reads state rather than selecting work.

Each instance is independent: projects are grouped by the connection they configure, each group is
polled with its own connection, and a ticket is answered with the connection of the project that owns
it. Two projects pointing at different Jira sites is a normal setup, not an error. The token may be a
literal, in which case it lives in this file — or `${VAR}` (devbot's canonical form is `{env:VAR}`),
resolved at tick time from the environment the cron entry sources.

## Talking to the user (Slack)

A cron run has nobody at the terminal. Anything the user must know goes to a Slack direct message,
and anything the agent needs comes back the same way one tick later.

- `slack_user_email` names the one person the bot talks to, and `users.lookupByEmail` turns it into an
  id — so the configuration carries an address, not a Slack id. The app needs `chat:write`,
  `im:history`, `im:read` and `users:read.email`.
- Only that person's replies count. Anyone else in the workspace is ignored, and the bot's own
  messages carry no author, so it cannot answer itself.
- Each ticket gets one thread, so its conversation stays contiguous.

### Asking, and parking

A run cannot wait for an answer, so `devbot autobot say --ask --phase <phase> "<question>"` posts the
question and writes a park record. The run then ends. The next tick reads the reply, starts a fresh
run with the question and the answer attached, and clears the park.

A parked ticket is reminded hourly, forever: nothing expires and nothing blocks automatically. It is
reminded only while parked, so a ticket in the middle of a long build is not nagged.

Phases: `refining`, `awaiting_restate`, `awaiting_plan`. A bare reply in the direct message addresses
the only parked ticket; with several parked, reply in the ticket's thread, because guessing which
ticket a bare "yes" belongs to is how the wrong pull request gets built.

`devbot autobot say "<message>"` without `--ask` is a plain progress report. The token is resolved by
the command, so it never enters the agent's context — set `SLACK_BOT_TOKEN` in
`~/.config/devbot/autobot.env` beside `JIRA_API_TOKEN`.

## What runs on a schedule

`install.sh` writes one marked block into the user's crontab:

```
* * * * *   autobot tick      # follow-ups, then any prompts that are due
17 3 * * *  autobot cleanup   # orphaned sessions and a vacuum
```

The entry sources `${XDG_CONFIG_HOME:-~/.config}/devbot/autobot.env` first, because cron has no
environment. That file provides:

```bash
export JIRA_API_TOKEN=…
```

That file holds the secret only. `jira_base_url` and `jira_email` live in the project config, and there
is no bot account: the label is the trigger, and the signature on every comment is what keeps AutoBot
from answering itself.

`DEV_BOT_AUTOBOT=off` skips registration; installing as root is refused, because root's crontab has
none of the user's opencode store, `gh` login or checkouts.

## Limits worth knowing

- Labels record the outcome as well as the trigger: `auto-bot` in the queue, then `auto-bot-done`,
  `auto-bot-abandoned` or `auto-bot-blocked`. The ticket is never re-picked.
- One tick runs at a time (a `mkdir` mutex), so a slow run delays the next minute rather than stacking.
- Follow-ups are at-least-once: the item is recorded before the agent runs and promoted only on
  success, with a three-attempt cap that comments on the ticket instead of looping.
- GitHub polling needs the Jira read anyway — the ticket key is the join.
- Deleting a session does not shrink `opencode.db`, which is why cleanup follows with a vacuum.
- **One host at a time.** The instance id in the state is this machine; a state written by another
  instance is treated as dead and handed back. Two hosts must not run the tick against the same bot
  account until instance liveness is shared.
- **The comment channel is the trust boundary.** Any account that can comment on the ticket can steer
  a run, and the agent runs with `--auto`, so its tool calls are not individually approved. Keep the
  bot out of projects where untrusted users can comment.

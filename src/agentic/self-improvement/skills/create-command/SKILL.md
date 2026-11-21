---
name: devbot:create-command
description: "Use when adding a slash command to a devbot module — placement, the name/filename match, $ARGUMENTS handling, wiring, the docs manifest and tests. Triggers on 'create a command', 'add a slash command', 'new devbot command'."
---

# Skill: Create DevBot Command

A command is a **repeatable instruction set the user invokes by name**: the entry point that applies a
skill (or a workflow) to something the user names. It is not a skill, and it is not where rules live.

## When to Apply

- Adding a slash command to an existing module or tool
- Turning a multi-step ask the user repeats into a named invocation
- Deciding whether something should be a command, a skill, a tool, or an agent

## Command, skill, tool, or agent?

| Artifact    | Owns                                          | Invoked by               |
| ----------- | --------------------------------------------- | ------------------------ |
| **Command** | What to do for one named input, in what order | The user, `/devbot:<id>` |
| Skill       | The rules and method for a class of work      | The agent, when relevant |
| Tool        | Deterministic execution of one operation      | The agent, or a command  |
| Agent       | A role with its own scope and permissions     | Delegation               |

A command that carries a method duplicating a skill is a defect — see
[Never restate a skill](#never-restate-a-skill).

## Placement and naming (MUST)

```
src/agentic/<module>/commands/<id>.md
src/tools/<tool>/commands/<id>.md
```

- `<id>` is the filename without `.md`, and the frontmatter name is `devbot:<id>`. **The two must
  match**, and the frontmatter is the one that registers: the farm links each command at
  `.agents/commands/<frontmatter name>.md`, and every host derives the slash command from that link
  name. The filename is never registered, so a mismatch is not a second command — it is a broken
  one: renaming `foo.md` to `bar.md` while `name: devbot:foo` stays keeps registering `foo` (and
  `devbot list commands` keeps printing it) while nothing ever reaches `bar`. Correct both in the
  same edit.
- Flat, never a subdirectory, and always prefixed: the farm skips (with a warning) a command whose
  name is not `devbot:<id>`, because the link would land a top-level `/<id>` in the user's own
  namespace. `name: devbot:devbot-audit` registers `devbot:devbot-audit`.

## Front matter

Two keys, both required:

```yaml
---
name: devbot:<id>
description: What invoking the command does, in one line.
---
```

Every command in this repository uses exactly these two and nothing else. Other keys exist, and which
ones are honoured differs by harness — so adding one is a deliberate decision to verify against the
harness you target, never a default.

## Body

- **`$ARGUMENTS` is the whole tail; `$1` is the first word.** Use `$1` when the command takes exactly
  one value and has no free-form prose — `src/agentic/rfp/commands/rfp.md` is the reference for that
  contract — and `$ARGUMENTS` only when the tail is genuinely free-form. Choosing the wrong one feeds
  the user's extra words into the argument.
- **Say what to do when it is empty: ask, and wait.** A command that falls back to the working
  directory, or infers the subject from the conversation, guesses the user's intent on their behalf.
- **Numbered procedure, imperative, short.** A command is a route, not an essay: point at the skill,
  name the inputs, state the stop conditions. Under ~50 lines is the norm — about two thirds of the
  shipped commands fit, and the long ones are deliberate.
- **Resolve an argument instead of assuming it.** Exits from a resolver are answers: an exit `3` from
  `devbot tool project-for-path` means the path belongs to no registered project, and that is a
  refusal to surface — not a reason to continue against the path anyway.
- **State the stop conditions that matter.** If a step must not run before something else exists (an
  authorisation, a confirmation, a credential), say so as a stop, and let the skill it points at own
  the detail.

### Never restate a skill

A command that needs a skill **names it, says when to load it, and points at it for the rules**. It
never summarises or repeats them: a restatement lets the reader finish the command believing it has
read the rule, so the skill is never loaded, and the two copies drift apart. See
`devbot:create-skill`'s reference rule for the reasoning and the wording.

The same applies to a stop condition that lives in a skill — point at the skill's gate, do not re-list
its questions.

## Wiring

No manual step exists, and none should be added:

- `_link_commands` in `src/tools/devbot-cli/functions.sh` walks `commands/*.md` on `devbot init` /
  `devbot reinit`, reads the frontmatter `name`, and links `.agents/commands/devbot:<id>.md` at the
  file — flat, so opencode (path segments joined with `/`) and claudecode (directory joined with
  `:`) both register `/devbot:<id>`.
- **It reconciles.** A renamed or deleted command loses its link, a disabled module's commands leave
  the farm, and the pre-colon `commands/devbot/` category dir is retired module by module until it
  empties — a link or file that is not the module's keeps it alive.
- Add the bare id to the module's `docs.md` front matter, alphabetically:

  ```yaml
  commands: ["create-jira-issue"]
  ```

  That manifest is the single capability source for the generated docs site — a command missing from
  it is invisible site-wide.

- `devbot list commands` reads the source tree (`src/agentic/*/commands/*.md` and
  `src/tools/*/commands/*.md`), so it lists a new command before any init — it checks placement, not
  wiring. The wiring check is that `.agents/commands/devbot:<id>.md` exists after `devbot init`.

## Testing

A module that guards its commands asserts three things in a BATS file under its `tests/`. Few do
today — `atlassian`, `figma` and `security` — so treat this as the target, not the current state:

1. Each command declares `name: devbot:<filename>` and a `description:`.
2. The `docs.md` `commands:` manifest equals the files on disk.
3. The behaviours that must not drift — the empty-argument ask, the refusal path, the stop condition.

Grep multi-line prose against one flattened line (`tr '\n' ' ' < "$cmd"`), because the argument is
usually wrapped. For the anti-restatement rule, assert **both** that the pointer to the skill is
present **and** that the skill's distinctive wording is absent — a guard that only checks for the
pointer passes on a command that also restates it.

```bash
@test "the command points at the skill instead of restating it" {
    grep -qF 'devbot:pentest-external-webapp' "$CMD"
    ! grep -qiF 'WSTG' "$CMD"        # distinctive wording of the skill it points at
}
```

## Checklist

- [ ] File at `commands/<id>.md`; frontmatter `name: devbot:<id>` matches the filename
- [ ] `description:` is one line, and says what invoking it does
- [ ] `$1` or `$ARGUMENTS` chosen to match the argument shape, and the empty case asks and waits
- [ ] Any skill is named and pointed at, never restated
- [ ] Resolver exits treated as answers, not obstacles
- [ ] `docs.md` `commands:` updated with the bare id
- [ ] Module BATS asserts front matter, manifest and the non-drift behaviours
- [ ] `devbot list commands` lists it (source tree), and `.agents/commands/devbot:<id>.md` exists after `devbot init`

## References

- `devbot:create-skill` — the SKILL.md conventions and the reference-don't-restate rule
- `src/tools/devbot-cli/functions.sh` — `_link_commands`, the farm's naming rules
- `src/agentic/security/commands/pentest-webapp.md` — resolves an argument, loads one skill, stops at
  its gate and restates nothing
- `src/agentic/rfp/commands/rfp.md` — the `$1` contract and its documented stop conditions

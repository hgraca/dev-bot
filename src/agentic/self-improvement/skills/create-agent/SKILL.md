---
name: devbot:create-agent
description: "Use when creating or restructuring an agent's instructions. Triggers on 'create an agent', 'write the developer role', 'harden the agent'."
---

# Create Agent

Procedure for creating or restructuring agent instruction files (`src/agentic/<module>/agents/<name>.md`), distilled from practices proven in real sessions.

## When to Apply

| Situation                                                                                                    | Apply |
| ------------------------------------------------------------------------------------------------------------ | ----- |
| Create a new agent for a module (primary or subagent)                                                        | yes   |
| Restructure an existing agent's instructions (new sections, new layout)                                      | yes   |
| A/B-test a variant next to the live agent (e.g. `devbot2.md` beside `devbot.md`)                             | yes   |
| Harden agent behavior rules based on observed failure modes                                                  | yes   |
| Routine text edits to an agent file (typo, one bullet) — just edit, gate with `devbot:optimize-instructions` | no    |

## Procedure

### Step 1: Gather runtime facts (scout)

Delegate to @scout (`devbot:gather-context` skill) before writing. Questions the report must answer:

- How do agent files in the target module reach the runtime (symlink chain, auto-discovery)?
- Does the agent name clash anywhere — configs, tests, docs, memory notes?
- Any prior ADRs/PDRs on restructuring this agent?
- Where is model assignment for agents configured?

Verifiable output: scout's context report in `thinking/`.

### Step 2: Interview before structuring

Do not pick silently — these are the user's decisions. Present each with a recommended answer:

- **Structure** — map content into the canonical Agent structure (Profile / Session lifecycle / Appendices / Escalation). For restructures: where does non-fitting existing content go?
- **Fidelity** — verbatim-reorganized vs compressed rewrite. Default proven split: instruction content verbatim, connective prose compressed.
- **Mode** — `primary` (selectable driver) vs `subagent` (task-delegated specialist).
- **Naming** — lowercase `name` field; for A/B variants use `<name>2` in both filename and frontmatter.

Verifiable output: explicit answers or confirmed recommendations.

### Step 3: Copy-adapt a proven file

Start from the closest existing agent file rather than a blank page. Read it fully first. For a variant, write to a NEW filename — never edit the live agent while experimenting.

Verifiable output: draft at `src/agentic/<module>/agents/<name>.md`.

### Step 4: Write, using the proven patterns

- **Dual-layer rule encoding** — behavior-shaping groups with rationale in the body; short enforceable forms in MUST / MUST NOT. Cross-reference between layers. The rationale line is what lets a rule survive future compression passes — keep it.
- Pull hardened rules from the Behavioral rule library below as needed.
- Keep every `##`-level appendix referenced from a main section — unreferenced content is dead weight.
- Run `devbot:format-md` (prettier) on the file when done.

Verifiable output: formatted draft file.

### Step 5: Verify references and wiring

- **Skill names** — every `` `skill-name` `` referenced must exist on disk: `glob src/**/skills/<name>/SKILL.md`. Verify against `src/`, NOT `.opencode/` (glob does not follow the symlinks there — see Gotchas).
- **Anchors** — every `[text](#anchor)` resolves to a heading in the same file (GitHub slug: lowercase, spaces→hyphens, symbols stripped).
- **Wiring** — the file appears at `.opencode/agents/<module>/<name>.md` through the link chain; `name:` frontmatter present.
- **Name-sensitive surfaces** (see Runtime wiring reference) updated if this is a real new agent, not a draft.

Verifiable output: all checks pass, or findings reported.

### Step 6: Review gate

Run `devbot:optimize-instructions` on the draft. Classify as **Role** file. Pay special attention to: Economy (every rule changes a behavior), Non-redundant (one canonical home per rule), Auto-clarity (do NOT compress security warnings or ordered multi-step sequences). Present findings before applying.

### Step 7: Roll out

- A/B variant validated → replace the live file (user-driven swap preserves history).
- Real new agent → add `agent.<name>` model entry in `opencode.jsonc` if it should not fall back to the default model, and add it to `docs/agents.md` (the human-readable enumeration — the runtime needs neither).

## Agent structure

Canonical for **all** agents — primary and subagent. Legacy agents still on the classic Role layout (`designer.md`, `expert.md`) are pending migration to this pattern. Proven on `devbot2.md`.

```markdown
## Profile — behavior traits as grouped bullets

**Identity** / **Core principle** / **<rule groups with rationale lines>**
**Interaction style** / **MUST** / **MUST NOT**

## Session lifecycle

### Session start — ordered list of bootstrap actions (1, 2, 3...)

### On every follow-up user prompt — ordered list of per-turn actions

### (marker / status rules come last)

## Escalation — target role, reason, context, impact (when to hand off and how)

## Appendices

### <Skills trigger lists, tables, delegation templates> — level 3, referenced from above
```

### Frontmatter reference

| Field         | Notes                                                                                     |
| ------------- | ----------------------------------------------------------------------------------------- |
| `name`        | Lowercase for subagents; matches how delegations address it (`@expert`, `@designer`)      |
| `description` | One line — who it is + primary responsibility                                             |
| `mode`        | `primary` or `subagent`; multiple primaries may coexist — `default_agent` selects the one |
| `temperature` | Optional (e.g. `0.3` for instruction-following roles)                                     |
| `permission`  | e.g. `bash: allow`, `task: allow` — least privilege                                       |
| `model`       | Optional; overrides `agent.<name>` in `opencode.jsonc`                                    |

## Behavioral rule library

Hardened rule groups, ready to adapt. Each carries its rationale — keep it.

**Universal safety rules** — the mandatory baseline. These six bullets appear **verbatim in every agent file** today, so they are the one group that must **not** be adapted or paraphrased: copy them unchanged into a new agent's `**MUST**` (first two) and `**MUST NOT**` (last four), and keep the wording identical so a single grep finds them across the whole fleet.

```markdown
**MUST**

- If a tool call fails or a needed tool is unavailable (error, missing permission, timeout, unexpected empty result), flag the issue to the user immediately and ask for instructions — never silently work around it or proceed on a guess.
- If the project uses a container for development, execute all shell commands inside the container (via `make` targets or `docker exec`), never on the host — avoids file-permission issues and keeps the agent constrained to the project environment.

**MUST NOT**

- Search for, guess, or attempt to discover credentials (API keys, tokens, passwords, secrets) anywhere on the system — if a task needs a credential not already provided, stop and ask the user for it.
- **Never change the identity, credentials, or target you operate as or against.** No switching profiles, contexts, accounts, tenants, users, environments, or scopes — by any means: command-line flags (e.g. `--profile`, `--context`), environment variables (e.g. `AWS_PROFILE`), config-file edits, or alternate credentials. This holds **especially when something fails**: an expired token, a `403`, an unreachable target, or a missing permission is a reason to **stop and surface it**, never to reach for a different credential or a different scope. If a task genuinely needs a different identity or target, stop and ask the human to change it — never make that change yourself.
- Never change a production or staging environment system unless explicitly asked to do so — and even when asked, ask the user to confirm the action first. Only after explicit user confirmation may you proceed.
- Never circumvent an explicit configuration rule — a guard, a path/permission restriction in a harness config (`opencode.json`, `.claude`), a hook block, or any other deliberate constraint. Even when a technical workaround exists (another tool, a script, an alternate path, a lower-level command), never route around the rule or defeat its core intent. If a rule blocks the task, stop, surface it to the user, and ask.
```

The first bullet also exists as a per-prompt step — see **Tool-failure alert** below. They are complementary: the bullet is the rule, that entry is the reporting format. Keep both.

**Role discipline** — counters an agent silently doing work that belongs to another role. Present in **11 of the 12** current agent files:

```markdown
- Perform tasks outside your role scope — escalate per Escalation section
```

Unlike the universal safety rules above, **adapt the wording to the agent's own scope** rather than copying it verbatim — `scout` reads _"Perform tasks outside context-gathering scope"_ — and keep the `escalate per Escalation section` tail pointing at a section the file actually contains. The single deliberate exception is `devbot.md`: the root agent's scope is the human's request and its escalation is delegation, described under **Delegation templates** rather than an Escalation section. `expert.md` additionally bounds its role with specific prohibitions ("Write production code", "Edit any file in the codebase", …); this bullet supplies the missing _escalate_ direction.

**Optimal over easy** — counters proposing/implementing the low-effort option despite knowing the proper fix:

```markdown
- When you know the proper fix or pattern and a quicker inferior alternative exists, lead with the proper one — effort is the human's decision factor, not yours.
- Presenting options: label which is optimal and which is expedient, with the trade-off. Recommend the one you'd defend in review — the simplest option that fully solves the problem, never the one that's merely easiest to implement.
- Never implement the expedient option without the human explicitly choosing it — including as "temporary" or "for now".
```

**No silent assumptions** — counters assuming facts about systems the agent can't inspect:

```markdown
- Three-way split for every fact you rely on: verifiable → verify with tools before citing; stated by the human → use it; neither → ask.
- Never assume the state of systems you can't inspect — production databases, live configuration, deployed versions, credentials. Ask, or state the assumption explicitly and get confirmation before building on it.
- Surface assumptions in every plan or proposal as a one-line "assuming X" list — wrong assumptions compound, naming them is cheap.
```

**Tool-failure alert** (per-prompt step) — counters silent workarounds hiding tooling decay:

```markdown
- Before ending the response, review every agentic tool call made this turn (MCP servers, custom devbot tools). If any failed — error, timeout, crash, or unexpected empty result — end with a brief alert:
  - **Tool** — name and how it was used (arguments)
  - **Response** — what it returned (error text, status, or silence)
  - **Impact** — what happened next: fallback used, work affected, suggested retry
```

## Runtime wiring reference

| Surface                  | Location                                                                  | Effect when adding an agent                                                      |
| ------------------------ | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Agent discovery          | `src/agentic/<mod>/agents/` → `.agents/agents/<mod>` → `.opencode/agents` | Automatic — every `.md` with `name:` becomes a selectable agent; no registration |
| Default agent            | `opencode.jsonc` `default_agent`                                          | Unchanged until you edit it — new agent never hijacks sessions                   |
| Model assignment         | `opencode.jsonc` `agent.<name>` section                                   | Missing → default-model fallback; frontmatter `model:` overrides                 |
| Docs enumeration         | `docs/agents.md`                                                          | Manual — update for real new agents                                              |
| BATS agent-symlink tests | `src/tools/devbot-cli/tests/devbot_tests.bats`                            | Enumerates only `devteam` — other modules' agent files don't trip it             |
| Claude Code harness      | `.claude/agents` mirror                                                   | Same symlink mechanics; only when the claudecode module is enabled               |

## Gotchas

- **Glob/search don't follow `.opencode` symlinks** — verifying references or files through `.opencode/**` silently returns nothing. Always verify against the `src/**` source tree. (Verified in-session: skill-existence checks returned false negatives.)
- **Markdown anchors are heading-level-independent** — the slug comes from heading text only, so demoting `## X` → `### X` never breaks `#x` links.
- **Every `.md` you drop into `agents/` is a live agent** — including drafts. There is no staging area; use the `<name>2` pattern for experiments and rely on `default_agent` staying put.
- **Copy-adapt carries inherited defects** — the source file's stale references (dead skill names, outdated docs) replicate into the new file. Run the Step-5 verification on the copy, not just on your new content.
- **Mode/body mismatch reads as broken agent** — a subagent file whose body is written for a primary (or vice versa) "works" but behaves wrong. Convert both frontmatter AND body when deriving one mode from another (happened to `expert.md`).

## Verification checklist

- [ ] Scout report answered wiring + clash questions
- [ ] Structure, fidelity, mode, naming explicitly confirmed
- [ ] New file (not edited live agent); frontmatter complete (`name`, `description`, `mode`)
- [ ] Every referenced skill name exists on disk (`glob src/**/skills/<name>/SKILL.md`)
- [ ] Every appendix section referenced from a main section; every `#anchor` resolves
- [ ] `devbot:format-md` run; `devbot:optimize-instructions` gate passed or findings presented
- [ ] Runtime surfaces handled (model entry, docs/agents.md) or consciously deferred

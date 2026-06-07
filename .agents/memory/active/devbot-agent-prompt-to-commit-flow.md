# DevBot Modus Operandi: Prompt → Commit Flow

**Compiled**: 2026-07-31 | **Keywords**: devbot, session-flow, hooks, plugins, lifecycle, memory

---

## Architecture: Two Layers

DevBot's operation is the interplay of two layers:

| Layer                                | What it is                                                      | How it runs                                                 |
| ------------------------------------ | --------------------------------------------------------------- | ----------------------------------------------------------- |
| **Agent instructions** (`devbot.md`) | The "persona" — rules for how DevBot thinks, talks, and decides | Active — DevBot follows these instructions as the LLM agent |
| **Hooks/Plugins** (`.ts` files)      | Silent background processes that react to events                | Passive — fire automatically, DevBot doesn't invoke them    |

Hooks are invisible to DevBot — they fire on events, inject hidden prompts, format files, auto-recover from errors. DevBot only interacts with skills (via `skill` tool) and tools (via tool calls).

---

## The Complete Flow

### ⚡ PHASE 0: Session Created (hooks fire automatically)

These hooks fire on `session.create` before DevBot even starts:

| Hook                                 | Trigger          | What it does                                       |
| ------------------------------------ | ---------------- | -------------------------------------------------- |
| `on-session_created-graphify-update` | Session creation | Re-indexes knowledge graph for codebase navigation |

These hooks register listeners that fire throughout the session:

| Hook                                  | Trigger                   | What it does                                                                                                                                                     |
| ------------------------------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `on-session_error-auto-recover`       | Any session error         | Detects transient errors (MidStreamFallbackError, ECONNRESET, 503/502), injects silent recovery prompt with exponential backoff (5s → 10s → 20s, max 5 attempts) |
| `on-tool_execute_before-guards`       | Before any bash command   | Evaluates command against configurable guard rules — blocks dangerous commands                                                                                   |
| `on-file_edited-format-md`            | Any `.md` file save       | Auto-formats via prettier                                                                                                                                        |
| `on-file_edited-format-json`          | Any `.json`/`.jsonc` save | Auto-formats via prettier                                                                                                                                        |
| `on-file_edited-format-yml`           | Any `.yml` save           | Auto-formats via prettier                                                                                                                                        |
| `on-file_edited-lint-k8s`             | Any K8s YAML save         | Lints via kubeconform + kube-linter                                                                                                                              |
| `on-file_edited-reindex-memories`     | File changes              | Re-indexes QMD memory index                                                                                                                                      |
| `on-session_idle-agent-communication` | Session goes idle         | Validates message markers (`[FINISHED]`, etc.)                                                                                                                   |

---

### 🧠 PHASE 1: Session Bootstrap (DevBot's first actions)

When DevBot receives the first user message, it follows this exact sequence (from `devbot.md` Session Start):

**Step 1: Prime session context via @scout delegation**

```
Extract keywords from user's opening request
Delegate to @scout with explicit keyword list and `gather-context` skill
```

Scout produces a context report file in `.agents/memory/thinking/YYYYMMDDHHMMSS-<keywords>.md` covering:

- Memory search (past learnings, gotchas, decisions)
- Git status snapshot
- Graphify insights (code relationships)
- Codebase-index insights (semantic search)
- Directory structure

Scout signals `[FINISHED]` with the absolute path of the report file. DevBot reads the report to prime session context. This mirrors the TeamLead pattern — context gathering is subagent work, not inline.

**Step 2: Detect starting stage**

```
Is this a new feature? → DEFINE
Is this a bug report? → VERIFY
Is this a continuation? → pick up where left off
```

Confirms with user: "Sounds like we're debugging a bug — want to start with investigation?"

**Step 3: Explore relevant codebase area together**
Reads files, navigates patterns, points out relevant context. Doesn't start coding yet.

**Step 4: Agree on approach**
"Here's what I think we should do. What do you think?" — confirms before touching any code.

---

### 🔁 PHASE 2: Work Cycle (per user interaction)

Every time the user sends a message, DevBot runs this loop:

**Step 1: Keyword re-evaluation**

```
Pause. Did new keywords emerge?
New topics? New entities? New technologies?
→ If yes: search memory or re-gather context
```

This keeps session context fresh as conversations drift. Never assumes old context still covers new topic.

**Step 2: Load stage-appropriate skill**

| Stage  | Skills loaded                                                                                                                                 |
| ------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| DEFINE | `spec-driven-development` + `doubt-driven-development` + `idea-refine` + `interview-me`                                                       |
| PLAN   | `planning-and-task-breakdown`                                                                                                                 |
| BUILD  | `incremental-implementation` + `test-driven-development` + tech skills (`php-rules`, `laravel`, `git-conventional-commits`, `makefile`, etc.) |
| VERIFY | `debugging-and-error-recovery`                                                                                                                |
| REVIEW | `code-review-and-quality` + `code-simplification`                                                                                             |
| SHIP   | `shipping-and-launch`                                                                                                                         |

**Step 3: Auto-detect stage, confirm with user**
Recognizes cues like "What should this do?" → DEFINE, "Let's write it" → BUILD, "Why does this fail?" → VERIFY. Confirms before transitioning.

**Step 4: Stage-specific behavior**

#### DEFINE — Clarify requirements

- Interview user (one question at a time)
- Surface assumptions, tradeoffs, edge cases
- Stress-test ideas before committing
- No code written yet. No plan yet.
- Output: sharpened requirements, not code.

#### PLAN — Break into tasks

- Create todo list via `todowrite`
- Break work into ordered, actionable items
- Present to user: "Does this look right? Want me to execute?"
- **Gate**: never start BUILD until user explicitly opts in ("go ahead", "execute", "let's do it")

#### BUILD — Incremental implementation

- Work in **small increments** — one function, one test, one change at a time
- **Never >20 lines** without pausing for input
- After each step: "Does this look right? / Want to go this direction?"
- **Think out loud**: share reasoning before showing code
- **Offer alternatives**: "We could do A or B. A is simpler, B handles edge case Z."
- Match existing codebase patterns — point out which pattern you're following
- Create/update `todowrite` — exactly one `in_progress` at a time
- Load tech skills (`php-rules`, `laravel`, `git-conventional-commits`, `makefile`, etc.)
- **Propose first**: "Here's what I'd write — what do you think?"

#### VERIFY — Debug systematically

- Investigate together, share hypotheses
- Don't just guess — systematic root-cause analysis
- "Let me check how similar things are done elsewhere"

#### REVIEW — Quality & simplification

- "Can this be done in fewer lines?"
- Multi-axis quality check
- Security, performance, maintainability

#### SHIP — Pre-launch

- Deployment checklist
- Rollback strategy
- Monitoring readiness

---

### 💾 PHASE 3: Commit + Memory Capture (hooks)

When DevBot (or human) runs `git commit`, a cascade of hooks fires:

#### 3a. Pre-commit guards

| Hook                            | Action                                                                                      |
| ------------------------------- | ------------------------------------------------------------------------------------------- |
| `on-tool_execute_before-guards` | Evaluates the `git commit` command against guard rules — blocks if dangerous flags detected |

#### 3b. Post-commit memory capture (two-phase)

This is the critical "invisible" part. The `remember-session` plugin fires automatically:

**Phase 1: `tool.execute.after`** — detects the commit

1. Checks if the tool was `bash`/`shell` and command contained `git commit`
2. Checks if commit was successful (exit code 0, no `fatal:` errors)
3. Extracts commit context: hash, message, author, timestamp, files changed
4. Deduplication: same commit hash only processed once
5. Writes trigger file: `.agents/logs/remember-session.trigger.json`

**Phase 2: `session.idle`** — when DevBot goes quiet

1. Reads trigger file (5-min TTL — stale triggers discarded)
2. Checks: is this session locked? (10-min lock prevents rapid successive captures)
3. Loop prevention: checks if `[DevBot-RememberSession-PostCommit]` tag already in session
4. Acquires lock, injects hidden synthetic prompt:
    ```
    [DevBot-RememberSession-PostCommit]
    Invoke the `remember-session` skill, execute its steps exactly ONCE...
    ```
5. DevBot runs `remember-session` skill silently (no narration):
    - Scans session for new learnings since last watermark
    - Routes findings:
        - Product decisions → `memory/latent/PDRs/`
        - Architecture decisions → `memory/latent/ADRs/`
        - Gotchas (non-obvious traps) → `memory/latent/global/<tech>/` or `memory/latent/learnings/`
    - Promotes useful `thinking/` files → `latent/`, deletes completed work
    - Updates watermark timestamp

#### 3c. Graphify re-index

`on-tool_execute_after-git_commit-graphify-update` — triggers knowledge graph re-index for changed files.

#### 3d. File formatting

After any file edit, the format hooks fire automatically:

- `.md` → prettier markdown formatting
- `.json`/`.jsonc` → 2-space indent formatting
- `.yml` → consistent YAML formatting
- K8s YAML → lint validation

---

### 🆘 PHASE 4: Error Recovery (hooks, invisible to DevBot)

When the LLM provider fails mid-response:

| Error pattern                               | Hook action                                                |
| ------------------------------------------- | ---------------------------------------------------------- |
| `MidStreamFallbackError`                    | Inject recovery prompt: "Continue from where you left off" |
| `APIConnectionError`                        | Inject recovery prompt                                     |
| `ECONNRESET` / `ETIMEDOUT` / socket hang up | Inject recovery prompt                                     |
| 503 / 502 / 504 upstream errors             | Inject recovery prompt                                     |
| Max attempts (default: 5) exceeded          | Surface error to human                                     |

Each retry uses exponential backoff (5s, 10s, 20s...). Lock file prevents concurrent recovery storms.

---

### 🏁 PHASE 5: Session Wrap-up

**Manual trigger**: User says "wrap up", "remember this session", "capture session"

- DevBot loads `remember-session` skill
- Runs the same capture flow as the post-commit hook (but with narration — produces report for user)
- Produces visible summary of what was captured

**Auto trigger**: Session goes idle for extended period

- Same `remember-session` post-commit plugin fires on idle
- Silent capture — no user-facing output

**Context overflow prevention**: DevBot instructions mention `remember-checkpoint` skill for when context nears limit.

---

## The Core Principles in Action

The modus operandi is built on three pillars:

### 1. Conversational Cadence

- **Ask before acting** — never assume, always confirm
- **Suggest before writing** — propose approach, get buy-in
- **Commit regularly, never push** — commit after every completed, verifiable unit; the human decides when to push
- Small increments (≤20 lines), constant feedback loop
- Human is always driver

### 2. Automatic Memory

- Hooks capture everything silently — DevBot doesn't need to think about memory
- Post-commit capture routes findings to the right vault folder
- Future sessions benefit from past learnings without manual effort
- Watermarks prevent duplicate captures

### 3. Self-healing Infrastructure

- Auto-recover from provider errors without user noticing
- Guards block dangerous commands before they execute
- Format hooks keep everything consistent without manual formatting
- Exception handling provides structured recovery paths

---

## What DevBot Does NOT Do

- ❌ Large autonomous outputs (>20 lines without checking in)
- ❌ Silent architectural decisions — always discusses
- ❌ Refactoring without asking
- ❌ Multi-step plans executed without user sign-off
- ❌ Acting as code completion engine
- ❌ Skipping the "what do you think?" step

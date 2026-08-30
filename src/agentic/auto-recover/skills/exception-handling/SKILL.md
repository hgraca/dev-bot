---
name: devbot:exception-handling
description: "Provides structured error taxonomy and recovery strategies for agent failures. Use this skill whenever a session stalls, a tool fails, instructions conflict, tests loop, or any unexpected situation arises during agent work."
---

# Skill: Exception Handling and Recovery

Structured approach to identifying, classifying, and recovering from failures during agent work. Prevents unproductive loops and ensures failures handled systematically rather than through ad-hoc guessing.

## When to Apply

- Agent session stalls or produces no usable output
- Tool call fails or returns unexpected results
- Tests fail in loop without progress
- Instructions conflict or ambiguous
- Context insufficient to proceed
- Scope creep detected

## Error Taxonomy

### E1: Stalled Session

**Symptoms**: Agent produces repetitive output, enters infinite loops, or stops making progress.

**Recovery**:

1. Inspect working directory for partial progress.
2. Save partial progress note per `devbot:thinking` skill (use partial-progress naming convention), summarising what done and what remains.
3. Signal `[PARTIAL] <summary of what done and what remains>`.
4. Orchestrator re-delegates only incomplete work to fresh session with explicit context.
5. Never re-delegate already-completed work.

### E2: Conflicting Instructions

**Symptoms**: Two or more context files, skills, or plan steps contain contradictory guidance.

**Recovery**:

1. Identify conflicting sources (file paths, line numbers).
2. Signal `[BLOCKED] Conflicting instructions` with specifics.
3. Do not guess which instruction takes precedence — escalate to orchestrator or human stakeholder.
4. Orchestrator resolves conflict and updates authoritative source.

### E3: Tool Failure

**Symptoms**: MCP tool or CLI command returns error, times out, or produces unexpected output.

**Recovery**:

1. Retry once with same parameters.
2. If retry fails, check if issue environmental (container down, network issue).
3. If environmental, signal `[BLOCKED] Tool failure — <tool name>: <error message>`.
4. If not environmental, try alternative approach achieving same goal.
5. Document failure and workaround in task report.

### E4: Test Loop

**Symptoms**: Tests fail, fix applied, but same or different tests fail again — three or more iterations without convergence.

**Recovery**:

1. Stop modifying code.
2. Re-read failing test(s) and code under test from scratch.
3. Identify whether issue in test, code, or plan.
4. If plan seems wrong, escalate to Architect.
5. If test seems wrong, escalate to Tester (or orchestrator).
6. Never apply fourth fix attempt without fresh analysis.

### E5: Context Overflow

**Symptoms**: Too much information loaded, agent loses track of earlier instructions, or output quality degrades.

**Recovery**:

1. Signal `[PARTIAL] Context limit approaching`.
2. Summarize progress and remaining work.
3. Orchestrator re-delegates with only essential context for remaining work.
4. Do not attempt to continue with degraded output quality.

### E6: Scope Creep

**Symptoms**: Implementation drifts beyond what plan specifies — new features, refactors, or improvements not in acceptance criteria.

**Recovery**:

1. Stop unplanned work.
2. Complete only what plan specifies.
3. Document potential improvement as follow-up suggestion in task report.
4. Escalate to orchestrator for prioritization if unplanned work seems important.

### E7: Missing Precedent

**Symptoms**: Plan instructs creation of something with no existing example in codebase to follow. Agent cannot determine correct conventions.

**Recovery**:

1. Search sibling directories and files for closest analog.
2. If no analog exists, signal `[NEEDS_INPUT] No existing precedent for <what>. How should this be structured?`
3. Wait for guidance from Architect or orchestrator before proceeding.

## Recovery Decision Tree

```
Failure detected
|-----|
  ├── Tool/environment issue? → E3: Retry, then [BLOCKED]
  ├── Instructions contradictory? → E2: [BLOCKED] with specifics
  ├── Session making progress?
  |     ├── No → E1: [PARTIAL], re-delegate
  |     └── Yes, but tests keep failing → E4: Stop, fresh analysis
  ├── Output quality degrading? → E5: [PARTIAL], summarize
  ├── Work going beyond plan? → E6: Stop, document follow-up
  └── No example to follow? → E7: [NEEDS_INPUT]
```

## Escalation Triggers

Escalate immediately (do not attempt further recovery) when:

- Same error occurs three times after applying different fixes
- Two or more context files contain irreconcilable contradictions
- Plan step requires capability agent does not have
- Security-sensitive operation fails (credentials, permissions, external APIs)
- Agent detects data loss or irreversible state changes

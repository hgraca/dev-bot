---
name: make-adr
description: "Creates Architecture Decision Records (ADRs). Use this skill whenever the user asks to create, write, or draft an ADR, document an architecture decision, record a technical decision, or capture why a choice was made — even if they do not use the term 'ADR'."
---

# Skill: Create Architecture Decision Record (ADR)

## When to Apply

Activate when asked: create/write/draft ADR, document architecture decision, record technical decision.

## Inputs

If not provided, ask before starting:

1. **Topic** — architectural question or choice being decided
2. **Decision status** — already made (which option and why) or still exploring (ADR ends with `[pending review]`)
3. **Proponents and deciders** — default: `Herberto` / `[pending review]`
4. **Date** — default: today in `YYYY-MM-DD`

Do not ask for information inferable from codebase. Research first.

## Process

### Step 1 — Research

Explore codebase for:

- Current state (existing patterns and implementations)
- Pain points motivating decision
- Two or more credible options
- Relevant code, config, or documentation

### Step 2 — Determine ADR number

List files in `.ai/local/ADRs/`. New number = highest `ADR-NNN` + 1, zero-padded to three digits.

### Step 3 — Derive filename

Pattern: `ADR-{NNN}-{kebab-case-title}.md`

Title: short, present-tense imperative phrase, <50 chars, lowercase kebab-case, no articles unless essential.

Example: `.ai/local/ADRs/ADR-015-enforce-cursor-based-pagination.md`

### Step 4 — Write ADR

Use template at `./_template.md`. Match style of existing ADRs, if any.

#### Structure

**Header:**

```markdown
# {Title}

Created by: Herberto
Created time: {Month DD, YYYY H:MM AM/PM}
Last edited by: Herberto
Last updated time: {Month DD, YYYY H:MM AM/PM}
```

**Summary** — structured paragraph:

```markdown
**In context of** {use case}
**facing**

- {concern}
  **we decided for** {chosen option}
  **to achieve**
- {quality/benefit}
  **accepting** {key downside/trade-off}.
```

**Context** — 3-5 paragraphs: current state, why decision needed, anti-patterns/failure modes, what ADR establishes. Do not name chosen option here.

**Options** — at least two, mark chosen with `(decided)`:

```markdown
### Option N — {Name} (decided)

{Description}
**Pros**

- {argument}
  **Cons**
- {argument}
```

**Decision** — opens with "We adopt **Option N**: ...", explains why, uses comparison tables when applicable.

**Design Constraints** — each constraint: `### Heading` + paragraph. Ends with `### Rationale` numbered list (bold titles + explanation paragraphs).

**Consequences and Follow-Up Work** — opens with "To implement this decision, we need to:", followed by actionable tasks. Ends with:

```markdown
### Proponents: {name(s)}

### Deciders: {name(s) or [pending review]}

### Date: {YYYY-MM-DD}
```

#### Required section: Convention deviation justification

If this ADR deviates from established project convention (Explicit Architecture, naming, layering, testing, etc), it MUST include section before `Consequences and Follow-Up Work`:

> ## Why existing convention is insufficient
>
> - **Existing convention**: <one-line summary of what convention says>.
> - **Where it falls short for this case**: concrete failure mode convention does not address. Cite file, test scenario, or pattern in codebase.
> - **What was tried first**: at least one attempt to comply with convention before deciding to deviate. If no attempt made, deviation premature — comply first, then write ADR if compliance fails.

If you cannot complete three bullets above, do not deviate. Convention exists because someone considered alternatives; you must engage with their reasoning, not bypass it.

ADRs documenting _conformance_ (not deviation) do not need this section.

### Step 5 — Save

Write to `.ai/local/ADRs/{filename}.md`. Confirm file path and title to user.

## Quality Checklist

- Filename follows `ADR-{NNN}-{kebab-case-title}.md`
- Title is present-tense imperative, <50 chars
- Summary uses exact structured format
- At least two options, chosen marked `(decided)`
- Pros/cons are specific, not generic
- Decision opens with "We adopt **Option N**:"
- Every Design Constraint has heading + paragraph
- Rationale items numbered with bold titles
- Follow-up tasks are concrete and actionable
- Proponents, Deciders, Date filled in
- No template section missing or empty

## Style Rules

- Clear, direct, third-person technical prose. No first-person.
- **Bold** for key terms being defined or distinguished.
- Tables for comparing across multiple dimensions.
- Code blocks for URLs, JSON, config snippets.
- `##` for top-level sections, `###` for sub-sections.
- No sections beyond template. No emoji.

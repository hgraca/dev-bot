---
name: devbot:improve-implementation
description: "Analyzes completed implementation iterations and produces a coding quality report: compares iteration outcomes, grades quality, traces each weakness back to a specific gap in instruction/context files, and logs a grading table. Use this skill after one or more implementation iterations complete to assess quality trends and find the root causes of remaining issues."
---

# Create coding quality report

1. Copy last iteration interactions report (`pokeapi-v<iteration>/.ai/team/epics/kata/interactions.md`) to `./reports/interactions.v<iteration>.md`

2. Compare all iterations built for epic `.ai/team/epics/kata` (`pokeapi-v*/` folders), focus on progress in last iteration.
   Create report in `reports/quality-report-v<iteration>.md`.
   Follow guide `.ai/tasks/quality-report-guide.md` to produce output comparable to `.ai/tasksquality-report-example.md` so results comparable across iterations.

3. Produce root-cause analysis tracing each weakness in last iteration back to specific gaps in `.ai/` files (context, roles, workflows).
   For gap between last iteration and 100% grade, map gaps with changes applied to skills files (`.ai/*.md`)

4. In `./reports/01-implementation_iterations_quality.md`, in grading table, log row with:
    - iteration number
    - quality grade
    - issues addressed in this iteration
    - issues still to address to reach 100% grade

5. Commit all changes

# Implementation Quality Report Guide

Use this guide to produce comparable quality reports for code implementations.
All reports following this guide comparable to each other and to example in
`.ai/tasks/quality-report-example.md`.

---

## 1. Inputs Required

Before writing report, gather for each implementation being evaluated:

1. **Source code** — all `src/` and `tests/` files
2. **Test results** — coverage percentage, PHPStan output, test pass/fail
3. **Commit history** — number of commits, commit style, per-task vs bundled
4. **Interactions report** (if available) — agent session flow, stalls, recovery actions
5. **Reference standards** — `.ai/context/ARCHITECTURE.md`, `.ai/team/workflows/IMPLEMENTATION.md`
6. **Prior iteration reports** (if this is incremental evaluation)

---

## 2. Report Structure

Every report MUST use this structure with these exact section numbers and titles:

```markdown
# Quality Report: <scope description>

## Epic: <epic name>

---

## 1. Approach Overview

<One subsection per implementation. Describe architecture, key decisions, file counts.>

## 2. Comparison by Dimension

<Table comparing all implementations across consistent dimensions.>

## 3. Strong Points

<One subsection per implementation. Bullet list of strengths.>

## 4. Weak Points

<One subsection per implementation. Bullet list with point deductions.>

## 5. Grades

<Table with all implementations and their grades.>

## 6. Grade Justification

<Explains gaps between implementations using +/- point accounting.>

## 7. Summary

<1–3 sentences per implementation summarizing its position.>
```

### Optional Additional Sections (for iterative evaluations)

When report covers iteration that builds on prior work, add:

```markdown
## 8. Conclusions

<Achievements and regressions of latest iteration.>

## 9. Root-Cause Analysis

<Traces each weakness to specific gaps in .ai/ files. Only for latest iteration.>
```

---

## 3. How to Write Each Section

### Section 1: Approach Overview

For each implementation, write subsection with:

1. **Title format**: `### V<N> — <Descriptive Label>` (e.g., "V12 — DeepSeek V3 0324")
2. **Architecture summary** (2–4 sentences): domain model approach, port design, CQRS usage
3. **Key differentiator** (1 sentence): what makes this iteration unique
4. **Bug handling decision**: "The team chose to **fix/preserve** the known bug"
5. **File counts**: `**Source files: X | Test files: Y | Total: Z**`

If many prior iterations exist, reference previous report rather than repeating:
`See quality-report-v<N>.md for full evolution from V1 through V<N>.`

### Section 2: Comparison by Dimension

Use markdown table. Left column = dimension name, subsequent columns = implementations.

**Required dimensions** (include all that apply):

| Category       | Dimensions to evaluate                                                               |
| -------------- | ------------------------------------------------------------------------------------ |
| Domain         | Domain richness, Bug handling, Level calc location                                   |
| Ports          | Port design, Port DTO typing                                                         |
| Application    | CQRS/Message-bus, Application DTO                                                    |
| Infrastructure | Infrastructure test strategy, Input validation, URL safety, Defensive infrastructure |
| Testing        | Test coverage, Test directory split, Named test doubles, End-to-end smoke test       |
| Code style     | FQN usage, `assert()` usage, Classes `final`, Dead production code                   |
| Process        | Commits, Developer session stalls, Reviewer invocations                              |
| Metadata       | Composer metadata, Output formatting, LLM used                                       |

Include only dimensions where at least one implementation differs from another.
Use **bold** to highlight latest iteration's values.

### Section 3: Strong Points

For each implementation, list 4–8 bullet points. Each bullet:

- Starts with **bold label** (2–4 words)
- Explains what was done well
- Explains why it matters (what failure it prevents or what quality it enables)

Example:

```markdown
- **100% line coverage** (122/122 lines): Achieved through targeted gap-closure tests,
  covering all defensive branches in HTTP adapters.
```

### Section 4: Weak Points

For each implementation, list all weaknesses. Each bullet:

- Starts with **bold label**
- Includes **point deduction** in parentheses: `(-X.XX)`
- References specific rule or standard violated
- States observable symptom

Example:

```markdown
- **FQN in test code** (-0.5): 8 occurrences of `\InvalidArgumentException`.
  ARCHITECTURE.md states: "We import classes whenever possible...
  This applies to both production and test code."
```

### Section 5: Grades

Use a simple two-column table:

```markdown
| Solution | Grade        |
| -------- | ------------ |
| **V1**   | **73 / 100** |
| **V2**   | **68 / 100** |
```

Include ALL iterations ever evaluated (carry forward from prior reports).

### Section 6: Grade Justification

Compare adjacent iterations or the most recent against the prior best. Structure:

```markdown
### V<N> vs V<M> (V<N>: XX.XX, V<M>: YY.YY — Z-point gap)

**V<N> weaknesses that V<M> doesn't have (-Z total):**

1. **<Label>** (-X.XX): <explanation>

**V<N> strengths over V<M> (offset +W total):**

1. **<Label>** (+X.XX): <explanation>

**Net: ±X points compared to V<M>**
```

Every point deduction in Section 4 must appear here. The sum of all +/- must equal the gap.

### Section 7: Summary

One bullet or short paragraph per implementation. Focus on positioning:

- What niche does it fill? (cost-efficient, highest-quality, fastest, etc.)
- What is the primary differentiator from adjacent iterations?

### Section 8: Conclusions (optional, for iterative reports)

Two subsections:

1. **Achievements** — numbered list of what the latest iteration accomplished
2. **Regressions** — numbered list of what got worse compared to prior best

End with a "Remaining Gap to 100" table:

```markdown
| Gap        | Points | Fix                             |
| ---------- | ------ | ------------------------------- |
| <weakness> | -X.XX  | <proposed change to .ai/ files> |
```

### Section 9: Root-Cause Analysis (optional, for iterative reports)

For each weakness in the latest iteration, write:

```markdown
### Gap N: <Title> — **-X.XX points**

**Observed behavior:** <what the code does wrong>

**Root cause in `.ai/<file>`:** <which rule is missing, unclear, or unenforced>

**Fix required:**
<concrete change to the .ai/ file>
```

End with a summary table:

```markdown
| Gap | Points | Source file | Root cause | Proposed fix |
| --- | ------ | ----------- | ---------- | ------------ |
```

---

## 4. Grading Methodology

### Grade Scale

| Range    | Meaning                                                                          |
| -------- | -------------------------------------------------------------------------------- |
| 95–100   | Production-ready. All architecture rules followed. Full coverage. Clean process. |
| 90–94    | High quality. Minor style or process issues. No architectural violations.        |
| 80–89    | Good. Some architectural gaps (missing VOs, leaky ports, incomplete coverage).   |
| 70–79    | Competent. Correct output but significant architectural or testing gaps.         |
| 60–69    | Functional. Works but violates multiple architecture rules.                      |
| Below 60 | Incomplete. Missing layers, broken tests, or incorrect output.                   |

### Point Deduction Scale

Deductions applied to base of 100. Sum of all deductions = 100 - grade.

| Severity | Points     | Examples                                                                    |
| -------- | ---------- | --------------------------------------------------------------------------- |
| Critical | -5 to -15  | Incorrect output, broken tests, missing entire layer                        |
| Major    | -2 to -5   | Anemic domain, leaky port, no test coverage on a layer, hidden dependencies |
| Moderate | -1 to -2   | Missing URL encoding, test suite mislabeling, dead code, commit bundling    |
| Minor    | -0.1 to -1 | FQN usage, non-final classes, cosmetic choices, session stalls              |

### What to Evaluate (Checklist)

Score implementation against these criteria. Each maps to potential deduction:

**Architecture (max ~30 points at risk)**

- [ ] Domain uses Value Objects (not primitives) for domain concepts
- [ ] Domain classes are `final readonly` with validation in constructors
- [ ] Domain behavior lives on the entity/aggregate that owns the data
- [ ] Dependencies are explicitly injected (no hidden instantiation)
- [ ] Port interfaces don't expose transport concepts (URLs, headers)
- [ ] Port contracts use typed DTOs (not raw arrays)
- [ ] Exceptions that cross boundaries are defined at port level
- [ ] Application layer returns a DTO to presentation (no domain leakage)
- [ ] Output formatting is a separate concern from application logic
- [ ] Directory structure matches ARCHITECTURE.md

**Correctness (max ~15 points at risk)**

- [ ] Output matches expected behavior (byte-identical for refactoring)
- [ ] Known bugs are either fixed with justification or preserved with justification
- [ ] Edge cases are handled (empty input, overflow, missing data)

**Testing (max ~20 points at risk)**

- [ ] Coverage meets target (90% floor, 100% goal)
- [ ] Tests are deterministic (no network calls, no flakiness)
- [ ] Unit/Integration split is correct
- [ ] Named test doubles (no anonymous classes, no mocks unless necessary)
- [ ] Test naming follows `it_*` convention
- [ ] End-to-end smoke test exists
- [ ] Error paths are tested

**Infrastructure (max ~15 points at risk)**

- [ ] External data validated defensively (type-checks on every field)
- [ ] URL encoding applied to interpolated values
- [ ] HTTPS validation on URLs from API responses
- [ ] `json_decode` with error handling

**Code Style (max ~10 points at risk)**

- [ ] No FQN (use imports everywhere, source and test)
- [ ] All classes `final` (source and test)
- [ ] No `assert()` for runtime checks
- [ ] No dead production code
- [ ] Composer metadata correct

**Process (max ~10 points at risk)**

- [ ] Per-task commits (not bundled)
- [ ] Reviewer invoked per task
- [ ] Static analysis passes at max level with 0 errors
- [ ] Session stalls handled gracefully

---

## 5. Comparability Rules

Ensure reports comparable across different implementations:

1. **Always use same section structure** — sections 1–7 mandatory; 8–9 optional
2. **Always carry forward all prior grades** — Section 5 must include every iteration ever graded
3. **Always use same deduction scale** — Minor: 0.1–1, Moderate: 1–2, Major: 2–5, Critical: 5–15
4. **Always reference ARCHITECTURE.md as standard** — deductions for violations of stated rules
5. **Always justify every point** — no deduction without specific rule reference or observable symptom
6. **Grade code as delivered, not as intended** — if fix planned but not applied, still deduction
7. **Compare apples to apples** — when implementations use different plans, note in Section 1 but grade against same ARCHITECTURE.md standard
8. **Never grade on effort, session time, or LLM cost** — only on quality of delivered code
9. **Account for accepted trade-offs** — if plan explicitly accepts limitation (e.g., `file_get_contents`), reduce deduction (cosmetic: -0.1 to -0.15) but still note it

---

## 6. Writing Tips

- **Be specific**: "8 occurrences of `\InvalidArgumentException` in test files" not "some FQN issues"
- **Be traceable**: reference line numbers, file paths, or rule citations
- **Be balanced**: every implementation has both strengths and weaknesses
- **Be concise**: bullets, not paragraphs. Tables, not prose where possible
- **Be fair**: same violation in two implementations gets same deduction
- **Be cumulative**: when later iteration fixes prior weakness, note it as strength; when it introduces new one, note it as regression

---

## 7. Checklist Before Submitting

- [ ] All mandatory sections (1–7) present with correct numbering
- [ ] Section 2 table includes all implementations being compared
- [ ] Every deduction in Section 4 has point value and rule reference
- [ ] Section 5 includes ALL iterations ever evaluated
- [ ] Section 6 point accounting sums to exact gap between iterations
- [ ] Summary concise (1–3 sentences per implementation)
- [ ] If iterative: Sections 8–9 present with gap-to-fix mapping
- [ ] Report self-contained (reader doesn't need to open source code to understand findings)
- [ ] Grades consistent with deduction scale (deductions sum correctly)

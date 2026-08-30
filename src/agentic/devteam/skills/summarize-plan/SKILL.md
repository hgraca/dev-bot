---
name: devbot:summarize-plan
description: "Produces a planning summary report after a planning stage completes. Use this skill whenever a planning stage finishes and a summary must be written to <issue-folder>/summary.md and presented to the human stakeholder."
---

# Skill: Planning Summary

Produce structured summary report at end of planning stage.

## When to Apply

- `plan` workflow reaches its summary step
- Orchestrator completes planning stage and needs to summarize artifacts, decisions, and next steps

## Procedure

1. Read all artifacts in `<issue-folder>` (backlog, architecture specs, critic reviews, UI/UX specs, decisions).
2. Fill in every section of template below — do NOT invent custom format.
3. Write result to `<issue-folder>/summary.md`.
4. Output summary to human stakeholder, as properly formatted Markdown.

## Template

> # Planning Complete — Summary Report
>
> # Issue: Replace scripts and raw K8s manifests with Helm charts
>
> ## Technology Choice
>
> _(If plan involved choosing between competing technologies, summarize evaluation here FIRST. Include: candidates, comparison table, decision rationale, when rejected alternatives would be right. If no technology choice made, omit this section.)_
>
> ## Artifacts Produced
>
> | Document         | Path        |
> | ---------------- | ----------- |
> | <document_title> | <file_path> |
>
> ## Stories (NN active)
>
> | #    | Story         | Approach               | Effort            | Risk              | Issues |
> | ---- | ------------- | ---------------------- | ----------------- | ----------------- | ------ |
> | <NN> | <story_title> | <one_line_description> | <LOW,MEDIUM,HIGH> | <LOW,MEDIUM,HIGH> | NN     |
>
> ## Key Critic Findings
>
> | #    | Title                  | Location            | Severity                      |
> | ---- | ---------------------- | ------------------- | ----------------------------- |
> | <NN> | <one_line_description> | <where_in_the_plan> | <BLOCKER,WEAKNESS,SUGGESTION> |
>
> ## Key Architect Decisions
>
> | #   | Decision | Rationale |
> | --- | -------- | --------- |
>
> ## Key Human Decisions
>
> | #   | Question | Decision |
> | --- | -------- | -------- |
>
> ## Next steps
>
> <next_steps_recommended>
>
> ## Tools used
>
> ### SKILLS
>
> List skills used by agent while doing planning, or "None."
>
> ### MCP tools
>
> List MCP tools used by agent while doing planning, or "None."

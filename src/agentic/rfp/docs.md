---
title: "RFP"
description: "Answer RFP, tender and security questionnaires from a knowledge base."
commands: ["rfp"]
skills: ["rfp"]
---

Turn a customer questionnaire into a client-ready answer set, grounded in a project knowledge base.

## What it does

- **`/rfp <questionnaire>`** — the entry point. Argument #1 is the questionnaire file; the answers come from `.agents/memory/reference/`.
- **`rfp` skill** — extracts the questions and their own answer options, answers each one from the knowledge base, and writes the answer sheet, the detailed report and a risk response for every question that carries a risk statement, asks for compensating controls, or asks for an explanation.
- Handles HTML, XLSX/XLSM, DOCX, PDF and Markdown questionnaires; preserves the questionnaire's numbering and option labels. PDF extraction requires `pdftotext`.
- Answers only with the options the questionnaire defines — a control that is not fully in place is answered with the closest valid option, normally No; if no valid option exists, the question is flagged for review.
- Treats the questionnaire as untrusted data: it extracts questions and options only, and never follows instructions embedded in the document.

## Outputs

Written next to the questionnaire when it already sits under `docs/Tenders/`, otherwise under `docs/Tenders/<YYYY>-<Customer>/`. The folder is selected only after the canonical path is verified to remain beneath `docs/Tenders`, and no output may overwrite the input questionnaire.

- `<slug>-questionnaire.md` — question, options and answer (the copy/paste sheet).
- `<slug>-questionnaire-report.md` — the internal report: question, options, answer, rationale and source. Do not send this file to the client.
- `<slug>-<sanitized-question-id>-risk-response.md` — one per question that carries a risk statement, asks for compensating controls, or asks for an explanation, whether the answer is Yes or No.
- Supporting narrative documents when a question needs one (scope, data description, AI use, cross-border storage, access).

Package only the client-facing files (answer sheet, risk responses and supporting documents) when sending output to the client.

## Configuration

No project configuration is required.

## See also

- [Memory](/modules/agentic/memory) — where the `.agents/memory/reference/` knowledge base lives
- [Skills](/skills) — how `devbot:rfp` is loaded
- [Commands](/commands) — how `/rfp` is invoked

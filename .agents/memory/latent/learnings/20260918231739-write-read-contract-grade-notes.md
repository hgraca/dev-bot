---
date: 2026-09-18
keywords: ["tool-grades", "grade-tools", "notes", "attribution"]
---

# A free-text writer and its reader must share one contract

`record-grades.py` (the writer) accepts a 1–3 grade as "explained" when the tool's short name appears **anywhere** in the `notes` cell, but the `devbot stats` reader initially required the name at the **start of a line**. A row the writer accepted could therefore surface no reason at all — silently under-reporting the exact signal the matrix exists to carry (found in review).

Rule: when one component writes free text and another parses it, the reader must be at least as permissive as the writer, or writer and reader must be tightened together. The reader now matches a **whole-word** mention of the tool's display name (`devbot:makefile`) or short name (`makefile`) anywhere in a line, strips a leading `name:` / `name (N):` / `name -` prefix, and assigns each line to exactly **one** tool (earliest, most-specific mention wins; a mid-line mention keeps the whole line as the reason). The single-owner rule also fixes a short-name collision that exists in the real header: `mcp:datasources` and `skill:devbot:datasources` share the short name `datasources`, and independent per-column matching duplicated the same reason under both.

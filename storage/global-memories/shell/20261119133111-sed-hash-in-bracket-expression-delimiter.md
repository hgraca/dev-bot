---
date: 2026-11-19
keywords: ["shell", "sed", "portability", "bracket-expression"]
aliases: ["sed delimiter hash", "bsd sed", "substitution delimiter"]
---

## `#` inside a bracket expression breaks the `s###` delimiter on non-GNU sed

`sed -E 's#^[a-z]+://##; s#[/?#].*##'` is a trap: the `#` inside `[/?#]` can be read as the end of the
substitution, because the delimiter is recognised before the bracket expression is parsed. GNU sed
tolerates it and the expression works — verified: the input `https://example.com/path?q=1#frag` yields
`example.com` — so the defect is invisible on Linux and surfaces only on a BSD sed (macOS), where the
same script mis-parses the host and every URL helper built on it follows. Since GREP/SED portability is
one of the rules for cross-platform scripts, prefer a delimiter that does not occur in the expression
(`s|[/?#].*||`) or escape the literal (`[/?\#]`). Generalisable: any `s<d>…<d>` whose pattern matches a
character class containing the delimiter is a portability hazard, and "it works on my GNU tools" is not
evidence.

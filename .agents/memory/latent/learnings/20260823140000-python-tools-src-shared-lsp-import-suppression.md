---
date: 2026-08-23
keywords: ["python", "sys.path", "lsp", "type-ignore", "src/_shared"]
---

# Python tools importing from src/_shared need `type: ignore[import-not-found]`

The `format-md.py` / `format-json.py` / `format-yml.py` tools import `editorconfig` from `src/_shared/` by inserting the path at runtime (`sys.path.insert(0, ...)`), which works when executed but makes static analyzers flag `Import "editorconfig" could not be resolved`. `# noqa: E402` only silences flake8's "import not at top of file" — it does nothing for the LSP/type-checker unresolved-import error. Add `# type: ignore[import-not-found]` (Pyright/Pylance) next to it; JetBrains/PyCharm instead wants `# noinspection PyUnresolvedReferences`. Verify the import still runs before committing, since the suppression masks a genuinely broken path if the runtime insert is wrong.

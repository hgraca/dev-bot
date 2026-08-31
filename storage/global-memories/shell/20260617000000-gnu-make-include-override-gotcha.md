---
date: 2026-06-17
keywords: ["shell", "makefile", "gnu make", "override", "include"]
---

## GNU Make `include` does not enable target overrides — last definition wins

When using `include file.mk` in a Makefile, the included file is processed at the point of the include directive. Any targets defined in the included file are established first. If the main Makefile later defines the same target (same name with single-colon rule), the main Makefile's definition **overrides** the included one — not the other way around.

This is the opposite of what many developers expect (intuition: "override file should have the final word, like CSS cascade"). In GNU Make, the last definition in file processing order wins, regardless of which file it came from.

**Fix**: To allow a file like `Makefile.proj.mk` to override targets from the main Makefile, it must be included AFTER those targets are defined — either via `-include` at the end of the main Makefile, or by not defining those targets in the main Makefile at all and leaving them to the override file.

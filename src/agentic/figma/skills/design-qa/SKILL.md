---
name: devbot:design-qa
description: "Use when comparing a Figma frame with the implemented page and reporting differences. Triggers on 'design QA', 'compare against Figma', 'does this match the design'."
---

# Design QA

Compare a Figma frame with the running implementation and produce a severity-ranked report mapped to
`file:line`. **Do not edit any file unless `--fix` is passed.**

Keep context lean: Figma metadata first, design context only for what is needed, computed styles from
ONE evaluate script. Never take full accessibility snapshots of the page unless an element cannot be
located otherwise.

## When to Apply

- The `design-qa` command asks for one Figma frame to be checked against a page.
- The `design-qa-all` batch skill delegates one entry to this workflow.

## Inputs

```text
<figma-link> <url-or-route> [viewport] [--as <userType>] [--scope "<component>"] [--fix]
```

## 0. Parse arguments

- `figma-link` — required. Extract:
  - `fileKey`: the segment after `/design/`, `/file/` or `/proto/` (for
    `/design/:fileKey/branch/:branchKey/` use `branchKey`).
  - `nodeId`: the `node-id` query param, with `-` converted to `:` (e.g. `12-345` → `12:345`).
  - If there is no `node-id`, stop and ask the user to copy the link with a frame selected.
- `url-or-route` — required. An absolute URL is used as-is. A route starting with `/` is resolved
  against `baseUrl` with exactly one slash between them (strip a trailing slash from `baseUrl`).
- `viewport` — optional width in px, or several comma-separated (`1440,1024`). Default: the Figma
  frame width; if unknown, `defaults.viewports[0]`. With several, do steps 1–2 once, then steps 3–6
  for each viewport (session check only for the first), and print one report per viewport with
  designer notes only in the first.
- `--as <userType>` — optional. Must be one of `project.userTypes`. Default: the matching
  `design-map.json` entry's `userType`, else `defaults.userType`, else the first non-`public` entry in
  `project.userTypes`; when there is none, `public`.
- `--scope "<component>"` — optional: the part of the page to check, described in words (e.g.
  `"Unassigned items card"`, `"bottom toolbar"`). Overrides the entry's `scope`.
- `--fix` — optional.

### Config

Read `design-map.json` at the repo root if it exists. Use `baseUrl`, `defaults.tolerancePx` and
`defaults.userType`.

If an entry matches, use these optional fields from it:

| Field         | Use                                                                               |
| ------------- | --------------------------------------------------------------------------------- |
| `userType`    | One of `project.userTypes`; `public` means no login                               |
| `state`       | Clicks or data needed to reach the designed state; perform them before extraction |
| `scope`       | Compare only the elements inside this part of the page, and ignore the rest       |
| `sourcePaths` | Where to look first when mapping issues to source                                 |
| `ignore`      | Differences to skip                                                               |

An entry matches only when **both** its `figma` file key (or branch key when the link carries one) and
its normalized node-id equal the link's — node ids are unique within a file, not across files, so
matching the node id alone can apply another frame's `state`, `scope`, `ignore` and `sourcePaths`. Use
all of a matching entry's fields. If only its `url` matches the route, use just `userType` and
`sourcePaths`; `state`, `scope` and `ignore` describe that entry's frame, not this one.

The `project` block carries everything that would otherwise be a literal from one consumer's codebase:

| Field                                                                       | Use                                                                |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `project.userTypes`                                                         | Allowed `--as` values; `public` means no login                     |
| `project.session.storage` / `.key`                                          | Where one session object lives (`localStorage` / `sessionStorage`) |
| `project.session.detect`                                                    | Map userType → JS expression over the session object `u`           |
| `project.publicRoutes`                                                      | Routes that need no session                                        |
| `project.stabilise.freezeAnimations`                                        | Freeze animations/transitions (default `true`)                     |
| `project.stabilise.hideSelectors`                                           | Overlays hidden with `display:none` before measuring               |
| `project.stabilise.skeletonSelectors`                                       | Placeholders hidden with `visibility:hidden` (layout preserved)    |
| `project.stabilise.loadingSelectors`                                        | Selectors waited out before measuring                              |
| `project.sourceRoot`                                                        | Root searched when mapping issues and imports to source            |
| `project.sharedRoots`                                                       | Directories whose changes affect importing entries (batch)         |
| `project.globalStyleFiles`                                                  | Files whose changes affect every entry (batch)                     |
| `project.tokens.colors` / `.theme` / `.spacing` / `.layout` / `.typography` | Token sources for the hardcoded-value check                        |
| `project.lint.lint` / `.format` / `.stylelint`                              | Commands that accept file paths, run after `--fix`                 |
| `project.baseBranch`                                                        | Default base for `--changed-only` in the batch skill               |

`project.session` models **one** storage key. A project that keeps each role under its own key cannot
be detected this way; omit `detect` and treat the type check as unverified (see step 3).

When the file or a field is absent, use these defaults:

| Field                      | Default                                                    |
| -------------------------- | ---------------------------------------------------------- |
| `baseUrl`                  | `http://localhost:3000`                                    |
| `defaults.tolerancePx`     | `4`                                                        |
| `defaults.viewports`       | `[1440]`                                                   |
| `defaults.userType`        | the first non-`public` `project.userTypes` entry           |
| `project.userTypes`        | `["public"]` — configure the project's roles to use `--as` |
| `project.publicRoutes`     | `[]`                                                       |
| `project.stabilise`        | freeze animations only                                     |
| `project.sourceRoot`       | `src/`                                                     |
| `project.sharedRoots`      | `[]`                                                       |
| `project.globalStyleFiles` | `[]`                                                       |
| `project.tokens`           | none — skip the hardcoded-value check                      |
| `project.lint`             | none — skip the lint step                                  |
| `project.baseBranch`       | `origin/HEAD`, then `main`                                 |

If the route still contains a parameter (`:id`, `:userId`, `:uuid`…), stop and ask the user for a
concrete URL with a record that matches the design.

### Login

Never log in yourself and never handle credentials. The user logs in by hand in the Playwright
browser; its profile keeps the session between runs.

## 1. Figma

1. `get_metadata(fileKey, nodeId)`. Note the frame name, width and height, and its children with their
   ids, names, types and bounds.
2. If the linked node is a SECTION, keep the section id for step 2 and use the largest FRAME inside it
   as the implementation frame. If the link is a FRAME that sits inside a section, **keep the linked
   frame** as the implementation frame and inspect the parent section only for notes — never substitute
   a sibling frame, which may be a different design (e.g. mobile beside desktop).
3. **Scope.** If `--scope` or the entry's `scope` is set, find the node in the metadata that matches it
   (by layer name, or by a heading text inside it; call `get_metadata` on a child instance if its
   contents are needed to decide). If several match, pick the closest one and add an Observation. Use
   that node for steps 4–6 instead of the whole frame. If nothing matches, use the whole frame **and
   clear the effective scope**: steps 3–4 then screenshot the viewport and extract from the whole page,
   so comparing a whole frame against a scoped fragment cannot report the fragment's siblings as
   missing.
4. Without a scope, if the frame has more than 3 top-level children, call `get_design_context` **per
   top-level child**; the metadata doesn't expand instances, so a whole frame can exceed the response
   limit even when it looks small. Skip children that are only images (names starting with
   "Screenshot", PDF previews, pasted app chrome); they're placeholders, not UI to check. Otherwise
   call it once on the frame. Ask for the project's framework hint (e.g. React + MUI) if the tool
   supports one.
5. `get_variable_defs(fileKey, nodeId)` returns the variable names and values used in the frame.
6. `get_design_context` already returns a screenshot; use it as the visual reference. Call
   `get_screenshot(fileKey, nodeId)` only if no screenshot came back (e.g. it was called per child
   section).

## 2. Separate review markup from UI

Treat these as **designer feedback, not UI to implement**:

- Sticky notes, comment-like text layers, and text outside the frame bounds.
- Text inside the frame that reads as an instruction ("make this…", "should be…", "TODO", numbered
  notes like "3: …").
- Ellipses, circles, arrows, lines and highlight rectangles in a non-UI color (red, magenta, bright
  yellow) overlapping UI, especially those named "Ellipse", "Arrow", "Highlight", "Note" or
  "Annotation".
- Figma annotation/measurement layers.

If the link points at a frame, also check the parent SECTION or canvas siblings for notes placed next
to the frame.

For each note record: exact text, the element it refers to (by arrow target, overlap, matching number,
proximity), and its position. Exclude all markup from the element comparison.

## 3. Open the page (Playwright MCP)

1. `browser_resize` to `{ width: viewport, height: <Figma frame height, min 900> }`.
2. Navigate to the target URL.
3. **Session check (when the route is not public).** A route is public when it is listed in
   `project.publicRoutes` or the selected `userType` is `public`.

   First check the configuration: when `project.session.storage` or `project.session.key` is absent,
   the session cannot be read. Do **not** stop for login in that case — record an Observation that the
   session could not be verified, and rely on the navigation and state checks below. A cookie-based
   session has no readable storage key, so this is the normal path for cookie auth.

   Otherwise read the session in one evaluate. Substitute `{{STORAGE}}` (`localStorage` /
   `sessionStorage`), `{{KEY}}` (the JSON-quoted `project.session.key`), and one arrow-function entry
   per `project.session.detect` pair — each expression is spliced into the body, so no string
   evaluation is needed:

   <!-- prettier-ignore -->
   ```js
   () => {
     let raw = null;
     try {
       raw = JSON.parse({{STORAGE}}.getItem({{KEY}}) || "null");
     } catch {
       raw = null;
     }
     const u = raw || {};
     // One entry per project.session.detect: userType -> arrow function of u.
     const detect = {
       {{USER_TYPE}}: (u) => ({{EXPRESSION}}),
     };
     const type =
       Object.entries(detect).find(([, matches]) => {
         try {
           return matches(u);
         } catch {
           return false;
         }
       })?.[0] || null;
     return { pathname: location.pathname, type, hasSession: raw !== null };
   }
   ```

   - If you landed on a public route, `hasSession` is false, or a configured `detect` resolved a type
     different from the selected `userType`, stop with "login needed as <userType>": ask the user to
     log in as that user in the Playwright browser window, then run the command again. Don't clear the
     existing session.
   - When `project.session.detect` is absent, emit `const detect = {}`, verify presence only, and add
     an Observation that the user type could not be checked.

4. Wait until it is stable. Apps commonly keep a websocket or a feature-flag stream open, so **do not
   rely on network idle alone**:
   - `browser_wait_for` a key text from the Figma frame (e.g. the page title); max 15s.
   - Then run the stabilisation script below once.
5. Do **not** force or stub feature flags. Use whatever the project returns for the user, as if the
   flags didn't exist. If the page clearly shows a different variant than Figma, report it as an
   observation, not as N issues.

Stabilisation script (`browser_evaluate`). Substitute the resolved `project.stabilise` values as JS
literals: `{{FREEZE}}` → `true`/`false`, and each `{{…_SELECTORS}}` → a JSON array of selectors (`[]`
when unconfigured). `hideSelectors` are removed from the layout (`display:none`); `skeletonSelectors`
are hidden but keep their box (`visibility:hidden`), which is what preserves the spacing a skeleton
occupies; `loadingSelectors` are waited out. Configure the skeleton/loader selectors your UI kit uses
— otherwise placeholders and loading states are measured as if they were the design:

<!-- prettier-ignore -->
```js
async () => {
  if ({{FREEZE}}) {
    // Finish finite animations so their fill-mode end state stays visible;
    // pause infinite ones. animation:none would reset completed entrance
    // animations to their base style (often opacity:0).
    for (const a of document.getAnimations?.() ?? []) {
      try {
        if (a.effect?.getTiming().iterations === Infinity) a.pause();
        else a.finish();
      } catch {
        a.pause();
      }
    }
    const s = document.createElement("style");
    s.id = "design-qa-freeze";
    s.textContent = `*,*::before,*::after{animation-play-state:paused!important;transition-duration:0s!important;caret-color:transparent!important}`;
    document.head.appendChild(s);
  }
  document.querySelectorAll({{HIDE_SELECTORS}}.join(",") || "__none__").forEach((e) => (e.style.display = "none"));
  document.querySelectorAll({{SKELETON_SELECTORS}}.join(",") || "__none__").forEach((e) => (e.style.visibility = "hidden"));
  await document.fonts.ready;
  const loading = {{LOADING_SELECTORS}}.join(",") || "__none__";
  const until = Date.now() + 8000;
  while (Date.now() < until && document.querySelector(loading)) {
    await new Promise((r) => setTimeout(r, 250));
  }
  return {
    fonts: [...document.fonts].filter((f) => f.status === "loaded").map((f) => `${f.family} ${f.weight}`),
    loading: !!document.querySelector(loading),
    innerWidth,
    dpr: devicePixelRatio,
  };
}
```

If the returned `loading` is still `true`, wait another 8 seconds and re-run the script once. If the
loading indicator is still present, **stop and ask the user** rather than measuring unfinished UI (in
the batch, return `STATUS: blocked — page still loading`).

**Zoom check.** If `innerWidth !== viewport`, the Playwright Chrome profile has a saved per-site zoom.
Compare the effective CSS viewport, not `devicePixelRatio`: a high-DPI display reports
`devicePixelRatio === 2` at 100% zoom, so a non-unit DPR alone is not evidence of zoom. Automation
can't reset zoom: Cmd+0 and the CDP metrics override don't work.

- Ask the user to click the Playwright browser window and press **Cmd+0** (Ctrl+0 on Windows/Linux),
  then re-run the script.
- If they can't, continue, but add an Observation that fluid widths and x positions are unreliable.
  Font sizes, colors, padding, gaps and fixed sizes are still valid in CSS px.

Then take ONE `browser_take_screenshot` for visual comparison. With `scope`, mark the scoped element
in the stabilisation evaluate (`setAttribute('data-qa-scope', '')`) and screenshot only
`[data-qa-scope]`; also limit the extraction targets to it. Otherwise screenshot the viewport, or the
full page if the Figma frame is taller.

**State check, before comparing.** A key text that never appeared is **not** by itself a different
state: report the missing or wrong heading as a High-severity text discrepancy and keep comparing. Stop
and ask the user only when the screenshot shows independent evidence of another state than the Figma
frame — no items where the design shows a list, a different status, edit mode or selection not active,
an empty state — so you do not report every element as "missing".

- Include what you saw: key counts and status from the page, and the component that renders the
  designed state, found by grepping the frame's texts under `project.sourceRoot`.
- If the designed state needs interaction (e.g. "Edit multiple" with N items selected), list the clicks
  needed and offer to perform them before extraction.

## 4. Extract computed styles (one script)

From the Figma design context, build a target list. Include only elements that correspond to Figma
layers: text, buttons, inputs, cards and papers, icons, chips, tabs, table headers and cells, and
containers with visible background, border, padding or gap.

Locate each target with a **stable locator**:

- Prefer `text` (exact visible text) plus an optional `role`/tag, or a stable component-library
  class the project's own UI kit emits.
- Use `nth` for repeats.
- Never use generated Emotion class names (`css-xxxx`).

Run a single `browser_evaluate` with the targets embedded:

<!-- prettier-ignore -->
```js
() => {
  const T = [
    /* { key: "page-title", text: "<exact visible text>", sel: "h1,h2" }, */
    /* { key: "primary-btn", sel: "<stable class or role>", nth: 0 }, */
  ];
  const P = ["color", "backgroundColor", "fontFamily", "fontSize", "fontWeight", "lineHeight", "letterSpacing", "textTransform", "textAlign", "paddingTop", "paddingRight", "paddingBottom", "paddingLeft", "marginTop", "marginBottom", "gap", "rowGap", "columnGap", "borderTopWidth", "borderTopStyle", "borderTopColor", "borderRightWidth", "borderRightStyle", "borderRightColor", "borderBottomWidth", "borderBottomStyle", "borderBottomColor", "borderLeftWidth", "borderLeftStyle", "borderLeftColor", "borderRadius", "boxShadow", "opacity", "display", "flexDirection", "justifyContent", "alignItems", "width", "height"];
  // Compare rendered text: innerText drops hidden descendants and already
  // reflects the CSS text-transform, so use it directly. Only the textContent
  // fallback (SVG and friends) needs the transform applied. Collapse
  // whitespace so a wrapped label still matches.
  const label = (e) => {
    // innerText is a string on HTML elements, including when the visible text is
    // empty — an empty string must not fall back to hidden textContent.
    const hasInnerText = typeof e.innerText === "string";
    const raw = hasInnerText ? e.innerText : e.textContent || "";
    const text = raw.replace(/\s+/g, " ").trim();
    if (hasInnerText) return text;
    const tt = getComputedStyle(e).textTransform;
    if (tt === "uppercase") return text.toUpperCase();
    if (tt === "lowercase") return text.toLowerCase();
    if (tt === "capitalize") return text.replace(/(^|\s)\p{L}/gu, (c) => c.toUpperCase());
    return text;
  };
  const find = (t) => {
    // offsetParent is null for visible fixed-position elements in Chromium, so
    // treat anything with client rects and a visible style as rendered.
    const rendered = (e) => e.getClientRects().length > 0 && getComputedStyle(e).visibility !== "hidden";
    // Limit the search to the scoped element when one is marked, including the
    // scope element itself. Hidden SVGs are excluded like any other candidate.
    const root = document.querySelector("[data-qa-scope]") || document;
    const sel = t.sel || "*";
    const pool = [...(root instanceof Element && root.matches(sel) ? [root] : []), ...root.querySelectorAll(sel)].filter(rendered);
    const wanted = (t.text || "").replace(/\s+/g, " ").trim();
    const matchesText = (e) =>
      label(e) === wanted &&
      (t.sel || ![...e.children].some((c) => rendered(c) && label(c) === wanted));
    const m = t.text ? pool.filter(matchesText) : pool;
    return m[t.nth || 0] || null;
  };
  return T.map((t) => {
    const e = find(t);
    if (!e) return { key: t.key, missing: true };
    const r = e.getBoundingClientRect(),
      cs = getComputedStyle(e),
      o = {};
    P.forEach((p) => {
      const v = cs[p];
      if (v && v !== "normal" && v !== "none" && v !== "0px" && v !== "rgba(0, 0, 0, 0)") o[p] = v;
    });
    return {
      key: t.key,
      tag: e.tagName.toLowerCase(),
      cls: [...e.classList].slice(0, 4).join(" "),
      text: label(e),
      x: Math.round(r.x),
      y: Math.round(r.y),
      w: Math.round(r.width),
      h: Math.round(r.height),
      icon: (e.matches("svg[data-testid]") ? e : e.querySelector("svg[data-testid]"))?.getAttribute("data-testid") ?? null,
      s: o,
    };
  });
}
```

If many targets are `missing`, fix the locators and re-run once with only the missing ones. Don't fall
back to a full snapshot unless that also fails; if it does, use `browser_find` for the specific element.

Icons: component libraries usually expose `data-testid="<Name>Icon"`. Compare that with the Figma
icon/component name.

## 5. Compare

Tolerance is `tolerancePx` (default ±4px) for:

- Spacing: padding, margin, gap, and distances between siblings computed from rects.
- Sizes: width and height of icons and avatars; height only of buttons, inputs and chips (their width
  follows the label or the container). Ignore other widths unless the layout breaks.
- Line-height and border width/radius.

These must match exactly:

- **Colors:** text, background, border and shadow color. Normalize both sides to `#RRGGBBAA`
  uppercase. `rgb(7, 54, 144)` = `#073690FF`. Figma fill opacity and layer opacity count towards
  alpha.
- **Fonts:** family (first family in the stack), size, weight as a number. Compare size in px (the
  browser and Figma both report px; 1rem = 16px). In code, a font size in px or rem is equally fine.

Also check:

- Missing elements (in Figma, not on the page) and extra elements (on the page, not in Figma). Ignore
  app chrome such as the sidebar and top bar unless they are inside the Figma frame.
- Wrong text: compare labels, headings and buttons literally.
- Wrong icon, order of siblings, alignment (left/center/right and vertical alignment within a row).

Ignore:

- Text-length differences caused by real data (names, dates, amounts, row counts), unless they break
  the layout (overflow, wrapping that pushes content, truncation of labels).
- Anything listed in the design-map entry's `ignore` array.
- Sub-pixel rendering differences within tolerance.
- Anything below Medium, such as small letter-spacing deltas or subtle shadow differences. Don't
  report it.

Severity:

- **High:** visibly wrong or breaks the layout. Examples: missing or extra element, wrong component,
  wrong color on a primary action or brand area, overflow or overlap, spacing off by more than 8px,
  wrong text.
- **Medium:** noticeable to a designer. Examples: font size or weight wrong, color off on secondary
  elements, spacing off by 5–8px, wrong icon, alignment off.

## 6. Map to source

For each issue find the `file:line` that produces the style:

1. Start from the entry's `sourcePaths` if a design-map entry matches. Otherwise grep
   `project.sourceRoot` for the route string and the element's visible text.
2. Grep for the element's visible text or label, then follow it to the `sx={…}`, `style={{…}}`,
   `styled()` or shared component (under a `project.sharedRoots` directory) that sets the property.
3. If the value comes from the theme file (`project.tokens.theme.file`, its `styleOverrides` or
   `typography`), point to the theme line and say that a fix there affects the whole app.

Hardcoded values: when the responsible line uses a literal (hex, `rgb()`, `'Npx'`, numeric font
weight), check whether a token exists. Font sizes in px or rem are not hardcoded values; don't list
them. The token sources come from `project.tokens` — **skip this whole section when it is absent**:

- **Colors:** `project.tokens.colors` names the file, the exported object and its key style; compare
  normalized values. Otherwise use the theme palette paths in `project.tokens.theme.file`.
- **Typography:** theme variants listed in `project.tokens.typography` (optional) and the font family.
- **Spacing:** `project.tokens.spacing` names the convention (e.g. `mui-8px` → `theme.spacing(n)` =
  n × 8px, `sx` numeric shorthand `p: 2` = 16px). Mention the spacing unit only when the value is a
  multiple of 4.
- **Layout:** the names in `project.tokens.layout`, in the theme file.

Also map Figma variable names (from `get_variable_defs`) to the code token when the values match.

## 7. Output

Print exactly these sections, nothing more verbose:

```text
**Design QA** — <frame name> vs <url> @ <viewport>px as <userType>
High: N · Medium: N · Designer notes: N · Hardcoded: N

| # | Element | Property | Figma | Actual | Severity | File:line |
|---|---------|----------|-------|--------|----------|-----------|

### Designer notes
| # | Note (exact text) | Element | Status |
Status is one of: Open (still differs) · Resolved (implementation already matches) · Needs clarification.

### Hardcoded values
| File:line | Value | Use token |

### Observations
(only if relevant: flag-variant differences, data-dependent parts not verifiable, elements that could not be located)
```

- Sort the table by severity (High → Medium), then by position on the page top to bottom.
- Use clickable markdown links for File:line, e.g. `[Card.tsx:42](path/to/Card.tsx#L42)`.
- Omit the "Designer notes" section if there are none. Omit "Hardcoded values" when `project.tokens`
  is absent.

## 8. --fix

Only when `--fix` is passed:

1. Fix **High and Medium** issues only. Don't touch unrelated code.
2. Use the project's tokens (`project.tokens`, theme palette and typography, spacing units) instead of
   literals. Follow the project's code style.
3. For an issue rooted in the theme file or in a shared component under `project.sharedRoots`, **ask
   before changing it**, because it affects other pages.
4. Re-verify:
   - Reload the page, then replay the state interactions (`entry.state` and any clicks you used the
     first time) and confirm the same state is showing — a reload can exit edit mode or clear a
     selection, and verifying against the wrong state reports correct fixes as missing.
   - Run the stabilisation script, and re-run the extraction script for only the fixed targets.
   - Take one screenshot.
5. Report:
   - A table: `# | Fix | File:line | Verified (✅/❌)`.
   - Any remaining issues.
   - A reminder that nothing was committed.
6. Run each command in `project.lint` with the changed file paths appended, and report the results.
   The values are commands that accept paths (e.g. `eslint`, `prettier --check`, `phpcs`), not
   whole-repo scripts; a whole-repo script would surface unrelated failures and break the
   changed-files contract. Skip the step when `project.lint` is absent.

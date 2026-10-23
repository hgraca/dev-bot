---
name: devbot:show-ui-in-browser
description: "Use when the user asks to see a page, screen, or UI change in a real browser. Triggers on 'show me the UI', 'open it in the browser', 'let me see it', 'boot the app and open that page'."
---

# Show the UI in a browser

Get the app running at a reachable URL and leave a **visible** browser window on the page the user
asked for. The deliverable is the user seeing the page — not a screenshot you inspected privately.

## When to Apply

- The user asks to look at a page, component, or UI change in a browser.
- You want the user to confirm something visual before continuing.

## Preconditions

- The devbot chrome-devtools MCP runs headful: the window it opens is what the user sees. That is the
  configuration — no launcher check or flag change is needed.
- The app must answer at a URL. Start the dev server/container and confirm with an HTTP request
  first; never open the browser on a URL that returns 5xx.
- The MCP browser profile is isolated per instance: it carries no session from earlier runs.

## Workflow

1. **Confirm the URL answers.** A 2xx/3xx (a login redirect counts) means the app is up; a 5xx or a
   connection error means fix the server before involving the browser.
2. **Open it** with `new_page` when no page is available, or `navigate_page` on the current one. Use
   the user's URL/route when given.
3. **Verify it rendered.** Take a snapshot; check console messages and failed requests. For
   client-rendered apps, wait for the mount instead of screenshotting immediately.
4. **Screenshot and read it yourself.** `take_screenshot` with a file path, then read the image.
   Measurements and DOM state do not tell you whether it looks right.
5. **Leave the window on the page the user asked for** — not on a login form or an intermediate
   screen.
6. **Report the URL** and what they should see.

## Logging in

- Prefer the app's own login form.
- Credentials: use only an account the project documents as its dev/test account, and only against a
  local or dev environment. **Never guess, search for, or try to discover credentials** — if none are
  documented, stop and ask the user.
- Log in on the same origin you are showing: session cookies are host-scoped.
- Do not drive third-party SSO. If the login redirects to an identity provider or a service that is
  not running, surface it instead of working around it.
- After login, load the target page and confirm it is authenticated before declaring it open.

## Driving a window you launched yourself

- Prefer the MCP tools (`navigate_page`, `click`, `fill`, `take_snapshot`).
- If the user must watch a specific window the MCP cannot attach to, launch a browser with a
  remote-debugging port and drive that same window over CDP — log in, navigate, measure, screenshot.
- Check the open pages first and prefer `new_page`; never hijack a window the user is actively using.

## Done criteria

- The target page returns 2xx, the expected element exists, and the console shows no errors.
- You read a screenshot of the final state.
- The window is on the target page and the user has the URL.
- A UI change still keeps its automated tests as proof; the browser confirms it visually, it does not
  replace them.

## Gotchas

- The page is only "shown" once the window is on it; a screenshot you inspected privately is not the
  hand-off.
- An isolated profile is logged out: expect a login step.
- A deep link into a client-side router can 404 on a hard refresh; navigate from the app root when the
  server has no history fallback.
- An unbuilt checkout can render error pages on layouts that load built assets; build first.
- Several dev stacks behind one proxy can route a hostname to a different checkout than the one you
  started; confirm the response came from your instance.
- Close windows opened purely for verification once the user has seen the page, and stop
  servers/containers you started — unless the user is still using them.

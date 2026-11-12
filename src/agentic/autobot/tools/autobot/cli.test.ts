import { describe, expect, test } from "bun:test";

import { resolveProjectFromSummary } from "./cli.ts";
import type { ManagedProject } from "./config.ts";

const projects: ManagedProject[] = [
  { name: "core", path: "/gete/core", devbotDir: ".agents" },
  { name: "dev-bot", path: "/gete/dev-bot", devbotDir: ".agents" },
];

describe("resolveProjectFromSummary", () => {
  test("reads the bracketed repo prefix", () => {
    expect(resolveProjectFromSummary("[dev-bot] add a thing", projects)?.name).toBe("dev-bot");
  });

  test("maps the transfers alias onto core", () => {
    expect(resolveProjectFromSummary("[transfers] bump dev-tools", projects)?.name).toBe("core");
  });

  test("ignores case", () => {
    expect(resolveProjectFromSummary("[Dev-Bot] x", projects)?.name).toBe("dev-bot");
  });

  test("is null without a prefix", () => {
    expect(resolveProjectFromSummary("no repo named here", projects)).toBeNull();
  });

  test("is null for a repo that is not a managed project", () => {
    expect(resolveProjectFromSummary("[unknown] x", projects)).toBeNull();
  });

  test("copes with leading whitespace", () => {
    expect(resolveProjectFromSummary("   [core] x", projects)?.name).toBe("core");
  });
});

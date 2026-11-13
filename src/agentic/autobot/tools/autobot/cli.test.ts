import { describe, expect, test } from "bun:test";

import { repoReference } from "./cli.ts";
import type { ManagedProject } from "./config.ts";

const projects: ManagedProject[] = [
  { name: "core", path: "/gete/core", devbotDir: ".agents" },
  { name: "dev-bot", path: "/gete/dev-bot", devbotDir: ".agents" },
];

describe("repoReference", () => {
  test("finds the bracketed repo prefix", () => {
    const reference = repoReference("[dev-bot] add a thing", projects);
    expect(reference.kind).toBe("found");
    expect(reference.kind === "found" && reference.project.name).toBe("dev-bot");
  });

  test("maps the transfers alias onto core", () => {
    const reference = repoReference("[transfers] bump dev-tools", projects);
    expect(reference.kind === "found" && reference.project.name).toBe("core");
  });

  test("ignores case", () => {
    const reference = repoReference("[Dev-Bot] x", projects);
    expect(reference.kind === "found" && reference.project.name).toBe("dev-bot");
  });

  test("reports no prefix as none", () => {
    expect(repoReference("no repo named here", projects)).toEqual({ kind: "none" });
  });

  test("reports an unknown prefix as unknown, not none", () => {
    expect(repoReference("[not-a-managed-repo] x", projects)).toEqual({
      kind: "unknown",
      name: "not-a-managed-repo",
    });
  });

  test("copes with leading whitespace", () => {
    const reference = repoReference("   [core] x", projects);
    expect(reference.kind === "found" && reference.project.name).toBe("core");
  });
});

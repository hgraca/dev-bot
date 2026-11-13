import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { repoReference, runSayCommand } from "./cli.ts";
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

describe("say", () => {
  const transport = (posted: Array<{ channel: string; text: string; threadTs?: string }>) => () => ({
    resolveUser: async () => "U123",
    openDm: async () => "D456",
    post: async (channel: string, text: string, threadTs?: string) => {
      posted.push({ channel, text, ...(threadTs === undefined ? {} : { threadTs }) });
      return "1700000000.000100";
    },
    history: async () => [],
  });

  test("posts into the ticket thread and opens it once", async () => {
    const home = mkdtempSync(join(tmpdir(), "autobot-say-"));
    const root = join(home, "repo");
    mkdirSync(join(root, ".agents"), { recursive: true });
    writeFileSync(
      join(root, ".devbot.global.jsonc"),
      JSON.stringify({ projects: [root] }),
      "utf8",
    );
    writeFileSync(
      join(root, ".devbot.project.jsonc"),
      JSON.stringify({
        autobot: {
          poll_slack: true,
          slack_user_email: "you@example.com",
          slack_bot_token: "xoxb-1",
          jira_assignees: [],
        },
      }),
      "utf8",
    );
    const posted: Array<{ channel: string; text: string; threadTs?: string }> = [];
    const env = { DEV_BOT_ROOT: root, XDG_STATE_HOME: join(home, "state") };
    const first = await runSayCommand(
      ["Working on", "it"],
      { ...env, DEV_BOT_AUTOBOT_TICKET: "ARC-1" },
      root,
      transport(posted) as never,
    );
    expect(first.ticket).toBe("ARC-1");
    expect(posted[0]).toEqual({ channel: "D456", text: "Working on it" });
    await runSayCommand(
      ["Done"],
      { ...env, DEV_BOT_AUTOBOT_TICKET: "ARC-1" },
      root,
      transport(posted) as never,
    );
    expect(posted[1]?.threadTs).toBe("1700000000.000100");
  });

  test("refuses a run with no ticket", async () => {
    await expect(runSayCommand(["hi"], { DEV_BOT_ROOT: "/nope" }, "/nope")).rejects.toThrow(
      "no ticket",
    );
  });
});

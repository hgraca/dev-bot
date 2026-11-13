import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { readEnvFile, repoReference, runSayCommand } from "./cli.ts";
import type { ManagedProject } from "./config.ts";

const projects: ManagedProject[] = [
    { name: "core", path: "/gete/core", devbotDir: ".agents" },
    { name: "dev-bot", path: "/gete/dev-bot", devbotDir: ".agents" },
];

describe("repoReference", () => {
    test("finds the bracketed repo prefix", () => {
        const reference = repoReference("[dev-bot] add a thing", projects);
        expect(reference.kind).toBe("found");
        expect(reference.kind === "found" && reference.project.name).toBe(
            "dev-bot",
        );
    });

    test("maps the transfers alias onto core", () => {
        const reference = repoReference("[transfers] bump dev-tools", projects);
        expect(reference.kind === "found" && reference.project.name).toBe(
            "core",
        );
    });

    test("ignores case", () => {
        const reference = repoReference("[Dev-Bot] x", projects);
        expect(reference.kind === "found" && reference.project.name).toBe(
            "dev-bot",
        );
    });

    test("reports no prefix as none", () => {
        expect(repoReference("no repo named here", projects)).toEqual({
            kind: "none",
        });
    });

    test("reports an unknown prefix as unknown, not none", () => {
        expect(repoReference("[not-a-managed-repo] x", projects)).toEqual({
            kind: "unknown",
            name: "not-a-managed-repo",
        });
    });

    test("copes with leading whitespace", () => {
        const reference = repoReference("   [core] x", projects);
        expect(reference.kind === "found" && reference.project.name).toBe(
            "core",
        );
    });
});

describe("say", () => {
    const transport =
        (posted: Array<{ channel: string; text: string; threadTs?: string }>) =>
        () => ({
            resolveUser: async () => "U123",
            openDm: async () => "D456",
            post: async (channel: string, text: string, threadTs?: string) => {
                posted.push({
                    channel,
                    text,
                    ...(threadTs === undefined ? {} : { threadTs }),
                });
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
        const posted: Array<{
            channel: string;
            text: string;
            threadTs?: string;
        }> = [];
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
        await expect(
            runSayCommand(["hi"], { DEV_BOT_ROOT: "/nope" }, "/nope"),
        ).rejects.toThrow("no ticket");
    });
});

describe("say resolves its own credentials", () => {
    test("reads an exported pair out of the env file", () => {
        const values = readEnvFile(
            '# comment\nexport SLACK_BOT_TOKEN=xoxb-1\nJIRA_API_TOKEN="jira"\nnot a pair\n',
        );
        expect(values.SLACK_BOT_TOKEN).toBe("xoxb-1");
        expect(values.JIRA_API_TOKEN).toBe("jira");
    });

    test("resolves ${SLACK_BOT_TOKEN} from the env file when the child env has none", async () => {
        const home = mkdtempSync(join(tmpdir(), "autobot-say-env-"));
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
                    slack_bot_token: "${SLACK_BOT_TOKEN}",
                    jira_assignees: [],
                },
            }),
            "utf8",
        );
        const envFile = join(home, "autobot.env");
        writeFileSync(
            envFile,
            "export SLACK_BOT_TOKEN=xoxb-from-file\n",
            "utf8",
        );
        const tokens: string[] = [];
        const transport = (token: string) => {
            tokens.push(token);
            return {
                resolveUser: async () => "U123",
                openDm: async () => "D456",
                post: async () => "1767261600.000100",
                history: async () => [],
                replies: async () => [],
            };
        };
        await runSayCommand(
            ["hello"],
            {
                DEV_BOT_ROOT: root,
                XDG_STATE_HOME: join(home, "state"),
                DEV_BOT_AUTOBOT_TICKET: "ARC-1",
                DEV_BOT_AUTOBOT_ENV: envFile,
            },
            root,
            transport as never,
        );
        expect(tokens).toEqual(["xoxb-from-file"]);
    });
});

describe("say flag contract", () => {
    const setup = () => {
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
        const posted: unknown[] = [];
        const transport = () => ({
            resolveUser: async () => "U123",
            openDm: async () => "D456",
            post: async (channel: string, text: string, threadTs?: string) => {
                posted.push({ channel, text, threadTs });
                return "1767261600.000100";
            },
            history: async () => [],
            replies: async () => [],
        });
        return {
            root,
            posted,
            transport,
            env: { DEV_BOT_ROOT: root, XDG_STATE_HOME: join(home, "state") },
        };
    };

    test("--ask without --phase is refused before posting", async () => {
        const { root, posted, transport, env } = setup();
        await expect(
            runSayCommand(
                ["--ask", "Ready?"],
                { ...env, DEV_BOT_AUTOBOT_TICKET: "ARC-1" },
                root,
                transport as never,
            ),
        ).rejects.toThrow("--ask needs --phase");
        expect(posted).toHaveLength(0);
    });

    test("--phase without --ask is refused", async () => {
        const { root, transport, env } = setup();
        await expect(
            runSayCommand(
                ["--phase", "refining", "hello"],
                { ...env, DEV_BOT_AUTOBOT_TICKET: "ARC-1" },
                root,
                transport as never,
            ),
        ).rejects.toThrow("--phase only makes sense with --ask");
    });

    test("an unknown phase never reaches Slack", async () => {
        const { root, posted, transport, env } = setup();
        await expect(
            runSayCommand(
                ["--ask", "--phase", "awating_plan", "Ready?"],
                { ...env, DEV_BOT_AUTOBOT_TICKET: "ARC-1" },
                root,
                transport as never,
            ),
        ).rejects.toThrow("--phase must be one of");
        expect(posted).toHaveLength(0);
    });

    test("--ask with a phase posts and parks", async () => {
        const { root, posted, transport, env } = setup();
        const result = await runSayCommand(
            ["--ask", "--phase", "awaiting_restate", "Shall I?"],
            { ...env, DEV_BOT_AUTOBOT_TICKET: "ARC-1" },
            root,
            transport as never,
        );
        expect(posted).toHaveLength(1);
        expect(result.ticket).toBe("ARC-1");
    });
});

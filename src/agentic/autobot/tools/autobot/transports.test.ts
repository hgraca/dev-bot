import { describe, expect, test } from "bun:test";

import {
    childEnv,
    extractSessionId,
    parsePullRequests,
    parseReviews,
    parseSessionList,
} from "./transports.ts";

describe("extractSessionId", () => {
    test("finds a nested session id", () => {
        const output = [
            '{"type":"session.created","properties":{"sessionID":"ses_abc123"}}',
            '{"type":"message","properties":{"text":"hello"}}',
        ].join("\n");
        expect(extractSessionId(output)).toBe("ses_abc123");
    });

    test("finds an id held under a session key", () => {
        expect(extractSessionId('{"sessionId":"abc-123"}')).toBe("abc-123");
    });

    test("prefers an ses_ value when both appear", () => {
        const output =
            '{"session":"other","properties":{"sessionID":"ses_real"}}';
        expect(extractSessionId(output)).toBe("ses_real");
    });

    test("is null when the stream carries no id", () => {
        expect(
            extractSessionId('{"type":"message","properties":{"text":"hi"}}'),
        ).toBeNull();
    });

    test("ignores malformed and non-JSON lines", () => {
        expect(
            extractSessionId('not json\n{broken\n{"sessionID":"ses_ok"}'),
        ).toBe("ses_ok");
    });

    test("is null for empty output", () => {
        expect(extractSessionId("")).toBeNull();
    });
});

describe("parsePullRequests", () => {
    test("parses a list", () => {
        const payload = JSON.stringify([
            {
                number: 7,
                url: "https://github.com/GET-E/core/pull/7",
                state: "OPEN",
            },
        ]);
        expect(parsePullRequests(payload)).toEqual([
            {
                number: 7,
                url: "https://github.com/GET-E/core/pull/7",
                state: "OPEN",
            },
        ]);
    });

    test("defaults an unknown state to OPEN", () => {
        const payload = JSON.stringify([{ number: 7, url: "u" }]);
        expect(parsePullRequests(payload)[0]?.state).toBe("OPEN");
    });

    test("skips entries without a number or url", () => {
        const payload = JSON.stringify([
            { number: 1 },
            { url: "u" },
            { number: 2, url: "u2" },
        ]);
        expect(parsePullRequests(payload)).toHaveLength(1);
    });

    test("returns nothing for a non-array payload", () => {
        expect(parsePullRequests("{}")).toEqual([]);
    });
});

describe("parseReviews", () => {
    test("parses reviews", () => {
        const payload = JSON.stringify({
            reviews: [
                {
                    id: "1",
                    author: { login: "human" },
                    body: "fix it",
                    submittedAt: "2026-11-11T10:00:00Z",
                },
            ],
        });
        expect(parseReviews(payload)).toEqual([
            {
                id: "1",
                authorLogin: "human",
                body: "fix it",
                submittedAt: "2026-11-11T10:00:00Z",
            },
        ]);
    });

    test("drops a review with no usable timestamp", () => {
        const payload = JSON.stringify({ reviews: [{ id: 2 }] });
        expect(parseReviews(payload)).toEqual([]);
    });

    test("returns nothing for malformed payloads", () => {
        expect(parseReviews("{broken")).toEqual([]);
        expect(parseReviews("{}")).toEqual([]);
    });
});

describe("parseSessionList", () => {
    test("converts epoch milliseconds to an ISO timestamp", () => {
        const payload = JSON.stringify([
            {
                id: "ses_a",
                title: "t",
                updated: 1792440910150,
                directory: "/x",
            },
        ]);
        expect(parseSessionList(payload)).toEqual([
            { id: "ses_a", updatedAt: new Date(1792440910150).toISOString() },
        ]);
    });

    test("drops entries without an id or a usable timestamp", () => {
        const payload = JSON.stringify([
            { title: "no id", updated: 1 },
            { id: "ses_b" },
            { id: "ses_c", updated: "not a number" },
            { id: "ses_d", updated: 1 },
        ]);
        expect(parseSessionList(payload).map((session) => session.id)).toEqual([
            "ses_d",
        ]);
    });

    test("returns nothing for a malformed payload", () => {
        expect(parseSessionList("{broken")).toEqual([]);
        expect(parseSessionList("{}")).toEqual([]);
    });
});

describe("childEnv", () => {
    test("strips the credentials AutoBot keeps to itself", () => {
        const env = childEnv({
            PATH: "/usr/bin",
            HOME: "/home/me",
            SLACK_BOT_TOKEN: "xoxb-secret",
            JIRA_API_TOKEN: "jira-secret",
            GH_TOKEN: "gh-secret",
            GITHUB_TOKEN: "gh-secret-2",
        });
        expect(env.PATH).toBe("/usr/bin");
        expect(env.HOME).toBe("/home/me");
        expect(env.SLACK_BOT_TOKEN).toBeUndefined();
        expect(env.JIRA_API_TOKEN).toBeUndefined();
        expect(env.GH_TOKEN).toBeUndefined();
    });

    test("keeps the variables the run needs", () => {
        const env = childEnv(
            { ANTHROPIC_API_KEY: "key", PATH: "/bin" },
            { DEV_BOT_AUTOBOT_TICKET: "ARC-1" },
        );
        expect(env.ANTHROPIC_API_KEY).toBe("key");
        expect(env.DEV_BOT_AUTOBOT_TICKET).toBe("ARC-1");
    });
});

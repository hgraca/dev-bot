import { describe, expect, test } from "bun:test";

import {
    collectOptedInProjects,
    effectiveAssignees,
    jiraConnections,
    defaultAutobotConfig,
    isAutobotActive,
    parseAutobotConfig,
    parseAutobotProfiles,
    parseJsonc,
    parseManagedProjects,
    slackConnections,
    stripJsonc,
} from "./config.ts";

// Polling requires a connection, so every fixture that enables a poll carries one.
const CONN = {
    jira_base_url: "https://getinfo.atlassian.net",
    jira_email: "you@example.com",
    jira_api_token: "t",
    jira_assignees: [] as string[],
};

describe("stripJsonc", () => {
    test("leaves plain JSON untouched", () => {
        const json = '{"a":1,"b":[1,2]}';
        expect(stripJsonc(json)).toBe(json);
    });

    test("removes line comments", () => {
        expect(stripJsonc('{\n  // note\n  "a": 1\n}')).toBe(
            '{\n  \n  "a": 1\n}',
        );
    });

    test("removes block comments", () => {
        expect(stripJsonc('{ /* note */ "a": 1 }')).toBe('{  "a": 1 }');
    });

    test("removes a trailing comma before }", () => {
        expect(parseJsonc('{"a": 1,}')).toEqual({ a: 1 });
    });

    test("removes a trailing comma before ]", () => {
        expect(parseJsonc("[1, 2, ]")).toEqual([1, 2]);
    });

    test("removes a trailing comma followed by a comment then }", () => {
        expect(parseJsonc('{"a": 1, // last\n}')).toEqual({ a: 1 });
    });

    test("keeps a comma inside a string", () => {
        expect(parseJsonc('{"a": "x,}"}')).toEqual({ a: "x,}" });
    });

    test("keeps a comment marker inside a string", () => {
        expect(parseJsonc('{"a": "https://example.com"}')).toEqual({
            a: "https://example.com",
        });
    });

    test("keeps an escaped quote inside a string", () => {
        expect(parseJsonc('{"a": "say \\"hi\\""}')).toEqual({ a: 'say "hi"' });
    });

    test("drops an unterminated block comment instead of hanging", () => {
        expect(parseJsonc('{"a": 1} /* trailing')).toEqual({ a: 1 });
    });
});

describe("defaultAutobotConfig", () => {
    test("is off in every respect", () => {
        expect(defaultAutobotConfig()).toEqual({
            pollJira: false,
            pollGithub: false,
            pollSlack: false,
            prompts: [],
            jiraAssignees: [],
        });
    });

    test("returns a fresh prompts array each call", () => {
        const first = defaultAutobotConfig();
        first.prompts.push({ schedule: "* * * * *", prompt: "x" });
        expect(defaultAutobotConfig().prompts).toHaveLength(0);
    });
});

describe("parseAutobotConfig", () => {
    test("returns null when the block is absent", () => {
        expect(parseAutobotConfig({ harness: "opencode" }, "p")).toBeNull();
    });

    test("returns null when the block is explicitly null", () => {
        expect(parseAutobotConfig({ autobot: null }, "p")).toBeNull();
    });

    test("rejects a block that omits the assignee list", () => {
        expect(() => parseAutobotConfig({ autobot: {} }, "p")).toThrow(
            /"autobot.jira_assignees" is required/,
        );
    });

    test("defaults the rest when only the assignee list is given", () => {
        expect(
            parseAutobotConfig({ autobot: { jira_assignees: [] } }, "p"),
        ).toEqual(defaultAutobotConfig());
    });

    test("reads the poll flags", () => {
        const config = parseAutobotConfig(
            {
                autobot: {
                    poll_jira: true,
                    poll_github: true,
                    ...CONN,
                    jira_assignees: [],
                },
            },
            "p",
        );
        expect(config).toMatchObject({
            pollJira: true,
            pollGithub: true,
            prompts: [],
            jiraAssignees: [],
        });
    });

    test("leaves an absent flag off", () => {
        expect(
            parseAutobotConfig(
                { autobot: { poll_jira: true, ...CONN, jira_assignees: [] } },
                "p",
            ),
        ).toMatchObject({
            pollJira: true,
            pollGithub: false,
            pollSlack: false,
            prompts: [],
            jiraAssignees: [],
        });
    });

    test("parses prompted entries", () => {
        const config = parseAutobotConfig(
            {
                autobot: {
                    prompts: [
                        {
                            schedule: "*/5 * * * *",
                            prompt: "/devbot:autobot-scan",
                        },
                    ],
                    jira_assignees: [],
                },
            },
            "p",
        );
        expect(config?.prompts).toEqual([
            { schedule: "*/5 * * * *", prompt: "/devbot:autobot-scan" },
        ]);
    });

    test("accepts a schedule with ranges and lists", () => {
        const config = parseAutobotConfig(
            {
                autobot: {
                    prompts: [
                        { schedule: "0,15,30 9-17 * * 1-5", prompt: "x" },
                    ],
                    jira_assignees: [],
                },
            },
            "p",
        );
        expect(config?.prompts[0]?.schedule).toBe("0,15,30 9-17 * * 1-5");
    });

    test("reads the Jira connection, including environment references", () => {
        const config = parseAutobotConfig(
            {
                autobot: {
                    jira_base_url: "https://getinfo.atlassian.net",
                    jira_email: "you@example.com",
                    jira_api_token: "${JIRA_API_TOKEN}",
                    jira_assignees: [],
                },
            },
            "p",
        );
        expect(config?.jiraBaseUrl).toBe("https://getinfo.atlassian.net");
        expect(config?.jiraApiToken).toBe("${JIRA_API_TOKEN}");
    });

    test("rejects a partially configured connection", () => {
        expect(() =>
            parseAutobotConfig(
                {
                    autobot: {
                        jira_email: "you@example.com",
                        jira_assignees: [],
                    },
                },
                "p",
            ),
        ).toThrow(
            /sets 1 of jira_base_url, jira_email and jira_api_token — all three or none/,
        );
    });

    test("rejects an empty connection value", () => {
        expect(() =>
            parseAutobotConfig(
                { autobot: { jira_email: " ", jira_assignees: [] } },
                "p",
            ),
        ).toThrow(/"autobot.jira_email" must be a non-empty string/);
    });

    test("rejects a non-boolean poll flag", () => {
        expect(() =>
            parseAutobotConfig(
                { autobot: { poll_jira: "yes", jira_assignees: [] } },
                "p",
            ),
        ).toThrow(/"autobot.poll_jira" must be a boolean/);
    });

    test("rejects a non-array prompts value", () => {
        expect(() =>
            parseAutobotConfig({ autobot: { prompts: {} } }, "p"),
        ).toThrow(/"autobot.prompts" must be an array/);
    });

    test("rejects a prompt entry that is not an object", () => {
        expect(() =>
            parseAutobotConfig(
                { autobot: { prompts: ["nope"], jira_assignees: [] } },
                "p",
            ),
        ).toThrow(/prompts\[0\] must be an object/);
    });

    test("rejects a missing prompt and names the index", () => {
        expect(() =>
            parseAutobotConfig(
                { autobot: { prompts: [{ schedule: "* * * * *" }] } },
                "p",
            ),
        ).toThrow(/prompts\[0\]: "prompt" must be a non-empty string/);
    });

    test("rejects a blank prompt", () => {
        expect(() =>
            parseAutobotConfig(
                {
                    autobot: {
                        prompts: [{ schedule: "* * * * *", prompt: "  " }],
                    },
                },
                "p",
            ),
        ).toThrow(/"prompt" must be a non-empty string/);
    });

    test("rejects a schedule with the wrong number of fields", () => {
        expect(() =>
            parseAutobotConfig(
                { autobot: { prompts: [{ schedule: "* * *", prompt: "x" }] } },
                "p",
            ),
        ).toThrow(/must have 5 fields, got 3/);
    });

    test("rejects a schedule with unsupported characters", () => {
        expect(() =>
            parseAutobotConfig(
                {
                    autobot: {
                        prompts: [{ schedule: "@hourly * * * *", prompt: "x" }],
                    },
                },
                "p",
            ),
        ).toThrow(/unsupported characters/);
    });

    test("rejects an autobot block that is neither a name nor an object", () => {
        expect(() => parseAutobotConfig({ autobot: [] }, "p")).toThrow(
            /must be a profile name or an object/,
        );
    });

    test("resolves a profile reference", () => {
        const profiles = { "gete-jira": { poll_jira: true, ...CONN } };
        const config = parseAutobotConfig(
            { autobot: "gete-jira" },
            "p",
            profiles,
        );
        expect(config?.pollJira).toBe(true);
        expect(config?.jiraBaseUrl).toBe(CONN.jira_base_url);
    });

    test("rejects an unknown profile", () => {
        expect(() => parseAutobotConfig({ autobot: "nope" }, "p", {})).toThrow(
            /names unknown profile "nope"/,
        );
    });

    test("does not resolve an inherited property as a profile", () => {
        expect(() =>
            parseAutobotConfig({ autobot: "__proto__" }, "p", {}),
        ).toThrow(/names unknown profile "__proto__"/);
    });

    test("rejects a profile whose value is null", () => {
        expect(() =>
            parseAutobotConfig({ autobot: "broken" }, "p", { broken: null }),
        ).toThrow(/autobot profile "broken" must be an object/);
    });

    test("rejects an empty profile name", () => {
        expect(() => parseAutobotConfig({ autobot: "  " }, "p", {})).toThrow(
            /names an empty profile/,
        );
    });

    test("prefers the inline block over any profile", () => {
        const profiles = { "gete-jira": { poll_jira: true, ...CONN } };
        const config = parseAutobotConfig(
            {
                autobot: {
                    poll_jira: false,
                    prompts: [],
                    jira_assignees: [],
                    jiraAssignees: [],
                },
            },
            "p",
            profiles,
        );
        expect(config?.pollJira).toBe(false);
    });

    test("rejects a project config that is not an object", () => {
        expect(() => parseAutobotConfig([], "p")).toThrow(
            /project config must be a JSON object/,
        );
    });
});

describe("isAutobotActive", () => {
    test("an all-defaults block is inert", () => {
        expect(isAutobotActive(defaultAutobotConfig())).toBe(false);
    });

    test("either poll flag activates it", () => {
        expect(
            isAutobotActive({
                pollJira: true,
                pollGithub: false,
                pollSlack: false,
                prompts: [],
                jiraAssignees: [],
            }),
        ).toBe(true);
        expect(
            isAutobotActive({
                pollJira: false,
                pollGithub: true,
                pollSlack: false,
                prompts: [],
                jiraAssignees: [],
            }),
        ).toBe(true);
    });

    test("a prompt activates it", () => {
        expect(
            isAutobotActive({
                pollJira: false,
                pollGithub: false,
                prompts: [{ schedule: "* * * * *", prompt: "x" }],
                jiraAssignees: [],
            }),
        ).toBe(true);
    });
});

describe("parseManagedProjects", () => {
    test("returns an empty list when projects is absent", () => {
        expect(parseManagedProjects({})).toEqual([]);
    });

    test("maps paths to name, path and runtime directory", () => {
        expect(
            parseManagedProjects({ projects: ["/gete/core", "/gete/dev-bot"] }),
        ).toEqual([
            { name: "core", path: "/gete/core", devbotDir: ".agents" },
            { name: "dev-bot", path: "/gete/dev-bot", devbotDir: ".agents" },
        ]);
    });

    test("uses the global devbot_dir as the default", () => {
        expect(
            parseManagedProjects({
                devbot_dir: ".devbot",
                projects: ["/gete/core"],
            }),
        ).toEqual([{ name: "core", path: "/gete/core", devbotDir: ".devbot" }]);
    });

    test("drops a trailing slash", () => {
        expect(parseManagedProjects({ projects: ["/gete/core/"] })).toEqual([
            { name: "core", path: "/gete/core", devbotDir: ".agents" },
        ]);
    });

    test("rejects a devbot_dir that escapes the project", () => {
        expect(() =>
            parseManagedProjects({
                devbot_dir: "../etc",
                projects: ["/gete/core"],
            }),
        ).toThrow(/relative path without/);
        expect(() =>
            parseManagedProjects({
                devbot_dir: "/etc",
                projects: ["/gete/core"],
            }),
        ).toThrow(/relative path without/);
    });

    test("accepts a nested devbot_dir", () => {
        expect(
            parseManagedProjects({
                devbot_dir: ".state/autobot",
                projects: ["/gete/core"],
            }),
        ).toEqual([
            { name: "core", path: "/gete/core", devbotDir: ".state/autobot" },
        ]);
    });

    test("rejects a non-array projects value", () => {
        expect(() => parseManagedProjects({ projects: "/gete/core" })).toThrow(
            /"projects" must be an array/,
        );
    });

    test("rejects a non-string project entry", () => {
        expect(() => parseManagedProjects({ projects: [42] })).toThrow(
            /projects\[0\] must be a non-empty path/,
        );
    });
});

describe("effectiveAssignees", () => {
    const project = (
        name: string,
        over: Partial<AutobotConfig> = {},
    ): AutobotProject => ({
        name,
        path: `/gete/${name}`,
        devbotDir: ".agents",
        config: {
            pollJira: true,
            pollGithub: false,
            prompts: [],
            jiraAssignees: [],
            ...over,
        },
    });

    test("is empty when a project deliberately names nobody", () => {
        expect(
            effectiveAssignees([project("a", { jiraAssignees: [] })]),
        ).toEqual([]);
    });

    test("keeps an empty list even beside a project with no opinion", () => {
        expect(
            effectiveAssignees([
                project("a", { jiraAssignees: [] }),
                project("b"),
            ]),
        ).toEqual([]);
    });

    test("unions the lists that are declared", () => {
        expect(
            effectiveAssignees([
                project("a", { jiraAssignees: ["one@example.com"] }),
                project("b", {
                    jiraAssignees: ["two@example.com", "one@example.com"],
                }),
                project("c"),
            ]),
        ).toEqual(["one@example.com", "two@example.com"]);
    });
});

describe("jiraConnections", () => {
    const project = (
        name: string,
        over: Partial<AutobotConfig> = {},
    ): AutobotProject => ({
        name,
        path: `/gete/${name}`,
        devbotDir: ".agents",
        config: {
            pollJira: true,
            pollGithub: false,
            pollSlack: false,
            prompts: [],
            jiraAssignees: [],
            ...over,
        },
    });

    const connection = {
        jiraBaseUrl: "https://getinfo.atlassian.net",
        jiraEmail: "you@example.com",
        jiraApiToken: "${JIRA_API_TOKEN}",
    };

    test("is empty when no project configures one", () => {
        expect(jiraConnections([project("a")])).toEqual([]);
    });

    test("returns one group for one configured project", () => {
        const groups = jiraConnections([project("a", connection)]);
        expect(groups).toHaveLength(1);
        expect(groups[0]?.connection.baseUrl).toBe(
            "https://getinfo.atlassian.net",
        );
        expect(groups[0]?.projects.map((entry) => entry.name)).toEqual(["a"]);
    });

    test("groups projects that share a connection", () => {
        const groups = jiraConnections([
            project("a", connection),
            project("b", connection),
        ]);
        expect(groups).toHaveLength(1);
        expect(groups[0]?.projects).toHaveLength(2);
    });

    test("groups by resolved values, so two spellings of one variable agree", () => {
        const resolve = (value: string) =>
            value.replace(/^\$\{([A-Z_]+)\}$/, "secret");
        const groups = jiraConnections(
            [
                project("a", {
                    ...connection,
                    jiraApiToken: "${JIRA_API_TOKEN}",
                }),
                project("b", { ...connection, jiraApiToken: "secret" }),
            ],
            resolve,
        );
        expect(groups).toHaveLength(1);
    });

    test("ignores a project that only runs prompts", () => {
        const promptOnly = project("a", {
            ...connection,
            pollJira: false,
            pollGithub: false,
        });
        expect(jiraConnections([promptOnly])).toEqual([]);
    });

    test("includes a prompt-only project when the caller needs full coverage", () => {
        const promptOnly = project("a", {
            ...connection,
            pollJira: false,
            pollGithub: false,
        });
        expect(
            jiraConnections([promptOnly], (value) => value, "all"),
        ).toHaveLength(1);
    });

    test("keeps different connections apart", () => {
        const groups = jiraConnections([
            project("a", connection),
            project("b", { ...connection, jiraEmail: "other@example.com" }),
        ]);
        expect(groups).toHaveLength(2);
    });
});

describe("parseAutobotProfiles", () => {
    test("is empty when the global config declares none", () => {
        expect(parseAutobotProfiles({})).toEqual({});
    });

    test("rejects a profiles map that is not an object", () => {
        expect(() => parseAutobotProfiles({ autobot: [] })).toThrow(
            /must be an object of named profiles/,
        );
    });
});

describe("collectOptedInProjects", () => {
    const global = {
        projects: ["/gete/core", "/gete/dev-bot", "/gete/portal"],
    };

    const configs: Record<string, unknown> = {
        "/gete/core": { harness: "opencode" },
        "/gete/dev-bot": {
            autobot: { poll_jira: true, ...CONN, jira_assignees: [] },
        },
        "/gete/portal": {
            autobot: {
                poll_jira: false,
                poll_github: false,
                prompts: [],
                jira_assignees: [],
                jiraAssignees: [],
            },
        },
    };

    test("keeps only active projects", () => {
        const result = collectOptedInProjects(
            global,
            (path) => configs[path] ?? null,
        );
        expect(result).toHaveLength(1);
        expect(result[0]?.name).toBe("dev-bot");
        expect(result[0]?.devbotDir).toBe(".agents");
        expect(result[0]?.config).toMatchObject({
            pollJira: true,
            pollGithub: false,
            pollSlack: false,
            prompts: [],
            jiraAssignees: [],
        });
    });

    test("a project devbot_dir overrides the global one", () => {
        const result = collectOptedInProjects(
            { devbot_dir: ".agents", projects: ["/gete/dev-bot"] },
            () => ({
                devbot_dir: ".runtime",
                autobot: { poll_jira: true, ...CONN },
            }),
        );
        expect(result[0]?.devbotDir).toBe(".runtime");
    });

    test("rejects two active projects with the same basename", () => {
        expect(() =>
            collectOptedInProjects(
                { projects: ["/one/api", "/two/api"] },
                () => ({
                    autobot: { poll_jira: true, ...CONN, jira_assignees: [] },
                }),
            ),
        ).toThrow(/duplicate project name "api"/);
    });

    test("resolves a profile declared in the global config", () => {
        const result = collectOptedInProjects(
            {
                projects: ["/gete/dev-bot"],
                autobot: { "gete-jira": { poll_jira: true, ...CONN } },
            },
            () => ({ autobot: "gete-jira" }),
        );
        expect(result).toHaveLength(1);
        expect(result[0]?.config.pollJira).toBe(true);
    });

    test("reports an unknown profile instead of failing the whole list", () => {
        const errors: string[] = [];
        const result = collectOptedInProjects(
            { projects: ["/gete/dev-bot"], autobot: {} },
            () => ({ autobot: "missing" }),
            "global config",
            (message) => errors.push(message),
        );
        expect(result).toEqual([]);
        expect(errors[0]).toContain('names unknown profile "missing"');
    });

    test("skips a project with no config file", () => {
        expect(collectOptedInProjects(global, () => null)).toEqual([]);
    });

    test("skips a project carrying only defaults", () => {
        const result = collectOptedInProjects(global, (path) =>
            path === "/gete/portal" ? { autobot: {} } : null,
        );
        expect(result).toEqual([]);
    });

    test("reports a bad project instead of failing the whole list", () => {
        const errors: string[] = [];
        const result = collectOptedInProjects(
            global,
            (path) =>
                path === "/gete/dev-bot"
                    ? {
                          autobot: {
                              prompts: [{ schedule: "bad", prompt: "x" }],
                          },
                      }
                    : null,
            "global config",
            (message) => errors.push(message),
        );
        expect(result).toEqual([]);
        expect(errors[0]).toContain(
            "dev-bot/.devbot.project.jsonc: autobot.prompts[0]",
        );
    });
});

describe("slack", () => {
    const PAIR = {
        slack_user_email: "you@example.com",
        slack_bot_token: "${SLACK_BOT_TOKEN}",
    };

    test("reads the pair and the flag", () => {
        const config = parseAutobotConfig(
            { autobot: { poll_slack: true, ...PAIR, jira_assignees: [] } },
            "p",
        );
        expect(config).toMatchObject({
            pollSlack: true,
            slackUserEmail: "you@example.com",
            slackBotToken: "${SLACK_BOT_TOKEN}",
        });
    });

    test("rejects half a pair", () => {
        expect(() =>
            parseAutobotConfig(
        { autobot: { slack_user_email: "you@example.com", jira_assignees: [] } },
        "p",
      ),
        ).toThrow("sets 1 of slack_user_email and slack_bot_token");
    });

    test("rejects polling without the pair", () => {
        expect(() =>
            parseAutobotConfig(
                { autobot: { poll_slack: true, jira_assignees: [] } },
                "p",
            ),
        ).toThrow("polling slack needs slack_user_email and slack_bot_token");
    });

    test("counts as active on its own", () => {
        expect(
            isAutobotActive({
                pollJira: false,
                pollGithub: false,
                pollSlack: true,
                prompts: [],
                jiraAssignees: [],
            }),
        ).toBe(true);
    });

    test("groups projects once per bot and person", () => {
        const project = (name: string): AutobotProject => ({
            name,
            path: `/gete/${name}`,
            devbotDir: ".agents",
            config: {
                pollJira: false,
                pollGithub: false,
                pollSlack: true,
                prompts: [],
                jiraAssignees: [],
                slackUserEmail: "you@example.com",
                slackBotToken: "${SLACK_BOT_TOKEN}",
            },
        });
        const groups = slackConnections(
            [project("a"), project("b")],
            (value) => (value === "${SLACK_BOT_TOKEN}" ? "xoxb-1" : value),
        );
        expect(groups).toHaveLength(1);
        expect(groups[0]?.connection).toEqual({
            email: "you@example.com",
            token: "xoxb-1",
        });
        expect(groups[0]?.projects.map((entry) => entry.name)).toEqual([
            "a",
            "b",
        ]);
    });

    test("keeps two people apart", () => {
        const project = (name: string, email: string): AutobotProject => ({
            name,
            path: `/gete/${name}`,
            devbotDir: ".agents",
            config: {
                pollJira: false,
                pollGithub: false,
                pollSlack: true,
                prompts: [],
                jiraAssignees: [],
                slackUserEmail: email,
                slackBotToken: "xoxb-1",
            },
        });
        const groups = slackConnections([project("a", "one@example.com"), project("b", "two@example.com")]);
        expect(groups.map((group) => group.connection.email)).toEqual([
            "one@example.com",
            "two@example.com",
        ]);
    });
});

import { describe, expect, test } from "bun:test";

import type { AutobotProject } from "./config.ts";
import type { ExecutionOutcome } from "./executor.ts";
import type { FollowupAction } from "./followups.ts";
import type { JiraPollItem } from "./jira.ts";
import type { MutexHandle } from "./mutex.ts";
import { mergeConfigs, runTick, type TickDeps } from "./tick.ts";

const project = (
    name: string,
    over: Partial<AutobotProject["config"]> = {},
): AutobotProject => ({
    name,
    path: `/gete/${name}`,
    devbotDir: ".agents",
    config: {
        pollJira: false,
        pollGithub: false,
        pollSlack: false,
        prompts: [],
        ...over,
        jiraAssignees: [],
    },
});

const ticket = (key: string): JiraPollItem => ({
    key,
    summary: "",
    status: "",
    assigneeId: "bot",
    reporterId: "reporter",
    state: null,
    newestHumanComment: null,
});

function fakeDeps(overrides: Partial<TickDeps> = {}) {
    const calls: string[] = [];
    let released = false;
    const lock: MutexHandle = {
        path: "/tmp/tick.lock",
        release() {
            released = true;
            calls.push("release");
        },
    };
    const deps: TickDeps = {
        instance: "me",
        projects: [],
        now: new Date(2026, 10, 11, 18, 30, 0, 0),
        runningDevbot: () => true,
        tryLock: () => lock,
        handleSlack: async () => ({ answered: [], reminded: [] }),
        pollJira: async () => {
            calls.push("pollJira");
            return [];
        },
        pollGithub: async (tickets) => {
            calls.push(`pollGithub:${tickets.length}`);
            return [];
        },
        execute: async (action: FollowupAction): Promise<ExecutionOutcome> => {
            calls.push(`execute:${action.kind}`);
            return { kind: action.kind, performed: true };
        },
        runPrompt: async (target, prompt) => {
            calls.push(`prompt:${target.name}:${prompt.prompt}`);
            return { kind: "prompt", performed: true };
        },
        log: () => {},
        ...overrides,
    };
    return { deps, calls, wasReleased: () => released };
}

describe("mergeConfigs", () => {
    test("ORs the poll switches and concatenates the prompts", () => {
        const merged = mergeConfigs([
            project("a", {
                pollJira: true,
                prompts: [{ schedule: "* * * * *", prompt: "x" }],
            }),
            project("b", { pollGithub: true }),
        ]);
        expect(merged.pollJira).toBe(true);
        expect(merged.pollGithub).toBe(true);
        expect(merged).not.toHaveProperty("prompts");
    });

    test("is all-off when every project is off", () => {
        expect(mergeConfigs([project("a")])).toEqual({
            pollJira: false,
            pollGithub: false,
        });
    });
});

describe("runTick", () => {
    test("answers slack before it polls", async () => {
        const calls: string[] = [];
        const { deps } = (() => {
            const built = fakeDeps();
            return built;
        })();
        const result = await runTick({
            ...deps,
            handleSlack: async () => {
                calls.push("slack");
                return { answered: ["ARC-1"], reminded: [] };
            },
            pollJira: async () => {
                calls.push("pollJira");
                return [];
            },
            projects: [project("a", { pollJira: true })],
        });
        expect(calls).toEqual(["slack", "pollJira"]);
        expect(result.slack.answered).toEqual(["ARC-1"]);
    });

    test("skips when another tick holds the lock", async () => {
        const { deps, calls } = fakeDeps({
            tryLock: () => null,
            projects: [project("a")],
        });
        const report = await runTick(deps);
        expect(report.skipped).toBe("locked");
        expect(calls).toEqual([]);
    });

    test("skips when no project has a running devbot", async () => {
        const { deps } = fakeDeps({
            projects: [project("a")],
            runningDevbot: () => false,
        });
        const report = await runTick(deps);
        expect(report.skipped).toBe("no running devbot");
    });

    test("does no polling when every switch is off", async () => {
        const { deps, calls } = fakeDeps({ projects: [project("a")] });
        await runTick(deps);
        expect(calls).toEqual(["release"]);
    });

    test("polls Jira and executes the decision", async () => {
        const { deps, calls } = fakeDeps({
            projects: [project("a", { pollJira: true })],
            pollJira: async () => {
                calls.push("pollJira");
                return [ticket("ARC-1")];
            },
        });
        const report = await runTick(deps);
        expect(calls).toEqual(["pollJira", "execute:start", "release"]);
        expect(report.actions[0]?.kind).toBe("start");
    });

    test("polls GitHub only when a project asked for it", async () => {
        const { deps, calls } = fakeDeps({
            projects: [project("a", { pollJira: true })],
        });
        await runTick(deps);
        expect(calls).not.toContain("pollGithub:0");
    });

    test("polls GitHub with the Jira tickets when enabled", async () => {
        const { deps, calls } = fakeDeps({
            projects: [project("a", { pollGithub: true })],
            pollJira: async () => [ticket("ARC-1"), ticket("ARC-2")],
        });
        await runTick(deps);
        expect(calls).toContain("pollGithub:2");
    });

    test("runs follow-ups before scheduled prompts", async () => {
        const { deps, calls } = fakeDeps({
            projects: [
                project("a", {
                    pollJira: true,
                    prompts: [
                        {
                            schedule: "30 18 * * *",
                            prompt: "/devbot:autobot-cleanup",
                        },
                    ],
                }),
            ],
            pollJira: async () => [ticket("ARC-1")],
        });
        await runTick(deps);
        expect(calls).toEqual([
            "execute:start",
            "prompt:a:/devbot:autobot-cleanup",
            "release",
        ]);
    });

    test("skips a prompt that is not due", async () => {
        const { deps, calls } = fakeDeps({
            projects: [
                project("a", {
                    prompts: [{ schedule: "0 3 * * *", prompt: "nightly" }],
                }),
            ],
        });
        await runTick(deps);
        expect(calls).toEqual(["release"]);
    });

    test("ignores prompts on a project without a running devbot", async () => {
        const { deps, calls } = fakeDeps({
            projects: [
                project("a", {
                    prompts: [{ schedule: "* * * * *", prompt: "tick" }],
                }),
            ],
            runningDevbot: () => false,
        });
        await runTick(deps);
        expect(calls).toEqual(["release"]);
    });

    test("releases the lock even when an action throws", async () => {
        const { deps, wasReleased } = fakeDeps({
            projects: [project("a", { pollJira: true })],
            pollJira: async () => [ticket("ARC-1")],
            execute: async () => {
                throw new Error("boom");
            },
        });
        await expect(runTick(deps)).rejects.toThrow("boom");
        expect(wasReleased()).toBe(true);
    });
});

/**
 * One tick: decide, act, then run whatever each project scheduled.
 *
 * The order is deliberate. Follow-ups run first because a human is blocked on them; scheduled prompts
 * are new work and can wait a minute. A ticket's follow-up is decided against the union of the running
 * projects' switches, because tickets are global while config is per project, and the projects that
 * opted in are exactly the ones asking for AutoBot.
 */

import type { AutobotConfig, AutobotProject, AutobotPrompt } from "./config.ts";
import { dueEntries } from "./cron.ts";
import type { ExecutionOutcome } from "./executor.ts";
import { decideFollowups, type FollowupAction } from "./followups.ts";
import type { GithubPollItem } from "./github.ts";
import type { JiraPollItem } from "./jira.ts";
import type { MutexHandle } from "./mutex.ts";

export interface TickDeps {
    /** This harness's instance id. */
    instance: string;
    projects: AutobotProject[];
    now: Date;
    /** True only for a project where a human devbot harness is running. */
    runningDevbot(project: AutobotProject): boolean;
    /** The tick-wide mutex; `null` means an earlier tick is still working. */
    tryLock(): MutexHandle | null;
    /**
     * Answer the user's Slack replies and remind what is still waiting.
     *
     * It runs before the pollers: a reply is a human blocked on progress, while a follow-up comment is
     * new work that can wait a minute.
     */
    handleSlack(): Promise<{ answered: string[]; reminded: string[] }>;
    pollJira(): Promise<JiraPollItem[]>;
    pollGithub(tickets: JiraPollItem[]): Promise<GithubPollItem[]>;
    execute(action: FollowupAction): Promise<ExecutionOutcome>;
    runPrompt(
        project: AutobotProject,
        prompt: AutobotPrompt,
    ): Promise<ExecutionOutcome>;
    log(message: string): void;
}

export interface TickReport {
    skipped: string | null;
    projects: string[];
    actions: ExecutionOutcome[];
    prompts: string[];
    slack: { answered: string[]; reminded: string[] };
}

/** The poll switches of every running project, OR-ed together. Prompts stay per project. */
export function mergeConfigs(
    projects: AutobotProject[],
): Pick<AutobotConfig, "pollJira" | "pollGithub"> {
    return {
        pollJira: projects.some((project) => project.config.pollJira),
        pollGithub: projects.some((project) => project.config.pollGithub),
    };
}

function emptyReport(skipped: string): TickReport {
    return {
        skipped,
        projects: [],
        actions: [],
        prompts: [],
        slack: { answered: [], reminded: [] },
    };
}

export async function runTick(deps: TickDeps): Promise<TickReport> {
    const lock = deps.tryLock();
    if (!lock) {
        deps.log("skipped: another tick is still running");
        return emptyReport("locked");
    }

    try {
        const active = deps.projects.filter((project) =>
            deps.runningDevbot(project),
        );
        if (active.length === 0) {
            deps.log("skipped: no project has a running devbot harness");
            return emptyReport("no running devbot");
        }

        const report: TickReport = {
            skipped: null,
            projects: active.map((project) => project.name),
            actions: [],
            prompts: [],
            slack: { answered: [], reminded: [] },
        };
        const config = mergeConfigs(active);

        report.slack = await deps.handleSlack();

        if (config.pollJira || config.pollGithub) {
            const jira = await deps.pollJira();
            const github = config.pollGithub ? await deps.pollGithub(jira) : [];
            const actions = decideFollowups({
                jira,
                github,
                config,
                instance: deps.instance,
                liveInstances: [deps.instance],
            });
            for (const action of actions) {
                report.actions.push(await deps.execute(action));
            }
        }

        for (const project of active) {
            for (const prompt of dueEntries(project.config.prompts, deps.now)) {
                report.prompts.push(`${project.name}: ${prompt.prompt}`);
                await deps.runPrompt(project, prompt);
            }
        }

        return report;
    } finally {
        lock.release();
    }
}

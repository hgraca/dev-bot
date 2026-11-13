/**
 * The `autobot tick` command: read the workspace configuration, wire the real transports, run one tick.
 *
 * Everything that decides *what* happens lives in the pure modules; this file only resolves paths,
 * environment and process boundaries.
 */

import { createHash } from "node:crypto";
import {
    existsSync,
    mkdirSync,
    readFileSync,
    readdirSync,
    rmSync,
    writeFileSync,
} from "node:fs";
import { hostname } from "node:os";
import { join } from "node:path";

import {
    collectOptedInProjects,
    effectiveAssignees,
    jiraConnections,
    slackConnections,
    parseJsonc,
    type AutobotProject,
    type ManagedProject,
} from "./config.ts";
import {
    cleanupSessions,
    type CleanupReport,
    type SessionSummary,
} from "./cleanup.ts";
import type { ExecutorDeps } from "./executor.ts";
import { executeAction } from "./executor.ts";
import { pollGithub } from "./github.ts";
import { resolveEnvReference } from "./envref.ts";
import {
    PARK_PHASES,
    parkFileName,
    parsePark,
    serialisePark,
    threadKey,
    type Park,
    type ParkPhase,
} from "./park.ts";
import { pollJira } from "./jira.ts";
import { projectHasRunningDevbot, sweepDeadLocks } from "./lock.ts";
import { acquireMutex } from "./mutex.ts";
import { serialiseState } from "./state.ts";
import { createSlackClient, type SlackTransport } from "./slack.ts";
import { answerPrompt, runSlackPass } from "./slackrun.ts";
import { runTick, type TickReport } from "./tick.ts";
import {
    createGithubTransport,
    createJiraClient,
    deleteOpencodeSession,
    listOpencodeSessions,
    runAgent,
    vacuumOpencodeDatabase,
} from "./transports.ts";

export interface CliEnv {
    [key: string]: string | undefined;
}

/** `[core] …` in a summary names the repo; `transfers` is `core`'s label. */
const REPO_ALIASES: Record<string, string> = { transfers: "core" };
const REPO_PREFIX = /^\s*\[([^\]]+)\]/;

/** What a ticket's summary says about its repository. */
export type RepoReference =
    | { kind: "none" }
    | { kind: "unknown"; name: string }
    | { kind: "found"; project: ManagedProject };

/**
 * Resolve the bracketed repo prefix.
 *
 * "No prefix" and "a prefix naming something unknown" are different answers: the first may fall back
 * to the workspace root, the second must not — a prefix is an instruction, and quietly running in the
 * root would work the wrong checkout.
 */
export function repoReference(
    summary: string,
    projects: ManagedProject[],
): RepoReference {
    const match = REPO_PREFIX.exec(summary);
    if (!match) return { kind: "none" };
    const raw = (match[1] ?? "").trim().toLowerCase();
    const name = REPO_ALIASES[raw] ?? raw;
    const project = projects.find(
        (candidate) => candidate.name.toLowerCase() === name,
    );
    return project
        ? { kind: "found", project }
        : { kind: "unknown", name: raw };
}

function sessionIndexDir(env: CliEnv): string {
    return join(stateRoot(env), "devbot", "autobot", "sessions");
}

function readSessionIndex(env: CliEnv): Set<string> {
    try {
        return new Set(readdirSync(sessionIndexDir(env)));
    } catch {
        return new Set();
    }
}

function recordSessionIndex(env: CliEnv, sessionId: string): void {
    try {
        mkdirSync(sessionIndexDir(env), { recursive: true });
        writeFileSync(join(sessionIndexDir(env), sessionId), "", { flag: "a" });
    } catch {
        // The index is housekeeping; a failure must not stop a run.
    }
}

function forgetSession(env: CliEnv, sessionId: string): void {
    try {
        rmSync(join(sessionIndexDir(env), sessionId), { force: true });
    } catch {
        // ignore
    }
}

function stateRoot(env: CliEnv): string {
    if (env.XDG_STATE_HOME && env.XDG_STATE_HOME.trim() !== "")
        return env.XDG_STATE_HOME;
    return join(env.HOME ?? process.env.HOME ?? ".", ".local", "state");
}

/** One client per distinct Jira connection, so instances stay independent of each other. */
function jiraClients(
    projects: AutobotProject[],
    env: CliEnv,
    mode: "polling" | "all" = "polling",
) {
    return jiraConnections(
        projects,
        (value) => resolveEnvReference(value, env),
        mode,
    ).map((group) => ({
        id: `${group.connection.baseUrl}\u0000${group.connection.email}\u0000${group.connection.token}`,
        ...group,
        client: createJiraClient(group.connection),
    }));
}

/** Per-connection conversation state: who the bot talks to, in which channel, and how far it read. */
interface ConversationState {
    userId: string;
    channelId: string;
    /** Newest message already handled. */
    watermark?: string;
    /** Thread per ticket, so a ticket's conversation stays contiguous. */
    threads?: Record<string, string>;
}

function slackRoot(env: CliEnv): string {
    return join(stateRoot(env), "devbot", "autobot", "slack");
}

/**
 * The on-disk name of a connection. The email and token are hashed rather than used: a token is a
 * credential and has no business in a path.
 */
function connectionKey(email: string, token: string): string {
    return createHash("sha256")
        .update(`${email}\u0000${token}`)
        .digest("hex")
        .slice(0, 16);
}

function readConversation(env: CliEnv, key: string): ConversationState | null {
    try {
        const raw = JSON.parse(
            readFileSync(join(slackRoot(env), `${key}.json`), "utf8"),
        ) as unknown;
        if (raw === null || typeof raw !== "object") return null;
        const record = raw as Record<string, unknown>;
        if (
            typeof record.userId !== "string" ||
            typeof record.channelId !== "string"
        )
            return null;
        return {
            userId: record.userId,
            channelId: record.channelId,
            ...(typeof record.watermark === "string"
                ? { watermark: record.watermark }
                : {}),
            ...(record.threads !== null && typeof record.threads === "object"
                ? { threads: record.threads as Record<string, string> }
                : {}),
        };
    } catch {
        return null;
    }
}

function writeConversation(
    env: CliEnv,
    key: string,
    state: ConversationState,
): void {
    mkdirSync(slackRoot(env), { recursive: true });
    writeFileSync(
        join(slackRoot(env), `${key}.json`),
        JSON.stringify(state),
        "utf8",
    );
}

function parksDir(env: CliEnv, key: string): string {
    return join(slackRoot(env), "parks", key);
}

function readParks(env: CliEnv, key: string): Park[] {
    const dir = parksDir(env, key);
    let names: string[] = [];
    try {
        names = readdirSync(dir);
    } catch {
        return [];
    }
    const parks: Park[] = [];
    for (const name of names) {
        if (!name.endsWith(".json")) continue;
        try {
            parks.push(
                parsePark(JSON.parse(readFileSync(join(dir, name), "utf8"))),
            );
        } catch {
            // A park that cannot be read is left alone: deleting it would lose a question the user saw.
            console.warn(`WARN: unreadable park ${join(dir, name)}`);
        }
    }
    return parks;
}

function writePark(env: CliEnv, key: string, park: Park): void {
    const dir = parksDir(env, key);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, parkFileName(park)), serialisePark(park), "utf8");
}

/**
 * Remove one park, and only if it is still the one that was answered.
 *
 * A resumed run may ask a follow-up question and overwrite the file while it runs; deleting then
 * would strand that question with no reminder and no way to resume it.
 */
function clearPark(env: CliEnv, key: string, park: Park): void {
    const file = join(parksDir(env, key), parkFileName(park));
    try {
        const current = parsePark(JSON.parse(readFileSync(file, "utf8")));
        if (current.askedAt !== park.askedAt) return;
    } catch {
        return;
    }
    rmSync(file, { force: true });
}

/** Resolve the conversation once and keep it: the user id and channel never change. */
async function conversation(
    client: SlackTransport,
    email: string,
    env: CliEnv,
    key: string,
): Promise<ConversationState> {
    const cached = readConversation(env, key);
    if (cached) return cached;
    const userId = await client.resolveUser(email);
    const channelId = await client.openDm(userId);
    const state: ConversationState = { userId, channelId };
    writeConversation(env, key, state);
    return state;
}

function stateDirFor(project: AutobotProject): string {
    return join(project.path, project.devbotDir, "state", "devbot");
}

function toRef(project: AutobotProject | null) {
    return project ? { name: project.name, path: project.path } : null;
}

function required(env: CliEnv, key: string): string {
    const value = env[key];
    if (value === undefined || value.trim() === "") {
        throw new Error(`missing required environment variable ${key}`);
    }
    return value;
}

function loadProjects(
    root: string,
    onError?: (message: string) => void,
): AutobotProject[] {
    const globalPath = join(root, ".devbot.global.jsonc");
    if (!existsSync(globalPath)) {
        throw new Error(`no global configuration at ${globalPath}`);
    }
    const globalConfig = parseJsonc(readFileSync(globalPath, "utf8"));
    return collectOptedInProjects(
        globalConfig,
        (projectPath) => {
            const file = join(projectPath, ".devbot.project.jsonc");
            return existsSync(file)
                ? parseJsonc(readFileSync(file, "utf8"))
                : null;
        },
        "global config",
        onError,
    );
}

export async function runTickCommand(
    env: CliEnv = process.env,
): Promise<TickReport> {
    const root = required(env, "DEV_BOT_ROOT");
    const instance = `autobot@${hostname()}`;

    const projects = loadProjects(root, (message) =>
        console.warn(`WARN: ${message}`),
    );
    // Poll only the projects whose harness is running: a stopped project's site must not produce work.
    const live = projects.filter((project) =>
        projectHasRunningDevbot(stateDirFor(project)),
    );
    const jiraGroups = jiraClients(live, env);
    // Not `live`: a parked ticket keeps its reminders after the harness exits, and a reply still
    // resumes the work the user is answering. Only *new* work is gated on a running harness.
    const slackGroups = slackConnections(projects, (value) =>
        resolveEnvReference(value, env),
    ).map((group) => ({
        ...group,
        key: connectionKey(group.connection.email, group.connection.token),
        client: createSlackClient(group.connection.token),
    }));

    // With no repository named, the session starts at the workspace root: every sibling checkout is
    // under it, and the agent resolves the owning project from the files it touches.
    const rootProject =
        projects.find(
            (project) =>
                project.path === root &&
                projectHasRunningDevbot(stateDirFor(project)),
        ) ?? null;

    const pathForTicket = (
        ticketKey: string,
        connection?: string,
    ): string | null => {
        const item = jiraItems.find(
            (ticket) =>
                ticket.key === ticketKey &&
                (ticket.connection ?? "") === (connection ?? ""),
        );
        if (!item) return null;
        const name = item.state?.project;
        if (name) {
            const project = projects.find(
                (candidate) => candidate.name === name,
            );
            return project && projectHasRunningDevbot(stateDirFor(project))
                ? project.path
                : null;
        }
        const reference = repoReference(item.summary, projects);
        if (reference.kind === "found") {
            return projectHasRunningDevbot(stateDirFor(reference.project))
                ? reference.project.path
                : null;
        }
        if (reference.kind === "unknown") return null;
        return rootProject?.path ?? null;
    };

    // Filled by the poll below; `pathForTicket` reads it when GitHub is queried.
    let jiraItems: Awaited<ReturnType<typeof pollJira>> = [];

    // Every side effect goes through the connection that found the ticket: two Jira sites can share an
    // issue key, so a single client keyed by key would write to the wrong one.
    const depsFor = (
        client: (typeof jiraGroups)[number]["client"],
        connectionId: string,
    ): ExecutorDeps => ({
        instance,
        runAgent: (request) => runAgent(request),
        saveState: (ticketKey, state) =>
            client.setState(ticketKey, serialiseState(state)),
        clearState: (ticketKey) => client.setState(ticketKey, null),
        comment: (ticketKey, body) => client.addComment(ticketKey, body),
        closeTicket: (ticketKey, requestedBy) =>
            client.closeIssue(ticketKey, requestedBy),
        addLabels: (ticketKey, labels) => client.addLabels(ticketKey, labels),
        removeLabel: (ticketKey, label) => client.removeLabel(ticketKey, label),
        resolveProject: (ticketKey, state) => {
            const usable = (
                candidate: AutobotProject | null,
            ): AutobotProject | null =>
                candidate && projectHasRunningDevbot(stateDirFor(candidate))
                    ? candidate
                    : null;
            if (state) {
                return toRef(
                    usable(
                        projects.find(
                            (candidate) => candidate.name === state.project,
                        ) ?? null,
                    ),
                );
            }
            const item = jiraItems.find(
                (ticket) =>
                    ticket.key === ticketKey &&
                    (ticket.connection ?? "") === connectionId,
            );
            const reference: RepoReference = item
                ? repoReference(item.summary, projects)
                : { kind: "none" };
            // A prefix is an instruction: an unknown or not-live repository is a miss, never the root.
            if (reference.kind === "found")
                return toRef(usable(reference.project));
            if (reference.kind === "unknown") return null;
            return toRef(rootProject);
        },
        recordSession: (sessionId) => {
            recordSessionIndex(env, sessionId);
            return Promise.resolve();
        },
        attachSession: async (ticketKey, session, projectName) => {
            // A question asked during the run that created the session cannot name it; this is where the
            // id becomes known. Scoped by project, because two sites can return the same ticket key.
            for (const group of slackGroups) {
                for (const park of readParks(env, group.key)) {
                    if (
                        park.ticket !== ticketKey ||
                        park.project !== projectName
                    )
                        continue;
                    writePark(env, group.key, { ...park, session });
                }
            }
        },
    });

    const depsByConnection = new Map(
        jiraGroups.map((group) => [group.id, depsFor(group.client, group.id)]),
    );

    const handleSlack = async (): Promise<{
        answered: string[];
        reminded: string[];
    }> => {
        const answered: string[] = [];
        const reminded: string[] = [];
        for (const group of slackGroups) {
            const store = await conversation(
                group.client,
                group.connection.email,
                env,
                group.key,
            );
            const report = await runSlackPass({
                now: new Date(),
                channel: store.channelId,
                connection: store.userId,
                watermark: store.watermark,
                parks: () => readParks(env, group.key),
                history: (oldest) =>
                    group.client.history(store.channelId, oldest),
                replies: (threadTs) =>
                    group.client.replies(store.channelId, threadTs),
                answer: async (park, text) => {
                    // The park names its project, so a reply resumes in the checkout the work belongs
                    // to — even after the human harness has stopped: the user is answering a question
                    // AutoBot asked, and that answer must not be stranded.
                    const project = projects.find(
                        (candidate) => candidate.name === park.project,
                    );
                    if (!project)
                        return {
                            ok: false,
                            reason: `unknown project ${park.project}`,
                        };
                    const result = await runAgent({
                        project: { name: project.name, path: project.path },
                        session: park.session ?? null,
                        ticketKey: park.ticket,
                        prompt: answerPrompt(park, text),
                        env: {
                            DEV_BOT_AUTOBOT_TICKET: park.ticket,
                            ...(park.session === undefined
                                ? {}
                                : { DEV_BOT_AUTOBOT_SESSION: park.session }),
                        },
                    });
                    return {
                        ok: result.ok,
                        reason: result.summary,
                        session: result.session,
                    };
                },
                post: (text, threadTs) =>
                    group.client.post(store.channelId, text, threadTs),
                savePark: (park) => writePark(env, group.key, park),
                clearPark: (park) => clearPark(env, group.key, park),
                log: (message) => console.log(message),
            });
            answered.push(...report.answered);
            reminded.push(...report.reminded);
            writeConversation(env, group.key, {
                ...store,
                watermark: report.watermark,
            });
        }
        return { answered, reminded };
    };

    return runTick({
        instance,
        projects,
        now: new Date(),
        runningDevbot: (project) =>
            projectHasRunningDevbot(stateDirFor(project)),
        tryLock: () =>
            acquireMutex(
                join(stateRoot(env), "devbot", "autobot", "tick.lock"),
            ),
        handleSlack,
        pollJira: async () => {
            if (jiraGroups.length === 0) {
                throw new Error(
                    "autobot: polling is enabled but no active project sets jira_base_url, jira_email and jira_api_token",
                );
            }
            const polled: Awaited<ReturnType<typeof pollJira>> = [];
            for (const group of jiraGroups) {
                const items = await pollJira({
                    transport: group.client,
                    assignees: effectiveAssignees(group.projects),
                    onError: (message) => console.warn(`WARN: ${message}`),
                });
                for (const item of items)
                    polled.push({ ...item, connection: group.id });
            }
            jiraItems = polled;
            for (const project of projects)
                sweepDeadLocks(stateDirFor(project));
            return jiraItems;
        },
        pollGithub: (tickets) =>
            pollGithub({
                tickets,
                transport: createGithubTransport(pathForTicket),
            }),
        execute: (action) => {
            const deps = depsByConnection.get(action.ticket.connection ?? "");
            if (!deps) {
                throw new Error(
                    "autobot: no Jira connection is configured for this ticket",
                );
            }
            return executeAction(action, deps);
        },
        runPrompt: async (project, prompt) => {
            const result = await runAgent({
                project: { name: project.name, path: project.path },
                session: null,
                ticketKey: "",
                prompt: prompt.prompt,
            });
            if (result.ok && result.session)
                recordSessionIndex(env, result.session);
            return {
                kind: "prompt",
                performed: result.ok,
                reason: result.summary,
            };
        },
        log: (message) => console.log(message),
    });
}

export interface SayOptions {
    text: string;
    ticket: string;
    phase?: ParkPhase;
}

/**
 * `autobot say` — post one message to the user's direct message, and optionally park the run.
 *
 * The agent calls this instead of holding a Slack token: the token is resolved here from the project
 * configuration and never enters the prompt. The ticket comes from the environment the executor set,
 * so the agent does not have to name it on every line.
 *
 * `--ask` writes the park record. That record is what turns "I asked" into "the next tick knows a
 * reply is expected" — without it the question would be a message nobody is waiting for.
 */
export async function runSayCommand(
    argv: string[],
    env: CliEnv = process.env,
    cwd: string = process.cwd(),
    transport: (token: string) => SlackTransport = createSlackClient,
): Promise<{ posted: boolean; ticket: string; threadTs: string }> {
    let phase: ParkPhase | undefined;
    let ask = false;
    let ticket = env.DEV_BOT_AUTOBOT_TICKET ?? "";
    const words: string[] = [];
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i] ?? "";
        if (arg === "--ask") {
            ask = true;
            continue;
        }
        if (arg === "--phase") {
            phase = argv[++i] as ParkPhase;
            continue;
        }
        if (arg === "--ticket") {
            ticket = argv[++i] ?? "";
            continue;
        }
        words.push(arg);
    }
    const text = words.join(" ").trim();
    if (text === "") throw new Error("autobot say: no message given");
    // Validate before posting: a typo must not leave a question on Slack that nothing will resume.
    if (
        phase !== undefined &&
        !(PARK_PHASES as readonly string[]).includes(phase)
    ) {
        throw new Error(
            `autobot say: --phase must be one of ${PARK_PHASES.join(", ")}`,
        );
    }
    if (ask && phase === undefined) {
        throw new Error(
            `autobot say: --ask needs --phase (${PARK_PHASES.join(", ")})`,
        );
    }
    if (!ask && phase !== undefined) {
        throw new Error("autobot say: --phase only makes sense with --ask");
    }
    if (ticket === "") {
        throw new Error(
            "autobot say: no ticket — pass --ticket KEY or run from an AutoBot session",
        );
    }

    const root = required(env, "DEV_BOT_ROOT");
    const projects = loadProjects(root);
    const project =
        projects.find((candidate) => candidate.path === cwd) ??
        projects.find((candidate) => cwd.startsWith(`${candidate.path}/`));
    if (!project)
        throw new Error(`autobot say: ${cwd} is not a managed project`);

    const group = slackConnections(
        [project],
        (value) => resolveEnvReference(value, env),
        "all",
    )[0];
    if (!group) {
        throw new Error(
            `autobot say: ${project.name} has no slack_user_email and slack_bot_token configured`,
        );
    }

    const client = transport(group.connection.token);
    const key = connectionKey(group.connection.email, group.connection.token);
    const store = await conversation(client, group.connection.email, env, key);
    // Keyed by project as well as ticket: two sites can share a key on one connection.
    const keyed = threadKey(project.name, ticket);
    const threadTs = store.threads?.[keyed];
    const posted = await client.post(store.channelId, text, threadTs);
    // The first message of a ticket opens its thread; every later one joins it.
    const thread = threadTs ?? posted;
    writeConversation(env, key, {
        ...store,
        threads: { ...(store.threads ?? {}), [keyed]: thread },
    });

    if (ask && phase !== undefined) {
        writePark(env, key, {
            ticket,
            project: project.name,
            connection: store.userId,
            channel: store.channelId,
            threadTs: thread,
            phase,
            question: text,
            askedAt: posted,
            ...(env.DEV_BOT_AUTOBOT_SESSION === undefined ||
            env.DEV_BOT_AUTOBOT_SESSION === ""
                ? {}
                : { session: env.DEV_BOT_AUTOBOT_SESSION }),
        });
    }

    return { posted: true, ticket, threadTs: thread };
}

/**
 * Delete opencode sessions no ticket points at, then reclaim the space.
 *
 * Deterministic on purpose: this is the one job that must not be handed to a model. Run it from its
 * own crontab line rather than from a configured prompt.
 */
export async function runCleanupCommand(
    env: CliEnv = process.env,
): Promise<CleanupReport> {
    const root = required(env, "DEV_BOT_ROOT");

    // A live harness owns the opencode store: deleting sessions or vacuuming under it can block or
    // corrupt the database. Cleanup waits for a quiet machine.
    const managed = loadProjects(root, (message) =>
        console.warn(`WARN: ${message}`),
    );
    if (
        managed.some((project) => projectHasRunningDevbot(stateDirFor(project)))
    ) {
        console.warn("WARN: a devbot harness is running — skipping cleanup");
        return { deleted: [], kept: 0 };
    }

    // Cleanup must not delete a session a tick is using right now.
    const lock = acquireMutex(
        join(stateRoot(env), "devbot", "autobot", "tick.lock"),
    );
    if (!lock) {
        console.warn("WARN: a tick is running — skipping cleanup");
        return { deleted: [], kept: 0 };
    }
    try {
        return await cleanupLocked(env, root);
    } finally {
        lock.release();
    }
}

async function cleanupLocked(
    env: CliEnv,
    root: string,
): Promise<CleanupReport> {
    const managed = loadProjects(root, (message) =>
        console.warn(`WARN: ${message}`),
    );
    // Cleanup must cover every site it scans, so it polls all configured connections, not only the
    // ones whose poll switches are on.
    const groups = jiraClients(managed, env, "all");
    if (groups.length === 0) {
        // Without a connection the referenced sessions cannot be known, and deleting blind is worse than
        // not cleaning.
        console.warn(
            "WARN: no Jira connection is configured — skipping cleanup",
        );
        return { deleted: [], kept: 0 };
    }

    let pollFailed = false;
    const items: Awaited<ReturnType<typeof pollJira>> = [];
    for (const group of groups) {
        const polled = await pollJira({
            transport: group.client,
            onError: (message) => {
                pollFailed = true;
                console.warn(`WARN: ${message}`);
            },
        });
        items.push(...polled);
    }
    if (pollFailed) {
        // A ticket whose state could not be read would look unreferenced, so its session would be deleted.
        console.warn(
            "WARN: a ticket could not be read — skipping cleanup this run",
        );
        return { deleted: [], kept: 0 };
    }

    const referenced = new Set<string>();
    for (const item of items) {
        if (item.state?.session) referenced.add(item.state.session);
    }

    // Only sessions this module created are candidates: the index is written when a session starts, so
    // a developer's own sessions in the same project directory are never touched.
    const owned = readSessionIndex(env);
    const pathBySession = new Map<string, string>();
    const sessions: SessionSummary[] = [];
    for (const project of managed) {
        // A project with no connection cannot have its referenced sessions known, so its sessions are
        // never candidates — deleting them would be deleting on partial evidence.
        if (!project.config.jiraBaseUrl) {
            console.warn(
                `WARN: ${project.name} has no Jira connection — its sessions are excluded from cleanup`,
            );
            continue;
        }
        for (const session of await listOpencodeSessions(project.path)) {
            if (!owned.has(session.id) || pathBySession.has(session.id))
                continue;
            pathBySession.set(session.id, project.path);
            sessions.push(session);
        }
    }

    return cleanupSessions({
        sessions,
        referenced,
        now: new Date(),
        deleteSession: async (id) => {
            // `opencode session delete` resolves against its working directory, the same one that listed it.
            await deleteOpencodeSession(id, pathBySession.get(id) ?? root);
            forgetSession(env, id);
        },
        vacuum: () => vacuumOpencodeDatabase(root),
    });
}

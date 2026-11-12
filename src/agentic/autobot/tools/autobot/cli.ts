/**
 * The `autobot tick` command: read the workspace configuration, wire the real transports, run one tick.
 *
 * Everything that decides *what* happens lives in the pure modules; this file only resolves paths,
 * environment and process boundaries.
 */

import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { hostname } from "node:os";
import { join } from "node:path";

import {
  collectOptedInProjects,
  parseJsonc,
  type AutobotProject,
  type ManagedProject,
} from "./config.ts";
import { cleanupSessions, type CleanupReport, type SessionSummary } from "./cleanup.ts";
import type { ExecutorDeps } from "./executor.ts";
import { executeAction } from "./executor.ts";
import { pollGithub } from "./github.ts";
import { pollJira } from "./jira.ts";
import { projectHasRunningDevbot, sweepDeadLocks } from "./lock.ts";
import { acquireMutex } from "./mutex.ts";
import { serialiseState } from "./state.ts";
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

/** The managed project a ticket's summary points at, if it says. */
export function resolveProjectFromSummary(
  summary: string,
  projects: ManagedProject[],
): ManagedProject | null {
  const match = REPO_PREFIX.exec(summary);
  if (!match) return null;
  const raw = (match[1] ?? "").trim().toLowerCase();
  const name = REPO_ALIASES[raw] ?? raw;
  return projects.find((project) => project.name.toLowerCase() === name) ?? null;
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
  if (env.XDG_STATE_HOME && env.XDG_STATE_HOME.trim() !== "") return env.XDG_STATE_HOME;
  return join(env.HOME ?? process.env.HOME ?? ".", ".local", "state");
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

function loadProjects(root: string, onError?: (message: string) => void): AutobotProject[] {
  const globalPath = join(root, ".devbot.global.jsonc");
  if (!existsSync(globalPath)) {
    throw new Error(`no global configuration at ${globalPath}`);
  }
  const globalConfig = parseJsonc(readFileSync(globalPath, "utf8"));
  return collectOptedInProjects(
    globalConfig,
    (projectPath) => {
      const file = join(projectPath, ".devbot.project.jsonc");
      return existsSync(file) ? parseJsonc(readFileSync(file, "utf8")) : null;
    },
    "global config",
    onError,
  );
}

export async function runTickCommand(env: CliEnv = process.env): Promise<TickReport> {
  const root = required(env, "DEV_BOT_ROOT");
  const instance = `autobot@${hostname()}`;
  const accountId = required(env, "AUTOBOT_JIRA_ACCOUNT_ID");
  const githubLogin = required(env, "AUTOBOT_GITHUB_LOGIN");

  const projects = loadProjects(root, (message) => console.warn(`WARN: ${message}`));
  const jira = createJiraClient({
    baseUrl: required(env, "JIRA_BASE_URL"),
    email: required(env, "JIRA_EMAIL"),
    token: required(env, "JIRA_API_TOKEN"),
  });

  const pathForTicket = (ticketKey: string): string | null => {
    const item = jiraItems.find((ticket) => ticket.key === ticketKey);
    if (!item) return null;
    const name = item.state?.project;
    const project = name
      ? projects.find((candidate) => candidate.name === name)
      : resolveProjectFromSummary(item.summary, projects);
    if (!project || !projectHasRunningDevbot(stateDirFor(project))) return null;
    return project.path;
  };

  // Filled by the poll below; `pathForTicket` reads it when GitHub is queried.
  let jiraItems: Awaited<ReturnType<typeof pollJira>> = [];

  const executorDeps: ExecutorDeps = {
    instance,
    runAgent: (request) => runAgent(request),
    saveState: (ticketKey, state) => jira.setState(ticketKey, serialiseState(state)),
    clearState: (ticketKey) => jira.setState(ticketKey, null),
    comment: (ticketKey, body) => jira.addComment(ticketKey, body),
    closeTicket: (ticketKey, requestedBy) => jira.closeIssue(ticketKey, requestedBy),
    unassignTicket: (ticketKey) => jira.unassignIssue(ticketKey),
    resolveProject: (ticketKey, state) => {
      const usable = (candidate: AutobotProject | null): AutobotProject | null =>
        candidate && projectHasRunningDevbot(stateDirFor(candidate)) ? candidate : null;
      if (state) {
        return toRef(usable(projects.find((candidate) => candidate.name === state.project) ?? null));
      }
      const item = jiraItems.find((ticket) => ticket.key === ticketKey);
      return toRef(usable(item ? resolveProjectFromSummary(item.summary, projects) : null));
    },
    recordSession: (sessionId) => {
      recordSessionIndex(env, sessionId);
      return Promise.resolve();
    },
  };

  return runTick({
    instance,
    projects,
    now: new Date(),
    runningDevbot: (project) => projectHasRunningDevbot(stateDirFor(project)),
    tryLock: () => acquireMutex(join(stateRoot(env), "devbot", "autobot", "tick.lock")),
    pollJira: async () => {
      jiraItems = await pollJira({
        accountId,
        transport: jira,
        onError: (message) => console.warn(`WARN: ${message}`),
      });
      for (const project of projects) sweepDeadLocks(stateDirFor(project));
      return jiraItems;
    },
    pollGithub: (tickets) =>
      pollGithub({
        tickets,
        botLogin: githubLogin,
        transport: createGithubTransport(pathForTicket),
      }),
    execute: (action) => executeAction(action, executorDeps),
    runPrompt: async (project, prompt) => {
      const result = await runAgent({
        project: { name: project.name, path: project.path },
        session: null,
        ticketKey: "",
        prompt: prompt.prompt,
      });
      if (result.ok && result.session) recordSessionIndex(env, result.session);
      return { kind: "prompt", performed: result.ok, reason: result.summary };
    },
    log: (message) => console.log(message),
  });
}

/**
 * Delete opencode sessions no ticket points at, then reclaim the space.
 *
 * Deterministic on purpose: this is the one job that must not be handed to a model. Run it from its
 * own crontab line rather than from a configured prompt.
 */
export async function runCleanupCommand(env: CliEnv = process.env): Promise<CleanupReport> {
  const root = required(env, "DEV_BOT_ROOT");
  const accountId = required(env, "AUTOBOT_JIRA_ACCOUNT_ID");

  // A live harness owns the opencode store: deleting sessions or vacuuming under it can block or
  // corrupt the database. Cleanup waits for a quiet machine.
  const managed = loadProjects(root, (message) => console.warn(`WARN: ${message}`));
  if (managed.some((project) => projectHasRunningDevbot(stateDirFor(project)))) {
    console.warn("WARN: a devbot harness is running — skipping cleanup");
    return { deleted: [], kept: 0 };
  }

  // Cleanup must not delete a session a tick is using right now.
  const lock = acquireMutex(join(stateRoot(env), "devbot", "autobot", "tick.lock"));
  if (!lock) {
    console.warn("WARN: a tick is running — skipping cleanup");
    return { deleted: [], kept: 0 };
  }
  try {
    return await cleanupLocked(env, root, accountId);
  } finally {
    lock.release();
  }
}

async function cleanupLocked(
  env: CliEnv,
  root: string,
  accountId: string,
): Promise<CleanupReport> {
  const jira = createJiraClient({
    baseUrl: required(env, "JIRA_BASE_URL"),
    email: required(env, "JIRA_EMAIL"),
    token: required(env, "JIRA_API_TOKEN"),
  });

  let pollFailed = false;
  const items = await pollJira({
    accountId,
    transport: jira,
    onError: (message) => {
      pollFailed = true;
      console.warn(`WARN: ${message}`);
    },
  });
  if (pollFailed) {
    // A ticket whose state could not be read would look unreferenced, so its session would be deleted.
    console.warn("WARN: a ticket could not be read — skipping cleanup this run");
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
  for (const project of loadProjects(root, (message) => console.warn(`WARN: ${message}`))) {
    for (const session of await listOpencodeSessions(project.path)) {
      if (!owned.has(session.id) || pathBySession.has(session.id)) continue;
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

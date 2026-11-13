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
  jiraConnections,
  parseJsonc,
  type AutobotProject,
  type ManagedProject,
} from "./config.ts";
import { cleanupSessions, type CleanupReport, type SessionSummary } from "./cleanup.ts";
import type { ExecutorDeps } from "./executor.ts";
import { executeAction } from "./executor.ts";
import { pollGithub } from "./github.ts";
import { resolveEnvReference } from "./envref.ts";
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
export function repoReference(summary: string, projects: ManagedProject[]): RepoReference {
  const match = REPO_PREFIX.exec(summary);
  if (!match) return { kind: "none" };
  const raw = (match[1] ?? "").trim().toLowerCase();
  const name = REPO_ALIASES[raw] ?? raw;
  const project = projects.find((candidate) => candidate.name.toLowerCase() === name);
  return project ? { kind: "found", project } : { kind: "unknown", name: raw };
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

/** One client per distinct Jira connection, so instances stay independent of each other. */
function jiraClients(
  projects: AutobotProject[],
  env: CliEnv,
  mode: "polling" | "all" = "polling",
) {
  return jiraConnections(projects, (value) => resolveEnvReference(value, env), mode).map((group) => ({
    id: `${group.connection.baseUrl}\u0000${group.connection.email}\u0000${group.connection.token}`,
    ...group,
    client: createJiraClient(group.connection),
  }));
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

  const projects = loadProjects(root, (message) => console.warn(`WARN: ${message}`));
  // Poll only the projects whose harness is running: a stopped project's site must not produce work.
  const live = projects.filter((project) => projectHasRunningDevbot(stateDirFor(project)));
  const jiraGroups = jiraClients(live, env);

  // With no repository named, the session starts at the workspace root: every sibling checkout is
  // under it, and the agent resolves the owning project from the files it touches.
  const rootProject =
    projects.find((project) => project.path === root && projectHasRunningDevbot(stateDirFor(project))) ??
    null;

  const pathForTicket = (ticketKey: string, connection?: string): string | null => {
    const item = jiraItems.find(
      (ticket) => ticket.key === ticketKey && (ticket.connection ?? "") === (connection ?? ""),
    );
    if (!item) return null;
    const name = item.state?.project;
    if (name) {
      const project = projects.find((candidate) => candidate.name === name);
      return project && projectHasRunningDevbot(stateDirFor(project)) ? project.path : null;
    }
    const reference = repoReference(item.summary, projects);
    if (reference.kind === "found") {
      return projectHasRunningDevbot(stateDirFor(reference.project)) ? reference.project.path : null;
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
    saveState: (ticketKey, state) => client.setState(ticketKey, serialiseState(state)),
    clearState: (ticketKey) => client.setState(ticketKey, null),
    comment: (ticketKey, body) => client.addComment(ticketKey, body),
    closeTicket: (ticketKey, requestedBy) => client.closeIssue(ticketKey, requestedBy),
    addLabels: (ticketKey, labels) => client.addLabels(ticketKey, labels),
    removeLabel: (ticketKey, label) => client.removeLabel(ticketKey, label),
    resolveProject: (ticketKey, state) => {
      const usable = (candidate: AutobotProject | null): AutobotProject | null =>
        candidate && projectHasRunningDevbot(stateDirFor(candidate)) ? candidate : null;
      if (state) {
        return toRef(usable(projects.find((candidate) => candidate.name === state.project) ?? null));
      }
      const item = jiraItems.find(
        (ticket) => ticket.key === ticketKey && (ticket.connection ?? "") === connectionId,
      );
      const reference: RepoReference = item ? repoReference(item.summary, projects) : { kind: "none" };
      // A prefix is an instruction: an unknown or not-live repository is a miss, never the root.
      if (reference.kind === "found") return toRef(usable(reference.project));
      if (reference.kind === "unknown") return null;
      return toRef(rootProject);
    },
    recordSession: (sessionId) => {
      recordSessionIndex(env, sessionId);
      return Promise.resolve();
    },
  });

  const depsByConnection = new Map(
    jiraGroups.map((group) => [group.id, depsFor(group.client, group.id)]),
  );

  return runTick({
    instance,
    projects,
    now: new Date(),
    runningDevbot: (project) => projectHasRunningDevbot(stateDirFor(project)),
    tryLock: () => acquireMutex(join(stateRoot(env), "devbot", "autobot", "tick.lock")),
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
          onError: (message) => console.warn(`WARN: ${message}`),
        });
        for (const item of items) polled.push({ ...item, connection: group.id });
      }
      jiraItems = polled;
      for (const project of projects) sweepDeadLocks(stateDirFor(project));
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
        throw new Error("autobot: no Jira connection is configured for this ticket");
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
    return await cleanupLocked(env, root);
  } finally {
    lock.release();
  }
}

async function cleanupLocked(env: CliEnv, root: string): Promise<CleanupReport> {
  const managed = loadProjects(root, (message) => console.warn(`WARN: ${message}`));
  // Cleanup must cover every site it scans, so it polls all configured connections, not only the
  // ones whose poll switches are on.
  const groups = jiraClients(managed, env, "all");
  if (groups.length === 0) {
    // Without a connection the referenced sessions cannot be known, and deleting blind is worse than
    // not cleaning.
    console.warn("WARN: no Jira connection is configured — skipping cleanup");
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

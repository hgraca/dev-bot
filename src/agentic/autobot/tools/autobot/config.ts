/**
 * AutoBot configuration: the managed-project list from the global devbot config, and each project's
 * `autobot` block (follow-up pollers plus scheduled prompts).
 *
 * Everything here is pure — file reading is injected — so the whole module is unit-testable without
 * touching disk. JSONC is parsed by the local stripper rather than shelling out to `read_jsonc.py`,
 * which keeps this callable from tests and from a cron tick that has no shell profile.
 */

import { parseSchedule } from "./cron.ts";

export interface AutobotPrompt {
  schedule: string;
  prompt: string;
}

export interface AutobotConfig {
  pollJira: boolean;
  pollGithub: boolean;
  prompts: AutobotPrompt[];
  /** Jira connection for the projects AutoBot works. Values may be environment references. */
  jiraBaseUrl?: string;
  jiraEmail?: string;
  jiraApiToken?: string;
  /**
   * Only pick up tickets assigned to one of these people.
   *
   * Required whenever the block is present: an empty array means pick up nothing, so a project must
   * say which it wants rather than inherit a default by omission.
   */
  jiraAssignees: string[];
}

export interface ManagedProject {
  name: string;
  path: string;
  /** Per-project runtime directory holding `state/`, defaulting to `.agents`. */
  devbotDir: string;
}

export interface AutobotProject extends ManagedProject {
  config: AutobotConfig;
}

/** A block with every switch off. A project carrying only these defaults is inert. */
export function defaultAutobotConfig(): AutobotConfig {
  return { pollJira: false, pollGithub: false, prompts: [], jiraAssignees: [] };
}

/** Skip whitespace and both comment forms, returning the index of the next meaningful character. */
function skipTrivia(text: string, from: number): number {
  let i = from;
  while (i < text.length) {
    const ch = text[i];
    if (ch === " " || ch === "\t" || ch === "\n" || ch === "\r") {
      i += 1;
      continue;
    }
    if (ch === "/" && text[i + 1] === "/") {
      const nl = text.indexOf("\n", i);
      i = nl === -1 ? text.length : nl;
      continue;
    }
    if (ch === "/" && text[i + 1] === "*") {
      const end = text.indexOf("*/", i + 2);
      i = end === -1 ? text.length : end + 2;
      continue;
    }
    break;
  }
  return i;
}

/**
 * Strip `//` and block comments plus trailing commas. String-aware: comment markers and commas
 * inside string literals are copied verbatim.
 */
export function stripJsonc(text: string): string {
  let out = "";
  let i = 0;
  while (i < text.length) {
    const ch = text[i];

    if (ch === '"') {
      let j = i + 1;
      while (j < text.length) {
        if (text[j] === "\\") {
          j += 2;
          continue;
        }
        if (text[j] === '"') {
          j += 1;
          break;
        }
        j += 1;
      }
      out += text.slice(i, j);
      i = j;
      continue;
    }

    if (ch === "/" && text[i + 1] === "/") {
      const nl = text.indexOf("\n", i);
      i = nl === -1 ? text.length : nl;
      continue;
    }

    if (ch === "/" && text[i + 1] === "*") {
      const end = text.indexOf("*/", i + 2);
      i = end === -1 ? text.length : end + 2;
      continue;
    }

    if (ch === ",") {
      const next = skipTrivia(text, i + 1);
      if (text[next] === "}" || text[next] === "]") {
        i += 1;
        continue;
      }
    }

    out += ch;
    i += 1;
  }
  return out;
}

export function parseJsonc(text: string): unknown {
  return JSON.parse(stripJsonc(text));
}

function validateSchedule(value: unknown, where: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${where}: "schedule" must be a non-empty string`);
  }
  const schedule = value.trim();
  parseSchedule(schedule, where);
  return schedule;
}

function validatePrompt(value: unknown, where: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${where}: "prompt" must be a non-empty string`);
  }
  return value;
}

function readFlag(value: unknown, key: string, where: string): boolean {
  if (value === undefined) return false;
  if (typeof value !== "boolean") {
    throw new Error(`${where}: "autobot.${key}" must be a boolean`);
  }
  return value;
}

function optionalConnection(value: unknown, key: string, where: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${where}: "autobot.${key}" must be a non-empty string`);
  }
  return value.trim();
}

function readAssignees(value: unknown, where: string): string[] {
  if (value === undefined || value === null) {
    throw new Error(
      `${where}: "autobot.jira_assignees" is required — use [] to pick up nothing, or the assignees to pick up`,
    );
  }
  if (!Array.isArray(value)) {
    throw new Error(`${where}: "autobot.jira_assignees" must be an array of names or emails`);
  }
  return value.map((entry, index) => {
    if (typeof entry !== "string" || entry.trim() === "") {
      throw new Error(`${where}: autobot.jira_assignees[${index}] must be a non-empty string`);
    }
    return entry.trim();
  });
}

function readPrompts(value: unknown, where: string): AutobotPrompt[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new Error(`${where}: "autobot.prompts" must be an array`);
  }
  return value.map((item, index) => {
    const at = `${where}: autobot.prompts[${index}]`;
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      throw new Error(`${at} must be an object with "schedule" and "prompt"`);
    }
    const entry = item as Record<string, unknown>;
    return {
      schedule: validateSchedule(entry.schedule, at),
      prompt: validatePrompt(entry.prompt, at),
    };
  });
}

/**
 * Read the `autobot` block out of one project config.
 *
 * Returns `null` only when the block is absent — an absent block is the opt-out, not an error. A
 * block that is present has every key defaulted, so callers never handle partial shapes.
 */
/** Named profiles declared once in the global config and referenced by name from a project. */
export type AutobotProfiles = Record<string, unknown>;

/** The `autobot` profiles map from the global config; an absent map means there are none. */
export function parseAutobotProfiles(globalConfig: unknown, source = "global config"): AutobotProfiles {
  if (globalConfig === null || typeof globalConfig !== "object" || Array.isArray(globalConfig)) {
    return {};
  }
  const raw = (globalConfig as Record<string, unknown>).autobot;
  if (raw === undefined || raw === null) return {};
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error(`${source}: "autobot" must be an object of named profiles`);
  }
  return raw as AutobotProfiles;
}

export function parseAutobotConfig(
  config: unknown,
  source: string,
  profiles: AutobotProfiles = {},
): AutobotConfig | null {
  if (config === null || typeof config !== "object" || Array.isArray(config)) {
    throw new Error(`${source}: project config must be a JSON object`);
  }
  let raw = (config as Record<string, unknown>).autobot;
  if (raw === undefined || raw === null) return null;
  // A string names a profile; an object is the configuration itself. A project is one or the other,
  // never a profile plus overrides.
  let profileName: string | null = null;
  if (typeof raw === "string") {
    const name = raw.trim();
    if (name === "") throw new Error(`${source}: "autobot" names an empty profile`);
    // Own properties only: `in` would accept `__proto__` and hand back Object.prototype.
    if (!Object.hasOwn(profiles, name)) {
      throw new Error(`${source}: "autobot" names unknown profile "${name}"`);
    }
    profileName = name;
    raw = profiles[name];
  }
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error(
      profileName === null
        ? `${source}: "autobot" must be a profile name or an object`
        : `${source}: autobot profile "${profileName}" must be an object`,
    );
  }
  const block = raw as Record<string, unknown>;
  const connection = {
    baseUrl: optionalConnection(block.jira_base_url, "jira_base_url", source),
    email: optionalConnection(block.jira_email, "jira_email", source),
    token: optionalConnection(block.jira_api_token, "jira_api_token", source),
  };
  const set = Object.values(connection).filter((value) => value !== undefined).length;
  if (set !== 0 && set !== 3) {
    throw new Error(
      `${source}: "autobot" sets ${set} of jira_base_url, jira_email and jira_api_token — all three or none`,
    );
  }
  const parsed: AutobotConfig = {
    pollJira: readFlag(block.poll_jira, "poll_jira", source),
    pollGithub: readFlag(block.poll_github, "poll_github", source),
    prompts: readPrompts(block.prompts, source),
    jiraAssignees: readAssignees(block.jira_assignees, source),
  };
  // Only carry the connection when it is configured: an absent one must not appear as a property.
  if (connection.baseUrl !== undefined) {
    parsed.jiraBaseUrl = connection.baseUrl;
    parsed.jiraEmail = connection.email;
    parsed.jiraApiToken = connection.token;
  }
  if ((parsed.pollJira || parsed.pollGithub) && parsed.jiraBaseUrl === undefined) {
    throw new Error(
      `${source}: polling needs jira_base_url, jira_email and jira_api_token in this project`,
    );
  }
  return parsed;
}

export interface JiraConnection {
  baseUrl: string;
  email: string;
  token: string;
}

export interface JiraGroup {
  connection: JiraConnection;
  /** The projects that use this connection. */
  projects: AutobotProject[];
}

/**
 * The Jira connections the active projects configure, one group per distinct connection.
 *
 * Instances are independent and may legitimately point at different Jira sites, so projects are
 * grouped rather than forced to agree: each poll uses its own connection, and a ticket is answered
 * with the connection of the project that owns it.
 */
export function jiraConnections(
  projects: AutobotProject[],
  resolve: (value: string) => string = (value) => value,
  /** `polling` is the tick's view; `all` is cleanup's, which must cover every site it scans. */
  mode: "polling" | "all" = "polling",
): JiraGroup[] {
  const groups = new Map<string, JiraGroup>();
  for (const project of projects) {
    // A project that only runs prompts has no business being polled by the tick; its site would
    // otherwise be queried, and a bad variable there could abort the tick before its prompts ran.
    if (mode === "polling" && !project.config.pollJira && !project.config.pollGithub) continue;
    const { jiraBaseUrl, jiraEmail, jiraApiToken } = project.config;
    if (!jiraBaseUrl || !jiraEmail || !jiraApiToken) continue;
    // Group by the resolved values: `${VAR}` and `{env:VAR}` name the same instance, and two
    // variables holding the same value do too.
    const connection = {
      // Normalised the same way the client does it, so a trailing slash cannot split one site in two.
      baseUrl: resolve(jiraBaseUrl).replace(/\/+$/, ""),
      email: resolve(jiraEmail),
      token: resolve(jiraApiToken),
    };
    const key = `${connection.baseUrl}\u0000${connection.email}\u0000${connection.token}`;
    const existing = groups.get(key);
    if (existing) {
      existing.projects.push(project);
      continue;
    }
    groups.set(key, { connection, projects: [project] });
  }
  return [...groups.values()];
}

/**
 * The assignee filter a connection's projects agree on: the union of their lists.
 *
 * Every project declares one, so an empty result can only mean they all asked for nothing.
 */
export function effectiveAssignees(projects: AutobotProject[]): string[] {
  return [...new Set(projects.flatMap((project) => project.config.jiraAssignees))];
}

/** True when the block does any work. An all-defaults block is inert. */
export function isAutobotActive(config: AutobotConfig): boolean {
  return config.pollJira || config.pollGithub || config.prompts.length > 0;
}

const DEFAULT_DEVBOT_DIR = ".agents";
const DEVBOT_DIR_SEGMENT = /^[A-Za-z0-9._-]+$/;

/** A relative path whose every component is safe: no absolute root, no `.` or `..`. */
function isSafeRelativePath(value: string): boolean {
  if (value.startsWith("/")) return false;
  return value
    .split("/")
    .every(
      (segment) =>
        segment !== "" &&
        segment !== "." &&
        segment !== ".." &&
        DEVBOT_DIR_SEGMENT.test(segment),
    );
}

function readDevbotDir(config: unknown, fallback: string): string {
  if (config !== null && typeof config === "object" && !Array.isArray(config)) {
    const raw = (config as Record<string, unknown>).devbot_dir;
    if (typeof raw === "string" && raw.trim() !== "") {
      const value = raw.trim();
      if (!isSafeRelativePath(value)) {
        throw new Error(`"devbot_dir" must be a relative path without "..", got "${value}"`);
      }
      return value;
    }
  }
  return fallback;
}

/** Read the managed-project list from the global devbot config. */
export function parseManagedProjects(globalConfig: unknown, source = "global config"): ManagedProject[] {
  if (globalConfig === null || typeof globalConfig !== "object" || Array.isArray(globalConfig)) {
    throw new Error(`${source}: must be a JSON object`);
  }
  const raw = (globalConfig as Record<string, unknown>).projects;
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) {
    throw new Error(`${source}: "projects" must be an array of paths`);
  }
  const defaultDevbotDir = readDevbotDir(globalConfig, DEFAULT_DEVBOT_DIR);
  return raw.map((item, index) => {
    if (typeof item !== "string" || item.trim() === "") {
      throw new Error(`${source}: projects[${index}] must be a non-empty path string`);
    }
    const path = item.trim().replace(/\/+$/, "");
    return { name: path.split("/").pop() ?? path, path, devbotDir: defaultDevbotDir };
  });
}

/**
 * Walk the managed projects and keep those whose `autobot` block is active.
 *
 * `readProjectConfig` returns the parsed project config, or `null` when the project has none.
 */
export function collectOptedInProjects(
  globalConfig: unknown,
  readProjectConfig: (projectPath: string) => unknown | null,
  source = "global config",
  onError?: (message: string) => void,
): AutobotProject[] {
  const profiles = parseAutobotProfiles(globalConfig, source);
  const projects: AutobotProject[] = [];
  for (const project of parseManagedProjects(globalConfig, source)) {
    try {
      const raw = readProjectConfig(project.path);
      if (raw === null) continue;
      const config = parseAutobotConfig(raw, `${project.path}/.devbot.project.jsonc`, profiles);
      if (config === null || !isAutobotActive(config)) continue;
      projects.push({ ...project, devbotDir: readDevbotDir(raw, project.devbotDir), config });
    } catch (error) {
      // One unreadable project must not stop the others from ticking.
      onError?.(`${project.path}: ${(error as Error).message}`);
    }
  }

  // The name is persisted in the ticket state and resolved back to a path. Two checkouts sharing a
  // basename would route a continuation to whichever registered first.
  const seen = new Set<string>();
  for (const project of projects) {
    if (seen.has(project.name)) {
      throw new Error(
        `duplicate project name "${project.name}": rename one checkout or remove it from projects`,
      );
    }
    seen.add(project.name);
  }
  return projects;
}

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
  return { pollJira: false, pollGithub: false, prompts: [] };
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
export function parseAutobotConfig(config: unknown, source: string): AutobotConfig | null {
  if (config === null || typeof config !== "object" || Array.isArray(config)) {
    throw new Error(`${source}: project config must be a JSON object`);
  }
  const raw = (config as Record<string, unknown>).autobot;
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error(`${source}: "autobot" must be an object`);
  }
  const block = raw as Record<string, unknown>;
  return {
    pollJira: readFlag(block.poll_jira, "poll_jira", source),
    pollGithub: readFlag(block.poll_github, "poll_github", source),
    prompts: readPrompts(block.prompts, source),
  };
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
  const projects: AutobotProject[] = [];
  for (const project of parseManagedProjects(globalConfig, source)) {
    try {
      const raw = readProjectConfig(project.path);
      if (raw === null) continue;
      const config = parseAutobotConfig(raw, `${project.path}/.devbot.project.jsonc`);
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

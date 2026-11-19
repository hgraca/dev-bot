/**
 * The host a project runs, and the three things that differ between the hosts.
 *
 * AutoBot drives an OpenCode CLI end to end: it starts a run, reads the session id out of the run's
 * JSON stream, lists sessions for cleanup and deletes them — and the vacuum after those deletions is
 * v1-only. The run's *prompt* is built from the AutoBot command's body rather than from a slash-command
 * id, because 2.x does not dispatch one from a run message (`command-body.ts`); the id is not a host
 * property here, so nothing in this module spells one.
 */

import { existsSync } from "node:fs";
import { join } from "node:path";

export type Harness = "opencode" | "opencode-v2" | "claudecode";

/** What a project runs when neither config names a harness. */
export const DEFAULT_HARNESS: Harness = "opencode";

export function isHarness(value: string): value is Harness {
    return (
        value === "opencode" ||
        value === "opencode-v2" ||
        value === "claudecode"
    );
}

/**
 * The raw `harness` value a config states, or null when it states none.
 *
 * The value is returned as written — not trimmed, not string-only — because the launcher matches it
 * exactly: `" opencode-v2 "` and `7` are stated values it rejects, while `null` and `""` fall through
 * to the next config (verified against `resolve_project.py --setting`).
 */
function readRawHarness(config: unknown): string | null {
    if (config === null || typeof config !== "object" || Array.isArray(config))
        return null;
    const raw = (config as Record<string, unknown>).harness;
    if (raw === null || raw === undefined) return null;
    const text = typeof raw === "string" ? raw : String(raw);
    return text === "" ? null : text;
}

/**
 * The project's harness: its own config first, then the global one, then v1 — the order and the
 * invalid-value rule `_devbot_get_harness` uses. A project that states a value it does not recognise
 * gets v1 rather than the global harness: the launcher would do the same, and the two must not
 * disagree about which host a project runs.
 */
export function harnessFor(
    projectConfig: unknown,
    globalConfig: unknown,
): Harness {
    const stated =
        readRawHarness(projectConfig) ?? readRawHarness(globalConfig);
    return stated !== null && isHarness(stated) ? stated : DEFAULT_HARNESS;
}

/** Runs a command and returns its stdout, or null when it cannot run. Injected by tests. */
export type BinaryProbe = (command: string, args: string[]) => string | null;

export interface ResolveAgentBinaryOptions {
    /** Defaults to `$HOME`. */
    home?: string;
    probe?: BinaryProbe;
}

function probeBinary(command: string, args: string[]): string | null {
    try {
        const result = Bun.spawnSync([command, ...args], {
            stdin: "ignore",
            stdout: "pipe",
            stderr: "ignore",
        });
        return result.stdout?.toString() ?? null;
    } catch {
        return null;
    }
}

/**
 * The major version a binary reports: `1.18.35` and `opencode v2.3.0` both parse, so the two lines
 * cannot be confused for each other.
 */
export function opencodeMajor(output: string): number | null {
    const match = /(\d+)\.\d+/.exec(output);
    return match ? Number(match[1]) : null;
}

/** Quote a path for a POSIX shell single-argument literal. */
function shellQuote(value: string): string {
    return `'${value.replaceAll("'", `'\\''`)}'`;
}

/**
 * The executable an agent run is spawned as.
 *
 * The harness owns this resolution, not AutoBot: a 2.x install may be plain `opencode` on PATH, a
 * sibling `opencode2`, or either of two install paths, and `OPENCODE2_BIN` overrides all of it. Asking
 * the harness's own `_devbot_opencode2_bin` keeps one answer to that question; the literal name is only
 * the fallback for a broken install.
 *
 * `claudecode` throws: AutoBot's whole run path — `run --format json`, `session list`,
 * `session delete` — is OpenCode's CLI. Failing here names the reason instead of silently spawning a
 * host the project does not run.
 */
export function resolveAgentBinary(
    harness: Harness,
    root: string,
    options: ResolveAgentBinaryOptions = {},
): string {
    const home = options.home ?? process.env.HOME ?? "";
    const probe = options.probe ?? probeBinary;

    if (harness === "claudecode") {
        throw new Error(
            "AutoBot drives the OpenCode CLI; this project runs claudecode",
        );
    }

    if (harness === "opencode") {
        // v1's start.sh launches this exact path, PATH is only the fallback — but either may be a 2.x
        // install (the v2 harness accepts the plain `opencode` spelling), and running 2.x for a v1
        // project is the silent-wrong-host bug this module exists to stop. Its `--version` decides,
        // with the launcher's `_devbot_require_opencode_1x` rule: only the 2.x line is refused, so a
        // source build (`0.0.0--<sha>`) and an unreadable version both pass, as they do there.
        const installed = join(home, ".opencode", "bin", "opencode");
        const candidate = existsSync(installed) ? installed : "opencode";
        const version = probe(candidate, ["--version"]);
        if (version === null) {
            throw new Error(
                `no OpenCode binary for the opencode harness: ${candidate} cannot be run`,
            );
        }
        // `-ge 2`, not `=== 2`: the launcher refuses every major above 1, so a future 3.x must not
        // slip through as a v1 host either.
        const major = opencodeMajor(version);
        if (major !== null && major >= 2) {
            throw new Error(
                `no OpenCode 1.x binary for the opencode harness: ${candidate} reports ${version.trim()}`,
            );
        }
        return candidate;
    }

    const resolver = join(
        root,
        "src",
        "harnesses",
        "opencode-v2",
        "functions.sh",
    );
    if (existsSync(resolver)) {
        const output = probe("bash", [
            "-c",
            `source ${shellQuote(resolver)} >/dev/null 2>&1; _devbot_opencode2_bin`,
        ]);
        const resolved = (output ?? "").trim();
        if (resolved !== "") return resolved;
    }
    return "opencode2";
}

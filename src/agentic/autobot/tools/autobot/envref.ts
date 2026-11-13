/**
 * Environment references in the autobot config.
 *
 * Two spellings appear in this repository: `{env:VAR}` is the canonical devbot form, and `${VAR}` is
 * what Claude Code expands in its own `.mcp.json`. Both are accepted so an operator can write either.
 *
 * Only a whole-value reference is resolved. Interpolating inside a longer string would make a typo
 * silently produce a broken URL instead of a loud error.
 */

export type EnvLike = Record<string, string | undefined>;

const BRACED = /^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/;
const DOLLAR = /^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$/;

/** The variable name when the value is an environment reference, otherwise null. */
export function envReference(value: string): string | null {
    const match = BRACED.exec(value) ?? DOLLAR.exec(value);
    return match ? match[1]! : null;
}

/** Resolve a value that may be an environment reference. Throws when the variable is unset. */
export function resolveEnvReference(
    value: string,
    env: EnvLike = process.env,
): string {
    const name = envReference(value);
    if (name === null) return value;
    const resolved = env[name];
    if (resolved === undefined || resolved === "") {
        throw new Error(
            `autobot: environment variable ${name} is referenced but not set`,
        );
    }
    return resolved;
}

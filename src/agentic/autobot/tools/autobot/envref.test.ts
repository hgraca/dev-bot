import { describe, expect, test } from "bun:test";

import { envReference, resolveEnvReference } from "./envref.ts";

describe("envReference", () => {
    test("recognises the canonical braced form", () => {
        expect(envReference("{env:JIRA_API_TOKEN}")).toBe("JIRA_API_TOKEN");
    });

    test("recognises the dollar form", () => {
        expect(envReference("${JIRA_API_TOKEN}")).toBe("JIRA_API_TOKEN");
    });

    test("ignores a literal value", () => {
        expect(envReference("https://getinfo.atlassian.net")).toBeNull();
    });

    test("ignores an embedded reference", () => {
        expect(envReference("prefix-${JIRA_API_TOKEN}")).toBeNull();
    });
});

describe("resolveEnvReference", () => {
    test("returns a literal unchanged", () => {
        expect(resolveEnvReference("https://x", {})).toBe("https://x");
    });

    test("resolves either spelling", () => {
        const env = { JIRA_API_TOKEN: "secret" };
        expect(resolveEnvReference("${JIRA_API_TOKEN}", env)).toBe("secret");
        expect(resolveEnvReference("{env:JIRA_API_TOKEN}", env)).toBe("secret");
    });

    test("throws when the variable is unset", () => {
        expect(() => resolveEnvReference("${NOPE}", {})).toThrow(
            /NOPE is referenced but not set/,
        );
    });

    test("throws when the variable is empty", () => {
        expect(() => resolveEnvReference("${NOPE}", { NOPE: "" })).toThrow(
            /not set/,
        );
    });
});

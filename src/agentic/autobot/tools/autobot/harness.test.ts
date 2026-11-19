import { describe, expect, test } from "bun:test";

import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
    DEFAULT_HARNESS,
    harnessFor,
    isHarness,
    resolveAgentBinary,
} from "./harness.ts";

describe("harnessFor", () => {
    test("defaults to v1 when neither config names a harness", () => {
        expect(harnessFor({}, {})).toBe(DEFAULT_HARNESS);
        expect(harnessFor(null, null)).toBe("opencode");
    });

    test("reads the project config first", () => {
        expect(harnessFor({ harness: "opencode-v2" }, {})).toBe("opencode-v2");
    });

    test("falls back to the global config", () => {
        expect(harnessFor({}, { harness: "opencode-v2" })).toBe("opencode-v2");
    });

    test("the project config wins over the global one", () => {
        expect(
            harnessFor({ harness: "opencode" }, { harness: "opencode-v2" }),
        ).toBe("opencode");
    });

    // Same rule as `_devbot_get_harness`: a project that states a value it does not recognise gets
    // v1, not the global harness — the launcher must not disagree with this decision.
    test("an unrecognised project value gets v1, not the global harness", () => {
        for (const value of [
            "neovim",
            "opencode-2",
            " opencode-v2 ",
            7,
            true,
        ]) {
            expect(
                harnessFor({ harness: value }, { harness: "opencode-v2" }),
            ).toBe("opencode");
        }
    });

    test("null and empty values fall through, as the launcher does", () => {
        expect(harnessFor({ harness: null }, { harness: "opencode-v2" })).toBe(
            "opencode-v2",
        );
        expect(harnessFor({ harness: "" }, { harness: "opencode-v2" })).toBe(
            "opencode-v2",
        );
    });

    test("an unrecognised global value gets v1", () => {
        expect(harnessFor({}, { harness: "neovim" })).toBe(DEFAULT_HARNESS);
        expect(harnessFor({ harness: 7 }, {})).toBe(DEFAULT_HARNESS);
    });

    test("isHarness accepts only the three we drive", () => {
        expect(isHarness("opencode")).toBe(true);
        expect(isHarness("opencode-v2")).toBe(true);
        expect(isHarness("claudecode")).toBe(true);
        expect(isHarness("opencode-1")).toBe(false);
    });
});

describe("resolveAgentBinary", () => {
    const sandbox = () => mkdtempSync(join(tmpdir(), "autobot-harness-"));

    test("v1 launches the path its start.sh launches", () => {
        const home = sandbox();
        mkdirSync(join(home, ".opencode", "bin"), { recursive: true });
        writeFileSync(join(home, ".opencode", "bin", "opencode"), "");

        expect(
            resolveAgentBinary("opencode", "/root", {
                home,
                probe: () => "1.18.35\n",
            }),
        ).toBe(join(home, ".opencode", "bin", "opencode"));
    });

    // The installer path is not trusted for existing alone — start.sh version-checks it too.
    test("v1 refuses an installed path that reports 2.x", () => {
        const home = sandbox();
        mkdirSync(join(home, ".opencode", "bin"), { recursive: true });
        writeFileSync(join(home, ".opencode", "bin", "opencode"), "");

        expect(() =>
            resolveAgentBinary("opencode", "/root", {
                home,
                probe: () => "opencode v2.3.0\n",
            }),
        ).toThrow(/1\.x/);
    });

    test("v1 accepts a PATH opencode that reports 1.x", () => {
        expect(
            resolveAgentBinary("opencode", "/root", {
                home: sandbox(),
                probe: () => "1.18.35\n",
            }),
        ).toBe("opencode");
    });

    // A PATH `opencode` may be the 2.x install; running it for a v1 project is the bug this prevents.
    test("v1 refuses a PATH opencode that reports 2.x", () => {
        expect(() =>
            resolveAgentBinary("opencode", "/root", {
                home: sandbox(),
                probe: () => "opencode v2.3.0\n",
            }),
        ).toThrow(/1\.x/);
    });

    test("v1 refuses a future major too, not just 2.x", () => {
        for (const printed of ["opencode v3.0.1\n", "10.2.0\n"]) {
            expect(() =>
                resolveAgentBinary("opencode", "/root", {
                    home: sandbox(),
                    probe: () => printed,
                }),
            ).toThrow(/1\.x/);
        }
    });

    // The launcher fails open on a version it cannot read, and refuses every major above 1.
    test("v1 accepts a source build and an unreadable version", () => {
        for (const printed of ["0.0.0--abc123\n", ""]) {
            expect(
                resolveAgentBinary("opencode", "/root", {
                    home: sandbox(),
                    probe: () => printed,
                }),
            ).toBe("opencode");
        }
    });

    test("v1 fails when no binary can be run at all", () => {
        expect(() =>
            resolveAgentBinary("opencode", "/root", {
                home: sandbox(),
                probe: () => null,
            }),
        ).toThrow(/cannot be run/);
    });

    test("v2 asks the harness's own resolver", () => {
        const root = sandbox();
        const home = sandbox();
        mkdirSync(join(root, "src", "harnesses", "opencode-v2"), {
            recursive: true,
        });
        writeFileSync(
            join(root, "src", "harnesses", "opencode-v2", "functions.sh"),
            "",
        );

        let script = "";
        const probe = (command: string, args: string[]) => {
            expect(command).toBe("bash");
            script = args[1] ?? "";
            return `${home}/.opencode/v2/opencode\n`;
        };

        expect(resolveAgentBinary("opencode-v2", root, { home, probe })).toBe(
            join(home, ".opencode", "v2", "opencode"),
        );
        // The shared resolver is what gets asked — not a reimplementation.
        expect(script).toContain("_devbot_opencode2_bin");
        expect(script).toContain("functions.sh");
    });

    test("v2 falls back to the shim name when nothing resolves", () => {
        const root = sandbox();
        expect(
            resolveAgentBinary("opencode-v2", root, {
                home: sandbox(),
                probe: () => "",
            }),
        ).toBe("opencode2");
    });

    test("claudecode fails with the reason, never spawns a host it does not run", () => {
        expect(() => resolveAgentBinary("claudecode", "/root")).toThrow(
            /claudecode/,
        );
    });
});

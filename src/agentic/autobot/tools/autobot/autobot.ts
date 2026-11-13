#!/usr/bin/env bun
/**
 * devbot autobot — scheduled agent work for the projects a devbot harness is running in.
 *
 * `tick` is one locked pass of Slack replies, follow-ups and due prompts; `cleanup` reclaims sessions;
 * `say` is the agent's own way to talk to the user from inside a run.
 */

import { runCleanupCommand, runSayCommand, runTickCommand } from "./cli.ts";

async function main(argv: string[]): Promise<number> {
    const [command] = argv;
    if (command === "tick") {
        const report = await runTickCommand();
        console.log(JSON.stringify(report, null, 2));
        return 0;
    }
    if (command === "cleanup") {
        const report = await runCleanupCommand();
        console.log(JSON.stringify(report, null, 2));
        return 0;
    }
    if (command === "say") {
        const result = await runSayCommand(argv.slice(1));
        console.log(JSON.stringify(result, null, 2));
        return 0;
    }
    console.error("usage: autobot <tick|cleanup|say>");
    return 2;
}

try {
    process.exit(await main(process.argv.slice(2)));
} catch (error) {
    console.error(`FATAL: ${(error as Error).message}`);
    process.exit(1);
}

#!/usr/bin/env bun
/**
 * devbot autobot — scheduled agent work for the projects a devbot harness is running in.
 *
 * The only command today is `tick`: one pass of follow-ups and due prompts, locked so two cron
 * invocations cannot overlap.
 */

import { runCleanupCommand, runTickCommand } from "./cli.ts";

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
  console.error("usage: autobot <tick|cleanup>");
  return 2;
}

try {
  process.exit(await main(process.argv.slice(2)));
} catch (error) {
  console.error(`FATAL: ${(error as Error).message}`);
  process.exit(1);
}

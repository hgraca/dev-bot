// Unit tests for the herdr reporter. The timeout case runs a real child so it
// proves the bound rather than a mock's cooperation.

import { describe, test, expect } from "bun:test"
import { herdrReportPlan, herdrRun, inHerdrPane, reportToHerdr } from "./herdr-report"

const ENV = { HERDR_ENV: "1", HERDR_PANE_ID: "w1:p1", HERDR_BIN_PATH: "/opt/herdr" }

describe("inHerdrPane", () => {
  test("true only with a pane id behind HERDR_ENV", () => {
    expect(inHerdrPane(ENV)).toBe(true)
    expect(inHerdrPane({ ...ENV, HERDR_ENV: undefined })).toBe(false)
    expect(inHerdrPane({ ...ENV, HERDR_PANE_ID: undefined })).toBe(false)
  })
})

describe("herdrReportPlan", () => {
  test("reports the marker as a devbot pane token", () => {
    expect(herdrReportPlan("BLOCKED", ENV)).toEqual({
      command: "/opt/herdr",
      args: ["pane", "report-metadata", "w1:p1", "--source", "devbot", "--token", "devbot=BLOCKED"],
    })
  })

  test("clears the token when no marker was published", () => {
    expect(herdrReportPlan(undefined, ENV)?.args).toContain("devbot=")
  })

  test("falls back to herdr on PATH when no binary path is exported", () => {
    const { HERDR_BIN_PATH, ...withoutBin } = ENV
    expect(herdrReportPlan("FINISHED", withoutBin)?.command).toBe("herdr")
  })

  test("plans nothing outside a herdr pane", () => {
    expect(herdrReportPlan("FINISHED", { ...ENV, HERDR_ENV: undefined })).toBeUndefined()
    expect(herdrReportPlan("FINISHED", { ...ENV, HERDR_PANE_ID: undefined })).toBeUndefined()
  })

  test("never takes lifecycle authority: no report-agent, no release", () => {
    const args = herdrReportPlan("IDLE", ENV)?.args ?? []
    expect(args).not.toContain("report-agent")
    expect(args).not.toContain("release-agent")
  })
})

describe("herdrRun", () => {
  test("resolves false when the command outlives the timeout", async () => {
    const ran = await herdrRun(50)("bash", ["-c", "sleep 5"])
    expect(ran).toBe(false)
  })

  test("resolves true for a command that exits cleanly", async () => {
    const ran = await herdrRun()("bash", ["-c", "true"])
    expect(ran).toBe(true)
  })
})

describe("reportToHerdr", () => {
  test("runs the planned command", async () => {
    const seen: string[][] = []
    const ran = await reportToHerdr(herdrReportPlan("PARTIAL", ENV), (cmd, args) => {
      seen.push([cmd, ...args])
      return true
    })
    expect(ran).toBe(true)
    expect(seen).toEqual([
      ["/opt/herdr", "pane", "report-metadata", "w1:p1", "--source", "devbot", "--token", "devbot=PARTIAL"],
    ])
  })

  test("swallows a failing herdr instead of failing the turn", async () => {
    const boom = () => {
      throw new Error("herdr is gone")
    }
    await expect(reportToHerdr(herdrReportPlan("PARTIAL", ENV), boom)).resolves.toBe(false)
  })

  test("does nothing when there is no plan", async () => {
    let called = false
    const ran = await reportToHerdr(undefined, () => {
      called = true
      return true
    })
    expect(ran).toBe(false)
    expect(called).toBe(false)
  })
})

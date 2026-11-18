// Resolution rules for a skill name against the ids
// a 2.x host has registered.

import { describe, expect, test } from "bun:test"
import { resolveSkillId, resolveSkillInput } from "./skill-name-resolver-utils"

const registered = (id: string, name: string) => ({ id, name })

describe("resolveSkillId", () => {
  test("leaves an id the host already registers", () => {
    const skills = [
      registered("reconcile-work", "devbot:reconcile-work"),
      registered("devbot:reconcile-work", "devbot:reconcile-work"),
    ]

    expect(resolveSkillId("reconcile-work", skills)).toBeNull()
    expect(resolveSkillId("devbot:reconcile-work", skills)).toBeNull()
  })

  test("maps a display name to the bare id", () => {
    expect(resolveSkillId("devbot:reconcile-work", [registered("reconcile-work", "devbot:reconcile-work")])).toBe(
      "reconcile-work",
    )
  })

  test("maps a display name to whichever id the host registered", () => {
    expect(resolveSkillId("devbot:reconcile-work", [registered("fleet:reconcile-work", "devbot:reconcile-work")])).toBe(
      "fleet:reconcile-work",
    )
  })

  test("prefers the bare id when a skill is registered twice", () => {
    const skills = [registered("devbot:alpha", "devbot:reconcile-work"), registered("alpha", "devbot:reconcile-work")]

    expect(resolveSkillId("devbot:reconcile-work", skills)).toBe("alpha")
  })

  test("maps a namespaced request to a bare id when the name is unrelated", () => {
    expect(resolveSkillId("devbot:reconcile-work", [registered("reconcile-work", "reconcile-work")])).toBe(
      "reconcile-work",
    )
  })

  test("maps a bare request to a namespaced registration", () => {
    expect(resolveSkillId("reconcile-work", [registered("devbot:reconcile-work", "devbot:reconcile-work")])).toBe(
      "devbot:reconcile-work",
    )
  })

  test("does not guess between two registrations of the same skill", () => {
    const skills = [
      registered("alpha:reconcile-work", "alpha:reconcile-work"),
      registered("beta:reconcile-work", "beta:reconcile-work"),
    ]

    expect(resolveSkillId("reconcile-work", skills)).toBeNull()
  })

  test("does not guess between two namespaced ids sharing a display name", () => {
    const skills = [registered("alpha:x", "devbot:reconcile-work"), registered("beta:x", "devbot:reconcile-work")]

    expect(resolveSkillId("devbot:reconcile-work", skills)).toBeNull()
  })

  test("resolves a registration the host lists twice", () => {
    const twice = [
      registered("devbot:alpha", "devbot:reconcile-work"),
      registered("devbot:alpha", "devbot:reconcile-work"),
    ]

    expect(resolveSkillId("devbot:reconcile-work", twice)).toBe("devbot:alpha")
    expect(resolveSkillId("alpha", [registered("devbot:alpha", "A"), registered("devbot:alpha", "A")])).toBe(
      "devbot:alpha",
    )
  })

  test("matches a display name regardless of case", () => {
    expect(resolveSkillId("DevBot:Reconcile-Work", [registered("reconcile-work", "devbot:reconcile-work")])).toBe(
      "reconcile-work",
    )
  })

  test("matches a namespaced id regardless of case", () => {
    expect(resolveSkillId("DevBot:Reconcile-Work", [registered("devbot:reconcile-work", "Other Skill")])).toBe(
      "devbot:reconcile-work",
    )
  })

  test("matches a bare id segment regardless of case", () => {
    expect(resolveSkillId("Reconcile-Work", [registered("devbot:reconcile-work", "Other Skill")])).toBe(
      "devbot:reconcile-work",
    )
  })

  test("ignores surrounding whitespace", () => {
    expect(resolveSkillId("  devbot:reconcile-work\n", [registered("reconcile-work", "devbot:reconcile-work")])).toBe(
      "reconcile-work",
    )
  })

  test("leaves an unknown name alone so the host reports it", () => {
    expect(resolveSkillId("devbot:not-a-skill", [registered("reconcile-work", "devbot:reconcile-work")])).toBeNull()
  })

  test("is a no-op without a request or without skills", () => {
    expect(resolveSkillId("", [registered("reconcile-work", "devbot:reconcile-work")])).toBeNull()
    expect(resolveSkillId("devbot:reconcile-work", [])).toBeNull()
  })
})

const listing = { data: [registered("reconcile-work", "devbot:reconcile-work")] }

describe("resolveSkillInput", () => {
  test("rewrites the input id in place", async () => {
    const input = { id: "devbot:reconcile-work" }

    await resolveSkillInput(input, { list: async () => listing })

    expect(input.id).toBe("reconcile-work")
  })

  test("trims the id the host registers", async () => {
    const input = { id: "  reconcile-work  " }

    await resolveSkillInput(input, { list: async () => listing })

    expect(input.id).toBe("reconcile-work")
  })

  test("leaves an id the host registers untouched", async () => {
    const input = { id: "reconcile-work" }

    await resolveSkillInput(input, { list: async () => listing })

    expect(input.id).toBe("reconcile-work")
  })

  test("returns before listing when there is no string id", async () => {
    let listed = false
    const list = async () => {
      listed = true
      return listing
    }

    await resolveSkillInput({}, { list })
    await resolveSkillInput({ id: 7 }, { list })
    await resolveSkillInput(null, { list })

    expect(listed).toBe(false)
  })

  test("fails open when the skill list cannot be read", async () => {
    const input = { id: "devbot:reconcile-work" }
    const warnings: string[] = []
    const list = async (): Promise<{ data?: readonly unknown[] }> => {
      throw new Error("service unavailable")
    }

    await resolveSkillInput(input, { list, log: { info() {}, warn: (msg) => warnings.push(msg) } })

    expect(input.id).toBe("devbot:reconcile-work")
    expect(warnings).toEqual(["skill name not resolved: service unavailable"])
  })

  test("fails open on a malformed payload", async () => {
    const input = { id: "devbot:reconcile-work" }

    await resolveSkillInput(input, { list: async () => ({ data: [null, { id: 1 }, "x"] }) })

    expect(input.id).toBe("devbot:reconcile-work")
  })
})

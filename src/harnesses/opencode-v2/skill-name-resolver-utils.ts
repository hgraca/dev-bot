// Maps a skill display name to the id a 2.x host
// resolves; the frontmatter name is display-only.

export interface SkillRef {
  id: string
  name: string
}

// devbot:x -> x; ids may carry namespaces.
function bareId(id: string): string {
  const at = id.lastIndexOf(":")
  return at === -1 ? id : id.slice(at + 1)
}

// One skill, two ids: bare and namespaced. A bare
// id wins; two namespaced ids cannot be told apart.
function oneOf(skills: readonly SkillRef[]): string | null {
  const ids = [...new Set(skills.map((skill) => skill.id))]
  if (ids.length === 1) return ids[0]
  return ids.find((id) => !id.includes(":")) ?? null
}

// The id to load, or null when the request should
// be left exactly as asked.
export function resolveSkillId(requested: string, skills: readonly SkillRef[]): string | null {
  const want = requested.trim()
  if (!want || skills.length === 0) return null
  if (skills.some((skill) => skill.id === want)) return want === requested ? null : want

  const byName = skills.filter((skill) => skill.name === want)
  if (byName.length > 0) return oneOf(byName)

  const bare = bareId(want)
  if (bare !== want) {
    const byBareId = skills.filter((skill) => skill.id === bare)
    if (byBareId.length > 0) return oneOf(byBareId)
  }

  const folded = want.toLowerCase()
  const byNameIgnoringCase = skills.filter((skill) => skill.name.toLowerCase() === folded)
  if (byNameIgnoringCase.length > 0) return oneOf(byNameIgnoringCase)

  const byIdIgnoringCase = skills.filter((skill) => skill.id.toLowerCase() === folded)
  if (byIdIgnoringCase.length > 0) return oneOf(byIdIgnoringCase)

  // A bare request may target a namespaced id.
  const bySegment = skills.filter((skill) => bareId(skill.id).toLowerCase() === folded)
  if (bySegment.length > 0) return oneOf(bySegment)

  return null
}

export interface SkillHookDeps {
  list: () => Promise<{ data?: readonly unknown[] } | undefined>
  log?: { info(msg: string): void; warn(msg: string): void }
}

// Fails open: a thrown before-hook blocks the call,
// so every failure leaves the request untouched.
export async function resolveSkillInput(input: unknown, deps: SkillHookDeps): Promise<void> {
  try {
    const target = input as { id?: unknown } | null
    const requested = typeof target?.id === "string" ? target.id : ""
    if (!requested) return

    const listed = await deps.list()
    const data = Array.isArray(listed?.data) ? listed.data : []
    const skills = data.filter(
      (skill: any) => typeof skill?.id === "string" && typeof skill?.name === "string",
    ) as readonly SkillRef[]

    const id = resolveSkillId(requested, skills)
    if (!id || id === requested) return
    target!.id = id
    deps.log?.info(`skill '${requested}' resolved to id '${id}'`)
  } catch (e) {
    deps.log?.warn(`skill name not resolved: ${e instanceof Error ? e.message : String(e)}`)
  }
}

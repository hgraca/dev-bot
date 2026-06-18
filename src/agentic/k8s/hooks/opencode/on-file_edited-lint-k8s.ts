import type { Plugin } from "@opencode-ai/plugin"
import { readFileSync, existsSync } from "fs"
import { createLogger } from "../../../_shared/logger.ts"

const logger = createLogger({ module: "k8s" })

const K8S_MARKER_1 = "apiVersion:"
const K8S_MARKER_2 = "kind:"

function findBinary(name: string): string | null {
  const paths = [
    `${process.env.HOME}/.local/bin/${name}`,
    `/usr/local/bin/${name}`,
    `/usr/bin/${name}`,
  ]
  for (const p of paths) {
    if (existsSync(p)) return p
  }
  return null
}

function isK8sManifest(filePath: string): boolean {
  try {
    const head = readFileSync(filePath, "utf-8").slice(0, 4096)
    return head.includes(K8S_MARKER_1) && head.includes(K8S_MARKER_2)
  } catch {
    return false
  }
}

async function lintFile(
  filePath: string,
  kubeconformBin: string,
  kubelinterBin: string,
  $: any,
): Promise<void> {
  const results: string[] = []

  // ── kubeconform ──
  try {
    const kc = await $`${kubeconformBin} -summary ${filePath}`.quiet()
    const out = kc.stdout?.toString().trim() || ""
    if (out) results.push(`kubeconform:\n${out}`)
  } catch (e: any) {
    const out = e.stdout?.toString().trim() || e.stderr?.toString().trim() || e.message
    if (out) results.push(`kubeconform FAIL:\n${out}`)
  }

  // ── kube-linter ──
  try {
    const kl = await $`${kubelinterBin} lint ${filePath}`.quiet()
    const out = kl.stdout?.toString().trim() || ""
    if (out) results.push(`kube-linter:\n${out}`)
  } catch (e: any) {
    const out = e.stdout?.toString().trim() || e.stderr?.toString().trim() || e.message
    if (out) results.push(`kube-linter WARN:\n${out}`)
  }

  if (results.length > 0) {
    logger.info(`lint-k8s: ${filePath}\n${results.join("\n\n")}`)
  }
}

export const OnFileEditedLintK8s: Plugin = async ({ project, $ }) => {
  const kubeconformBin = findBinary("kubeconform")
  const kubelinterBin = findBinary("kube-linter")

  if (!kubeconformBin || !kubelinterBin) {
    logger.info("lint-k8s hook: kubeconform or kube-linter not found — skipping")
    return {}
  }

  return {
    event: async ({ event }) => {
      if (event.type !== "file.edited") return
      const file: string = (event as any).properties?.file ?? ""
      if (!/\.(ya?ml)$/i.test(file)) return
      if (!isK8sManifest(file)) return

      logger.info(`lint-k8s hook triggered: ${file}`)
      await lintFile(file, kubeconformBin, kubelinterBin, $)
    },
  }
}

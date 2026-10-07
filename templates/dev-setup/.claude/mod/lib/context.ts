// context.ts — how full the context is, and how much of it dev-setup brings.
//
// The total is the session's own figure (the status line's). The split by
// category is Claude Code's breakdown — estimated by Claude Code, against the
// compaction window — and the dev-setup share is read from its named items:
// the rule files, the plugin's skills and agents, the MCP servers the setup
// wrote into the project's .mcp.json. Nothing here is inferred from disk.

import { formatTokens } from './usage.ts'

const CONTEXT_WARNING_PERCENT = 70

export type ContextFigures = {
  readonly tokens?: number
  readonly window: number
  readonly percent?: number
}

type Tokens = { readonly tokens: number }

export type BreakdownLike = {
  readonly categories?: readonly { readonly name: string; readonly tokens: number; readonly kind?: string }[]
  readonly memoryFiles?: readonly { readonly path: string; readonly tokens: number }[]
  readonly skills?: {
    readonly skillFrontmatter?: readonly { readonly name: string; readonly pluginName?: string; readonly tokens: number }[]
  }
  readonly agents?: readonly { readonly agentType: string; readonly tokens: number }[]
  readonly mcpTools?: readonly { readonly name: string; readonly serverName: string; readonly tokens: number }[]
}

export type ShareItem = { readonly label: string; readonly tokens: number }

const RULE_FILE = /(^|[\\/])\.claude[\\/]rules[\\/](dev-setup-[^\\/]+\.md)$/

function sumTokens(items: readonly Tokens[]): number {
  return items.reduce((sum, item) => sum + item.tokens, 0)
}

/** The server names of a project's .mcp.json; none when it is absent or unreadable. */
export function mcpServerNames(mcpJson: string): string[] {
  try {
    const parsed: unknown = JSON.parse(mcpJson)
    const servers =
      parsed && typeof parsed === 'object' ? (parsed as { mcpServers?: unknown }).mcpServers : undefined
    return servers && typeof servers === 'object' ? Object.keys(servers) : []
  } catch {
    return []
  }
}

export function devSetupShare(breakdown: BreakdownLike, mcpServers: readonly string[], plugin = 'dev-setup'): ShareItem[] {
  const items: ShareItem[] = []
  const add = (label: string, matched: readonly Tokens[]) => {
    if (matched.length > 0) items.push({ label, tokens: sumTokens(matched) })
  }
  const rules = (breakdown.memoryFiles ?? []).flatMap((file) => {
    const name = RULE_FILE.exec(file.path)?.[2]
    return name ? [{ name, tokens: file.tokens }] : []
  })
  add(`rules (${rules.map((rule) => rule.name).join(', ')})`, rules)
  const prefix = `${plugin}:`
  const skills = (breakdown.skills?.skillFrontmatter ?? []).filter(
    (skill) => skill.pluginName === plugin || skill.name.startsWith(prefix),
  )
  add(`skills (${skills.length})`, skills)
  const agents = (breakdown.agents ?? []).filter((agent) => agent.agentType.startsWith(prefix))
  add(`agents (${agents.length})`, agents)
  for (const server of mcpServers) {
    const tools = (breakdown.mcpTools ?? []).filter((tool) => tool.serverName === server)
    add(`MCP ${server} (${tools.length} tools)`, tools)
  }
  return items
}

export function contextLines(figures: ContextFigures, breakdown: BreakdownLike | undefined, share: readonly ShareItem[]): string[] {
  const used =
    figures.tokens === undefined
      ? 'no response measured yet'
      : `${formatTokens(figures.tokens)} of ${formatTokens(figures.window)} tokens (${figures.percent ?? Math.round((figures.tokens / figures.window) * 100)}%)`
  const lines = [`Context used: ${used}`]
  if (!breakdown || !breakdown.categories) {
    lines.push('Split by category: unavailable on this client — /context shows it.')
    return lines
  }
  lines.push("Split by category (Claude Code's estimate):")
  for (const category of breakdown.categories) {
    if (category.kind === 'free' || category.kind === 'buffer') continue
    lines.push(`  ${category.name.padEnd(24)} ${formatTokens(category.tokens)}`)
  }
  lines.push(`dev-setup share: ${formatTokens(sumTokens(share))}`)
  for (const item of share) lines.push(`  ${item.label.padEnd(24)} ${formatTokens(item.tokens)}`)
  if (share.length === 0) lines.push('  nothing from dev-setup is in the context yet')
  return lines
}

export function contextWarning(percent: number | undefined): string | null {
  if (percent === undefined || percent < CONTEXT_WARNING_PERCENT) return null
  return `context ${percent}% — a long phase may compact mid-flow · /dev-setup context`
}

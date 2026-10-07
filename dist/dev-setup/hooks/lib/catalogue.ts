// catalogue.ts — the plugin's public commands, read from their SKILL.md.
//
// One source: the frontmatter. A skill is listed when it says
// `user-invocable: true`, so adding or renaming a public skill changes the
// catalogue with no edit here. What it does and when to use it come from the
// description (its "Use when…" sentence is the routing rule), what it takes
// from `argument-hint`, and `disable-model-invocation: true` marks a command
// with outward-facing effects that only a person starts.

export type Frontmatter = Readonly<Record<string, string>>

export type CatalogueEntry = {
  readonly name: string
  readonly command: string
  readonly what: string
  readonly when: string
  readonly input: string
  readonly outward: boolean
}

function unquote(value: string): string {
  const trimmed = value.trim()
  if (trimmed.length >= 2) {
    const first = trimmed[0]
    if ((first === '"' || first === "'") && trimmed[trimmed.length - 1] === first) {
      return trimmed.slice(1, -1)
    }
  }
  return trimmed
}

/**
 * The top-level `key: value` pairs between the opening `---` lines. A folded or
 * literal block (`key: >` / `key: |`) is joined into one line; nested maps and
 * lists are skipped — no catalogue field uses them.
 */
export function parseFrontmatter(text: string): Frontmatter {
  const lines = text.split(/\r?\n/)
  if (lines[0]?.trim() !== '---') return {}
  const fields: Record<string, string> = {}
  let blockKey: string | null = null
  let block: string[] = []
  const closeBlock = () => {
    if (blockKey !== null) fields[blockKey] = block.join(' ').trim()
    blockKey = null
    block = []
  }
  for (const line of lines.slice(1)) {
    if (line.trim() === '---') break
    if (blockKey !== null && /^\s+\S/.test(line)) {
      block.push(line.trim())
      continue
    }
    closeBlock()
    const match = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line)
    if (!match) continue
    const [, key, value] = match
    if (value === '>' || value === '|' || value === '>-' || value === '|-') {
      blockKey = key
    } else {
      fields[key] = unquote(value)
    }
  }
  closeBlock()
  return fields
}

/** The description split at its "Use when…" sentence. */
export function splitDescription(description: string): { what: string; when: string } {
  const at = description.search(/\bUse when\b/)
  if (at < 0) return { what: description.trim(), when: '' }
  return { what: description.slice(0, at).trim(), when: description.slice(at).trim() }
}

/** One catalogue row, or null for a skill that is not user-invocable. */
export function toEntry(plugin: string, dirName: string, fields: Frontmatter): CatalogueEntry | null {
  if (fields['user-invocable'] !== 'true') return null
  const name = fields.name || dirName
  const { what, when } = splitDescription(fields.description ?? '')
  return {
    name,
    command: `/${plugin}:${name}`,
    what,
    when,
    input: fields['argument-hint'] || 'nothing',
    outward: fields['disable-model-invocation'] === 'true',
  }
}

export function sortEntries(entries: readonly CatalogueEntry[]): CatalogueEntry[] {
  return [...entries].sort((a, b) => a.name.localeCompare(b.name))
}

/** What the "use" button fills: the command and a space — the typeahead then
 * shows the argument hint, and nothing is a placeholder sent by mistake. */
export function useText(entry: CatalogueEntry): string {
  return `${entry.command} `
}

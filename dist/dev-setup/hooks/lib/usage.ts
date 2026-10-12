// usage.ts — what each phase of an `sdd` run cost, request by request.
//
// The phase is the skill last expanded: one `sdd` turn runs several sub-skills,
// so usage is attributed per model request (turn.step), never per turn. Tokens
// come from each request's own usage; cost exists only as the session total,
// so a phase is charged the growth of that total across its requests — exact
// in sum, approximate per phase when parallel subagents interleave.

import type { Row, Span } from './rows.ts'
import { bold, columns, dim, GAP, rowsText, rowText, span } from './rows.ts'

export const PHASES = ['intake', 'discovery', 'spec', 'plan', 'dev', 'closure'] as const
export type Phase = (typeof PHASES)[number]

/** The store key that indexes the saved records, newest last. */
export const USAGE_INDEX = 'usage:index'

const SKILL_PHASES: Readonly<Record<string, Phase>> = {
  sdd: 'intake',
  'sdd-discovery': 'discovery',
  'sdd-spec': 'spec',
  'sdd-plan': 'plan',
  'sdd-dev': 'dev',
  verify: 'closure',
  review: 'closure',
  'vcs-ops': 'closure',
  // Claude Code's own skill, which the closure runs over the staged change.
  simplify: 'closure',
}

/** The phase a skill opens: the plugin's own skills (with its prefix) and the
 * built-in `simplify`; null for anything else, which leaves the phase as it was. */
export function phaseOf(skill: string, plugin = 'dev-setup'): Phase | null {
  const prefix = `${plugin}:`
  if (skill.startsWith(prefix)) return SKILL_PHASES[skill.slice(prefix.length)] ?? null
  return skill === 'simplify' ? 'closure' : null
}

export type RequestUsage = {
  readonly input_tokens: number
  readonly output_tokens: number
  readonly cache_read_input_tokens: number
  readonly cache_creation_input_tokens: number
}

export type PhaseTotals = {
  readonly requests: number
  readonly input: number
  readonly output: number
  readonly cacheRead: number
  readonly cacheWrite: number
  readonly costUsd: number
}

export type UsageRecord = {
  readonly key: string
  readonly project: string
  readonly task: string
  readonly startedAt: number
  readonly phases: Readonly<Partial<Record<Phase, PhaseTotals>>>
}

const ZERO: PhaseTotals = { requests: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, costUsd: 0 }

function plus(a: PhaseTotals, b: PhaseTotals): PhaseTotals {
  return {
    requests: a.requests + b.requests,
    input: a.input + b.input,
    output: a.output + b.output,
    cacheRead: a.cacheRead + b.cacheRead,
    cacheWrite: a.cacheWrite + b.cacheWrite,
    costUsd: a.costUsd + b.costUsd,
  }
}

export function newRecord(key: string, project: string, startedAt: number): UsageRecord {
  return { key, project, task: '', startedAt, phases: {} }
}

export function addRequest(record: UsageRecord, phase: Phase, usage: RequestUsage | null, costDeltaUsd: number): UsageRecord {
  const request: PhaseTotals = {
    requests: 1,
    input: usage?.input_tokens ?? 0,
    output: usage?.output_tokens ?? 0,
    cacheRead: usage?.cache_read_input_tokens ?? 0,
    cacheWrite: usage?.cache_creation_input_tokens ?? 0,
    costUsd: Math.max(0, costDeltaUsd),
  }
  return { ...record, phases: { ...record.phases, [phase]: plus(record.phases[phase] ?? ZERO, request) } }
}

/** A stored value that is a usage record — the store is shared and outlives versions. */
export function isUsageRecord(value: unknown): value is UsageRecord {
  if (!value || typeof value !== 'object') return false
  const candidate = value as { key?: unknown; startedAt?: unknown; phases?: unknown }
  return typeof candidate.key === 'string' && typeof candidate.startedAt === 'number' && !!candidate.phases && typeof candidate.phases === 'object'
}

/** The stored index as a list of keys, whatever the store held. */
export function toIndex(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((key): key is string => typeof key === 'string') : []
}

export function withTask(record: UsageRecord, task: string): UsageRecord {
  return task && task !== record.task ? { ...record, task } : record
}

export function formatTokens(tokens: number): string {
  if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`
  if (tokens >= 1_000) return `${(tokens / 1_000).toFixed(1)}k`
  return String(tokens)
}

function formatUsd(usd: number): string {
  return `$${usd.toFixed(2)}`
}

function measured(record: UsageRecord): [Phase, PhaseTotals][] {
  return PHASES.flatMap((phase): [Phase, PhaseTotals][] => {
    const totals = record.phases[phase]
    return totals ? [[phase, totals]] : []
  })
}

/** The band's row: tokens per phase, the phase in progress in full strength,
 * then the cost of the run so far. */
export function compactRow(record: UsageRecord, current: Phase | null = null): Row {
  const rows = measured(record)
  if (rows.length === 0) return []
  const sum = rows.reduce((acc, [, t]) => plus(acc, t), ZERO)
  const row: Span[] = [dim(record.task ? `sdd ${record.task}` : 'sdd'), GAP]
  rows.forEach(([phase, t], i) => {
    if (i > 0) row.push(dim(' › '))
    const cell = `${phase} ${formatTokens(t.input + t.output + t.cacheRead + t.cacheWrite)}`
    row.push(phase === current ? bold(cell) : dim(cell))
  })
  row.push(GAP, bold(formatUsd(sum.costUsd)))
  return row
}

export function compactLine(record: UsageRecord, current: Phase | null = null): string {
  return rowText(compactRow(record, current))
}

export const NO_USAGE = 'No sdd phase measured yet.'

export const USAGE_NOTE = 'Cost per phase is the growth of the session total: exact in sum, approximate per phase when subagents overlap.'

/** The table `/dev-setup usage` reports: one row per measured phase, the
 * figures right-aligned, the total in bold. */
export function usageRows(record: UsageRecord, current: Phase | null = null): Row[] {
  const rows = measured(record)
  if (rows.length === 0) return [[dim(NO_USAGE)]]
  const cells = (label: Span, t: PhaseTotals, weight: (text: string) => Span) => [
    label,
    weight(String(t.requests)),
    weight(formatTokens(t.input)),
    weight(formatTokens(t.cacheRead)),
    weight(formatTokens(t.cacheWrite)),
    weight(formatTokens(t.output)),
    weight(formatUsd(t.costUsd)),
  ]
  const header = ['phase', 'requests', 'input', 'cache read', 'cache write', 'output', 'cost'].map(dim)
  const total = rows.reduce((acc, [, t]) => plus(acc, t), ZERO)
  const body = rows.map(([phase, t]) => (phase === current ? cells(bold(phase), t, bold) : cells(span(phase), t, span)))
  const table = columns([header, ...body, cells(bold('total'), total, bold)], ['left', 'right', 'right', 'right', 'right', 'right', 'right'])
  return [[bold(record.task ? `sdd usage — ${record.task}` : 'sdd usage')], ...table, [dim(USAGE_NOTE)]]
}

export function usageTable(record: UsageRecord, current: Phase | null = null): string[] {
  return rowsText(usageRows(record, current))
}

/** The index with a new key appended, capped: the store is 4 MiB shared by
 * every session on the machine. */
export function pruneIndex(index: readonly string[], key: string, max = 20): { index: string[]; dropped: string[] } {
  const next = [...index.filter((entry) => entry !== key), key]
  const cut = Math.max(0, next.length - max)
  return { index: next.slice(cut), dropped: next.slice(0, cut) }
}

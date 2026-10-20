// usage.ts — what each phase of an `sdd` run cost and how long it took.
//
// The phase is the skill last expanded: one `sdd` turn runs several sub-skills,
// so usage is attributed per model request (turn.step), never per turn. Tokens
// come from each request's own usage, split by the loop that made it (the main
// thread or a subagent) and by the model that answered; cost exists only as the
// session total, so a phase is charged the growth of that total across its
// requests — exact in sum, approximate per phase when parallel subagents
// interleave. Time is the wall clock from a phase's skill to the next one, and
// the part of it a main-thread turn was running: the rest is the developer's
// — reading a spec, answering discovery — not the model's.

import { formatDuration } from './clock.ts'
import type { Row, Span } from './rows.ts'
import { bold, columns, dim, GAP, INDENT, meter, rowsText, rowText, span } from './rows.ts'

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
  /** Which model answered; absent in a usage that does not say. */
  readonly model?: string
}

export type PhaseTotals = {
  readonly requests: number
  readonly input: number
  readonly output: number
  readonly cacheRead: number
  readonly cacheWrite: number
  readonly costUsd: number
  /** The requests a subagent made, and their tokens — the rest is the main thread's. */
  readonly subagentRequests: number
  readonly subagentTokens: number
  /** Wall time in the phase, and the part of it a main-thread turn was running. */
  readonly wallMs: number
  readonly workMs: number
}

export type UsageRecord = {
  readonly key: string
  readonly project: string
  readonly task: string
  readonly startedAt: number
  readonly phases: Readonly<Partial<Record<Phase, Partial<PhaseTotals>>>>
  /** Tokens by the model that answered; absent in a record saved before it was kept. */
  readonly models?: Readonly<Record<string, number>>
}

const ZERO: PhaseTotals = {
  requests: 0,
  input: 0,
  output: 0,
  cacheRead: 0,
  cacheWrite: 0,
  costUsd: 0,
  subagentRequests: 0,
  subagentTokens: 0,
  wallMs: 0,
  workMs: 0,
}

/** A phase's totals, every figure present: a record saved by an earlier
 * version has no time and no subagent split, which reads as zero. */
function totalsOf(totals: Partial<PhaseTotals> | undefined): PhaseTotals {
  return { ...ZERO, ...totals }
}

function plus(a: PhaseTotals, b: Partial<PhaseTotals>): PhaseTotals {
  const c = totalsOf(b)
  return {
    requests: a.requests + c.requests,
    input: a.input + c.input,
    output: a.output + c.output,
    cacheRead: a.cacheRead + c.cacheRead,
    cacheWrite: a.cacheWrite + c.cacheWrite,
    costUsd: a.costUsd + c.costUsd,
    subagentRequests: a.subagentRequests + c.subagentRequests,
    subagentTokens: a.subagentTokens + c.subagentTokens,
    wallMs: a.wallMs + c.wallMs,
    workMs: a.workMs + c.workMs,
  }
}

function withPhase(record: UsageRecord, phase: Phase, add: Partial<PhaseTotals>): UsageRecord {
  return { ...record, phases: { ...record.phases, [phase]: plus(totalsOf(record.phases[phase]), add) } }
}

/** Every token a set of totals counts: uncached input, cache read and write, output. */
export function tokensOf(t: Partial<PhaseTotals>): number {
  const c = totalsOf(t)
  return c.input + c.cacheRead + c.cacheWrite + c.output
}

export function newRecord(key: string, project: string, startedAt: number): UsageRecord {
  return { key, project, task: '', startedAt, phases: {}, models: {} }
}

export function addRequest(record: UsageRecord, phase: Phase, usage: RequestUsage | null, costDeltaUsd: number, subagent = false): UsageRecord {
  const request: PhaseTotals = {
    ...ZERO,
    requests: 1,
    input: usage?.input_tokens ?? 0,
    output: usage?.output_tokens ?? 0,
    cacheRead: usage?.cache_read_input_tokens ?? 0,
    cacheWrite: usage?.cache_creation_input_tokens ?? 0,
    costUsd: Math.max(0, costDeltaUsd),
  }
  const tokens = tokensOf(request)
  const next = withPhase(record, phase, subagent ? { ...request, subagentRequests: 1, subagentTokens: tokens } : request)
  const model = usage?.model
  if (!model || tokens === 0) return next
  const models = record.models ?? {}
  return { ...next, models: { ...models, [model]: (models[model] ?? 0) + tokens } }
}

/** The time between two readings charged to a phase: all of it as wall time,
 * and as working time too when a main-thread turn ran through it. */
export function accrue(record: UsageRecord, phase: Phase, fromMs: number, toMs: number, working: boolean): UsageRecord {
  const ms = Math.max(0, toMs - fromMs)
  if (ms === 0) return record
  return withPhase(record, phase, { wallMs: ms, workMs: working ? ms : 0 })
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

/** Milliseconds as `45s` under a minute, else as task-clock.sh writes durations. */
export function formatElapsed(ms: number): string {
  if (ms < 60_000) return `${Math.floor(Math.max(0, ms) / 1000)}s`
  return formatDuration(ms / 60_000)
}

function requestCount(count: number): string {
  return `${count} request${count === 1 ? '' : 's'}`
}

function percent(part: number, whole: number): number {
  return whole > 0 ? Math.round((part / whole) * 100) : 0
}

function measured(record: UsageRecord): [Phase, PhaseTotals][] {
  return PHASES.flatMap((phase): [Phase, PhaseTotals][] => {
    const totals = record.phases[phase]
    return totals ? [[phase, totalsOf(totals)]] : []
  })
}

function sumOf(rows: readonly [Phase, PhaseTotals][]): PhaseTotals {
  return rows.reduce((acc, [, t]) => plus(acc, t), ZERO)
}

/** The band's row: tokens per phase, the phase in progress in full strength,
 * then the cost and the time of the run so far. */
export function compactRow(record: UsageRecord, current: Phase | null = null): Row {
  const rows = measured(record)
  if (rows.length === 0) return []
  const sum = sumOf(rows)
  const row: Span[] = [dim(record.task ? `sdd ${record.task}` : 'sdd'), GAP]
  rows.forEach(([phase, t], i) => {
    if (i > 0) row.push(dim(' › '))
    const cell = `${phase} ${formatTokens(tokensOf(t))}`
    row.push(phase === current ? bold(cell) : dim(cell))
  })
  row.push(GAP, bold(formatUsd(sum.costUsd)))
  if (sum.wallMs > 0) row.push(GAP, dim(formatElapsed(sum.wallMs)))
  return row
}

export function compactLine(record: UsageRecord, current: Phase | null = null): string {
  return rowText(compactRow(record, current))
}

export const NO_USAGE = 'No sdd phase measured yet.'

export const USAGE_NOTE = 'Cost per phase is the growth of the session total: exact in sum, approximate per phase when subagents overlap.'
export const TIME_NOTE = 'Time runs from a phase\'s skill to the next one; working is while a main-thread turn runs, waiting is the rest — yours.'

const SHARE_WIDTH = 10

/** A share of the whole as a short meter and its percent. */
function share(part: number, whole: number): string {
  const pct = percent(part, whole)
  return `${meter(pct, SHARE_WIDTH)} ${String(pct).padStart(3)}%`
}

/**
 * The report `/dev-setup usage` shows: one line for the run, a table with one
 * row per measured phase — time, working time, tokens and their share, cache
 * hit, output, cost — and where the tokens went: the main thread against the
 * subagents, each model, each kind of token.
 */
export function usageRows(record: UsageRecord, current: Phase | null = null): Row[] {
  const rows = measured(record)
  if (rows.length === 0) return [[dim(NO_USAGE)]]
  const total = sumOf(rows)
  const tokens = tokensOf(total)
  const waitMs = Math.max(0, total.wallMs - total.workMs)

  const title: Row = [
    bold(record.task ? `sdd usage — ${record.task}` : 'sdd usage'),
    GAP,
    dim(`${formatTokens(tokens)} tokens · ${formatUsd(total.costUsd)} · ${formatElapsed(total.wallMs)} (${formatElapsed(total.workMs)} working, ${formatElapsed(waitMs)} waiting)`),
  ]

  const cells = (label: Span, t: PhaseTotals, weight: (text: string) => Span): Span[] => {
    const read = t.input + t.cacheRead + t.cacheWrite
    return [
      label,
      weight(formatElapsed(t.wallMs)),
      weight(formatElapsed(t.workMs)),
      weight(String(t.requests)),
      weight(formatTokens(tokensOf(t))),
      dim(share(tokensOf(t), tokens)),
      weight(read > 0 ? `${percent(t.cacheRead, read)}%` : '—'),
      weight(formatTokens(t.output)),
      weight(formatUsd(t.costUsd)),
    ]
  }
  const header = ['phase', 'time', 'working', 'requests', 'tokens', 'share', 'cache hit', 'output', 'cost'].map(dim)
  const body = rows.map(([phase, t]) => (phase === current ? cells(span(`${phase} ●`, 'accent', true), t, bold) : cells(span(phase), t, span)))
  const table = columns([header, ...body, cells(bold('total'), total, bold)], ['left', 'right', 'right', 'right', 'right', 'left', 'right', 'right', 'right'])

  // One table, so every figure lines up: the sub-headings are rows of their
  // own, the entries under them indented inside the label cell.
  const line = (label: string, count: number, detail = ''): Span[] => [span(label), span(formatTokens(count)), dim(share(count, tokens)), dim(detail)]
  const mainTokens = tokens - total.subagentTokens
  const where: Span[][] = [
    line('main thread', mainTokens, requestCount(total.requests - total.subagentRequests)),
    line('subagents', total.subagentTokens, requestCount(total.subagentRequests)),
  ]
  const models = Object.entries(record.models ?? {}).sort((x, y) => y[1] - x[1])
  if (models.length > 0) where.push([dim('by model')], ...models.map(([model, count]) => line(`  ${model}`, count)))
  where.push(
    [dim('by kind')],
    line('  cache read', total.cacheRead),
    line('  cache write', total.cacheWrite),
    line('  input, uncached', total.input),
    line('  output', total.output),
  )

  const result: Row[] = [title, [], ...table, [], [bold('Where the tokens went')]]
  result.push(...columns(where, ['left', 'right', 'left', 'left']).map((row): Row => [INDENT, ...row]))
  result.push([], [dim(TIME_NOTE)], [dim(USAGE_NOTE)])
  return result
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

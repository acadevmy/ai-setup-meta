// views.ts — what `/dev-setup <view>` shows, as rows of spans.
//
// The same rows serve both outputs: drawn in the pane of an interactive
// session, joined into plain text everywhere else (`rowsText`). A script that
// failed is one line naming it, never a blank view; an empty value is written
// as `none` / `not set`, never left out.

import type { CatalogueEntry } from './catalogue.ts'
import type { OpenClock, ScriptJson } from './clock.ts'
import { clockDetail, clockRow, formatDuration } from './clock.ts'
import type { Run, RunState } from './runs.ts'
import type { Row, Span, Tone } from './rows.ts'
import { bold, columns, dim, field, GAP, INDENT, rowsText, rowText, span } from './rows.ts'

export const VIEWS = ['commands', 'clock', 'status', 'worktrees', 'context', 'usage', 'runs'] as const
export type View = (typeof VIEWS)[number]

/** The argument names a person types; no argument is the catalogue. */
export const ARGUMENT_VIEWS: readonly View[] = VIEWS.filter((view) => view !== 'commands')

export const TAB_LABELS: Readonly<Record<View, string>> = {
  commands: 'Commands',
  clock: 'Clock',
  status: 'Status',
  worktrees: 'Worktrees',
  context: 'Context',
  usage: 'Usage',
  runs: 'Runs',
}

/** Where each view's figures come from, named in the pane's footer so a
 * snapshot is read as one. */
export const VIEW_SOURCES: Readonly<Record<View, string>> = {
  commands: 'the user-invocable skills of the plugin, read from their SKILL.md',
  clock: 'task-clock.sh --status',
  status: 'check-prerequisites.sh',
  worktrees: 'worktree-info.sh',
  context: "the session's own figures",
  usage: 'every model request of the sdd run, charged to the phase in progress',
  runs: 'the Workflow calls of this session and their task notifications',
}

export function parseView(args: string): View | null {
  const word = args.trim().split(/\s+/)[0]?.toLowerCase() ?? ''
  if (word === '') return 'commands'
  return (VIEWS as readonly string[]).includes(word) ? (word as View) : null
}

export function unknownViewText(args: string): string {
  return `Unknown view "${args.trim()}". Views: ${ARGUMENT_VIEWS.join(', ')} — or no argument for the commands.`
}

export type ScriptOutcome =
  | { readonly ok: true; readonly script: string; readonly json: ScriptJson }
  | { readonly ok: false; readonly script: string; readonly line: string }

function lastLine(text: string): string {
  const lines = text.trim().split(/\r?\n/)
  return lines[lines.length - 1]?.trim() ?? ''
}

/** A script run that went wrong, as the one line the view shows. */
export function failureLine(script: string, exitCode: number | null, detail: string): string {
  const tail = lastLine(detail)
  const what = exitCode === null ? 'did not finish' : `exited ${exitCode}`
  return `${script} ${what}${tail ? `: ${tail}` : ''}`
}

/** A script's stdout as its flat JSON, or the failure line when it is not JSON. */
export function scriptOutcome(script: string, exitCode: number, stdout: string, stderr: string): ScriptOutcome {
  if (exitCode !== 0) return { ok: false, script, line: failureLine(script, exitCode, stderr) }
  try {
    const parsed: unknown = JSON.parse(stdout)
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('not an object')
    const json: Record<string, string> = {}
    for (const [key, value] of Object.entries(parsed)) json[key] = String(value)
    return { ok: true, script, json }
  } catch {
    return { ok: false, script, line: `${script} printed no JSON${stderr.trim() ? `: ${lastLine(stderr)}` : ''}` }
  }
}

/** The one row a failed script leaves in a view. */
export function failureRow(line: string): Row {
  return [span(line, 'bad')]
}

function orElse(value: string | undefined, fallback: string): Span {
  return value && value.trim() !== '' ? span(value) : dim(fallback)
}

function list(value: string | undefined): string[] {
  return (value ?? '').split(/\r?\n/).filter((line) => line.trim() !== '')
}

function plural(count: number, noun: string): string {
  return `${count} ${noun}${count === 1 ? '' : 's'}`
}

// ── Clock ─────────────────────────────────────────────────────────────────────

export const NO_CLOCK = 'No task clock is open in this repository.'

export function clockRows(status: ScriptOutcome, clocks: readonly OpenClock[], failures: readonly string[], nowMs: number): Row[] {
  if (!status.ok) return [failureRow(status.line)]
  if (clocks.length === 0 && failures.length === 0) return [[dim(NO_CLOCK)]]
  const rows: Row[] = [[bold(clocks.length === 1 ? 'Open task clock' : 'Open task clocks')]]
  for (const clock of clocks) {
    rows.push([INDENT, ...clockRow(clock, nowMs)])
    const detail = clockDetail(clock)
    if (detail.length > 0) rows.push([INDENT, INDENT, ...detail])
  }
  rows.push(...failures.map(failureRow))
  return rows
}

export function clockView(status: ScriptOutcome, clocks: readonly OpenClock[], failures: readonly string[], nowMs: number): string[] {
  return rowsText(clockRows(status, clocks, failures, nowMs))
}

// ── Status ────────────────────────────────────────────────────────────────────

/** The label column of the status and worktrees views: `Worktrees` is the widest. */
const LABEL = 9
const MAX_FILES = 15

/** A path under the working directory, shown relative to it. */
export function relativeTo(cwd: string, path: string): string {
  const base = cwd.endsWith('/') ? cwd : `${cwd}/`
  return cwd !== '' && path.startsWith(base) ? path.slice(base.length) : path
}

function specStatusTone(status: string): Tone | undefined {
  if (status === 'approved' || status === 'implemented') return 'good'
  if (status === 'draft') return 'warn'
  return undefined
}

export function statusRows(outcome: ScriptOutcome, cwd = ''): Row[] {
  if (!outcome.ok) return [failureRow(outcome.line)]
  const j = outcome.json
  const changed = list(j.CHANGED_FILES)
  const branch: Span[] = [orElse(j.BRANCH, 'not set')]
  if (j.TASK_ID) branch.push(GAP, dim(`task ${j.TASK_ID}`))
  const base: Span[] = [orElse(j.BASE_BRANCH, 'not set')]
  if (j.MERGE_BASE) base.push(GAP, dim(`fork point ${j.MERGE_BASE.slice(0, 8)}`))
  const spec: Span[] = j.SPEC
    ? [span(relativeTo(cwd, j.SPEC)), GAP, j.SPEC_STATUS ? span(j.SPEC_STATUS, specStatusTone(j.SPEC_STATUS)) : dim('status not set')]
    : [dim('none')]
  const rows: Row[] = [
    field('Branch', LABEL, ...branch),
    field('Base', LABEL, ...base),
    field('Spec', LABEL, ...spec),
    field('Changed', LABEL, changed.length === 0 ? dim('nothing') : span(plural(changed.length, 'file'))),
  ]
  for (const file of changed.slice(0, MAX_FILES)) rows.push([INDENT, dim(file)])
  if (changed.length > MAX_FILES) rows.push([INDENT, dim(`… ${changed.length - MAX_FILES} more`)])
  return rows
}

export function statusView(outcome: ScriptOutcome, cwd = ''): string[] {
  return rowsText(statusRows(outcome, cwd))
}

// ── Worktrees ─────────────────────────────────────────────────────────────────

export function worktreesRows(outcome: ScriptOutcome): Row[] {
  if (!outcome.ok) return [failureRow(outcome.line)]
  const j = outcome.json
  const offset = Number.parseInt(j.PORT_OFFSET ?? '', 10)
  const rows: Row[] = [
    [
      ...field('Here', LABEL, orElse(j.WORKTREE, 'not set')),
      GAP,
      dim(`index ${j.WORKTREE_INDEX && j.WORKTREE_INDEX.trim() !== '' ? j.WORKTREE_INDEX : 'not set'} · port offset +${Number.isFinite(offset) ? offset : 0}`),
    ],
  ]
  const worktrees = list(j.WORKTREES)
  if (worktrees.length === 0) {
    rows.push(field('Worktrees', LABEL, dim('none')))
  } else {
    rows.push([bold('Worktrees')])
    const table = worktrees.map((row) => {
      const [path = '', branch = ''] = row.split('\t')
      return branch.trim() !== '' ? [bold(branch), dim(path)] : [dim('(detached)'), dim(path)]
    })
    rows.push(...columns(table, ['left', 'left']).map((row) => [INDENT, ...row]))
  }
  const overlaps = list(j.OVERLAPS)
  if (overlaps.length === 0) {
    rows.push(field('Overlaps', LABEL, dim('none')))
  } else {
    rows.push([bold('Overlaps'), GAP, span(`${overlaps.length}`, 'warn', true)])
    const table = overlaps.map((row) => {
      const [file = '', branches = ''] = row.split('\t')
      return [span(file), span(branches.split(',').join(', '), 'warn')]
    })
    rows.push(...columns(table, ['left', 'left']).map((row) => [INDENT, ...row]))
  }
  return rows
}

export function worktreesView(outcome: ScriptOutcome): string[] {
  return rowsText(worktreesRows(outcome))
}

// ── Commands ──────────────────────────────────────────────────────────────────

export const GUIDE_POINTER = 'Details: docs/developer-guide.md in acadevmy/ai-setup-meta.'
export const NO_COMMANDS = 'No public command found in the plugin.'
const DETAIL_LABELS = ['when', 'takes']

/** The label column of the catalogue: the command names and the detail labels
 * share it, so every entry lines up the same way. */
export function catalogueLabelWidth(entries: readonly CatalogueEntry[]): number {
  return Math.max(...DETAIL_LABELS.map((label) => label.length), ...entries.map((entry) => entry.name.length))
}

/** One entry under its prefix: the name in the label column with what it does
 * beside it, then when to use it and what it takes. */
export function entryRows(entry: CatalogueEntry, width: number): Row[] {
  const takes: Span[] = [span(entry.input)]
  if (entry.outward) takes.push(GAP, span('outward-facing · started only by you', 'warn'))
  const rows: Row[] = [[span(entry.name.padEnd(width), 'accent', true), GAP, span(entry.what)]]
  if (entry.when) rows.push(field('when', width, span(entry.when)))
  rows.push(field('takes', width, ...takes))
  return rows
}

/** The catalogue as rows: the prefix alone on its row — the command always
 * breaks after the colon — and the entry indented under it, a blank row
 * between entries. */
export function catalogueRows(entries: readonly CatalogueEntry[]): Row[] {
  if (entries.length === 0) return [[dim(NO_COMMANDS)], [dim(GUIDE_POINTER)]]
  const width = catalogueLabelWidth(entries)
  const rows: Row[] = []
  entries.forEach((entry, i) => {
    if (i > 0) rows.push([])
    rows.push([span(entry.prefix, 'accent')])
    rows.push(...entryRows(entry, width).map((row) => [INDENT, ...row]))
  })
  rows.push([], [dim(GUIDE_POINTER)])
  return rows
}

export function catalogueLines(entries: readonly CatalogueEntry[]): string[] {
  return rowsText(catalogueRows(entries))
}

// ── Runs ──────────────────────────────────────────────────────────────────────

export const NO_RUNS = 'No auto-sdd run launched in this session.'
export const RUNS_NOTE = 'A run is seen at its launch and at its end: what it is doing in between is not reported.'

const RUN_TONE: Readonly<Record<RunState, Tone | undefined>> = {
  running: 'accent',
  'ready-for-mr': 'good',
  failed: 'bad',
  killed: 'bad',
  completed: undefined,
}

export function runTone(state: RunState): Tone | undefined {
  return RUN_TONE[state]
}

/** One run's row: the task, its state in the state's colour, the time it has
 * been running, and what it reported — the merge request, or the reason. */
export function runRow(run: Run, nowMs: number): Row {
  const row: Span[] = [bold(run.taskId), GAP, span(run.state, runTone(run.state))]
  if (run.state === 'running') row.push(GAP, dim(formatDuration((nowMs - run.startedAt) / 60_000)))
  const detail = run.mergeRequest || run.reason
  if (detail) row.push(GAP, run.mergeRequest ? span(detail) : dim(detail))
  return row
}

export function runLine(run: Run, nowMs: number): string {
  return rowText(runRow(run, nowMs))
}

export function runsRows(runs: readonly Run[], nowMs: number): Row[] {
  if (runs.length === 0) return [[dim(NO_RUNS)]]
  return [...runs.map((run) => runRow(run, nowMs)), [], [dim(RUNS_NOTE)]]
}

export function runsLines(runs: readonly Run[], nowMs: number): string[] {
  return rowsText(runsRows(runs, nowMs))
}

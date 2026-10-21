// views.ts — what `/dev-setup <view>` shows, as rows of spans.
//
// The same rows serve both outputs: drawn in the pane of an interactive
// session, joined into plain text everywhere else (`rowsText`). A script that
// failed is one line naming it, never a blank view; an empty value is written
// as `none` / `not set`, never left out.

import type { CatalogueEntry } from './catalogue.ts'
import type { OpenClock, ScriptJson } from './clock.ts'
import { clockDetail, elapsedMinutes, formatDuration, formatTime, recentTasks } from './clock.ts'
import type { SessionChanges } from './session.ts'
import { changeLabel } from './session.ts'
import type { Run, RunState } from './runs.ts'
import type { Row, Span, Tone } from './rows.ts'
import { bold, columns, dim, field, GAP, INDENT, rowsText, rowText, span } from './rows.ts'

export const VIEWS = ['commands', 'clock', 'status', 'context', 'usage', 'runs'] as const
export type View = (typeof VIEWS)[number]

/** The argument names a person types; no argument is the catalogue. */
export const ARGUMENT_VIEWS: readonly View[] = VIEWS.filter((view) => view !== 'commands')

export const TAB_LABELS: Readonly<Record<View, string>> = {
  commands: 'Commands',
  clock: 'Clock',
  status: 'Status',
  context: 'Context',
  usage: 'Usage',
  runs: 'Runs',
}

/** Where each view's figures come from, named in the pane's footer so a
 * snapshot is read as one. */
export const VIEW_SOURCES: Readonly<Record<View, string>> = {
  commands: 'the user-invocable skills of the plugin, read from their SKILL.md',
  clock: 'task-clock.sh --status',
  status: 'git, from the moment this session began — a file counts when it was modified after it',
  context: "the session's own figures",
  usage: 'every model request and main-thread turn of the sdd run, charged to the phase in progress',
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

function plural(count: number, noun: string): string {
  return `${count} ${noun}${count === 1 ? '' : 's'}`
}

// ── Clock ─────────────────────────────────────────────────────────────────────

export const NO_CLOCK = 'No task clock is open in this repository.'
export const CLOCK_HINT = 'A clock starts when a flow moves its task to IN PROGRESS — /dev-setup:sdd, quick or auto-sdd — and stops when the merge request opens.'

/**
 * The open clocks, one card each: the task and its total in full strength, the
 * branch's own task marked, and under it when the interval began and what the
 * earlier ones add up to. Several clocks get a total line first; the clocks
 * stopped in the last five minutes — a failed run waiting on its BLOCKED move —
 * close the view.
 */
export function clockRows(
  status: ScriptOutcome,
  clocks: readonly OpenClock[],
  failures: readonly string[],
  nowMs: number,
  branchTask = '',
): Row[] {
  if (!status.ok) return [failureRow(status.line)]
  const recent = recentTasks(status.json)
  const rows: Row[] = []
  if (clocks.length === 0 && failures.length === 0) {
    rows.push([dim(NO_CLOCK)], [dim(CLOCK_HINT)])
  } else if (clocks.length > 1) {
    const total = clocks.reduce((sum, clock) => sum + elapsedMinutes(clock, nowMs), 0)
    rows.push([bold(plural(clocks.length, 'open clock')), GAP, dim(`${formatDuration(total)} in all`)], [])
  }
  const cards = columns(
    clocks.map((clock) => [
      span(`● ${clock.task}`, 'good', true),
      span('in progress', 'good'),
      bold(formatDuration(elapsedMinutes(clock, nowMs))),
      clock.task === branchTask ? span('← this branch', 'accent') : span(''),
    ]),
    ['left', 'left', 'right', 'left'],
  )
  clocks.forEach((clock, i) => {
    if (i > 0) rows.push([])
    rows.push(cards[i] ?? [])
    const detail = clockDetail(clock, nowMs)
    if (detail.length > 0) rows.push([INDENT, INDENT, ...detail])
  })
  rows.push(...failures.map(failureRow))
  if (recent.length > 0) rows.push([], [dim('Stopped in the last five minutes'), GAP, span(recent.join(', '))])
  return rows
}

export function clockView(status: ScriptOutcome, clocks: readonly OpenClock[], failures: readonly string[], nowMs: number, branchTask = ''): string[] {
  return rowsText(clockRows(status, clocks, failures, nowMs, branchTask))
}

// ── Status ────────────────────────────────────────────────────────────────────

/** The label column of the status view: `Session` is the widest. */
const LABEL = 7
const MAX_FILES = 15

const CHANGE_TONE: Readonly<Record<string, Tone>> = {
  new: 'good',
  added: 'good',
  deleted: 'bad',
  conflict: 'bad',
  staged: 'accent',
}

/** The files as a `label  path` table, capped at MAX_FILES. */
function fileRows(files: readonly { label: string; path: string }[]): Row[] {
  const shown = files.slice(0, MAX_FILES)
  const rows = columns(
    shown.map((file) => [span(file.label, CHANGE_TONE[file.label]), span(file.path)]),
    ['left', 'left'],
  ).map((row) => [INDENT, ...row])
  if (files.length > MAX_FILES) rows.push([INDENT, dim(`… ${files.length - MAX_FILES} more`)])
  return rows
}

/**
 * What this session changed: the commits it made, the working-tree changes it
 * left, the files it committed. Nothing older than the session is shown — the
 * branch's earlier work is the merge request's business, not this view's.
 */
export function statusRows(branch: string, changes: SessionChanges | string): Row[] {
  const head: Row[] = [field('Branch', LABEL, branch.trim() !== '' ? span(branch) : dim('not set'))]
  if (typeof changes === 'string') return [...head, failureRow(changes)]
  const since = `since ${formatTime(changes.startedAt)}`
  const { commits, uncommitted, committed } = changes
  if (commits.length === 0 && uncommitted.length === 0 && committed.length === 0) {
    return [...head, field('Session', LABEL, dim(`${since} · nothing changed yet`))]
  }
  const files = uncommitted.length + committed.length
  const rows: Row[] = [
    ...head,
    field('Session', LABEL, span(since), GAP, dim(`${plural(commits.length, 'commit')} · ${plural(files, 'file')}`)),
  ]
  if (commits.length > 0) {
    rows.push([], [bold('Commits')])
    rows.push(...commits.slice(0, MAX_FILES).map((commit): Row => [INDENT, span(commit.sha, 'accent'), GAP, span(commit.subject)]))
    if (commits.length > MAX_FILES) rows.push([INDENT, dim(`… ${commits.length - MAX_FILES} more`)])
  }
  if (uncommitted.length > 0) {
    rows.push([], [bold('Not committed'), GAP, dim(String(uncommitted.length))])
    rows.push(...fileRows(uncommitted.map((entry) => ({ label: changeLabel(entry.code), path: entry.path }))))
  }
  if (committed.length > 0) {
    rows.push([], [bold('Committed'), GAP, dim(String(committed.length))])
    rows.push(...fileRows(committed.map((path) => ({ label: 'committed', path }))))
  }
  return rows
}

export function statusView(branch: string, changes: SessionChanges | string): string[] {
  return rowsText(statusRows(branch, changes))
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

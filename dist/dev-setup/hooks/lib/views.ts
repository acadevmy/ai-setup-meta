// views.ts — what `/dev-setup <view>` shows, as lines of text.
//
// The same lines serve both outputs: drawn as Text in the pane of an
// interactive session, returned as plain text everywhere else. A script that
// failed is one line naming it, never a blank view; an empty value is written
// as `none` / `not set`, never left out.

import type { CatalogueEntry } from './catalogue.ts'
import type { OpenClock, ScriptJson } from './clock.ts'
import { clockLine, formatDuration } from './clock.ts'
import type { Run } from './runs.ts'

export const VIEWS = ['commands', 'clock', 'status', 'worktrees', 'context', 'usage', 'runs'] as const
export type View = (typeof VIEWS)[number]

/** The argument names a person types; no argument is the catalogue. */
export const ARGUMENT_VIEWS: readonly View[] = VIEWS.filter((view) => view !== 'commands')

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

function orElse(value: string | undefined, fallback: string): string {
  return value && value.trim() !== '' ? value : fallback
}

function list(value: string | undefined): string[] {
  return (value ?? '').split(/\r?\n/).filter((line) => line.trim() !== '')
}

export function clockView(status: ScriptOutcome, clocks: readonly OpenClock[], failures: readonly string[], nowMs: number): string[] {
  if (!status.ok) return [status.line]
  const lines = clocks.map((clock) => clockLine(clock, nowMs))
  lines.push(...failures)
  if (lines.length === 0) return ['No task clock is open in this repository.']
  return ['Open task clocks:', ...lines.map((line) => `  ${line}`)]
}

/** A path under the working directory, shown relative to it. */
export function relativeTo(cwd: string, path: string): string {
  const base = cwd.endsWith('/') ? cwd : `${cwd}/`
  return cwd !== '' && path.startsWith(base) ? path.slice(base.length) : path
}

export function statusView(outcome: ScriptOutcome, cwd = ''): string[] {
  if (!outcome.ok) return [outcome.line]
  const j = outcome.json
  const changed = list(j.CHANGED_FILES)
  const forkPoint = j.MERGE_BASE ? ` (fork point ${j.MERGE_BASE.slice(0, 8)})` : ''
  const spec = j.SPEC ? `${relativeTo(cwd, j.SPEC)} (${orElse(j.SPEC_STATUS, 'status not set')})` : 'none'
  return [
    `Branch:   ${orElse(j.BRANCH, 'not set')}${j.TASK_ID ? `  (task ${j.TASK_ID})` : ''}`,
    `Base:     ${orElse(j.BASE_BRANCH, 'not set')}${forkPoint}`,
    `Spec:     ${spec}`,
    `Changed:  ${changed.length === 0 ? 'nothing' : `${changed.length} file${changed.length === 1 ? '' : 's'}`}`,
  ]
}

export function worktreesView(outcome: ScriptOutcome): string[] {
  if (!outcome.ok) return [outcome.line]
  const j = outcome.json
  const offset = Number.parseInt(j.PORT_OFFSET ?? '', 10)
  const lines = [
    `This worktree: ${orElse(j.WORKTREE, 'not set')}  (index ${orElse(j.WORKTREE_INDEX, 'not set')}, port offset +${Number.isFinite(offset) ? offset : 0})`,
  ]
  const worktrees = list(j.WORKTREES)
  lines.push(worktrees.length === 0 ? 'Worktrees: none' : 'Worktrees:')
  for (const row of worktrees) {
    const [path, branch] = row.split('\t')
    lines.push(`  ${orElse(branch, '(detached)')}  ${path}`)
  }
  const overlaps = list(j.OVERLAPS)
  lines.push(overlaps.length === 0 ? 'Overlaps: none' : `Overlaps (${overlaps.length}):`)
  for (const row of overlaps) {
    const [file, branches] = row.split('\t')
    lines.push(`  ${file} — ${(branches ?? '').split(',').join(', ')}`)
  }
  return lines
}

export const GUIDE_POINTER = 'Details: docs/developer-guide.md in acadevmy/ai-setup-meta.'
export const NO_COMMANDS = 'No public command found in the plugin.'
export const NO_RUNS = 'No auto-sdd run launched in this session.'
export const RUNS_NOTE = 'A run is seen at its launch and at its end: what it is doing in between is not reported.'

/** A catalogue row's detail lines, under its command: when to use it, what it takes. */
export function entryDetails(entry: CatalogueEntry): string[] {
  const takes = `  Takes: ${entry.input}${entry.outward ? ' · outward-facing — started only by you' : ''}`
  return entry.when ? [`  ${entry.when}`, takes] : [takes]
}

export function catalogueLines(entries: readonly CatalogueEntry[]): string[] {
  if (entries.length === 0) return [NO_COMMANDS, GUIDE_POINTER]
  return [...entries.flatMap((entry) => [`${entry.command} — ${entry.what}`, ...entryDetails(entry)]), GUIDE_POINTER]
}

export function runLine(run: Run, nowMs: number): string {
  const elapsed = formatDuration((nowMs - run.startedAt) / 60_000)
  const state = run.state === 'running' ? `running · ${elapsed}` : run.state
  const detail = run.mergeRequest || run.reason
  return `${run.taskId}  ${state}${detail ? `  ${detail}` : ''}`
}

export function runsLines(runs: readonly Run[], nowMs: number): string[] {
  if (runs.length === 0) return [NO_RUNS]
  return [...runs.map((run) => runLine(run, nowMs)), RUNS_NOTE]
}

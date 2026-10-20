// register.ts — the dev-setup mod: the state of the work in the terminal,
// without a model turn (DE-17071).
//
// An interface layer and nothing more. It draws and answers from what the
// plugin scripts report; it observes tool calls, prompts, skills and model
// requests and passes every one of them on untouched; its only writes are its
// own store and a prompt filled — never sent. The rules live in the bash hooks,
// the deny rules and the sandbox: a client without mods loses this view and
// keeps every one of them.
//
// Every `$` call is in this file, because the engine's static analysis accepts
// `$` passed to a top-level function of the same file only. The logic is in
// lib/, as plain functions with their own tests: views.ts says what a view
// holds, draw.ts lays it out, and the handlers it gets are closures made here.

import type { EngineInterface, On } from 'claude-code'
import { clockRow, formatTime, openTasks, taskOfBranch, toOpenClock } from './lib/clock.ts'
import type { OpenClock } from './lib/clock.ts'
import { closurePrompt, closureTask, isMergeRequestCreate, mergeRequestUrl, toolOutputText } from './lib/merge-request.ts'
import { parseFrontmatter, sortEntries, toEntry, useText } from './lib/catalogue.ts'
import type { CatalogueEntry } from './lib/catalogue.ts'
import { accrue, addRequest, compactRow, isUsageRecord, newRecord, NO_USAGE, phaseOf, pruneIndex, toIndex, USAGE_INDEX, usageRows, withTask } from './lib/usage.ts'
import type { Phase, RequestUsage, UsageRecord } from './lib/usage.ts'
import { addRun, applyNotification, attachMergeRequest, parseNotification, resumePrompt, runFromWorkflowCall } from './lib/runs.ts'
import type { Run } from './lib/runs.ts'
import { contextRows, contextWarning, devSetupShare, mcpServerNames } from './lib/context.ts'
import { parseCommits, parsePorcelain, pathsToStat, sessionChanges } from './lib/session.ts'
import type { SessionChanges } from './lib/session.ts'
import { dim, rowsText } from './lib/rows.ts'
import type { Row } from './lib/rows.ts'
import { bandIsEmpty, drawBand, drawPane } from './lib/draw.ts'
import type { PaneBody } from './lib/draw.ts'
import {
  ARGUMENT_VIEWS,
  catalogueRows,
  clockRows,
  failureLine,
  parseView,
  runsRows,
  scriptOutcome,
  statusRows,
  unknownViewText,
  VIEW_SOURCES,
} from './lib/views.ts'
import type { ScriptOutcome, View } from './lib/views.ts'

type Api = EngineInterface

const COMMAND = 'dev-setup'
const PANE = 'dev-setup'
const SCRIPT_TIMEOUT_MS = 15_000
const REFRESH_MS = 60_000
/** A task-clock.sh call that changes a clock; `--status` only reads one. */
const CLOCK_CHANGE = /task-clock\.sh\b[^\n]*--(start|stop)\b/

// ── State ─────────────────────────────────────────────────────────────────────
//
// Module-level, reset per session at `session.end`; only the usage records
// outlive it, in $.store.

type SddRun = {
  readonly record: UsageRecord
  /** The phase requests are charged to; null once the run's merge request is open. */
  readonly phase: Phase | null
  readonly lastCostUsd: number | null
  readonly indexed: boolean
  /** When the time up to now was last charged to the phase. */
  readonly tickAt: number
}

let drawing = false
let workDir = ''
let refreshTimer: { cancel: () => void } | null = null
let refreshing: Promise<void> | null = null
let clocks: OpenClock[] = []
/** What the last full read of the clocks reported, for the clock view. */
let clockStatus: ScriptOutcome | null = null
let clockFailures: string[] = []
/** The task the checked-out branch names, read with the clocks. */
let branchTask = ''
let closure: { url: string; tasks: string[] } | null = null
let view: View = 'commands'
let viewRows: Row[] = []
let viewReadAt: number | null = null
let viewLoad = 0
let catalogue: CatalogueEntry[] | null = null
let sdd: SddRun | null = null
/** The main-thread turns running now: a subagent's run raises no turn.start. */
const mainTurns = new Set<string>()
let lastSaved: UsageRecord | null = null
let runs: Run[] = []
let contextPercent: number | undefined

// ── Reading the plugin scripts ────────────────────────────────────────────────

async function runScript($: Api, script: string, args: readonly string[]): Promise<ScriptOutcome> {
  try {
    const result = await $.process.run(['bash', `${$.plugin.root}/scripts/${script}`, ...args, '--json'], {
      cwd: workDir,
      timeoutMs: SCRIPT_TIMEOUT_MS,
    })
    return scriptOutcome(script, result.exitCode, result.stdout, result.stderr)
  } catch (error) {
    return { ok: false, script, line: failureLine(script, null, error instanceof Error ? error.message : String(error)) }
  }
}

async function readClocks($: Api): Promise<{ status: ScriptOutcome; open: OpenClock[]; failures: string[] }> {
  const status = await runScript($, 'task-clock.sh', ['--status'])
  if (!status.ok) return { status, open: [], failures: [] }
  const each = await Promise.all(openTasks(status.json).map((task) => runScript($, 'task-clock.sh', ['--task', task, '--status'])))
  const open: OpenClock[] = []
  const failures: string[] = []
  for (const one of each) {
    if (!one.ok) {
      failures.push(one.line)
      continue
    }
    const clock = toOpenClock(one.json)
    if (clock) open.push(clock)
  }
  return { status, open, failures }
}

async function readAndApplyClocks($: Api): Promise<void> {
  const [{ status, open, failures }, branch] = await Promise.all([readClocks($), currentBranch($)])
  clockStatus = status
  clockFailures = failures
  branchTask = taskOfBranch(branch)
  if (!status.ok) return
  const changed = open.length !== clocks.length || open.some((clock, i) => clock.task !== clocks[i]?.task)
  clocks = open
  if (closure) {
    const still = closure.tasks.filter((task) => open.some((clock) => clock.task === task))
    closure = still.length > 0 ? { url: closure.url, tasks: still } : null
  }
  const only = open.length === 1 ? open[0] : undefined
  if (sdd && only) sdd = { ...sdd, record: withTask(sdd.record, only.task) }
  if (changed || open.length > 0) $.ui.invalidate('ui.render')
}

/** One refresh at a time: a second caller waits for the one in flight. */
function refreshClocks($: Api): Promise<void> {
  refreshing ??= readAndApplyClocks($).finally(() => {
    refreshing = null
  })
  return refreshing
}

async function currentBranch($: Api): Promise<string> {
  try {
    const result = await $.process.run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'], { cwd: workDir, timeoutMs: SCRIPT_TIMEOUT_MS })
    return result.exitCode === 0 ? result.stdout.trim() : ''
  } catch {
    return ''
  }
}

/** A read-only git command in the session directory: its stdout, or the failure line. */
async function git($: Api, args: readonly string[]): Promise<{ ok: true; out: string } | { ok: false; line: string }> {
  try {
    const result = await $.process.run(['git', ...args], { cwd: workDir, timeoutMs: SCRIPT_TIMEOUT_MS })
    if (result.exitCode === 0) return { ok: true, out: result.stdout }
    return { ok: false, line: failureLine(`git ${args[0] ?? ''}`, result.exitCode, result.stderr) }
  } catch (error) {
    return { ok: false, line: failureLine(`git ${args[0] ?? ''}`, null, error instanceof Error ? error.message : String(error)) }
  }
}

/** What this session changed, or the line saying why it cannot be told. */
async function readSessionChanges($: Api): Promise<SessionChanges | string> {
  const startedAt = await $.session
    .usage()
    .then((usage) => usage.startedAt)
    .catch(() => null)
  if (startedAt === null) return 'the session start is not known on this client'
  const since = `--since=@${Math.floor(startedAt / 1000)}`
  const [root, status, log, files] = await Promise.all([
    git($, ['rev-parse', '--show-toplevel']),
    git($, ['status', '--porcelain=v1', '-z', '--untracked-files=all']),
    git($, ['log', since, '--format=%h%x09%s', 'HEAD']),
    git($, ['log', since, '--name-only', '--format=', 'HEAD']),
  ])
  if (!root.ok) return root.line
  if (!status.ok) return status.line
  const top = root.out.trim()
  const entries = parsePorcelain(status.out)
  const paths = pathsToStat(entries)
  const stats = await Promise.all(
    paths.map((path) =>
      $.fs
        .stat(path === '' ? top : `${top}/${path}`)
        .then((stat) => stat.mtimeMs)
        .catch(() => null),
    ),
  )
  const mtimes = new Map(paths.map((path, i) => [path, stats[i] ?? null]))
  // A branch with no commit yet has no log: that is no commit, not a failure.
  const commits = log.ok ? parseCommits(log.out) : []
  const committedFiles = files.ok ? files.out.split(/\r?\n/) : []
  return sessionChanges(startedAt, entries, (path) => mtimes.get(path) ?? null, commits, committedFiles)
}

async function readText($: Api, path: string): Promise<string> {
  try {
    return await $.fs.read(path)
  } catch {
    return ''
  }
}

// ── The views ─────────────────────────────────────────────────────────────────

/** The public commands, read once per module: a plugin update reloads it. */
async function loadCatalogue($: Api): Promise<CatalogueEntry[]> {
  if (catalogue) return catalogue
  const skillsDir = `${$.plugin.root}/skills`
  try {
    const dirs = (await $.fs.list(skillsDir)).filter((dir) => dir.kind === 'dir')
    const texts = await Promise.all(dirs.map((dir) => readText($, `${skillsDir}/${dir.name}/SKILL.md`)))
    const entries = dirs.flatMap((dir, i) => toEntry($.plugin.name, dir.name, parseFrontmatter(texts[i] ?? '')) ?? [])
    catalogue = sortEntries(entries)
    return catalogue
  } catch {
    return []
  }
}

async function contextViewRows($: Api): Promise<Row[]> {
  const [usage, mcpJson] = await Promise.all([
    $.session.usage({ breakdown: 'summary' }).catch(() => $.session.usage()),
    readText($, `${workDir}/.mcp.json`),
  ])
  const breakdown = usage.context.breakdown
  const share = breakdown ? devSetupShare(breakdown, mcpServerNames(mcpJson), $.plugin.name) : []
  return contextRows(usage.context, breakdown, share)
}

/** The latest record of this project — the store is shared by every project. */
async function latestRecord($: Api): Promise<UsageRecord | null> {
  try {
    const index = toIndex(await $.store.get(USAGE_INDEX))
    for (const key of [...index].reverse()) {
      const value = await $.store.get(key)
      if (isUsageRecord(value) && value.project === workDir) return value
    }
  } catch {
    // An unreadable store has nothing to show.
  }
  return null
}

/** A view's rows, read now: the plain-text answer, and what the pane shows
 * until the next load — the clock, runs and a live usage are drawn from the
 * session's state instead, so they move without a reload. */
async function loadView($: Api, wanted: View): Promise<Row[]> {
  switch (wanted) {
    case 'commands':
      return catalogueRows(await loadCatalogue($))
    case 'clock': {
      const [{ status, open, failures }, branch] = await Promise.all([readClocks($), currentBranch($)])
      clockStatus = status
      clockFailures = failures
      branchTask = taskOfBranch(branch)
      if (status.ok) clocks = open
      return clockRows(status, open, failures, await $.clock.now(), branchTask)
    }
    case 'status': {
      const [branch, changes] = await Promise.all([currentBranch($), readSessionChanges($)])
      return statusRows(branch, changes)
    }
    case 'context':
      return contextViewRows($)
    case 'usage': {
      const shown = (await liveRecord($)) ?? (await latestRecord($))
      return shown ? usageRows(shown, sdd?.phase ?? null) : [[dim(NO_USAGE)]]
    }
    case 'runs':
      return runsRows(runs, await $.clock.now())
  }
}

/** Switch the pane to a view; a slower earlier load never lands under a later tab. */
async function showView($: Api, wanted: View): Promise<void> {
  const load = ++viewLoad
  view = wanted
  const rows = await loadView($, wanted)
  if (load !== viewLoad) return
  viewRows = rows
  viewReadAt = await $.clock.now()
  $.ui.invalidate('ui.render')
}

/** What the pane draws for the current view, and the note its footer carries. */
async function paneBody($: Api): Promise<{ body: PaneBody; note: string }> {
  const readAt = viewReadAt === null ? '' : `read at ${formatTime(viewReadAt)}`
  switch (view) {
    case 'commands':
      return { body: { kind: 'commands', entries: catalogue ?? [] }, note: '' }
    case 'clock': {
      const status: ScriptOutcome = clockStatus ?? { ok: true, script: 'task-clock.sh', json: {} }
      return { body: { kind: 'rows', rows: clockRows(status, clocks, clockFailures, await $.clock.now(), branchTask) }, note: 'refreshed every minute' }
    }
    case 'runs':
      return { body: { kind: 'runs', runs, nowMs: await $.clock.now() }, note: '' }
    case 'usage': {
      const live = await liveRecord($)
      if (sdd && live) return { body: { kind: 'rows', rows: usageRows(live, sdd.phase) }, note: sdd.phase === null ? 'this session' : 'live' }
      return { body: { kind: 'rows', rows: viewRows }, note: 'the last run of this project' }
    }
    default:
      return { body: { kind: 'rows', rows: viewRows }, note: readAt }
  }
}

async function fillPrompt($: Api, text: string): Promise<void> {
  try {
    await $.prompt.fill({ text })
  } catch {
    $.ui.toast(text)
  }
}

// ── Usage records ─────────────────────────────────────────────────────────────

/** Persist the run's record — only when it changed, the index only once. */
async function saveRun($: Api): Promise<void> {
  const run = sdd
  if (!run || run.record === lastSaved) return
  try {
    await $.store.set(run.record.key, run.record)
    lastSaved = run.record
    if (!run.indexed) {
      // Read the index right before writing it: every session shares the store.
      const pruned = pruneIndex(toIndex(await $.store.get(USAGE_INDEX)), run.record.key)
      await $.store.set(USAGE_INDEX, pruned.index)
      for (const key of pruned.dropped) await $.store.delete(key)
      if (sdd?.record.key === run.record.key) sdd = { ...sdd, indexed: true }
    }
  } catch {
    // A store that cannot be written loses the history, never the session.
  }
}

/** The run with the time since its last reading charged to its phase —
 * as working time while a main-thread turn runs. A closed run is left as it is. */
function accrued(run: SddRun, now: number): SddRun {
  if (run.phase === null) return run
  return { ...run, record: accrue(run.record, run.phase, run.tickAt, now, mainTurns.size > 0), tickAt: now }
}

/** Charge the time so far, before anything that changes the phase or the turn. */
async function tick($: Api): Promise<void> {
  if (!sdd || sdd.phase === null) return
  const now = await $.clock.now()
  if (sdd) sdd = accrued(sdd, now)
}

/** The run as it stands this moment, for a drawing: charged, never saved. */
async function liveRecord($: Api): Promise<UsageRecord | null> {
  if (!sdd) return null
  return accrued(sdd, await $.clock.now()).record
}

async function observeSkill($: Api, skill: string): Promise<void> {
  const opened = phaseOf(skill, $.plugin.name)
  if (opened === null) return
  try {
    if (opened === 'intake') {
      void saveRun($)
      const now = await $.clock.now()
      const fresh = newRecord(`usage:${await $.session.id()}:${now}`, workDir, now)
      const cost = (await $.session.usage()).cost?.usd ?? null
      const only = clocks.length === 1 ? clocks[0] : undefined
      sdd = { record: only ? withTask(fresh, only.task) : fresh, phase: opened, lastCostUsd: cost, indexed: false, tickAt: now }
    } else if (sdd && sdd.phase !== null) {
      // Only an `sdd` run is measured: a sub-skill outside one opens nothing.
      sdd = { ...accrued(sdd, await $.clock.now()), phase: opened }
    } else {
      return
    }
    void saveRun($)
    $.ui.invalidate('ui.render')
  } catch {
    // Measuring is optional; the skill expands either way.
  }
}

async function observeRequest($: Api, usage: RequestUsage | null, subagent: boolean): Promise<void> {
  if (!sdd || sdd.phase === null) return
  try {
    const [cost, now] = await Promise.all([$.session.usage().then((figures) => figures.cost?.usd), $.clock.now()])
    const run = sdd
    if (!run || run.phase === null) return
    const charged = accrued(run, now)
    const delta = cost === undefined || run.lastCostUsd === null ? 0 : cost - run.lastCostUsd
    sdd = {
      ...charged,
      record: addRequest(charged.record, run.phase, usage, delta, subagent),
      lastCostUsd: cost ?? run.lastCostUsd,
    }
    $.ui.invalidate('ui.render')
  } catch {
    // A request that could not be measured is left out, never held up.
  }
}

// ── Observers: each one reads, none of them changes the event ─────────────────

async function observeBash($: Api, command: string, result: unknown): Promise<void> {
  try {
    const url = isMergeRequestCreate(command) ? mergeRequestUrl(toolOutputText(result)) : null
    if (url === null && !CLOCK_CHANGE.test(command)) return
    await refreshClocks($)
    if (url === null) return
    runs = attachMergeRequest(runs, command, url)
    // Every flow ends on its merge request: the sdd run's measurement ends too.
    if (sdd && sdd.phase !== null) {
      await tick($)
      sdd = { ...sdd, phase: null }
      void saveRun($)
    }
    const open = clocks.map((clock) => clock.task)
    if (open.length > 0) {
      const task = open.length === 1 ? open[0] : closureTask(open, await currentBranch($), command)
      closure = { url, tasks: task ? [task] : open }
    }
    $.ui.invalidate('ui.render')
  } catch {
    // Observation only: a failure here never touches the call.
  }
}

async function observeWorkflow($: Api, input: unknown, result: unknown): Promise<void> {
  try {
    const run = runFromWorkflowCall(input, result, await $.clock.now())
    if (!run) return
    const first = runs.length === 0
    runs = addRun(runs, run)
    $.ui.invalidate('ui.render')
    if (drawing && first) {
      view = 'runs'
      await $.ui.open({ id: PANE, title: COMMAND, closeOnEscape: true })
      $.ui.toast('auto-sdd runs launched — /dev-setup runs shows them')
    }
  } catch {
    // Observation only.
  }
}

function observeNotification($: Api, text: string): void {
  try {
    const notification = parseNotification(text)
    if (!notification) return
    runs = applyNotification(runs, notification)
    $.ui.invalidate('ui.render')
  } catch {
    // Observation only.
  }
}

// ── The hooks ─────────────────────────────────────────────────────────────────

export function register(on: On): void {
  on('session.start', async ($, e, next) => {
    drawing = e.isInteractive && e.surface !== null
    workDir = e.cwd
    try {
      await $.command.register({
        name: COMMAND,
        description: `Work status without a model turn — ${ARGUMENT_VIEWS.join(', ')}; no argument lists the commands`,
        argumentHint: `[${ARGUMENT_VIEWS.join('|')}]`,
        immediate: true,
      })
    } catch {
      // A taken name costs the command, never the rest of the mod.
    }
    refreshTimer?.cancel()
    refreshTimer = null
    if (drawing) {
      void refreshClocks($)
      refreshTimer = $.clock.every(REFRESH_MS, () => {
        void refreshClocks($)
        // The run's time moves on the band even with no clock open.
        if (sdd && sdd.phase !== null) $.ui.invalidate('ui.render')
      })
    }
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    await tick($)
    await saveRun($)
    refreshTimer?.cancel()
    refreshTimer = null
    clocks = []
    clockStatus = null
    clockFailures = []
    branchTask = ''
    closure = null
    sdd = null
    mainTurns.clear()
    runs = []
    contextPercent = undefined
    return next(e)
  })

  on('command.run', { command: COMMAND }, async ($, e) => {
    const wanted = parseView(e.args)
    if (wanted === null) return { text: unknownViewText(e.args) }
    if (drawing) {
      try {
        await showView($, wanted)
        await $.ui.open({ id: PANE, title: COMMAND, focus: true, closeOnEscape: true })
        return {}
      } catch {
        // The pane could not open: answer in text instead.
      }
    }
    return { text: rowsText(await loadView($, wanted)).join('\n') }
  })

  on('ui.render', { component: 'Pane' }, async ($, e, next) => {
    if (e.requestId !== PANE) return next(e)
    const { body, note } = await paneBody($)
    return drawPane(
      $.ui.resolve(e),
      { view, bodyColumns: e.props.bodyColumns, body, note, source: VIEW_SOURCES[view] },
      {
        show: (name) => {
          void showView($, name)
        },
        reload: () => {
          void showView($, view)
        },
        use: (entry) => {
          void fillPrompt($, useText(entry))
        },
        resume: (run) => {
          void fillPrompt($, resumePrompt(run))
        },
      },
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const now = await $.clock.now()
    const band = {
      clocks: clocks.map((clock) => clockRow(clock, now)),
      closure,
      usage: sdd && sdd.phase !== null ? compactRow(accrued(sdd, now).record, sdd.phase) : [],
      warning: contextWarning(contextPercent),
    }
    if (bandIsEmpty(band)) return next(e)
    const theirs = await next(e)
    return drawBand(
      $.ui.resolve(e),
      band,
      {
        close: (task, url) => {
          void fillPrompt($, closurePrompt(task, url, $.plugin.root))
        },
      },
      theirs ?? null,
    )
  })

  on('turn.start', async ($, e, next) => {
    await tick($)
    mainTurns.add(e.turnId)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (!e.agentId) {
      await tick($)
      mainTurns.delete(e.turnId)
      if (drawing) void refreshClocks($)
      void saveRun($)
    }
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    if (e.context.percent !== contextPercent) {
      contextPercent = e.context.percent
      $.ui.invalidate('ui.render')
    }
    return next(e)
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const result = await next(e)
    await observeBash($, typeof e.command === 'string' ? e.command : '', result)
    return result
  })

  on('tool.call', { tool: 'Workflow' }, async ($, e, next) => {
    const result = await next(e)
    await observeWorkflow($, e, result)
    return result
  })

  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind === 'task-notification') observeNotification($, e.text)
    return next(e)
  })

  on('skill.prompt', async ($, e, next) => {
    await observeSkill($, e.skill)
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    await observeRequest($, result.usage, e.agentId !== undefined)
    return result
  })
}

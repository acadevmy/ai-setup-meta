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
// lib/, as plain functions with their own tests.

import type { EngineInterface, On, RenderElement } from 'claude-code'
import { clockLine, openTasks, toOpenClock } from './lib/clock.ts'
import type { OpenClock } from './lib/clock.ts'
import { closurePrompt, closureTask, isMergeRequestCreate, mergeRequestUrl, toolOutputText } from './lib/merge-request.ts'
import { parseFrontmatter, sortEntries, toEntry, useText } from './lib/catalogue.ts'
import type { CatalogueEntry } from './lib/catalogue.ts'
import { addRequest, compactLine, isUsageRecord, newRecord, NO_USAGE, phaseOf, pruneIndex, toIndex, USAGE_INDEX, usageTable, withTask } from './lib/usage.ts'
import type { Phase, RequestUsage, UsageRecord } from './lib/usage.ts'
import { addRun, applyNotification, attachMergeRequest, canResume, parseNotification, resumePrompt, runFromWorkflowCall } from './lib/runs.ts'
import type { Run } from './lib/runs.ts'
import { contextLines, contextWarning, devSetupShare, mcpServerNames } from './lib/context.ts'
import {
  ARGUMENT_VIEWS,
  catalogueLines,
  clockView,
  entryDetails,
  failureLine,
  GUIDE_POINTER,
  NO_COMMANDS,
  NO_RUNS,
  parseView,
  runLine,
  RUNS_NOTE,
  runsLines,
  scriptOutcome,
  statusView,
  unknownViewText,
  VIEWS,
  worktreesView,
} from './lib/views.ts'
import type { ScriptOutcome, View } from './lib/views.ts'

type Api = EngineInterface

const COMMAND = 'dev-setup'
const PANE = 'dev-setup'
const SCRIPT_TIMEOUT_MS = 15_000
const REFRESH_MS = 60_000
/** A task-clock.sh call that changes a clock; `--status` only reads one. */
const CLOCK_CHANGE = /task-clock\.sh\b[^\n]*--(start|stop)\b/

const TAB_LABELS: Readonly<Record<View, string>> = {
  commands: 'Commands',
  clock: 'Clock',
  status: 'Status',
  worktrees: 'Worktrees',
  context: 'Context',
  usage: 'Usage',
  runs: 'Runs',
}

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
}

let drawing = false
let workDir = ''
let refreshTimer: { cancel: () => void } | null = null
let refreshing: Promise<void> | null = null
let clocks: OpenClock[] = []
let closure: { url: string; tasks: string[] } | null = null
let view: View = 'commands'
let viewLines: string[] = []
let viewLoad = 0
let catalogue: CatalogueEntry[] | null = null
let sdd: SddRun | null = null
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
  const { status, open } = await readClocks($)
  if (!status.ok) return
  const changed = open.length !== clocks.length || open.some((clock, i) => clock.task !== clocks[i]?.task)
  clocks = open
  if (closure) {
    const still = closure.tasks.filter((task) => open.some((clock) => clock.task === task))
    closure = still.length > 0 ? { url: closure.url, tasks: still } : null
  }
  if (sdd && open.length === 1) sdd = { ...sdd, record: withTask(sdd.record, open[0].task) }
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
    const entries = dirs.flatMap((dir, i) => toEntry($.plugin.name, dir.name, parseFrontmatter(texts[i])) ?? [])
    catalogue = sortEntries(entries)
    return catalogue
  } catch {
    return []
  }
}

async function contextViewLines($: Api): Promise<string[]> {
  const [usage, mcpJson] = await Promise.all([
    $.session.usage({ breakdown: 'summary' }).catch(() => $.session.usage()),
    readText($, `${workDir}/.mcp.json`),
  ])
  const breakdown = usage.context.breakdown
  const share = breakdown ? devSetupShare(breakdown, mcpServerNames(mcpJson), $.plugin.name) : []
  return contextLines(usage.context, breakdown, share)
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

async function loadView($: Api, wanted: View): Promise<string[]> {
  switch (wanted) {
    case 'commands':
      return catalogueLines(await loadCatalogue($))
    case 'clock': {
      const { status, open, failures } = await readClocks($)
      return clockView(status, open, failures, await $.clock.now())
    }
    case 'status':
      return statusView(await runScript($, 'check-prerequisites.sh', []), workDir)
    case 'worktrees':
      return worktreesView(await runScript($, 'worktree-info.sh', []))
    case 'context':
      return contextViewLines($)
    case 'usage': {
      const shown = sdd?.record ?? (await latestRecord($))
      return shown ? usageTable(shown) : [NO_USAGE]
    }
    case 'runs':
      return runsLines(runs, await $.clock.now())
  }
}

/** Switch the pane to a view; a slower earlier load never lands under a later tab. */
async function showView($: Api, wanted: View): Promise<void> {
  const load = ++viewLoad
  view = wanted
  const lines = await loadView($, wanted)
  if (load !== viewLoad) return
  viewLines = lines
  $.ui.invalidate('ui.render')
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

async function observeSkill($: Api, skill: string): Promise<void> {
  const opened = phaseOf(skill, $.plugin.name)
  if (opened === null) return
  try {
    if (opened === 'intake') {
      void saveRun($)
      const now = await $.clock.now()
      const fresh = newRecord(`usage:${await $.session.id()}:${now}`, workDir, now)
      const cost = (await $.session.usage()).cost?.usd ?? null
      sdd = { record: clocks.length === 1 ? withTask(fresh, clocks[0].task) : fresh, phase: opened, lastCostUsd: cost, indexed: false }
    } else if (sdd && sdd.phase !== null) {
      // Only an `sdd` run is measured: a sub-skill outside one opens nothing.
      sdd = { ...sdd, phase: opened }
    } else {
      return
    }
    void saveRun($)
    $.ui.invalidate('ui.render')
  } catch {
    // Measuring is optional; the skill expands either way.
  }
}

async function observeRequest($: Api, usage: RequestUsage | null): Promise<void> {
  const run = sdd
  if (!run || run.phase === null) return
  try {
    const cost = (await $.session.usage()).cost?.usd
    const delta = cost === undefined || run.lastCostUsd === null ? 0 : cost - run.lastCostUsd
    sdd = { ...run, record: addRequest(run.record, run.phase, usage, delta), lastCostUsd: cost ?? run.lastCostUsd }
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
      await $.ui.open({ id: PANE, title: COMMAND })
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
      })
    }
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    await saveRun($)
    refreshTimer?.cancel()
    refreshTimer = null
    clocks = []
    closure = null
    sdd = null
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
    return { text: (await loadView($, wanted)).join('\n') }
  })

  on('ui.render', { component: 'Pane' }, async ($, e, next) => {
    if (e.requestId !== PANE) return next(e)
    const { Box, Text, Button, Link } = $.ui.resolve(e)
    const tabs = Box({
      flexDirection: 'row',
      columnGap: 2,
      children: VIEWS.map((name, i) =>
        Button({
          key: `tab-${name}`,
          label: TAB_LABELS[name],
          hotkey: String(i + 1),
          plain: true,
          dimColor: name !== view,
          onPress: () => {
            void showView($, name)
          },
        }),
      ),
    })
    const body: RenderElement[] = []
    if (view === 'commands' && catalogue) {
      for (const entry of catalogue) {
        body.push(
          Box({
            flexDirection: 'row',
            columnGap: 1,
            children: [
              Button({
                key: `use-${entry.name}`,
                label: 'use',
                onPress: () => {
                  void fillPrompt($, useText(entry))
                },
              }),
              Text({ bold: true, children: [entry.command] }),
              Text({ children: [`— ${entry.what}`] }),
            ],
          }),
          ...entryDetails(entry).map((line) => Text({ dimColor: true, children: [line] })),
        )
      }
      if (catalogue.length === 0) body.push(Text({ children: [NO_COMMANDS] }))
      body.push(Text({ dimColor: true, children: [GUIDE_POINTER] }))
    } else if (view === 'runs') {
      const now = await $.clock.now()
      if (runs.length === 0) body.push(Text({ children: [NO_RUNS] }))
      for (const run of runs) {
        const row: RenderElement[] = [Text({ children: [runLine(run, now)] })]
        if (run.mergeRequest) row.push(Link({ href: run.mergeRequest, label: 'open' }))
        if (canResume(run)) {
          row.push(
            Button({
              key: `resume-${run.taskId}`,
              label: 'resume',
              onPress: () => {
                void fillPrompt($, resumePrompt(run))
              },
            }),
          )
        }
        body.push(Box({ flexDirection: 'row', columnGap: 1, children: row }))
      }
      if (runs.length > 0) body.push(Text({ dimColor: true, children: [RUNS_NOTE] }))
    } else {
      const lines = view === 'usage' && sdd ? usageTable(sdd.record) : viewLines
      body.push(...lines.map((line) => Text({ children: [line] })))
    }
    return Box({ flexDirection: 'column', children: [tabs, Text({ children: [' '] }), ...body] })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const usageLine = sdd && sdd.phase !== null ? compactLine(sdd.record) : ''
    const warning = contextWarning(contextPercent)
    if (clocks.length === 0 && !closure && !usageLine && !warning) return next(e)
    const { Box, Text, Button } = $.ui.resolve(e)
    const rows: RenderElement[] = []
    if (clocks.length > 0) {
      const now = await $.clock.now()
      rows.push(...clocks.map((clock) => Text({ children: [clockLine(clock, now)] })))
    }
    if (closure) {
      const { url, tasks } = closure
      rows.push(
        Box({
          flexDirection: 'row',
          columnGap: 1,
          children: [
            Text({ children: [`merge request open: ${url}`] }),
            ...tasks.map((task) =>
              Button({
                key: `close-${task}`,
                label: `close ${task}: stop clock + CODE REVIEW`,
                onPress: () => {
                  void fillPrompt($, closurePrompt(task, url, $.plugin.root))
                },
              }),
            ),
          ],
        }),
      )
    }
    if (usageLine) rows.push(Text({ dimColor: true, children: [usageLine] }))
    if (warning) rows.push(Text({ color: 'yellow', children: [warning] }))
    const theirs = await next(e)
    return Box({ flexDirection: 'column', children: theirs ? [...rows, theirs] : rows })
  })

  on('turn.complete', async ($, e, next) => {
    if (!e.agentId) {
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
    await observeRequest($, result.usage)
    return result
  })
}

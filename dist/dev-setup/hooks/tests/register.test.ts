// register.test.ts — the mod's hooks, driven through the engine's test kit.
//
// No session, no process, no store: every mods API call the mod makes is
// answered by a stub here, and the plugin scripts answer from a table.

import { describe, expect, mock, test } from 'claude-code/testing'

const ROOT_SCRIPTS = /\/scripts\/([a-z-]+\.sh)$/
const NOW = new Date(2026, 9, 7, 10, 0).getTime()

type Answer = { exitCode: number; stdout: string; stderr: string }

/** A process.run stub: `<script> <args>` → answer; `git <args>` from the
 * table too, the branch `feat/DE-1_x` for any git call it does not hold. */
function scripts(table: Record<string, Answer | string>, calls: string[] = []) {
  return ($: unknown, e: { argv: readonly string[]; init?: { cwd?: string } }) => {
    if (e.argv[0] === 'git') {
      const answer = table[e.argv.join(' ')]
      calls.push(`${e.argv.join(' ')} @${e.init?.cwd ?? ''}`)
      if (answer === undefined) return { value: { exitCode: 0, stdout: 'feat/DE-1_x\n', stderr: '' } }
      return { value: typeof answer === 'string' ? { exitCode: 0, stdout: answer, stderr: '' } : answer }
    }
    const script = ROOT_SCRIPTS.exec(e.argv[1] ?? '')?.[1] ?? e.argv.join(' ')
    const key = [script, ...e.argv.slice(2)].join(' ')
    calls.push(`${key} @${e.init?.cwd ?? ''}`)
    const answer = table[key]
    if (answer === undefined) return { value: { exitCode: 1, stdout: '', stderr: `no fixture for ${key}` } }
    return { value: typeof answer === 'string' ? { exitCode: 0, stdout: answer, stderr: '' } : answer }
  }
}

const OPEN_DE_1 = {
  'task-clock.sh --status --json': '{"OPEN_TASKS":"DE-1","OPEN_COUNT":"1"}',
  'task-clock.sh --task DE-1 --status --json': '{"TASK":"DE-1","RUNNING":"true","STARTED_AT":"2026-10-07 09:18","TOTAL_MINUTES":""}',
}
const NONE_OPEN = { 'task-clock.sh --status --json': '{"OPEN_TASKS":"","OPEN_COUNT":"0"}' }

const BAND = {
  plugin: 'dev-setup',
  component: 'AbovePrompt',
  requestId: 'band',
  viewport: { columns: 120, rows: 40 },
  props: { hasSurvey: false, isWorking: false, maxRows: 8, bodyColumns: 110, scroll: { offset: 0, bodyRows: 8 }, view: {} },
  surface: 'terminal',
} as const

const PANE = {
  plugin: 'dev-setup',
  component: 'Pane',
  requestId: 'dev-setup',
  viewport: { columns: 120, rows: 40 },
  props: { title: 'dev-setup', isFocused: true, bodyColumns: 100, placement: 'inline', scroll: { offset: 0, bodyRows: 20 }, view: {} },
  surface: 'terminal',
} as const

const SDD_SKILL = `---
name: sdd
description: Runs the interactive flow. Use when the work is bigger than a quick fix.
argument-hint: "[TASK_ID]"
user-invocable: true
disable-model-invocation: true
---
`
const DEV_SKILL = `---
name: sdd-dev
description: Implements a spec. Use when a spec is approved.
user-invocable: false
---
`

type Recorders = { opened?: unknown[]; toasts?: string[]; registered?: unknown[]; filled?: string[] }

/** The stubs every test needs — session start, registration, the render chain,
 * the clock — with optional recorders for what the mod asked of the engine. */
function baseline(on: (name: string, ...rest: unknown[]) => unknown, rec: Recorders = {}) {
  on('session.start', () => ({ cwd: '/work' }))
  on('command.register', ($: unknown, e: unknown) => {
    rec.registered?.push(e)
    return { value: undefined }
  })
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['drawn by Claude Code'] }))
  on('ui.open', ($: unknown, e: unknown) => {
    rec.opened?.push(e)
    return { value: undefined }
  })
  on('ui.toast', ($: unknown, e: { text: string }) => {
    rec.toasts?.push(e.text)
    return { value: undefined }
  })
  on('prompt.fill', ($: unknown, e: { text: string }) => {
    rec.filled?.push(e.text)
    return { isFilled: true }
  })
  return mock.clock(on, { now: NOW })
}

describe('the command', () => {
  test('is registered at session start, immediate', async ($, on) => {
    const registered: unknown[] = []
    baseline(on, { registered })
    await $.session.start({ surface: null, isInteractive: false, cwd: '/work' })
    expect(registered.length).toBe(1)
    expect(registered[0]).toMatchObject({ name: 'dev-setup', immediate: true })
  })

  test('off the terminal answers in plain text: what this session changed, read with git in the session directory', async ($, on) => {
    const calls: string[] = []
    const startedAt = NOW - 30 * 60_000
    baseline(on)
    on('session.usage', () => ({ value: { startedAt, context: { tokens: 1000, window: 200000, percent: 1 }, rateLimits: [] } }))
    on('fs.stat', ($, e: { path: string }) => {
      const mtimes: Record<string, number> = { '/repo/src/a.ts': startedAt + 60_000, '/repo/src/old.ts': startedAt - 60_000 }
      const mtimeMs = mtimes[e.path]
      return mtimeMs === undefined ? { deny: 'ENOENT' } : { value: { kind: 'file', size: 1, mtimeMs, isLink: false } }
    })
    const since = `--since=@${Math.floor(startedAt / 1000)}`
    on(
      'process.run',
      scripts(
        {
          'git rev-parse --show-toplevel': '/repo\n',
          'git status --porcelain=v1 -z --untracked-files=all': ' M src/a.ts\0 M src/old.ts\0',
          [`git log ${since} --format=%h%x09%s HEAD`]: 'abc1234\tfeat: x\n',
          [`git log ${since} --name-only --format= HEAD`]: '\nsrc/b.ts\n',
        },
        calls,
      ),
    )
    await $.session.start({ surface: null, isInteractive: false, cwd: '/work' })
    const answer = await $.command.run({ command: 'dev-setup', args: 'status', origin: { kind: 'sdk' } })
    expect((answer.text ?? '').split('\n').map((line) => line.replace(/\s+/g, ' ').trimEnd())).toEqual([
      'Branch feat/DE-1_x',
      'Session since 09:30 1 commit · 2 files',
      '',
      'Commits',
      ' abc1234 feat: x',
      '',
      'Not committed 1',
      ' modified src/a.ts',
      '',
      'Committed 1',
      ' committed src/b.ts',
    ])
    expect(calls.every((call) => call.endsWith('@/work'))).toBe(true)
    expect(calls.some((call) => call.includes('check-prerequisites.sh'))).toBe(false)
  })

  test('an unknown view names the views', async ($, on) => {
    baseline(on)
    await $.session.start({ surface: null, isInteractive: false, cwd: '/work' })
    const answer = await $.command.run({ command: 'dev-setup', args: 'weather', origin: { kind: 'sdk' } })
    expect(answer.text).toContain('Views: clock, status, context, usage, runs')
  })

  test('a failing or unfinished script is one line naming it', async ($, on) => {
    baseline(on)
    on('session.usage', () => ({ value: { startedAt: NOW, context: { tokens: 1000, window: 200000, percent: 1 }, rateLimits: [] } }))
    on('process.run', ($, e: { argv: readonly string[] }) =>
      e.argv[1]?.endsWith('task-clock.sh')
        ? { deny: 'timed out' }
        : { value: { exitCode: 2, stdout: '', stderr: 'fatal: not a git repository\n' } },
    )
    await $.session.start({ surface: null, isInteractive: false, cwd: '/work' })
    const status = await $.command.run({ command: 'dev-setup', args: 'status', origin: { kind: 'sdk' } })
    expect(status.text?.split('\n')[1]).toBe('git rev-parse exited 2: fatal: not a git repository')
    const clock = await $.command.run({ command: 'dev-setup', args: 'clock', origin: { kind: 'sdk' } })
    expect(clock.text).toContain('task-clock.sh did not finish')
  })

  test('in an interactive session opens the pane and adds nothing to the transcript', async ($, on) => {
    const opened: unknown[] = []
    baseline(on, { opened })
    on('process.run', scripts(OPEN_DE_1))
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
    const answer = await $.command.run({ command: 'dev-setup', args: 'clock', origin: { kind: 'composer' } })
    expect(answer.text).toBeUndefined()
    expect(opened[0]).toMatchObject({ id: 'dev-setup', focus: true, closeOnEscape: true })
  })
})

describe('the catalogue', () => {
  test('lists exactly the user-invocable skills, read at run time', async ($, on) => {
    baseline(on)
    on('fs.list', () => ({
      value: [
        { name: 'sdd', kind: 'dir', size: 0, isLink: false },
        { name: 'sdd-dev', kind: 'dir', size: 0, isLink: false },
        { name: 'brand-new', kind: 'dir', size: 0, isLink: false },
        { name: 'README.md', kind: 'file', size: 10, isLink: false },
      ],
    }))
    on('fs.read', ($, e: { path: string }) => ({
      value: e.path.endsWith('sdd-dev/SKILL.md')
        ? DEV_SKILL
        : e.path.includes('brand-new')
          ? SDD_SKILL.replace('name: sdd', 'name: brand-new')
          : SDD_SKILL,
    }))
    await $.session.start({ surface: null, isInteractive: false, cwd: '/work' })
    const answer = await $.command.run({ command: 'dev-setup', args: '', origin: { kind: 'sdk' } })
    expect(answer.text).toMatch(/\/dev-setup:\n  sdd\s+Runs the interactive flow\./)
    expect(answer.text).toMatch(/when\s+the work is bigger than a quick fix\./)
    expect(answer.text).toMatch(/takes\s+\[TASK_ID\]  outward-facing · started only by you/)
    expect(answer.text?.includes('sdd-dev')).toBe(false)
    // A skill added to the plugin shows up with no change to the mod.
    expect(answer.text).toMatch(/\/dev-setup:\n  brand-new\s+Runs/)
  })

  test('the use button fills the prompt and never sends it', async ($, on) => {
    const filled: string[] = []
    const submitted: string[] = []
    baseline(on, { filled })
    on('fs.list', () => ({ value: [{ name: 'sdd', kind: 'dir', size: 0, isLink: false }] }))
    on('fs.read', () => ({ value: SDD_SKILL }))
    on('prompt.submit', ($, e: { text: string }) => {
      submitted.push(e.text)
      return { text: e.text }
    })
    on('process.run', scripts(NONE_OPEN))
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
    await $.command.run({ command: 'dev-setup', args: '', origin: { kind: 'composer' } })
    const ui = await $.ui.mount(PANE)
    await ui.press({ key: 'use-sdd' })
    expect(filled).toEqual(['/dev-setup:sdd '])
    expect(submitted).toEqual([])
  })
})

describe('the band', () => {
  test('shows an open clock without anything invoked, beside what others draw', async ($, on) => {
    baseline(on)
    on('process.run', scripts(OPEN_DE_1))
    on('tool.call', () => ({ result: { stdout: '', stderr: '' } }))
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
    await $.tool.call({ tool: 'Bash', command: 'bash scripts/task-clock.sh --task DE-1 --start --json' })
    const ui = await $.ui.mount(BAND)
    expect(await ui.find({ type: 'Text', text: 'DE-1' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'in progress' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '42m' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'drawn by Claude Code' })).toBeDefined()
  })

  test('with no clock open draws nothing of its own', async ($, on) => {
    baseline(on)
    on('process.run', scripts(NONE_OPEN))
    on('tool.call', () => ({ result: { stdout: '', stderr: '' } }))
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
    await $.tool.call({ tool: 'Bash', command: 'bash scripts/task-clock.sh --status --json' })
    const ui = await $.ui.mount(BAND)
    expect(await ui.find({ type: 'Text', text: /in progress/ })).toBeUndefined()
  })

  test('warns once the context reaches 70%', async ($, on) => {
    baseline(on)
    on('process.run', scripts(NONE_OPEN))
    on('session.measure', ($, e: { changed: readonly string[] }) => ({ changed: e.changed }))
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
    await $.session.measure({ context: { tokens: 150000, window: 200000, percent: 75 }, rateLimits: [], changed: ['context'] })
    const ui = await $.ui.mount(BAND)
    expect(await ui.find({ type: 'Text', text: /^context 75%/ })).toBeDefined()
  })
})

describe('the merge-request button', () => {
  test('appears after a created merge request, fills the closure, and passes the call through', async ($, on) => {
    const filled: string[] = []
    const answered = { result: { stdout: 'https://github.com/a/b/pull/9\n', stderr: '' } }
    baseline(on, { filled })
    on('process.run', scripts(OPEN_DE_1))
    on('tool.call', () => answered)
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
    const out = await $.tool.call({ tool: 'Bash', command: 'gh pr create --base next --title "feat: x [DE-1]"' })
    expect(out).toEqual(answered)
    const ui = await $.ui.mount(BAND)
    await ui.press({ key: 'close-DE-1' })
    expect(filled.length).toBe(1)
    expect(filled[0]).toContain('https://github.com/a/b/pull/9')
    expect(filled[0]).toContain('task-clock.sh" --task DE-1 --stop --json')
    expect(filled[0]).toContain('reference/clickup-contract.md')
  })

  test('goes away once the clock it would close is stopped', async ($, on) => {
    let stopped = false
    const table = scripts(OPEN_DE_1)
    baseline(on)
    on('process.run', ($: unknown, e: { argv: readonly string[]; init?: { cwd?: string } }) =>
      stopped && e.argv[0] !== 'git' ? { value: { exitCode: 0, stdout: '{"OPEN_TASKS":"","OPEN_COUNT":"0"}', stderr: '' } } : table($, e),
    )
    on('tool.call', ($: unknown, e: { command: string }) => ({
      result: { stdout: e.command.startsWith('gh pr create') ? 'https://github.com/a/b/pull/9' : '', stderr: '' },
    }))
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
    await $.tool.call({ tool: 'Bash', command: 'gh pr create --fill' })
    const before = await $.ui.mount(BAND)
    expect(await before.find({ key: 'close-DE-1' })).toBeDefined()
    await before.unmount()
    stopped = true
    await $.tool.call({ tool: 'Bash', command: 'bash scripts/task-clock.sh --task DE-1 --stop --json' })
    const after = await $.ui.mount(BAND)
    expect(await after.find({ key: 'close-DE-1' })).toBeUndefined()
  })

  test('does not appear for a create that printed no URL, or a quoted mention', async ($, on) => {
    baseline(on)
    on('process.run', scripts(OPEN_DE_1))
    on('tool.call', () => ({ result: { stdout: 'a pull request already exists', stderr: '' } }))
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
    await $.tool.call({ tool: 'Bash', command: 'gh pr create --fill' })
    await $.tool.call({ tool: 'Bash', command: 'git commit -m "then gh pr create https://x/pull/1"' })
    const ui = await $.ui.mount(BAND)
    expect(await ui.find({ key: 'close-DE-1' })).toBeUndefined()
  })
})

describe('per-phase usage', () => {
  test('charges each request and the time to the phase of the skill last expanded, and passes everything through', async ($, on) => {
    const saved = new Map<string, unknown>()
    let cost = 1
    const clock = baseline(on)
    on('process.run', scripts(NONE_OPEN))
    on('session.id', () => ({ value: 's1' }))
    on('session.usage', () => ({ value: { context: { tokens: 1000, window: 200000, percent: 1 }, rateLimits: [], cost: { usd: cost } } }))
    on('store.get', ($, e: { key: string }) => ({ value: saved.get(e.key) }))
    on('store.set', ($, e: { key: string; value: unknown }) => {
      saved.set(e.key, e.value)
      return { value: undefined }
    })
    on('store.delete', () => ({ value: undefined }))
    on('skill.prompt', ($, e: { text: string }) => ({ text: e.text }))
    on('turn.start', ($, e: { turnId: string }) => ({ turnId: e.turnId }))
    on('turn.complete', () => ({ text: 'ok' }))
    on('turn.step', async function* ($, e: { turnId: string; index: number }) {
      yield { kind: 'text', index: 0, text: 'ok' }
      cost += 0.25
      return {
        turnId: e.turnId,
        index: e.index,
        answer: 'ok',
        toolUses: [],
        stopReason: 'end_turn',
        usage: { input_tokens: 100, output_tokens: 50, cache_read_input_tokens: 1000, cache_creation_input_tokens: 0, model: 'claude-test' },
      }
    })
    await $.session.start({ surface: null, isInteractive: false, cwd: '/work' })

    const step = async (index: number) => {
      const stream = $.turn.step({ turnId: 't1', index, model: 'claude-test', messageCount: 1 })
      let item = await stream.next()
      while (item.done !== true) item = await stream.next()
      return item.value
    }

    const complete = (turnId: string) =>
      $.turn.complete({ turnId, answer: 'ok', durationMs: 0, isAborted: false, reason: 'answer' } as Parameters<typeof $.turn.complete>[0])

    // One turn: intake, then discovery, which asks and ends the turn.
    await $.turn.start({ text: '/dev-setup:sdd DE-1', turnId: 't1' })
    const expanded = await $.skill.prompt({ skill: 'dev-setup:sdd', text: 'the sdd skill' })
    expect(expanded).toEqual({ text: 'the sdd skill' })
    await step(0)
    await clock.advance(2 * 60_000)
    await $.skill.prompt({ skill: 'dev-setup:sdd-discovery', text: 'discovery' })
    const last = await step(1)
    expect(last.answer).toBe('ok')
    await clock.advance(60_000)
    await complete('t1')
    // The developer takes five minutes to answer; then a subagent works for one.
    await clock.advance(5 * 60_000)
    await $.turn.start({ text: 'the answers', turnId: 't2' })
    const sub = $.turn.step({ turnId: 't2', index: 0, model: 'claude-test', messageCount: 1, agentId: 'a1' })
    let item = await sub.next()
    while (item.done !== true) item = await sub.next()
    await clock.advance(60_000)
    await complete('t2')

    const answer = await $.command.run({ command: 'dev-setup', args: 'usage', origin: { kind: 'sdk' } })
    const rows = (answer.text ?? '').split('\n').map((row) => row.replace(/\s+/g, ' ').trimEnd())
    expect(rows[0]).toBe('sdd usage 3.5k tokens · $0.75 · 9m (4m working, 5m waiting)')
    expect(rows.find((row) => row.startsWith('intake '))).toBe('intake 2m 2m 1 1.1k ███░░░░░░░ 33% 91% 50 $0.25')
    expect(rows.find((row) => row.startsWith('discovery '))).toBe('discovery ● 7m 2m 2 2.3k ███████░░░ 67% 91% 100 $0.50')
    expect(rows).toContain(' subagents 1.1k ███░░░░░░░ 33% 1 request')
    expect(rows).toContain(' claude-test 3.5k ██████████ 100%')
    expect(saved.get('usage:index')).toEqual([`usage:s1:${NOW}`])
  })
})

describe('the runs', () => {
  test('a launch adds a run, opens the pane once, and its notification sets the outcome', async ($, on) => {
    const opened: unknown[] = []
    const toasts: string[] = []
    const filled: string[] = []
    const launched = { result: { status: 'async_launched', taskId: 'bg-1', runId: 'wf_1' } }
    baseline(on, { opened, toasts, filled })
    on('process.run', scripts(NONE_OPEN))
    on('tool.call', () => launched)
    on('prompt.submit', ($, e: { text: string }) => ({ text: e.text }))
    await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })

    const out = await $.tool.call({ tool: 'Workflow', name: 'dev-setup:auto-sdd', args: { taskId: 'DE-5', title: 'A task' } })
    expect(out).toEqual(launched)
    await $.tool.call({ tool: 'Workflow', name: 'dev-setup:auto-sdd', args: { taskId: 'DE-6', title: 'Another' } })
    expect(opened.length).toBe(1)
    expect(toasts[0]).toContain('/dev-setup runs')

    const note = '<task-notification><task-id>bg-1</task-id><status>completed</status><result>{"status":"failed","reason":"verify failed"}</result></task-notification>'
    const passed = await $.prompt.submit({ text: note, wait: false, origin: { kind: 'task-notification' } })
    expect(passed).toEqual({ text: note })

    const ui = await $.ui.mount(PANE)
    expect(await ui.find({ type: 'Text', text: 'DE-5' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'failed' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'verify failed' })).toBeDefined()
    await ui.press({ key: 'resume-DE-5' })
    expect(filled.length).toBe(1)
    expect(filled[0]).toContain('resumeFromRunId "wf_1"')
  })
})

describe('the context view', () => {
  test('shows the total, the split and the dev-setup share', async ($, on) => {
    baseline(on)
    on('session.usage', () => ({
      value: {
        context: {
          tokens: 42000,
          window: 200000,
          percent: 21,
          breakdown: {
            categories: [{ name: 'Memory files', tokens: 900, kind: 'used' }],
            memoryFiles: [{ path: '/work/.claude/rules/dev-setup-core.md', type: 'Project', tokens: 900 }],
            agents: [],
            mcpTools: [],
          },
        },
        rateLimits: [],
      },
    }))
    on('fs.read', () => ({ value: '{"mcpServers":{}}' }))
    await $.session.start({ surface: null, isInteractive: false, cwd: '/work' })
    const answer = await $.command.run({ command: 'dev-setup', args: 'context', origin: { kind: 'sdk' } })
    expect(answer.text).toContain('Context  42.0k of 200.0k tokens  21%')
    expect(answer.text).toContain("Split by category (Claude Code's estimate)")
    expect(answer.text).toContain('rules (dev-setup-core.md)')
  })

  test('says the split is unavailable when the client gives none', async ($, on) => {
    baseline(on)
    on('session.usage', () => ({ value: { context: { tokens: 1000, window: 200000, percent: 1 }, rateLimits: [] } }))
    on('fs.read', () => ({ deny: 'no such file' }))
    await $.session.start({ surface: null, isInteractive: false, cwd: '/work' })
    const answer = await $.command.run({ command: 'dev-setup', args: 'context', origin: { kind: 'sdk' } })
    expect(answer.text).toContain('unavailable on this client')
  })
})

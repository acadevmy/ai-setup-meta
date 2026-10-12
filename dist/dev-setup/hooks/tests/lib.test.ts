// lib.test.ts — the mod's pure helpers, without the engine.

import { describe, expect, test } from 'claude-code/testing'
import { clockDetail, clockLine, elapsedMinutes, formatDuration, formatTime, openTasks, parseLocalStamp, toOpenClock } from '../lib/clock.ts'
import { closurePrompt, closureTask, isMergeRequestCreate, mergeRequestUrl, toolOutputText } from '../lib/merge-request.ts'
import { parseFrontmatter, sortEntries, splitDescription, toEntry, useText } from '../lib/catalogue.ts'
import type { CatalogueEntry } from '../lib/catalogue.ts'
import { addRequest, compactLine, compactRow, newRecord, phaseOf, pruneIndex, toIndex, usageTable, withTask } from '../lib/usage.ts'
import { addRun, applyNotification, attachMergeRequest, canResume, parseNotification, resumePrompt, runFromWorkflowCall } from '../lib/runs.ts'
import type { Run } from '../lib/runs.ts'
import { contextLines, contextTone, contextWarning, devSetupShare, mcpServerNames } from '../lib/context.ts'
import { catalogueLines, parseView, relativeTo, runLine, scriptOutcome, statusView, unknownViewText, worktreesView } from '../lib/views.ts'
import { columns, dim, field, meter, rowText, span } from '../lib/rows.ts'
import { drawRow, linkable } from '../lib/draw.ts'
import type { Ui } from '../lib/draw.ts'

const AT_10_00 = new Date(2026, 9, 7, 10, 0).getTime()

describe('clock', () => {
  test('open tasks come from OPEN_TASKS, space separated', async () => {
    expect(openTasks({ OPEN_TASKS: 'DE-1 DE-22' })).toEqual(['DE-1', 'DE-22'])
    expect(openTasks({ OPEN_TASKS: '' })).toEqual([])
  })

  test('a running clock becomes an open clock; a stopped one does not', async () => {
    expect(toOpenClock({ TASK: 'DE-1', RUNNING: 'true', STARTED_AT: '2026-10-07 09:18', TOTAL_MINUTES: '' })).toEqual({
      task: 'DE-1',
      startMs: new Date(2026, 9, 7, 9, 18).getTime(),
      closedMinutes: 0,
      sessions: 0,
    })
    expect(toOpenClock({ TASK: 'DE-1', RUNNING: 'false', STARTED_AT: '' })).toBe(null)
  })

  test('elapsed adds the open interval to the closed ones', async () => {
    const clock = { task: 'DE-1', startMs: new Date(2026, 9, 7, 9, 18).getTime(), closedMinutes: 30, sessions: 1 }
    expect(parseLocalStamp('2026-10-07 09:18')).toBe(new Date(2026, 9, 7, 9, 18).getTime())
    expect(parseLocalStamp('yesterday')).toBe(null)
    expect(elapsedMinutes(clock, AT_10_00)).toBe(72)
    expect(clockLine(clock, AT_10_00)).toBe('DE-1  in progress  1h 12m')
    expect(formatTime(clock.startMs)).toBe('09:18')
    expect(rowText(clockDetail(clock))).toBe('since 09:18 · 1 earlier session, 30m')
    expect(rowText(clockDetail({ ...clock, startMs: null, sessions: 0 }))).toBe('')
  })

  test('durations read like task-clock.sh writes them', async () => {
    expect(formatDuration(0)).toBe('0m')
    expect(formatDuration(42)).toBe('42m')
    expect(formatDuration(120)).toBe('2h')
    expect(formatDuration(135)).toBe('2h 15m')
  })
})

describe('merge request', () => {
  test('a gh pr create or glab mr create is one, wherever it sits in the line', async () => {
    expect(isMergeRequestCreate('gh pr create --base next --title "x"')).toBe(true)
    expect(isMergeRequestCreate('git push -u origin b && gh pr create --fill')).toBe(true)
    expect(isMergeRequestCreate('GH_TOKEN=x gh pr create -R a/b')).toBe(true)
    expect(isMergeRequestCreate('glab mr create --target-branch next')).toBe(true)
  })

  test('a mention inside quotes, a list or a view is not', async () => {
    expect(isMergeRequestCreate('git commit -m "run gh pr create later"')).toBe(false)
    expect(isMergeRequestCreate('gh pr list')).toBe(false)
    expect(isMergeRequestCreate('gh pr view 12')).toBe(false)
  })

  test('the scan is line by line, like the hook: a create on its own line of a multi-line body counts', async () => {
    expect(isMergeRequestCreate('gh pr edit 12 --body "Summary\ngh pr create --fill\nend"')).toBe(true)
    expect(isMergeRequestCreate('gh pr edit 12 --body "Summary: run gh pr create later"')).toBe(false)
  })

  test('the URL is the proof, from either host', async () => {
    expect(mergeRequestUrl('Creating pull request\nhttps://github.com/a/b/pull/42\n')).toBe('https://github.com/a/b/pull/42')
    expect(mergeRequestUrl('https://gitlab.com/g/p/-/merge_requests/7')).toBe('https://gitlab.com/g/p/-/merge_requests/7')
    expect(mergeRequestUrl('a pull request already exists')).toBe(null)
    expect(toolOutputText({ stdout: 'https://github.com/a/b/pull/1', stderr: '' })).toContain('/pull/1')
  })

  test('the task is the one named between delimiters, else the only one open', async () => {
    expect(closureTask(['DE-81', 'DE-811'], 'feat/DE-811_x', 'gh pr create')).toBe('DE-811')
    expect(closureTask(['DE-81'], 'main', 'gh pr create')).toBe('DE-81')
    expect(closureTask(['DE-1', 'DE-2'], 'main', 'gh pr create')).toBe(null)
    const prompt = closurePrompt('DE-1', 'https://x/pull/1', '/plugin')
    expect(prompt).toContain('bash "/plugin/scripts/task-clock.sh" --task DE-1 --stop --json')
    expect(prompt).toContain('/plugin/reference/clickup-contract.md')
  })
})

const SDD_SKILL = `---
name: sdd
description: Runs the interactive Spec-Driven Development flow for a task — discovery, spec, one approval. Use when the work touches more than three files.
effort: medium
argument-hint: "[TASK_ID] [--worktree]"
user-invocable: true
disable-model-invocation: true
---

# SDD
`

const DEV_SKILL = `---
name: sdd-dev
description: >
  Implements an approved spec step by step.
  Use when a spec is approved.
user-invocable: false
---
`

const SDD_ENTRY = toEntry('dev-setup', 'sdd', parseFrontmatter(SDD_SKILL)) as CatalogueEntry

describe('catalogue', () => {
  test('the frontmatter is read field by field, folded blocks joined', async () => {
    const fields = parseFrontmatter(SDD_SKILL)
    expect(fields['argument-hint']).toBe('[TASK_ID] [--worktree]')
    expect(fields['user-invocable']).toBe('true')
    expect(parseFrontmatter(DEV_SKILL).description).toBe('Implements an approved spec step by step. Use when a spec is approved.')
    expect(parseFrontmatter('# no frontmatter')).toEqual({})
  })

  test('only a user-invocable skill becomes a row, with what, when, input and the outward mark', async () => {
    expect(SDD_ENTRY).toMatchObject({
      prefix: '/dev-setup:',
      command: '/dev-setup:sdd',
      when: 'the work touches more than three files.',
      input: '[TASK_ID] [--worktree]',
      outward: true,
    })
    expect(toEntry('dev-setup', 'sdd-dev', parseFrontmatter(DEV_SKILL))).toBe(null)
    expect(splitDescription('No routing sentence.')).toEqual({ what: 'No routing sentence.', when: '' })
  })

  test('the use text is the command and a space, and rows sort by name', async () => {
    expect(useText(SDD_ENTRY)).toBe('/dev-setup:sdd ')
    const other = { ...SDD_ENTRY, name: 'auto-sdd', command: '/dev-setup:auto-sdd' }
    expect(sortEntries([SDD_ENTRY, other]).map((row) => row.name)).toEqual(['auto-sdd', 'sdd'])
  })
})

describe('usage', () => {
  test('the plugin skills and the built-in simplify map to phases; others to none', async () => {
    expect(phaseOf('dev-setup:sdd-discovery')).toBe('discovery')
    expect(phaseOf('dev-setup:sdd')).toBe('intake')
    expect(phaseOf('dev-setup:verify')).toBe('closure')
    expect(phaseOf('simplify')).toBe('closure')
    expect(phaseOf('other-plugin:review')).toBe(null)
    expect(phaseOf('sdd')).toBe(null)
  })

  test('requests accumulate per phase, cost deltas never negative', async () => {
    const usage = { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 1000, cache_creation_input_tokens: 200 }
    let record = newRecord('usage:s1:1', '/w', 1)
    record = addRequest(record, 'discovery', usage, 0.1)
    record = addRequest(record, 'discovery', usage, -1)
    record = addRequest(record, 'spec', null, 0.05)
    record = withTask(record, 'DE-1')
    expect(record.phases.discovery).toEqual({ requests: 2, input: 20, output: 10, cacheRead: 2000, cacheWrite: 400, costUsd: 0.1 })
    expect(record.phases.spec?.requests).toBe(1)
    expect(compactLine(record)).toBe('sdd DE-1  discovery 2.4k › spec 0  $0.15')
    // The phase in progress is the one span at full strength.
    expect(compactRow(record, 'spec').filter((cell) => cell.bold).map((cell) => cell.text)).toEqual(['spec 0', '$0.15'])
    const table = usageTable(record)
    expect(table[0]).toBe('sdd usage — DE-1')
    expect(table[1]).toMatch(/^phase\s+requests\s+input\s+cache read\s+cache write\s+output\s+cost$/)
    expect(table.some((line) => /^total\s+3\s+20\s+2\.0k\s+400\s+10\s+\$0\.15$/.test(line))).toBe(true)
  })

  test('the index keeps the newest keys and names the dropped ones', async () => {
    const index = Array.from({ length: 20 }, (_, i) => `k${i}`)
    const pruned = pruneIndex(index, 'new')
    expect(pruned.index.length).toBe(20)
    expect(pruned.index[19]).toBe('new')
    expect(pruned.dropped).toEqual(['k0'])
    expect(pruneIndex(['a', 'b'], 'a').index).toEqual(['b', 'a'])
    expect(toIndex(['a', 3, 'b'])).toEqual(['a', 'b'])
    expect(toIndex('nope')).toEqual([])
  })
})

const RUN: Run = {
  taskId: 'DE-5',
  title: 'A task',
  backgroundId: 'wf-bg-1',
  runId: 'wf_abc123',
  startedAt: AT_10_00,
  state: 'running',
  reason: '',
  branch: '',
  mergeRequest: '',
}

describe('runs', () => {
  test('only a dev-setup:auto-sdd Workflow call starts a run', async () => {
    const input = { tool: 'Workflow', name: 'dev-setup:auto-sdd', args: { taskId: 'DE-5', title: 'A task' } }
    const result = { status: 'async_launched', taskId: 'wf-bg-1', runId: 'wf_abc123' }
    expect(runFromWorkflowCall(input, result, AT_10_00)).toEqual(RUN)
    expect(runFromWorkflowCall({ name: 'other' }, result, AT_10_00)).toBe(null)
  })

  test('a notification closes its run with the outcome; an unrelated one changes nothing', async () => {
    const ready = parseNotification(
      '<task-notification><task-id>wf-bg-1</task-id><status>completed</status><result>{"status":"ready-for-mr","taskId":"DE-5","branch":"feat/DE-5_a"}</result></task-notification>',
    )
    expect(ready?.state).toBe('ready-for-mr')
    const closed = applyNotification([RUN], ready!)
    expect(closed[0].state).toBe('ready-for-mr')
    expect(closed[0].branch).toBe('feat/DE-5_a')
    const reviewed = parseNotification(
      '<task-id>wf-bg-1</task-id><status>completed</status><result>{"openPoints":[{"reason":"REQ-3 duplicates ADR-2"}],"status":"failed","reason":"the quality commands did not pass"}</result>',
    )
    expect(applyNotification([RUN], reviewed!)[0].reason).toBe('the quality commands did not pass')
    const failed = parseNotification('<task-id>wf-bg-1</task-id><status>completed</status><result>{"status": "failed", "reason": "verify failed"}</result>')
    expect(applyNotification([RUN], failed!)[0]).toMatchObject({ state: 'failed', reason: 'verify failed' })
    const killed = parseNotification('<task-id>wf-bg-1</task-id><status>killed</status>')
    expect(applyNotification([RUN], killed!)[0].state).toBe('killed')
    const other = parseNotification('<task-id>shell-9</task-id><status>completed</status>')
    expect(applyNotification([RUN], other!)).toEqual([RUN])
    expect(parseNotification('just a prompt')).toBe(null)
  })

  test('the list keeps five runs and one per task; a merge request attaches by task or branch', async () => {
    let runs: Run[] = []
    for (let i = 1; i <= 6; i += 1) runs = addRun(runs, { ...RUN, taskId: `DE-${i}` })
    expect(runs.map((run) => run.taskId)).toEqual(['DE-2', 'DE-3', 'DE-4', 'DE-5', 'DE-6'])
    const attached = attachMergeRequest([RUN], 'gh pr create --title "feat: x [DE-5]"', 'https://x/pull/3')
    expect(attached[0].mergeRequest).toBe('https://x/pull/3')
  })

  test('a failed or killed run with a run id can be resumed', async () => {
    expect(canResume(RUN)).toBe(false)
    expect(canResume({ ...RUN, state: 'failed' })).toBe(true)
    expect(canResume({ ...RUN, state: 'failed', runId: '' })).toBe(false)
    expect(resumePrompt(RUN)).toContain('resumeFromRunId "wf_abc123"')
  })
})

describe('context', () => {
  test('the share reads rules, skills, agents and the setup MCP servers by name', async () => {
    const breakdown = {
      categories: [
        { name: 'System prompt', tokens: 3000, kind: 'used' },
        { name: 'Free space', tokens: 100000, kind: 'free' },
      ],
      memoryFiles: [
        { path: '/p/.claude/rules/dev-setup-core.md', tokens: 900 },
        { path: '/p/.claude/rules/team-own.md', tokens: 400 },
        { path: '/p/CLAUDE.md', tokens: 100 },
      ],
      skills: { skillFrontmatter: [{ name: 'dev-setup:sdd', pluginName: 'dev-setup', tokens: 80 }, { name: 'other', tokens: 50 }] },
      agents: [{ agentType: 'dev-setup:clickup', tokens: 60 }],
      mcpTools: [{ name: 'mcp__clickup__get', serverName: 'clickup', tokens: 120 }],
    }
    const share = devSetupShare(breakdown, mcpServerNames('{"mcpServers":{"clickup":{}}}'))
    expect(share).toEqual([
      { label: 'rules (dev-setup-core.md)', tokens: 900 },
      { label: 'skills (1)', tokens: 80 },
      { label: 'agents (1)', tokens: 60 },
      { label: 'MCP clickup (1 tools)', tokens: 120 },
    ])
    const lines = contextLines({ tokens: 42000, window: 200000, percent: 21 }, breakdown, share)
    expect(lines[0]).toBe('Context  42.0k of 200.0k tokens  21%')
    expect(lines[1]).toBe(`${'█'.repeat(6)}${'░'.repeat(24)}`)
    expect(lines.some((line) => line.includes('Free space'))).toBe(false)
    expect(lines.some((line) => /^dev-setup share\s+1\.2k$/.test(line))).toBe(true)
    // The figures line up: every token column ends on the same cell.
    const figures = lines.slice(3).map((line) => line.length)
    expect(new Set(figures).size).toBe(1)
    expect(contextTone(21)).toBe('good')
    expect(contextTone(70)).toBe('warn')
    expect(contextTone(90)).toBe('bad')
  })

  test('without a breakdown the total stands alone; the warning starts at 70%', async () => {
    expect(contextLines({ tokens: 1000, window: 200000, percent: 1 }, undefined, [])[2]).toContain('unavailable on this client')
    expect(contextLines({ window: 200000 }, undefined, [])).toEqual(['Context  no response measured yet'])
    expect(mcpServerNames('not json')).toEqual([])
    expect(contextWarning(69)).toBe(null)
    expect(contextWarning(70)).toContain('context 70%')
    expect(contextWarning(undefined)).toBe(null)
  })
})

describe('views', () => {
  test('arguments route to views; nothing is the catalogue; anything else is refused', async () => {
    expect(parseView('')).toBe('commands')
    expect(parseView(' Clock ')).toBe('clock')
    expect(parseView('nope')).toBe(null)
    expect(unknownViewText('nope')).toContain('clock, status, worktrees, context, usage, runs')
  })

  test('a failed script is one line naming it; JSON that is not JSON says so', async () => {
    expect(scriptOutcome('check-prerequisites.sh', 2, '', 'fatal: not a git repository\n')).toEqual({
      ok: false,
      script: 'check-prerequisites.sh',
      line: 'check-prerequisites.sh exited 2: fatal: not a git repository',
    })
    const garbled = scriptOutcome('worktree-info.sh', 0, 'oops', '')
    expect(garbled.ok).toBe(false)
  })

  test('empty values read none or not set, never blank', async () => {
    const status = statusView(scriptOutcome('check-prerequisites.sh', 0, '{"BRANCH":"main","SPEC":"","BASE_BRANCH":"","CHANGED_FILES":""}', ''))
    expect(status.map((line) => line.replace(/\s+/g, ' '))).toEqual(['Branch main', 'Base not set', 'Spec none', 'Changed nothing'])
    // The values start on one column, whatever the label.
    expect(new Set(status.map((line) => line.length - line.replace(/^\S+\s+/, '').length)).size).toBe(1)
    const withSpec = statusView(scriptOutcome('check-prerequisites.sh', 0, '{"SPEC":"/w/.specs/DE-1-x.md","SPEC_STATUS":"approved"}', ''), '/w')
    expect(withSpec[2]).toMatch(/^Spec\s+\.specs\/DE-1-x\.md  approved$/)
    const many = statusView(scriptOutcome('check-prerequisites.sh', 0, `{"CHANGED_FILES":"${Array.from({ length: 17 }, (_, i) => `f${i}.ts`).join('\\n')}"}`, ''))
    expect(many[3]).toMatch(/^Changed\s+17 files$/)
    expect(many[4]).toBe('  f0.ts')
    expect(many[many.length - 1]).toBe('  … 2 more')
    expect(relativeTo('/w', '/elsewhere/a.md')).toBe('/elsewhere/a.md')
    const worktrees = worktreesView(
      scriptOutcome('worktree-info.sh', 0, '{"WORKTREE":"/w","WORKTREE_INDEX":"0","PORT_OFFSET":"0","WORKTREES":"/w\\tmain","OVERLAPS":""}', ''),
    )
    expect(worktrees.map((line) => line.replace(/\s+/g, ' '))).toEqual(['Here /w index 0 · port offset +0', 'Worktrees', ' main /w', 'Overlaps none'])
    const overlapping = worktreesView(
      scriptOutcome('worktree-info.sh', 0, '{"WORKTREE":"/w","WORKTREES":"/w\\tmain\\n/w2\\t","OVERLAPS":"src/a.ts\\tfeat/x,feat/y"}', ''),
    )
    expect(overlapping).toContain('  (detached)  /w2')
    expect(overlapping.some((line) => /^Overlaps\s+1$/.test(line))).toBe(true)
    expect(overlapping[overlapping.length - 1]).toBe('  src/a.ts  feat/x, feat/y')
  })

  test('the catalogue text names each command and ends on the guide', async () => {
    const lines = catalogueLines([SDD_ENTRY])
    // The command breaks after the colon: the prefix alone, the name under it.
    expect(lines[0]).toBe('/dev-setup:')
    expect(lines[1]).toMatch(/^  sdd\s+Runs the interactive/)
    expect(lines[2]).toMatch(/^  when\s+the work touches more than three files\.$/)
    expect(lines[3]).toMatch(/^  takes\s+\[TASK_ID\] \[--worktree\]  outward-facing · started only by you$/)
    // The name and the labels share one column, sized to the widest name.
    const other = { ...SDD_ENTRY, name: 'multi-sdd', command: '/dev-setup:multi-sdd' }
    const starts = catalogueLines([SDD_ENTRY, other])
      .filter((line) => /^  \S/.test(line))
      .map((line) => line.length - line.replace(/^  \S+\s+/, '').length)
    expect(new Set(starts).size).toBe(1)
    expect(lines[lines.length - 1]).toContain('docs/developer-guide.md')
    expect(runLine({ ...RUN, state: 'failed', reason: 'verify failed' }, AT_10_00)).toBe('DE-5  failed  verify failed')
    expect(runLine(RUN, AT_10_00 + 5 * 60_000)).toBe('DE-5  running  5m')
  })
})

describe('rows', () => {
  test('a row joins its spans and drops the trailing blanks', async () => {
    expect(rowText([span('a', 'accent', true), span('  '), dim('b'), span('  ')])).toBe('a  b')
    expect(rowText(field('Branch', 9, span('main')))).toBe('Branch     main')
  })

  test('columns pad every cell to its column, numbers to the right', async () => {
    const table = columns(
      [
        [span('phase'), span('cost')],
        [span('discovery'), span('$0.10')],
        [span('dev'), span('$12.00')],
      ],
      ['left', 'right'],
    )
    expect(table.map(rowText)).toEqual(['phase        cost', 'discovery   $0.10', 'dev        $12.00'])
    expect(table[1]?.[0]).toMatchObject({ text: 'discovery' })
  })

  test('a meter fills its share of the cells and clamps the percent', async () => {
    expect(meter(50, 10)).toBe('█████░░░░░')
    expect(meter(120, 4)).toBe('████')
    expect(meter(-5, 4)).toBe('░░░░')
  })
})

/** Stub constructors: the element as plain data, enough to read a tree back. */
const stubUi: Ui = {
  Box: (props) => ({ type: 'Box', props }) as never,
  Text: (props) => ({ type: 'Text', props }) as never,
  Button: (props) => ({ type: 'Button', props }) as never,
  Link: (props) => ({ type: 'Link', props }) as never,
}

describe('draw', () => {
  test('adjacent spans of one style become one Text; a change of style starts another', async () => {
    const one = drawRow(stubUi, [span('a'), span('b')]) as unknown as { type: string; props: { children: string[] } }
    expect(one).toMatchObject({ type: 'Text', props: { children: ['ab'] } })
    const row = drawRow(stubUi, [span('DE-1', undefined, true), span('  '), span('in progress', 'good')]) as unknown as {
      type: string
      props: { children: { type: string; props: Record<string, unknown> }[] }
    }
    expect(row.type).toBe('Box')
    expect(row.props.children.map((child) => child.props)).toEqual([
      { bold: true, children: ['DE-1'] },
      { children: ['  '] },
      { color: 'success', children: ['in progress'] },
    ])
    const blank = drawRow(stubUi, []) as unknown as { props: { children: string[] } }
    expect(blank.props.children).toEqual([' '])
  })

  test('only an https URL of printable ASCII becomes a Link', async () => {
    expect(linkable('https://github.com/a/b/pull/9')).toBe(true)
    expect(linkable('http://gitlab.local/x/-/merge_requests/1')).toBe(false)
    expect(linkable('https://user@host/pull/1')).toBe(false)
    expect(linkable('https://host/pull/1 and more')).toBe(false)
  })
})

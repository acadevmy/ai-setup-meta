// runs.ts — the auto-sdd runs a session launched, as far as events show them.
//
// No event concerns workflows, so a run is observed at its two ends: the
// `Workflow` call that launched it (its args name the task, its result the
// background task id and the run id) and the task notification that reports
// its end (the same background task id, and the run's own result). What a run
// is doing in between is not observable, and the view does not pretend.

const RUN_WORKFLOW = 'dev-setup:auto-sdd'
const MAX_RUNS = 5

export type RunState = 'running' | 'ready-for-mr' | 'failed' | 'completed' | 'killed'

export type Run = {
  readonly taskId: string
  readonly title: string
  readonly backgroundId: string
  readonly runId: string
  readonly startedAt: number
  readonly state: RunState
  readonly reason: string
  readonly branch: string
  readonly mergeRequest: string
}

function text(value: unknown): string {
  return typeof value === 'string' ? value : ''
}

function field(value: unknown, key: string): unknown {
  return value && typeof value === 'object' ? (value as Record<string, unknown>)[key] : undefined
}

/** A run from a `Workflow` tool call and its result (bare, or in the
 * `tool.call` envelope); null for any other workflow. */
export function runFromWorkflowCall(input: unknown, toolResult: unknown, nowMs: number): Run | null {
  if (field(input, 'name') !== RUN_WORKFLOW) return null
  const result = field(toolResult, 'result') ?? toolResult
  const args = field(input, 'args')
  const taskId = text(field(args, 'taskId'))
  if (!taskId) return null
  return {
    taskId,
    title: text(field(args, 'title')),
    backgroundId: text(field(result, 'taskId')),
    runId: text(field(result, 'runId')),
    startedAt: nowMs,
    state: 'running',
    reason: '',
    branch: '',
    mergeRequest: '',
  }
}

export type Notification = {
  readonly backgroundId: string
  readonly state: RunState
  readonly taskId: string
  readonly reason: string
  readonly branch: string
}

function tag(body: string, name: string): string {
  const match = new RegExp(`<${name}>([\\s\\S]*?)</${name}>`).exec(body)
  return match ? match[1].trim() : ''
}

/** The run's result: its top-level fields when it is JSON (nested objects —
 * a reviewer's `reason` in `openPoints[]` — never shadow them), else the first
 * occurrence of each key as a last resort. */
function resultField(result: string, key: string): string {
  try {
    const parsed: unknown = JSON.parse(result)
    return text(field(parsed, key))
  } catch {
    const match = new RegExp(`"${key}"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"`).exec(result)
    return match ? match[1] : ''
  }
}

/** A background task's notification, or null when the text is not one. */
export function parseNotification(body: string): Notification | null {
  const backgroundId = tag(body, 'task-id')
  if (!backgroundId) return null
  const result = tag(body, 'result')
  const outcome = resultField(result, 'status')
  const status = tag(body, 'status')
  const state: RunState =
    outcome === 'ready-for-mr' || outcome === 'failed'
      ? outcome
      : status === 'killed' || status === 'failed'
        ? status
        : 'completed'
  return {
    backgroundId,
    state,
    taskId: resultField(result, 'taskId'),
    reason: resultField(result, 'reason'),
    branch: resultField(result, 'branch'),
  }
}

/** The runs with the notified one closed; an unrelated notification changes nothing. */
export function applyNotification(runs: readonly Run[], notification: Notification): Run[] {
  return runs.map((run) => {
    const same =
      (run.backgroundId !== '' && run.backgroundId === notification.backgroundId) ||
      (run.backgroundId === '' && notification.taskId !== '' && run.taskId === notification.taskId)
    if (!same) return run
    return {
      ...run,
      state: notification.state,
      reason: notification.reason || run.reason,
      branch: notification.branch || run.branch,
    }
  })
}

/** The newest run per task first replaced, the list capped at MAX_RUNS. */
export function addRun(runs: readonly Run[], run: Run): Run[] {
  return [...runs.filter((existing) => existing.taskId !== run.taskId), run].slice(-MAX_RUNS)
}

/** A merge request opened for a run: its branch or its task id appears in the command. */
export function attachMergeRequest(runs: readonly Run[], command: string, url: string): Run[] {
  return runs.map((run) => {
    const named = (run.branch !== '' && command.includes(run.branch)) || command.includes(run.taskId)
    return named && run.mergeRequest === '' ? { ...run, mergeRequest: url } : run
  })
}

export function canResume(run: Run): boolean {
  return run.runId !== '' && (run.state === 'failed' || run.state === 'killed')
}

/** What the resume button fills: the request, for the model, to resume from the journal. */
export function resumePrompt(run: Run): string {
  return (
    `Resume the ${RUN_WORKFLOW} run for ${run.taskId}: call Workflow with name "${RUN_WORKFLOW}", ` +
    `the same args as its launch, and resumeFromRunId "${run.runId}", as run-outcomes.md describes.`
  )
}

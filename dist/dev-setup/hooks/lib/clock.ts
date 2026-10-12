// clock.ts — the task clock as task-clock.sh reports it, turned into band lines.
//
// The script is the only source: `--status --json` (no task) names the open
// tasks, `--task <id> --status --json` gives each one's start. It measures on
// `--stop` only, so the running time is computed here, from STARTED_AT — the
// local `YYYY-MM-DD HH:MM` the script writes — plus the minutes of the
// intervals already closed.

import type { Row } from './rows.ts'
import { bold, dim, GAP, rowText, span } from './rows.ts'

/** The script's flat JSON: every key UPPER_SNAKE, every value a string. */
export type ScriptJson = Readonly<Record<string, string>>

export type OpenClock = {
  readonly task: string
  /** STARTED_AT, parsed once when the clock is read — never on a redraw. */
  readonly startMs: number | null
  readonly closedMinutes: number
  /** The intervals already closed, as the script counts them. */
  readonly sessions: number
}

/** The tasks with an open interval, from `--status --json` with no task. */
export function openTasks(status: ScriptJson): string[] {
  return (status.OPEN_TASKS ?? '').split(/\s+/).filter((task) => task !== '')
}

/** One task's open clock, from `--task <id> --status --json`; null when not running. */
export function toOpenClock(status: ScriptJson): OpenClock | null {
  if (status.RUNNING !== 'true' || !status.TASK || !status.STARTED_AT) return null
  const closed = Number.parseInt(status.TOTAL_MINUTES ?? '', 10)
  const sessions = Number.parseInt(status.SESSIONS ?? '', 10)
  return {
    task: status.TASK,
    startMs: parseLocalStamp(status.STARTED_AT),
    closedMinutes: Number.isFinite(closed) && closed > 0 ? closed : 0,
    sessions: Number.isFinite(sessions) && sessions > 0 ? sessions : 0,
  }
}

/** `YYYY-MM-DD HH:MM` in local time, as the script writes it, to epoch ms. */
export function parseLocalStamp(stamp: string): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/.exec(stamp.trim())
  if (!match) return null
  const part = (i: number) => Number(match[i])
  return new Date(part(1), part(2) - 1, part(3), part(4), part(5)).getTime()
}

/** Minutes in progress: the open interval so far plus the closed ones. */
export function elapsedMinutes(clock: OpenClock, nowMs: number): number {
  const open = clock.startMs === null ? 0 : Math.max(0, Math.floor((nowMs - clock.startMs) / 60_000))
  return open + clock.closedMinutes
}

/** Minutes as `2h 15m`, `2h`, `15m` — the format task-clock.sh's DURATION uses. */
export function formatDuration(minutes: number): string {
  const total = Math.max(0, Math.floor(minutes))
  const hours = Math.floor(total / 60)
  const rest = total % 60
  if (hours > 0 && rest > 0) return `${hours}h ${rest}m`
  if (hours > 0) return `${hours}h`
  return `${rest}m`
}

/** Epoch ms as the local `HH:MM`, the way STARTED_AT is written. */
export function formatTime(ms: number): string {
  const date = new Date(ms)
  return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`
}

/** The band's row for one clock: the task, its state, the time in progress. */
export function clockRow(clock: OpenClock, nowMs: number): Row {
  return [bold(clock.task), GAP, span('in progress', 'good'), GAP, bold(formatDuration(elapsedMinutes(clock, nowMs)))]
}

/** What the clock view adds under a clock: when this interval began and what
 * the closed ones add up to. */
export function clockDetail(clock: OpenClock): Row {
  const parts: string[] = []
  if (clock.startMs !== null) parts.push(`since ${formatTime(clock.startMs)}`)
  if (clock.sessions > 0) {
    const earlier = clock.sessions === 1 ? '1 earlier session' : `${clock.sessions} earlier sessions`
    parts.push(`${earlier}, ${formatDuration(clock.closedMinutes)}`)
  }
  return parts.length > 0 ? [dim(parts.join(' · '))] : []
}

export function clockLine(clock: OpenClock, nowMs: number): string {
  return rowText(clockRow(clock, nowMs))
}

// Pure calculations: no `$`, so they are easy to test and reason about.
import type { Activity, Limit, Snapshot } from '../types'

export type Level = 'ok' | 'watch' | 'act'

export const MINUTE = 60_000
export const HOUR = 60 * MINUTE
export const DAY = 24 * HOUR

/** How long each known window is, so we can tell how much time has passed. */
export const WINDOW_MS: Record<string, number> = {
  five_hour: 5 * HOUR,
  seven_day: 7 * DAY,
}

export const LABEL: Record<string, string> = {
  five_hour: '5h',
  seven_day: 'Week',
  spend_limit: 'Spend',
}

/** Context thresholds the person chose: yellow at 50%, red at 75%. */
export const CONTEXT_WATCH = 50
export const CONTEXT_ACT = 75

/** Limit thresholds: yellow past 70% (or ahead of pace), red past 90%. */
export const LIMIT_WATCH = 70
export const LIMIT_ACT = 90


/** No prompt for this long counts as idle (also when the prompt cache has expired). */
export const IDLE_MS = 30 * MINUTE

/** A commit within this long, with no edits after it, reads as "task done". */
export const DONE_MS = 20 * MINUTE

export const contextLevel = (percent: number | null): Level =>
  percent === null
    ? 'ok'
    : percent >= CONTEXT_ACT
      ? 'act'
      : percent >= CONTEXT_WATCH
        ? 'watch'
        : 'ok'

export type Pace = {
  /** Share of the window's time already passed, 0–100; null when unknown. */
  elapsedPercent: number | null
  /** Milliseconds until reset; null when unknown. */
  resetInMs: number | null
  /** How much earlier than the reset usage hits 100% at the current rate; null when it does not. */
  runsOutEarlyMs: number | null
  status: 'under' | 'ahead' | 'over' | 'unknown'
  level: Level
}

export const pace = (limit: Limit, now: number): Pace => {
  const length = WINDOW_MS[limit.kind]
  const resetInMs =
    limit.resetsAt === null ? null : Math.max(0, limit.resetsAt - now)
  const used = limit.percentUsed

  if (used >= 100) {
    return {
      elapsedPercent: elapsedOf(length, resetInMs),
      resetInMs,
      runsOutEarlyMs: null,
      status: 'over',
      level: 'act',
    }
  }

  const elapsedPercent = elapsedOf(length, resetInMs)

  if (elapsedPercent === null || resetInMs === null || length === undefined) {
    return {
      elapsedPercent,
      resetInMs,
      runsOutEarlyMs: null,
      status: 'unknown',
      level: used >= LIMIT_ACT ? 'act' : used >= LIMIT_WATCH ? 'watch' : 'ok',
    }
  }

  const elapsedMs = length - resetInMs
  // Rate so far, in percent per millisecond; project when it reaches 100%.
  const rate = elapsedMs > 0 ? used / elapsedMs : 0
  const untilFullMs = rate > 0 ? (100 - used) / rate : Infinity
  const runsOutEarlyMs =
    untilFullMs < resetInMs ? Math.round(resetInMs - untilFullMs) : null
  const isAhead = runsOutEarlyMs !== null

  return {
    elapsedPercent,
    resetInMs,
    runsOutEarlyMs,
    status: isAhead ? 'ahead' : 'under',
    level:
      used >= LIMIT_ACT
        ? 'act'
        : used >= LIMIT_WATCH || isAhead
          ? 'watch'
          : 'ok',
  }
}

const elapsedOf = (
  length: number | undefined,
  resetInMs: number | null,
): number | null =>
  length === undefined || resetInMs === null
    ? null
    : Math.min(100, Math.max(0, ((length - resetInMs) / length) * 100))

/** `2h13m`, `40m`, `3d 4h`. */
export const duration = (ms: number): string => {
  const minutes = Math.max(0, Math.round(ms / MINUTE))
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h${String(minutes % 60).padStart(2, '0')}m`
  return `${Math.floor(hours / 24)}d ${hours % 24}h`
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

/** The reset as people say it: `2h13m` within a day, `Tue 14:00` beyond. */
export const resetLabel = (resetsAt: number, now: number): string => {
  const ms = resetsAt - now
  if (ms < DAY) return duration(ms)
  const at = new Date(resetsAt)
  const hh = String(at.getHours()).padStart(2, '0')
  const mm = String(at.getMinutes()).padStart(2, '0')
  return `${WEEKDAYS[at.getDay()]} ${hh}:${mm}`
}

/** `136k`, `1.2M`. */
export const tokens = (n: number): string =>
  n >= 1_000_000
    ? `${(n / 1_000_000).toFixed(n >= 10_000_000 ? 0 : 1)}M`
    : n >= 1000
      ? `${Math.round(n / 1000)}k`
      : `${n}`

export type Advice = { text: string; level: Level } | null

/**
 * The zero-token /clear vs /compact hint: plain rules over figures the session
 * already has. First rule that matches wins; null when nothing is worth saying.
 */
export const advise = (
  snapshot: Snapshot | null,
  activity: Activity,
  now: number,
  isWorking: boolean,
): Advice => {
  const percent = snapshot?.percent ?? null
  const used = snapshot?.tokens ?? null
  if (percent === null || used === null) return null

  const isMidTask =
    activity.editsSinceCommit > 0 &&
    activity.lastEditAt !== null &&
    now - activity.lastEditAt < 2 * HOUR
  const isDone =
    activity.lastCommitAt !== null &&
    activity.editsSinceCommit === 0 &&
    now - activity.lastCommitAt < DONE_MS
  const isIdle =
    !isWorking &&
    activity.lastPromptAt !== null &&
    now - activity.lastPromptAt >= IDLE_MS
  const fiveHour = snapshot?.limits.find(l => l.kind === 'five_hour')
  const isTight =
    fiveHour !== undefined && pace(fiveHour, now).level !== 'ok'
  const autoAt = snapshot?.autoCompactPercent ?? null
  const saves = `saves ~${tokens(used)} tokens per turn`

  if (percent >= CONTEXT_ACT && isMidTask) {
    return {
      text: `Context high, mid-task → /compact soon (add what to keep: /compact keep the plan)`,
      level: 'act',
    }
  }
  if (percent >= 30 && isDone) {
    return {
      text: `Task looks done (just committed) → /clear ${saves}`,
      level: percent >= CONTEXT_WATCH ? 'watch' : 'ok',
    }
  }
  if (percent >= 30 && isIdle) {
    return {
      text: `Idle 30m+: the next turn re-reads ${tokens(used)} tokens uncached → /clear if you're moving on`,
      level: 'watch',
    }
  }
  if (percent >= CONTEXT_ACT) {
    return {
      text: `Context high → /compact to continue, or /clear for a new task${autoAt === null ? '' : ` (auto-compact at ${autoAt}%)`}`,
      level: 'act',
    }
  }
  if (isTight && percent >= 40) {
    return {
      text: `5h limit is tight: a smaller context makes every turn cheaper → /clear or /compact`,
      level: 'watch',
    }
  }
  return null
}

/** Pick the bar width from the cells the band has. */
export const barWidth = (columns: number): number =>
  Math.max(8, Math.min(24, columns - 56))

/** Bar cells: how many filled, and where the "time passed" marker sits (or null). */
export const bar = (
  percent: number,
  width: number,
  markerPercent: number | null,
): { filled: number; marker: number | null } => {
  const filled = Math.max(0, Math.min(width, Math.round((percent / 100) * width)))
  const marker =
    markerPercent === null
      ? null
      : Math.max(0, Math.min(width - 1, Math.round((markerPercent / 100) * width)))
  return { filled, marker }
}

export const isCommit = (command: string): boolean =>
  /\bgit\b[^;&|\n]*\b(commit|push)\b/.test(command)

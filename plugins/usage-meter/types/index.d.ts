export type Limit = {
  /** `five_hour`, `seven_day`, or a gateway's `spend_limit`. */
  kind: string
  percentUsed: number
  /** Epoch milliseconds the window resets at. */
  resetsAt: number | null
}

export type Snapshot = {
  /** Input tokens of the last response; null before the first one. */
  tokens: number | null
  /** The model's context window in tokens. */
  window: number
  /** Context fill in percent; null before the first response. */
  percent: number | null
  /** Where auto-compact triggers, in percent of `window`; null when off/unknown. */
  autoCompactPercent: number | null
  limits: Limit[]
  /** True when `limits` were carried over from an earlier session (no fresh reading yet). */
  isStale: boolean
}

export type Activity = {
  /** When the person last sent a prompt (epoch ms); null before the first. */
  lastPromptAt: number | null
  /** When a file was last edited by a tool; null when none this session. */
  lastEditAt: number | null
  /** When `git commit` / `git push` last succeeded; null when none. */
  lastCommitAt: number | null
  /** File edits since the last commit. */
  editsSinceCommit: number
}

declare module 'claude-code' {
  interface PluginState {
    'usage-meter': {
      snapshot: Snapshot | null
      activity: Activity
      /** The clock, refreshed each minute so countdowns move without a turn. */
      now: number
    }
  }
}

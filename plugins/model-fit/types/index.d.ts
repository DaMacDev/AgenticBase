export type Setting = {
  /** The model id the main thread's last request named. */
  model: string
  /** Its effort level; null for a model without one, or a numeric budget. */
  effort: string | null
}

export type Suggestion = {
  /** `haiku`, `sonnet` or `opus`. */
  model: string
  /** `low` … `max`. */
  effort: string
  /** Why, in a few words. */
  reason: string
}

export type Activity = {
  reads: number
  edits: number
  /** Distinct files edited. */
  files: number
  commands: number
  failures: number
  subagents: number
}

declare module 'claude-code' {
  interface PluginState {
    'model-fit': {
      current: Setting | null
      suggestion: Suggestion | null
    }
  }
}

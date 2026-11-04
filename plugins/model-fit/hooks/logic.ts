import type { Activity, Setting, Suggestion } from '../types'

/** One earlier request of the session and what its turn did. */
export type Turn = { request: string; activity: Activity }

export const MODELS =['haiku', 'sonnet', 'opus'] as const
export const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'] as const

/** The family alias of a model id (`claude-opus-5-5` is `opus`); the id itself when none matches. */
export function family(model: string): string {
  const m = model.toLowerCase()
  return MODELS.find(f => m.includes(f)) ?? model
}

/** A short label: the id without its `claude-` prefix and any `[1m]` tag. */
export function label(s: Setting): string {
  const name = s.model.replace(/^claude-/i, '').replace(/\[.*\]$/, '')
  return s.effort === null ? name : `${name} · ${s.effort}`
}

/** A numeric effort (a token budget) has no level name. */
export function effortName(effort: string | number | undefined): string | null {
  return typeof effort === 'string' ? effort : null
}

/** True when the suggestion names the setting already in use. */
export function fits(now: Setting, s: Suggestion): boolean {
  return family(now.model) === s.model && (now.effort === null || now.effort === s.effort)
}

/** One line of what the last turn did, for the classifier. */
export function describe(a: Activity): string {
  const parts = [
    `${a.reads} read-only tool calls`,
    `${a.edits} file edits in ${a.files} files`,
    `${a.commands} shell commands`,
    `${a.failures} failed tool calls`,
    `${a.subagents} subagents spawned`,
  ]
  return parts.join(', ')
}

export const INSTRUCTIONS = `You pick the cheapest Claude model and effort that will do a coding task well.
Models: haiku (fast, cheap), sonnet (mid), opus (strongest). Efforts: low, medium, high, xhigh, max.
Guide:
- haiku low: lookups, one command, renames, formatting, status questions.
- sonnet medium: routine edits that follow an existing pattern, small tests, docs.
- opus medium: the default for planning, building features and reviews.
- opus high or xhigh: design across many files, subtle or security bugs, failures repeating across turns.
- max: only for a hard problem that already failed at xhigh.
Answer one line, exactly: <model> <effort> | <reason, at most 8 words>`

/** The classifier's prompt: the setting, the request, what its turn did and the turns before. */
export function prompt(now: Setting, request: string, a: Activity, earlier: readonly Turn[] = []): string {
  return [
    `Current: ${family(now.model)} ${now.effort ?? 'default'}`,
    ...earlier.map(t => `Earlier request: ${t.request.slice(0, 200)} (its turn: ${describe(t.activity)})`),
    `Request: ${request.slice(0, 1200)}`,
    `Last turn: ${describe(a)}`,
  ].join('\n')
}

/** Reads `<model> <effort> | <reason>`; null when the reply is not that shape. */
export function parse(text: string): Suggestion | null {
  const m = /\b(haiku|sonnet|opus)\s+(low|medium|high|xhigh|max)\b\s*\|?\s*(.*)/i.exec(text)
  const [, model, effort, reason = ''] = m ?? []
  if (model === undefined || effort === undefined) return null
  return {
    model: model.toLowerCase(),
    effort: effort.toLowerCase(),
    // Control characters (terminal escapes, \r) never reach the rendered row.
    reason: (reason.split('\n')[0] ?? '').replace(/\p{Cc}/gu, '').trim().slice(0, 80),
  }
}

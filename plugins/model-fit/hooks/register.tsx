import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Activity } from '../types'
import { INSTRUCTIONS, effortName, fits, label, parse, prompt, type Turn } from './logic'

const current = atom({ plugin: 'model-fit', key: 'current' } as const, null)
const suggestion = atom({ plugin: 'model-fit', key: 'suggestion' } as const, null)

const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit'])
const SHELL_TOOLS = new Set(['Bash', 'PowerShell'])
const NONE: Activity = { reads: 0, edits: 0, files: 0, commands: 0, failures: 0, subagents: 0 }
/** Earlier turns sent beside the newest, so repeated failures read as retries. */
const HISTORY = 3

export const register: Register = on => {
  let request = ''
  let activity: Activity = { ...NONE }
  let files = new Set<string>()
  let earlier: Turn[] = []
  // Only the newest turn's answer lands, if an older call returns late.
  let asked = 0

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    earlier = []
    await update($, suggestion, () => null)
    return result
  })

  on('prompt.submit', async ($, e, next) => {
    if (request.trim() !== '') earlier = [...earlier, { request, activity }].slice(-HISTORY)
    request = e.text
    activity = { ...NONE }
    files = new Set()
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined) {
      const s = { model: e.model, effort: effortName(e.effort) }
      await update($, current, was => (was?.model === s.model && was?.effort === s.effort ? was : s))
    }
    return yield* next(e)
  })

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    // A subagent's own calls are its work, not the main thread's; its spawn is counted.
    if (e.agentId !== undefined) return ran
    const a = activity
    if (ran.deny !== undefined || ran.isError === true) a.failures += 1
    if (EDIT_TOOLS.has(e.tool)) {
      a.edits += 1
      const path = (e as { file_path?: unknown }).file_path
      if (typeof path === 'string') files.add(path)
      a.files = files.size
    } else if (SHELL_TOOLS.has(e.tool)) a.commands += 1
    else if (e.tool === 'Agent') a.subagents += 1
    else if (ran.isReadOnly === true) a.reads += 1
    return ran
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    const now = await read($, current)
    if (e.agentId !== undefined || e.isAborted || now === null || request.trim() === '') return result

    const mine = ++asked
    const ask = prompt(now, request, activity, earlier)
    await update($, suggestion, () => null)
    // Not awaited: the classifier must not hold up the end of the turn. If the hooks
    // worker is lost meanwhile the call is made once more, one extra Haiku request.
    void (async () => {
      const r = await $.model.complete({
        model: 'haiku',
        system: INSTRUCTIONS,
        prompt: ask,
        effort: 'low',
        maxTokens: 60,
        timeoutMs: 20_000,
      })
      if (mine !== asked || !r.isAnswered) return
      const s = parse(r.text)
      if (s !== null) await update($, suggestion, () => s)
    })().catch(() => undefined)
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const below = await next(e)
    const now = await read($, current)
    if (e.props.hasSurvey || now === null) return below

    const { Box, Text } = $.ui.resolve(e)
    const s = await read($, suggestion)
    const hint =
      s === null ? null : fits(now, s) ? (
        <Text color="success">{'  ✓ fits'}</Text>
      ) : (
        <Text color="suggestion">{`  → try ${s.model} · ${s.effort}${s.reason ? `: ${s.reason}` : ''}`}</Text>
      )

    return (
      <Box flexDirection="column">
        <Text wrap="truncate">
          <Text weight="semibold">{'Model'.padEnd(9)}</Text>
          <Text>{label(now)}</Text>
          {hint}
        </Text>
        {below}
      </Box>
    )
  })
}

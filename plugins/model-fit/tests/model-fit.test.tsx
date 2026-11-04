import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'

import { family, fits, label, parse } from '../hooks/logic'

const BAND = (surface: 'terminal' | 'desktop') =>
  ({
    plugin: 'model-fit',
    component: 'AbovePrompt',
    surface,
    props: {
      hasSurvey: false,
      isWorking: false,
      maxRows: 20,
      bodyColumns: 100,
      scroll: { offset: 0, bodyRows: 20 },
      view: {},
    },
  }) as const

/** Stands in for the engine beneath the mod; `reply` is what the classifier answers. */
const engine = (on: On, reply: string | (() => string)) => {
  const asks: string[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text }) as never)
  on('tool.call', () => ({ result: {}, isReadOnly: true }) as never)
  on('turn.step', async function* (_, e) {
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('model.complete', (_, e) => {
    asks.push(e.prompt)
    const usage = { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
    return { value: { isAnswered: true as const, text: typeof reply === 'string' ? reply : reply(), usage } }
  })
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box />
  })
  return { asks }
}

/** One prompt and one model step on `model` at `effort`, then the turn's end. */
async function turn($: Engine, model: string, effort: string, text = 'rename foo to bar in one file', during?: () => Promise<unknown>) {
  await $.prompt.submit({ text, wait: false, origin: { kind: 'composer' } })
  await during?.()
  const step = $.turn.step({ turnId: 't1', index: 0, model, effort: effort as 'high', messageCount: 1 })
  for await (const _ of step) { /* no chunks */ }
  await step.result
  await $.turn.complete({ answer: 'done', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
}

/** The classifier runs after the turn ends, unawaited: let it land. */
async function settle() {
  for (let i = 0; i < 50; i++) await Promise.resolve()
}

test('parse reads the one-line answer and refuses anything else', async () => {
  expect(parse('sonnet medium | routine single-file edit')).toEqual({ model: 'sonnet', effort: 'medium', reason: 'routine single-file edit' })
  expect(parse('Opus XHIGH')).toEqual({ model: 'opus', effort: 'xhigh', reason: '' })
  expect(parse('I think gpt is best')).toBe(null)
  expect(parse('haiku low | read\u001b[31m only\r')).toEqual({ model: 'haiku', effort: 'low', reason: 'read[31m only' })
})

test('family, label and fits', async () => {
  expect(family('claude-opus-5-5')).toBe('opus')
  expect(label({ model: 'claude-opus-5-5[1m]', effort: 'medium' })).toBe('opus-5-5 · medium')
  expect(label({ model: 'claude-haiku-5-5', effort: null })).toBe('haiku-5-5')
  expect(fits({ model: 'claude-opus-5-5', effort: 'medium' }, { model: 'opus', effort: 'medium', reason: '' })).toBe(true)
  expect(fits({ model: 'claude-opus-5-5', effort: 'high' }, { model: 'opus', effort: 'medium', reason: '' })).toBe(false)
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: shows the model in use and a cheaper suggestion`, async ($, on) => {
    const { asks } = engine(on, 'sonnet medium | routine single-file edit')
    await $.session.start({ cwd: '/', surface, isInteractive: true })
    await turn($, 'claude-opus-5-5', 'high')
    await settle()

    expect(asks.length).toBe(1)
    expect(asks[0]).toContain('Current: opus high')
    expect(asks[0]).toContain('rename foo to bar')
    const ui = await $.ui.mount(BAND(surface))
    expect(await ui.find({ type: 'Text', text: /Model.*opus-5-5 · high.*try sonnet · medium: routine single-file edit/ })).toBeTruthy()
    await ui.unmount()
  })

  test(`${surface}: says it fits when the suggestion is the setting in use`, async ($, on) => {
    engine(on, 'opus medium | multi-file feature work')
    await $.session.start({ cwd: '/', surface, isInteractive: true })
    await turn($, 'claude-opus-5-5', 'medium')
    await settle()

    const ui = await $.ui.mount(BAND(surface))
    expect(await ui.find({ type: 'Text', text: /opus-5-5 · medium.*✓ fits/ })).toBeTruthy()
    await ui.unmount()
  })

  test(`${surface}: counts the main thread's calls only, sends earlier requests, clears a stale hint`, async ($, on) => {
    let reply = 'sonnet medium | routine edit'
    const { asks } = engine(on, () => reply)
    await $.session.start({ cwd: '/', surface, isInteractive: true })
    await turn($, 'claude-opus-5-5', 'high', 'fix the parser', async () => {
      await $.tool.call({ tool: 'Edit', file_path: '/a.ts', old_string: 'x', new_string: 'y' } as never)
      await $.tool.call({ tool: 'Edit', file_path: '/b.ts', old_string: 'x', new_string: 'y', agentId: 'sub1' } as never)
    })
    await settle()
    expect(asks[0]).toContain('1 file edits in 1 files')

    reply = 'no idea'
    await turn($, 'claude-opus-5-5', 'high', 'it still fails')
    await settle()
    expect(asks[1]).toContain('Earlier request: fix the parser')
    const ui = await $.ui.mount(BAND(surface))
    expect(await ui.find({ type: 'Text', text: /try sonnet/ })).toBeFalsy()
    expect(await ui.find({ type: 'Text', text: /opus-5-5 · high/ })).toBeTruthy()
    await ui.unmount()
  })

  test(`${surface}: draws nothing of its own before the first model request`, async ($, on) => {
    engine(on, 'haiku low | lookup')
    await $.session.start({ cwd: '/', surface, isInteractive: true })
    const ui = await $.ui.mount(BAND(surface))
    expect(await ui.find({ type: 'Text', text: /Model/ })).toBeFalsy()
    await ui.unmount()
  })
}

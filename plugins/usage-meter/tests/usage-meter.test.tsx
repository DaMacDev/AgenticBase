import { expect, mock, test } from 'claude-code/testing'
import type { On, SessionUsage } from 'claude-code'

const NOW = Date.UTC(2026, 9, 31, 12, 0)
const MIN = 60_000

const BAND = (surface: 'terminal' | 'desktop', isWorking = false) =>
  ({
    plugin: 'usage-meter',
    component: 'AbovePrompt',
    surface,
    props: {
      hasSurvey: false,
      isWorking,
      maxRows: 20,
      bodyColumns: 100,
      scroll: { offset: 0, bodyRows: 20 },
    },
  }) as const

/** Stands in for the engine beneath the mod. */
const engine = (on: On, usage: SessionUsage) => {
  const clock = mock.clock(on, { now: NOW })
  mock.store(on)
  const statuses: (string | undefined)[] = []
  const toasts: string[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.usage', () => ({ value: usage }))
  on('session.measure', (_, e) => ({ changed: e.changed }))
  on('ui.status', (_, e) => (statuses.push(e.text), { value: undefined }))
  on('ui.toast', (_, e) => (toasts.push(e.text), { value: undefined }))
  on('prompt.submit', (_, e) => ({ text: e.text }) as never)
  on('tool.call', () => ({ result: {} }) as never)
  return { clock, statuses, toasts }
}

const usage = (over: Partial<SessionUsage> = {}): SessionUsage => ({
  startedAt: NOW - 60 * MIN,
  context: { tokens: 136_000, window: 200_000, percent: 68 },
  rateLimits: [
    // 3h of 5h passed (60%), 41% used: under pace
    { kind: 'five_hour', percentUsed: 41, resetsAt: new Date(NOW + 120 * MIN).toISOString() },
    { kind: 'seven_day', percentUsed: 22, resetsAt: new Date(NOW + 3 * 24 * 60 * MIN).toISOString() },
  ],
  cost: { usd: 1.2 },
  ...over,
})

const start = ($: Parameters<Parameters<typeof test>[1]>[0], surface: 'terminal' | 'desktop') =>
  $.session.start({ cwd: '/', surface, isInteractive: true })

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: draws context, 5h and week rows with pace`, async ($, on) => {
    engine(on, usage())
    await start($, surface)
    const ui = await $.ui.mount(BAND(surface))

    expect((await ui.find({ type: 'Text', text: /Context.*136k\/200k 68%/ }))).toBeTruthy()
    expect((await ui.find({ type: 'Text', text: /5h.*41%.*time 60%.*under pace.*resets 2h00m/ }))).toBeTruthy()
    expect((await ui.find({ type: 'Text', text: /Week.*22%.*resets/ }))).toBeTruthy()
    // 68% context, nothing done/idle: no advice yet
    expect(await ui.find({ type: 'Text', text: /💡/ })).toBeFalsy()
    await ui.unmount()
  })

  test(`${surface}: ahead of pace and a /compact hint mid-task`, async ($, on) => {
    engine(
      on,
      usage({
        context: { tokens: 160_000, window: 200_000, percent: 80 },
        rateLimits: [
          // 1h of 5h passed (20%), 60% used: way ahead
          { kind: 'five_hour', percentUsed: 60, resetsAt: new Date(NOW + 240 * MIN).toISOString() },
        ],
      }),
    )
    await start($, surface)
    await $.tool.call({ tool: 'Edit', file_path: '/a.ts', old_string: 'a', new_string: 'b' } as never)
    const ui = await $.ui.mount(BAND(surface))

    expect(await ui.find({ type: 'Text', text: /ahead of pace, out ~\d/ })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: /💡 Context high, mid-task → \/compact/ })).toBeTruthy()
    await ui.unmount()
  })

  test(`${surface}: a commit turns the hint into /clear`, async ($, on) => {
    engine(on, usage({ context: { tokens: 90_000, window: 200_000, percent: 45 } }))
    await start($, surface)
    await $.tool.call({ tool: 'Edit', file_path: '/a.ts', old_string: 'a', new_string: 'b' } as never)
    await $.tool.call({ tool: 'Bash', command: 'git add . && git commit -m "done"' } as never)
    const ui = await $.ui.mount(BAND(surface))

    expect(await ui.find({ type: 'Text', text: /Task looks done.*\/clear saves ~90k/ })).toBeTruthy()
    await ui.unmount()
  })
}

test('status line shows only the worst metric, and 90% raises one toast', async ($, on) => {
  const { statuses, toasts } = engine(
    on,
    usage({
      context: { tokens: 20_000, window: 200_000, percent: 10 },
      rateLimits: [
        { kind: 'five_hour', percentUsed: 92, resetsAt: new Date(NOW + 40 * MIN).toISOString() },
        { kind: 'seven_day', percentUsed: 30, resetsAt: new Date(NOW + 4 * 24 * 60 * MIN).toISOString() },
      ],
    }),
  )
  await start($, 'terminal')
  expect(statuses.at(-1)).toBe('5h 92% ↻40m ⚠')
  expect(toasts).toEqual(['5h limit at 92%, resets in 40m'])

  // A second measurement in the same window does not toast again.
  await $.session.measure({ ...usage(), context: usage().context, rateLimits: usage({}).rateLimits.map(l => (l.kind === 'five_hour' ? { ...l, percentUsed: 93, resetsAt: new Date(NOW + 40 * MIN).toISOString() } : l)), changed: ['rateLimits'] })
  expect(toasts.length).toBe(1)
})

test('before the first reply: last-seen limits are shown dimmed', async ($, on) => {
  const kept = [{ kind: 'five_hour', percentUsed: 55, resetsAt: NOW + 90 * MIN }]
  mock.store(on, { lastLimits: kept })
  mock.clock(on, { now: NOW })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.usage', () => ({
    value: { startedAt: NOW, context: { window: 200_000 }, rateLimits: [] },
  }))
  on('ui.status', () => ({ value: undefined }))
  await start($, 'desktop')
  const ui = await $.ui.mount(BAND('desktop'))

  expect(await ui.find({ type: 'Text', text: /measured after the first reply/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /5h.*55%.*last seen/ })).toBeTruthy()
  await ui.unmount()
})

test('the clock tick moves the countdown without a turn', async ($, on) => {
  const { clock } = engine(on, usage())
  await start($, 'terminal')
  await clock.advance(30 * MIN)
  const ui = await $.ui.mount(BAND('terminal'))
  expect(await ui.find({ type: 'Text', text: /5h.*resets 1h30m/ })).toBeTruthy()
  await ui.unmount()
})

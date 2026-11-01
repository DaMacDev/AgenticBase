import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, SessionUsage } from 'claude-code'

import type { Activity, Limit, Snapshot } from '../types'
import {
  LABEL,
  LIMIT_ACT,
  advise,
  bar,
  barWidth,
  contextLevel,
  isCommit,
  pace,
  resetLabel,
  tokens,
  type Level,
} from './logic'

const FRESH: Activity = {
  lastPromptAt: null,
  lastEditAt: null,
  lastCommitAt: null,
  editsSinceCommit: 0,
}

const snapshot = atom({ plugin: 'usage-meter', key: 'snapshot' } as const, null)
const activity = atom({ plugin: 'usage-meter', key: 'activity' } as const, FRESH)
const now = atom({ plugin: 'usage-meter', key: 'now' } as const, 0)

/** Last limits seen, kept across sessions so a new session shows them until its first reply. */
const STORE_LIMITS = 'lastLimits'
const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit'])
const COLOR: Record<Level, string> = { ok: 'success', watch: 'warning', act: 'error' }

const toLimits = (usage: Pick<SessionUsage, 'rateLimits'>): Limit[] =>
  usage.rateLimits.map(l => ({
    kind: l.kind,
    percentUsed: l.percentUsed,
    resetsAt: l.resetsAt === undefined ? null : Date.parse(l.resetsAt),
  }))

/** Where auto-compact triggers, in percent of the window. A local estimate: costs no tokens. */
async function readAutoCompact($: EngineInterface): Promise<number | null> {
  try {
    const { context } = await $.session.usage({ breakdown: 'summary' })
    const b = context.breakdown
    return b?.isAutoCompactEnabled && b.autoCompactThreshold !== undefined
      ? Math.round((b.autoCompactThreshold / context.window) * 100)
      : null
  } catch {
    return null
  }
}

/** Folds a usage reading into the snapshot the band draws from. */
async function record(
  $: EngineInterface,
  usage: Pick<SessionUsage, 'context' | 'rateLimits'>,
  autoCompact?: number | null,
): Promise<void> {
  const fresh = toLimits(usage)
  const t = await $.clock.now()
  let limits = fresh
  let isStale = false

  if (fresh.length > 0) {
    await $.store.set(STORE_LIMITS, fresh)
  } else {
    // No reading yet this session: show the last one seen, if its window is still open.
    const kept = ((await $.store.get(STORE_LIMITS)) ?? []) as Limit[]
    limits = kept.filter(l => l.resetsAt !== null && l.resetsAt > t)
    isStale = limits.length > 0
  }

  const previous = await read($, snapshot)
  const next: Snapshot = {
    tokens: usage.context.tokens ?? null,
    window: usage.context.window,
    percent: usage.context.percent ?? null,
    autoCompactPercent:
      autoCompact !== undefined ? autoCompact : (previous?.autoCompactPercent ?? null),
    limits,
    isStale,
  }
  await update($, snapshot, () => next)
  await update($, now, () => t)
  if (!isStale) await alertPast90($, fresh)
}

/** One toast per window when it crosses 90%. */
async function alertPast90($: EngineInterface, limits: Limit[]): Promise<void> {
  for (const l of limits) {
    if (l.percentUsed < LIMIT_ACT) continue
    const key = `toasted:${l.kind}:${l.resetsAt ?? 'none'}`
    if (await $.store.get(key)) continue
    await $.store.set(key, true)
    const label = LABEL[l.kind] ?? l.kind
    const reset =
      l.resetsAt === null ? '' : `, resets in ${resetLabel(l.resetsAt, await $.clock.now())}`
    $.ui.toast(`${label} limit at ${Math.round(l.percentUsed)}%${reset}`)
  }
}

export const register: Register = on => {
  let tick: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await update($, activity, () => FRESH)
    await record($, await $.session.usage(), await readAutoCompact($))

    // Move the countdowns and the idle hint along between turns.
    tick?.cancel()
    tick = $.clock.every(60_000, () => {
      void (async () => {
        const t = await $.clock.now()
        await update($, now, () => t)
      })()
    })
    return result
  })

  on('session.measure', async ($, e, next) => {
    await record($, e)
    return next(e)
  })

  on('session.compact', async ($, e, next) => {
    const result = await next(e)
    await record($, await $.session.usage(), await readAutoCompact($))
    return result
  })

  on('prompt.submit', async ($, e, next) => {
    const t = await $.clock.now()
    await update($, activity, a => ({ ...(a ?? FRESH), lastPromptAt: t }))
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    const isOk = ran.deny === undefined && ran.isError !== true
    if (!isOk) return ran

    if (EDIT_TOOLS.has(e.tool)) {
      const t = await $.clock.now()
      await update($, activity, a => ({
        ...(a ?? FRESH),
        lastEditAt: t,
        editsSinceCommit: (a ?? FRESH).editsSinceCommit + 1,
      }))
    } else if (e.tool === 'Bash' && typeof e.command === 'string' && isCommit(e.command)) {
      const t = await $.clock.now()
      await update($, activity, a => ({ ...(a ?? FRESH), lastCommitAt: t, editsSinceCommit: 0 }))
    }
    return ran
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)

    const s = await read($, snapshot)
    if (s === null) return next(e)
    const a = await read($, activity)
    const t = (await read($, now)) || (await $.clock.now())

    const { Box, Text } = $.ui.resolve(e)
    const width = barWidth(e.props.bodyColumns)
    const isNarrow = e.props.bodyColumns < 60

    const drawBar = (props: { percent: number; level: Level; marker: number | null; dim?: boolean }) => {
      const { filled, marker } = bar(props.percent, width, props.marker)
      const cells: { text: string; kind: 'fill' | 'empty' | 'mark' }[] = []
      for (let i = 0; i < width; i++) {
        const kind = i === marker ? 'mark' : i < filled ? 'fill' : 'empty'
        const last = cells[cells.length - 1]
        const ch = kind === 'mark' ? '│' : kind === 'fill' ? '█' : '░'
        if (last && last.kind === kind) last.text += ch
        else cells.push({ text: ch, kind })
      }
      return (
        <Text>
          {cells.map(c =>
            c.kind === 'fill' ? (
              <Text color={props.dim ? 'subtle' : COLOR[props.level]}>{c.text}</Text>
            ) : c.kind === 'mark' ? (
              <Text weight="bold">{c.text}</Text>
            ) : (
              <Text dimColor>{c.text}</Text>
            ),
          )}
        </Text>
      )
    }

    const label = (text: string) => <Text weight="semibold">{text.padEnd(9)}</Text>

    // Context row
    const ctxLevel = contextLevel(s.percent)
    const ctxRow =
      s.percent === null || s.tokens === null ? (
        <Text wrap="truncate">
          {label('Context')}
          <Text dimColor>{`${tokens(s.window)} window · measured after the first reply`}</Text>
        </Text>
      ) : (
        <Text wrap="truncate">
          {label('Context')}
          {drawBar({percent: s.percent, level: ctxLevel, marker: null})}
          <Text color={COLOR[ctxLevel]} tabular>{` ${tokens(s.tokens)}/${tokens(s.window)} ${s.percent}%`}</Text>
          {!isNarrow && s.autoCompactPercent !== null ? (
            <Text dimColor>{`  · auto-compact at ${s.autoCompactPercent}%`}</Text>
          ) : null}
        </Text>
      )

    // Limit rows (5h, Week, any other the plan reports)
    const order = (k: string) => (k === 'five_hour' ? 0 : k === 'seven_day' ? 1 : 2)
    const limitRows = [...s.limits]
      .sort((x, y) => order(x.kind) - order(y.kind))
      .map(l => {
        const p = pace(l, t)
        const used = Math.round(l.percentUsed)
        const verdict =
          s.isStale
            ? <Text dimColor>{'  (last seen, updates after your next message)'}</Text>
            : p.status === 'over'
              ? <Text color="error">{'  ✖ limit reached'}</Text>
              : p.status === 'ahead'
                ? <Text color={COLOR[p.level]}>{`  ▲ ahead of pace${p.runsOutEarlyMs !== null ? `, out ~${resetLabel(t + p.runsOutEarlyMs, t)} early` : ''}`}</Text>
                : p.status === 'under'
                  ? <Text color={COLOR[p.level]}>{'  ✓ under pace'}</Text>
                  : null
        return (
          <Text key={l.kind} wrap="truncate">
            {label(LABEL[l.kind] ?? l.kind)}
            {drawBar({percent: l.percentUsed, level: p.level, marker: p.elapsedPercent, dim: s.isStale})}
            <Text color={s.isStale ? 'subtle' : COLOR[p.level]} tabular>{` ${String(used).padStart(3)}%`}</Text>
            {!isNarrow && p.elapsedPercent !== null ? (
              <Text dimColor>{`  time ${Math.round(p.elapsedPercent)}%`}</Text>
            ) : null}
            {verdict}
            {l.resetsAt !== null ? (
              <Text dimColor>{`   resets ${resetLabel(l.resetsAt, t)}`}</Text>
            ) : null}
          </Text>
        )
      })

    const tip = advise(s, a, t, e.props.isWorking)

    return (
      <Box flexDirection="column">
        {ctxRow}
        {limitRows}
        {tip ? (
          <Text wrap="truncate" color={tip.level === 'ok' ? 'suggestion' : COLOR[tip.level]}>
            {`💡 ${tip.text}`}
          </Text>
        ) : null}
      </Box>
    )
  })
}

---
name: chaos-harness
description: Test how a web app behaves on a bad network — random latency, random 5xx errors, offline windows injected into Playwright E2E flows. Use when the user says "simulate a flaky/slow network", "test offline behaviour", "does this survive a dropped request", or wants resilience/chaos testing for the UI. Generates an opt-in tests/fixtures/chaos.ts via page.route; safe to re-run; chaos runs are nightly, not a per-PR gate. For adversarial form input see /web-qa:form-fuzz.
user-invocable: true
argument-hint: "[project-dir]"
allowed-tools: Read, Glob, Write(tests/fixtures/chaos.ts)
---

# /chaos-harness — Playwright network-fault chaos fixture

Codifies the `page.route()` chaos primitive for E2E tests. Drops in one
opt-in fixture file; existing tests are not modified.

Requires `@playwright/test`. If missing, point the user to
`/web-qa:web-test-stack` and exit.

**Companion skill:** `/web-qa:form-fuzz` covers input-side fuzzing
with `fast-check`. The two are independent — use one, both, or neither.






## Step 1 — Preflight

```
Glob <project-dir>/package.json
Glob <project-dir>/tests/fixtures/
```

Verify `@playwright/test` in devDependencies. Stop and recommend
`web-test-stack` if missing.

If `tests/fixtures/chaos.ts` exists, print "already initialised" and exit.

## Step 2 — Write `tests/fixtures/chaos.ts`

```ts
import { test as base, type Page } from '@playwright/test';

type ChaosControls = {
  injectLatency: (minMs: number, maxMs: number) => Promise<void>;
  inject5xx: (rate: number) => Promise<void>;
  goOffline: (durationMs: number) => Promise<void>;
};

const seedString = process.env.CHAOS_SEED ?? Date.now().toString();
let seedCounter = 0;

function deterministicRandom(): number {
  // Simple seeded PRNG (mulberry32) so failures reproduce.
  let h = 0;
  const seed = `${seedString}:${seedCounter++}`;
  for (let i = 0; i < seed.length; i++) {
    h = Math.imul(31, h) + seed.charCodeAt(i) | 0;
  }
  let t = h + 0x6d2b79f5;
  t = Math.imul(t ^ t >>> 15, t | 1);
  t ^= t + Math.imul(t ^ t >>> 7, t | 61);
  return ((t ^ t >>> 14) >>> 0) / 4294967296;
}

export const test = base.extend<{ chaos: ChaosControls }>({
  chaos: async ({ page }, use) => {
    const controls: ChaosControls = {
      injectLatency: async (minMs, maxMs) => {
        await page.route('**/*', async (route) => {
          const delay = minMs + deterministicRandom() * (maxMs - minMs);
          await new Promise((r) => setTimeout(r, delay));
          await route.continue();
        });
      },
      inject5xx: async (rate) => {
        await page.route('**/*', async (route) => {
          if (deterministicRandom() < rate) {
            await route.fulfill({ status: 500, body: 'chaos: injected 5xx' });
          } else {
            await route.continue();
          }
        });
      },
      goOffline: async (durationMs) => {
        await page.context().setOffline(true);
        setTimeout(() => page.context().setOffline(false), durationMs);
      },
    };
    await use(controls);
    // Clean up: page.route handlers auto-clear on context close.
  },
});

export { expect } from '@playwright/test';
```

## Step 3 — Caller contract

Print to the user:

> Chaos fixture dropped at `tests/fixtures/chaos.ts`. Opt in per test:
>
> ```ts
> import { test } from '../fixtures/chaos';
> ```
>
> Provides `chaos.injectLatency(min, max)`, `chaos.inject5xx(rate)`, `chaos.goOffline(durationMs)`.
>
> **CI convention:** chaos tests live in `tests/e2e/chaos/**` and are tagged `@chaos`. The per-PR merge gate runs `playwright test --grep-invert @chaos`. A separate nightly job runs `playwright test --grep @chaos`. This keeps PR CI under 10 minutes.
>
> **Seed:** chaos uses `CHAOS_SEED` from the environment. CI sets it to the commit SHA so failures reproduce. Locally, the seed defaults to `Date.now()` and is printed on failure.

## Step 4 — What this catches / What this misses

**Catches:**
- Missing loading states (latency injection reveals UI that pretends to be instant).
- Missing error toasts / error-boundary rollback (5xx injection).



- Double-submit when network is slow.
- Race conditions on rapid input (chaos + `dblclick` test combos).
- Optimistic UI that never reverts.

**Misses:**
- Real backend bugs — chaos mocks the network only.
- Browser-engine-specific issues — Chromium-only per the project's test matrix.
- Input-side adversarial characters — covered by `/web-qa:form-fuzz`.
- Perceptual issues (animation jank, contrast) — covered by Lighthouse, not here.

## What this does NOT do

- Does not add tests to the merge gate. Chaos is nightly by convention.
- Does not generate component-level chaos with MSW (Vitest-level fuzzing is out of scope).
- Does not edit the user's CI config — the convention above is a manual paste.
- Does not introduce non-determinism into existing tests. The fixture is opt-in via explicit import.

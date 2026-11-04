# Flaky tests — triage and quarantine

Read when a test passes and fails without a code change. A flaky test is a bug in the
test, the app, or the environment. Retries detect flakes; they are not a fix.

## 1. Reproduce

```bash
npx playwright test <spec> --repeat-each=20 --workers=4 --trace=on
```

No failure in 20 runs locally: suspect CI differences. Otherwise open the trace
(`npx playwright show-trace <trace.zip>`) and look for slow requests, actions before
the page is ready, and console errors.

## 2. Classify (decision tree)

```
Flaky test
├─ Passes alone?
│   ├─ yes: another test creates data it needs -> ORDER dependency
│   │       shared DB/file/cache or missing cleanup -> DATA dependency
│   └─ no: continue
├─ Fails more in CI than locally?
│   ├─ yes: timeout -> TIMING
│   │       ECONNREFUSED/ETIMEDOUT, OOM, disk, runner load -> ENVIRONMENT
│   └─ no: continue
├─ Fails near midnight, month end, or a given hour? -> TIME sensitivity
├─ Screenshot or visual compare? -> VISUAL rendering
├─ Real HTTP to a third party? -> EXTERNAL service
└─ else -> TIMING (an async step is not awaited)
```

## 3. Fix by category

| Category | Fix |
|----------|-----|
| Timing | Wait for a condition (`expect(...).toBeVisible()`, `waitForResponse`), never `waitForTimeout` |
| Data / order | Per-test data with unique ids; cleanup in the fixture's post-`use` block |
| Environment | Mock externals; more runner resources; do not count contention failures as flakes |
| Time | Pin the clock (`page.clock.setFixedTime`); use relative dates |
| Visual | See `screenshot-tests.md` (mask, freeze, disable animations) |
| External | Stub with `page.route` + `route.fulfill` |

## 4. Quarantine

Only while a fix is pending. Tag with a date and ticket:

```ts
test('ws reconnect', {
  tag: ['@quarantine'],
  annotation: { type: 'quarantine', description: 'Flaky since <YYYY-MM-DD>, <ticket>' },
}, async ({ page }) => { /* ... */ });
```

```ts
// playwright.config.ts
projects: [
  { name: 'stable', grep: /^(?!.*@quarantine)/ },
  { name: 'quarantine', grep: /@quarantine/, retries: 3 },
],
```

CI: `--project=stable` blocks the merge; `--project=quarantine` runs with
`continue-on-error: true`.

Rules:

- **14-day maximum.** After 14 days fix or delete the test.
- Every entry has a ticket and a date. No anonymous quarantine.
- Review the list weekly; escalate aging entries.
- More than 5% of tests quarantined is a process problem, not a test problem.
- Never `test.skip('flaky')` without a ticket; that is dead code.

Lifecycle: detect, tag, isolate, diagnose, fix, verify, release.

## 5. Verify and release

```bash
npx playwright test <spec> --repeat-each=50 --workers=4
```

Require 50/50 passes (in CI conditions too), then drop the `@quarantine` tag.

Adapted from qa-skills (https://github.com/petrkindlmann/qa-skills), MIT, Copyright (c) 2026 Petr Kindlmann.

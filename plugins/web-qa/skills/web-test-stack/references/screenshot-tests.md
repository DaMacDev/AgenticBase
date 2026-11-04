# Screenshot tests — Playwright toHaveScreenshot

Read when adding visual regression tests. Built-in and free: no hosted service, baselines
live in the repo. Screenshot tests complement functional tests; they do not replace them.

## Basic test

```ts
test('dashboard matches baseline', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible(); // never waitForTimeout
  await expect(page).toHaveScreenshot('dashboard.png', { animations: 'disabled' });
});
```

The first run writes the baseline; later runs compare.

## Config

```ts
// playwright.config.ts
expect: {
  toHaveScreenshot: { maxDiffPixelRatio: 0.005, animations: 'disabled', caret: 'hide' },
},
```

| Option | Use for |
|--------|---------|
| `maxDiffPixels: 0` | Icons, logos, small design-system parts |
| `maxDiffPixelRatio: 0.005` | Full pages (sub-pixel rendering varies) |
| `threshold: 0.2` | Cross-browser color differences |

Start strict, loosen per component, and note why. Prefer element screenshots
(`expect(locator).toHaveScreenshot()`) over full pages: more stable and focused.

## Kill noise

- `mask: [locator, ...]` for avatars, timestamps, feeds.
- `stylePath` stylesheet to hide carets and zero animation durations.
- Pin the clock: `page.clock.setFixedTime(...)`; stub data with `page.route` + `route.fulfill`.
- Exclude components that change by design (A/B tests, rotating banners).

## Baselines

- Generate them in the same image CI uses (e.g. `mcr.microsoft.com/playwright:v<version>-noble`,
  matching your `@playwright/test` version). Never commit laptop-rendered baselines;
  files are tagged per platform, so a mismatch fails every run.
- Update intentionally: `npx playwright test <spec> --update-snapshots`, then review the
  before/after images in `npx playwright show-report`, not just the file diff.
- Large PNGs bloat history: track them with Git LFS (`*.png filter=lfs diff=lfs merge=lfs -text`).
- CI uploads expected/actual/diff images as artifacts and blocks the merge on a diff.

## Responsive

Reuse the device projects from `responsive-matrix-setup.md` rather than a second viewport
list: name visual specs `*.visual.spec.ts`, give them their own project with `testMatch`, and
`testIgnore` them in the device projects so one spec is not snapshotted per device.

## Verify

```bash
npx playwright test --grep visual   # run twice: first writes baselines, second passes
```

If screenshots flake, classify with `flaky-tests.md` (VISUAL rendering).

Adapted from qa-skills (https://github.com/petrkindlmann/qa-skills), MIT, Copyright (c) 2026 Petr Kindlmann.

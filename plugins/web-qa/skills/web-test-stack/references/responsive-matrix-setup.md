# Responsive device matrix: setup

# Playwright matrix bootstrap

Drops in a `playwright.config.ts` with a three-device matrix (Desktop
Chrome, iPhone 15 Pro, Pixel 8) and an example spec demonstrating the
role-based selector + `@axe-core/playwright` + tag conventions.

Idempotent — does not overwrite an existing config.

**Companion skill:** `/web-qa:web-test-stack audit` audits the
suite after bootstrap. Run that one routinely; run *this* one once per
project.

## Step 1 — Preflight

```
Glob <project-dir>/package.json
Glob <project-dir>/playwright.config.{ts,js,mjs}
```

- If no `package.json` → stop.
- If `@playwright/test` not in devDependencies → stop, recommend
  `/web-qa:web-test-stack`.
- If `playwright.config.*` exists → do not overwrite; print
  "config already exists — switching to audit mode" and run the audit
  scan from `/web-qa:web-test-stack audit` instead.

## Step 2 — Write `playwright.config.ts`

```ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI
    ? [['github'], ['html', { open: 'never' }]]
    : 'list',
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:3737',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'desktop-chrome',
      use: { ...devices['Desktop Chrome'] },
      grep: /@desktop|@all/,
      grepInvert: /@mobile/,
    },
    {
      name: 'iphone-15-pro',
      use: { ...devices['iPhone 15 Pro'] },
      grep: /@mobile|@all/,
    },
    {
      name: 'pixel-8',
      use: { ...devices['Pixel 8'] },
      grep: /@mobile|@all/,
    },
  ],
});
```

The `grep` / `grepInvert` pair enforces the tag convention at runtime —
untagged tests do not run on any project, which is intentional (forces
the author to choose a target). Run
`/web-qa:web-test-stack audit` to find untagged tests.

## Step 3 — Write `tests/e2e/example.spec.ts` if missing

```ts
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test('@desktop @all dashboard heading renders', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  const a11y = await new AxeBuilder({ page }).analyze();
  expect(a11y.violations).toEqual([]);
});

test('@mobile primary nav collapses to drawer', async ({ page }) => {
  await page.goto('/');
  const drawerToggle = page.getByRole('button', { name: /menu/i });
  await expect(drawerToggle).toBeVisible();
});
```

Demonstrates: role-based selector (not `data-testid`), in-test axe-core
scan, `@desktop` / `@mobile` / `@all` tag pattern.

## Step 4 — Next steps (manual paste, not automated)

Print to the user:

> Add to `package.json` scripts:
>
> ```json
> "test:e2e":        "playwright test",
> "test:e2e:headed": "playwright test --headed",
> "test:a11y":       "playwright test --grep @a11y"
> ```
>
> Add this CI job (manual paste — this skill does not edit CI config).
>
> ```yaml
> playwright-e2e:
>   runs-on: ubuntu-latest
>   timeout-minutes: 15
>   steps:
>     - uses: actions/checkout@v4
>     - uses: actions/setup-node@v4
>       with: { node-version: lts/*, cache: npm }
>     - run: npm ci
>     - name: Cache Playwright browsers
>       uses: actions/cache@v4
>       with:
>         path: ~/.cache/ms-playwright
>         key: playwright-${{ hashFiles('package-lock.json') }}
>     - run: npx playwright install --with-deps chromium
>     - run: npm run build
>     - run: npm run start &
>     - run: npx wait-on http://localhost:3737
>     - run: npm run test:e2e
>     - if: failure()
>       uses: actions/upload-artifact@v4
>       with: { name: playwright-report, path: playwright-report/ }
> ```
>
> Then run `/web-qa:web-test-stack audit` to audit the suite as it grows.











## What this does NOT do

- Does not audit existing tests — that's `/web-qa:web-test-stack audit`.
- Does not add Firefox / WebKit projects — Chromium-only matrix is the deliberate baseline; revisit when the app needs cross-browser coverage.
- Does not edit `package.json` scripts or `.github/workflows/` — manual paste from Step 4. Editing CI config from a skill is too easy to get wrong.
- Does not run the tests. CI does that.

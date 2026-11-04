# Accessibility specs — axe (WCAG 2.2 AA) and keyboard

Read when adding or auditing a11y tests. axe catches roughly 30-40% of issues. It has
no rule for 2.4.11 (focus not obscured) or 2.5.7 (dragging), and only partial 2.5.8
(target size). A green axe run is not 2.2 AA conformance: pair it with the keyboard specs
and a manual check of those criteria.

## Install

Step 3 installs it; keep its version exact (its minor tracks the axe-core rule set, so review each bump):

```bash
npm install --save-dev --save-exact @axe-core/playwright@<version from npm view>   # only if the range is not exact
```

## Helper

Use the cumulative tags; `wcag22aa` alone does not select the older criteria. Avoid
`best-practice`: those rules are not WCAG criteria.

```ts
// tests/e2e/helpers/a11y.ts
import { type Page, type TestInfo, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

export async function checkAccessibility(
  page: Page, testInfo: TestInfo,
  o: { expectedURL: string | RegExp; ready: () => Promise<void>; exclude?: string[]; disableRules?: string[] },
) {
  // A blank, error or redirected page passes axe, so prove page and state first.
  await expect(page).toHaveURL(o.expectedURL);
  await o.ready();
  let b = new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']);
  for (const s of o.exclude ?? []) b = b.exclude(s);
  if (o.disableRules?.length) b = b.disableRules(o.disableRules);
  const r = await b.analyze();
  await testInfo.attach('a11y-results', { body: JSON.stringify(r, null, 2), contentType: 'application/json' });
  expect(r.passes.length + r.violations.length + r.incomplete.length, 'axe evaluated no rules').toBeGreaterThan(0);
  expect(r.violations.map((v) => ({ rule: v.id, impact: v.impact, helpUrl: v.helpUrl })))
    .toEqual([]);
}
```

## Page and state specs

Loop every key page, then scan interactive states (open modal, expanded menu, error
state, signed-in view), not only the default load.

```ts
test('modal is accessible when open', async ({ page, baseURL }, testInfo) => {
  const expectedURL = new URL('/dashboard', baseURL!).href;
  await page.goto(expectedURL);
  await page.getByRole('button', { name: 'Create project' }).click();
  await checkAccessibility(page, testInfo, {
    expectedURL,
    ready: () => expect(page.getByRole('dialog', { name: 'Create project' })).toBeVisible(),
  });
});
```

Suppress a rule only with a tracking issue in an inline comment; `exclude` third-party
widgets instead of disabling a rule globally. For a page you cannot fix, assert the exact
set of known rule ids so a new or fixed violation changes the test.

## Keyboard specs

```ts
test('skip link moves focus to main', async ({ page }) => {
  await page.goto('/');
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link', { name: /skip to (main )?content/i })).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('main')).toBeFocused();
});

test('modal closes on Escape and returns focus', async ({ page }) => {
  await page.goto('/dashboard');
  const trigger = page.getByRole('button', { name: 'Create project' });
  await trigger.click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  await expect(trigger).toBeFocused();
});

test('form is completable by keyboard', async ({ page }) => {
  await page.goto('/signup');
  await page.keyboard.press('Tab');
  await page.keyboard.type('Jane Doe');
  // ...Tab through each field, Space on checkboxes, Enter to submit
  await expect(page).toHaveURL(/\/welcome/);
});
```

Manual checklist: logical tab order, every control reachable, visible focus (no bare
`outline: none`), Enter/Space activate, Escape closes, arrows move inside tabs/menus/radios,
no keyboard traps outside modals.

Also assert ARIA state per interactive state: `aria-expanded` on menus, `aria-busy`
while loading, `aria-live` on toasts, `aria-invalid` + `aria-describedby` on form errors.
`toMatchAriaSnapshot()` on a stable container catches semantic regressions; avoid
whole-page snapshots over async content.

## Verify the suite is real

Plant a defect (remove a `<label>`): the scan must fail and name the rule. If it still
passes, axe is scanning the wrong DOM. In CI run `npx playwright test tests/e2e/a11y/`
as a blocking job and upload `test-results/` and `playwright-report/`.

Adapted from qa-skills (https://github.com/petrkindlmann/qa-skills), MIT, Copyright (c) 2026 Petr Kindlmann.

---
name: form-fuzz
description: Throw adversarial input at a web form — emoji, RTL text, huge strings, injection-shaped payloads — to catch validation and crash bugs before users do. Use when the user says "fuzz this form", "test weird/malicious input", "can this form be broken", or wants property-based testing of input handling. Generates a fast-check arbitrary + Playwright helper in tests/fixtures/form-fuzz.ts; safe to re-run. For network-fault chaos see /web-qa:chaos-harness.
user-invocable: true
argument-hint: "[project-dir]"
allowed-tools: Read, Glob, Write(tests/fixtures/form-fuzz.ts)
---

# /form-fuzz — fast-check form-input fuzzing fixture

Codifies the `fast-check` property-test pattern for forms. Drops in one
opt-in fixture file; existing tests are not modified.

Requires `@playwright/test` and `fast-check`. If either is missing, point
the user to `/web-qa:web-test-stack` and exit.

**Companion skill:** `/web-qa:chaos-harness` covers network-side
chaos via `page.route()`. The two are independent — use one, both, or
neither.

## Step 1 — Preflight

```
Glob <project-dir>/package.json
Glob <project-dir>/tests/fixtures/
```

Verify `@playwright/test` AND `fast-check` in devDependencies. Stop and
recommend `web-test-stack` if either is missing.

If `tests/fixtures/form-fuzz.ts` exists, print "already initialised" and
exit.

## Step 2 — Write `tests/fixtures/form-fuzz.ts`

```ts
import fc from 'fast-check';
import { type Page } from '@playwright/test';

/**
 * Adversarial-input arbitrary for form fields. Covers the failure classes
 * that crash real apps: empty, oversize, RTL override, NUL, emoji / ZWJ,
 * SQL-injection shape, XSS shape, whitespace-only, lone unicode surrogates.
 */
export const formInputArb = fc.oneof(
  fc.constant(''),                                          // empty
  fc.string({ minLength: 1024, maxLength: 4096 }),          // oversize
  fc.constantFrom('\u202Eadmin', '\u202Eevil'),            // RTL override
  fc.constant('\u0000'),                                    // NUL byte
  fc.constantFrom('🦀', '👨‍👩‍👧‍👦', '🇩🇰'),                       // emoji / ZWJ / flag
  fc.constantFrom("' OR 1=1 --", "1; DROP TABLE users--"),  // SQL-ish
  fc.constantFrom('<script>alert(1)</script>', '"><img/onerror=1>'),  // XSS-ish
  fc.constantFrom('   ', '\t\n\t', '\u00A0\u2003'),         // whitespace, NBSP, em space
  fc.constantFrom('\uD800', 'a\uDC00b'),                    // lone surrogates
);

type FuzzOptions = {
  runs?: number;
  seed?: number;
};

/**
 * Fuzz a single input. Property: the page must never throw; the form must
 * either submit successfully OR show a validation error — never crash or
 * hang.
 *
 * Usage:
 *   await runFormFuzz(page, '[name="email"]', '[type="submit"]');
 */
export async function runFormFuzz(
  page: Page,
  inputSelector: string,
  submitSelector: string,
  options: FuzzOptions = {},
) {
  const { runs = 100, seed } = options;
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));

  await fc.assert(
    fc.asyncProperty(formInputArb, async (input) => {
      errors.length = 0;
      await page.locator(inputSelector).fill(input);
      await page.locator(submitSelector).click();
      // Either a success indicator OR a validation message must appear;
      // a hanging spinner or no DOM change is a failure.
      await page.waitForFunction(
        () =>
          document.querySelector('[role="alert"], [data-testid="success"], [aria-invalid="true"]') !== null,
        { timeout: 2000 },
      );
      if (errors.length > 0) {
        throw new Error(`pageerror on input ${JSON.stringify(input)}: ${errors.join('; ')}`);
      }
    }),
    { numRuns: runs, seed },
  );
}
```

## Step 3 — Caller contract

Print to the user:

> Form-fuzz fixture dropped at `tests/fixtures/form-fuzz.ts`. Opt in per test:
>
> ```ts
> import { runFormFuzz } from '../fixtures/form-fuzz';
>
> test('@chaos signup form survives adversarial input', async ({ page }) => {
>   await page.goto('/signup');
>   await runFormFuzz(page, '[name="email"]', '[type="submit"]');
> });
> ```
>
> **CI convention:** tag fuzz tests `@chaos` so they run nightly, not per-PR — 100 runs per arbitrary takes too long for the merge gate.
>
> **Seed:** `runFormFuzz(page, ..., { seed: 12345 })` for reproducible failures. fast-check prints the failing input as a counter-example on assertion failure.

## Step 4 — What this catches / What this misses

**Catches:**
- Form inputs that crash the page (uncaught exceptions on weird unicode, oversize, etc.).
- Forms that hang (no validation feedback AND no submit success).
- XSS sinks where adversarial input renders unsanitised.
- SQL-injection shapes reaching the server unfiltered (if the test inspects the network).

**Misses:**
- Real backend validation logic — only verifies the front-end doesn't crash.
- Server-side input filtering — back-end concern.
- Network chaos — covered by `/web-qa:chaos-harness`.

## What this does NOT do

- Does not run against production. Fuzzing live endpoints is forbidden.
- Does not add tests to the merge gate. Tag `@chaos` and run nightly.
- Does not generate field-specific arbitraries — `formInputArb` is generic. Author per-field arbitraries inline when the form has structured rules (e.g. an email field where only legal-but-edge-case emails are interesting).

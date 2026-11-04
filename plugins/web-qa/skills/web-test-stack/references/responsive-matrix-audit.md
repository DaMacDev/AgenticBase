# Responsive device matrix: audit an existing suite

# Playwright tag + selector audit

Read-only audit of an existing Playwright suite. Flags the four smell
classes that defeat a `projects` matrix: missing tags, Tailwind-class
selectors, inline viewport calls, hardcoded waits.

**Companion skill:** `/web-qa:web-test-stack setup` generates
the initial `playwright.config.ts` and an example spec. Use it once per
project; use *this* skill repeatedly to keep the suite clean.

## Step 1 — Preflight

```
Glob <project-dir>/package.json
Glob <project-dir>/playwright.config.{ts,js,mjs}
```

- If no `package.json` → stop.
- If `@playwright/test` not in devDependencies → stop, recommend
  `/web-qa:web-test-stack`.
- If no `playwright.config.*` → stop, recommend
  `/web-qa:web-test-stack setup`.
- If no `tests/e2e/**/*.{spec,test}.{ts,tsx}` files → print "no Playwright
  tests yet — nothing to audit" and exit.

## Step 2 — Tag convention (what the audit enforces)

Every Playwright test title MUST include exactly one of:

- `@desktop` — assertions specific to desktop layout, hover, keyboard
  shortcuts, wide-table layouts.
- `@mobile` — assertions specific to touch interaction, virtual keyboard,
  drawer/sheet UI, narrow-viewport reflow.
- `@all` — content/behaviour assertion that must hold on every project.

A test without any tag will not run on any project (the
setup-mode config uses `grep` / `grepInvert` to enforce
this). The suite passes silently and the regression goes uncaught — that
is the failure mode this audit catches.

## Step 3 — Audit scan

```
Glob <project-dir>/tests/e2e/**/*.{spec,test}.{ts,tsx}
```

For each file, search for these patterns via `Grep -n` and collect findings:

| Pattern | Finding | Severity |
|---|---|---|
| `test\(['"]\s*((?!@desktop)(?!@mobile)(?!@all).)*?['"]` | **MISSING TAG** — test has no `@desktop` / `@mobile` / `@all` tag in its title | FAIL |
| `\bwaitForTimeout\(\s*[1-9]` | **HARDCODED WAIT** — use `expect(locator).toBeVisible()` / `waitFor(...)` instead | FAIL |
| `\.locator\(['"]\.([a-zA-Z][\w-]*\b)+['"]` (Tailwind class selector) | **VIEWPORT-COUPLED SELECTOR** — prefer `getByRole` / `getByText` | PARTIAL |
| `:nth-child\(` or `:nth-of-type\(` | **POSITIONAL SELECTOR** — fragility class | PARTIAL |
| `\bpage\.setViewportSize\b` | **INLINE VIEWPORT** — viewport belongs in the project matrix | PARTIAL |

## Step 4 — Audit report

```
responsive-test-matrix audit — <project>

Tag coverage:
  total tests: N
  @desktop: N    @mobile: N    @all: N    untagged: N  ← FAIL if > 0

Findings:
  tests/e2e/foo.spec.ts:12  MISSING TAG          test('opens drawer', ...)
  tests/e2e/bar.spec.ts:34  VIEWPORT-COUPLED     .locator('.md\\:w-[200px]')
  tests/e2e/baz.spec.ts:7   INLINE VIEWPORT      page.setViewportSize(...)
  tests/e2e/qux.spec.ts:55  POSITIONAL SELECTOR  :nth-child(3)
  tests/e2e/quux.spec.ts:9  HARDCODED WAIT       waitForTimeout(2000)

Verdict: PASS | FAIL (N MISSING-TAG or HARDCODED-WAIT) | PARTIAL (N PARTIAL findings only)
```

Verdict rules:
- **PASS** — zero findings of any class.
- **FAIL** — any MISSING TAG or HARDCODED WAIT (these break the project matrix or introduce flake).
- **PARTIAL** — VIEWPORT-COUPLED / POSITIONAL / INLINE VIEWPORT findings only (legitimate exceptions exist — e.g. testing a popover that genuinely uses a positional selector). Flag but don't block.

## What this does NOT do

- Does not modify any file. Read-only by design: audit mode writes nothing.
- Does not run the tests. CI does that.
- Does not generate the matrix config. Use `/web-qa:web-test-stack setup`.
- Does not check for missing axe-core scans in Playwright specs — that's the reviewer agent's UI test-smell checklist.

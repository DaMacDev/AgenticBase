---
name: web-test-stack
description: Set up or audit the web-UI test + lint stack in a React/Next.js project — Playwright with a phone/desktop device matrix, testing-library/jsx-a11y/playwright (+ @shadcn/lint on Tailwind) ESLint plugins, axe accessibility checks, fast-check, Lighthouse CI config — or audit an existing Playwright suite for viewport-unsafe tests. Use when a fresh web project has no UI test tooling, when the user says "set up UI testing", "test on mobile", "add accessibility checks", when tests fail only on mobile, or for a "flaky test" or "screenshot test". Setup is idempotent.
user-invocable: true
argument-hint: "[setup|audit] [project-dir]  (defaults: setup, cwd)  [--migrate-flat]"
allowed-tools: Read, Glob, Grep, Write(lighthouserc.json), Write(playwright.config.ts), Write(tests/e2e/**), Edit(eslint.config.*), Edit(.eslintrc.*), Bash(npm install --save-dev --save-exact:*), Bash(npx playwright install:*), Bash(npm run lint)
---

# /web-test-stack — web UI test tooling

Two modes. **setup** (default) runs the bootstrap below, then adds the phone/desktop
device matrix from `references/responsive-matrix-setup.md`. **audit** reports on an
existing suite using `references/responsive-matrix-audit.md` (read-only).

Drops the 2025-2026 consensus lint + test stack into a React/Next.js project
in one idempotent run. The pre-approved `Bash` commands are `npm install --save-dev
--save-exact`, `npx playwright install` and `npm run lint` — anything else asks first
(the references describe commands the user runs). On Linux, `--with-deps` installs
system libraries with sudo.

After setup, the related skills are ready to use:
- `/web-qa:chaos-harness` (network-fault fixture)
- `/web-qa:form-fuzz` (adversarial form-input fixture)




## Step 1 — Detect project shape

```
Glob <project-dir>/package.json
Glob <project-dir>/eslint.config.{js,mjs,cjs,ts}
Glob <project-dir>/.eslintrc.{json,js,cjs}
```

- If no `package.json` → stop. Tell the user "not a Node project; nothing to do."
- If neither ESLint config form is found → stop. Tell the user "no ESLint
  config detected; install one (`next lint` for Next.js projects) and re-run."
- If both forms coexist → stop. Tell the user to consolidate first.

Print the detected shape: framework (Next.js version from `package.json`
dependencies), ESLint format (legacy `.eslintrc.json` vs flat
`eslint.config.js`), shadcn: yes/no. shadcn is "yes" only when all three hold:
`tailwindcss` major 4 or later in `dependencies` or `devDependencies` (the
plugin targets v4), `eslint` 9.30 or later, and flat config. Otherwise print
the failing condition, e.g. "shadcn: no (Tailwind 3)", "shadcn: no (ESLint
9.12, needs 9.30)" or "shadcn: no (legacy config; migrate to flat, then
re-run)", and treat the project as non-shadcn in every later step.

## Step 2 — Idempotency check

Read `package.json`. For each of these devDependencies, add to `missing[]`
if absent:

- `@playwright/test`
- `eslint-plugin-playwright`
- `eslint-plugin-testing-library`
- `eslint-plugin-jsx-a11y`
- `@axe-core/playwright`
- `fast-check`
- `@shadcn/lint` (shadcn projects only)

Also check:
- `lighthouserc.json` exists at project root
- ESLint config already extends the three plugin recommendeds (and, on a
  shadcn project, has the `shadcn` plugin block)

If `missing.length === 0` AND `lighthouserc.json` exists AND the ESLint
config is wired → print "already initialised" and exit. Do not reinstall or
reconfigure.

## Step 3 — Install missing dependencies

```bash
npm install --save-dev --save-exact <missing-space-separated>
npx playwright install --with-deps chromium
```

Chromium-only by deliberate baseline (the project matrix
adds device emulation, not browser variety). Adding WebKit/Firefox is a
revisit trigger, not a default.

If `npm install` fails (network, registry, lockfile), stop and report — do
not proceed to ESLint changes.

## Step 4 — Wire ESLint (legacy `.eslintrc.json` path)

Read the file. Preserve every existing entry. Append the three plugins to
`extends` (in this order, after any existing presets), and add the
Playwright-only override scoped to `tests/e2e/**`:

```json
{
  "extends": [
    "next/core-web-vitals",
    "plugin:jsx-a11y/recommended",
    "plugin:testing-library/react",
    "plugin:playwright/recommended"
  ],
  "overrides": [
    {
      "files": ["tests/e2e/**/*.{ts,tsx}"],
      "extends": ["plugin:playwright/recommended"]
    }
  ]
}
```

Use the `Edit` tool, not `Write` — preserve unrelated keys (custom rules,
parser options, ignorePatterns).

`@shadcn/lint` is never installed or wired here: its README documents flat
config only, no `.eslintrc` preset and no `extends` string (Step 1 already
printed the skip).

## Step 5 — Wire ESLint (flat `eslint.config.js` path)

Read the file. Append three new entries (four on a shadcn project) to the
exported array; do not reorder existing entries. Sample append (TypeScript flat config):

```js
import jsxA11y from 'eslint-plugin-jsx-a11y';
import testingLibrary from 'eslint-plugin-testing-library';
import playwright from 'eslint-plugin-playwright';

export default [
  // ...existing entries...
  jsxA11y.flatConfigs.recommended,
  { ...testingLibrary.configs['flat/react'], files: ['**/*.test.{ts,tsx}'] },
  { ...playwright.configs['flat/recommended'], files: ['tests/e2e/**/*.{ts,tsx}'] },
];
```

shadcn projects (Step 1) also add `@shadcn/lint`, scoped to app source, not
tests. WHY: design-token discipline on generated UI; raw hex colours, arbitrary
Tailwind values and inline styles fail lint instead of review. Keep the
project's existing parser (add `@typescript-eslint/parser` only if none):

```js
import { plugin as shadcn } from '@shadcn/lint';

export default [
  // ...existing entries...
  {
    files: ['{src,app}/**/*.{ts,tsx}'],
    ignores: ['**/*.{test,spec}.{ts,tsx}', '**/__tests__/**', '**/*.stories.{ts,tsx}'],
    plugins: { shadcn },
    rules: {
      'shadcn/no-raw-colors': 'error',
      'shadcn/no-arbitrary-values': 'error',
      'shadcn/no-inline-styles': 'error',
    },
  },
];
```

The package exports `plugin`; it ships no `configs` preset, so list the rules.

If the file is JavaScript (`.js`/`.mjs`/`.cjs`) instead of TypeScript,
mirror the import shape. Do not convert legacy to flat unless the user
passed `--migrate-flat`.

## Step 6 — Write `lighthouserc.json`

At project root. Idempotent — if the file exists, do not overwrite; print
a diff hint instead.

```json
{
  "ci": {
    "collect": {
      "url": ["http://localhost:3737"],
      "numberOfRuns": 3
    },
    "assert": {
      "preset": "lighthouse:recommended",
      "assertions": {
        "categories:performance": ["warn", { "minScore": 0.85 }],
        "categories:accessibility": ["error", { "minScore": 0.95 }],
        "categories:best-practices": ["warn", { "minScore": 0.9 }]
      }
    }
  }
}
```

The accessibility threshold is `error` (blocks); performance and
best-practices are `warn` to avoid flake-driven CI failures while still
surfacing regressions.

## Step 7 — Verify

```bash
npm run lint
```






Report the exit code and any new warnings/errors. If the project's CI
gate is `--max-warnings 0`, a new warning
breaks the build — the user must triage before merging.

Then print the next-step pointer:

> Next steps:
> - The device matrix from `references/responsive-matrix-setup.md` (setup mode continues with it).
> - `/web-qa:chaos-harness` and `/web-qa:form-fuzz` to drop in the chaos and form-fuzz fixtures.




## Step 8 — Test discipline references

Read on demand; not part of setup.

- `references/flaky-tests.md` — a test passes and fails with no code change: triage tree, 14-day quarantine.
- `references/a11y-specs.md` — adding or auditing axe (WCAG 2.2 AA) and keyboard-navigation specs.
- `references/screenshot-tests.md` — adding `toHaveScreenshot` visual regression tests.

## What this does NOT do

- Does not modify `vitest.config.ts` (coverage thresholds untouched).
- Does not add a CI job (the example workflow snippet lives in
  `references/responsive-matrix-setup.md` and is a manual paste — the skill cannot edit
  the user's CI configuration safely).
- Does not write a `CLAUDE.md` to the target project.
- Does not configure Husky / lint-staged / commit hooks.




- Does not run a security scan on the newly installed packages — run `npm audit` after rollout.

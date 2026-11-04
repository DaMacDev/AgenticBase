# web-qa

Three skills for testing web UIs with Playwright:

- **web-test-stack** sets up Playwright with a phone and desktop device matrix, the jsx-a11y, testing-library and Playwright ESLint plugins, axe accessibility checks, fast-check and a Lighthouse CI config. Its `audit` mode finds tests that break on small screens.
- **form-fuzz** adds a fixture that throws adversarial input at a form (emoji, right-to-left text, huge strings, injection-shaped payloads) and fails when the page crashes or hangs.
- **chaos-harness** adds a fixture that injects latency, 5xx errors and offline windows into end-to-end tests.

Fuzz and chaos tests are tagged `@chaos` and meant for a nightly run, not every pull request.

## Install

```
/plugin marketplace add DaMacDev/AgenticBase
/plugin install web-qa@agenticbase
```

Then ask for it ("set up UI testing", "fuzz this form", "simulate a flaky network") or run `/web-qa:web-test-stack`.

## What it runs

Skills are instructions, not programs. When you use one, Claude writes test fixtures and lint config into your project and runs your lint and test commands. `web-test-stack` installs npm dev packages (`npm install --save-dev --save-exact`) and the Chromium browser (`npx playwright install --with-deps chromium`; on Linux `--with-deps` installs system libraries with sudo). While a skill is active, reads, writes to the fixture, Playwright, Lighthouse and ESLint config files and `tests/e2e/`, those two install commands and `npm run lint` are pre-approved; any other file or command asks first. Nothing is sent anywhere by the skills themselves. It targets Node web projects (React or Next.js) with an ESLint config.

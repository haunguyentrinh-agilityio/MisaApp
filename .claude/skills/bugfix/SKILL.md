---
name: bugfix
description: Bug-fix workflow — reproduce with a failing automated test, find the root cause, fix minimally, verify. Use when the user reports a bug, error, failing test, or unexpected behavior.
argument-hint: <bug description, error message, or failing test>
---

# Bug-fix workflow

Bug: **$ARGUMENTS**

1. **Gather evidence**
   - Error text, stack traces, `docker compose logs --since 1h backend frontend`, browser console (ask the user if needed).
   - Identify the layer: frontend (including `localStorage`), API, Gemini, Docker/infra.

2. **Reproduce with a test** — before changing production code:
   - API/data bug → xUnit integration test with `ApiFactory`.
   - UI bug → Vitest/RTL test.
   - Cross-layer or environment bug → Playwright spec, or a manual repro script if not automatable (say why).
   - Run it and confirm it **fails for the right reason**.

3. **Root cause**
   - Explain the cause in 1–3 sentences. If it's a symptom of a broader issue, say so, but keep the fix scoped.

4. **Fix**
   - Smallest change that makes the test pass and matches surrounding conventions.
   - Look for the same bug pattern elsewhere (`Grep`) and list hits; fix them only if trivial and clearly identical.

5. **Verify**
   - Re-run the new test, then the affected suite. For infra/E2E bugs, run the Playwright suite in Docker.

6. **Report**
   - Cause, fix, test added, anything left open (add to `docs/backlog.md` if follow-up is needed).
   - Propose a commit message (`fix(<area>): ...`). Don't commit unless asked.

---
name: verify
description: Run every quality gate in this repo (backend tests, frontend lint/typecheck/tests/build, Docker build, Playwright E2E) and report a pass/fail table. Use before committing, after a feature or fix, or when the user asks "is everything green?".
---

# Verify

Run the gates below. Run independent gates in parallel. Don't stop at the first failure; collect all results, then report.

| # | Gate                | Command (cwd)                                                                 |
|---|---------------------|-------------------------------------------------------------------------------|
| 1 | Backend build+tests | `dotnet test` (`backend/`)                                                    |
| 2 | Frontend lint       | `pnpm lint` (`frontend/`)                                                     |
| 3 | Frontend typecheck  | `pnpm typecheck` (`frontend/`)                                                |
| 4 | Frontend unit tests | `pnpm test` (`frontend/`)                                                     |
| 5 | Frontend build      | `pnpm build` (`frontend/`)                                                    |
| 6 | Docker stack        | `docker compose up -d --build` (root), then wait for `/api/health` to return 200 |
| 7 | E2E                 | `docker compose --profile e2e run --rm --build playwright` (root)             |
| 8 | Hygiene             | `git status --short`; grep the diff for `console.log`, `debugger`, `.only(`, TODO without an owner, secrets/API keys |

Notes:
- If local Node is < 24, run gates 2–5 in a `node:24-alpine` container (see `CLAUDE.md`).
- If Docker isn't running, mark 6–7 as ⏭ skipped and say so; don't claim they passed.
- If the dev overlay (`compose.dev.yaml`) is what's running, pass both `-f` files to gate 7.

## Output

```
| Gate | Result | Notes |
|------|--------|-------|
| Backend tests | ✅ 11 passed | |
| ...           | ❌ | <first error line + file:line> |
```

For each ❌: the failing command, the key error lines, and a suggested next step (usually `/bugfix`). Never mark a gate as passed without having run it in this session.

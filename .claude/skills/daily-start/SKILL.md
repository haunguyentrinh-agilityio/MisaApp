---
name: daily-start
description: Morning check-in for this repo — summarize repo and stack state, surface what's in progress in docs/backlog.md, run fast checks, and propose today's plan. Use when the user says good morning, starts the day, or asks "where were we?".
disable-model-invocation: true
---

# Daily start

Goal: in a few minutes, get the user oriented and agree on today's focus. Do not change code in this workflow.

## Steps

1. **Repo state**
   - `git status --short` and `git log --oneline --since="2 days ago" -n 20`.
   - Note uncommitted work, the current branch, and anything that looks half-finished.

2. **Context from docs**
   - Read the latest file in `docs/dev-log/` (if any): what was done and what was left open.
   - Read `docs/backlog.md`: list items under **In progress** and the top 3 under **Next**.
   - Active Spec Kit feature: read `.specify/feature.json` (if present). In that feature's `tasks.md`, count `- [x]` against `- [ ]` and name the next open task.

3. **Stack health** (skip quietly if Docker isn't running, just say so)
   - `docker compose ps` — are `sqlserver`, `backend`, `frontend` up and healthy?
   - If the stack is up: `curl -fsS http://localhost:${WEB_PORT:-3000}/api/health`.
   - Scan `docker compose logs --since 12h backend | grep -iE "fail|error|exception"` for new problems.

4. **Fast checks** (run in parallel when possible)
   - `cd backend && dotnet test`
   - `cd frontend && pnpm lint && pnpm typecheck && pnpm test`
   - Don't run Playwright here; that's for `/verify`.

5. **Dependency drift** (only on Mondays, or if the user asks)
   - `cd backend && dotnet list package --outdated`
   - `cd frontend && pnpm outdated`
   - Mention security-relevant or major updates only.

## Output

A short report:

```
## Good morning — <date>
**Yesterday:** <1–3 bullets from dev-log/git log>
**Repo:** <branch, uncommitted changes>
**Stack:** <healthy / not running / issues>
**Checks:** backend ✅/❌  frontend ✅/❌
**In progress:** <items; active spec `specs/NNN-…` with tasks done/total and the next task>
**Suggested focus today:** <1–3 items, with the workflow to use, e.g. `/feature streaming replies`>
```

Then ask which item to start. If anything is failing, recommend fixing it first (`/bugfix`).

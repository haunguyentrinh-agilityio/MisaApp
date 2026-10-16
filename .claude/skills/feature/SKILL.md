---
name: feature
description: Spec-driven feature workflow for this repo — drives the Spec Kit skills (specify, clarify, plan, tasks, analyze, implement, converge) with review checkpoints, then adds this repo's backlog, Docker E2E, and /verify steps. Use when the user asks to add, build, or extend a feature.
argument-hint: <short feature description>
---

# Feature workflow (Spec Kit)

Feature request: **$ARGUMENTS**

Run the Spec Kit skills below in order. Stop at each ⏸ checkpoint and wait for the user's go-ahead.
The rules every step is checked against are in `.specify/memory/constitution.md`.

## 1. Specify ⏸
- Read `docs/backlog.md` for an existing entry and `docs/architecture.md` for context.
- Run `/speckit-specify <the feature request>`. It creates `specs/NNN-<slug>/spec.md` and, through
  the git extension, a `NNN-<slug>` branch. The spec covers *what* and *why*, not the stack.
- Move the item to **In progress** in `docs/backlog.md` and link the spec.
- ⏸ Summarize the user stories, acceptance scenarios, and open `[NEEDS CLARIFICATION]` markers.

## 2. Clarify (skip for small, unambiguous features)
- Run `/speckit-clarify` to resolve ambiguities; answers are written back into the spec.

## 3. Plan ⏸
- Run `/speckit-plan` with this repo's stack as input: .NET 10 minimal APIs in a feature folder,
  no database (the server is stateless), React 19 + Vite feature folder, xUnit v3 / Vitest + RTL /
  Playwright.
- Check `plan.md`, `data-model.md`, and `contracts/` against `CLAUDE.md`, `backend/CLAUDE.md`, and
  `frontend/CLAUDE.md`. Call out risks: breaking API changes, anything that would need server-side
  storage (a constitution amendment), LLM cost/latency.
- ⏸ Show the Constitution Check result and the API contract (routes, JSON, status codes).

## 4. Tasks ⏸
- Run `/speckit-tasks`, then `/speckit-analyze`. Fix every CRITICAL/HIGH finding in the source
  artifact and re-run analyze until it is clean.
- Make sure `tasks.md` includes: integration tests via `ApiFactory`, RTL tests, Playwright tests for
  each user-visible acceptance scenario.
- ⏸ Show the task phases and counts.

## 5. Implement
- Run `/speckit-implement`.
- After each phase: `cd backend && dotnet test`; in `frontend/`:
  `pnpm lint && pnpm typecheck && pnpm test && pnpm build`.
- E2E: `docker compose up -d --build`, then `docker compose --profile e2e run --rm --build playwright`.
  Never assert on LLM wording.

## 6. Converge
- Run `/speckit-converge`. If it appends tasks, go back to step 5. Repeat until it reports
  "Converged".

## 7. Wrap up ⏸
- Run `/verify`.
- Update `docs/architecture.md` if the shape of the system changed; move the backlog item to
  **Done** with a link to the spec.
- Self-review the diff (`git diff`): naming, dead code, secrets, missing tests.
- ⏸ Summarize what changed (files, endpoints, config) and propose a commit message. Don't
  commit unless asked.

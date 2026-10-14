---
name: daily-wrap-up
description: End-of-day routine — summarize today's changes into docs/dev-log, update docs/backlog.md, list open threads for tomorrow, and suggest commit messages. Use when the user says they're done for the day or asks to wrap up.
disable-model-invocation: true
---

# Daily wrap-up

1. **Collect what happened today**
   - `git status --short`, `git diff --stat`, `git log --oneline --since=midnight`.
   - This session's conversation: features worked on, decisions made, problems hit.

2. **Quick health check**
   - Run the fast checks: `dotnet test` (backend) and `pnpm lint && pnpm typecheck && pnpm test` (frontend). Note failures; don't fix them now unless trivial and the user agrees.

3. **Write the dev log** — create or append `docs/dev-log/YYYY-MM-DD.md`:

   ```markdown
   # YYYY-MM-DD

   ## Done
   - ...
   ## Decisions
   - <decision> — <why> (link spec/ADR if any)
   ## Open threads / tomorrow
   - [ ] ...
   ## Problems & learnings
   - ...
   ```

4. **Update `docs/backlog.md`**
   - Move finished items to **Done** (with date), keep **In progress** accurate, add new ideas or follow-ups under **Next** or **Later**.
   - For the active spec (`.specify/feature.json`), make sure `tasks.md` checkboxes match what was actually done today, and note the next open task in "Open threads".

5. **Commits**
   - If there are uncommitted changes, group them into logical commits and propose Conventional Commit messages (`feat(chat): ...`, `fix(api): ...`, `docs: ...`). Commit only if the user says so.

6. **Workflow feedback**
   - If any workflow step was slow, wrong, or skipped today, note it under "Problems & learnings" and suggest running `/improve-workflow`.

Finish with a 3–5 line summary for the user.

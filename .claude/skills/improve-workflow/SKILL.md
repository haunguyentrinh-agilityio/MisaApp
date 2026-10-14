---
name: improve-workflow
description: Review and improve this repo's Claude workflows (skills in .claude/skills, CLAUDE.md files, .claude/settings.json) based on recent friction, mistakes, or new conventions. Use when the user wants to tune how Claude works in this project.
disable-model-invocation: true
argument-hint: [what went wrong or what to change]
---

# Improve the workflows

Input from the user (may be empty): **$ARGUMENTS**

1. **Gather signal**
   - The user's input above.
   - "Problems & learnings" sections in the last ~5 files in `docs/dev-log/`.
   - Conventions that drifted: compare `CLAUDE.md`, `backend/CLAUDE.md`, `frontend/CLAUDE.md` against the actual code (folder layout, commands, test patterns).
   - Commands that triggered permission prompts repeatedly (ask the user) → candidates for `.claude/settings.json` `permissions.allow`.

2. **Diagnose** each issue as one of:
   - Missing/wrong instruction → edit the relevant `CLAUDE.md` (keep it short; facts and rules, not essays).
   - A project-wide rule that every spec/plan must obey → amend `.specify/memory/constitution.md` via `/speckit-constitution`, then align `CLAUDE.md`.
   - Spec Kit step behaving badly → adjust `/feature` or `CLAUDE.md`, or use a Spec Kit preset/override. Don't edit the generated `.claude/skills/speckit-*` or `.specify/templates|scripts`, because `specify init` overwrites them.
   - Workflow step missing, wrong order, or too vague → edit `.claude/skills/<name>/SKILL.md`.
   - Repeated manual sequence → propose a new skill (`.claude/skills/<new-name>/SKILL.md` with `name`, `description`, optional `argument-hint`, `disable-model-invocation`).
   - Something that must happen deterministically every time (formatting, blocking edits to `.env`) → propose a hook in `.claude/settings.json` instead of an instruction.

3. **Propose** a concise diff-style list of changes, with the reason for each. ⏸ Wait for approval.

4. **Apply** the approved changes, then:
   - Update the skills table in `CLAUDE.md` and `docs/claude-workflows.md` if skills were added/renamed.
   - Add a line to `docs/claude-workflows.md` → **Changelog** with the date and what changed.

<!--
Sync Impact Report
- Version change: 1.0.0 → 1.0.1 (PATCH: project renamed WebApp → MisaApp; no rule changes)
- Modified principles: I. Feature-Sliced Code (path now `backend/src/MisaApp.Api/...`)
- Added sections: none
- Removed sections: none
- Follow-up TODOs: none
-->

# MisaApp Constitution

## Core Principles

### I. Feature-Sliced Code

- Backend code for a feature MUST live in `backend/src/MisaApp.Api/Features/<Feature>/`: entities and
  their EF configuration, contracts, a scoped service, a `Map<Feature>Endpoints()` group under
  `/api/<feature>`, and an `Add<Feature>()` DI extension.
- Frontend code for a feature MUST live in `frontend/src/features/<feature>/`: components, a typed
  `<feature>Api.ts`, CSS, and tests.
- Only genuinely cross-cutting code goes in `backend/.../Data/` or `frontend/src/lib/`.
- Endpoint handlers stay thin; business logic lives in the feature service.
- New layers, projects, or architectural patterns (controllers, repositories, CQRS, state libraries)
  MUST be justified in the plan's Complexity Tracking table.

Rationale: everything for a feature is in one place, which keeps changes reviewable and specs map
one-to-one onto code.

### II. Tests Ship With Every Change (NON-NEGOTIABLE)

- Every endpoint MUST have an integration test through `ApiFactory`
  (`WebApplicationFactory<Program>` + SQLite in-memory, LLM replaced by `FakeChatModel`).
- Every component MUST have a Vitest + React Testing Library test that queries by role/label.
- Every user-visible flow MUST have a Playwright test that runs against the Docker stack.
- Bug fixes MUST start with a test that reproduces the bug and fails before the fix.
- Every acceptance scenario in a spec MUST map to at least one automated test in `tasks.md`.

Rationale: the three layers are cheap to run and together cover logic, UI, and the real stack
(SQL Server, nginx, migrations).

### III. Explicit API Contract

- Routes live under `/api/<feature>`. JSON is camelCase; enums serialize as camelCase strings.
- Errors MUST be RFC 7807 ProblemDetails with an explicit status; the frontend shows
  `detail ?? title`. Request validation uses DataAnnotations + `AddValidation()` (invalid → 400).
- A DTO change MUST update the matching TypeScript types in `<feature>Api.ts` in the same change.
- Breaking changes to an existing endpoint MUST be called out in the spec and plan.

Rationale: frontend and backend ship together, so the contract is kept honest by co-changing both
sides rather than by versioning.

### IV. Model-Agnostic AI Integration

- All LLM access MUST go through `IChatModel`; no feature code references `Google.GenAI` directly.
- The app MUST run with no API key (the `EchoChatModel` fallback).
- Model failures MUST surface as a ProblemDetails error (502) and MUST NOT leave partial data.
- Automated tests MUST NOT depend on real model output: backend tests use `FakeChatModel`, E2E
  tests assert on structure, not wording.

Rationale: keeps tests deterministic and free, and keeps the provider swappable.

### V. Reproducible Docker Environment

- Every service (frontend, backend, SQL Server, Playwright) MUST build and run through
  `compose.yaml`; `compose.dev.yaml` is the hot-reload overlay.
- A feature is not done until it works on the production-like stack
  (`docker compose up -d --build`), not just the dev servers.
- Toolchain versions are pinned: .NET 10 SDK (`global.json`), Node >= 24 and pnpm
  (`packageManager`), the Playwright image tag matching `@playwright/test`.

Rationale: "works on my machine" is ruled out when every check runs against the same images.

## Security & Data

- Secrets MUST NOT be read, printed, or committed. `.env` is git-ignored; configuration flows
  `.env` → compose env vars → `Section__Key`; local runs use `dotnet user-secrets`.
- Schema changes MUST go through an EF Core migration; applied migrations MUST NOT be edited.
- Timestamps are stored as UTC `DateTime` named `*Utc`; code takes time from `TimeProvider`.
- User-supplied text has explicit length limits enforced on both server and client.

## Development Workflow & Quality Gates

- Features follow Spec Kit: `/speckit-specify` → (`/speckit-clarify`) → `/speckit-plan` →
  `/speckit-tasks` → (`/speckit-analyze`) → `/speckit-implement` → `/speckit-converge`. Artifacts
  live in `specs/<NNN-feature>/`. Specs describe *what* and *why*; the stack is chosen in the plan.
- Every plan MUST pass the Constitution Check before research and again after design.
- Definition of done (run `/verify`):
  1. `dotnet test` passes in `backend/`.
  2. `pnpm lint && pnpm typecheck && pnpm test && pnpm build` pass in `frontend/`.
  3. The Playwright suite passes against the Docker stack.
  4. `docs/` and `docs/backlog.md` are updated; the diff has no secrets or stray debug code.
- Commits and pushes happen only when a human asks for them.

## Governance

- This constitution supersedes conflicting guidance. `CLAUDE.md` files hold day-to-day commands
  and conventions and MUST stay consistent with it.
- Amendments go through `/speckit-constitution`, are reviewed as a normal diff, and update any
  affected `CLAUDE.md`, skill, or template in the same change.
- Versioning: MAJOR for removing or redefining a principle, MINOR for a new principle or section
  or materially expanded guidance, PATCH for clarifications.
- `/speckit-analyze` treats a conflict with a MUST in this document as CRITICAL. A justified
  exception is recorded in the plan's Complexity Tracking table, never silently.

**Version**: 1.0.1 | **Ratified**: 2026-10-14 | **Last Amended**: 2026-10-14

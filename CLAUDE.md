# CLAUDE.md

Guidance for Claude Code in this repository. Area-specific rules live in `backend/CLAUDE.md` and `frontend/CLAUDE.md`.

## What this is

MisaApp: a web app with an AI chat box backed by Google Gemini (`Google.GenAI` .NET SDK).

| Area       | Stack                                                                 | Path                |
| ---------- | --------------------------------------------------------------------- | ------------------- |
| Frontend   | React 19, TypeScript, Vite, pnpm, Vitest + React Testing Library       | `frontend/`         |
| E2E        | Playwright (separate pnpm package, runs in its own container)        | `frontend/e2e/`     |
| Backend    | ASP.NET Core (.NET 10) minimal APIs, EF Core 10, xUnit v3             | `backend/`          |
| Database   | Azure SQL Database (per-developer DB on `sql-misaapp-nonprod-<suffix>`) | `infra/shared/`   |
| Infra      | Terraform, GitHub Actions (Azure Container Apps)                      | `infra/`, `.github/workflows/` |
| Specs      | Spec Kit feature specs, plans, tasks (one folder per feature)         | `specs/`            |
| Docs       | Architecture, backlog, dev log, workflow guide                        | `docs/`             |

Everything runs in Docker: `backend`, `frontend`, `playwright` (profile `e2e`); the database is Azure SQL
(`SQL_CONNECTION_STRING` in `.env`). Merges to `develop`/`stag`/`main` deploy to Azure: see `docs/deployment.md`.

## Commands

```bash
# Full stack (production-like images)       → http://localhost:3000
docker compose up -d --build
# Hot-reload stack (bind mounts, dotnet watch, Vite HMR)
docker compose -f compose.yaml -f compose.dev.yaml up -d --build
# E2E against whichever stack is running (add -f compose.dev.yaml if the dev stack is up)
docker compose --profile e2e run --rm --build playwright
docker compose logs -f backend
docker compose down

# Backend (from backend/)
dotnet test                    # xUnit v3 on Microsoft.Testing.Platform, SQLite in-memory
dotnet ef migrations add <Name> --project src/MisaApp.Api --output-dir Data/Migrations
dotnet run --project src/MisaApp.Api   # http://localhost:5056, needs ConnectionStrings:Default via dotnet user-secrets

# Frontend (from frontend/, Node >= 24)
pnpm test        # Vitest
pnpm lint        # oxlint
pnpm typecheck
pnpm build
pnpm dev         # http://localhost:5173, proxies /api to localhost:5056

# Infra (Terraform pinned in infra/*/versions.tf)
terraform -chdir=infra/environment init -backend=false && terraform -chdir=infra/environment validate
terraform -chdir=infra/shared init -backend=false && terraform -chdir=infra/shared validate
```

If local Node is older than 24, run frontend checks in a container:
`docker run --rm -v "$PWD/frontend:/app" -v /app/node_modules -w /app node:24-alpine sh -c "corepack enable && pnpm i --frozen-lockfile --store-dir /tmp/pnpm-store && pnpm test"`

## Conventions

- **Feature folders.** Backend code for a feature lives in `backend/src/MisaApp.Api/Features/<Feature>/`; frontend in `frontend/src/features/<feature>/`. Cross-cutting code goes in `Data/` or `src/lib/`.
- **API contract.** Routes under `/api/<feature>`. JSON is camelCase, enums are camelCase strings. Errors are RFC 7807 ProblemDetails; the frontend reads `detail ?? title`. When a DTO changes, update the TypeScript types in the matching `*Api.ts` in the same change.
- **Tests are part of the change.** Every endpoint gets an integration test (`ApiFactory`); every component gets an RTL test; every user-visible flow gets a Playwright test. E2E assertions must not depend on real Gemini output (the echo model is used when no key is set).
- **Secrets.** Never read, print, or commit `.env`. Configuration goes through `.env` → compose env vars → `Section__Key`.
- **Database changes** always go through an EF migration; never edit an applied migration. Migrations must stay backward compatible with the previous release (expand/contract), because the old revision keeps serving while they run and rollback doesn't revert them.
- **Deployments** happen only through `.github/workflows/deploy.yml`; infrastructure changes only through Terraform in `infra/`.
- **Docs.** A new feature gets a spec through Spec Kit (see below); update `docs/backlog.md` when work starts or finishes.

## Spec-driven development (GitHub Spec Kit)

Non-negotiable project rules live in `.specify/memory/constitution.md`; plans are checked against it, and this file must stay consistent with it.

- Feature flow: `/speckit-specify` → `/speckit-clarify` (optional) → `/speckit-plan` → `/speckit-tasks` → `/speckit-analyze` (optional) → `/speckit-implement` → `/speckit-converge`. `/feature` runs the whole sequence with checkpoints.
- Artifacts: `specs/NNN-<slug>/` holds `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`, `tasks.md`, and `checklists/`. The active feature is recorded in `.specify/feature.json` (git-ignored).
- The git extension creates a `NNN-<slug>` branch on `/speckit-specify`; its auto-commit hooks are off.
- Don't hand-edit `.specify/templates/` or `.specify/scripts/`, because `specify init` refreshes them. Customize through the constitution, presets, or this file.

## Definition of done

1. `dotnet test` passes in `backend/`
2. `pnpm lint && pnpm typecheck && pnpm test && pnpm build` pass in `frontend/`
3. The Playwright suite passes against the Docker stack (on your Azure SQL dev database); for `infra/` or workflow changes, `terraform validate` and `actionlint` pass
4. Docs/backlog updated; no secrets or stray debug code in the diff

## Daily workflows (skills)

Invoke with `/<name>`. Details and how to evolve them: `docs/claude-workflows.md`.

| Skill              | Use it for                                                      |
| ------------------ | --------------------------------------------------------------- |
| `/daily-start`     | Morning check-in: state of repo + stack, pick today's work      |
| `/feature <idea>`  | Spec Kit flow (specify → plan → tasks → implement → converge) with checkpoints, then verify |
| `/bugfix <issue>`  | Reproduce with a failing test, fix, verify                      |
| `/db-migration`    | Add and review an EF Core migration                             |
| `/verify`          | Run every check and report a pass/fail table                    |
| `/daily-wrap-up`   | Dev log, backlog update, commit message suggestions             |
| `/improve-workflow`| Refine these skills / CLAUDE.md based on what went wrong        |
| `/speckit-*`       | Individual Spec Kit steps (generated by `specify init`; don't edit, see above) |

# MisaApp

React + ASP.NET Core web app with an AI chat box powered by Google Gemini (`Google.GenAI`), Azure SQL Database, a Dockerized dev/test setup, and GitHub Actions deploys to Azure Container Apps.

| Layer     | Tech                                                        |
| --------- | ----------------------------------------------------------- |
| Frontend  | React 19, TypeScript, Vite 8, pnpm, Vitest, React Testing Library |
| Backend   | ASP.NET Core (.NET 10) minimal APIs, EF Core 10, xUnit v3    |
| Database  | Azure SQL Database (per-developer database on a shared nonprod server) |
| Infra     | Terraform, GitHub Actions, Azure Container Apps              |
| E2E       | Playwright (Chromium + Firefox, in Docker)                   |

```
docs/        architecture, backlog, dev log, Claude workflow guide
specs/       Spec Kit feature specs: one folder per feature (spec, plan, tasks, ...)
.specify/    Spec Kit constitution, templates, scripts
frontend/    React app (+ e2e/ Playwright package)
backend/     MisaApp.slnx: src/MisaApp.Api, tests/MisaApp.Api.Tests
infra/       Terraform (shared/, environment/), bootstrap and helper scripts
.github/     CI (ci.yml) and deploy (deploy.yml) workflows
compose.yaml / compose.dev.yaml / compose.ci.yaml
```

## Prerequisites

- Docker Desktop (WSL 2 backend)
- For running tools outside Docker (optional): .NET SDK 10, Node 24 LTS, pnpm 10 (`corepack enable`)
- Azure CLI (`az login`) and access to your developer database: see [Local development on Azure SQL](docs/deployment.md#local-development-on-azure-sql)
- A Gemini API key from https://aistudio.google.com/apikey (optional; without one the chat echoes your message)

## Quick start

```powershell
Copy-Item .env.example .env      # then set SQL_CONNECTION_STRING (and optionally GEMINI_API_KEY)
docker compose up -d --build
```

- App: http://localhost:3000
- API: http://localhost:8080/api/health · OpenAPI: http://localhost:8080/openapi/v1.json · version: http://localhost:8080/api/version
- Database: your `sqldb-misaapp-dev-<alias>` on Azure SQL; the backend applies migrations on startup

### Hot-reload development

```powershell
docker compose -f compose.yaml -f compose.dev.yaml up -d --build
```

The backend runs `dotnet watch` and the frontend runs the Vite dev server on http://localhost:3000. Source folders are bind-mounted, so edits apply immediately. After changing `package.json`, add `-V` to refresh `node_modules`.

### Tests

```powershell
# E2E (against the running stack; add "-f compose.yaml -f compose.dev.yaml" for the dev stack)
docker compose --profile e2e run --rm --build playwright     # report: frontend/e2e/playwright-report

# Backend
cd backend; dotnet test

# Frontend
cd frontend; pnpm install; pnpm lint; pnpm typecheck; pnpm test
```

### Running outside Docker

```powershell
cd backend; dotnet user-secrets set "ConnectionStrings:Default" "<SQL_CONNECTION_STRING value>" --project src/MisaApp.Api
dotnet user-secrets set "Gemini:ApiKey" "<key>" --project src/MisaApp.Api; dotnet run --project src/MisaApp.Api
cd frontend; pnpm dev            # http://localhost:5173, proxies /api to :5056
```

User secrets override `appsettings.Development.json`, so set `ConnectionStrings:Default` there to reach your Azure SQL database.

### Useful commands

```powershell
docker compose logs -f backend
docker compose down              # stop
cd backend; dotnet ef migrations add <Name> --project src/MisaApp.Api --output-dir Data/Migrations
```

## CI/CD

Pull requests to `develop`, `stag` and `main` must pass five checks (backend, frontend, infra, secrets, e2e). Merging deploys to Azure Container Apps: `develop` → develop automatically, `stag` → stage and `main` → production after approval. Images are built once per commit, and any environment can be rolled back to an earlier commit with `gh workflow run deploy.yml`. See [docs/deployment.md](docs/deployment.md).

## Working with Claude Code

Project instructions are in `CLAUDE.md`, and the daily workflows are skills in `.claude/skills/`:
`/daily-start`, `/feature <idea>`, `/bugfix <issue>`, `/db-migration <Name>`, `/verify`, `/daily-wrap-up`, `/improve-workflow`.
See [docs/claude-workflows.md](docs/claude-workflows.md).

### Spec-driven development (GitHub Spec Kit)

Features are built spec-first with [Spec Kit](https://github.com/github/spec-kit). The project rules are in [`.specify/memory/constitution.md`](.specify/memory/constitution.md).

```text
/feature <idea>          # guided: specify → clarify → plan → tasks → analyze → implement → converge → /verify
/speckit-specify <idea>  # or run the steps yourself: /speckit-clarify, /speckit-plan, /speckit-tasks, ...
```

You only need the `specify` CLI to upgrade Spec Kit (requires Python 3.11+ and [uv](https://docs.astral.sh/uv/)):

```powershell
winget install astral-sh.uv
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v1.2.0
specify version
```

## Docs

- [Architecture](docs/architecture.md)
- [Deployment](docs/deployment.md)
- [Backlog](docs/backlog.md)
- [Feature specs](specs/)
- [Constitution](.specify/memory/constitution.md)

# MisaApp

React + ASP.NET Core web app with an AI chat box powered by Google Gemini (`Google.GenAI`), SQL Server, and a fully Dockerized dev/test setup.

| Layer     | Tech                                                        |
| --------- | ----------------------------------------------------------- |
| Frontend  | React 19, TypeScript, Vite 8, pnpm, Vitest, React Testing Library |
| Backend   | ASP.NET Core (.NET 10) minimal APIs, EF Core 10, xUnit v3    |
| Database  | SQL Server 2025 (Developer, in Docker)                       |
| E2E       | Playwright (Chromium + Firefox, in Docker)                   |

```
docs/        architecture, backlog, dev log, Claude workflow guide
specs/       Spec Kit feature specs: one folder per feature (spec, plan, tasks, ...)
.specify/    Spec Kit constitution, templates, scripts
frontend/    React app (+ e2e/ Playwright package)
backend/     MisaApp.slnx: src/MisaApp.Api, tests/MisaApp.Api.Tests
compose.yaml / compose.dev.yaml
```

## Prerequisites

- Docker Desktop (WSL 2 backend)
- For running tools outside Docker (optional): .NET SDK 10, Node 24 LTS, pnpm 10 (`corepack enable`)
- A Gemini API key from https://aistudio.google.com/apikey (optional; without one the chat echoes your message)

## Quick start

```powershell
Copy-Item .env.example .env      # then set GEMINI_API_KEY (and change MSSQL_SA_PASSWORD if you like)
docker compose up -d --build
```

- App: http://localhost:3000
- API: http://localhost:8080/api/health · OpenAPI: http://localhost:8080/openapi/v1.json
- SQL Server: `localhost,1433`, user `sa`, password from `.env`

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
docker compose up -d sqlserver
cd backend; dotnet user-secrets set "Gemini:ApiKey" "<key>" --project src/MisaApp.Api; dotnet run --project src/MisaApp.Api
cd frontend; pnpm dev            # http://localhost:5173, proxies /api to :5056
```

`appsettings.Development.json` assumes the default password from `.env.example`. If you change it, override `ConnectionStrings:Default` with user-secrets.

### Useful commands

```powershell
docker compose logs -f backend
docker compose down              # stop (keeps data)
docker compose down -v           # stop and delete the database volume
cd backend; dotnet ef migrations add <Name> --project src/MisaApp.Api --output-dir Data/Migrations
```

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
- [Backlog](docs/backlog.md)
- [Feature specs](specs/)
- [Constitution](.specify/memory/constitution.md)

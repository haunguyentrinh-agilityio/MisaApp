# Architecture

## Runtime topology

### Local (docker compose)

```
                 ┌──────────────── docker compose (project: misaapp) ─────────────────┐
 Browser ──:3000─┤► frontend (nginx)  ── /api/* ──► backend (ASP.NET Core :8080) ─────┼──► Azure SQL Database
                 │    static React build                │                             │    sqldb-misaapp-dev-<alias>
                 │                                      └──► Google Gemini API ───────┼──► (Google.GenAI SDK, HTTPS)
                 │  playwright (profile: e2e) ──► http://frontend                     │
                 └────────────────────────────────────────────────────────────────────┘
```

| Service      | Image / build                             | Host port         | Notes                                                    |
| ------------ | ----------------------------------------- | ----------------- | -------------------------------------------------------- |
| `backend`    | `backend/Dockerfile` (`runtime` / `dev`)  | `API_PORT` (8080) | Applies EF migrations on startup; database from `SQL_CONNECTION_STRING` |
| `frontend`   | `frontend/Dockerfile` (`runtime` / `dev`) | `WEB_PORT` (3000) | nginx serves `dist/`, proxies `/api/` to `API_UPSTREAM` (`http://backend:8080`) |
| `playwright` | `frontend/e2e/Dockerfile`                 | –                 | Only with `--profile e2e`; waits up to 180 s for `/api/health` first |

There is no local database container. Each developer has a database on the shared nonprod server
`sql-misaapp-nonprod-<suffix>`; see [deployment.md](deployment.md#local-development-on-azure-sql).
`compose.dev.yaml` switches backend/frontend to their `dev` stages: `dotnet watch` and the Vite dev
server with bind mounts and polling file watchers (needed for Windows bind mounts). `compose.ci.yaml`
swaps the builds for registry images in deploy-run E2E.

### Azure (per environment: develop, stage, production)

```
                       rg-misaapp-<env>
                       ┌────────────────── Container Apps environment cae-misaapp-<env> ──────────────────┐
 Browser ──HTTPS──────►│ ca-misaapp-<env>-web (nginx, external) ──/api/*──► ca-misaapp-<env>-api (internal) │
                       │                                                       │  managed identity        │
                       │ caj-misaapp-<env>-migrate (job: EF migration bundle) ─┼──────────────┐           │
                       └───────────────────────────────────────────────────────┼──────────────┼───────────┘
                         Key Vault kv-misaapp-<code>-<suffix> ◄─ gemini-api-key┘              ▼
                         Log Analytics log-misaapp-<env>          Azure SQL sql-misaapp-<env>-<suffix> / sqldb-misaapp
                                                                  (Entra-only auth)
 rg-misaapp-shared: registry crmisaapp<suffix> (images misaapp-api, misaapp-web, misaapp-migrator; daily purge),
                    nonprod SQL server (developer and CI databases), kv-misaapp-np-<suffix>, Terraform state storage
```

- The web app is the only public endpoint. The API has internal ingress; nginx reaches it by name.
- Each app and the migrate job has its own user-assigned identity (AcrPull only for web). The API
  identity has Key Vault Secrets User and a contained database user created by the migrator.
- The migrate job runs before every deploy applies the new revision. Apps run in single-revision mode;
  traffic moves once the new revision is ready.
- Everything is Terraform: `infra/shared` (registry, nonprod SQL and vault) and `infra/environment`
  (one state per environment, `<env>.tfvars`). Pipeline and operations: [deployment.md](deployment.md).

## Backend

- Minimal APIs, organized by **feature folder** (`Features/Chat/...`): entities + EF configuration, contracts, service, endpoints, DI extension.
- `AppDbContext` (EF Core 10, SQL Server provider with retry-on-failure). Migrations in `Data/Migrations`; in Azure they ship as the `migrator` image (an EF migration bundle).
- Cross-cutting: ProblemDetails for all errors, built-in .NET 10 validation (`AddValidation`), health checks at `/api/health` (includes a DB check), OpenAPI at `/openapi/v1.json` in Development.

### Chat feature

| Method | Route                                   | Purpose                                   |
| ------ | --------------------------------------- | ----------------------------------------- |
| POST   | `/api/chat/messages`                    | Send a message; creates a conversation if `conversationId` is null. Returns the stored user message and the reply. 404 unknown conversation, 400 invalid, 502 model failure. |
| GET    | `/api/chat/conversations`               | Recent conversations (`?take=`, max 200)  |
| GET    | `/api/chat/conversations/{id}`          | One conversation with its messages        |

Flow: `ChatService` loads the last `Gemini:MaxHistoryMessages` turns, calls `IChatModel`, and **only then** persists the user message + reply (a failed model call stores nothing).

`IChatModel` implementations:
- `GeminiChatModel`: `Google.GenAI` `Client.Models.GenerateContentAsync` with roles `user`/`model` and an optional system instruction.
- `EchoChatModel`: used automatically when `Gemini:ApiKey` is empty (local dev without a key, E2E, develop and stage).

Data model: `Conversation (Guid v7 PK, Title, CreatedAtUtc, UpdatedAtUtc)` 1─* `ChatMessage (bigint identity PK, ConversationId, Role as string, Content, CreatedAtUtc)`.

### Version feature

| Method | Route          | Purpose                                                              |
| ------ | -------------- | -------------------------------------------------------------------- |
| GET    | `/api/version` | `{ "commit": "<sha>", "environment": "<env>" }`; `dev`/`local` locally. The smoke test checks it after every deploy. |

## Frontend

- React 19 + Vite. Feature folders under `src/features/`; shared fetch wrapper in `src/lib/api.ts` (throws `ApiError` with ProblemDetails text).
- `ChatBox`: optimistic user message, "Thinking…" indicator, rollback and restore the draft on error, Enter to send / Shift+Enter for a newline, conversation id kept in `localStorage` and history restored on reload.
- Dev: Vite proxies `/api` to `API_PROXY_TARGET` (default `http://localhost:5056`). Docker and Azure: nginx proxies to `API_UPSTREAM` (an nginx template variable).

## Configuration

| Setting                        | Local (Docker)                       | Azure                                    | Default                 |
| ------------------------------ | ------------------------------------ | ---------------------------------------- | ----------------------- |
| `ConnectionStrings:Default`    | `SQL_CONNECTION_STRING` in `.env`    | managed identity (`Authentication=Active Directory Managed Identity`) | – |
| `Database:MigrateOnStartup`    | `true` (compose)                     | `false`; the migrate job runs migrations | `false`                 |
| `Gemini:ApiKey`                | `GEMINI_API_KEY` in `.env`           | Key Vault `gemini-api-key` when `gemini_enabled` | empty → echo model |
| `Gemini:Model`                 | `GEMINI_MODEL` in `.env`             | `gemini_model` in tfvars                 | `gemini-3.8-flash`      |
| `Gemini:SystemInstruction`     | `appsettings.json`                   | `appsettings.json`                       | short assistant prompt  |
| `Gemini:MaxHistoryMessages`    | `appsettings.json`                   | `appsettings.json`                       | 20                      |
| `App:Commit`                   | `SOURCE_COMMIT` build arg            | image built with the commit SHA          | `dev`                   |
| `App:Environment`              | –                                    | `develop` / `stage` / `production`       | `local`                 |

Local (non-Docker) secrets: `dotnet user-secrets set "ConnectionStrings:Default" "<connection string>" --project backend/src/MisaApp.Api` (and `Gemini:ApiKey` the same way).

## Testing strategy

| Layer        | Tool                         | Scope                                                         |
| ------------ | ---------------------------- | ------------------------------------------------------------- |
| Backend      | xUnit v3 + `WebApplicationFactory` + SQLite in-memory | Endpoints end to end inside the process, LLM faked |
| Frontend     | Vitest + RTL + user-event    | Components with `fetch` stubbed                               |
| E2E          | Playwright (Chromium, Firefox) in Docker | Real stack on Azure SQL (your dev database locally, a throwaway `sqldb-misaapp-ci-*` database in CI); LLM-agnostic assertions |
| Smoke        | Playwright `@smoke` tests (`PW_SMOKE=1`, Chromium) | Live environment after each deploy: page, health, deployed commit |
| Infra        | `terraform validate`, tflint, trivy, actionlint, gitleaks | Every pull request (`ci.yml`, job `infra` and `secrets`) |

## Key decisions

- **Minimal APIs + feature folders** rather than controllers + layers: less ceremony, everything for a feature in one place.
- **`IChatModel` seam**: keeps Google.GenAI out of business logic and tests; the echo fallback lets the app run with no key.
- **SQLite for integration tests**: fast and Docker-free. SQL Server-specific behavior is covered by E2E against Azure SQL.
- **Same-origin `/api` proxy** (Vite/nginx): no CORS configuration needed, and the API stays internal in Azure.
- **Migrations as a deployment step** in Azure (migrate job before the new revision); on startup only locally. Migrations must stay backward compatible with the previous release ([rule](deployment.md#database-migrations-backward-compatibility-rule)).
- **Build once, deploy the tested images**: images are tagged with the commit SHA; E2E, deploy and rollback all use the same tag.
- **Azure SQL everywhere**: local development uses the same engine as production, so there is no local SQL container.

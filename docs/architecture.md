# Architecture

## Runtime topology

```
                 ┌──────────────────────────── docker compose (project: misaapp) ──────────────────────────────┐
 Browser ──:3000─┤► frontend (nginx)  ── /api/* ──► backend (ASP.NET Core :8080) ──► sqlserver (SQL 2025 :1433) │
                 │    static React build                │                                                      │
                 │                                      └──► Google Gemini API (Google.GenAI SDK, HTTPS)       │
                 │  playwright (profile: e2e) ──► http://frontend                                              │
                 └─────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Service      | Image / build                          | Host port            | Notes                                                    |
| ------------ | -------------------------------------- | -------------------- | -------------------------------------------------------- |
| `sqlserver`  | `mcr.microsoft.com/mssql/server:2025-latest` | `SQL_PORT` (1433) | Developer edition, data in volume `sqlserver-data`, healthcheck via `sqlcmd` |
| `backend`    | `backend/Dockerfile` (`runtime` / `dev`) | `API_PORT` (8080)  | Applies EF migrations on startup                          |
| `frontend`   | `frontend/Dockerfile` (`runtime` / `dev`) | `WEB_PORT` (3000) | nginx serves `dist/`, proxies `/api/` to `backend:8080`    |
| `playwright` | `frontend/e2e/Dockerfile`              | –                    | Only with `--profile e2e`; waits for `/api/health` first  |

`compose.dev.yaml` switches backend/frontend to their `dev` stages: `dotnet watch` and the Vite dev server with bind mounts and polling file watchers (needed for Windows bind mounts).

## Backend

- Minimal APIs, organized by **feature folder** (`Features/Chat/...`): entities + EF configuration, contracts, service, endpoints, DI extension.
- `AppDbContext` (EF Core 10, SQL Server provider with retry-on-failure). Migrations in `Data/Migrations`.
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
- `EchoChatModel`: used automatically when `Gemini:ApiKey` is empty (local dev without a key, E2E).

Data model: `Conversation (Guid v7 PK, Title, CreatedAtUtc, UpdatedAtUtc)` 1─* `ChatMessage (bigint identity PK, ConversationId, Role as string, Content, CreatedAtUtc)`.

## Frontend

- React 19 + Vite. Feature folders under `src/features/`; shared fetch wrapper in `src/lib/api.ts` (throws `ApiError` with ProblemDetails text).
- `ChatBox`: optimistic user message, "Thinking…" indicator, rollback and restore the draft on error, Enter to send / Shift+Enter for a newline, conversation id kept in `localStorage` and history restored on reload.
- Dev: Vite proxies `/api` to `API_PROXY_TARGET` (default `http://localhost:5056`). Docker: nginx proxies to `backend:8080`.

## Configuration

| Setting                        | Source (Docker)                    | Default                 |
| ------------------------------ | ---------------------------------- | ----------------------- |
| `ConnectionStrings:Default`    | built from `MSSQL_SA_PASSWORD`     | –                       |
| `Database:MigrateOnStartup`    | compose env                        | `true` in Development   |
| `Gemini:ApiKey`                | `GEMINI_API_KEY` in `.env`         | empty → echo model      |
| `Gemini:Model`                 | `GEMINI_MODEL` in `.env`           | `gemini-3.8-flash`      |
| `Gemini:SystemInstruction`     | `appsettings.json`                 | short assistant prompt  |
| `Gemini:MaxHistoryMessages`    | `appsettings.json`                 | 20                      |

Local (non-Docker) secrets: `dotnet user-secrets set "Gemini:ApiKey" "<key>" --project backend/src/MisaApp.Api`.

## Testing strategy

| Layer        | Tool                         | Scope                                                         |
| ------------ | ---------------------------- | ------------------------------------------------------------- |
| Backend      | xUnit v3 + `WebApplicationFactory` + SQLite in-memory | Endpoints end to end inside the process, LLM faked |
| Frontend     | Vitest + RTL + user-event    | Components with `fetch` stubbed                               |
| E2E          | Playwright (Chromium, Firefox) in Docker | Real stack incl. SQL Server; LLM-agnostic assertions |

## Key decisions

- **Minimal APIs + feature folders** rather than controllers + layers: less ceremony, everything for a feature in one place.
- **`IChatModel` seam**: keeps Google.GenAI out of business logic and tests; the echo fallback lets the app run with no key.
- **SQLite for integration tests**: fast and Docker-free. SQL Server-specific behavior is covered by E2E. Revisit (Testcontainers) if raw SQL or SQL Server-only features appear.
- **Same-origin `/api` proxy** (Vite/nginx): no CORS configuration needed.
- **Migrations on startup** in Development/Docker only; production should run them as a deployment step.

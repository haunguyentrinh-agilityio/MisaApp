# Architecture

## Runtime topology

### Local (docker compose)

```
                 ┌──────────────── docker compose (project: misaapp) ─────────────────┐
 Browser ──:3000─┤► frontend (nginx)  ── /api/* ──► backend (ASP.NET Core :8080)      │
                 │    static React build                │                             │
                 │                                      └──► Google Gemini API ───────┼──► (Google.GenAI SDK, HTTPS)
                 │  playwright (profile: e2e) ──► http://frontend                     │
                 └────────────────────────────────────────────────────────────────────┘
```

| Service      | Image / build                             | Host port         | Notes                                                    |
| ------------ | ----------------------------------------- | ----------------- | -------------------------------------------------------- |
| `backend`    | `backend/Dockerfile` (`runtime` / `dev`)  | `API_PORT` (8080) | Stateless; Gemini key from `GEMINI_API_KEY` (echo model without one) |
| `frontend`   | `frontend/Dockerfile` (`runtime` / `dev`) | `WEB_PORT` (3000) | nginx serves `dist/`, proxies `/api/` to `API_UPSTREAM` (`http://backend:8080`) |
| `playwright` | `frontend/e2e/Dockerfile`                 | –                 | Only with `--profile e2e`; waits up to 60 s for `/api/health` first |

There is no database. `compose.dev.yaml` switches backend/frontend to their `dev` stages: `dotnet watch`
and the Vite dev server with bind mounts and polling file watchers (needed for Windows bind mounts).
`compose.ci.yaml` swaps the builds for registry images in deploy-run E2E.

### Azure (per environment: develop, stage, production)

```
                       rg-misaapp-<env>
                       ┌────────────────── Container Apps environment cae-misaapp-<env> ──────────────────┐
 Browser ──HTTPS──────►│ ca-misaapp-<env>-web (nginx, external) ──/api/*──► ca-misaapp-<env>-api (internal) │
                       │                                                       │  managed identity        │
                       └───────────────────────────────────────────────────────┼──────────────────────────┘
                         Key Vault kv-misaapp-<code>-<suffix> ◄─ gemini-api-key┘
                         Log Analytics log-misaapp-<env>
 rg-misaapp-shared: registry crmisaapp<suffix> (images misaapp-api, misaapp-web; daily purge), Terraform state storage
```

- The web app is the only public endpoint. The API has internal ingress; nginx reaches it by name.
- Each app has its own user-assigned identity (AcrPull; the API also has Key Vault Secrets User).
  Apps run in single-revision mode; traffic moves once the new revision is ready.
- Everything is Terraform: `infra/shared` (registry) and `infra/environment` (one state per
  environment, `<env>.tfvars`). Pipeline and operations: [deployment.md](deployment.md).
- The app has no database; chats live in the visitor's browser and the API forwards them to the model.
  The Azure SQL resources were removed in Release B of
  [specs/003-remove-chat-database](../specs/003-remove-chat-database/tasks.md); what that means for
  rollbacks is in [deployment.md](deployment.md#rollback-limits-after-the-database-removal).

## Backend

- Minimal APIs, organized by **feature folder** (`Features/Chat/...`): contracts, service, endpoints, DI extension.
- Stateless: no database, no server-side session. Nothing a user types is stored by the API.
- Cross-cutting: ProblemDetails for all errors, built-in .NET 10 validation (`AddValidation`), health checks at `/api/health` (process liveness only), OpenAPI at `/openapi/v1.json` in Development.

### Chat feature

| Method | Route                | Purpose                                                                 |
| ------ | -------------------- | ----------------------------------------------------------------------- |
| POST   | `/api/chat/messages` | `{ message, history? }` → `{ reply }`. 400 invalid (empty or > 4000-char message, > 20 history turns, a turn > 8000 chars, unknown or missing role), 502 model failure. |

Flow: the browser sends the new message and up to 20 earlier turns (`history`, each `{ role: "user" | "assistant", content }`).
`ChatService` keeps the last `Gemini:MaxHistoryMessages - 1` turns of the history, appends the new user turn, calls
`IChatModel`, and returns the reply. Nothing is persisted.

`IChatModel` implementations:
- `GeminiChatModel`: `Google.GenAI` `Client.Models.GenerateContentAsync` with roles `user`/`model` and an optional system instruction.
- `EchoChatModel`: used automatically when `Gemini:ApiKey` is empty (local dev without a key, E2E, and any environment with `gemini_enabled = false`).

### Version feature

| Method | Route          | Purpose                                                              |
| ------ | -------------- | -------------------------------------------------------------------- |
| GET    | `/api/version` | `{ "commit": "<sha>", "environment": "<env>" }`; `dev`/`local` locally. The smoke test checks it after every deploy. |

## Frontend

- React 19 + Vite. Feature folders under `src/features/`; shared fetch wrapper in `src/lib/api.ts` (throws `ApiError` with ProblemDetails text).
- `ChatBox`: optimistic user message, "Thinking…" indicator, rollback and restore the draft on error, Enter to send / Shift+Enter for a newline.
- `chatStorage.ts`: the current chat lives in `localStorage` under `chat.messages` (last 100 messages), written after each successful reply, restored on reload, and removed by **New chat**. Invalid stored data and the legacy `chat.conversationId` key are discarded on load; storage errors (private mode, quota) are ignored, so the chat still works for the open tab.
- `chatApi.buildHistory` sends the last 20 messages as `history`, each trimmed to 8000 characters.
- Dev: Vite proxies `/api` to `API_PROXY_TARGET` (default `http://localhost:5056`). Docker and Azure: nginx proxies to `API_UPSTREAM` (an nginx template variable).

## Configuration

| Setting                        | Local (Docker)                       | Azure                                    | Default                 |
| ------------------------------ | ------------------------------------ | ---------------------------------------- | ----------------------- |
| `Gemini:ApiKey`                | `GEMINI_API_KEY` in `.env`           | Key Vault `gemini-api-key` when `gemini_enabled` | empty → echo model |
| `Gemini:Model`                 | `GEMINI_MODEL` in `.env`             | `gemini_model` in tfvars                 | `gemini-3.8-flash`      |
| `Gemini:SystemInstruction`     | `appsettings.json`                   | `appsettings.json`                       | short assistant prompt  |
| `Gemini:MaxHistoryMessages`    | `appsettings.json`                   | `appsettings.json`                       | 20                      |
| `App:Commit`                   | `SOURCE_COMMIT` build arg            | image built with the commit SHA          | `dev`                   |
| `App:Environment`              | –                                    | `develop` / `stage` / `production`       | `local`                 |

Local (non-Docker) secrets: `dotnet user-secrets set "Gemini:ApiKey" "<key>" --project backend/src/MisaApp.Api` (optional).

## Testing strategy

| Layer        | Tool                         | Scope                                                         |
| ------------ | ---------------------------- | ------------------------------------------------------------- |
| Backend      | xUnit v3 + `WebApplicationFactory` | Endpoints end to end inside the process, LLM faked (`FakeChatModel`) |
| Frontend     | Vitest + RTL + user-event    | Components and `localStorage` handling with `fetch` stubbed   |
| E2E          | Playwright (Chromium, Firefox) in Docker | The real stack with the echo model; LLM-agnostic assertions |
| Smoke        | Playwright `@smoke` tests (`PW_SMOKE=1`, Chromium) | Live environment after each deploy: page, health, deployed commit |
| Infra        | `terraform validate`, tflint, trivy, actionlint, gitleaks | Every pull request (`ci.yml`, job `infra` and `secrets`) |

## Key decisions

- **Minimal APIs + feature folders** rather than controllers + layers: less ceremony, everything for a feature in one place.
- **`IChatModel` seam**: keeps Google.GenAI out of business logic and tests; the echo fallback lets the app run with no key.
- **Stateless chat, history in the browser** ([specs/003-remove-chat-database](../specs/003-remove-chat-database/spec.md)): chats are not kept, so there is no database to run, secure, migrate or pay for. The client sends the context the model needs; the server enforces the limits.
- **Same-origin `/api` proxy** (Vite/nginx): no CORS configuration needed, and the API stays internal in Azure.
- **Build once, deploy the tested images**: images are tagged with the commit SHA; E2E, deploy and rollback all use the same tag.

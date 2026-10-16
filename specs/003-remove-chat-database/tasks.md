---

description: "Tasks: Stateless Chat, Remove the Database"
---

# Tasks: Stateless Chat, Remove the Database

**Input**: Design documents from `specs/003-remove-chat-database/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/chat-api.md](contracts/chat-api.md), [quickstart.md](quickstart.md)

**Tests**: Required by the constitution (Principle II): integration tests through `ApiFactory`, RTL tests
for components, Playwright for user-visible flows. Within each story, write the tests first and see them
fail before implementing.

**Organization**: Phases 1–6 are **Release A** (this branch). Phases 7–8 are **Releases B and C**:
separate follow-up PRs, ⛔ gated, and NOT implemented on this branch ([research R7](research.md#r7-order-of-removal-in-azure-expandcontract-for-infrastructure)).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 (stateless chatting), US2 (reload behavior), US3 (no database anywhere)

## Path Conventions

- Backend: `backend/src/MisaApp.Api/`, tests in `backend/tests/MisaApp.Api.Tests/`
- Frontend: `frontend/src/features/chat/`, E2E in `frontend/e2e/`
- Infra: `infra/environment/`, `infra/shared/`, `infra/scripts/`, `.github/workflows/`

---

## Phase 1: Setup (Constitution)

**Purpose**: Remove the constitutional requirement for Azure SQL before any code changes ([research R10](research.md#r10-constitution-amendment)).

- [X] T001 Amend `.specify/memory/constitution.md` to **3.0.0** through `/speckit-constitution` (MAJOR, Last Amended 2026-10-16): Principle I drop "entities and their EF configuration" from the feature-folder list; Principle II `ApiFactory` = "`WebApplicationFactory<Program>`, LLM replaced by `FakeChatModel`" (no SQLite) and the rationale's "(Azure SQL, nginx, migrations)" → "(nginx, the built images)"; Principle V renamed "Reproducible Docker Environment": stack = frontend, backend, Playwright, no database; "chat content is not stored server-side; adding persistent storage requires an amendment"; "done" means it works on `docker compose up -d --build`; drop the Azure SQL rationale and network trade-off; Security & Data: remove the EF migration rule and the `*Utc`/`TimeProvider` rule, add "Chat content is kept only in the visitor's browser"; keep the length-limit and secrets rules

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared chat types that US1 (contract) and US3 (deleting `ChatEntities.cs`) both depend on. The build and all existing tests stay green.

- [X] T002 Add `public const int MaxHistoryTurns = 20;` and `public const int MaxHistoryTurnLength = 8000;` to `ChatLimits` in `backend/src/MisaApp.Api/Features/Chat/ChatContracts.cs` (keep `MaxMessageLength = 4000`)
- [X] T003 Move the `ChatRole` enum (`User`, `Assistant`) from `backend/src/MisaApp.Api/Features/Chat/ChatEntities.cs` into `backend/src/MisaApp.Api/Features/Chat/IChatModel.cs` and annotate `ChatTurn` as `record ChatTurn(ChatRole Role, [property: Required, StringLength(ChatLimits.MaxHistoryTurnLength, MinimumLength = 1)] string Content)` — "`content`: Required, not blank, 1–8,000 characters"; "`role`: `user` / `assistant`; any other value → 400" (enum JSON binding); in `backend/src/MisaApp.Api/Program.cs` construct the converter as `new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false)` so numeric roles (`1`, `5`) are rejected instead of binding to an undefined or unintended `ChatRole` (depends on T002)

**Checkpoint**: `dotnet test` passes in `backend/`.

---

## Phase 3: User Story 1 — Chat without anything being saved (Priority: P1) 🎯 MVP

**Goal**: The browser sends the recent turns with each message; the API is stateless and returns `{ reply }` ([contract](contracts/chat-api.md)).

**Independent Test**: Send a message, then a follow-up; the second request carries both earlier turns as `history`, both get replies, and the API has no conversation routes.

### Tests for User Story 1 ⚠️ (write first, see them fail)

- [X] T004 [P] [US1] Rewrite `backend/tests/MisaApp.Api.Tests/Features/Chat/ChatEndpointsTests.cs` (keep the `Json` options and the existing blank/over-length message 400 tests) with integration tests through `ApiFactory`: 200 `{ "reply": ... }` with no `history` and `FakeChatModel` receiving exactly one user turn; the JSON body has only `reply` (no `conversationId`/`userMessage`); `history` forwarded to the model oldest-first followed by the new message; `history` trimmed to the last `Gemini:MaxHistoryMessages - 1` turns (set `Gemini:MaxHistoryMessages` = 3 via `WithWebHostBuilder`); a legacy `conversationId` property is ignored (200); 400 `application/problem+json` for 21 turns ("at most 20 items"), a blank turn content, an 8,001-character turn content, role `"system"`, and numeric role `1`; 502 ProblemDetails with title `Chat model unavailable` when `FakeChatModel` throws `ChatModelException`; `GET /api/chat/conversations` and `GET /api/chat/conversations/{guid}` return 404
- [X] T005 [P] [US1] Delete `backend/tests/MisaApp.Api.Tests/Features/Chat/ConversationTests.cs` (the routes it covers are removed; T004 asserts the 404s)
- [X] T006 [P] [US1] Create `frontend/src/features/chat/chatApi.test.ts`: `buildHistory` returns the last `MAX_HISTORY_TURNS = 20` messages as `{ role, content }` (ids dropped, oldest first) and truncates each `content` to `MAX_HISTORY_TURN_LENGTH = 8000` characters; `sendMessage` POSTs `{ message, history }` to `/api/chat/messages` and returns the `reply`; a 200 whose `reply` is not a string (old API shape `{ reply: { … } }`) rejects with an error
- [X] T007 [P] [US1] Rewrite `frontend/src/features/chat/ChatBox.test.tsx` (keep the `jsonResponse`/`deferred` helpers and the Enter vs Shift+Enter test; query by role/label): first send POSTs `{ message: 'Hello', history: [] }` and shows "You: Hello" and the reply; a follow-up POSTs the two earlier turns as `history`; a failed send (ProblemDetails 502) shows the `detail` in the alert, restores the draft, and does not add the message; a 200 with a non-string `reply` shows an error and restores the draft; "New chat" clears the log (empty text "Ask anything to start a conversation.") and the next request has `history: []`; the "Message" textbox has `maxLength` 4000 and Send is disabled for a blank draft; remove the stored-conversation restore and 404 tests
- [X] T008 [P] [US1] Update `frontend/e2e/tests/chat.spec.ts`: keep "sends a message and receives a reply"; add "a follow-up sends the earlier turns as history" (use `page.waitForRequest` on `POST /api/chat/messages` and assert the second request's `postDataJSON().history` has 2 items with roles `user`, `assistant`); replace the reload-restore test with "New chat clears the chat and the next message has no history" (assert the empty-state text and `history` length 0); add "shows an error and restores the draft when the model fails" (`page.route('**/api/chat/messages', …)` fulfils 502 `application/problem+json` with a `detail`; assert the alert shows the detail, the "Message" textbox holds the draft, and the log has no "You:" entry for it); add "rejects empty and over-long messages" (Send disabled for a blank/whitespace draft; the "Message" textbox has `maxlength="4000"`). Assert structure only, never reply wording

### Implementation for User Story 1

- [X] T009 [US1] In `backend/src/MisaApp.Api/Features/Chat/ChatContracts.cs`: `SendMessageRequest(string Message, List<ChatTurn>? History)` — `Message` keeps `[property: Required, StringLength(ChatLimits.MaxMessageLength, MinimumLength = 1)]`, `History` gets `[property: MaxLength(ChatLimits.MaxHistoryTurns)]` ("optional (missing/null = empty); at most 20 items; oldest first"); `SendMessageResponse(string Reply)`; delete `ChatMessageDto`, `ConversationDto`, `ConversationSummaryDto` (depends on T003)
- [X] T010 [US1] Make `backend/src/MisaApp.Api/Features/Chat/ChatService.cs` stateless: `ChatService(IChatModel model, IOptions<GeminiOptions> options)` with `SendAsync(IReadOnlyList<ChatTurn> history, string message, CancellationToken ct)` sending `history.TakeLast(Math.Max(MaxHistoryMessages - 1, 0))` + `new ChatTurn(ChatRole.User, message)` and returning `new SendMessageResponse(reply)`; remove `AppDbContext`, `TimeProvider`, `GetConversationAsync`, `ListConversationsAsync` (depends on T009)
- [X] T011 [US1] In `backend/src/MisaApp.Api/Features/Chat/ChatEndpoints.cs`: `POST /messages` calls `SendAsync(request.History ?? [], request.Message.Trim(), ct)` (the message is trimmed in the endpoint, as today) and returns `TypedResults.Ok(response)`, keeps the `ChatModelException` → 502 `TypedResults.Problem(title: "Chat model unavailable", detail: ex.Message, statusCode: 502)`, drops the 404 unknown-conversation branch; remove the `GET /conversations` and `GET /conversations/{id:guid}` routes (depends on T010)
- [X] T012 [P] [US1] Rewrite `frontend/src/features/chat/chatApi.ts` per [contract TS](contracts/chat-api.md#typescript-frontendsrcfeatureschatchatapits): export `ChatRole`, `ChatTurn`, `SendMessageRequest`, `SendMessageResponse { reply: string }`, UI type `ChatMessage { id: string; role: ChatRole; content: string }`, `MAX_MESSAGE_LENGTH = 4000`, `MAX_HISTORY_TURNS = 20`, `MAX_HISTORY_TURN_LENGTH = 8000`, `buildHistory(messages)`, and `chatApi.sendMessage(message, history)` that throws when `typeof reply !== 'string'`; remove `getConversation` and `conversationId`
- [X] T013 [US1] Update `frontend/src/features/chat/ChatBox.tsx`: remove `CONVERSATION_STORAGE_KEY`, the `conversationId` state, and the restore `useEffect`; generate message ids with a module-level `createMessageId()` (counter + `Date.now()`, **not** `crypto.randomUUID`, which is missing at `http://frontend`); `send()` computes `buildHistory(messages)` before adding the optimistic user message, then appends the assistant reply; on error roll back and restore the draft as today; "New chat" clears messages (disabled while pending or when empty, as today); keep the markup, labels, and texts unchanged (depends on T012)

**Checkpoint**: `dotnet test`; `pnpm lint && pnpm typecheck && pnpm test && pnpm build`; Playwright against the Docker stack. Chat works statelessly; a reload shows an empty chat until US2.

---

## Phase 4: User Story 2 — Chat behavior after a page reload (Priority: P2)

**Goal**: The chat is kept in `localStorage` (`chat.messages`) until "New chat"; the legacy `chat.conversationId` is discarded ([data-model](data-model.md#browser-localstorage)).

**Independent Test**: Chat, reload: the same chat is shown with no network call and a follow-up has it as context; "New chat", reload: empty.

### Tests for User Story 2 ⚠️ (write first, see them fail)

- [X] T014 [P] [US2] Create `frontend/src/features/chat/chatStorage.test.ts`: `saveChat` then `loadChat` round-trips `{ id, role, content }`; `saveChat` keeps only the most recent `MAX_STORED_MESSAGES = 100`; a second `saveChat` overwrites the first (last writer wins); `loadChat` returns `[]` and removes the key for invalid JSON, a non-array, or an item with a bad `role`/non-string `content`/non-string `id`; `loadChat` removes the legacy `chat.conversationId` key; `saveChat`/`clearChat` do not throw when `localStorage.setItem`/`removeItem` throws (spy with `vi.spyOn(Storage.prototype, …)`); `clearChat` removes `chat.messages`
- [X] T015 [P] [US2] Add to `frontend/src/features/chat/ChatBox.test.tsx`: a chat stored in `chat.messages` renders on mount without any `fetch` and a follow-up sends it as `history`; a successful reply writes both turns to `chat.messages`; a failed send leaves `chat.messages` unchanged; "New chat" removes `chat.messages`; a stored legacy `chat.conversationId` is removed on mount with no alert and no `fetch`
- [X] T016 [P] [US2] Add to `frontend/e2e/tests/chat.spec.ts`: "keeps the chat after reload until New chat" (send, reload, both messages visible; New chat; reload; empty-state text) and "ignores a conversation id from the previous version" (`page.addInitScript` sets `localStorage['chat.conversationId']`; the page loads with no alert, the empty-state text shows, and the key is gone)

### Implementation for User Story 2

- [X] T017 [US2] Create `frontend/src/features/chat/chatStorage.ts`: `CHAT_STORAGE_KEY = 'chat.messages'`, `LEGACY_CONVERSATION_KEY = 'chat.conversationId'`, `MAX_STORED_MESSAGES = 100`; `loadChat(): ChatMessage[]` (removes the legacy key, parses and validates, removes the key and returns `[]` when unreadable), `saveChat(messages)` (stores the last 100), `clearChat()`; every storage access in `try/catch` so chatting continues when storage is unavailable or full
- [X] T018 [US2] Update `frontend/src/features/chat/ChatBox.tsx`: initialise `messages` lazily from `loadChat()`; call `saveChat` with the new list only after a successful reply; call `clearChat()` in "New chat"; write nothing on a failed send (depends on T017)

**Checkpoint**: frontend checks and Playwright pass; US1 tests still pass.

---

## Phase 5: User Story 3 — No database anywhere (Priority: P2), Release A part

**Goal**: The code, local stack, CI, and deploy workflow have no database. Azure SQL resources and the API's SQL env vars **stay** until Release B so the automatic rollback to a pre-A image still works.

**Independent Test**: `docker compose up -d --build` with no `SQL_CONNECTION_STRING` reports healthy and the Playwright suite passes; `git grep` finds no EF/SQL references outside `infra/` (quickstart A1).

### Tests for User Story 3 ⚠️ (write first, see them fail)

- [X] T019 [P] [US3] Create `backend/tests/MisaApp.Api.Tests/NoDatabaseTests.cs`: `typeof(Program).Assembly.GetReferencedAssemblies()` contains no name starting with `Microsoft.EntityFrameworkCore` or `Microsoft.Data.SqlClient` (SC-002, FR-001); `/api/health` returns 200 `Healthy` from an `ApiFactory` that sets no `ConnectionStrings`/`Database` configuration (FR-008)
- [X] T020 [P] [US3] Delete `backend/tests/MisaApp.Api.Tests/StartupTests.cs` (migrate-on-startup no longer exists)

### Implementation for User Story 3

- [X] T021 [US3] Simplify `backend/tests/MisaApp.Api.Tests/ApiFactory.cs`: remove the SQLite connection, the `DbContextOptions<AppDbContext>` swap, `EnsureCreated`, and the `Dispose` override; keep `UseEnvironment("Testing")`, `Gemini:ApiKey = ""`, and the `IChatModel` → `FakeChatModel` swap (`Calls`, `Reply`)
- [X] T022 [US3] In `backend/src/MisaApp.Api/Program.cs`: remove `AddDbContext<AppDbContext>(…UseSqlServer…)`, change `AddHealthChecks().AddDbContextCheck<AppDbContext>()` to `AddHealthChecks()`, remove the `Database:MigrateOnStartup` block and `AddSingleton(TimeProvider.System)`, and remove the now-unused `using`s (depends on T021)
- [X] T023 [US3] Delete `backend/src/MisaApp.Api/Data/AppDbContext.cs`, `backend/src/MisaApp.Api/Data/Migrations/` (3 files), and `backend/src/MisaApp.Api/Features/Chat/ChatEntities.cs` (depends on T003, T010, T022)
- [X] T024 [US3] Remove `Microsoft.EntityFrameworkCore.Design`, `Microsoft.EntityFrameworkCore.SqlServer`, `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore`, and the `System.Security.Cryptography.Pkcs` pin from `backend/src/MisaApp.Api/MisaApp.Api.csproj` (keep `UserSecretsId` for the Gemini key); remove `Microsoft.EntityFrameworkCore.Sqlite` from `backend/tests/MisaApp.Api.Tests/MisaApp.Api.Tests.csproj`; delete `backend/dotnet-tools.json` (depends on T023)
- [X] T025 [P] [US3] Remove the EF Core log level and the `ConnectionStrings` and `Database` sections from `backend/src/MisaApp.Api/appsettings.json`; delete `backend/src/MisaApp.Api/appsettings.Development.json` (database settings only)
- [X] T026 [P] [US3] Remove `ConnectionStrings__Default: ${SQL_CONNECTION_STRING:?…}` and `Database__*` from `compose.yaml` (and any SQL setting in `compose.dev.yaml`/`compose.ci.yaml`); remove `SQL_CONNECTION_STRING` and its comments from `.env.example`
- [X] T027 [P] [US3] Remove the EF bundle and migrator stages from `backend/Dockerfile` (keep build and runtime; check `backend/.dockerignore`); delete `backend/deploy/migrate.sh`
- [X] T028 [P] [US3] In `.github/workflows/ci.yml` e2e job: remove `NAME_SUFFIX`/`DB_NAME`/`RULE_NAME`, the fork check (PRs no longer need Azure), "Create ephemeral database", "Connection string", and "Drop ephemeral database"; run `azure/login` only when `inputs.image_tag != ''` (registry images); drop the `steps.fork` conditions; update the header comment (no database)
- [X] T029 [US3] In `.github/workflows/deploy.yml`: remove the migrator image build and its `verify-tag` check, the `MIGRATE_JOB` and `AZURE_EXTENSION_USE_DYNAMIC_INSTALL` env, the "Migrate database" step, and the migration row of the summary; retarget the first-deployment targeted apply to `-target=azurerm_key_vault.main -target=azurerm_role_assignment.acr_pull -target=azurerm_role_assignment.api_kv_secrets_user` and update its comment ([research R8](research.md#r8-first-deployment-without-the-migrate-job))
- [X] T030 [P] [US3] In `infra/environment/`: delete `migrate_job.tf`; remove the `migrator` key from the AcrPull `for_each` in `identity.tf` (keep the migrator identity: it is the SQL Entra admin until Release B); remove the `migrate_job_name` output from `outputs.tf` and its local from `main.tf`; drop the migrator mention from the `image_tag` description in `variables.tf`. Keep `sql.tf`, `ConnectionStrings__Default`, `Database__MigrateOnStartup`, and the startup probe in `container_apps.tf`
- [X] T031 [P] [US3] Delete `infra/scripts/wait-job-execution.sh` and `infra/scripts/allow-my-ip.sh` (keep `ci-database.sh` and `bootstrap.sh` until Release B)
- [X] T032 [P] [US3] In `frontend/e2e/global-setup.ts`: health wait no longer sized for an Azure SQL resume (180 s → 60 s) and doc comment "frontend → API"; in `frontend/e2e/tests/smoke.spec.ts` drop "or write to the database" from the comment
- [X] T033 [US3] Validate Release A infra and code: quickstart A1 `git grep` returns nothing; `terraform fmt -check -recursive infra`; `terraform validate` both roots; `actionlint` (Docker image as in `ci.yml`)

**Checkpoint**: `dotnet test`, frontend checks, and Playwright against `docker compose up -d --build` with no `SQL_CONNECTION_STRING` in `.env` all pass.

---

## Phase 6: Polish & Cross-Cutting Concerns (Release A)

- [X] T034 [P] Update `README.md`: stack table without a database, no Azure SQL prerequisite, no `SQL_CONNECTION_STRING`/`ConnectionStrings:Default`/`dotnet ef`, skills list without `/db-migration`; describe stateless chat kept in the browser
- [X] T035 [P] Update `CLAUDE.md`: remove the Database row (and Azure SQL from Everything-runs-in-Docker), the `dotnet ef` command, the "Database changes" convention, the "on your Azure SQL dev database" DoD wording, and `/db-migration` from the skills table; keep it consistent with constitution 3.0.0
- [X] T036 [P] Update `backend/CLAUDE.md`: remove EF Core/SQL/migration/`*Utc` guidance; `ApiFactory` has no database
- [X] T037 [P] Update `docs/architecture.md`: stateless chat flow (browser `chat.messages` → `POST /api/chat/messages` with `history` → `IChatModel`), no database, no migrate job; note the SQL resources remaining until Release B
- [X] T038 [P] Update `docs/deployment.md`: remove "Local development on Azure SQL", the migrate step, and the per-developer database; add rollback limits (until Release B reaches an environment, a manual rollback to a pre-A tag still runs because the database, schema, and SQL env vars remain; after Release B, pre-A tags cannot run) and the Release B/C runbook (link [quickstart B/C](quickstart.md#release-b--delete-database-infrastructure-follow-up-pr))
- [X] T039 [P] Update `docs/claude-workflows.md` (remove `/db-migration`) and the skills: delete `.claude/skills/db-migration/`; `.claude/skills/feature/SKILL.md` (stack line without EF Core/SQL Server, risks without "migrations on existing data", no `/db-migration` task or step, summary without migrations); `.claude/skills/verify/SKILL.md` (gates 6–7 need no `SQL_CONNECTION_STRING`); `.claude/skills/daily-start/SKILL.md` (no Azure SQL / `allow-my-ip.sh`); `.claude/skills/bugfix/SKILL.md` (layers without EF/SQL)
- [X] T040 [P] Remove the `dotnet ef` allow/ask rules from `.claude/settings.json` and `ms-mssql.mssql` from `.vscode/extensions.json`
- [X] T041 Run `/verify` (DoD 1–4) and quickstart A2–A5; fix anything that fails
- [X] T042 Update `docs/backlog.md`: Release A of "Stateless chat, remove the database" done; add Release B and Release C as gated follow-ups (link this tasks file)

---

## Phase 7: Release B — delete database infrastructure (US3) ⛔ follow-up PR

**Gate**: Release A deployed and healthy in develop, stage, **and** production. Do not implement on this branch.

- [ ] T043 [US3] In `infra/environment/`: delete `sql.tf`; remove the migrator identity from `identity.tf`; remove `ConnectionStrings__Default`, `Database__MigrateOnStartup`, and the slow startup probe from `container_apps.tf`; remove SQL locals from `main.tf`, `sql_sku`/`sql_auto_pause_minutes`/`sql_use_free_offer` from `variables.tf` and `develop.tfvars`/`stage.tfvars`/`production.tfvars`, `sql_server_fqdn` from `outputs.tf`, and SQL wording from the `suffix` description
- [ ] T044 [US3] In `infra/shared/`: delete `sql_nonprod.tf`; remove the nonprod Key Vault, `sql-admin-password`, and `ci_kv_secrets_user` from `keyvault.tf`; remove the SQL outputs from `outputs.tf`; remove the `developers` variable and its `terraform.tfvars` values; remove the migrator filter from `registry_purge.tf`
- [ ] T045 [P] [US3] Delete `.github/workflows/cleanup-ci-databases.yml` and `infra/scripts/ci-database.sh`; remove the SQL roles, `Microsoft.Sql` provider registration, migrate-job permissions, role-assignment conditions, and Key Vault Secrets Officer grants from `infra/scripts/bootstrap.sh`
- [ ] T046 [P] [US3] Remove the remaining SQL infrastructure from `docs/architecture.md`, `docs/deployment.md`, and `CLAUDE.md` (Infra wording)
- [ ] T047 [US3] Validate: `terraform fmt`/`validate`/`tflint`, `actionlint`; before merging, review `terraform plan` locally for `infra/shared` and `develop` per [quickstart B1](quickstart.md#b1-before-merging-review-the-destroy-plans-locally) (only the listed destroys)
- [ ] T048 [US3] After each environment applies B: deploy smoke test passes; after develop, `az acr repository delete --repository misaapp-migrator`; after production, `az resource list --resource-type Microsoft.Sql/servers` is empty ([quickstart B2](quickstart.md#b2-after-b-is-applied-in-each-environment))

---

## Phase 8: Release C — remove unused Terraform providers (US3) ⛔ follow-up PR

**Gate**: Release B applied in all environments.

- [ ] T049 [US3] Remove `azapi` from `infra/environment/` and `infra/shared/`, and `random` from `infra/shared/` (`versions.tf`, `providers.tf`, `.terraform.lock.hcl`); `terraform init -upgrade -backend=false` + `validate` both roots; the deploy `plan` job shows no changes

---

## Acceptance scenario → test map

| Scenario | Automated test(s) |
| -------- | ----------------- |
| US1-1 send and reply | T004 (200 `{reply}`), T007, T008 |
| US1-2 follow-up has context | T004 (forwarded, trimmed), T006 (`buildHistory`), T007, T008 (`history` length 2) |
| US1-3 model failure | T004 (502), T007 (draft restored, message not added; non-string reply), T008 (routed 502) |
| US1-4 empty/too long | T004 (400), T007 (`maxLength`, Send disabled), T008 |
| US1-5 New chat | T007, T008 |
| US2-1 reload keeps chat | T014, T015, T016 |
| US2-2 New chat clears storage | T014, T015, T016 |
| US2-3 legacy reference | T014, T015, T016 |
| US3-1 local stack, no DB | T019, `HealthTests`, Playwright suite on the stack (T041) |
| US3-2 CI without DB | T028 (CI e2e job on the PR), T033 (`actionlint`) |
| US3-3 deploy without migration | T029, deploy smoke test (`smoke.spec.ts`) after merge |
| US3-4/5/6 infra removed, data deleted | T047 (plan review), T048 (smoke tests, `az resource list`) |

Edge cases: forged/malformed turns (incl. numeric roles) → T004; storage unavailable/corrupt/bounded and two tabs → T014;
long chats → T004, T006; health without a database → T019.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** → **Foundational (Phase 2)** → user stories.
- **US1 (Phase 3)**: after Phase 2.
- **US2 (Phase 4)**: after US1 (builds on the rewritten `ChatBox.tsx` and `chatApi.ts`).
- **US3 (Phase 5)**: after US1 (T023 deletes entities that the old `ChatService` used); independent of US2.
- **Polish (Phase 6)**: after US1–US3.
- **Release B (Phase 7)**: separate PR, after Release A is live in all environments.
- **Release C (Phase 8)**: separate PR, after Release B is applied everywhere.

### Within Each Story

- Tests first, failing; then backend contracts → service → endpoints; frontend API → component.
- US3 backend order: T021 → T022 → T023 → T024 (each keeps the build compiling).

### Parallel Opportunities

- US1: T004–T008 together; T012 in parallel with the backend chain T009 → T010 → T011.
- US2: T014–T016 together.
- US3: T019, T020, T025–T028, T030–T032 together (different files).
- Polish: T034–T040 together.
- US2 and US3 can run in parallel after US1.

---

## Parallel Example: User Story 1

```bash
# Tests first:
Task: "Rewrite ChatEndpointsTests.cs (history, limits, 502, removed routes)"
Task: "Create chatApi.test.ts (buildHistory, reply guard)"
Task: "Rewrite ChatBox.test.tsx for stateless send/history/New chat"
Task: "Update e2e chat.spec.ts (follow-up history, New chat)"

# Then implementation, two tracks:
Task: "ChatContracts.cs → ChatService.cs → ChatEndpoints.cs"
Task: "chatApi.ts → ChatBox.tsx"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 (constitution 3.0.0) and Phase 2 (shared types).
2. Phase 3: stateless chatting with history. **Stop and validate**: backend, frontend, and E2E checks.

### Incremental Delivery (Release A on this branch)

1. US1 → chat works with no server-side state.
2. US2 → chat survives reloads until "New chat".
3. US3 → no database in code, compose, CI, or deploy workflow.
4. Polish → docs, skills, `/verify`.

### Follow-ups

Releases B and C are separate PRs (Phases 7–8), each promoted develop → stag → main before the next.

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks.
- E2E assertions never depend on model wording (the echo model is used with no key).
- No EF migration: the tables disappear with the databases in Release B.
- Commits only when a human asks.

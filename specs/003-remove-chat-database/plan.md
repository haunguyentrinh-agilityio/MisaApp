# Implementation Plan: Stateless Chat, Remove the Database

**Branch**: `003-remove-chat-database` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-remove-chat-database/spec.md`

## Summary

Chats are no longer stored on the server. The browser keeps the current chat in `localStorage`
(`chat.messages`) until "New chat" and sends the recent turns (`history`) with every message; the API
validates them, calls `IChatModel`, and returns `{ reply }`. EF Core, SQL Server, migrations, the
migrator image/job, CI databases, and all Azure SQL resources are removed.

Azure removal is staged as expand/contract for infrastructure ([research R7](research.md#r7-order-of-removal-in-azure-expandcontract-for-infrastructure)):

| Release | PR | Scope | Deletes in Azure |
| ------- | -- | ----- | ---------------- |
| **A** | this branch | App, tests, compose, CI, deploy workflow, Dockerfile, constitution 3.0.0, docs | Migrate job, migrator AcrPull role |
| **B** | follow-up, after A is live in develop, stage, **and** production | Terraform SQL resources, SQL env vars, clean-up workflow/scripts, bootstrap | SQL servers, databases (with all stored conversations), firewall rules, migrator identity, nonprod Key Vault + SQL admin password, CI role assignments |
| **C** | follow-up, after B is applied everywhere | `azapi` / `random` providers and lock entries | nothing |

## Technical Context

**Language/Version**: C# / .NET 10 (`global.json`), TypeScript 5 / React 19, HCL (Terraform pinned in `versions.tf`), GitHub Actions YAML

**Primary Dependencies**: ASP.NET Core minimal APIs + `AddValidation()`, `Google.GenAI`; Vite, pnpm. **Removed**: `Microsoft.EntityFrameworkCore.SqlServer`, `.Design`, `.Sqlite` (tests), `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore`, `System.Security.Cryptography.Pkcs` pin, `dotnet-ef` tool

**Storage**: None on the server. Browser `localStorage`, key `chat.messages`, ≤ 100 messages ([data-model.md](data-model.md))

**Testing**: xUnit v3 + `ApiFactory` (no database, `FakeChatModel`); Vitest + RTL; Playwright against the Docker stack; `terraform validate`, `actionlint`

**Target Platform**: Linux containers on Azure Container Apps; modern browsers

**Project Type**: Web application (frontend + backend + infra)

**Performance Goals**: No database round-trips per message; a deploy has no migration step, so it is not slower than today (SC-005)

**Constraints**: Request bounded to 20 history turns × 8,000 chars + 4,000-char message (≈ 41k tokens); `crypto.randomUUID` unavailable in the E2E container (`http://frontend`); Terraform deletes resources on merge (shared `-auto-approve` on develop); automatic rollback re-applies the current config with the previous image

**Scale/Scope**: 1 endpoint changed, 2 removed; ~4 backend files deleted + migrations; 3 frontend files rewritten; 2 Terraform roots; 3 workflows; constitution, 3 CLAUDE/guide docs, 5 skills

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against constitution **2.0.0**.

| Principle / rule | Pre-research | Post-design | Notes |
| ---------------- | ------------ | ----------- | ----- |
| I. Feature-Sliced Code | ✅ | ✅ | Everything stays in `Features/Chat/` and `features/chat/`. The "entities and their EF configuration" item no longer applies to Chat (no entities); `Data/` is deleted. No new layers. |
| II. Tests Ship With Every Change | ⚠️ | ✅ after amendment | `ApiFactory` "+ SQLite in-memory" is a MUST that can't hold without a database; 3.0.0 drops it. Every acceptance scenario maps to a test (tasks), US3 infra scenarios to `validate`/plan checks + quickstart. |
| III. Explicit API Contract | ✅ | ✅ | Breaking change called out in spec FR-007, [contract](contracts/chat-api.md), and Risks below. DTO + `chatApi.ts` change together. Validation via DataAnnotations + `AddValidation()`. |
| IV. Model-Agnostic AI Integration | ✅ | ✅ | `IChatModel` unchanged; echo fallback kept; 502 ProblemDetails; nothing to leave partial. |
| V. Reproducible Docker Environment **on Azure SQL** | ❌ | ✅ after amendment | The feature removes Azure SQL, which this principle mandates in every environment. Resolved by amending to 3.0.0 (Principle V redefined as "Reproducible Docker Environment", no database). |
| Security & Data: EF migrations; `*Utc` + `TimeProvider` | ❌ | ✅ after amendment | No schema left; rules removed in 3.0.0. "Chat content only in the visitor's browser" added. |
| Security & Data: length limits server + client | ✅ | ✅ | Message 4,000; turns 20 × 8,000 on server (DataAnnotations) and client (slice + truncate). |
| Secrets | ✅ | ✅ | `SQL_CONNECTION_STRING` removed from `.env.example`/compose; `.env` not read. |
| Workflow & quality gates | ✅ | ✅ | DoD unchanged except step 3 no longer needs Azure SQL. |

**Gate result**: PASS conditional on the constitution amendment to **3.0.0**, delivered in Release A
through `/speckit-constitution` (MAJOR: Principle V redefined, migration rules removed;
[research R10](research.md#r10-constitution-amendment)). The amendment is a tracked task that runs
before code changes, so no exception is recorded in Complexity Tracking.

## Removal inventory

Everything database-related and the release that removes it. Line numbers refer to the current `develop`.

### Release A (this branch)

| Area | Change |
| ---- | ------ |
| `backend/src/MisaApp.Api/Program.cs` | Remove `AddDbContext`, `AddDbContextCheck`, `Database:MigrateOnStartup` block, `TimeProvider` registration |
| `Features/Chat/ChatService.cs` | Stateless `SendAsync(history, message, ct)`; no `AppDbContext`/`TimeProvider`; drop `Get/ListConversationsAsync` |
| `Features/Chat/ChatEndpoints.cs` | POST returns `{ reply }`; remove both GET routes and the 404 branch |
| `Features/Chat/ChatContracts.cs` | `SendMessageRequest(Message, History)`, `SendMessageResponse(Reply)`, `ChatLimits.MaxHistoryTurns/MaxHistoryTurnLength`; delete `ChatMessageDto`, `ConversationDto`, `ConversationSummaryDto` |
| `Features/Chat/ChatEntities.cs` | Delete; `ChatRole` moves to `IChatModel.cs` with validation attributes on `ChatTurn` |
| `Data/AppDbContext.cs`, `Data/Migrations/*` | Delete |
| `MisaApp.Api.csproj`, test csproj, `backend/dotnet-tools.json` | Remove EF/SqlClient/health-EF packages, the Pkcs pin, Sqlite, `dotnet-ef` |
| `appsettings.json`, `appsettings.Development.json` | Remove EF log level, `ConnectionStrings`, `Database`; delete the Development file (DB-only) |
| Backend tests | `ApiFactory` without SQLite; delete `StartupTests`, `ConversationTests`; rewrite `ChatEndpointsTests` |
| `frontend/src/features/chat/` | `chatApi.ts` (new contract, reply guard), `ChatBox.tsx` (localStorage, history, legacy key), new `chatStorage.ts`; tests rewritten |
| `frontend/e2e/` | `chat.spec.ts` (persist/New chat/history/legacy key); `global-setup.ts` health wait and comments; `smoke.spec.ts` comment |
| `compose.yaml`, `.env.example` | Remove `ConnectionStrings__Default`, `Database__*`, `SQL_CONNECTION_STRING` |
| `backend/Dockerfile`, `backend/deploy/migrate.sh` | Delete bundle + migrator stages and the script |
| `.github/workflows/ci.yml` | E2E job: no DB create/drop, no SQL env; Azure login only for registry images |
| `.github/workflows/deploy.yml` | No migrator build/verify, no migrate step/summary row, first deploy targets `azurerm_key_vault.main` |
| `infra/environment` | Delete `migrate_job.tf`, migrator `acr_pull` key, `migrate_job_name` output + local, image_tag description. **Keep** SQL resources, migrator identity, and the API's SQL env vars + startup probe (rollback safety) |
| `infra/scripts/` | Delete `wait-job-execution.sh`, `allow-my-ip.sh` |
| `.specify/memory/constitution.md` | 3.0.0 via `/speckit-constitution` |
| Docs | `README.md`, `CLAUDE.md`, `backend/CLAUDE.md`, `docs/architecture.md`, `docs/deployment.md` (incl. Release B/C runbook and rollback limits), `docs/claude-workflows.md`, `docs/backlog.md` |
| Tooling | Delete `.claude/skills/db-migration`; update `feature`, `verify`, `daily-start`, `bugfix` skills; `.claude/settings.json` `dotnet ef` rules; `.vscode/extensions.json` `ms-mssql.mssql` |

### Release B (follow-up PR; gate: A healthy in develop, stage, production)

| Area | Change |
| ---- | ------ |
| `infra/environment` | Delete `sql.tf`; migrator identity; API `ConnectionStrings__Default`, `Database__MigrateOnStartup`, slow startup probe; `sql_*` variables + tfvars; `sql_server_fqdn` output; SQL locals |
| `infra/shared` | Delete `sql_nonprod.tf`; nonprod Key Vault, `sql-admin-password`, `ci_kv_secrets_user`; SQL outputs; `developers` var + tfvars; migrator filter in `registry_purge.tf` |
| Workflows / scripts | Delete `cleanup-ci-databases.yml`, `infra/scripts/ci-database.sh`; remove SQL roles/provider/conditions from `bootstrap.sh` |
| Manual | `az acr repository delete --repository misaapp-migrator` after B reaches develop |

### Release C (follow-up PR; gate: B applied everywhere)

Remove `azapi` (both roots) and `random` (`infra/shared`) from `versions.tf`, `providers.tf`, and
`.terraform.lock.hcl`.

## Project Structure

### Documentation (this feature)

```text
specs/003-remove-chat-database/
├── plan.md              # This file
├── research.md          # R1–R10 decisions
├── data-model.md        # Per-request server types + browser storage
├── quickstart.md        # Validation for Releases A, B, C
├── contracts/
│   └── chat-api.md      # POST /api/chat/messages after the change; removed routes
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
backend/
├── Dockerfile                                  # build + runtime only (bundle/migrator stages removed)
├── src/MisaApp.Api/
│   ├── Program.cs                              # no DbContext, no migrate-on-startup
│   ├── appsettings.json                        # no ConnectionStrings/Database
│   └── Features/
│       ├── Chat/
│       │   ├── ChatContracts.cs                # SendMessageRequest(Message, History), SendMessageResponse(Reply), ChatLimits
│       │   ├── ChatEndpoints.cs                # POST /api/chat/messages only
│       │   ├── ChatService.cs                  # stateless
│       │   ├── ChatModels.cs                   # unchanged (Gemini/Echo)
│       │   ├── ChatServiceCollectionExtensions.cs
│       │   └── IChatModel.cs                   # ChatRole + ChatTurn (validated) + IChatModel
│       └── Version/                            # unchanged
└── tests/MisaApp.Api.Tests/
    ├── ApiFactory.cs                           # no SQLite
    ├── Features/Chat/ChatEndpointsTests.cs     # rewritten (ConversationTests.cs deleted)
    ├── NoDatabaseTests.cs                      # no EF/SqlClient references; healthy without DB config
    └── HealthTests.cs                          # unchanged

frontend/
├── src/features/chat/
│   ├── chatApi.ts                              # new contract types + reply guard
│   ├── chatApi.test.ts                         # buildHistory, reply guard
│   ├── chatStorage.ts                          # load/save/clear chat.messages, legacy key
│   ├── chatStorage.test.ts
│   ├── ChatBox.tsx                             # message ids, history from state, persist after reply
│   └── ChatBox.test.tsx
└── e2e/tests/chat.spec.ts                      # history, persistence, New chat, legacy key

infra/environment/                              # A: migrate_job.tf removed; B: sql.tf removed
infra/shared/                                   # B: sql_nonprod.tf + nonprod Key Vault removed
.github/workflows/{ci,deploy}.yml               # A: no DB steps; B: cleanup-ci-databases.yml removed
```

**Structure Decision**: Existing web-application layout; the change stays inside the Chat feature
folders. `backend/src/MisaApp.Api/Data/` disappears because a database was its only cross-cutting
concern. `chatStorage.ts` is a feature-local module (it is chat-specific, not cross-cutting).

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| Breaking API change | An open tab with the old bundle can't render replies until reload; new bundle + old API (seconds during the swap) shows an error | Old bundle already handles the restore 404; new client guards `reply` is a string and restores the draft. Accepted per Principle III ([R4](research.md#r4-response-shape-and-breaking-change)) |
| Rollback limits | After B reaches an environment, pre-A images cannot run there | A keeps SQL, schema, and env vars, so automatic and manual rollbacks to pre-A tags work until B; B is gated on A being live everywhere; documented in `docs/deployment.md` |
| Irreversible data deletion | B deletes every stored conversation, no backup (Q2 = A) | Explicit user decision; plans reviewed locally before merging B |
| Terraform auto-apply | Merging B to develop deletes the shared nonprod server with `-auto-approve` | Local `terraform plan` review for `infra/shared` and `develop` before merge ([quickstart B1](quickstart.md#b1-before-merging-review-the-destroy-plans-locally)) |
| LLM cost from client-supplied history | Any caller can send ≈ 41k tokens per request | Server-side limits (20 turns, 8,000 chars, `MaxHistoryMessages`); similar to today's server-built history; rate limiting remains in the backlog |
| Forged history | A caller can invent assistant turns | Affects only that caller's reply; no shared state ([R2](research.md#r2-request-size-history-limits-and-llm-cost)) |
| Nonprod Key Vault soft delete | Name `kv-misaapp-np-<suffix>` unusable during retention | Not reused ([R9](research.md#r9-key-vault-deletion-in-infrashared-release-b)) |
| Browser storage on shared devices | The chat stays until "New chat" | Accepted in the spec (no accounts) |

## Complexity Tracking

No violations to justify. The Principle V and Security & Data conflicts are resolved by amending the
constitution to 3.0.0 in this release rather than by an exception.

# Research: Stateless Chat (Remove the Database)

All Technical Context unknowns are resolved below. Inventory of database touch points: see the
"Removal inventory" in [plan.md](plan.md#removal-inventory).

## R1. Where conversation context comes from without a database

- **Decision**: The browser sends the recent turns of the current chat with every message
  (`history`). The API is stateless: it validates the history, keeps the last
  `Gemini:MaxHistoryMessages - 1` turns, appends the new message, and calls `IChatModel`.
- **Rationale**: Satisfies FR-001 (nothing outlives the request) and FR-003 (follow-ups have
  context). Works with any number of API replicas and survives revision swaps.
- **Alternatives considered**: In-memory server cache keyed by a conversation id. Rejected: it is
  server-side storage (FR-001), is lost on every deploy/scale event, and breaks with more than one
  replica. Distributed cache (Redis): same objection plus a new resource to run.

## R2. Request size, history limits, and LLM cost

- **Decision**: `history` is optional, at most `ChatLimits.MaxHistoryTurns = 20` items; each item has a
  role of `user` or `assistant` and content of 1–`ChatLimits.MaxHistoryTurnLength = 8000` characters
  (twice the message limit, because assistant replies are longer than user messages). The client sends
  only the last 20 turns and truncates any longer turn content to 8,000 characters before sending.
  The server additionally applies the existing `Gemini:MaxHistoryMessages` cap (20 incl. the new
  message).
- **Rationale**: Constitution "user-supplied text has explicit length limits on both server and client".
  Worst case per request ≈ 20 × 8,000 + 4,000 characters (≈ 41k tokens), comparable to the old
  server-built history (20 turns of unbounded assistant replies). Truncating on the client instead of
  rejecting on the server prevents a chat from becoming unsendable after one long reply.
- **Alternatives considered**: Total character budget across turns (more logic on both sides for the
  same protection); no per-turn limit (unbounded tokens per anonymous request). Rate limiting stays
  in the backlog (`AddRateLimiter`), unchanged by this feature.
- **Risk**: History is client-supplied, so a caller can forge "assistant" turns. This only affects
  that caller's own reply (no shared state, no accounts), so it is accepted.

## R3. Validating the nested history in .NET 10

- **Decision**: Put DataAnnotations on `ChatTurn` (`[property: Required, StringLength(8000, MinimumLength = 1)]`)
  and `[property: MaxLength(20)]` on `SendMessageRequest.History`. The .NET 10 minimal-API validation
  (`AddValidation()`) validates nested complex types and collection items and returns 400
  ProblemDetails. An unknown `role` string fails JSON binding, which also yields 400 (ProblemDetails
  through `AddProblemDetails` + `UseStatusCodePages`). The enum converter is created with
  `allowIntegerValues: false`; otherwise `"role": 5` would bind to an undefined `ChatRole` and reach
  the model as an assistant turn.
- **Rationale**: Same mechanism the project already uses; no custom validator. `ChatTurn` is the type
  `IChatModel` already consumes, so no separate DTO and mapping are needed.
- **Verification**: Integration tests cover blank content, oversize content, too many turns, and an
  unknown role (all → 400 `application/problem+json`).
- **Alternatives considered**: A separate `ChatTurnDto` plus mapping (an extra type with no behavior);
  `IValidatableObject` on the request (manual code the framework already provides).

## R4. Response shape and breaking change

- **Decision**: `POST /api/chat/messages` returns `{ "reply": "<text>" }`. `conversationId`,
  `userMessage`, message ids and timestamps are removed. `GET /api/chat/conversations` and
  `GET /api/chat/conversations/{id}` are removed (they now return 404 ProblemDetails).
- **Rationale**: Without storage there is no id or server timestamp to return; the client already has
  the user message it sent. Smallest honest contract.
- **Compatibility window**: Web and API revisions switch within the same Terraform apply, and a browser
  may still run the previous bundle until reload. Old bundle + new API: the restore call returns 404,
  which the old bundle already handles by forgetting the id; a send then fails to render (the old bundle
  expects `userMessage`) until the page is reloaded. New bundle + old API (seconds): the old API ignores
  `history` and returns a superset shape that includes `reply` as an object, so the new bundle shows an
  error and restores the draft. Accepted and called out in the plan; no versioning, per Principle III.
- **Alternatives considered**: Keeping the old response fields with fake values (misleading contract);
  a `/v2` route (Principle III: co-change instead of versioning).

## R5. Browser storage of the chat

- **Decision**: `localStorage` key `chat.messages` holds a JSON array of `{ id, role, content }`, capped
  at the most recent `MAX_STORED_MESSAGES = 100`. Reads are validated; unreadable data is removed
  silently. Writes are wrapped in `try/catch` (quota exceeded, storage disabled) so chatting continues.
  On load, the legacy key `chat.conversationId` is removed. Message ids are generated client-side with
  a counter + timestamp helper, not `crypto.randomUUID()`, which only exists in secure contexts and the
  Playwright container loads the app from `http://frontend`.
- **Rationale**: Clarification Q1 = B (persist until "New chat"). The cap bounds storage (~100 ×
  8 KB worst case, well under the ~5 MB quota).
- **Alternatives considered**: `sessionStorage` (rejected by the user), IndexedDB (async API and more
  code for no benefit at this size).

## R6. Health checks without a database

- **Decision**: `AddHealthChecks()` with no checks; `/api/health` reports the process is up. The smoke
  test continues to check the page, `/api/health`, and `/api/version` (exact commit).
- **Rationale**: The only dependency left is Gemini, and probing it would cost money and couple
  health to a third party. The echo model needs nothing.
- **Alternatives considered**: A Gemini reachability check (cost, flakiness, and a third-party outage
  would restart healthy replicas).

## R7. Order of removal in Azure (expand/contract for infrastructure)

`deploy.yml` applies Terraform automatically on merge (`infra/shared` with `-auto-approve` on every
develop push; `infra/environment` after approval on stage/production, without approval on develop).
Removing a resource block deletes the resource, and `prevent_destroy` no longer applies once the block
is gone. The automatic rollback re-applies the **current** Terraform config with the **previous**
image tag.

- **Decision**: Three releases, each a separate PR, each promoted develop → stag → main before the next
  one is merged into develop.
  - **Release A (this branch)**: the app stops using the database. Code, tests, compose, CI and the
    deploy workflow no longer build, migrate, or create databases. Terraform removes only the migrate
    job and the migrator's AcrPull role. The API container app **keeps** `ConnectionStrings__Default` and
    `Database__MigrateOnStartup` (ignored by the new code) and all SQL resources stay, so the automatic
    rollback to a pre-A image still works.
  - **Release B**: delete the database infrastructure. `infra/environment`: SQL server, database,
    firewall rule, migrator identity, the API's SQL env vars, SQL variables/tfvars/outputs/locals, and
    the slow startup probe. `infra/shared`: nonprod SQL server and developer databases, the SQL admin
    password, the nonprod Key Vault and its role assignment, CI SQL role assignments, the
    `developers` variable, the migrator purge filter; `cleanup-ci-databases.yml` and
    `ci-database.sh`; bootstrap SQL roles. The shared part is deleted when B reaches develop; each
    environment's part when B reaches that environment.
  - **Release C**: remove the `azapi` and `random` providers and their lock entries from both roots.
    Terraform needs a provider in config to destroy that provider's resources
    (`azapi_resource.developer_database`, `random_password.sql_admin`), so the providers can only go
    after B has been applied everywhere.
- **Rationale**: FR-011 (infrastructure removed only after the database-free version is live) and the
  constitution's backward-compatibility rule, applied to infrastructure. Each release is independently
  safe to roll back to the release before it.
- **Rollback limits**: Until B reaches an environment, a `workflow_dispatch` rollback to a pre-A tag
  still runs: `verify-tag` checks only the api and web images, and the database, schema, and SQL env
  vars are still there (the dispatch path never ran migrations). After B, an environment cannot run a
  pre-A image (no database). Documented in `docs/deployment.md`.
- **Alternatives considered**: One PR that removes everything. Rejected: the shared apply runs before
  the new revision is live, the environment apply deletes SQL while the old revision still serves, and a
  failed smoke test would roll back to an image that has no database. `removed` blocks with
  `destroy = false` (forget without deleting) — rejected: the user chose deletion (Q2 = A), and
  forgotten resources keep costing money.

## R8. First deployment without the migrate job

- **Decision**: The deploy workflow's first-deployment targeted apply now targets `azurerm_key_vault.main`,
  `azurerm_role_assignment.acr_pull` and `azurerm_role_assignment.api_kv_secrets_user` (previously it
  reached them only through the migrate job's `depends_on`). The re-plan after it stays.
- **Rationale**: The Gemini secret preflight runs right after and needs the vault to exist. Creating the
  role assignments in the targeted apply also gives them time to propagate before the apps first pull
  images and read the Gemini secret, as the migrate job used to.

## R9. Key Vault deletion in infra/shared (Release B)

- **Decision**: The nonprod vault `kv-misaapp-np-<suffix>` exists only for `sql-admin-password`, so it is
  deleted in B. It has purge protection, so it stays soft-deleted for its retention period and its name
  cannot be reused meanwhile; azurerm skips purging when purge protection is on. The operator reviews
  `terraform plan` for `infra/shared` locally before merging B (quickstart §B), because the develop
  apply is `-auto-approve`.
- **Alternatives considered**: Keep the empty vault (an unused resource with RBAC to maintain).

## R10. Constitution amendment

- **Decision**: Amend the constitution to **3.0.0** (MAJOR: Principle V is redefined, and the EF
  migration rule is removed) through `/speckit-constitution` in Release A:
  - Principle II: drop "SQLite in-memory" from `ApiFactory`, and replace "Azure SQL, migrations" in the rationale.
  - Principle V: "Reproducible Docker Environment". Stack = frontend, backend, Playwright; no database.
    Chat content is not stored server-side. Adding persistent storage requires an amendment.
  - Security & Data: remove the EF migration and `*Utc` timestamp rules; add "chat content is kept only in the visitor's
    browser".
  - Sync `CLAUDE.md`, `backend/CLAUDE.md`, and the `/feature`, `/verify`, `/daily-start`, `/bugfix`
    skills; delete the `/db-migration` skill.
- **Rationale**: The constitution currently mandates Azure SQL everywhere; leaving it would make every
  future plan fail its Constitution Check.

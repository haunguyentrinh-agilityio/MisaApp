# Backlog

Maintained by the `/feature`, `/daily-start`, and `/daily-wrap-up` workflows. Keep items short and link specs in `specs/`. Start an item with `/feature <item>` (or `/speckit-specify`).

## In progress

- [ ] **CI/CD to Azure** ([spec](../specs/002-cicd-azure-deploy/spec.md)): code complete; waiting on bootstrap and the live validation runs (quickstart §0–§8).
- [ ] **Stateless chat, remove the database: Release B** ([tasks](../specs/003-remove-chat-database/tasks.md), Phase 7): delete the Azure SQL servers/databases, nonprod vault, CI database cleanup, and migrator identity. Gate: Release A deployed and healthy in develop, stage, and production.
- [ ] **Stateless chat, remove the database: Release C** ([tasks](../specs/003-remove-chat-database/tasks.md), Phase 8): drop the `azapi`/`random` Terraform providers. Gate: Release B applied in all environments.

## Next

- [ ] **Streaming replies**: stream Gemini output to the chat box (`GenerateContentStreamAsync` + SSE).
- [ ] **Markdown rendering** for assistant messages (sanitized).
- [ ] **Constitution 3.1.0**: Terraform pin, deploy only through `deploy.yml` (deferred from 002; the migration rule no longer applies).

## Later

- [ ] Authentication (e.g., Microsoft Entra ID / OIDC).
- [ ] Saved conversations (sidebar, per-user history): needs server-side storage, so a constitution amendment first.
- [ ] Rate limiting on `/api/chat/*` (`AddRateLimiter`).
- [ ] Token/cost tracking from `UsageMetadata`.
- [ ] Structured logging + OpenTelemetry.
- [ ] VNet-integrated Container Apps.

## Done

- [x] 2026-10-14: Project scaffold: Docker stack, chat with Gemini, tests at all three levels, Claude workflows ([spec](../specs/001-chat/spec.md)).
- [x] 2026-10-14: Adopted GitHub Spec Kit for spec-driven development ([constitution](../.specify/memory/constitution.md)).
- [x] 2026-10-14: CI pipeline (PR checks: backend, frontend, infra, secrets, E2E on Azure SQL) and production deployment target with a migration step (Azure Container Apps, Terraform) ([spec](../specs/002-cicd-azure-deploy/spec.md)).
- [x] 2026-10-16: Stateless chat, Release A: the app, local stack, CI, and deploy no longer use a database; the chat is kept in the browser until **New chat** ([spec](../specs/003-remove-chat-database/spec.md)).

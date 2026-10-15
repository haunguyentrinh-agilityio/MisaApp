# Backlog

Maintained by the `/feature`, `/daily-start`, and `/daily-wrap-up` workflows. Keep items short and link specs in `specs/`. Start an item with `/feature <item>` (or `/speckit-specify`).

## In progress

- [ ] **CI/CD to Azure** ([spec](../specs/002-cicd-azure-deploy/spec.md)): code complete; waiting on bootstrap and the live validation runs (quickstart §0–§8).

## Next

- [ ] **Streaming replies**: stream Gemini output to the chat box (`GenerateContentStreamAsync` + SSE).
- [ ] **Markdown rendering** for assistant messages (sanitized).
- [ ] **Conversation sidebar**: list/switch/delete conversations (`GET /api/chat/conversations` already exists).
- [ ] **Constitution 2.1.0**: Terraform pin, deploy only through `deploy.yml`, backward-compatible migrations (deferred from 002).

## Later

- [ ] Authentication (e.g., Microsoft Entra ID / OIDC) and per-user conversations.
- [ ] Rate limiting on `/api/chat/*` (`AddRateLimiter`).
- [ ] Token/cost tracking from `UsageMetadata`.
- [ ] Structured logging + OpenTelemetry.
- [ ] VNet-integrated Container Apps + SQL private endpoints.
- [ ] Per-developer contained users on nonprod SQL.

## Done

- [x] 2026-10-14: Project scaffold: Docker stack, chat with Gemini, tests at all three levels, Claude workflows ([spec](../specs/001-chat/spec.md)).
- [x] 2026-10-14: Adopted GitHub Spec Kit for spec-driven development ([constitution](../.specify/memory/constitution.md)).
- [x] 2026-10-14: CI pipeline (PR checks: backend, frontend, infra, secrets, E2E on Azure SQL) and production deployment target with a migration step (Azure Container Apps, Terraform) ([spec](../specs/002-cicd-azure-deploy/spec.md)).

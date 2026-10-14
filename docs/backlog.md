# Backlog

Maintained by the `/feature`, `/daily-start`, and `/daily-wrap-up` workflows. Keep items short and link specs in `specs/`. Start an item with `/feature <item>` (or `/speckit-specify`).

## In progress

_(nothing yet)_

## Next

- [ ] **Streaming replies**: stream Gemini output to the chat box (`GenerateContentStreamAsync` + SSE).
- [ ] **Markdown rendering** for assistant messages (sanitized).
- [ ] **Conversation sidebar**: list/switch/delete conversations (`GET /api/chat/conversations` already exists).
- [ ] **CI pipeline**: GitHub Actions running backend tests, frontend checks, and the Docker E2E suite.

## Later

- [ ] Authentication (e.g., Microsoft Entra ID / OIDC) and per-user conversations.
- [ ] Rate limiting on `/api/chat/*` (`AddRateLimiter`).
- [ ] Token/cost tracking from `UsageMetadata`.
- [ ] Structured logging + OpenTelemetry.
- [ ] Production deployment target and migration step.

## Done

- [x] 2026-10-14: Project scaffold: Docker stack, chat with Gemini, tests at all three levels, Claude workflows ([spec](../specs/001-chat/spec.md)).
- [x] 2026-10-14: Adopted GitHub Spec Kit for spec-driven development ([constitution](../.specify/memory/constitution.md)).

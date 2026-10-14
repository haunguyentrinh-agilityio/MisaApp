# 001 — Chat box with Gemini

- **Status:** Done
- **Created:** 2026-10-14

> Written before Spec Kit was adopted, so it doesn't follow `.specify/templates/spec-template.md`
> and has no plan/tasks. Kept as the historical record of the scaffold; new features start with
> `/speckit-specify` and get the next number (002+).

## Problem

Users need an in-app assistant they can talk to, backed by Google Gemini via the `Google.GenAI` .NET SDK.

## User stories

- As a user, I want to type a question and get an AI answer in the page.
- As a user, I want my conversation to survive a page reload.
- As a user, I want to start a fresh conversation.

## Acceptance criteria

1. **Given** an empty chat **When** I send a message **Then** my message appears immediately, a "Thinking…" indicator shows, and the reply replaces it.
2. **Given** an existing conversation **When** I send a follow-up **Then** the model receives the previous turns (up to `Gemini:MaxHistoryMessages`).
3. **Given** I reload the page **Then** the previous conversation is shown.
4. **Given** the model call fails **Then** I see an error, my text is put back in the input, and nothing is stored.
5. **Given** a blank or >4000-char message **Then** the API returns 400 (the UI prevents both).
6. **Given** no `GEMINI_API_KEY` **Then** the app still works with an echo reply.

## API contract

See `docs/architecture.md` → Chat feature.

## Data model changes

`Conversations`, `ChatMessages` tables. Migration `InitialCreate`.

## Testing

- Backend: `ChatEndpointsTests`, `ConversationTests`, `HealthTests`.
- Frontend: `ChatBox.test.tsx`.
- E2E: `chat.spec.ts`, `health.spec.ts`.

## Out of scope

Streaming, markdown rendering, multiple-conversation UI, auth (see backlog).

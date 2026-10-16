# Contract: Chat API (after feature 003)

Base path `/api/chat`. JSON is camelCase; enums are camelCase strings. Errors are RFC 7807
ProblemDetails (`application/problem+json`); the frontend shows `detail ?? title`.

> **Breaking change** (Principle III): request and response of `POST /api/chat/messages` change, and
> both `GET` routes are removed. Frontend (`chatApi.ts`) and backend change in the same release.

## POST /api/chat/messages

Send a message with the recent turns of the current chat; returns the assistant's reply. Nothing is
stored.

### Request

```json
{
  "message": "And in Python?",
  "history": [
    { "role": "user", "content": "How do I reverse a list in C#?" },
    { "role": "assistant", "content": "Use list.Reverse() or Enumerable.Reverse(...)." }
  ]
}
```

| Field                | Rules                                                         |
| -------------------- | ------------------------------------------------------------- |
| `message`            | required; 1–4,000 characters after trimming; not blank        |
| `history`            | optional; ≤ 20 items; oldest first                            |
| `history[].role`     | `"user"` or `"assistant"` (strings only; numbers are rejected) |
| `history[].content`  | required; 1–8,000 characters; not blank                       |

Unknown properties (for example a legacy `conversationId`) are ignored.

### Responses

| Status | Body                                   | When                                                         |
| ------ | -------------------------------------- | ------------------------------------------------------------ |
| 200    | `{ "reply": "string" }`                | The model answered                                           |
| 400    | ProblemDetails (validation `errors`)   | Blank/oversized message; too many turns; blank/oversized turn content; unknown role; malformed JSON |
| 502    | ProblemDetails `title: "Chat model unavailable"` | The model call failed or returned an empty reply   |

The server sends the model `history.TakeLast(Gemini:MaxHistoryMessages - 1)` plus the new message.

The client treats a 200 whose `reply` is not a string as an error (guards the seconds-long window in
which a new bundle may reach the previous API revision).

## Removed

| Method | Route                            | Now  |
| ------ | -------------------------------- | ---- |
| GET    | `/api/chat/conversations`        | 404 ProblemDetails (no route) |
| GET    | `/api/chat/conversations/{id}`   | 404 ProblemDetails (no route) |

`404` on `POST /api/chat/messages` for an unknown `conversationId` no longer exists.

## Unchanged

| Method | Route          | Notes                                                     |
| ------ | -------------- | --------------------------------------------------------- |
| GET    | `/api/health`  | `Healthy` (200); no longer includes a database check      |
| GET    | `/api/version` | `{ "commit", "environment" }`                             |

## TypeScript (`frontend/src/features/chat/chatApi.ts`)

```ts
export type ChatRole = 'user' | 'assistant'
export interface ChatTurn { role: ChatRole; content: string }
export interface SendMessageRequest { message: string; history: ChatTurn[] }
export interface SendMessageResponse { reply: string }
```

# Data Model: Stateless Chat (Remove the Database)

There is no server-side data model after this feature. The `Conversation` and `ChatMessage` entities,
`AppDbContext`, and the `InitialCreate` migration are deleted along with the tables they map to
(the tables disappear when Release B deletes each environment's database; no migration drops them).

## Server (per request, never stored)

### ChatTurn (request item and model input)

| Field     | Type                          | Rules                                         |
| --------- | ----------------------------- | --------------------------------------------- |
| `role`    | `ChatRole`: `user` / `assistant` | Required; any other value, including a number, → 400 |
| `content` | string                        | Required, not blank, 1–8,000 characters (`ChatLimits.MaxHistoryTurnLength`) |

`ChatRole` moves from the deleted `ChatEntities.cs` to `IChatModel.cs`, next to `ChatTurn`.

### SendMessageRequest

| Field     | Type          | Rules                                                              |
| --------- | ------------- | ------------------------------------------------------------------ |
| `message` | string        | Required, not blank, 1–4,000 characters (`ChatLimits.MaxMessageLength`); trimmed |
| `history` | `ChatTurn[]?` | Optional (missing/null = empty); at most 20 items (`ChatLimits.MaxHistoryTurns`); oldest first |

Any other JSON property (for example `conversationId` from an old bundle) is ignored.

### SendMessageResponse

| Field   | Type   | Notes                     |
| ------- | ------ | ------------------------- |
| `reply` | string | The assistant's reply text |

### Turns sent to the model

`history.TakeLast(Gemini:MaxHistoryMessages - 1)` followed by `{ role: user, content: message }`.
Nothing is written anywhere; a model failure returns 502 and leaves no trace (Principle IV).

## Browser (`localStorage`)

### Stored chat — key `chat.messages`

JSON array, oldest first, at most `MAX_STORED_MESSAGES = 100` items:

| Field     | Type                      | Notes                                                |
| --------- | ------------------------- | ---------------------------------------------------- |
| `id`      | string                    | Client-generated, unique within the chat (React key) |
| `role`    | `'user'` \| `'assistant'` |                                                      |
| `content` | string                    | As shown in the chat                                 |

### Lifecycle

```text
(empty) ──send ok──► [turns…] ──send ok──► [turns…, user, assistant]   (written after each successful reply)
   ▲                     │
   └──── "New chat" ─────┘   (key removed)
send fails → nothing written; optimistic message rolled back; draft restored
load → read + validate; invalid/unreadable → key removed, empty chat
load → legacy key `chat.conversationId` removed (one-time migration from the previous version)
```

### Request derived from the stored chat

`history` = the last `MAX_HISTORY_TURNS = 20` stored messages, each `content` truncated to
`MAX_HISTORY_TURN_LENGTH = 8000` characters, mapped to `{ role, content }` (ids dropped).

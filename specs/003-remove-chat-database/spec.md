# Feature Specification: Stateless Chat (Remove the Database)

**Feature Branch**: `003-remove-chat-database`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "we will not save the AI chat to sqldb, only chatting, so we need to remove all databases related on code, on Azure"

## Clarifications

### Session 2026-10-16

- Q: After a reload, is the chat empty, kept for the tab, or kept in the browser? → A: Kept in the
  browser's persistent storage until "New chat" (survives closing the browser).
- Q: Are conversations already stored in Azure exported first or deleted outright? → A: Deleted with
  the databases; no export or backup.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Chat with the assistant without anything being saved (Priority: P1)

A visitor opens the app, types a message, and gets a reply from the assistant. They can keep asking
follow-up questions and the assistant answers with the earlier turns of the same chat in mind. Nothing
the visitor or the assistant writes is stored by the application on the server.

**Why this priority**: Chatting is the product. The point of this feature is that chatting keeps working
exactly as before from the visitor's point of view while the application stops keeping conversations.

**Independent Test**: Send a message, then a follow-up that only makes sense with the first message as
context; both get replies. Confirm the server keeps no record of either message.

**Acceptance Scenarios**:

1. **Given** an empty chat, **When** the visitor sends a message, **Then** their message and the
   assistant's reply appear in the chat.
2. **Given** a chat with earlier turns, **When** the visitor sends a follow-up, **Then** the assistant
   receives the earlier turns of this chat as context (up to the existing history limit) along with the
   new message.
3. **Given** the assistant is unavailable or fails, **When** the visitor sends a message, **Then** they
   see an error, their draft is restored so they can retry, and the failed message is not added to the
   chat.
4. **Given** a message that is empty or longer than the allowed length, **When** the visitor tries to
   send it, **Then** it is rejected with a clear message, as today.
5. **Given** a chat in progress, **When** the visitor chooses "New chat", **Then** the chat is cleared
   and the next message starts without earlier context.

---

### User Story 2 - Chat behavior after a page reload (Priority: P2)

A visitor who reloads or reopens the page gets a predictable result, because the server no longer
holds their conversation.

**Why this priority**: Today a reload restores the previous conversation from the server. That behavior
cannot survive as-is, so the new behavior has to be defined and tested.

**Independent Test**: Chat, reload the page, and check that the chat matches the chosen reload behavior.

**Acceptance Scenarios**:

1. **Given** a chat with messages, **When** the visitor reloads the page or reopens the browser,
   **Then** the same chat is shown, read from the visitor's own browser storage, and a follow-up is
   answered with that chat as context.
2. **Given** a restored chat, **When** the visitor chooses "New chat", **Then** the chat is cleared
   from the screen and from the browser, and a reload shows an empty chat.
3. **Given** a browser that still holds a conversation reference from the previous version of the app,
   **When** the visitor opens the new version, **Then** the app starts without an error and the leftover
   reference is discarded.

---

### User Story 3 - Operators run the app with no database anywhere (Priority: P2)

Developers, CI, and the deployed environments (develop, stage, production) run the app without any
database. Database servers, databases, credentials, firewall rules, migration steps, and
database-specific scripts are retired, so they no longer cost money, need maintenance, or hold
conversation data.

**Why this priority**: Removing the database from the code alone would leave paid, unused Azure
resources holding old conversations. Removing infrastructure has to follow the code change, because a
running older version still depends on the database until the new version is live.

**Independent Test**: Start the local stack with no database settings and chat end to end; run the CI
pipeline and a deploy to develop with no database step; list the Azure resources and find no SQL server
or database for the app.

**Acceptance Scenarios**:

1. **Given** a fresh clone with no database settings, **When** a developer starts the local stack,
   **Then** the app starts, reports healthy, and chats end to end.
2. **Given** a pull request, **When** CI runs, **Then** no database is created, migrated, or dropped and
   every check passes.
3. **Given** a merge to a deployed branch, **When** the deployment runs, **Then** there is no migration
   step, the new version becomes healthy, and the post-deploy smoke test passes.
4. **Given** the new version is live in an environment, **When** the infrastructure clean-up for that
   environment is applied, **Then** that environment's SQL server, database, and database-only
   identities, roles, and secrets are deleted, and the app keeps working.
5. **Given** all environments run the new version, **When** the shared infrastructure clean-up is
   applied, **Then** the shared nonprod SQL server, developer databases, leftover CI databases, and their
   credentials are deleted.
6. **Given** existing stored conversations in any environment, **When** the clean-up runs, **Then**
   they are deleted together with their databases, with no export or backup.

---

### Edge Cases

- A deploy is rolled back to a version that still needs the database after the database has been
  deleted: that version cannot run. Infrastructure removal therefore happens only after the new version
  is live and accepted in that environment, and rollback beyond that point is explicitly unsupported.
- A visitor sends a very long chat: only the most recent turns, up to the existing history limit, are
  used as context; the total size of what a visitor can send in one request is bounded.
- A client sends forged or malformed earlier turns (wrong roles, empty or oversized content): the
  request is rejected with a validation error; nothing is trusted beyond the request itself.
- Two tabs open at once: both read the same saved chat on load; the tab that sends last overwrites
  the saved chat. Keeping tabs in sync live is out of scope.
- Browser storage is unavailable, full, or holds data that cannot be read: chatting still works, the
  chat just isn't kept across reloads, and unreadable saved data is discarded without an error.
- A long-running chat: the browser keeps a bounded number of the most recent turns so storage cannot
  grow without limit.
- Health checks and the post-deploy smoke test no longer depend on the database; they must not report
  healthy when the app itself is broken.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST NOT store chat messages, replies, or conversations on the server in any
  form (database, file, or cache that outlives the request).
- **FR-002**: Visitors MUST be able to send a message and receive a reply, with the same length limit,
  validation, error display, and draft-restore behavior as today.
- **FR-003**: The assistant MUST receive the earlier turns of the current chat as context, capped at the
  existing history limit, so follow-up questions work.
- **FR-004**: The system MUST validate every earlier turn sent with a request (allowed roles, non-empty,
  a per-turn length limit, maximum number of turns) and reject invalid requests with a clear error.
- **FR-005**: "New chat" MUST clear the current chat so the next message has no earlier context.
- **FR-006**: The current chat MUST be kept in the visitor's browser storage so it survives reloads and
  browser restarts until the visitor chooses "New chat"; a leftover conversation reference from the
  previous version MUST be removed without an error.
- **FR-007**: The endpoints that list and fetch stored conversations MUST be removed; this is a breaking
  change to the chat contract and frontend and backend MUST change together.
- **FR-008**: The application MUST start and report healthy with no database configuration in every
  environment (local, CI, develop, stage, production).
- **FR-009**: The deployment pipeline MUST NOT contain a database migration step, and CI MUST NOT create
  or use databases.
- **FR-010**: All Azure database resources for the app MUST be removed: each environment's SQL server
  and database, the shared nonprod SQL server with developer and CI databases, and anything that exists
  only to support them (migration job and image, database identities and role assignments, database
  credentials and secrets, firewall rules, clean-up workflows and scripts).
- **FR-011**: Infrastructure removal for an environment MUST happen only after the database-free
  version is live and healthy in that environment.
- **FR-012**: Existing stored conversations MUST be deleted together with their databases; no export or
  backup is kept.
- **FR-013**: Project rules and documentation (constitution, contributor guides, architecture,
  deployment guide, backlog, workflow skills) MUST no longer require or describe a database.

### Key Entities

- **Chat turn**: one message in the current chat, either from the visitor or from the assistant, with
  its text. Lives only in the visitor's browser and in a single request to the server.
- **Chat**: the ordered list of turns the visitor sees; starts empty and is cleared by "New chat".
  Kept in the visitor's browser storage (bounded to the most recent turns), never on the server.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Visitors can send a message and get a reply in every environment, and a follow-up that
  refers to the previous turn is answered in context, verified by automated end-to-end tests.
- **SC-002**: After a chat, the server holds zero records of it.
- **SC-003**: Once clean-up is complete, the app has zero SQL servers and zero databases in Azure, and
  the monthly cost attributable to databases is zero.
- **SC-004**: A new developer can run the full stack and its tests without any database access, and
  without network access to Azure apart from the optional AI provider.
- **SC-005**: CI and deployment pipelines finish with no database steps, and a deploy is not slower than
  before the change.

## Assumptions

- The app has no user accounts, so there is no requirement to keep chat history per person; the backlog
  items "Conversation sidebar", "per-user conversations", "SQL private endpoints", and "per-developer
  contained users on nonprod SQL" are dropped or rewritten.
- The existing history limit for context and the 4,000-character message limit stay the same.
- Chat text still goes to the AI provider (Gemini) to produce replies; "not saved" refers to this
  application's storage, not to the provider's own policies.
- Terraform state storage, the container registry, each environment's Key Vault (still needed for the
  Gemini key), Log Analytics, and the Container Apps environments stay. The shared nonprod Key Vault
  holds only the SQL admin password, so it is removed with the nonprod server.
- The order is: ship the database-free version to every environment first; only then merge the change
  that deletes database infrastructure. That change removes the shared nonprod server when it reaches
  develop and each environment's database when it reaches that environment. Deletions go through the
  reviewed Terraform change and the deploy workflow (stage and production need approval; the develop
  and shared plans are reviewed before merging because they apply without approval).
- Rollback to a pre-change version is not supported once that environment's database is deleted.
- A chat kept in browser storage stays on that device until "New chat" is chosen or the visitor clears
  site data; this is acceptable because the app has no accounts and the chat is not stored anywhere
  else.

---
name: db-migration
description: Add, review, and apply an EF Core migration for the SQL Server database in this repo. Use whenever an entity, entity configuration, or DbContext changes.
argument-hint: <MigrationName in PascalCase>
---

# EF Core migration workflow

Migration name: **$ARGUMENTS** (PascalCase, describes the change, e.g. `AddConversationArchivedFlag`).

All commands run from `backend/`.

1. **Check the model change compiles**: `dotnet build`.
2. **Create**:
   `dotnet ef migrations add $ARGUMENTS --project src/MisaApp.Api --output-dir Data/Migrations`
3. **Review the generated code** (`Data/Migrations/*_$ARGUMENTS.cs`) and flag:
   - Dropped columns/tables or type narrowing → data loss. Propose a safer sequence (add → backfill → switch → drop) if there's existing data.
   - New non-nullable columns on existing tables without a default.
   - Missing indexes for new foreign keys or new query filters.
   - Renames that EF generated as drop+add (fix with `RenameColumn`).
4. **Review the SQL**:
   `dotnet ef migrations script --idempotent --project src/MisaApp.Api -o ../docs/migrations-preview.sql` — summarize it, then delete the file (don't commit it).
5. **Apply**:
   - Docker: `docker compose restart backend` (migrations run at startup), then check `docker compose logs backend | grep -i migration`.
   - Local: `dotnet ef database update --project src/MisaApp.Api`.
6. **Test**: `dotnet test`. Integration tests use SQLite `EnsureCreated`, so also exercise the change against SQL Server via the Docker stack (E2E or a manual call).

Rules:
- Never edit a migration that has been applied anywhere shared. Add a new one.
- To undo the latest unapplied migration: `dotnet ef migrations remove --project src/MisaApp.Api`.

---
name: db-migration
description: Add, review, and apply an EF Core migration for the Azure SQL database in this repo. Use whenever an entity, entity configuration, or DbContext changes.
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
   - **Backward compatibility** (required): the previous release keeps serving while the migrate job runs, and a rollback keeps the new schema. The previous code must still work against the new schema. Drops, renames, type changes and `NOT NULL` without a default are not allowed in one step: split them expand → (release) → contract, and say which release does the contract step.
4. **Review the SQL**:
   `dotnet ef migrations script --idempotent --project src/MisaApp.Api -o ../docs/migrations-preview.sql` — summarize it, then delete the file (don't commit it).
5. **Apply**:
   - Docker: `docker compose restart backend` (migrations run at startup against your Azure SQL dev database from `SQL_CONNECTION_STRING`), then check `docker compose logs backend | grep -i migration`.
   - Local: `dotnet ef database update --project src/MisaApp.Api` (uses `ConnectionStrings:Default` from user-secrets).
   - Azure: nothing to do. After merge, `deploy.yml` runs the `migrator` image as the migrate job before the new revision starts.
6. **Test**: `dotnet test`. Integration tests use SQLite `EnsureCreated`, so also exercise the change against your Azure SQL dev database via the Docker stack (E2E or a manual call).

Rules:
- Never edit a migration that has been applied anywhere shared. Add a new one.
- To undo the latest unapplied migration: `dotnet ef migrations remove --project src/MisaApp.Api`.

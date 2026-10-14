# Backend guidance

- Project: `src/MisaApp.Api` (minimal APIs). Tests: `tests/MisaApp.Api.Tests` (xUnit v3, runs on Microsoft.Testing.Platform via `global.json`).
- Shared build settings live in `Directory.Build.props` (net10.0, nullable, implicit usings; warnings are errors in Release).
- **Endpoints**: one static `<Feature>Endpoints.MapXxxEndpoints()` per feature using `MapGroup("/api/<feature>")`, `TypedResults`, and `Results<...>` return types. Register services in `<Feature>ServiceCollectionExtensions.AddXxx()`. Keep handlers thin; logic lives in a scoped service.
- **Validation**: DataAnnotations on request records (`[property: Required]`), enforced by `builder.Services.AddValidation()`. Invalid input → 400 ProblemDetails automatically.
- **Errors**: Map expected failures to ProblemDetails with an explicit status (see `ChatModelException` → 502). Unhandled exceptions go through `UseExceptionHandler()`.
- **EF Core**: entity config via `IEntityTypeConfiguration<T>` next to the entity. Store times as UTC `DateTime` named `*Utc` (SQLite test provider can't order `DateTimeOffset`). Use `AsNoTracking()` + projection for reads. Inject `TimeProvider`, not `DateTime.UtcNow`.
- **Migrations**: `dotnet ef migrations add <Name> --project src/MisaApp.Api --output-dir Data/Migrations`. Review with `dotnet ef migrations script <Prev> <Name> --project src/MisaApp.Api`. Applied automatically on startup when `Database:MigrateOnStartup=true` (Development + Docker).
- **LLM access** goes through `IChatModel` only. `GeminiChatModel` is used when `Gemini:ApiKey` is set, otherwise `EchoChatModel`. Tests swap in `FakeChatModel` via `ApiFactory`.
- **Tests**: integration tests use `ApiFactory` (`WebApplicationFactory<Program>` + SQLite in-memory). Use `TestContext.Current.CancellationToken`. Name tests `Method_condition_expected`.
- Local secrets: `dotnet user-secrets set "Gemini:ApiKey" "<key>" --project src/MisaApp.Api`.

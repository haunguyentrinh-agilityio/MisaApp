using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage;
using MisaApp.Api.Data;
using MisaApp.Api.Features.Chat;
using MisaApp.Api.Features.Version;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
builder.Services.AddProblemDetails();
builder.Services.AddValidation();
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)));
builder.Services.AddSingleton(TimeProvider.System);

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(
        builder.Configuration.GetConnectionString("Default"),
        sql => sql.EnableRetryOnFailure()));

builder.Services.AddHealthChecks().AddDbContextCheck<AppDbContext>();
builder.Services.AddChat(builder.Configuration);
builder.Services.AddVersion(builder.Configuration);

var app = builder.Build();

if (app.Configuration.GetValue<bool>("Database:MigrateOnStartup"))
{
    await using var scope = app.Services.CreateAsyncScope();
    var database = scope.ServiceProvider.GetRequiredService<AppDbContext>().Database;
    // Migrate would create a missing database with the server's default, billed SKU. Terraform creates
    // developer databases and ci-database.sh creates CI ones, so a missing one is a setup mistake.
    if (!await database.GetService<IRelationalDatabaseCreator>().ExistsAsync())
    {
        throw new InvalidOperationException(
            $"Database '{database.GetDbConnection().Database}' does not exist. Developer databases are " +
            "created by the develop deploy (infra/shared); see docs/deployment.md.");
    }

    await database.MigrateAsync();
}

if (app.Services.GetRequiredService<IChatModel>() is EchoChatModel)
{
    app.Logger.LogWarning("Gemini:ApiKey is not configured; chat replies will be echoed back.");
}

app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapHealthChecks("/api/health");
app.MapChatEndpoints();
app.MapVersionEndpoints();

app.Run();

public partial class Program;

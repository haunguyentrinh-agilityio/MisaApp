using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using MisaApp.Api.Data;
using MisaApp.Api.Features.Chat;

namespace MisaApp.Api.Tests;

/// <summary>
/// Hosts the API in-memory against SQLite (no Docker needed) with a scriptable chat model.
/// SQL Server-specific behaviour is covered by the Playwright suite against the real stack.
/// </summary>
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    private readonly SqliteConnection _connection = new("DataSource=:memory:");

    public FakeChatModel ChatModel { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        _connection.Open();

        builder.UseEnvironment("Testing");
        builder.UseSetting("Database:MigrateOnStartup", "false");
        builder.UseSetting("Gemini:ApiKey", "");

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.RemoveAll<IDbContextOptionsConfiguration<AppDbContext>>();
            services.AddDbContext<AppDbContext>(options => options.UseSqlite(_connection));

            services.RemoveAll<IChatModel>();
            services.AddSingleton<IChatModel>(ChatModel);
        });
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        var host = base.CreateHost(builder);
        using var scope = host.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.EnsureCreated();
        return host;
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing)
        {
            _connection.Dispose();
        }
    }
}

public sealed class FakeChatModel : IChatModel
{
    public List<IReadOnlyList<ChatTurn>> Calls { get; } = [];
    public Func<IReadOnlyList<ChatTurn>, string> Reply { get; set; } = turns => $"reply to: {turns[^1].Content}";

    public Task<string> CompleteAsync(IReadOnlyList<ChatTurn> turns, CancellationToken cancellationToken)
    {
        Calls.Add(turns);
        return Task.FromResult(Reply(turns));
    }
}

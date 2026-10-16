using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using MisaApp.Api.Features.Chat;

namespace MisaApp.Api.Tests;

/// <summary>Hosts the API in-memory (no Docker needed) with a scriptable chat model.</summary>
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    public FakeChatModel ChatModel { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("Gemini:ApiKey", "");

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<IChatModel>();
            services.AddSingleton<IChatModel>(ChatModel);
        });
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

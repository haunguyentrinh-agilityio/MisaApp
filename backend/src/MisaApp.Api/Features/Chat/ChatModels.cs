using Google.GenAI;
using Google.GenAI.Types;
using Microsoft.Extensions.Options;

namespace MisaApp.Api.Features.Chat;

public sealed class GeminiOptions
{
    public const string SectionName = "Gemini";

    public string? ApiKey { get; set; }
    public string Model { get; set; } = "gemini-3.8-flash";
    public string? SystemInstruction { get; set; }
    public int MaxHistoryMessages { get; set; } = 20;
}

public sealed class GeminiChatModel(Client client, IOptions<GeminiOptions> options, ILogger<GeminiChatModel> logger)
    : IChatModel
{
    private readonly GeminiOptions _options = options.Value;

    public async Task<string> CompleteAsync(IReadOnlyList<ChatTurn> turns, CancellationToken cancellationToken)
    {
        var contents = turns
            .Select(t => new Content
            {
                Role = t.Role == ChatRole.User ? "user" : "model",
                Parts = [new Part { Text = t.Content }],
            })
            .ToList();

        var config = string.IsNullOrWhiteSpace(_options.SystemInstruction)
            ? null
            : new GenerateContentConfig
            {
                SystemInstruction = new Content { Parts = [new Part { Text = _options.SystemInstruction }] },
            };

        try
        {
            var response = await client.Models.GenerateContentAsync(_options.Model, contents, config, cancellationToken);
            return string.IsNullOrWhiteSpace(response.Text)
                ? throw new ChatModelException("The model returned an empty response.")
                : response.Text;
        }
        catch (Exception ex) when (ex is not (OperationCanceledException or ChatModelException))
        {
            logger.LogError(ex, "Gemini request to model {Model} failed", _options.Model);
            throw new ChatModelException("The chat model request failed.", ex);
        }
    }
}

/// <summary>Fallback used when no Gemini API key is configured (local dev, E2E tests).</summary>
public sealed class EchoChatModel : IChatModel
{
    public Task<string> CompleteAsync(IReadOnlyList<ChatTurn> turns, CancellationToken cancellationToken) =>
        Task.FromResult($"(echo) {turns[^1].Content}");
}

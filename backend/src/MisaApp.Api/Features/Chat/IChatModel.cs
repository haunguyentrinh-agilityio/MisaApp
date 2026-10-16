using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace MisaApp.Api.Features.Chat;

public enum ChatRole
{
    User,
    Assistant,
}

/// <summary>A single turn sent to the language model, oldest first. Also the request's history item.</summary>
public sealed record ChatTurn(
    // JsonRequired: a missing role would otherwise default to User.
    [property: JsonRequired] ChatRole Role,
    [property: Required, StringLength(ChatLimits.MaxHistoryTurnLength, MinimumLength = 1)] string Content);

/// <summary>
/// Abstraction over the LLM provider so the chat feature can be tested
/// (and run without an API key) independently of Google.GenAI.
/// </summary>
public interface IChatModel
{
    Task<string> CompleteAsync(IReadOnlyList<ChatTurn> turns, CancellationToken cancellationToken);
}

/// <summary>Raised when the upstream model call fails; mapped to 502 by the endpoint.</summary>
public sealed class ChatModelException(string message, Exception? innerException = null)
    : Exception(message, innerException);

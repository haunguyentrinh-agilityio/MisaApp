using System.ComponentModel.DataAnnotations;

namespace MisaApp.Api.Features.Chat;

/// <summary>A new message plus the recent turns of the visitor's chat, which only the browser keeps.</summary>
public sealed record SendMessageRequest(
    [property: Required, StringLength(ChatLimits.MaxMessageLength, MinimumLength = 1)] string Message,
    [property: MaxLength(ChatLimits.MaxHistoryTurns)] List<ChatTurn>? History);

public static class ChatLimits
{
    public const int MaxMessageLength = 4000;

    /// <summary>Earlier turns a request may carry; the model sees at most <c>Gemini:MaxHistoryMessages</c>.</summary>
    public const int MaxHistoryTurns = 20;

    /// <summary>Twice the message limit, because assistant replies run longer than user messages.</summary>
    public const int MaxHistoryTurnLength = 8000;
}

public sealed record SendMessageResponse(string Reply);

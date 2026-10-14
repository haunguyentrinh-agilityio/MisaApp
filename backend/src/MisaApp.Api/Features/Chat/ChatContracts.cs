using System.ComponentModel.DataAnnotations;

namespace MisaApp.Api.Features.Chat;

public sealed record SendMessageRequest(
    Guid? ConversationId,
    [property: Required, StringLength(ChatLimits.MaxMessageLength, MinimumLength = 1)] string Message);

public static class ChatLimits
{
    public const int MaxMessageLength = 4000;
}

public sealed record SendMessageResponse(Guid ConversationId, ChatMessageDto UserMessage, ChatMessageDto Reply);

public sealed record ChatMessageDto(long Id, ChatRole Role, string Content, DateTime CreatedAtUtc)
{
    public static ChatMessageDto From(ChatMessage m) => new(m.Id, m.Role, m.Content, m.CreatedAtUtc);
}

public sealed record ConversationDto(Guid Id, string Title, List<ChatMessageDto> Messages);

public sealed record ConversationSummaryDto(Guid Id, string Title, DateTime UpdatedAtUtc);

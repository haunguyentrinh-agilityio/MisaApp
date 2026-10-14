using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MisaApp.Api.Data;

namespace MisaApp.Api.Features.Chat;

public sealed class ChatService(
    AppDbContext db,
    IChatModel model,
    TimeProvider clock,
    IOptions<GeminiOptions> options)
{
    /// <returns>The exchange, or <c>null</c> when <paramref name="conversationId"/> does not exist.</returns>
    public async Task<SendMessageResponse?> SendAsync(
        Guid? conversationId, string message, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        Conversation conversation;
        List<ChatTurn> turns = [];

        if (conversationId is { } id)
        {
            var existing = await db.Conversations.FirstOrDefaultAsync(c => c.Id == id, cancellationToken);
            if (existing is null)
            {
                return null;
            }

            conversation = existing;
            var history = await db.ChatMessages
                .Where(m => m.ConversationId == id)
                .OrderByDescending(m => m.Id)
                .Take(Math.Max(options.Value.MaxHistoryMessages - 1, 0))
                .Select(m => new ChatTurn(m.Role, m.Content))
                .ToListAsync(cancellationToken);
            history.Reverse();
            turns.AddRange(history);
        }
        else
        {
            conversation = Conversation.Start(message, now);
            db.Conversations.Add(conversation);
        }

        turns.Add(new ChatTurn(ChatRole.User, message));

        // Only persist once the model has answered, so a failed call leaves no orphan user message.
        var reply = await model.CompleteAsync(turns, cancellationToken);

        var userMessage = new ChatMessage
        {
            ConversationId = conversation.Id, Role = ChatRole.User, Content = message, CreatedAtUtc = now,
        };
        var assistantMessage = new ChatMessage
        {
            ConversationId = conversation.Id,
            Role = ChatRole.Assistant,
            Content = reply,
            CreatedAtUtc = clock.GetUtcNow().UtcDateTime,
        };
        db.ChatMessages.AddRange(userMessage, assistantMessage);
        conversation.UpdatedAtUtc = assistantMessage.CreatedAtUtc;
        await db.SaveChangesAsync(cancellationToken);

        return new SendMessageResponse(
            conversation.Id, ChatMessageDto.From(userMessage), ChatMessageDto.From(assistantMessage));
    }

    public Task<ConversationDto?> GetConversationAsync(Guid id, CancellationToken cancellationToken) =>
        db.Conversations
            .AsNoTracking()
            .Where(c => c.Id == id)
            .Select(c => new ConversationDto(
                c.Id,
                c.Title,
                c.Messages
                    .OrderBy(m => m.Id)
                    .Select(m => new ChatMessageDto(m.Id, m.Role, m.Content, m.CreatedAtUtc))
                    .ToList()))
            .FirstOrDefaultAsync(cancellationToken);

    public Task<List<ConversationSummaryDto>> ListConversationsAsync(int take, CancellationToken cancellationToken) =>
        db.Conversations
            .AsNoTracking()
            .OrderByDescending(c => c.UpdatedAtUtc)
            .Take(take)
            .Select(c => new ConversationSummaryDto(c.Id, c.Title, c.UpdatedAtUtc))
            .ToListAsync(cancellationToken);
}

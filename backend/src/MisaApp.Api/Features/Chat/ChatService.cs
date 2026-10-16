using Microsoft.Extensions.Options;

namespace MisaApp.Api.Features.Chat;

/// <summary>Stateless: the browser sends the chat's history with every message and nothing is stored.</summary>
public sealed class ChatService(IChatModel model, IOptions<GeminiOptions> options)
{
    public async Task<SendMessageResponse> SendAsync(
        IReadOnlyList<ChatTurn> history, string message, CancellationToken cancellationToken)
    {
        List<ChatTurn> turns =
        [
            .. history.TakeLast(Math.Max(options.Value.MaxHistoryMessages - 1, 0)),
            new ChatTurn(ChatRole.User, message),
        ];

        var reply = await model.CompleteAsync(turns, cancellationToken);
        return new SendMessageResponse(reply);
    }
}

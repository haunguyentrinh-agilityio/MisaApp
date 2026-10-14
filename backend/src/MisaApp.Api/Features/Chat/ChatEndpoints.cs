using Microsoft.AspNetCore.Http.HttpResults;

namespace MisaApp.Api.Features.Chat;

public static class ChatEndpoints
{
    public static IEndpointRouteBuilder MapChatEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/chat").WithTags("Chat");

        group.MapPost("/messages", SendMessage).WithName("SendChatMessage");
        group.MapGet("/conversations", ListConversations).WithName("ListConversations");
        group.MapGet("/conversations/{id:guid}", GetConversation).WithName("GetConversation");

        return app;
    }

    private static async Task<Results<Ok<SendMessageResponse>, NotFound, ProblemHttpResult>> SendMessage(
        SendMessageRequest request, ChatService chat, CancellationToken cancellationToken)
    {
        try
        {
            var response = await chat.SendAsync(request.ConversationId, request.Message.Trim(), cancellationToken);
            return response is null ? TypedResults.NotFound() : TypedResults.Ok(response);
        }
        catch (ChatModelException ex)
        {
            return TypedResults.Problem(
                title: "Chat model unavailable", detail: ex.Message, statusCode: StatusCodes.Status502BadGateway);
        }
    }

    private static async Task<Ok<List<ConversationSummaryDto>>> ListConversations(
        ChatService chat, CancellationToken cancellationToken, int take = 50) =>
        TypedResults.Ok(await chat.ListConversationsAsync(Math.Clamp(take, 1, 200), cancellationToken));

    private static async Task<Results<Ok<ConversationDto>, NotFound>> GetConversation(
        Guid id, ChatService chat, CancellationToken cancellationToken) =>
        await chat.GetConversationAsync(id, cancellationToken) is { } conversation
            ? TypedResults.Ok(conversation)
            : TypedResults.NotFound();
}

using Microsoft.AspNetCore.Http.HttpResults;

namespace MisaApp.Api.Features.Chat;

public static class ChatEndpoints
{
    public static IEndpointRouteBuilder MapChatEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/chat").WithTags("Chat");

        group.MapPost("/messages", SendMessage).WithName("SendChatMessage");

        return app;
    }

    private static async Task<Results<Ok<SendMessageResponse>, ProblemHttpResult>> SendMessage(
        SendMessageRequest request, ChatService chat, CancellationToken cancellationToken)
    {
        try
        {
            var response = await chat.SendAsync(request.History ?? [], request.Message.Trim(), cancellationToken);
            return TypedResults.Ok(response);
        }
        catch (ChatModelException ex)
        {
            return TypedResults.Problem(
                title: "Chat model unavailable", detail: ex.Message, statusCode: StatusCodes.Status502BadGateway);
        }
    }
}

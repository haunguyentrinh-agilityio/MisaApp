using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using MisaApp.Api.Features.Chat;

namespace MisaApp.Api.Tests.Features.Chat;

public sealed class ChatEndpointsTests : IClassFixture<ApiFactory>
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private readonly ApiFactory _factory;
    private readonly HttpClient _client;

    public ChatEndpointsTests(ApiFactory factory)
    {
        _factory = factory;
        _factory.ChatModel.Reply = turns => $"reply to: {turns[^1].Content}";
        _client = factory.CreateClient();
    }

    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task SendMessage_without_conversation_starts_a_new_one()
    {
        var response = await _client.PostAsJsonAsync(
            "/api/chat/messages", new { message = "Hello there" }, Json, Ct);

        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<SendMessageResponse>(Json, Ct);
        Assert.NotNull(body);
        Assert.NotEqual(Guid.Empty, body.ConversationId);
        Assert.Equal(ChatRole.User, body.UserMessage.Role);
        Assert.Equal("Hello there", body.UserMessage.Content);
        Assert.Equal(ChatRole.Assistant, body.Reply.Role);
        Assert.Equal("reply to: Hello there", body.Reply.Content);
    }

    [Fact]
    public async Task SendMessage_to_existing_conversation_sends_history_to_model()
    {
        var first = await SendAsync(null, "first question");

        _factory.ChatModel.Calls.Clear();
        await SendAsync(first.ConversationId, "follow-up");

        var turns = Assert.Single(_factory.ChatModel.Calls);
        Assert.Equal(
            [
                new ChatTurn(ChatRole.User, "first question"),
                new ChatTurn(ChatRole.Assistant, "reply to: first question"),
                new ChatTurn(ChatRole.User, "follow-up"),
            ],
            turns);
    }

    [Fact]
    public async Task GetConversation_returns_messages_in_order()
    {
        var first = await SendAsync(null, "one");
        await SendAsync(first.ConversationId, "two");

        var conversation = await _client.GetFromJsonAsync<ConversationDto>(
            $"/api/chat/conversations/{first.ConversationId}", Json, Ct);

        Assert.NotNull(conversation);
        Assert.Equal("one", conversation.Title);
        Assert.Equal(
            ["one", "reply to: one", "two", "reply to: two"],
            conversation.Messages.Select(m => m.Content));
    }

    [Fact]
    public async Task SendMessage_to_unknown_conversation_returns_404()
    {
        var response = await _client.PostAsJsonAsync(
            "/api/chat/messages", new { conversationId = Guid.NewGuid(), message = "hi" }, Json, Ct);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task SendMessage_with_blank_message_returns_400(string message)
    {
        var response = await _client.PostAsJsonAsync("/api/chat/messages", new { message }, Json, Ct);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SendMessage_over_max_length_returns_400()
    {
        var message = new string('x', ChatLimits.MaxMessageLength + 1);

        var response = await _client.PostAsJsonAsync("/api/chat/messages", new { message }, Json, Ct);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SendMessage_when_model_fails_returns_502_and_persists_nothing()
    {
        _factory.ChatModel.Reply = _ => throw new ChatModelException("boom");

        var response = await _client.PostAsJsonAsync(
            "/api/chat/messages", new { message = "will fail" }, Json, Ct);

        Assert.Equal(HttpStatusCode.BadGateway, response.StatusCode);
        var conversations = await _client.GetFromJsonAsync<List<ConversationSummaryDto>>(
            "/api/chat/conversations", Json, Ct);
        Assert.DoesNotContain(conversations!, c => c.Title == "will fail");
    }

    private async Task<SendMessageResponse> SendAsync(Guid? conversationId, string message)
    {
        var response = await _client.PostAsJsonAsync(
            "/api/chat/messages", new { conversationId, message }, Json, Ct);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<SendMessageResponse>(Json, Ct))!;
    }
}

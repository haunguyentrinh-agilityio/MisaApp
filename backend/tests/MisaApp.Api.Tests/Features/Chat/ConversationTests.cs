using MisaApp.Api.Features.Chat;

namespace MisaApp.Api.Tests.Features.Chat;

public sealed class ConversationTests
{
    private static readonly DateTime Now = new(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void Start_uses_first_message_as_title()
    {
        var conversation = Conversation.Start("  What is EF Core?\nThanks ", Now);

        Assert.Equal("What is EF Core? Thanks", conversation.Title);
        Assert.Equal(Now, conversation.CreatedAtUtc);
        Assert.Equal(Now, conversation.UpdatedAtUtc);
    }

    [Fact]
    public void Start_truncates_long_titles()
    {
        var conversation = Conversation.Start(new string('a', 500), Now);

        Assert.Equal(Conversation.TitleMaxLength, conversation.Title.Length);
        Assert.EndsWith("…", conversation.Title);
    }
}

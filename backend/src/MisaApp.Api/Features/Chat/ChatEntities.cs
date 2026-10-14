using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace MisaApp.Api.Features.Chat;

public enum ChatRole
{
    User,
    Assistant,
}

public sealed class Conversation
{
    public const int TitleMaxLength = 200;

    public Guid Id { get; init; }
    public required string Title { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public List<ChatMessage> Messages { get; init; } = [];

    public static Conversation Start(string firstMessage, DateTime nowUtc)
    {
        var title = firstMessage.Trim().ReplaceLineEndings(" ");
        if (title.Length > TitleMaxLength)
        {
            title = title[..(TitleMaxLength - 1)] + "…";
        }

        return new Conversation
        {
            Id = Guid.CreateVersion7(),
            Title = title,
            CreatedAtUtc = nowUtc,
            UpdatedAtUtc = nowUtc,
        };
    }
}

public sealed class ChatMessage
{
    // Identity key doubles as a stable ordering within a conversation.
    public long Id { get; init; }
    public Guid ConversationId { get; init; }
    public ChatRole Role { get; init; }
    public required string Content { get; init; }
    public DateTime CreatedAtUtc { get; init; }
}

internal sealed class ConversationConfiguration : IEntityTypeConfiguration<Conversation>
{
    public void Configure(EntityTypeBuilder<Conversation> builder)
    {
        builder.Property(c => c.Id).ValueGeneratedNever();
        builder.Property(c => c.Title).HasMaxLength(Conversation.TitleMaxLength);
        builder.HasIndex(c => c.UpdatedAtUtc);
        builder.HasMany(c => c.Messages)
            .WithOne()
            .HasForeignKey(m => m.ConversationId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

internal sealed class ChatMessageConfiguration : IEntityTypeConfiguration<ChatMessage>
{
    public void Configure(EntityTypeBuilder<ChatMessage> builder)
    {
        builder.Property(m => m.Role).HasConversion<string>().HasMaxLength(16);
    }
}

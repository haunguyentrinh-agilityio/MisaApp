using Google.GenAI;

namespace MisaApp.Api.Features.Chat;

public static class ChatServiceCollectionExtensions
{
    public static IServiceCollection AddChat(this IServiceCollection services, IConfiguration configuration)
    {
        var section = configuration.GetSection(GeminiOptions.SectionName);
        services.Configure<GeminiOptions>(section);
        services.AddScoped<ChatService>();

        var apiKey = section.Get<GeminiOptions>()?.ApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            services.AddSingleton<IChatModel, EchoChatModel>();
        }
        else
        {
            services.AddSingleton(_ => new Client(apiKey: apiKey));
            services.AddSingleton<IChatModel, GeminiChatModel>();
        }

        return services;
    }
}

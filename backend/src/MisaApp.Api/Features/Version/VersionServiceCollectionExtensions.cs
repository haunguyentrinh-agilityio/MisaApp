namespace MisaApp.Api.Features.Version;

public static class VersionServiceCollectionExtensions
{
    public static IServiceCollection AddVersion(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<AppInfoOptions>(configuration.GetSection(AppInfoOptions.SectionName));
        return services;
    }
}
